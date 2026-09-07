import CryptoKit
import Foundation

enum AudioFormat: String, Codable, CaseIterable, Sendable {
    case flac = "FLAC"
    case alac = "ALAC"
    case wav = "WAV"
    case aiff = "AIFF"
    case aac = "AAC"
    case mp3 = "MP3"
    case dsf = "DSF"
    case dff = "DFF"
    case unknown = "?"

    var isDSD: Bool {
        self == .dsf || self == .dff
    }

    static func infer(from url: URL) -> AudioFormat {
        switch url.pathExtension.lowercased() {
        case "flac": .flac
        case "m4a", "alac": .alac
        case "wav": .wav
        case "aiff", "aif": .aiff
        case "aac": .aac
        case "mp3": .mp3
        case "dsf": .dsf
        case "dff": .dff
        default: .unknown
        }
    }
}

struct Track: Identifiable, Hashable, Sendable {
    let id: UUID
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
    var url: URL
    var artworkData: Data?
    /// User-assigned labels (persisted by file path).
    var labels: [String]

    init(
        id: UUID? = nil,
        title: String,
        artist: String,
        album: String,
        trackNumber: Int? = nil,
        year: Int? = nil,
        duration: TimeInterval,
        format: AudioFormat,
        sampleRateHz: Int? = nil,
        bitDepth: Int? = nil,
        channelCount: Int? = nil,
        url: URL,
        artworkData: Data? = nil,
        labels: [String] = []
    ) {
        // Stable across rescans so playlists (and other ID refs) survive relaunch.
        self.id = id ?? Self.stableID(for: url)
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
        self.year = year
        self.duration = duration
        self.format = format
        self.sampleRateHz = sampleRateHz
        self.bitDepth = bitDepth
        self.channelCount = channelCount
        self.url = url
        self.artworkData = artworkData
        self.labels = labels
    }

    /// Deterministic UUID from file path (same idea as path-keyed labels).
    static func stableID(for url: URL) -> UUID {
        let path = url.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

struct Album: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var artist: String
    var year: Int?
    var tracks: [Track]
    var artworkData: Data?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        year: Int? = nil,
        tracks: [Track],
        artworkData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.year = year
        self.tracks = tracks
        self.artworkData = artworkData
    }
}

enum CatalogueBrowseMode: String, CaseIterable, Identifiable, Sendable {
    case smart
    case folders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: "Smart"
        case .folders: "Directories"
        }
    }

    var subtitle: String {
        switch self {
        case .smart: "Albums & metadata search"
        case .folders: "Browse connected directories"
        }
    }
}

struct FolderBrowseEntry: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case directory
        case audioFile
    }

    var id: String { url.path }
    let name: String
    let url: URL
    let kind: Kind
}

struct FolderSearchHit: Identifiable, Hashable, Sendable {
    var id: String { entry.id }
    let entry: FolderBrowseEntry
    /// Path under the shelf root, for result context (e.g. `Artist/Album`).
    let relativePath: String
}

enum OutputMode: String, CaseIterable, Identifiable, Sendable {
    case shared
    case exclusive
    case dop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shared: "Shared"
        case .exclusive: "Exclusive (bit-perfect)"
        case .dop: "Force DoP path"
        }
    }

    var detail: String {
        switch self {
        case .shared: "Uses the system mixer. Most compatible."
        case .exclusive: "Hog mode + sample-rate match on Mac. Preserves 24-bit PCM."
        case .dop: "Prefer DSD over PCM framing for capable DACs."
        }
    }
}

enum DSDStrategy: String, CaseIterable, Identifiable, Sendable {
    case preferDoP
    case convertToPCM

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferDoP: "Prefer DoP"
        case .convertToPCM: "Convert to PCM"
        }
    }
}

enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case failed(String)
}
