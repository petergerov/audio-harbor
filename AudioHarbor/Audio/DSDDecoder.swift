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
        self.frameCount = Int(header.sampleCountPerChannel / UInt64(bitsPerFrame))
        self.sampleRate = Double(header.sampleRate / bitsPerFrame)
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
        var o = 0
        for frame in startFrame..<(startFrame + frames) {
            let byteIndex = frame * bytesPerPCM
            for ch in 0..<channels {
                if isDoP {
                    let payload = read16(src: src, channel: ch, byteIndex: byteIndex)
                    let marker: UInt8 = (frame & 1) == 0 ? 0x05 : 0xFA
                    out[o] = UInt8(payload & 0xFF)
                    out[o + 1] = UInt8((payload >> 8) & 0xFF)
                    out[o + 2] = marker
                } else {
                    let sample = pcmInt24(src: src, channel: ch, byteIndex: byteIndex)
                    out[o] = UInt8(sample & 0xFF)
                    out[o + 1] = UInt8((sample >> 8) & 0xFF)
                    out[o + 2] = UInt8((sample >> 16) & 0xFF)
                }
                o += 3
            }
        }
        return frames
    }

    /// Interleaved float −1…1 for the Shared AVAudioEngine path.
    @discardableResult
    func copyFloatInterleaved(at startFrame: Int, count: Int, into dest: UnsafeMutablePointer<Float>) -> Int {
        let frames = min(count, max(0, frameCount - startFrame))
        guard frames > 0 else { return 0 }
        let src = bytes
        var o = 0
        let scale = 1.0 / Double(bytesPerPCM * 8)
        for frame in startFrame..<(startFrame + frames) {
            let byteIndex = frame * bytesPerPCM
            for ch in 0..<channelCount {
                let acc = popcount(src: src, channel: ch, byteIndex: byteIndex)
                dest[o] = Float((Double(acc) * 2.0 - Double(bytesPerPCM * 8)) * scale)
                o += 1
            }
        }
        return frames
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

    private func pcmInt24(src: UnsafePointer<UInt8>, channel: Int, byteIndex: Int) -> Int32 {
        let bits = bytesPerPCM * 8
        let acc = popcount(src: src, channel: channel, byteIndex: byteIndex)
        let sample = Int32((Double(acc * 2 - bits) / Double(bits)) * Double(1 << 22))
        return max(min(sample, (1 << 23) - 1), -(1 << 23))
    }

    private func popcount(src: UnsafePointer<UInt8>, channel: Int, byteIndex: Int) -> Int {
        var acc = 0
        for i in 0..<bytesPerPCM {
            let raw = byte(src, channel: channel, index: byteIndex + i)
            acc += Int((lsbFirst ? raw : raw.bitReversed).nonzeroBitCount)
        }
        return acc
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
