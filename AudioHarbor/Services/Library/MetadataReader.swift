import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct TrackMetadata: Sendable {
    var title: String
    var artist: String
    var album: String
    var trackNumber: Int?
    var year: Int?
    var duration: TimeInterval
    var format: AudioFormat
    var sampleRateHz: Int?
    var bitDepth: Int?
    var channelCount: Int?
    var artworkData: Data?
}

enum MetadataReader {
    static func read(url: URL) async -> TrackMetadata {
        let format = AudioFormat.infer(from: url)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent

        if format.isDSD {
            return readDSD(url: url, format: format, fallbackTitle: fallbackTitle)
        }

        return await readPCM(url: url, format: format, fallbackTitle: fallbackTitle)
    }

    private static func readDSD(url: URL, format: AudioFormat, fallbackTitle: String) -> TrackMetadata {
        do {
            let header = try DSDDecoder.probe(url: url)
            return TrackMetadata(
                title: fallbackTitle,
                artist: "Unknown Artist",
                album: url.deletingLastPathComponent().lastPathComponent,
                trackNumber: nil,
                year: nil,
                duration: header.duration,
                format: format,
                sampleRateHz: header.sampleRate,
                bitDepth: 1,
                channelCount: header.channelCount,
                artworkData: nil
            )
        } catch {
            return TrackMetadata(
                title: fallbackTitle,
                artist: "Unknown Artist",
                album: url.deletingLastPathComponent().lastPathComponent,
                trackNumber: nil,
                year: nil,
                duration: 0,
                format: format,
                sampleRateHz: format == .dsf ? 2_822_400 : nil,
                bitDepth: 1,
                channelCount: 2,
                artworkData: nil
            )
        }
    }

    private static func readPCM(url: URL, format: AudioFormat, fallbackTitle: String) async -> TrackMetadata {
        var meta = TrackMetadata(
            title: fallbackTitle,
            artist: "Unknown Artist",
            album: url.deletingLastPathComponent().lastPathComponent,
            trackNumber: nil,
            year: nil,
            duration: 0,
            format: format,
            sampleRateHz: nil,
            bitDepth: nil,
            channelCount: nil,
            artworkData: nil
        )

        if let file = try? AVAudioFile(forReading: url) {
            let processing = file.processingFormat
            meta.duration = Double(file.length) / processing.sampleRate
            meta.sampleRateHz = Int(processing.sampleRate.rounded())
            meta.channelCount = Int(processing.channelCount)
            meta.bitDepth = bitDepth(from: file.fileFormat)
            if format == .alac || format == .unknown, file.fileFormat.settings["AVFormatIDKey"] as? UInt32 == kAudioFormatAppleLossless {
                meta.format = .alac
            }
        }

        let asset = AVURLAsset(url: url)
        do {
            let items = try await asset.load(.commonMetadata)
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try await item.load(.stringValue), !value.isEmpty {
                        meta.title = value
                    }
                case .commonKeyArtist:
                    if let value = try await item.load(.stringValue), !value.isEmpty {
                        meta.artist = value
                    }
                case .commonKeyAlbumName:
                    if let value = try await item.load(.stringValue), !value.isEmpty {
                        meta.album = value
                    }
                case .commonKeyArtwork:
                    if let data = try await item.load(.dataValue) {
                        meta.artworkData = normalizedImageData(data)
                    }
                default:
                    break
                }
            }

            // iTunes / ID3 style extras
            let all = try await asset.load(.metadata)
            for item in all {
                let id = item.identifier
                if id == .id3MetadataTrackNumber || id == .iTunesMetadataTrackNumber {
                    if let value = try await item.load(.stringValue) {
                        meta.trackNumber = parseTrackNumber(value)
                    } else if let number = try await item.load(.numberValue) {
                        meta.trackNumber = number.intValue
                    }
                }
                if id == .id3MetadataYear || id == .iTunesMetadataReleaseDate {
                    if let value = try await item.load(.stringValue) {
                        meta.year = parseYear(value)
                    }
                }
            }

            if meta.duration <= 0 {
                let duration = try await asset.load(.duration)
                meta.duration = duration.seconds.isFinite ? duration.seconds : 0
            }
        } catch {
            // Keep AVAudioFile-derived fields.
        }

        return meta
    }

    private static func bitDepth(from format: AVAudioFormat) -> Int? {
        let asbd = format.streamDescription.pointee
        if asbd.mBitsPerChannel > 0 {
            return Int(asbd.mBitsPerChannel)
        }
        if format.commonFormat == .pcmFormatFloat32 { return 32 }
        if format.commonFormat == .pcmFormatInt16 { return 16 }
        return nil
    }

    private static func parseTrackNumber(_ raw: String) -> Int? {
        let head = raw.split(separator: "/").first.map(String.init) ?? raw
        return Int(head.trimmingCharacters(in: .whitespaces))
    }

    private static func parseYear(_ raw: String) -> Int? {
        let digits = raw.prefix(4)
        return Int(digits)
    }

    private static func normalizedImageData(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return data }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return data
        }

        let destData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            destData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return data }
        CGImageDestinationAddImage(
            dest,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { return data }
        return destData as Data
    }
}

/// On-disk artwork store keyed by content hash. Tracks keep the hash, not pixels.
final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()

    private let directory: URL
    private let memory = NSCache<NSString, NSData>()
    private let io = DispatchQueue(label: "app.audioharbor.artwork-cache", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base
            .appendingPathComponent("AudioHarbor", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 256
        memory.totalCostLimit = 32 * 1024 * 1024
    }

    static func data(for track: Track) -> Data? {
        track.artworkData ?? track.artworkHash.flatMap { shared.load($0) }
    }

    func store(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let hash = Self.hash(data)
        let url = fileURL(for: hash)
        if !FileManager.default.fileExists(atPath: url.path) {
            io.sync {
                try? data.write(to: url, options: .atomic)
            }
        }
        memory.setObject(data as NSData, forKey: hash as NSString, cost: data.count)
        return hash
    }

    func load(_ hash: String) -> Data? {
        if let cached = memory.object(forKey: hash as NSString) {
            return cached as Data
        }
        let url = fileURL(for: hash)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        memory.setObject(data as NSData, forKey: hash as NSString, cost: data.count)
        return data
    }

    func removeUnreferenced(keeping hashes: Set<String>) {
        io.async { [directory] in
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
                return
            }
            for file in files {
                let name = file.deletingPathExtension().lastPathComponent
                if !hashes.contains(name) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    private func fileURL(for hash: String) -> URL {
        directory.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
