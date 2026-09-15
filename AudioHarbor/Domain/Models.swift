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
    case sacd = "SACD"
    case unknown = "?"

    var isDSD: Bool {
        self == .dsf || self == .dff || self == .sacd
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
        case "iso": .sacd
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
    /// Content hash into `ArtworkCache` — keeps the in-memory catalogue light.
    var artworkHash: String?
    /// User-assigned labels (persisted by file path).
    var labels: [String]
    /// Unique catalogue key. Same as `url.path` for ordinary files;
    /// `path#sacd/3` / `path#dff/3` when one container holds many tracks.
    var cataloguePath: String

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
        artworkHash: String? = nil,
        labels: [String] = [],
        cataloguePath: String? = nil
    ) {
        let identity = cataloguePath ?? url.standardizedFileURL.path
        // Stable across rescans so playlists (and other ID refs) survive relaunch.
        self.id = id ?? Self.stableID(forIdentity: identity)
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
        self.artworkHash = artworkHash
        self.labels = labels
        self.cataloguePath = identity
    }

    var folderDisplayName: String {
        if VirtualTrackPath.isVirtual(cataloguePath), let number = trackNumber {
            return String(format: "%02d  %@", number, title)
        }
        return url.lastPathComponent
    }

    /// Deterministic UUID from file path (same idea as path-keyed labels).
    static func stableID(for url: URL) -> UUID {
        stableID(forIdentity: url.standardizedFileURL.path)
    }

    static func stableID(forIdentity path: String) -> UUID {
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

struct LibraryFacet: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var count: Int
}

struct Album: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var artist: String
    var year: Int?
    var tracks: [Track]
    var artworkData: Data?
    var artworkHash: String?

    init(
        id: UUID? = nil,
        title: String,
        artist: String,
        year: Int? = nil,
        tracks: [Track],
        artworkData: Data? = nil,
        artworkHash: String? = nil
    ) {
        self.id = id ?? Self.stableID(title: title, artist: artist)
        self.title = title
        self.artist = artist
        self.year = year
        self.tracks = tracks
        self.artworkData = artworkData
        self.artworkHash = artworkHash
    }

    static func stableID(title: String, artist: String) -> UUID {
        let digest = SHA256.hash(data: Data("\(title.lowercased())|\(artist.lowercased())".utf8))
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

    let id: String
    let name: String
    let url: URL
    let kind: Kind

    init(name: String, url: URL, kind: Kind, id: String? = nil) {
        self.id = id ?? url.path
        self.name = name
        self.url = url
        self.kind = kind
    }
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
        case .exclusive: "Exclusive"
        case .dop: "DoP"
        }
    }

    /// One line under the title — what this is for.
    var blurb: String {
        switch self {
        case .shared: "Everyday listening — start here"
        case .exclusive: "Bit-perfect into a USB DAC"
        case .dop: "DSD files into a DSD DAC"
        }
    }

    /// Plain-language explanation for the selected mode.
    var detail: String {
        switch self {
        case .shared:
            "Plays like any other app. Other sound still works (calls, YouTube, notifications). Fine for built-in speakers, Bluetooth, AirPlay, and headphones. If you are not sure, stay here."
        case .exclusive:
            "Audio Harbor takes over a USB DAC so the file plays unchanged — same sample rate, nothing mixed in. Other apps go silent. Skip this for Mac speakers, Bluetooth, or AirPlay; they cannot do exclusive."
        case .dop:
            "For DSF, DFF, and SACD ISO tracks. Sends DSD to a DAC that understands DoP. If the DAC cannot, Audio Harbor converts to ordinary PCM so the track still plays. Ignore this unless you collect DSD."
        }
    }

    var isMacOnly: Bool {
        switch self {
        case .shared: false
        case .exclusive, .dop: true
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

    var detail: String {
        switch self {
        case .preferDoP:
            "When Output is Exclusive or DoP, try sending DSD as DoP first. If the DAC cannot, Audio Harbor converts to PCM."
        case .convertToPCM:
            "Always turn DSD into ordinary PCM. Safest for speakers, headphones, and DACs that do not do DSD."
        }
    }
}

enum RepeatMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case all
    case one

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Repeat off"
        case .all: "Repeat queue"
        case .one: "Repeat track"
        }
    }

    var systemImage: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    /// Cycle order for the deck button: off → queue → track → off.
    var cycled: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
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
