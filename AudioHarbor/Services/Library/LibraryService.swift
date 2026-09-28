import Foundation
import Observation

#if os(macOS)
import AppKit
#endif

@Observable
@MainActor
final class LibraryService {
    private(set) var albums: [Album] = []
    private(set) var tracks: [Track] = []
    private(set) var folders: [FolderBookmark] = []
    private(set) var isScanning = false
    private(set) var scanProgressText: String?
    var searchQuery = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            refreshQueryResults()
        }
    }
    var showsDemoLibrary = true

    private(set) var artistFacets: [LibraryFacet] = []
    private(set) var labelFacets: [LibraryFacet] = []
    private(set) var yearFacets: [LibraryFacet] = []
    private(set) var folderSearchHits: [FolderSearchHit] = []
    private var searchHitPaths: Set<String>?
    private var tracksByArtistKey: [String: [Track]] = [:]
    private var tracksByLabelKey: [String: [Track]] = [:]
    private var tracksByYear: [Int: [Track]] = [:]
    private var indexedDirectoryPaths: [String] = []

    /// Catalogue tabs: Directories (`.folders`), Albums (`.smart`), Artists (`.artists`).
    var browseMode: CatalogueBrowseMode = {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.catalogueBrowseMode) ?? ""
        return CatalogueBrowseMode(rawValue: raw) ?? .folders
    }() {
        didSet {
            UserDefaults.standard.set(browseMode.rawValue, forKey: DefaultsKey.catalogueBrowseMode)
        }
    }

    /// Where the Directories tab is. Folder search is scoped to it.
    private(set) var folderNavigation = FolderNavigation() {
        didSet {
            guard oldValue != folderNavigation else { return }
            refreshQueryResults()
        }
    }

    /// Resolved URLs currently held open via security scope.
    private(set) var accessibleFolderURLs: [UUID: URL] = [:]

    private var labelStore = TrackLabelStore()

    private var tracksByPath: [String: Track] = [:]
    private var tracksByParent: [String: [Track]] = [:]
    private var searchIndex = CatalogueSearchIndex()
    private(set) var indexedTrackCount = 0

    var indexStatusText: String? {
        guard !showsDemoLibrary, indexedTrackCount > 0 else { return nil }
        return "\(indexedTrackCount.formatted()) tracks indexed"
    }

    var filteredTracks: [Track] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return tracks }
        guard let hits = searchIndex.matchingIndices(query: q, trackCount: tracks.count) else {
            return tracks
        }
        return hits.sorted().compactMap { tracks.indices.contains($0) ? tracks[$0] : nil }
    }

    var allTracks: [Track] { tracks }

    var allArtists: [String] { artistFacets.map(\.name) }

    var allYears: [Int] { yearFacets.compactMap { Int($0.name) } }

    var allLabels: [String] { labelFacets.map(\.name) }

    var filteredAlbums: [Album] {
        guard let paths = searchHitPaths else { return albums }
        return albums.filter { album in
            album.tracks.contains { paths.contains($0.cataloguePath) }
        }
    }

    var filteredArtistFacets: [LibraryFacet] {
        guard let paths = searchHitPaths else { return artistFacets }
        return artistFacets.compactMap { facet in
            let count = tracks(forArtist: facet.name).filter { paths.contains($0.cataloguePath) }.count
            guard count > 0 else { return nil }
            return LibraryFacet(id: facet.id, name: facet.name, count: count)
        }
    }

    func visibleTracks(in album: Album) -> [Track] {
        guard let paths = searchHitPaths else { return album.tracks }
        return album.tracks.filter { paths.contains($0.cataloguePath) }
    }

    func visibleTracks(forArtist name: String) -> [Track] {
        let tracks = tracks(forArtist: name)
        guard let paths = searchHitPaths else { return tracks }
        return tracks.filter { paths.contains($0.cataloguePath) }
    }

    func tracks(forArtist name: String) -> [Track] {
        tracksByArtistKey[name.lowercased()] ?? []
    }

    func tracks(forLabel name: String) -> [Track] {
        tracksByLabelKey[name.lowercased()] ?? []
    }

    func tracks(forYear year: Int) -> [Track] {
        tracksByYear[year] ?? []
    }

    var selectedFolderRoot: FolderBookmark? {
        guard let rootID = folderNavigation.rootID else { return nil }
        return folders.first { $0.id == rootID }
    }

    var folderBrowseURL: URL? {
        guard let root = selectedFolderRoot,
              let rootURL = accessibleFolderURLs[root.id]
        else { return nil }
        return folderNavigation.pathComponents.reduce(rootURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
    }

    /// Contents of `folderBrowseURL`, filtered by the search query. Kept up to date by
    /// `refreshQueryResults()` so views never list a folder while rendering.
    private(set) var folderListing: [FolderBrowseEntry] = []

    var isFolderSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var filteredFolderRoots: [FolderBookmark] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return folders }
        return folders.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.displayPath.localizedCaseInsensitiveContains(q)
        }
    }

    var folderBreadcrumb: String {
        guard let root = selectedFolderRoot else { return "Directories" }
        return ([root.name] + folderNavigation.pathComponents).joined(separator: " / ")
    }

    init() {
        Task { await bootstrap() }
    }

    /// Force a full metadata re-read of every connected directory.
    func rebuildIndex() {
        Task { await refreshIndex(force: true) }
    }

    func setBrowseMode(_ mode: CatalogueBrowseMode) {
        browseMode = mode
        if mode == .folders, folderNavigation.rootID == nil, let first = folders.first {
            folderNavigation.open(root: first.id)
        }
    }

    // MARK: - Folder navigation

    func openFolderRoot(_ bookmark: FolderBookmark) {
        folderNavigation.open(root: bookmark.id)
    }

    func enterFolder(_ entry: FolderBrowseEntry) {
        guard entry.isDirectory else { return }
        folderNavigation.enter(entry.name)
    }

    func folderGoUp() {
        folderNavigation.goUp()
    }

    /// Jump to a breadcrumb segment: `0` = shelf root, `n` = first `n` path components.
    func navigateFolderBreadcrumb(depth: Int) {
        guard selectedFolderRoot != nil else { return }
        folderNavigation.jump(toDepth: depth)
    }

    /// Open the folder that contains `url` (file or directory) inside Folder mode.
    func revealInFolders(url: URL) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        let targetPath = (isDirectory ? url : url.deletingLastPathComponent()).path

        guard let root = folders.first(where: {
            guard let rootURL = accessibleFolderURLs[$0.id] else { return false }
            return targetPath.hasPrefix(rootURL.path)
        }),
              let rootURL = accessibleFolderURLs[root.id]
        else { return }

        let relative = targetPath.dropFirst(normalizedPath(rootURL.path).count)
        folderNavigation.show(relative.split(separator: "/").map(String.init), in: root.id)
    }

    func resetFolderBrowseToRoots() {
        folderNavigation.reset()
    }

    private func relativePath(for url: URL, under root: FolderBookmark) -> String {
        guard let rootURL = accessibleFolderURLs[root.id] else {
            return url.lastPathComponent
        }
        let rootPath = normalizedPath(rootURL.path)
        let full = url.path
        guard full.hasPrefix(rootPath) else { return url.lastPathComponent }
        let relative = String(full.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? root.name : "\(root.name)/\(relative)"
    }

    // MARK: - Playback queues

    /// Prefer indexed metadata; fall back to a lightweight file-based track.
    private func trackForPlayback(at url: URL, identity: String? = nil) -> Track {
        if let identity, let existing = tracksByPath[identity] {
            return existing
        }
        if let existing = tracksByPath[url.path] {
            return existing
        }
        let siblings = tracksInContainer(at: url)
        if let first = siblings.first {
            return first
        }
        let format = AudioFormat.infer(from: url)
        return labeled(
            Track(
                title: url.deletingPathExtension().lastPathComponent,
                artist: "Unknown Artist",
                album: "Unknown Album",
                duration: 0,
                format: format,
                url: url
            )
        )
    }

    /// Queue = audio files in the same folder, in listing order.
    func folderPlaybackQueue(startingAt url: URL, identity: String? = nil) -> (track: Track, queue: [Track]) {
        let container = tracksInContainer(at: url)
        if container.count > 1 || container.first.map({ VirtualTrackPath.isVirtual($0.cataloguePath) }) == true {
            let track = identity.flatMap { id in container.first { $0.cataloguePath == id } }
                ?? container.first
                ?? trackForPlayback(at: url, identity: identity)
            return (track, container)
        }
        let directory = url.deletingLastPathComponent()
        let queue = listFolderContents(at: directory).compactMap(\.track)
        let track = identity.flatMap { id in queue.first { $0.cataloguePath == id } }
            ?? queue.first(where: { $0.url.path == url.path })
            ?? trackForPlayback(at: url, identity: identity)
        return (track, queue.isEmpty ? [track] : queue)
    }

    private func tracksInContainer(at url: URL) -> [Track] {
        tracks
            .filter { $0.url.path == url.path }
            .sorted { ($0.trackNumber ?? 9999) < ($1.trackNumber ?? 9999) }
    }

    /// Immediate files in `url`, or every indexed track under it if the folder only has albums.
    func directoryPlaybackQueue(at url: URL) -> (track: Track, queue: [Track])? {
        let parentPath = normalizedPath(url.path)
        let immediate = (tracksByParent[parentPath] ?? []).sorted(by: Self.sortFolderTracks)
        if let first = immediate.first {
            return (first, immediate)
        }

        let prefix = normalizedPrefix(url.path)
        let nested = tracks
            .filter { $0.url.path.hasPrefix(prefix) }
            .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        guard let first = nested.first else { return nil }
        return (first, nested)
    }

    // MARK: - Labels

    func addLabel(_ label: String, to track: Track) {
        guard labelStore.add(label, to: track) else { return }
        labelsDidChange(for: track)
    }

    func removeLabel(_ label: String, from track: Track) {
        labelStore.remove(label, from: track)
        labelsDidChange(for: track)
    }

    func setLabels(_ labels: [String], for track: Track) {
        labelStore.set(labels, for: track)
        labelsDidChange(for: track)
    }

    /// Re-apply stored labels to the catalogue and mirror the edited track's labels into SQLite.
    private func labelsDidChange(for track: Track) {
        tracks = tracks.map(labeled)
        catalogueDidChange()

        let path = track.cataloguePath
        let labels = labelStore.labels(forPath: path)
        Task { await CatalogueIndexStore.shared.updateLabels(path: path, labels: labels) }
    }

    private func labeled(_ track: Track) -> Track {
        var copy = track
        copy.labels = labelStore.labels(forPath: track.cataloguePath)
        return copy
    }

    // MARK: - Connected directories
    func addFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.title = "Add Music Directories"
        panel.message = "Choose one or more directories with your audio files."
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            for url in panel.urls {
                claimPickerURL(url)
            }
        }
        #endif
    }

    func addFolders(urls: [URL]) {
        for url in urls {
            claimPickerURL(url)
        }
    }

    /// Document-picker URLs die unless security scope starts in the callback, before any `Task`.
    private func claimPickerURL(_ url: URL) {
        let started = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if started {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            await ingestFolder(url: url)
        }
    }

    func removeFolder(_ bookmark: FolderBookmark) {
        Task {
            await BookmarkStore.shared.stopAccess(for: bookmark.id)
            accessibleFolderURLs.removeValue(forKey: bookmark.id)
            folders.removeAll { $0.id == bookmark.id }
            if folderNavigation.rootID == bookmark.id {
                resetFolderBrowseToRoots()
            }
            await BookmarkStore.shared.save(folders)
            let path = bookmark.displayPath
            await CatalogueIndexStore.shared.delete(underPrefix: path)
            let remaining = await CatalogueIndexStore.shared.loadAll()
            if remaining.isEmpty {
                showsDemoLibrary = true
                loadDemoLibrary()
            } else {
                showsDemoLibrary = false
                await applyIndexedRecords(remaining)
            }
        }
    }

    // MARK: - Folder listing

    private func listFolderContents(at url: URL) -> [FolderBrowseEntry] {
        let parentPath = normalizedPath(url.path)
        let parentPrefix = normalizedPrefix(url.path)
        let dirNames = immediateChildDirectoryNamesContainingAudio(under: url)
        let indexedFiles = tracksByParent[parentPath] ?? []
        let parentIndexed = !indexedFiles.isEmpty || tracks.contains { $0.url.path.hasPrefix(parentPrefix) }

        if parentIndexed || !dirNames.isEmpty {
            let directories = dirNames.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }.map { name in
                FolderBrowseEntry(
                    name: name,
                    url: url.appendingPathComponent(name, isDirectory: true),
                    kind: .directory
                )
            }
            let files = indexedFiles
                .sorted(by: Self.sortFolderTracks)
                .map { track in
                    FolderBrowseEntry(
                        name: track.folderDisplayName,
                        url: track.url,
                        kind: .audioFile(track),
                        id: track.cataloguePath
                    )
                }
            return directories + files
        }

        let onDisk = FolderDiskScanner.listContents(at: url)
        let directories = onDisk.directories.map {
            FolderBrowseEntry(name: $0.lastPathComponent, url: $0, kind: .directory)
        }
        let files = onDisk.audioFiles.map {
            FolderBrowseEntry(name: $0.lastPathComponent, url: $0, kind: .audioFile(trackForPlayback(at: $0)))
        }
        return directories + files
    }

    /// Names of immediate subfolders of `parent` that contain supported audio somewhere below.
    private func immediateChildDirectoryNamesContainingAudio(under parent: URL) -> Set<String> {
        let prefix = normalizedPrefix(parent.path)
        var names = Set<String>()
        for track in tracks where track.url.path.hasPrefix(prefix) {
            let relative = String(track.url.path.dropFirst(prefix.count))
            let parts = relative.split(separator: "/", omittingEmptySubsequences: true)
            // Need a subdirectory component before the file name.
            guard parts.count >= 2 else { continue }
            names.insert(String(parts[0]))
        }
        return names
    }

    // MARK: - Indexing

    private func bootstrap() async {
        let stored = await BookmarkStore.shared.load()
        folders = stored
        for bookmark in stored {
            do {
                let url = try await BookmarkStore.shared.startAccess(for: bookmark)
                accessibleFolderURLs[bookmark.id] = url
            } catch {
                scanProgressText = error.localizedDescription
            }
        }

        let indexed = await CatalogueIndexStore.shared.loadAll()
        if !indexed.isEmpty {
            showsDemoLibrary = false
            await applyIndexedRecords(indexed)
            await refreshIndex(force: false)
        } else if !accessibleFolderURLs.isEmpty {
            showsDemoLibrary = false
            await refreshIndex(force: true)
        } else {
            showsDemoLibrary = true
            loadDemoLibrary()
        }
    }

    private func ingestFolder(url: URL) async {
        do {
            let bookmark = try await BookmarkStore.shared.makeBookmark(for: url)
            let accessed = try await BookmarkStore.shared.startAccess(for: bookmark)
            if !folders.contains(where: { $0.displayPath == bookmark.displayPath }) {
                folders.append(bookmark)
                await BookmarkStore.shared.save(folders)
            }
            accessibleFolderURLs[bookmark.id] = accessed
            await ICloudItem.ensureDownloaded(accessed)
            await refreshIndex(force: false)
        } catch {
            scanProgressText = error.localizedDescription
        }
    }

    private func refreshIndex(force: Bool) async {
        let roots = folders.compactMap { accessibleFolderURLs[$0.id] }
        guard !roots.isEmpty else { return }

        isScanning = true
        scanProgressText = force ? "Building catalogue index…" : "Checking catalogue…"
        defer {
            isScanning = false
            scanProgressText = nil
        }

        let files = await Task.detached(priority: .userInitiated) {
            CatalogueIndexer.enumerateAudioFiles(in: roots)
        }.value

        let existing = await CatalogueIndexStore.shared.fingerprints()
        let plan = CatalogueIndexer.plan(files: files, existing: existing, force: force)

        if !plan.staleVirtual.isEmpty {
            await CatalogueIndexStore.shared.delete(paths: plan.staleVirtual)
        }

        if !plan.toRead.isEmpty {
            let verb = force ? "Indexing" : "Updating"
            scanProgressText = "\(verb) 0/\(plan.toRead.count)…"
            let records = await CatalogueIndexer.readMetadata(
                files: plan.toRead,
                labelsByPath: labelStore.labelsByPath
            ) { done, total in
                await MainActor.run { [weak self] in
                    self?.scanProgressText = "\(verb) \(done)/\(total)…"
                }
            }
            let leftoverContainers = Set(
                records
                    .filter { VirtualTrackPath.isVirtual($0.path) }
                    .map { VirtualTrackPath.filePath(from: $0.path) }
            )
            if !leftoverContainers.isEmpty {
                await CatalogueIndexStore.shared.delete(paths: Array(leftoverContainers))
            }
            await CatalogueIndexStore.shared.upsert(records)
        }

        if !plan.toDelete.isEmpty {
            await CatalogueIndexStore.shared.delete(paths: plan.toDelete)
        }

        let loaded = await CatalogueIndexStore.shared.loadAll()
        if loaded.isEmpty {
            showsDemoLibrary = true
            loadDemoLibrary()
        } else {
            showsDemoLibrary = false
            await applyIndexedRecords(loaded)
            let hashes = await CatalogueIndexStore.shared.artworkHashes()
            ArtworkCache.shared.removeUnreferenced(keeping: hashes)
        }
    }

    private func applyIndexedRecords(_ records: [IndexedTrackRecord]) async {
        tracks = records.map { $0.asTrack(labelsByPath: labelStore.labelsByPath) }
        reindexLookups()
        let snapshot = tracks
        albums = await Task.detached(priority: .userInitiated) {
            LibraryService.makeAlbums(from: snapshot)
        }.value
        rebuildFacets()
        refreshQueryResults()
    }

    // MARK: - Derived state

    /// Rebuild every lookup, album, facet and search hit from `tracks`.
    private func catalogueDidChange() {
        reindexLookups()
        rebuildAlbums()
        rebuildFacets()
        refreshQueryResults()
    }

    private func reindexLookups() {
        tracksByPath = Dictionary(tracks.map { ($0.cataloguePath, $0) }, uniquingKeysWith: { _, last in last })
        tracksByParent = Dictionary(grouping: tracks) { $0.url.deletingLastPathComponent().path }
        searchIndex.rebuild(from: tracks)
        indexedTrackCount = showsDemoLibrary ? 0 : tracks.count
        rebuildDirectoryCatalog()
    }

    private func rebuildAlbums() {
        albums = Self.makeAlbums(from: tracks)
    }

    nonisolated private static func makeAlbums(from tracks: [Track]) -> [Album] {
        Dictionary(grouping: tracks) { track -> String in
            if CatalogueUnknown.isAlbum(track.album) { return "unknown|" }
            return "\(track.album)|\(track.artist)"
        }
            .values
            .map { list in
                let first = list[0]
                let unknownAlbum = CatalogueUnknown.isAlbum(first.album)
                return Album(
                    title: unknownAlbum ? CatalogueUnknown.display : first.album,
                    artist: unknownAlbum ? CatalogueUnknown.display : first.artist,
                    year: unknownAlbum ? nil : first.year,
                    tracks: list.sorted { ($0.trackNumber ?? 9999) < ($1.trackNumber ?? 9999) },
                    artworkHash: list.first(where: { $0.artworkHash != nil })?.artworkHash
                )
            }
            .sorted { lhs, rhs in
                if CatalogueUnknown.isAlbum(lhs.title) { return false }
                if CatalogueUnknown.isAlbum(rhs.title) { return true }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    nonisolated private static func sortFolderTracks(_ lhs: Track, _ rhs: Track) -> Bool {
        if lhs.url.path == rhs.url.path {
            let left = lhs.trackNumber ?? 9999
            let right = rhs.trackNumber ?? 9999
            if left != right { return left < right }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
    }

    private func rebuildFacets() {
        var artists: [String: [Track]] = [:]
        var labels: [String: [Track]] = [:]
        var years: [Int: [Track]] = [:]
        artists.reserveCapacity(256)
        labels.reserveCapacity(64)
        years.reserveCapacity(64)

        for track in tracks {
            let artistKey = CatalogueUnknown.isArtist(track.artist)
                ? "unknown"
                : track.artist.lowercased()
            artists[artistKey, default: []].append(track)
            for label in track.labels {
                labels[label.lowercased(), default: []].append(track)
            }
            if let year = track.year {
                years[year, default: []].append(track)
            }
        }

        func sortAlbumThenTrack(_ lhs: Track, _ rhs: Track) -> Bool {
            let album = lhs.album.localizedCaseInsensitiveCompare(rhs.album)
            if album != .orderedSame { return album == .orderedAscending }
            return (lhs.trackNumber ?? 9999) < (rhs.trackNumber ?? 9999)
        }

        func sortArtistThenAlbum(_ lhs: Track, _ rhs: Track) -> Bool {
            let artist = lhs.artist.localizedCaseInsensitiveCompare(rhs.artist)
            if artist != .orderedSame { return artist == .orderedAscending }
            return lhs.album.localizedCaseInsensitiveCompare(rhs.album) == .orderedAscending
        }

        for key in artists.keys { artists[key]?.sort(by: sortAlbumThenTrack) }
        for key in labels.keys { labels[key]?.sort(by: sortArtistThenAlbum) }
        for key in years.keys { years[key]?.sort(by: sortArtistThenAlbum) }

        tracksByArtistKey = artists
        tracksByLabelKey = labels
        tracksByYear = years

        artistFacets = artists.map { key, group in
            let name = key == "unknown"
                ? CatalogueUnknown.display
                : (group.first?.artist ?? key)
            return LibraryFacet(id: "artist-\(key)", name: name, count: group.count)
        }
        .sorted { lhs, rhs in
            if CatalogueUnknown.isArtist(lhs.name) { return false }
            if CatalogueUnknown.isArtist(rhs.name) { return true }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        labelFacets = labels.map { key, group in
            let name = group.flatMap(\.labels).first { $0.lowercased() == key } ?? key
            return LibraryFacet(id: "label-\(name)", name: name, count: group.count)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        yearFacets = years.keys.sorted(by: >).map { year in
            LibraryFacet(id: "year-\(year)", name: String(year), count: years[year]?.count ?? 0)
        }
    }

    // MARK: - Search

    /// Recompute everything that depends on the search query, folder location or catalogue.
    private func refreshQueryResults() {
        refreshSearchHits()
        refreshFolderListing()
    }

    private func refreshFolderListing() {
        guard let url = folderBrowseURL else {
            folderListing = []
            return
        }
        let listing = listFolderContents(at: url)
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        folderListing = q.isEmpty ? listing : listing.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private func refreshSearchHits() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchHitPaths = nil
            folderSearchHits = []
            return
        }
        if let indices = searchIndex.matchingIndices(query: q, trackCount: tracks.count) {
            searchHitPaths = Set(indices.compactMap { tracks.indices.contains($0) ? tracks[$0].cataloguePath : nil })
        } else {
            searchHitPaths = []
        }
        folderSearchHits = computeFolderHits(query: q)
    }

    private func computeFolderHits(query: String) -> [FolderSearchHit] {
        let scopes: [(root: FolderBookmark, base: URL)]
        if let root = selectedFolderRoot, let base = folderBrowseURL {
            scopes = [(root, base)]
        } else {
            scopes = folders.compactMap { bookmark in
                guard let url = accessibleFolderURLs[bookmark.id] else { return nil }
                return (bookmark, url)
            }
        }

        var hits: [FolderSearchHit] = []
        var seen = Set<String>()
        let matchingTracks: [Track]
        if let paths = searchHitPaths {
            matchingTracks = paths.compactMap { tracksByPath[$0] }
        } else {
            matchingTracks = []
        }

        for (root, base) in scopes {
            let prefix = normalizedPrefix(base.path)
            for track in matchingTracks where track.url.path.hasPrefix(prefix) {
                guard seen.insert(track.cataloguePath).inserted else { continue }
                hits.append(
                    FolderSearchHit(
                        entry: FolderBrowseEntry(
                            name: track.folderDisplayName,
                            url: track.url,
                            kind: .audioFile(track),
                            id: track.cataloguePath
                        ),
                        relativePath: relativePath(for: track.url, under: root)
                    )
                )
            }

            for path in indexedDirectoryPaths where path.hasPrefix(prefix) {
                let url = URL(fileURLWithPath: path, isDirectory: true)
                guard url.lastPathComponent.localizedCaseInsensitiveContains(query) else { continue }
                guard seen.insert(path).inserted else { continue }
                hits.append(
                    FolderSearchHit(
                        entry: FolderBrowseEntry(name: url.lastPathComponent, url: url, kind: .directory),
                        relativePath: relativePath(for: url, under: root)
                    )
                )
            }
        }

        return hits.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    private func rebuildDirectoryCatalog() {
        var dirs = Set<String>()
        dirs.reserveCapacity(tracks.count)
        for track in tracks {
            var directory = track.url.deletingLastPathComponent()
            while directory.path.count > 1 {
                if !dirs.insert(directory.path).inserted { break }
                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path { break }
                directory = parent
            }
        }
        indexedDirectoryPaths = Array(dirs)
    }

    private func normalizedPath(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func normalizedPrefix(_ path: String) -> String {
        normalizedPath(path) + "/"
    }

    private func loadDemoLibrary() {
        guard showsDemoLibrary else { return }
        tracks = DemoLibrary.tracks
        catalogueDidChange()
    }
}
