import AVFoundation
import Foundation
import ImageIO

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
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return data }
        return data
    }
}
