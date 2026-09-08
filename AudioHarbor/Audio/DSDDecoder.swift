import Foundation

/// DSF (and light DFF) probe + streamed DoP / PCM — never loads the whole bitstream twice.
enum DSDDecoder {
    struct Header: Equatable, Sendable {
        var sampleRate: Int
        var channelCount: Int
        var bitsPerSample: Int // 1 = LSB first, 8 = MSB first (DSF)
        var blockSizePerChannel: Int
        var sampleCountPerChannel: UInt64
        var dataOffset: Int
        var dataSize: Int
        var format: AudioFormat

        var duration: TimeInterval {
            guard sampleRate > 0 else { return 0 }
            return Double(sampleCountPerChannel) / Double(sampleRate)
        }

        var dopSampleRate: Int {
            sampleRate / 16
        }
    }

    struct DecodedPCM: Sendable {
        var sampleRate: Double
        var channelCount: Int
        var frames: Int
        var packed24: Data
        var isDoP: Bool
        var sourceSampleRate: Int
    }

    static func probe(url: URL) throws -> Header {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try parseHeader(data)
    }

    static func decode(url: URL, strategy: DSDStrategy) throws -> DecodedPCM {
        let source = try DSDStreamSource(url: url, strategy: strategy)
        return try source.materialize()
    }

    static func stream(url: URL, strategy: DSDStrategy) throws -> DSDStreamSource {
        try DSDStreamSource(url: url, strategy: strategy)
    }

    // MARK: - Header

    static func parseHeader(_ data: Data) throws -> Header {
        guard data.count >= 4 else { throw DSDError.truncated }
        let magic = data.prefix(4)
        if magic == Data("DSD ".utf8) {
            return try parseDSF(data)
        }
        if magic == Data("FRM8".utf8) {
            return try parseDFF(data)
        }
        throw DSDError.unsupportedContainer
    }

    private static func parseDSF(_ data: Data) throws -> Header {
        var c = Cursor(data)
        try c.expect("DSD ")
        _ = try c.u64le() // chunk size
        _ = try c.u64le() // file size
        _ = try c.u64le() // id3 offset

        try c.expect("fmt ")
        _ = try c.u64le()
        _ = try c.u32le() // version
        _ = try c.u32le() // format id
        _ = try c.u32le() // channel type
        let channelCount = Int(try c.u32le())
        let sampleRate = Int(try c.u32le())
        let bitsPerSample = Int(try c.u32le())
        let sampleCount = try c.u64le()
        let blockSize = Int(try c.u32le())
        _ = try c.u32le() // reserved

        try c.expect("data")
        let dataChunkSize = try c.u64le()
        let dataOffset = c.offset
        let dataSize = max(0, Int(dataChunkSize) - 12)

        return Header(
            sampleRate: sampleRate,
            channelCount: max(1, channelCount),
            bitsPerSample: bitsPerSample,
            blockSizePerChannel: max(1, blockSize),
            sampleCountPerChannel: sampleCount,
            dataOffset: dataOffset,
            dataSize: dataSize,
            format: .dsf
        )
    }

