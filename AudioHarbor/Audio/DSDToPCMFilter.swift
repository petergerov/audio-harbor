import Foundation
import os

/// The DSD→PCM make-up gain, read by the decode threads on every render quantum.
enum DSDConversion {
    private static let state = OSAllocatedUnfairLock(initialState: DSDPCMLevel.default.linearGain)

    static var gain: Float {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

/// Linear-phase DSD→PCM decimation: one 8:1 FIR on the bitstream (byte lookup tables),
/// then 2:1 FIR stages down to the output rate. Every stage keeps the band that survives the
/// next fold-down free of DSD's ultrasonic noise; the last one is flat to `passband` and
/// fully closed (≥ `stopbandAttenuation` dB) at the output Nyquist, so nothing aliases.
final class DSDToPCMDesign: Sendable {
    /// Flat (ripple far below 0.001 dB) up to here.
    static let passband = 25_000.0
    static let stopbandAttenuation = 120.0
    /// Lookup row for a byte outside the clip: adds nothing, like digital silence.
    static let silentByte: UInt16 = 256

    let stage1Bytes: Int
    /// `stage1Bytes` rows of 257: row j, byte b → Σ ±tap over the 8 bits of b at window byte j.
    let stage1Table: [Float]
    /// Taps for each 2:1 stage, input side first.
    let halfStageTaps: [[Float]]
    /// Output frames that refill every stage after a reset.
    let settleFrames: Int

    /// `decimation` is DSD bits per PCM frame: 8 × a power of two, at least 16.
    init(dsdRate: Int, decimation: Int) {
        let dsdRate = Double(dsdRate)
        let outRate = dsdRate / Double(decimation)
        let halfStages = max(1, Int(log2(Double(decimation / 8)).rounded()))
        let passband = min(Self.passband, outRate * 0.3)
        // A stage may keep whatever later folds above the output Nyquist; the rest must go.
        func stopband(stageOutRate: Double) -> Double { stageOutRate - outRate / 2 }

        let stage1Rate = dsdRate / 8
        var stage1Taps = Self.kaiserLowpass(
            passband: passband,
            stopband: stopband(stageOutRate: stage1Rate),
            sampleRate: dsdRate
        )
        let stage1Bytes = (stage1Taps.count + 7) / 8
        if stage1Taps.count < stage1Bytes * 8 {
            stage1Taps = Self.kaiserLowpass(
                passband: passband,
                stopband: stopband(stageOutRate: stage1Rate),
                sampleRate: dsdRate,
                count: stage1Bytes * 8
            )
        }
        var table = [Float](repeating: 0, count: stage1Bytes * 257)
        for j in 0..<stage1Bytes {
            for b in 0..<256 {
                var sum = 0.0
                for i in 0..<8 {
                    // Bit 7 is the oldest DSD sample of the byte.
                    let on = (b >> (7 - i)) & 1 == 1
                    sum += on ? stage1Taps[j * 8 + i] : -stage1Taps[j * 8 + i]
                }
                table[j * 257 + b] = Float(sum)
            }
        }

        var halfTaps: [[Float]] = []
        var rate = stage1Rate
        for _ in 0..<halfStages {
            var taps = Self.kaiserLowpass(
                passband: passband,
                stopband: stopband(stageOutRate: rate / 2),
                sampleRate: rate
            )
            if taps.count.isMultiple(of: 2) {
                taps = Self.kaiserLowpass(
                    passband: passband,
                    stopband: stopband(stageOutRate: rate / 2),
                    sampleRate: rate,
                    count: taps.count + 1
                )
            }
            halfTaps.append(taps.map(Float.init))
            rate /= 2
        }

        var settle = (stage1Bytes * 8 + decimation - 1) / decimation
        for (index, taps) in halfTaps.enumerated() {
            let perOutput = 1 << (halfStages - index)
            settle += (taps.count + perOutput - 1) / perOutput
        }

        self.stage1Bytes = stage1Bytes
        self.stage1Table = table
        self.halfStageTaps = halfTaps
        self.settleFrames = settle + 1
    }

    /// Kaiser-windowed sinc, unity gain at DC. Length from Kaiser's estimate unless `count` is given.
    static func kaiserLowpass(
        passband: Double,
        stopband: Double,
        sampleRate: Double,
        count: Int? = nil
    ) -> [Double] {
        let attenuation = stopbandAttenuation
        let transition = max(stopband - passband, 1) / sampleRate
        let estimate = Int(((attenuation - 7.95) / (14.36 * transition)).rounded(.up)) + 1
        let n = max(3, count ?? estimate)
        let beta = 0.1102 * (attenuation - 8.7)
        let cutoff = (passband + stopband) / 2 / sampleRate
        let center = Double(n - 1) / 2
        let i0Beta = besselI0(beta)
        var taps = (0..<n).map { k -> Double in
            let t = Double(k) - center
            let sinc = t == 0 ? 2 * cutoff : sin(2 * Double.pi * cutoff * t) / (Double.pi * t)
            let r = t / center
            let window = besselI0(beta * (1 - r * r).squareRoot()) / i0Beta
            return sinc * window
        }
        let sum = taps.reduce(0, +)
        for k in taps.indices { taps[k] /= sum }
        return taps
    }

    private static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        let half = x / 2
        for k in 1..<64 {
            term *= (half / Double(k)) * (half / Double(k))
            sum += term
            if term < sum * 1e-17 { break }
        }
        return sum
    }
}

/// One channel's running state through a `DSDToPCMDesign`. Feed DSD bytes in time order.
struct DSDToPCMConverter {
    private let design: DSDToPCMDesign
    /// Last `stage1Bytes` bytes, stored twice so the window is always contiguous.
    private var bytes: [UInt16]
    private var byteWrite = 0
    private var stages: [HalfDecimator]

