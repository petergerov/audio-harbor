import Foundation
import Observation

enum PlaylistKind: String, Codable, Hashable, Sendable {
    case manual
    case smart
}

enum SmartRuleField: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case artist
    case year
    case label

    var id: String { rawValue }

    var title: String {
        switch self {
        case .artist: "Artist"
        case .year: "Year"
        case .label: "Label"
        }
    }
}

enum SmartRuleMatch: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case equals
    case contains

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equals: "is"
        case .contains: "contains"
        }
    }
}

struct SmartPlaylistRule: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var field: SmartRuleField
    var match: SmartRuleMatch
    var value: String

    init(
        id: UUID = UUID(),
        field: SmartRuleField,
        match: SmartRuleMatch = .equals,
        value: String
    ) {
        self.id = id
        self.field = field
        self.match = match
        self.value = value
    }

    var summary: String {
        "\(field.title) \(match.title) “\(value)”"
    }
}

struct Playlist: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    /// File paths — stable across rescans (track UUIDs used to be regenerated each scan).
    var trackPaths: [String]
    var createdAt: Date
    var kind: PlaylistKind
    /// AND-combined rules for smart playlists.
    var rules: [SmartPlaylistRule]

    var isSmart: Bool { kind == .smart }

    init(
        id: UUID = UUID(),
        name: String,
        trackPaths: [String] = [],
        createdAt: Date = Date(),
        kind: PlaylistKind = .manual,
        rules: [SmartPlaylistRule] = []
    ) {
        self.id = id
        self.name = name
        self.trackPaths = trackPaths
        self.createdAt = createdAt
        self.kind = kind
        self.rules = rules
    }

    enum CodingKeys: String, CodingKey {
        case id, name, trackPaths, trackIDs, createdAt, kind, rules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        if let paths = try c.decodeIfPresent([String].self, forKey: .trackPaths) {
            trackPaths = paths
        } else {
            // Legacy UUID membership cannot be recovered after a library rescan.
            trackPaths = []
        }
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        kind = try c.decodeIfPresent(PlaylistKind.self, forKey: .kind) ?? .manual
        rules = try c.decodeIfPresent([SmartPlaylistRule].self, forKey: .rules) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(trackPaths, forKey: .trackPaths)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(kind, forKey: .kind)
        try c.encode(rules, forKey: .rules)
    }
}

@Observable
@MainActor
final class PlaylistService {
    private(set) var playlists: [Playlist] = []
    private let defaultsKey = "audioharbor.playlists"

    init() {
        load()
        if playlists.isEmpty {
            playlists = [
                Playlist(name: "Evening Listening"),
                Playlist(name: "Sunday Mix"),
            ]
            save()
        }
    }

    func createPlaylist(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlists.insert(Playlist(name: trimmed), at: 0)
        save()
    }

    func createSmartPlaylist(named name: String, rules: [SmartPlaylistRule]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = rules
            .map {
                SmartPlaylistRule(
                    field: $0.field,
                    match: $0.field == .year ? .equals : $0.match,
                    value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.value.isEmpty }
        guard !trimmed.isEmpty, !cleaned.isEmpty else { return }
        playlists.insert(
            Playlist(name: trimmed, kind: .smart, rules: cleaned),
            at: 0
        )
        save()
    }

    func updateSmartRules(_ playlist: Playlist, rules: [SmartPlaylistRule]) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }),
              playlists[idx].isSmart
        else { return }
        let cleaned = rules
            .map {
                SmartPlaylistRule(
                    id: $0.id,
                    field: $0.field,
                    match: $0.field == .year ? .equals : $0.match,
                    value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.value.isEmpty }
        playlists[idx].rules = cleaned
        save()
    }

    func rename(_ playlist: Playlist, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].name = trimmed
        save()
    }

    func delete(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    func add(_ track: Track, to playlist: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }),
              !playlists[idx].isSmart
        else { return }
        let path = track.cataloguePath
        guard !playlists[idx].trackPaths.contains(path) else { return }
        playlists[idx].trackPaths.append(path)
        save()
    }

    func removeTrack(id: UUID, from playlist: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }),
              !playlists[idx].isSmart
        else { return }
        // Resolve via current library if possible; id alone is enough with stable Track IDs.
        playlists[idx].trackPaths.removeAll { path in
            Track.stableID(forIdentity: path) == id
        }
        save()
    }

    func removeTrack(_ track: Track, from playlist: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }),
              !playlists[idx].isSmart
        else { return }
        playlists[idx].trackPaths.removeAll { $0 == track.cataloguePath }
        save()
    }

    func tracks(for playlist: Playlist, from libraryTracks: [Track]) -> [Track] {
        if playlist.isSmart {
            return libraryTracks
                .filter { Self.matches($0, rules: playlist.rules) }
                .sorted {
                    if $0.artist.localizedCaseInsensitiveCompare($1.artist) != .orderedSame {
                        return $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending
                    }
                    if $0.album.localizedCaseInsensitiveCompare($1.album) != .orderedSame {
                        return $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending
                    }
                    return ($0.trackNumber ?? 9999) < ($1.trackNumber ?? 9999)
                }
        }
        let map = Dictionary(libraryTracks.map { ($0.cataloguePath, $0) }, uniquingKeysWith: { _, last in last })
        return playlist.trackPaths.compactMap { map[$0] }
    }

    static func matches(_ track: Track, rules: [SmartPlaylistRule]) -> Bool {
        guard !rules.isEmpty else { return false }
        return rules.allSatisfy { rule in
            let value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return false }
            switch rule.field {
            case .artist:
                switch rule.match {
                case .equals:
                    return track.artist.caseInsensitiveCompare(value) == .orderedSame
                case .contains:
                    return track.artist.localizedCaseInsensitiveContains(value)
                }
            case .year:
                guard let year = track.year, let target = Int(value) else { return false }
                return year == target
            case .label:
                return track.labels.contains {
                    $0.caseInsensitiveCompare(value) == .orderedSame
                }
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data)
        else { return }
        playlists = decoded
    }
}