    private static func parseDFF(_ data: Data) throws -> Header {
        var c = Cursor(data)
        try c.expect("FRM8")
        _ = try c.u64be()
        try c.expect("DSD ")

        var sampleRate = 2_822_400
        var channelCount = 2
        var sampleCount: UInt64 = 0
        var dataOffset = 0
        var dataSize = 0

        while c.remaining >= 12 {
            let id = try c.fourCC()
            let chunkSize = Int(try c.u64be())
            let payloadStart = c.offset
            guard payloadStart + chunkSize <= data.count else { break }

            if id == "PROP" {
                let propEnd = payloadStart + chunkSize
                _ = try? c.fourCC()
                while c.offset + 12 <= propEnd {
                    let subID = try c.fourCC()
                    let subSize = Int(try c.u64be())
                    let subStart = c.offset
                    if subID == "FS  ", subSize >= 4 {
                        sampleRate = Int(try c.u32be())
                    } else if subID == "CHNL", subSize >= 2 {
                        channelCount = Int(try c.u16be())
                    }
                    c.offset = min(data.count, subStart + subSize + (subSize % 2))
                }
                c.offset = min(data.count, propEnd + (chunkSize % 2))
            } else if id == "DSD " {
                dataOffset = payloadStart
                dataSize = chunkSize
                if channelCount > 0 {
                    sampleCount = UInt64(dataSize * 8 / channelCount)
                }
                break
            } else {
                c.offset = min(data.count, payloadStart + chunkSize + (chunkSize % 2))
            }
        }

        guard dataSize > 0 else { throw DSDError.badDataChunk }
        return Header(
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitsPerSample: 8,
            blockSizePerChannel: 1,
            sampleCountPerChannel: sampleCount,
            dataOffset: dataOffset,
            dataSize: dataSize,
            format: .dff
        )
    }
}

/// Two cascaded RBJ biquads = 4th-order Butterworth. Cheap enough for real-time DSD.
private struct BiquadCoeffs {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double

    static func lowpass(fc: Double, fs: Double, q: Double) -> BiquadCoeffs {
        let w0 = 2 * Double.pi * fc / max(fs, 1)
        let cosw = cos(w0)
        let sinw = sin(w0)
        let alpha = sinw / (2 * max(q, 0.05))
        let b0 = (1 - cosw) / 2
        let b1 = 1 - cosw
        let b2 = (1 - cosw) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosw
        let a2 = 1 - alpha
        return BiquadCoeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }
}

private struct DSDLowpass {
    private let c1: BiquadCoeffs
    private let c2: BiquadCoeffs
    private var z11 = 0.0
    private var z12 = 0.0
    private var z21 = 0.0
    private var z22 = 0.0

    init(section1: BiquadCoeffs, section2: BiquadCoeffs) {
        c1 = section1
        c2 = section2
    }

    mutating func reset() {
        z11 = 0
        z12 = 0
        z21 = 0
        z22 = 0
    }

    mutating func process(_ x: Double) -> Double {
        let y1 = c1.b0 * x + z11
        z11 = c1.b1 * x - c1.a1 * y1 + z12
        z12 = c1.b2 * x - c1.a2 * y1
        let y2 = c2.b0 * y1 + z21
        z21 = c2.b1 * y1 - c2.a1 * y2 + z22
        z22 = c2.b2 * y1 - c2.a2 * y2
        return y2
    }
}

/// Memory-mapped DSF bitstream. Encodes DoP / PCM a render quantum at a time.
final class DSDStreamSource: @unchecked Sendable {
    let header: DSDDecoder.Header
    let isDoP: Bool
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int
    let sourceSampleRate: Int

    /// Kept so `bytes` stays valid for the source lifetime (mmap / NSData).
    private let map: NSData
    private let bytes: UnsafePointer<UInt8>
    private let byteCount: Int
    private let lsbFirst: Bool
    private let block: Int
    private let dataEnd: Int
    /// DSD bytes packed into one PCM/DoP frame (2 = 16 DSD bits = standard DoP).
    private let bytesPerPCM: Int
    private let bitsPerFrame: Int
    private let totalBits: UInt64
    private let lock = NSLock()
    private var filters: [DSDLowpass]
    private var nextBit: Int

