import Foundation
import Observation

/// Catalogue screen state and actions: debounced search, expanded album / artist rows,
/// adding directories, and starting playback from any browse mode.
@Observable
@MainActor
final class LibraryViewModel {
    private let app: AppModel
    private var library: LibraryService { app.library }

    /// What the search field shows. Pushed to the catalogue after a short pause.
    var searchDraft: String {
        didSet {
            guard searchDraft != oldValue else { return }
            scheduleSearch()
        }
    }
    var expandedAlbumID: UUID?
    var expandedArtistName: String?
    /// iOS: the folder picker is showing.
    var isDirectoryImporterPresented = false

    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        searchDraft = app.library.searchQuery
    }

    var subtitle: String {
        let mode = library.browseMode
        if library.showsDemoLibrary {
            return "Demo library — add a directory to start."
        }
        if let status = library.indexStatusText {
            return "\(mode.title) — \(status)."
        }
        return "\(mode.title) — \(mode.subtitle.lowercased())."
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            library.searchQuery = searchDraft
            expandedAlbumID = nil
            expandedArtistName = nil
        }
    }

    /// Clears the search and opens the folder holding `url` in Directories.
    func reveal(_ url: URL) {
        searchDraft = ""
        library.searchQuery = ""
        library.revealInFolders(url: url)
    }

    // MARK: - Expanding rows

    func toggleAlbum(_ album: Album) {
        expandedAlbumID = expandedAlbumID == album.id ? nil : album.id
    }

    func toggleArtist(_ name: String) {
        expandedArtistName = expandedArtistName == name ? nil : name
    }

    // MARK: - Directories

    func addDirectory() {
        #if os(macOS)
        library.addFolder()
        showDirectories()
        #else
        isDirectoryImporterPresented = true
        #endif
    }

    func addDirectories(_ urls: [URL]) {
        library.addFolders(urls: urls)
        showDirectories()
    }

    private func showDirectories() {
        if library.browseMode != .folders {
            library.setBrowseMode(.folders)
        }
    }

    // MARK: - Playback

    func playAlbum(_ album: Album, startingAt track: Track? = nil) {
        app.play(album.tracks, startingAt: track, from: .album(album.title))
    }

    func playArtist(_ name: String, startingAt track: Track? = nil) {
        app.play(library.visibleTracks(forArtist: name), startingAt: track, from: .artist(name))
    }

    /// Plays a directory's own files, or everything under it if it only holds subfolders.
    func playDirectory(_ url: URL, name: String) {
        guard let playback = library.directoryPlaybackQueue(at: url) else { return }
        app.play(playback.queue, startingAt: playback.track, from: .folder(name))
    }

    func playRoot(_ bookmark: FolderBookmark) {
        guard let url = library.accessibleFolderURLs[bookmark.id] else { return }
        playDirectory(url, name: bookmark.name)
    }

    /// Queues the folder holding `entry`, starting at `entry` or at the folder's first track.
    func playFolder(containing entry: FolderBrowseEntry, startingAtEntry: Bool = true) {
        let playback = library.folderPlaybackQueue(startingAt: entry.url, identity: entry.id)
        app.play(
            playback.queue,
            startingAt: startingAtEntry ? playback.track : nil,
            from: .folder(entry.url.deletingLastPathComponent().lastPathComponent)
        )
    }
}
