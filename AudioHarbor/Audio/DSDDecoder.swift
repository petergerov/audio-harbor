import Foundation

/// DSF (and light DFF) probe + decode into DoP frames or float PCM.
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
        /// Interleaved little-endian 24-bit packed samples (3 bytes × channels × frames).
        var packed24: Data
        var isDoP: Bool
        var sourceSampleRate: Int
    }

    static func probe(url: URL) throws -> Header {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let magic = try readBytes(handle, count: 4)
        if magic == Data("DSD ".utf8) {
            return try probeDSF(handle: handle, url: url)
        }
        if magic == Data("FRM8".utf8) {
            return try probeDFF(handle: handle, url: url)
        }
        throw DSDError.unsupportedContainer
    }

    static func decode(
        url: URL,
        strategy: DSDStrategy
    ) throws -> DecodedPCM {
        let header = try probe(url: url)
        switch header.format {
        case .dsf:
            let bits = try readDSFBits(url: url, header: header)
            switch strategy {
            case .preferDoP:
                return try encodeDoP(bits: bits, header: header)
            case .convertToPCM:
                return convertToPCM(bits: bits, header: header)
            }
        case .dff:
            // DFF full bitstream decode is more involved; probe works, playback uses PCM stub path message.
            throw DSDError.dffPlaybackNotReady
        default:
            throw DSDError.unsupportedContainer
        }
    }

    // MARK: - DSF

    private static func probeDSF(handle: FileHandle, url: URL) throws -> Header {
        _ = try readBytes(handle, count: 24)

        let fmtMagic = try readBytes(handle, count: 4)
        guard fmtMagic == Data("fmt ".utf8) else { throw DSDError.badFormatChunk }
        _ = try readUInt64LE(handle) // fmt chunk size
        _ = try readUInt32LE(handle) // format version
        _ = try readUInt32LE(handle) // format ID
        _ = try readUInt32LE(handle) // channel type
        let channelCount = Int(try readUInt32LE(handle))
        let sampleRate = Int(try readUInt32LE(handle))
        let bitsPerSample = Int(try readUInt32LE(handle))
        let sampleCount = try readUInt64LE(handle)
        let blockSize = Int(try readUInt32LE(handle))
        _ = try readUInt32LE(handle) // reserved

        let dataMagic = try readBytes(handle, count: 4)
        guard dataMagic == Data("data".utf8) else { throw DSDError.badDataChunk }
        let dataChunkSize = try readUInt64LE(handle)
        let dataOffset = Int(handle.offsetInFile)
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

    private static func readDSFBits(url: URL, header: Header) throws -> [[UInt8]] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(header.dataOffset))

        var planar = Array(repeating: [UInt8](), count: header.channelCount)
        var remaining = header.dataSize
        let block = header.blockSizePerChannel

        while remaining > 0 {
            for ch in 0..<header.channelCount {
                let toRead = min(block, remaining)
                guard toRead > 0 else { break }
                let chunk = try readBytes(handle, count: toRead)
                planar[ch].append(contentsOf: chunk)
                remaining -= chunk.count
                if chunk.count < toRead { break }
            }
        }

        // Trim to sampleCount bits
        let bytesNeeded = Int((header.sampleCountPerChannel + 7) / 8)
        for ch in 0..<header.channelCount {
            if planar[ch].count > bytesNeeded {
                planar[ch].removeLast(planar[ch].count - bytesNeeded)
            }
        }
        return planar
    }

    // MARK: - DFF (probe only)

    private static func probeDFF(handle: FileHandle, url: URL) throws -> Header {
        _ = try readUInt64BE(handle) // form size
        let formType = try readBytes(handle, count: 4)
        guard formType == Data("DSD ".utf8) else { throw DSDError.unsupportedContainer }

        var sampleRate = 2_822_400
        var channelCount = 2
        var sampleCount: UInt64 = 0
        var dataOffset = 0
        var dataSize = 0

        // Scan top-level chunks until DSD data
        while true {
            let chunkIDData = try readBytes(handle, count: 4)
            guard chunkIDData.count == 4 else { break }
            let chunkID = String(data: chunkIDData, encoding: .ascii) ?? ""
            let chunkSize = Int(try readUInt64BE(handle))
            let payloadStart = Int(handle.offsetInFile)

            if chunkID == "FVER" {
                try handle.seek(toOffset: UInt64(payloadStart + chunkSize + (chunkSize % 2)))
            } else if chunkID == "PROP" {
                // Look for FS and CHNL inside PROP
                let propEnd = payloadStart + chunkSize
                _ = try readBytes(handle, count: 4) // "SND "
                while Int(handle.offsetInFile) + 12 <= propEnd {
                    let subID = String(data: try readBytes(handle, count: 4), encoding: .ascii) ?? ""
                    let subSize = Int(try readUInt64BE(handle))
                    let subStart = Int(handle.offsetInFile)
                    if subID == "FS  ", subSize >= 4 {
                        sampleRate = Int(try readUInt32BE(handle))
                    } else if subID == "CHNL", subSize >= 2 {
                        channelCount = Int(try readUInt16BE(handle))
                    }
                    try handle.seek(toOffset: UInt64(subStart + subSize + (subSize % 2)))
                }
                try handle.seek(toOffset: UInt64(propEnd + (chunkSize % 2)))
            } else if chunkID == "DSD " {
                dataOffset = payloadStart
                dataSize = chunkSize
                // Estimate sample count: data bytes * 8 / channels
                if channelCount > 0 {
                    sampleCount = UInt64(dataSize * 8 / channelCount)
                }
                break
            } else {
                try handle.seek(toOffset: UInt64(payloadStart + chunkSize + (chunkSize % 2)))
            }
        }

        guard dataSize > 0 else { throw DSDError.badDataChunk }

        return Header(
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitsPerSample: 8, // DFF is typically MSB first
            blockSizePerChannel: 1,
            sampleCountPerChannel: sampleCount,
            dataOffset: dataOffset,
            dataSize: dataSize,
            format: .dff
        )
    }

    // MARK: - DoP / PCM

    private static func encodeDoP(bits: [[UInt8]], header: Header) throws -> DecodedPCM {
        let channels = header.channelCount
        guard channels >= 1, bits.count == channels else { throw DSDError.channelMismatch }

        let totalBits = Int(header.sampleCountPerChannel)
        let dopFrames = totalBits / 16
        let lsbFirst = header.bitsPerSample == 1

        var out = Data(capacity: dopFrames * channels * 3)
        var markers: [UInt8] = Array(repeating: 0x05, count: channels)

        for frame in 0..<dopFrames {
            for ch in 0..<channels {
                let bitIndex = frame * 16
                let payload = read16Bits(from: bits[ch], bitIndex: bitIndex, lsbFirst: lsbFirst)
                let marker = markers[ch]
                // 24-bit little-endian: [lo][mid][hi=marker]
                out.append(UInt8(payload & 0xFF))
                out.append(UInt8((payload >> 8) & 0xFF))
                out.append(marker)
                markers[ch] = (marker == 0x05) ? 0xFA : 0x05
            }
        }

        return DecodedPCM(
            sampleRate: Double(header.dopSampleRate),
            channelCount: channels,
            frames: dopFrames,
            packed24: out,
            isDoP: true,
            sourceSampleRate: header.sampleRate
        )
    }

    /// Simple 16× decimation to soft PCM (compatibility path — not audiophile-grade).
    private static func convertToPCM(bits: [[UInt8]], header: Header) -> DecodedPCM {
        let channels = header.channelCount
        let totalBits = Int(header.sampleCountPerChannel)
        let pcmFrames = totalBits / 16
        let lsbFirst = header.bitsPerSample == 1
        var out = Data(capacity: pcmFrames * channels * 3)

        for frame in 0..<pcmFrames {
            for ch in 0..<channels {
                var acc = 0
                let base = frame * 16
                for i in 0..<16 {
                    let bit = readBit(from: bits[ch], bitIndex: base + i, lsbFirst: lsbFirst)
                    acc += bit ? 1 : -1
                }
                // Map [-16,16] → roughly 24-bit
                let sample = Int32((Double(acc) / 16.0) * Double(1 << 22))
                let clipped = max(min(sample, (1 << 23) - 1), -(1 << 23))
                out.append(UInt8(clipped & 0xFF))
                out.append(UInt8((clipped >> 8) & 0xFF))
                out.append(UInt8((clipped >> 16) & 0xFF))
            }
        }

        return DecodedPCM(
            sampleRate: Double(header.dopSampleRate),
            channelCount: channels,
            frames: pcmFrames,
            packed24: out,
            isDoP: false,
            sourceSampleRate: header.sampleRate
        )
    }

    private static func read16Bits(from bytes: [UInt8], bitIndex: Int, lsbFirst: Bool) -> UInt16 {
        var value: UInt16 = 0
        for i in 0..<16 {
            if readBit(from: bytes, bitIndex: bitIndex + i, lsbFirst: lsbFirst) {
                value |= (1 << i)
            }
        }
        return value
    }

    private static func readBit(from bytes: [UInt8], bitIndex: Int, lsbFirst: Bool) -> Bool {
        let byteIndex = bitIndex / 8
        guard byteIndex < bytes.count else { return false }
        let bitInByte = bitIndex % 8
        let mask: UInt8 = lsbFirst ? (1 << bitInByte) : (0x80 >> bitInByte)
        return (bytes[byteIndex] & mask) != 0
    }

    // MARK: - Binary helpers

    private static func readUInt16BE(_ handle: FileHandle) throws -> UInt16 {
        let d = handle.readData(ofLength: 2)
        guard d.count == 2 else { throw DSDError.truncated }
        return (UInt16(d[0]) << 8) | UInt16(d[1])
    }

    private static func readUInt32LE(_ handle: FileHandle) throws -> UInt32 {
        let d = handle.readData(ofLength: 4)
        guard d.count == 4 else { throw DSDError.truncated }
        return UInt32(d[0]) | (UInt32(d[1]) << 8) | (UInt32(d[2]) << 16) | (UInt32(d[3]) << 24)
    }

    private static func readUInt32BE(_ handle: FileHandle) throws -> UInt32 {
        let d = handle.readData(ofLength: 4)
        guard d.count == 4 else { throw DSDError.truncated }
        return (UInt32(d[0]) << 24) | (UInt32(d[1]) << 16) | (UInt32(d[2]) << 8) | UInt32(d[3])
    }

    private static func readUInt64LE(_ handle: FileHandle) throws -> UInt64 {
        let d = handle.readData(ofLength: 8)
        guard d.count == 8 else { throw DSDError.truncated }
        var value: UInt64 = 0
        for i in 0..<8 { value |= UInt64(d[i]) << (8 * i) }
        return value
    }

    private static func readUInt64BE(_ handle: FileHandle) throws -> UInt64 {
        let d = handle.readData(ofLength: 8)
        guard d.count == 8 else { throw DSDError.truncated }
        var value: UInt64 = 0
        for i in 0..<8 { value = (value << 8) | UInt64(d[i]) }
        return value
    }

    private static func readBytes(_ handle: FileHandle, count: Int) throws -> Data {
        let d = handle.readData(ofLength: count)
        guard d.count == count || count == 0 else {
            if d.isEmpty { throw DSDError.truncated }
            return d
        }
        return d
    }
}

enum DSDError: LocalizedError {
    case unsupportedContainer
    case badFormatChunk
    case badDataChunk
    case truncated
    case channelMismatch
    case dffPlaybackNotReady

    var errorDescription: String? {
        switch self {
        case .unsupportedContainer: "Unsupported DSD container"
        case .badFormatChunk: "Invalid DSF fmt chunk"
        case .badDataChunk: "Invalid DSD data chunk"
        case .truncated: "Truncated DSD file"
        case .channelMismatch: "DSD channel data mismatch"
        case .dffPlaybackNotReady: "DFF probe works; full DFF playback lands next. Use DSF for DoP now."
        }
    }
}
