import Foundation

/// Wire-safe track identity. Never includes filesystem `url` or artwork bytes.
struct TrackDTO: Codable, Sendable, Hashable, Equatable {
    var id: UUID
    var cataloguePath: String
    var title: String
    var artist: String
    var album: String
    var trackNumber: Int?
    var year: Int?
    var duration: TimeInterval
    var format: String
    var sampleRateHz: Int?
    var bitDepth: Int?
    var channelCount: Int?
    var artworkHash: String?

    init(track: Track) {
        id = track.id
        cataloguePath = track.cataloguePath
        title = track.title
        artist = track.artist
        album = track.album
        trackNumber = track.trackNumber
        year = track.year
        duration = track.duration
        format = track.format.rawValue
        sampleRateHz = track.sampleRateHz
        bitDepth = track.bitDepth
        channelCount = track.channelCount
        artworkHash = track.artworkHash
    }
}

/// Snapshot the phone uses to render Now Playing.
/// Seek bar: `position + rate × (now − positionTimestamp)` while `rate > 0`.
struct NowPlayingSnapshot: Codable, Sendable, Equatable {
    var generation: UInt64
    var track: TrackDTO?
    var state: String
    var position: TimeInterval
    var duration: TimeInterval
    var positionTimestamp: Date
    var rate: Double
    var queueIndex: Int
    var queueCount: Int
    var queueSourceKind: String
    var queueSourceName: String?
    var repeatMode: String
    var isShuffled: Bool
    var activeFormatLabel: String?
    var pathLabel: String
    /// Hardware volume of the Mac's active output (the DAC), 0…1. Nil when that output has no
    /// volume control, or from a Mac that predates remote volume.
    var outputVolume: Double?
    /// Name of the output the Mac plays to.
    var outputName: String?

    /// Equality ignoring continuous position fields — used to coalesce tick updates.
    func equalsIgnoringPosition(_ other: NowPlayingSnapshot) -> Bool {
        var a = self
        var b = other
        a.position = 0
        b.position = 0
        a.positionTimestamp = .distantPast
        b.positionTimestamp = .distantPast
        a.generation = 0
        b.generation = 0
        return a == b
    }
}

struct QueueSnapshot: Codable, Sendable, Equatable {
    var generation: UInt64
    var index: Int
    var tracks: [TrackDTO]
    var sourceKind: String
    var sourceName: String?
}

enum BrowseScope: String, Codable, Sendable {
    case albums
    case artists
    case playlists
    case folders
    case albumTracks
    case artistTracks
    case playlistTracks
}

struct BrowseRequest: Codable, Sendable, Equatable {
    var scope: BrowseScope
    /// Album UUID, artist name, or playlist UUID depending on `scope`.
    var parentID: String?
    var offset: Int
    var limit: Int
}

enum BrowseItem: Codable, Sendable, Equatable {
    case album(id: UUID, title: String, artist: String, trackCount: Int, artworkHash: String?)
    case artist(name: String, trackCount: Int)
    case playlist(id: UUID, name: String, trackCount: Int)
    /// Connected directory or subdirectory. `id` is `rootUUID` or `rootUUID/rel/path`.
    case folder(id: String, name: String, childHint: String?)
    case track(TrackDTO)

    enum CodingKeys: String, CodingKey {
        case album, artist, playlist, folder, track
    }

    enum AlbumKeys: String, CodingKey {
        case id, title, artist, trackCount, artworkHash
    }

    enum ArtistKeys: String, CodingKey {
        case name, trackCount
    }

    enum PlaylistKeys: String, CodingKey {
        case id, name, trackCount
    }

