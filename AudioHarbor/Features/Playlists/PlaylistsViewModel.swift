import Foundation
import Observation

enum PlaylistBrowserScope: String, CaseIterable, Identifiable {
    case playlists
    case labels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playlists: "Playlists"
        case .labels: "Labels"
        }
    }

    func contains(_ item: PlaylistBrowserItem) -> Bool {
        switch (self, item) {
        case (.playlists, .playlist): true
        case (.labels, .label): true
        default: false
        }
    }
}

enum PlaylistBrowserItem: Hashable, Identifiable {
    case playlist(UUID)
    case label(String)

    var id: String {
        switch self {
        case .playlist(let id): "playlist-\(id.uuidString)"
        case .label(let name): "label-\(name)"
        }
    }

    var kindLabel: String {
        switch self {
        case .playlist: "Playlist"
        case .label: "Label"
        }
    }

    func queueSource(named name: String) -> QueueSource {
        switch self {
        case .playlist: .playlist(name)
        case .label: .label(name)
        }
    }
}

/// Playlists screen state and actions: the sidebar scope and selection, playback,
/// playlist editing, and M3U import / export.
@Observable
@MainActor
final class PlaylistsViewModel {
    struct Report {
        var title: String
        var message: String
    }

    private let app: AppModel
    private var playlists: PlaylistService { app.playlists }
    private var library: LibraryService { app.library }

    var selection: PlaylistBrowserItem?

    /// Which list the sidebar shows. Switching drops a selection the new list cannot show.
    var scope: PlaylistBrowserScope {
        didSet {
            UserDefaults.standard.set(scope.rawValue, forKey: Self.scopeKey)
            if let selection, !scope.contains(selection) {
                self.selection = nil
            }
        }
    }

    /// Outcome of the last import or failed export, shown as an alert.
    var report: Report?

    private static let scopeKey = DefaultsKey.playlistsBrowserScope
    private static let untitledName = "Untitled Playlist"

    init(app: AppModel) {
        self.app = app
        let raw = UserDefaults.standard.string(forKey: Self.scopeKey) ?? ""
        scope = PlaylistBrowserScope(rawValue: raw) ?? .playlists
    }

    // MARK: - Reading

    var manualPlaylists: [Playlist] {
        playlists.playlists.filter { !$0.isSmart }
    }

    func tracks(for item: PlaylistBrowserItem) -> [Track] {
        switch item {
        case .playlist(let id):
            guard let playlist = playlist(id) else { return [] }
            return playlists.tracks(for: playlist, from: library.allTracks)
        case .label(let name):
            return library.tracks(forLabel: name)
        }
    }

    func title(for item: PlaylistBrowserItem) -> String {
        switch item {
        case .playlist(let id): playlist(id)?.name ?? "Playlist"
        case .label(let name): name
        }
    }

    func emptyMessage(for item: PlaylistBrowserItem) -> String {
        switch item {
        case .playlist: "Open Catalogue, right‑click a track, Add to Playlist."
        case .label: "No tracks use this label yet."
        }
    }

    // MARK: - Playback

    func play(_ item: PlaylistBrowserItem, startingAt track: Track? = nil) {
        app.play(tracks(for: item), startingAt: track, from: item.queueSource(named: title(for: item)))
    }

    // MARK: - Editing