    init(design: DSDToPCMDesign) {
        self.design = design
        bytes = [UInt16](repeating: DSDToPCMDesign.silentByte, count: design.stage1Bytes * 2)
        stages = design.halfStageTaps.map(HalfDecimator.init)
    }

    mutating func reset() {
        for i in bytes.indices { bytes[i] = DSDToPCMDesign.silentByte }
        byteWrite = 0
        for i in stages.indices { stages[i].reset() }
    }

    /// `byte` holds the oldest DSD bit in bit 7, or `DSDToPCMDesign.silentByte`.
    /// Returns a PCM sample once every `decimation / 8` bytes.
    mutating func push(_ byte: UInt16) -> Float? {
        let length = design.stage1Bytes
        bytes[byteWrite] = byte
        bytes[byteWrite + length] = byte
        byteWrite = byteWrite + 1 == length ? 0 : byteWrite + 1

        var value: Float = 0
        let start = byteWrite
        design.stage1Table.withUnsafeBufferPointer { table in
            bytes.withUnsafeBufferPointer { window in
                for j in 0..<length {
                    value += table[j * 257 + Int(window[start + j])]
                }
            }
        }
        for i in stages.indices {
            guard let out = stages[i].push(value) else { return nil }
            value = out
        }
        return value
    }
}

/// 2:1 FIR decimator: keeps every second filtered sample.
private struct HalfDecimator {
    private let taps: [Float]
    /// History stored twice so the window is always contiguous.
    private var history: [Float]
    private var write = 0
    private var odd = false

    init(taps: [Float]) {
        self.taps = taps
        history = [Float](repeating: 0, count: taps.count * 2)
    }

    mutating func reset() {
        for i in history.indices { history[i] = 0 }
        write = 0
        odd = false
    }

    mutating func push(_ x: Float) -> Float? {
        let length = taps.count
        history[write] = x
        history[write + length] = x
        write = write + 1 == length ? 0 : write + 1
        odd.toggle()
        guard !odd else { return nil }

        // Symmetric taps, so oldest-first against tap order needs no reversal.
        var sum: Float = 0
        let start = write
        taps.withUnsafeBufferPointer { h in
            history.withUnsafeBufferPointer { x in
                for k in 0..<length {
                    sum += h[k] * x[start + k]
                }
            }
        }
        return sum
    }
}