    init(url: URL, strategy: DSDStrategy) throws {
        let map = try NSData(contentsOf: url, options: [.mappedIfSafe])
        let header = try DSDDecoder.parseHeader(Data(referencing: map))
        guard header.format == .dsf else { throw DSDError.dffPlaybackNotReady }
        guard map.length > 0 else { throw DSDError.truncated }

        let preferDoP: Bool = {
            switch strategy {
            case .preferDoP: true
            case .convertToPCM: false
            }
        }()

        let bytesPerPCM: Int = {
            if preferDoP { return 2 }
            var width = 2
            while width < 64, header.sampleRate / (width * 8) > 96_000 {
                width *= 2
            }
            return width
        }()

        self.map = map
        self.header = header
        self.isDoP = preferDoP
        self.lsbFirst = header.bitsPerSample == 1
        self.block = max(1, header.blockSizePerChannel)
        self.channelCount = header.channelCount
        self.sourceSampleRate = header.sampleRate
        self.bytesPerPCM = bytesPerPCM
        self.dataEnd = min(map.length, header.dataOffset + header.dataSize)
        self.byteCount = map.length
        self.bytes = map.bytes.assumingMemoryBound(to: UInt8.self)
        let bitsPerFrame = bytesPerPCM * 8
        guard bitsPerFrame > 0, header.sampleCountPerChannel > 0 else { throw DSDError.truncated }
        self.bitsPerFrame = bitsPerFrame
        self.totalBits = header.sampleCountPerChannel
        self.frameCount = Int(header.sampleCountPerChannel / UInt64(bitsPerFrame))
        self.sampleRate = Double(header.sampleRate / bitsPerFrame)
        self.nextBit = 0
        if preferDoP {
            self.filters = []
        } else {
            let fs = Double(header.sampleRate)
            let fc = min(20_000, Double(header.sampleRate / bitsPerFrame) * 0.40)
            let section1 = BiquadCoeffs.lowpass(fc: fc, fs: fs, q: 0.541196)
            let section2 = BiquadCoeffs.lowpass(fc: fc, fs: fs, q: 1.306563)
            self.filters = (0..<header.channelCount).map { _ in
                DSDLowpass(section1: section1, section2: section2)
            }
        }
        guard frameCount > 0, channelCount > 0, sampleRate > 0 else { throw DSDError.truncated }
    }

    var label: String {
        let mode = isDoP ? "DoP" : "DSD→PCM"
        return "\(mode) · \(Int(sampleRate)) Hz (src \(sourceSampleRate))"
    }

    func makeRenderBuffer() -> RenderBuffer {
        RenderBuffer(
            sampleRate: sampleRate,
            channelCount: channelCount,
            frameCount: frameCount,
            packed24: Data(),
            label: label,
            isDoP: isDoP
        )
    }

    /// Fill interleaved 24-bit LE samples. Audio-thread safe (read-only map).
    @discardableResult
    func copyPacked24(at startFrame: Int, count: Int, into dest: UnsafeMutableRawPointer) -> Int {
        let frames = min(count, max(0, frameCount - startFrame))
        guard frames > 0 else { return 0 }
        let src = bytes
        let channels = channelCount
        let out = dest.assumingMemoryBound(to: UInt8.self)
        if isDoP {
            var o = 0
            for frame in startFrame..<(startFrame + frames) {
                let byteIndex = frame * bytesPerPCM
                for ch in 0..<channels {
                    let payload = read16(src: src, channel: ch, byteIndex: byteIndex)
                    let marker: UInt8 = (frame & 1) == 0 ? 0x05 : 0xFA
                    out[o] = UInt8(payload & 0xFF)
                    out[o + 1] = UInt8((payload >> 8) & 0xFF)
                    out[o + 2] = marker
                    o += 3
                }
            }
            return frames
        }

        var o = 0
        return decodePCM(from: startFrame, count: frames) { _, _, sample in
            let v = Self.int24(from: sample)
            out[o] = UInt8(v & 0xFF)
            out[o + 1] = UInt8((v >> 8) & 0xFF)
            out[o + 2] = UInt8((v >> 16) & 0xFF)
            o += 3
        }
    }

    /// Interleaved float −1…1 for the Shared AVAudioEngine path.
    @discardableResult
    func copyFloatInterleaved(at startFrame: Int, count: Int, into dest: UnsafeMutablePointer<Float>) -> Int {
        let frames = min(count, max(0, frameCount - startFrame))
        guard frames > 0 else { return 0 }
        var o = 0
        return decodePCM(from: startFrame, count: frames) { _, _, sample in
            dest[o] = sample
            o += 1
        }
    }

