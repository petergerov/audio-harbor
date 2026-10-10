import AVFoundation
import Foundation

/// What a file tells about itself for the DIDL-Lite `<res>` element.
public struct FileInfo: Sendable {
    public var size: UInt64 = 0
    public var duration: Double?
    public var sampleRate: Double?
    public var bits: Int?
    public var channels: Int?

    public init(_ url: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        if url.pathExtension.lowercased() == "dsf" {
            readDSFHeader(url)
        } else if let file = try? AVAudioFile(forReading: url) {
            let format = file.fileFormat
            sampleRate = format.sampleRate
            channels = Int(format.channelCount)
            let bitsPerChannel = format.streamDescription.pointee.mBitsPerChannel
            if bitsPerChannel > 0 { bits = Int(bitsPerChannel) }
            if format.sampleRate > 0 { duration = Double(file.length) / format.sampleRate }
        }
    }

    /// DSF: "DSD " chunk (28 bytes), then "fmt " with channels @52, rate @56, sample count @64.
    private mutating func readDSFHeader(_ url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 80)
        guard data.count >= 72, data.prefix(4) == Data("DSD ".utf8) else { return }
        func u32(_ offset: Int) -> UInt32 {
            data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
        }
        func u64(_ offset: Int) -> UInt64 {
            data.subdata(in: offset..<offset + 8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
        }
        channels = Int(u32(52))
        let rate = Double(u32(56))
        sampleRate = rate
        bits = 1
        if rate > 0 { duration = Double(u64(64)) / rate }
    }

    public var label: String {
        var parts: [String] = []
        if let sampleRate { parts.append(String(format: "%g kHz", sampleRate / 1000)) }
        if let bits { parts.append("\(bits)-bit") }
        if let channels { parts.append("\(channels) ch") }
        if let duration { parts.append(hms(duration)) }
        parts.append(String(format: "%.1f MB", Double(size) / 1_048_576))
        return parts.joined(separator: " · ")
    }

    /// The attributes of a `<res>` element: protocolInfo, size, duration and the audio format.
    public func resAttributes(mime: String, features: String) -> String {
        var attributes = "protocolInfo=\"http-get:*:\(mime):\(features)\" size=\"\(size)\""
        if let duration {
            attributes += String(format: " duration=\"%@.%03d\"", hms(duration), Int(duration.truncatingRemainder(dividingBy: 1) * 1000))
        }
        if let sampleRate { attributes += " sampleFrequency=\"\(Int(sampleRate))\"" }
        if let bits { attributes += " bitsPerSample=\"\(bits)\"" }
        if let channels { attributes += " nrAudioChannels=\"\(channels)\"" }
        return attributes
    }
}