    enum FolderKeys: String, CodingKey {
        case id, name, childHint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.album) {
            let nested = try container.nestedContainer(keyedBy: AlbumKeys.self, forKey: .album)
            self = .album(
                id: try nested.decode(UUID.self, forKey: .id),
                title: try nested.decode(String.self, forKey: .title),
                artist: try nested.decode(String.self, forKey: .artist),
                trackCount: try nested.decode(Int.self, forKey: .trackCount),
                artworkHash: try nested.decodeIfPresent(String.self, forKey: .artworkHash)
            )
            return
        }
        if container.contains(.artist) {
            let nested = try container.nestedContainer(keyedBy: ArtistKeys.self, forKey: .artist)
            self = .artist(
                name: try nested.decode(String.self, forKey: .name),
                trackCount: try nested.decode(Int.self, forKey: .trackCount)
            )
            return
        }
        if container.contains(.playlist) {
            let nested = try container.nestedContainer(keyedBy: PlaylistKeys.self, forKey: .playlist)
            self = .playlist(
                id: try nested.decode(UUID.self, forKey: .id),
                name: try nested.decode(String.self, forKey: .name),
                trackCount: try nested.decode(Int.self, forKey: .trackCount)
            )
            return
        }
        if container.contains(.folder) {
            let nested = try container.nestedContainer(keyedBy: FolderKeys.self, forKey: .folder)
            self = .folder(
                id: try nested.decode(String.self, forKey: .id),
                name: try nested.decode(String.self, forKey: .name),
                childHint: try nested.decodeIfPresent(String.self, forKey: .childHint)
            )
            return
        }
        if container.contains(.track) {
            self = .track(try container.decode(TrackDTO.self, forKey: .track))
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unknown BrowseItem")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .album(id, title, artist, trackCount, artworkHash):
            var nested = container.nestedContainer(keyedBy: AlbumKeys.self, forKey: .album)
            try nested.encode(id, forKey: .id)
            try nested.encode(title, forKey: .title)
            try nested.encode(artist, forKey: .artist)
            try nested.encode(trackCount, forKey: .trackCount)
            try nested.encodeIfPresent(artworkHash, forKey: .artworkHash)
        case let .artist(name, trackCount):
            var nested = container.nestedContainer(keyedBy: ArtistKeys.self, forKey: .artist)
            try nested.encode(name, forKey: .name)
            try nested.encode(trackCount, forKey: .trackCount)
        case let .playlist(id, name, trackCount):
            var nested = container.nestedContainer(keyedBy: PlaylistKeys.self, forKey: .playlist)
            try nested.encode(id, forKey: .id)
            try nested.encode(name, forKey: .name)
            try nested.encode(trackCount, forKey: .trackCount)
        case let .folder(id, name, childHint):
            var nested = container.nestedContainer(keyedBy: FolderKeys.self, forKey: .folder)
            try nested.encode(id, forKey: .id)
            try nested.encode(name, forKey: .name)
            try nested.encodeIfPresent(childHint, forKey: .childHint)
        case .track(let dto):
            try container.encode(dto, forKey: .track)
        }
    }

    var listID: String {
        switch self {
        case let .album(id, _, _, _, _): "album:\(id.uuidString)"
        case let .artist(name, _): "artist:\(name)"
        case let .playlist(id, _, _): "playlist:\(id.uuidString)"
        case let .folder(id, _, _): "folder:\(id)"
        case .track(let dto): "track:\(dto.cataloguePath)"
        }
    }

    var title: String {
        switch self {
        case let .album(_, title, _, _, _): title
        case let .artist(name, _): name
        case let .playlist(_, name, _): name
        case let .folder(_, name, _): name
        case .track(let dto): dto.title
        }
    }

    var subtitle: String {
        switch self {
        case let .album(_, _, artist, trackCount, _): "\(artist) · \(trackCount)"
        case let .artist(_, trackCount): "\(trackCount) tracks"
        case let .playlist(_, _, trackCount): "\(trackCount) tracks"
        case let .folder(_, _, hint): hint ?? "Folder"
        case .track(let dto): "\(dto.artist) — \(dto.album)"
        }
    }
}

enum PlaySelection: Codable, Sendable, Equatable {
    case album(id: UUID)
    case artist(name: String)
    case track(cataloguePath: String)
    case playlist(id: UUID)
    /// `rootUUID` or `rootUUID/rel/path` — plays that directory's queue.
    case folder(id: String)

    enum CodingKeys: String, CodingKey {
        case album, artist, track, playlist, folder
    }