    /// Non-interleaved float planes (AVAudioPCMBuffer.floatChannelData).
    @discardableResult
    func copyFloatPlanar(
        at startFrame: Int,
        count: Int,
        planes: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount destChannels: Int
    ) -> Int {
        let frames = min(count, max(0, frameCount - startFrame))
        guard frames > 0 else { return 0 }
        let channels = min(self.channelCount, destChannels)
        return decodePCM(from: startFrame, count: frames) { channel, frame, sample in
            guard channel < channels else { return }
            planes[channel][frame] = sample
        }
    }

    /// Only for tiny files / tests. Prefer streaming.
    func materialize() throws -> DSDDecoder.DecodedPCM {
        let packedBytes = frameCount * channelCount * 3
        var packed = Data(count: packedBytes)
        packed.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = copyPacked24(at: 0, count: frameCount, into: base)
        }
        return DSDDecoder.DecodedPCM(
            sampleRate: sampleRate,
            channelCount: channelCount,
            frames: frameCount,
            packed24: packed,
            isDoP: isDoP,
            sourceSampleRate: sourceSampleRate
        )
    }

    /// Sequential 4th-order Butterworth at the DSD rate, then keep every `bitsPerFrame` sample.
    @discardableResult
    private func decodePCM(
        from startFrame: Int,
        count: Int,
        emit: (_ channel: Int, _ frame: Int, _ sample: Float) -> Void
    ) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard !filters.isEmpty else { return 0 }

        let startBit = startFrame * bitsPerFrame
        if startBit != nextBit {
            preroll(to: startBit)
        }

        let src = bytes
        for frame in 0..<count {
            let base = nextBit
            for ch in 0..<channelCount {
                var y = 0.0
                var cachedByteIndex = Int.min
                var cachedByte: UInt8 = 0
                for i in 0..<bitsPerFrame {
                    let x = Double(signedBit(
                        src,
                        channel: ch,
                        bitIndex: base + i,
                        cachedByteIndex: &cachedByteIndex,
                        cachedByte: &cachedByte
                    ))
                    y = filters[ch].process(x)
                }
                emit(ch, frame, Float(max(-1, min(1, y))))
            }
            nextBit = base + bitsPerFrame
        }
        return count
    }

    private func preroll(to startBit: Int) {
        for i in filters.indices { filters[i].reset() }
        nextBit = 0
        guard startBit > 0 else { return }
        let prerollBits = min(startBit, bitsPerFrame * 48)
        let from = startBit - prerollBits
        let src = bytes
        var bit = from
        while bit < startBit {
            let take = min(bitsPerFrame, startBit - bit)
            for ch in 0..<channelCount {
                var cachedByteIndex = Int.min
                var cachedByte: UInt8 = 0
                for i in 0..<take {
                    let x = Double(signedBit(
                        src,
                        channel: ch,
                        bitIndex: bit + i,
                        cachedByteIndex: &cachedByteIndex,
                        cachedByte: &cachedByte
                    ))
                    _ = filters[ch].process(x)
                }
            }
            bit += take
        }
        nextBit = startBit
    }

    private func signedBit(
        _ src: UnsafePointer<UInt8>,
        channel: Int,
        bitIndex: Int,
        cachedByteIndex: inout Int,
        cachedByte: inout UInt8
    ) -> Float {
        if bitIndex < 0 || UInt64(bitIndex) >= totalBits { return 0 }
        let byteIndex = bitIndex >> 3
        if byteIndex != cachedByteIndex {
            cachedByteIndex = byteIndex
            cachedByte = byte(src, channel: channel, index: byteIndex)
        }
        let on: Bool
        if lsbFirst {
            on = ((cachedByte >> (bitIndex & 7)) & 1) != 0
        } else {
            on = ((cachedByte >> (7 - (bitIndex & 7))) & 1) != 0
        }
        return on ? 1 : -1
    }

    private static func int24(from sample: Float) -> Int32 {
        let v = Int32((sample * Float((1 << 23) - 1)).rounded())
        return max(min(v, (1 << 23) - 1), -(1 << 23))
    }

    private func read16(src: UnsafePointer<UInt8>, channel: Int, byteIndex: Int) -> UInt16 {
        let b0 = byte(src, channel: channel, index: byteIndex)
        let b1 = byte(src, channel: channel, index: byteIndex + 1)
        if lsbFirst {
            return UInt16(b0) | (UInt16(b1) << 8)
        }
        return UInt16(b0.bitReversed) | (UInt16(b1.bitReversed) << 8)
    }

    private func byte(_ src: UnsafePointer<UInt8>, channel: Int, index: Int) -> UInt8 {
        let blockIndex = index / block
        let offsetInBlock = index % block
        let pos = header.dataOffset + blockIndex * block * channelCount + channel * block + offsetInBlock
        guard pos < dataEnd, pos < byteCount else { return 0 }
        return src[pos]
    }
}

