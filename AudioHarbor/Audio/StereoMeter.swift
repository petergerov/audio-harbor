import AVFoundation
import Foundation

/// Ballistics of the on-screen VU needles, applied once per UI tick.
enum VUNeedle {
    /// 0 VU ≈ −18 dBFS. Scale −20…+3 dB onto 0…1.
    static func position(forRMS rms: Float) -> Double {
        let db = 20.0 * log10(Double(max(rms, 1e-7)))
        return min(max((db + 20.0) / 23.0, 0), 1)
    }

    /// Extra mechanical inertia on the needle (~280 ms), same rise and fall.
    static func step(_ current: Double, toward target: Double, dt: Double = 0.05) -> Double {
        let alpha = 1 - exp(-dt / 0.28)
        return current + (target - current) * alpha
    }
}

/// Audio-thread-safe stereo RMS envelope. Analog VU: ~300 ms, not peak.
final class StereoMeterProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var vuLeft: Float = 0
    private var vuRight: Float = 0

    func ingest(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let channels = Int(buffer.format.channelCount)
        var sumL = 0.0
        var sumR = 0.0

        if let data = buffer.floatChannelData {
            for i in 0..<frames {
                let l = Double(data[0][i])
                sumL += l * l
                if channels > 1 {
                    let r = Double(data[1][i])
                    sumR += r * r
                }
            }
        } else if let data = buffer.int16ChannelData {
            for i in 0..<frames {
                let l = Double(data[0][i]) / 32768
                sumL += l * l
                if channels > 1 {
                    let r = Double(data[1][i]) / 32768
                    sumR += r * r
                }
            }
        } else {
            return
        }

        if channels < 2 { sumR = sumL }
        let n = Double(frames)
        let dt = n / max(buffer.format.sampleRate, 1)
        apply(rmsLeft: Float(sqrt(sumL / n)), rmsRight: Float(sqrt(sumR / n)), dt: dt)
    }

    func ingestPacked24(
        bytes: UnsafePointer<UInt8>,
        count: Int,
        frames: Int,
        channels: Int,
        byteOffset: Int,
        sampleRate: Double
    ) {
        guard frames > 0, channels > 0 else { return }
        var sumL = 0.0
        var sumR = 0.0
        for frame in 0..<frames {
            let base = byteOffset + frame * channels * 3
            let l = Double(Self.float24(bytes, base, count: count))
            sumL += l * l
            if channels > 1 {
                let r = Double(Self.float24(bytes, base + 3, count: count))
                sumR += r * r
            }
        }
        if channels < 2 { sumR = sumL }
        let n = Double(frames)
        apply(rmsLeft: Float(sqrt(sumL / n)), rmsRight: Float(sqrt(sumR / n)), dt: n / max(sampleRate, 1))
    }

    func takeEnvelope() -> (left: Float, right: Float) {
        lock.lock()
        defer { lock.unlock() }
        return (vuLeft, vuRight)
    }

    func reset() {
        lock.lock()
        vuLeft = 0
        vuRight = 0
        lock.unlock()
    }

    private func apply(rmsLeft: Float, rmsRight: Float, dt: Double) {
        let alpha = Float(1 - exp(-dt / 0.300))
        lock.lock()
        vuLeft += alpha * (rmsLeft - vuLeft)
        vuRight += alpha * (rmsRight - vuRight)
        lock.unlock()
    }

    private static func float24(_ bytes: UnsafePointer<UInt8>, _ offset: Int, count: Int) -> Float {
        guard offset + 2 < count else { return 0 }
        var v = Int32(bytes[offset]) | (Int32(bytes[offset + 1]) << 8) | (Int32(bytes[offset + 2]) << 16)
        if v & 0x800000 != 0 { v |= ~0xFFFFFF }
        return Float(v) / 8_388_608
    }
}
