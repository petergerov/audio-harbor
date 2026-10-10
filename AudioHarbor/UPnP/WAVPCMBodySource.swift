#if os(macOS)
import AVFoundation
import Foundation

/// PCM WAV body with a fixed `Content-Length` so HTTP `Range` maps to a frame.
/// Generated on the fly as the renderer reads — not pre-rendered to disk.
final class WAVPCMBodySource: @unchecked Sendable {
    static let headerSize = 44

    let sampleRate: Int
    let channelCount: Int
    let frameCount: Int
    let bitsPerSample: Int
    let label: String

    var blockAlign: Int { channelCount * (bitsPerSample / 8) }
    var dataByteCount: UInt64 { UInt64(frameCount) * UInt64(blockAlign) }
    var totalSize: UInt64 { UInt64(Self.headerSize) + dataByteCount }
    var mime: String { "audio/wav" }

    private let lock = NSLock()
    /// Fills interleaved PCM at `bitsPerSample`; returns frames written.
    private let fill: @Sendable (Int, Int, UnsafeMutableRawPointer) -> Int
    private let header: Data

    init(
        sampleRate: Int,
        channelCount: Int,
        frameCount: Int,
        bitsPerSample: Int = 24,
        label: String,
        fill: @escaping @Sendable (Int, Int, UnsafeMutableRawPointer) -> Int
    ) {
        precondition(bitsPerSample == 16 || bitsPerSample == 24)
        self.sampleRate = sampleRate
        self.channelCount = max(1, channelCount)
        self.frameCount = max(0, frameCount)
        self.bitsPerSample = bitsPerSample
        self.label = label
        self.fill = fill
        self.header = Self.makeHeader(
            sampleRate: sampleRate,
            channelCount: self.channelCount,
            frameCount: self.frameCount,
            bitsPerSample: bitsPerSample
        )
    }

    /// DSD / SACD / DST → ~88.2 kHz / 24-bit PCM (live).
    static func dsd(track: Track) throws -> WAVPCMBodySource {
        let source = try DSDPlayback.stream(for: track, strategy: .convertToPCM)
        return WAVPCMBodySource(
            sampleRate: Int(source.sampleRate.rounded()),
            channelCount: source.channelCount,
            frameCount: source.frameCount,
            bitsPerSample: 24,
            label: "wav·\(track.format.rawValue)"
        ) { start, count, dest in
            source.copyPacked24(at: start, count: count, into: dest)
        }
    }

    /// DSD as DoP in a 24-bit WAV at DSD rate / 16 (live) — for network players that take DoP.
    static func dop(track: Track) throws -> WAVPCMBodySource {
        let source = try DSDPlayback.stream(for: track, strategy: .preferDoP)
        return WAVPCMBodySource(
            sampleRate: Int(source.sampleRate.rounded()),
            channelCount: source.channelCount,
            frameCount: source.frameCount,
            bitsPerSample: 24,
            label: "dop·\(track.format.rawValue)"
        ) { start, count, dest in
            source.copyPacked24(at: start, count: count, into: dest)
        }
    }

    /// Any file AVAudioFile can open — decoded to 24-bit at the file's sample rate (live).
    static func decodedPCM(url: URL) throws -> WAVPCMBodySource {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        let frames = Int(file.length)
        let rate = Int(format.sampleRate.rounded())
        let lock = NSLock()
        return WAVPCMBodySource(
            sampleRate: rate,
            channelCount: channels,
            frameCount: frames,
            bitsPerSample: 24,
            label: "wav·\(url.pathExtension)"
        ) { start, count, dest in
            lock.lock()
            defer { lock.unlock() }
            return Self.fillFloatFile(
                file,
                format: format,
                channels: channels,
                start: start,
                count: count,
                bitsPerSample: 24,
                into: dest
            )
        }
    }

