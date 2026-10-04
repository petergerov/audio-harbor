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
        var isDSTCompressed: Bool = false

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
        var isDSTCompressed = false
        var dstFrames: UInt64 = 0

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
                    } else if subID == "CMPR", subSize >= 4 {
                        let four = String(data: data.subdata(in: subStart..<(subStart + 4)), encoding: .ascii) ?? ""
                        if four.hasPrefix("DST") {
                            isDSTCompressed = true
                        }
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
            } else if id == "DST " {
                isDSTCompressed = true
                dstFrames = max(dstFrames, dstFrameCount(in: data, start: payloadStart, size: chunkSize))
                c.offset = min(data.count, payloadStart + chunkSize + (chunkSize % 2))
            } else {
                c.offset = min(data.count, payloadStart + chunkSize + (chunkSize % 2))
            }
        }

        if dataSize == 0, isDSTCompressed {
            let oversample = max(1, sampleRate / 44_100)
            sampleCount = dstFrames * UInt64(588 * oversample)
            dataSize = 1
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
            format: .dff,
            isDSTCompressed: isDSTCompressed && dataOffset == 0
        )
    }

    private static func dstFrameCount(in data: Data, start: Int, size: Int) -> UInt64 {
        let end = start + size
        var offset = start
        var framesFromIndex: UInt64 = 0
        var framesFromChunks: UInt64 = 0
        while offset + 12 <= end {
            let id = String(data: data.subdata(in: offset..<(offset + 4)), encoding: .ascii) ?? ""
            let chunk = Int(be64(data, offset + 4))
            let payload = offset + 12
            guard chunk >= 0, payload + chunk <= end else { break }
            if id == "FRTE", chunk >= 4 {
                framesFromIndex = UInt64(be32(data, payload))
            } else if id == "DSTF", chunk > 0 {
                framesFromChunks += 1
            }
            offset = payload + chunk + (chunk % 2)
        }
        return framesFromIndex > 0 ? framesFromIndex : framesFromChunks
    }

    private static func be32(_ d: Data, _ o: Int) -> UInt32 {
        guard o + 3 < d.count else { return 0 }
        return (UInt32(d[o]) << 24) | (UInt32(d[o + 1]) << 16) | (UInt32(d[o + 2]) << 8) | UInt32(d[o + 3])
    }

    private static func be64(_ d: Data, _ o: Int) -> UInt64 {
        guard o + 7 < d.count else { return 0 }
        var v: UInt64 = 0
        for i in 0..<8 { v = (v << 8) | UInt64(d[o + i]) }
        return v
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
    /// Absolute DSD bit index in the file for clip start (0 for a whole file).
    private let clipStartBit: Int
    private let lock = NSLock()
    /// One per channel; empty for DoP.
    private var converters: [DSDToPCMConverter]
    private let settleFrames: Int
    /// The PCM frame the converters are positioned to produce next.
    private var nextFrame: Int
    /// Keeps the prefetch reads from being optimised away.
    private var prefetchSink: UInt8 = 0

    init(url: URL, strategy: DSDStrategy, startSample: UInt64 = 0, sampleCount: UInt64? = nil) throws {
        let map = try NSData(contentsOf: url, options: [.mappedIfSafe])
        let header = try DSDDecoder.parseHeader(Data(referencing: map))
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
        let available = header.sampleCountPerChannel
        let clippedStart = min(startSample, available)
        let clippedCount = min(sampleCount ?? (available - clippedStart), available - clippedStart)
        guard bitsPerFrame > 0, clippedCount > 0 else { throw DSDError.truncated }
        self.bitsPerFrame = bitsPerFrame
        self.clipStartBit = Int(clippedStart)
        self.totalBits = clippedCount
        self.frameCount = Int(clippedCount / UInt64(bitsPerFrame))
        self.sampleRate = Double(header.sampleRate / bitsPerFrame)
        self.nextFrame = 0
        if preferDoP {
            self.converters = []
            self.settleFrames = 0
        } else {
            let design = DSDToPCMDesign(dsdRate: header.sampleRate, decimation: bitsPerFrame)
            self.converters = (0..<header.channelCount).map { _ in DSDToPCMConverter(design: design) }
            self.settleFrames = design.settleFrames
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
            let clipBytes = clipStartBit >> 3
            for frame in startFrame..<(startFrame + frames) {
                let byteIndex = clipBytes + frame * bytesPerPCM
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

    /// Multi-stage FIR decimation (see `DSDToPCMDesign`), then the make-up gain from Settings.
    @discardableResult
    private func decodePCM(
        from startFrame: Int,
        count: Int,
        emit: (_ channel: Int, _ frame: Int, _ sample: Float) -> Void
    ) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard !converters.isEmpty else { return 0 }

        if startFrame != nextFrame {
            preroll(to: startFrame)
        }

        let gain = DSDConversion.gain
        let src = bytes
        for frame in 0..<count {
            let firstByte = nextFrame * bytesPerPCM
            for ch in 0..<channelCount {
                var y: Float = 0
                for i in 0..<bytesPerPCM {
                    if let out = converters[ch].push(pcmByte(src, channel: ch, relativeIndex: firstByte + i)) {
                        y = out
                    }
                }
                emit(ch, frame, max(-1, min(1, y * gain)))
            }
            nextFrame += 1
        }
        return count
    }

    /// Restart the converters a few frames early so the first frame out is already settled.
    private func preroll(to startFrame: Int) {
        for i in converters.indices { converters[i].reset() }
        let from = max(0, startFrame - settleFrames)
        let src = bytes
        for frame in from..<startFrame {
            let firstByte = frame * bytesPerPCM
            for ch in 0..<channelCount {
                for i in 0..<bytesPerPCM {
                    _ = converters[ch].push(pcmByte(src, channel: ch, relativeIndex: firstByte + i))
                }
            }
        }
        nextFrame = startFrame
    }

    /// Clip-relative DSD byte with the oldest bit in bit 7; silence outside the clip.
    private func pcmByte(_ src: UnsafePointer<UInt8>, channel: Int, relativeIndex: Int) -> UInt16 {
        guard relativeIndex >= 0, UInt64(relativeIndex) < totalBits >> 3 else {
            return DSDToPCMDesign.silentByte
        }
        let b = byte(src, channel: channel, index: (clipStartBit >> 3) + relativeIndex)
        return UInt16(lsbFirst ? b.bitReversed : b)
    }

    private static func int24(from sample: Float) -> Int32 {
        let v = Int32((sample * Float((1 << 23) - 1)).rounded())
        return max(min(v, (1 << 23) - 1), -(1 << 23))
    }

    /// Touch the mapped pages for `count` frames from `startFrame` so the IO thread never
    /// page-faults on disk. Call off the audio thread.
    func prefetch(from startFrame: Int, count: Int) {
        let first = max(0, startFrame)
        let last = min(frameCount, first + count)
        guard last > first else { return }
        let bitsLo = clipStartBit + first * bitsPerFrame
        let bitsHi = clipStartBit + last * bitsPerFrame
        // Interleave is per block, so the covered file range is whole blocks × channels.
        let blockLo = (bitsLo >> 3) / block
        let blockHi = ((bitsHi >> 3) + block - 1) / block
        let lo = header.dataOffset + blockLo * block * channelCount
        let hi = min(dataEnd, byteCount, header.dataOffset + blockHi * block * channelCount)
        guard hi > lo else { return }
        let page = Int(getpagesize())
        var sum: UInt8 = 0
        var p = lo
        while p < hi {
            sum &+= bytes[p]
            p += page
        }
        sum &+= bytes[hi - 1]
        prefetchSink = sum
    }

    /// DoP payload: the oldest DSD bit sits in bit 15, so the first byte (MSB-first) goes high.
    private func read16(src: UnsafePointer<UInt8>, channel: Int, byteIndex: Int) -> UInt16 {
        var b0 = byte(src, channel: channel, index: byteIndex)
        var b1 = byte(src, channel: channel, index: byteIndex + 1)
        if lsbFirst {
            b0 = b0.bitReversed
            b1 = b1.bitReversed
        }
        return (UInt16(b0) << 8) | UInt16(b1)
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
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedContainer: "Unsupported DSD container"
        case .badFormatChunk: "Invalid DSF fmt chunk"
        case .badDataChunk: "Invalid DSD data chunk"
        case .truncated: "Truncated DSD file"
        case .channelMismatch: "DSD channel data mismatch"
        case .tooLarge: "This DSD file is too large to decode in memory on this device."
        }
    }
}
