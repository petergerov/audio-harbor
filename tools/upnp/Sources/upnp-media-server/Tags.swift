import AVFoundation
import Foundation

/// Title, artist, album and track number: FLAC from its Vorbis comments (AVFoundation does not
/// expose them), the rest through AVFoundation. DSD files stay with their file names.
struct Tags {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var track: Int?

    init(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "flac": readFLAC(url)
        case "dsf", "dff": break
        default: readAVFoundation(url)
        }
    }

    private mutating func readFLAC(_ url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard handle.readData(ofLength: 4) == Data("fLaC".utf8) else { return }
        while true {
            let header = [UInt8](handle.readData(ofLength: 4))
            guard header.count == 4 else { return }
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            if header[0] & 0x7F == 4 {
                apply(vorbisComments: [UInt8](handle.readData(ofLength: length)))
                return
            }
            guard header[0] & 0x80 == 0, (try? handle.seek(toOffset: handle.offsetInFile + UInt64(length))) != nil else { return }
        }
    }

    /// Vendor string, then `count` × "KEY=value", all lengths little-endian 32-bit.
    private mutating func apply(vorbisComments block: [UInt8]) {
        var offset = 0
        func u32() -> Int? {
            guard offset + 4 <= block.count else { return nil }
            defer { offset += 4 }
            return Int(block[offset]) | Int(block[offset + 1]) << 8 | Int(block[offset + 2]) << 16 | Int(block[offset + 3]) << 24
        }
        guard let vendor = u32(), offset + vendor <= block.count else { return }
        offset += vendor
        guard let count = u32() else { return }
        for _ in 0..<count {
            guard let length = u32(), offset + length <= block.count else { return }
            let comment = String(decoding: block[offset..<offset + length], as: UTF8.self)
            offset += length
            guard let equals = comment.firstIndex(of: "=") else { continue }
            let value = String(comment[comment.index(after: equals)...])
            switch comment[..<equals].uppercased() {
            case "TITLE": title = title ?? value
            case "ARTIST": artist = artist ?? value
            case "ALBUM": album = album ?? value
            case "ALBUMARTIST", "ALBUM ARTIST": albumArtist = albumArtist ?? value
            case "TRACKNUMBER": track = track ?? Int(value.split(separator: "/").first ?? "")
            default: break
            }
        }
    }

    private mutating func readAVFoundation(_ url: URL) {
        for item in AVURLAsset(url: url).commonMetadata {
            guard let value = item.stringValue else { continue }
            switch item.commonKey {
            case .commonKeyTitle?: title = title ?? value
            case .commonKeyArtist?: artist = artist ?? value
            case .commonKeyAlbumName?: album = album ?? value
            default: break
            }
        }
    }
}