    /// Creates a manual playlist (blank names become "Untitled Playlist N") and selects it.
    func createPlaylist(named draft: String) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? nextUntitledName() : trimmed
        playlists.createPlaylist(named: name)
        if let created = manualPlaylists.first(where: { $0.name == name }) {
            show(.playlist(created.id))
        }
    }

    func rename(_ playlist: Playlist, to name: String) {
        playlists.rename(playlist, to: name)
    }

    func delete(_ playlist: Playlist) {
        if selection == .playlist(playlist.id) { selection = nil }
        playlists.delete(playlist)
    }

    func deleteManualPlaylists(at offsets: IndexSet) {
        let manuals = manualPlaylists
        offsets.map { manuals[$0] }.forEach(playlists.delete)
    }

    /// Only manual playlists can lose tracks; smart playlists and labels are read-only here.
    func canRemoveTracks(from item: PlaylistBrowserItem) -> Bool {
        guard case .playlist(let id) = item, let playlist = playlist(id) else { return false }
        return !playlist.isSmart
    }

    func removeTracks(at offsets: IndexSet, of tracks: [Track], from item: PlaylistBrowserItem) {
        guard canRemoveTracks(from: item), case .playlist(let id) = item, let playlist = playlist(id) else { return }
        offsets.forEach { playlists.removeTrack(tracks[$0], from: playlist) }
    }

    private func playlist(_ id: UUID) -> Playlist? {
        playlists.playlists.first { $0.id == id }
    }

    private func nextUntitledName() -> String {
        let existing = Set(playlists.playlists.map(\.name))
        guard existing.contains(Self.untitledName) else { return Self.untitledName }
        var index = 2
        while existing.contains("\(Self.untitledName) \(index)") {
            index += 1
        }
        return "\(Self.untitledName) \(index)"
    }

    private func show(_ item: PlaylistBrowserItem) {
        scope = .playlists
        selection = item
    }

    // MARK: - M3U

    func exportFileName(for item: PlaylistBrowserItem) -> String {
        "\(title(for: item).replacingOccurrences(of: "/", with: "-")).m3u8"
    }

    func exportM3U8(_ item: PlaylistBrowserItem, to url: URL) {
        let text = M3UWriter.render(name: title(for: item), tracks: tracks(for: item))
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            report = Report(
                title: "Export Failed",
                message: "\(url.lastPathComponent) could not be written. \(error.localizedDescription)"
            )
        }
    }

    /// Imports each file as a playlist of the catalogue tracks it points at, then reports
    /// what matched. The last imported playlist is selected.
    func importM3U(from urls: [URL]) {
        let libraryTracks = library.allTracks
        guard !libraryTracks.isEmpty else {
            report = Report(
                title: "Nothing to Match Yet",
                message: "Add the folders with your music first. Playlists only point at files Harbor already knows."
            )
            return
        }

        let matcher = M3UMatcher(tracks: libraryTracks)
        var lines: [String] = []
        var lastImported: Playlist?
        for url in urls {
            guard let text = Self.readPlaylistFile(url) else {
                lines.append("\(url.lastPathComponent): could not be read.")
                continue
            }

            let result = matcher.resolve(M3UParser.parse(text), playlistURL: url)
            guard !result.trackPaths.isEmpty else {
                lines.append("“\(result.name)”: none of \(result.entryCount) entries found in your folders — not imported.")
                continue
            }

            let playlist = playlists.importPlaylist(named: result.name, trackPaths: result.trackPaths)
            lastImported = playlist
            lines.append(Self.summary(for: result, importedAs: playlist.name))
        }

        if let lastImported {
            show(.playlist(lastImported.id))
        }
        report = Report(
            title: lastImported == nil ? "Import Failed" : "Playlist Imported",
            message: lines.joined(separator: "\n\n")
        )
    }

    /// Picker URLs are security-scoped; read synchronously while access is open.
    private static func readPlaylistFile(_ url: URL) -> String? {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started { url.stopAccessingSecurityScopedResource() }
        }
        return (try? Data(contentsOf: url)).flatMap(M3UParser.decode)
    }

    private static func summary(for result: M3UImportResult, importedAs name: String) -> String {
        let fileEntries = result.entryCount - result.skippedRemoteCount
        var text = "“\(name)”: \(fileEntries - result.unmatched.count) of \(fileEntries) tracks."
        if result.skippedRemoteCount > 0 {
            text += " \(result.skippedRemoteCount) stream URLs skipped."
        }
        if !result.unmatched.isEmpty {
            let names = result.unmatched.prefix(5).map { entry in
                entry.displayName ?? URL(fileURLWithPath: entry.location.replacingOccurrences(of: "\\", with: "/")).lastPathComponent
            }
            text += "\nNot in your folders:\n" + names.map { "· \($0)" }.joined(separator: "\n")
            if result.unmatched.count > names.count {
                text += "\n· … and \(result.unmatched.count - names.count) more"
            }
        }
        return text
    }
}