    enum AlbumKeys: String, CodingKey { case id }
    enum ArtistKeys: String, CodingKey { case name }
    enum TrackKeys: String, CodingKey { case cataloguePath }
    enum PlaylistKeys: String, CodingKey { case id }
    enum FolderKeys: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.album) {
            let nested = try container.nestedContainer(keyedBy: AlbumKeys.self, forKey: .album)
            self = .album(id: try nested.decode(UUID.self, forKey: .id))
            return
        }
        if container.contains(.artist) {
            let nested = try container.nestedContainer(keyedBy: ArtistKeys.self, forKey: .artist)
            self = .artist(name: try nested.decode(String.self, forKey: .name))
            return
        }
        if container.contains(.track) {
            let nested = try container.nestedContainer(keyedBy: TrackKeys.self, forKey: .track)
            self = .track(cataloguePath: try nested.decode(String.self, forKey: .cataloguePath))
            return
        }
        if container.contains(.playlist) {
            let nested = try container.nestedContainer(keyedBy: PlaylistKeys.self, forKey: .playlist)
            self = .playlist(id: try nested.decode(UUID.self, forKey: .id))
            return
        }
        if container.contains(.folder) {
            let nested = try container.nestedContainer(keyedBy: FolderKeys.self, forKey: .folder)
            self = .folder(id: try nested.decode(String.self, forKey: .id))
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unknown PlaySelection")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .album(let id):
            var nested = container.nestedContainer(keyedBy: AlbumKeys.self, forKey: .album)
            try nested.encode(id, forKey: .id)
        case .artist(let name):
            var nested = container.nestedContainer(keyedBy: ArtistKeys.self, forKey: .artist)
            try nested.encode(name, forKey: .name)
        case .track(let path):
            var nested = container.nestedContainer(keyedBy: TrackKeys.self, forKey: .track)
            try nested.encode(path, forKey: .cataloguePath)
        case .playlist(let id):
            var nested = container.nestedContainer(keyedBy: PlaylistKeys.self, forKey: .playlist)
            try nested.encode(id, forKey: .id)
        case .folder(let id):
            var nested = container.nestedContainer(keyedBy: FolderKeys.self, forKey: .folder)
            try nested.encode(id, forKey: .id)
        }
    }
}

enum TransportCommand: Codable, Sendable, Equatable {
    case playPause
    case next
    case previous
    case seek(seconds: TimeInterval)
    case playQueueIndex(index: Int)
    case setRepeat(mode: String)
    case setShuffle(on: Bool)
    /// Hardware volume of the Mac's active output, 0…1. Only sent when the snapshot has one.
    case setVolume(level: Double)

    enum CodingKeys: String, CodingKey {
        case playPause, next, previous, seek, playQueueIndex, setRepeat, setShuffle, setVolume
    }

    enum SeekKeys: String, CodingKey { case seconds }
    enum IndexKeys: String, CodingKey { case index }
    enum RepeatKeys: String, CodingKey { case mode }
    enum ShuffleKeys: String, CodingKey { case on }
    enum VolumeKeys: String, CodingKey { case level }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.playPause) { self = .playPause; return }
        if container.contains(.next) { self = .next; return }
        if container.contains(.previous) { self = .previous; return }
        if container.contains(.seek) {
            let nested = try container.nestedContainer(keyedBy: SeekKeys.self, forKey: .seek)
            self = .seek(seconds: try nested.decode(TimeInterval.self, forKey: .seconds))
            return
        }
        if container.contains(.playQueueIndex) {
            let nested = try container.nestedContainer(keyedBy: IndexKeys.self, forKey: .playQueueIndex)
            self = .playQueueIndex(index: try nested.decode(Int.self, forKey: .index))
            return
        }
        if container.contains(.setRepeat) {
            let nested = try container.nestedContainer(keyedBy: RepeatKeys.self, forKey: .setRepeat)
            self = .setRepeat(mode: try nested.decode(String.self, forKey: .mode))
            return
        }
        if container.contains(.setShuffle) {
            let nested = try container.nestedContainer(keyedBy: ShuffleKeys.self, forKey: .setShuffle)
            self = .setShuffle(on: try nested.decode(Bool.self, forKey: .on))
            return
        }
        if container.contains(.setVolume) {
            let nested = try container.nestedContainer(keyedBy: VolumeKeys.self, forKey: .setVolume)
            self = .setVolume(level: try nested.decode(Double.self, forKey: .level))
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unknown TransportCommand")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .playPause:
            try container.encode(true, forKey: .playPause)
        case .next:
            try container.encode(true, forKey: .next)
        case .previous:
            try container.encode(true, forKey: .previous)
        case .seek(let seconds):
            var nested = container.nestedContainer(keyedBy: SeekKeys.self, forKey: .seek)
            try nested.encode(seconds, forKey: .seconds)
        case .playQueueIndex(let index):
            var nested = container.nestedContainer(keyedBy: IndexKeys.self, forKey: .playQueueIndex)
            try nested.encode(index, forKey: .index)
        case .setRepeat(let mode):
            var nested = container.nestedContainer(keyedBy: RepeatKeys.self, forKey: .setRepeat)
            try nested.encode(mode, forKey: .mode)
        case .setShuffle(let on):
            var nested = container.nestedContainer(keyedBy: ShuffleKeys.self, forKey: .setShuffle)
            try nested.encode(on, forKey: .on)
        case .setVolume(let level):
            var nested = container.nestedContainer(keyedBy: VolumeKeys.self, forKey: .setVolume)
            try nested.encode(level, forKey: .level)
        }
    }
}