    /// Wi‑Fi path for DSF / DFF / SACD: live 44.1 kHz / 16-bit PCM (~1.4 Mbit/s).
    /// Other formats must not call this — they stay passthrough in the planner.
    static func wifiLive(track: Track) throws -> WAVPCMBodySource {
        precondition(NetworkMediaPlanner.needsTranscode(track), "wifiLive is only for DSD / SACD")
        let outRate = 44_100
        let bits = 16
        let source = try DSDPlayback.stream(for: track, strategy: .convertToPCM)
        let channels = min(2, max(1, source.channelCount))
        let outFrames = max(
            1,
            Int((Double(source.frameCount) * Double(outRate) / source.sampleRate).rounded())
        )
        return WAVPCMBodySource(
            sampleRate: outRate,
            channelCount: channels,
            frameCount: outFrames,
            bitsPerSample: bits,
            label: "wifi·\(track.format.rawValue)"
        ) { start, count, dest in
            Self.fillDownsampledFloat(
                start: start,
                count: count,
                outRate: outRate,
                outChannels: channels,
                bitsPerSample: bits,
                sourceRate: source.sampleRate,
                sourceChannels: source.channelCount,
                sourceFrames: source.frameCount,
                into: dest
            ) { srcStart, srcCount, floats in
                _ = source.copyFloatInterleaved(at: srcStart, count: srcCount, into: floats)
            }
        }
    }