private struct Cursor {
    let data: Data
    var offset: Int = 0

    init(_ data: Data) { self.data = data }

    var remaining: Int { max(0, data.count - offset) }

    mutating func expect(_ four: String) throws {
        let got = try fourCC()
        guard got == four else { throw DSDError.badFormatChunk }
    }

    mutating func fourCC() throws -> String {
        let d = try take(4)
        return String(data: d, encoding: .ascii) ?? ""
    }

    mutating func take(_ n: Int) throws -> Data {
        guard offset + n <= data.count else { throw DSDError.truncated }
        let slice = data.subdata(in: offset..<(offset + n))
        offset += n
        return slice
    }

    mutating func u16be() throws -> UInt16 {
        let d = try take(2)
        return (UInt16(d[0]) << 8) | UInt16(d[1])
    }

    mutating func u32le() throws -> UInt32 {
        let d = try take(4)
        return UInt32(d[0]) | (UInt32(d[1]) << 8) | (UInt32(d[2]) << 16) | (UInt32(d[3]) << 24)
    }

    mutating func u32be() throws -> UInt32 {
        let d = try take(4)
        return (UInt32(d[0]) << 24) | (UInt32(d[1]) << 16) | (UInt32(d[2]) << 8) | UInt32(d[3])
    }

    mutating func u64le() throws -> UInt64 {
        let d = try take(8)
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(d[i]) << (8 * i) }
        return v
    }

    mutating func u64be() throws -> UInt64 {
        let d = try take(8)
        var v: UInt64 = 0
        for i in 0..<8 { v = (v << 8) | UInt64(d[i]) }
        return v
    }
}

private extension UInt8 {
    var bitReversed: UInt8 {
        var x = self
        x = ((x & 0xF0) >> 4) | ((x & 0x0F) << 4)
        x = ((x & 0xCC) >> 2) | ((x & 0x33) << 2)
        x = ((x & 0xAA) >> 1) | ((x & 0x55) << 1)
        return x
    }
}

enum DSDError: LocalizedError {
    case unsupportedContainer
    case badFormatChunk
    case badDataChunk
    case truncated
    case channelMismatch
    case dffPlaybackNotReady
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedContainer: "Unsupported DSD container"
        case .badFormatChunk: "Invalid DSF fmt chunk"
        case .badDataChunk: "Invalid DSD data chunk"
        case .truncated: "Truncated DSD file"
        case .channelMismatch: "DSD channel data mismatch"
        case .dffPlaybackNotReady: "DFF probe works; full DFF playback lands next. Use DSF for DoP now."
        case .tooLarge: "This DSD file is too large to decode in memory on this device."
        }
    }
}