    func read(offset: UInt64, maxLength: Int) throws -> Data {
        guard maxLength > 0, offset < totalSize else { return Data() }
        let end = min(offset + UInt64(maxLength), totalSize)
        let length = Int(end - offset)
        var out = Data(count: length)
        out.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            write(offset: offset, length: length, into: base)
        }
        return out
    }

    private func write(offset: UInt64, length: Int, into dest: UnsafeMutableRawPointer) {
        var written = 0
        var cursor = offset
        let out = dest.assumingMemoryBound(to: UInt8.self)

        if cursor < UInt64(Self.headerSize) {
            let headerOffset = Int(cursor)
            let take = min(length - written, Self.headerSize - headerOffset)
            header.withUnsafeBytes { src in
                guard let from = src.baseAddress else { return }
                memcpy(out.advanced(by: written), from.advanced(by: headerOffset), take)
            }
            written += take
            cursor += UInt64(take)
        }
        guard written < length else { return }

        let dataOffset = cursor - UInt64(Self.headerSize)
        let align = UInt64(blockAlign)
        guard align > 0 else { return }
        let startFrame = Int(dataOffset / align)
        let skipBytes = Int(dataOffset % align)
        let bytesWanted = length - written
        let framesNeeded = (skipBytes + bytesWanted + blockAlign - 1) / blockAlign
        guard framesNeeded > 0, startFrame < frameCount else { return }

        let frames = min(framesNeeded, frameCount - startFrame)
        let bufferBytes = frames * blockAlign
        let temp = UnsafeMutableRawPointer.allocate(byteCount: bufferBytes, alignment: 1)
        defer { temp.deallocate() }
        lock.lock()
        let got = fill(startFrame, frames, temp)
        lock.unlock()
        guard got > 0 else { return }
        let available = got * blockAlign
        let from = min(skipBytes, available)
        let take = min(bytesWanted, available - from)
        guard take > 0 else { return }
        memcpy(out.advanced(by: written), temp.advanced(by: from), take)
    }

    // MARK: - Sample helpers

    private static func pack(
        _ sample: Float,
        bitsPerSample: Int,
        into out: UnsafeMutablePointer<UInt8>,
        at o: inout Int
    ) {
        let clipped = max(-1, min(1, sample))
        if bitsPerSample == 16 {
            let v = Int16((clipped * 32_767.0).rounded())
            let bits = UInt16(bitPattern: v)
            out[o] = UInt8(bits & 0xFF)
            out[o + 1] = UInt8(bits >> 8)
            o += 2
        } else {
            let v = Int32((clipped * 8_388_607.0).rounded())
            let clipped24 = max(-8_388_608, min(8_388_607, v))
            let bits = UInt32(bitPattern: clipped24) & 0x00FF_FFFF
            out[o] = UInt8(bits & 0xFF)
            out[o + 1] = UInt8((bits >> 8) & 0xFF)
            out[o + 2] = UInt8((bits >> 16) & 0xFF)
            o += 3
        }
    }

    private static func fillFloatFile(
        _ file: AVAudioFile,
        format: AVAudioFormat,
        channels: Int,
        start: Int,
        count: Int,
        bitsPerSample: Int,
        into dest: UnsafeMutableRawPointer
    ) -> Int {
        file.framePosition = AVAudioFramePosition(start)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
        else { return 0 }
        do {
            try file.read(into: buffer, frameCount: AVAudioFrameCount(count))
        } catch {
            return 0
        }
        let got = Int(buffer.frameLength)
        guard got > 0, let planes = buffer.floatChannelData else { return 0 }
        let out = dest.assumingMemoryBound(to: UInt8.self)
        var o = 0
        let chCount = min(channels, Int(format.channelCount))
        for frame in 0..<got {
            for ch in 0..<chCount {
                pack(planes[ch][frame], bitsPerSample: bitsPerSample, into: out, at: &o)
            }
        }
        return got
    }

    private static func fillDownsampledFloat(
        start: Int,
        count: Int,
        outRate: Int,
        outChannels: Int,
        bitsPerSample: Int,
        sourceRate: Double,
        sourceChannels: Int,
        sourceFrames: Int,
        into dest: UnsafeMutableRawPointer,
        read: (Int, Int, UnsafeMutablePointer<Float>) -> Void
    ) -> Int {
        guard count > 0, sourceFrames > 0 else { return 0 }
        let srcStart = min(sourceFrames - 1, Int((Double(start) * sourceRate / Double(outRate)).rounded(.down)))
        let srcEndExclusive = min(
            sourceFrames,
            Int((Double(start + count) * sourceRate / Double(outRate)).rounded(.up)) + 1
        )
        let srcCount = max(1, srcEndExclusive - srcStart)
        let floats = UnsafeMutablePointer<Float>.allocate(capacity: srcCount * sourceChannels)
        defer { floats.deallocate() }
        read(srcStart, srcCount, floats)

        let out = dest.assumingMemoryBound(to: UInt8.self)
        var o = 0
        let chOut = min(outChannels, sourceChannels)
        for i in 0..<count {
            let srcFrame = min(
                sourceFrames - 1,
                Int((Double(start + i) * sourceRate / Double(outRate)).rounded(.down))
            )
            let local = srcFrame - srcStart
            guard local >= 0, local < srcCount else { continue }
            for ch in 0..<chOut {
                pack(floats[local * sourceChannels + ch], bitsPerSample: bitsPerSample, into: out, at: &o)
            }
        }
        return count
    }

    private static func makeHeader(
        sampleRate: Int,
        channelCount: Int,
        frameCount: Int,
        bitsPerSample: Int
    ) -> Data {
        let blockAlign = channelCount * (bitsPerSample / 8)
        let byteRate = sampleRate * blockAlign
        let dataSize = frameCount * blockAlign
        var data = Data(capacity: headerSize)
        func ascii(_ s: String) { data.append(contentsOf: s.utf8) }
        func le16(_ v: Int) {
            var x = UInt16(clamping: v).littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }
        func le32(_ v: Int) {
            var x = UInt32(clamping: v).littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }
        ascii("RIFF")
        le32(36 + dataSize)
        ascii("WAVE")
        ascii("fmt ")
        le32(16)
        le16(1) // PCM
        le16(channelCount)
        le32(sampleRate)
        le32(byteRate)
        le16(blockAlign)
        le16(bitsPerSample)
        ascii("data")
        le32(dataSize)
        return data
    }
}
#endif
