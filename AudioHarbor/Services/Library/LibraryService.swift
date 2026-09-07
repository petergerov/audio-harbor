import Foundation
import Observation
import SQLite3

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
    var searchQuery = ""
    var showsDemoLibrary = true

    /// Smart (metadata albums) vs Folders (filesystem tree).
    var browseMode: CatalogueBrowseMode = {
        let raw = UserDefaults.standard.string(forKey: "audioharbor.catalogue.browseMode") ?? ""
        return CatalogueBrowseMode(rawValue: raw) ?? .smart
    }() {
        didSet {
            UserDefaults.standard.set(browseMode.rawValue, forKey: "audioharbor.catalogue.browseMode")
        }
    }

    /// Selected shelf root while browsing folders (`nil` = root picker).
    var folderRootID: UUID?
    /// Relative path components under the selected root.
    var folderPathComponents: [String] = []

    /// Resolved URLs currently held open via security scope.
    private(set) var accessibleFolderURLs: [UUID: URL] = [:]

    /// User labels keyed by absolute file path (survives track ID churn on rescan).
    private var labelsByPath: [String: [String]] = [:]
    private let labelsKey = "audioharbor.trackLabels"

    private var tracksByPath: [String: Track] = [:]
    private var tracksByParent: [String: [Track]] = [:]
    private var searchIndex = CatalogueSearchIndex()
    private(set) var indexedTrackCount = 0

    private static let audioExtensions = CatalogueIndexer.audioExtensions

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

    var allArtists: [String] {
        Array(Set(tracks.map(\.artist).filter { !$0.isEmpty && $0 != "Unknown Artist" }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var allYears: [Int] {
        Array(Set(tracks.compactMap(\.year))).sorted(by: >)
    }

    var allLabels: [String] {
        Array(Set(tracks.flatMap(\.labels)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var filteredAlbums: [Album] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return albums }
        guard let hits = searchIndex.matchingIndices(query: q, trackCount: tracks.count) else {
            return albums
        }
        let paths = Set(hits.compactMap { tracks.indices.contains($0) ? tracks[$0].url.path : nil })
        return albums.filter { album in
            album.tracks.contains { paths.contains($0.url.path) }
        }
    }

    var selectedFolderRoot: FolderBookmark? {
        guard let folderRootID else { return nil }
        return folders.first { $0.id == folderRootID }
    }

    var folderBrowseURL: URL? {
        guard let root = selectedFolderRoot,
              let rootURL = accessibleFolderURLs[root.id]
        else { return nil }
        return folderPathComponents.reduce(rootURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
    }

    var folderListing: [FolderBrowseEntry] {
        guard let url = folderBrowseURL else { return [] }
        let listing = listFolderContents(at: url)
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return listing }
        return listing.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

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

    /// Recursive hits under the current directory scope (or all roots at picker).
    var folderSearchHits: [FolderSearchHit] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

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
        if let indices = searchIndex.matchingIndices(query: q, trackCount: tracks.count) {
            matchingTracks = indices.compactMap { tracks.indices.contains($0) ? tracks[$0] : nil }
        } else {
            matchingTracks = []
        }

        for (root, base) in scopes {
            let prefix = normalizedPrefix(base.path)
            for track in matchingTracks where track.url.path.hasPrefix(prefix) {
                guard seen.insert(track.url.path).inserted else { continue }
                hits.append(
                    FolderSearchHit(
                        entry: FolderBrowseEntry(name: track.url.lastPathComponent, url: track.url, kind: .audioFile),
                        relativePath: relativePath(for: track.url, under: root)
                    )
                )
            }

            for directory in indexedDirectories(under: base) {
                guard directory.lastPathComponent.localizedCaseInsensitiveContains(q) else { continue }
                guard seen.insert(directory.path).inserted else { continue }
                hits.append(
                    FolderSearchHit(
                        entry: FolderBrowseEntry(name: directory.lastPathComponent, url: directory, kind: .directory),
                        relativePath: relativePath(for: directory, under: root)
                    )
                )
            }
        }

        return hits.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    var folderBreadcrumb: String {
        guard let root = selectedFolderRoot else { return "Directories" }
        if folderPathComponents.isEmpty { return root.name }
        return ([root.name] + folderPathComponents).joined(separator: " / ")
    }

    init() {
        loadLabels()
        Task { await bootstrap() }
    }

    /// Force a full metadata re-read of every connected directory.
    func rebuildIndex() {
        Task { await refreshIndex(force: true) }
    }

    func setBrowseMode(_ mode: CatalogueBrowseMode) {
        browseMode = mode
        if mode == .folders, folderRootID == nil, let first = folders.first {
            folderRootID = first.id
            folderPathComponents = []
        }
    }

    func openFolderRoot(_ bookmark: FolderBookmark) {
        folderRootID = bookmark.id
        folderPathComponents = []
    }

    func enterFolder(_ entry: FolderBrowseEntry) {
        guard entry.kind == .directory else { return }
        folderPathComponents.append(entry.name)
    }

    func folderGoUp() {
        if !folderPathComponents.isEmpty {
            folderPathComponents.removeLast()
        } else {
            folderRootID = nil
        }
    }

    /// Jump to a breadcrumb segment: `0` = shelf root, `n` = first `n` path components.
    func navigateFolderBreadcrumb(depth: Int) {
        guard selectedFolderRoot != nil else { return }
        let clamped = max(0, min(depth, folderPathComponents.count))
        folderPathComponents = Array(folderPathComponents.prefix(clamped))
    }

    /// Open the folder that contains `url` (file or directory) inside Folder mode.
    func revealInFolders(url: URL) {
        let targetDirectory: URL = {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            return isDir ? url : url.deletingLastPathComponent()
        }()

        guard let root = folders.first(where: {
            guard let rootURL = accessibleFolderURLs[$0.id] else { return false }
            return targetDirectory.path.hasPrefix(rootURL.path)
        }),
              let rootURL = accessibleFolderURLs[root.id]
        else { return }

        folderRootID = root.id
        let rootPath = rootURL.path.hasSuffix("/") ? String(rootURL.path.dropLast()) : rootURL.path
        let targetPath = targetDirectory.path
        guard targetPath.count > rootPath.count else {
            folderPathComponents = []
            return
        }
        let relative = String(targetPath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        folderPathComponents = relative.isEmpty ? [] : relative.split(separator: "/").map(String.init)
    }

    func resetFolderBrowseToRoots() {
        folderRootID = nil
        folderPathComponents = []
    }

    private func relativePath(for url: URL, under root: FolderBookmark) -> String {
        guard let rootURL = accessibleFolderURLs[root.id] else {
            return url.lastPathComponent
        }
        let rootPath = rootURL.path.hasSuffix("/") ? String(rootURL.path.dropLast()) : rootURL.path
        let full = url.path
        guard full.hasPrefix(rootPath) else { return url.lastPathComponent }
        let relative = String(full.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? root.name : "\(root.name)/\(relative)"
    }

    /// Prefer indexed metadata; fall back to a lightweight file-based track.
    func trackForPlayback(at url: URL) -> Track {
        if let existing = tracksByPath[url.path] {
            return existing
        }
        let format = AudioFormat.infer(from: url)
        return labeled(
            Track(
                title: url.deletingPathExtension().lastPathComponent,
                artist: "Unknown Artist",
                album: url.deletingLastPathComponent().lastPathComponent,
                duration: 0,
                format: format,
                url: url
            )
        )
    }

    /// Queue = audio files in the same folder, in listing order.
    func folderPlaybackQueue(startingAt url: URL) -> (track: Track, queue: [Track]) {
        let directory = url.deletingLastPathComponent()
        let files = listFolderContents(at: directory)
            .filter { $0.kind == .audioFile }
            .map(\.url)
        let queue = files.map { trackForPlayback(at: $0) }
        let track = queue.first(where: { $0.url.path == url.path }) ?? trackForPlayback(at: url)
        return (track, queue.isEmpty ? [track] : queue)
    }

    func addLabel(_ label: String, to track: Track) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = labelsByPath[track.url.path] ?? track.labels
        guard !current.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        current.append(trimmed)
        labelsByPath[track.url.path] = current.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        saveLabels()
        applyStoredLabelsToTracks()
        persistLabels(for: track.url.path)
    }

    func removeLabel(_ label: String, from track: Track) {
        var current = labelsByPath[track.url.path] ?? track.labels
        current.removeAll { $0.caseInsensitiveCompare(label) == .orderedSame }
        if current.isEmpty {
            labelsByPath.removeValue(forKey: track.url.path)
        } else {
            labelsByPath[track.url.path] = current
        }
        saveLabels()
        applyStoredLabelsToTracks()
        persistLabels(for: track.url.path)
    }

    func setLabels(_ labels: [String], for track: Track) {
        let cleaned = Array(Set(labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if cleaned.isEmpty {
            labelsByPath.removeValue(forKey: track.url.path)
        } else {
            labelsByPath[track.url.path] = cleaned
        }
        saveLabels()
        applyStoredLabelsToTracks()
        persistLabels(for: track.url.path)
    }

    private func persistLabels(for path: String) {
        let labels = labelsByPath[path] ?? []
        Task { await CatalogueIndexStore.shared.updateLabels(path: path, labels: labels) }
    }

    private func applyStoredLabelsToTracks() {
        tracks = tracks.map { track in
            var copy = track
            copy.labels = labelsByPath[track.url.path] ?? []
            return copy
        }
        reindexLookups()
        rebuildAlbums()
    }

    private func labeled(_ track: Track) -> Track {
        var copy = track
        copy.labels = labelsByPath[track.url.path] ?? []
        return copy
    }

    private func loadLabels() {
        guard let data = UserDefaults.standard.data(forKey: labelsKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }
        labelsByPath = decoded
    }

    private func saveLabels() {
        if let data = try? JSONEncoder().encode(labelsByPath) {
            UserDefaults.standard.set(data, forKey: labelsKey)
        }
    }

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
                Task { await ingestFolder(url: url) }
            }
        }
        #endif
    }

    func addFolders(urls: [URL]) {
        for url in urls {
            Task { await ingestFolder(url: url) }
        }
    }

    func removeFolder(_ bookmark: FolderBookmark) {
        Task {
            await BookmarkStore.shared.stopAccess(for: bookmark.id)
            accessibleFolderURLs.removeValue(forKey: bookmark.id)
            folders.removeAll { $0.id == bookmark.id }
            if folderRootID == bookmark.id {
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
                applyIndexedRecords(remaining)
            }
        }
    }

    private func listFolderContents(at url: URL) -> [FolderBrowseEntry] {
        let parentPath = normalizedPath(url.path)
        let parentPrefix = parentPath + "/"
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
                .sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
                .map { track in
                    FolderBrowseEntry(name: track.url.lastPathComponent, url: track.url, kind: .audioFile)
                }
            return directories + files
        }

        return listFolderContentsFromDisk(at: url)
    }

    private func listFolderContentsFromDisk(at url: URL) -> [FolderBrowseEntry] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var directories: [FolderBrowseEntry] = []
        var files: [FolderBrowseEntry] = []

        for item in items {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if directoryContainsSupportedAudioOnDisk(item) {
                    directories.append(FolderBrowseEntry(name: item.lastPathComponent, url: item, kind: .directory))
                }
            } else if values?.isRegularFile == true,
                      Self.audioExtensions.contains(item.pathExtension.lowercased()) {
                files.append(FolderBrowseEntry(name: item.lastPathComponent, url: item, kind: .audioFile))
            }
        }

        directories.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return directories + files
    }

    /// Names of immediate subfolders of `parent` that contain supported audio somewhere below.
    private func immediateChildDirectoryNamesContainingAudio(under parent: URL) -> Set<String> {
        let parentPath = parent.path.hasSuffix("/") ? String(parent.path.dropLast()) : parent.path
        let prefix = parentPath + "/"
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

    private func directoryContainsSupportedAudio(_ url: URL) -> Bool {
        let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
        let prefix = path + "/"
        if tracks.contains(where: { $0.url.path.hasPrefix(prefix) }) {
            return true
        }
        // Index miss (demo / mid-scan): probe the disk once.
        return directoryContainsSupportedAudioOnDisk(url)
    }

    private func directoryContainsSupportedAudioOnDisk(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        while let fileURL = enumerator.nextObject() as? URL {
            if Self.audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                return true
            }
        }
        return false
    }

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
            applyIndexedRecords(indexed)
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

        if !plan.toRead.isEmpty {
            let verb = force ? "Indexing" : "Updating"
            scanProgressText = "\(verb) 0/\(plan.toRead.count)…"
            let records = await CatalogueIndexer.readMetadata(
                files: plan.toRead,
                labelsByPath: labelsByPath
            ) { done, total in
                await MainActor.run { [weak self] in
                    self?.scanProgressText = "\(verb) \(done)/\(total)…"
                }
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
            applyIndexedRecords(loaded)
            let hashes = await CatalogueIndexStore.shared.artworkHashes()
            ArtworkCache.shared.removeUnreferenced(keeping: hashes)
        }
    }

    private func applyIndexedRecords(_ records: [IndexedTrackRecord]) {
        tracks = records.map { $0.asTrack(labelsByPath: labelsByPath) }
        reindexLookups()
        rebuildAlbums()
    }

    private func reindexLookups() {
        tracksByPath = Dictionary(uniqueKeysWithValues: tracks.map { ($0.url.path, $0) })
        tracksByParent = Dictionary(grouping: tracks) { $0.url.deletingLastPathComponent().path }
        searchIndex.rebuild(from: tracks)
        indexedTrackCount = showsDemoLibrary ? 0 : tracks.count
    }

    private func rebuildAlbums() {
        let grouped = Dictionary(grouping: tracks) { "\($0.album)|\($0.artist)" }
        albums = grouped.values
            .map { list in
                let first = list[0]
                let art = list.lazy.compactMap { ArtworkCache.data(for: $0) }.first
                return Album(
                    title: first.album,
                    artist: first.artist,
                    year: first.year,
                    tracks: list.sorted { ($0.trackNumber ?? 9999) < ($1.trackNumber ?? 9999) },
                    artworkData: art
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func normalizedPath(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func normalizedPrefix(_ path: String) -> String {
        normalizedPath(path) + "/"
    }

    private func indexedDirectories(under base: URL) -> [URL] {
        let prefix = normalizedPrefix(base.path)
        var dirs = Set<String>()
        for track in tracks where track.url.path.hasPrefix(prefix) {
            var directory = track.url.deletingLastPathComponent()
            while directory.path.hasPrefix(prefix) || directory.path == normalizedPath(base.path) {
                if directory.path != normalizedPath(base.path) {
                    dirs.insert(directory.path)
                }
                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path { break }
                directory = parent
            }
        }
        return dirs.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func loadDemoLibrary() {
        guard showsDemoLibrary else { return }
        let demo = [
            Track(
                title: "Amber Signal",
                artist: "North Room",
                album: "Quiet Hours",
                trackNumber: 1,
                year: 2024,
                duration: 243,
                format: .flac,
                sampleRateHz: 96000,
                bitDepth: 24,
                url: URL(fileURLWithPath: "/demo/quiet-hours/01-amber-signal.flac")
            ),
            Track(
                title: "Glass Corridor",
                artist: "North Room",
                album: "Quiet Hours",
                trackNumber: 2,
                year: 2024,
                duration: 318,
                format: .flac,
                sampleRateHz: 96000,
                bitDepth: 24,
                url: URL(fileURLWithPath: "/demo/quiet-hours/02-glass-corridor.flac")
            ),
            Track(
                title: "Night Wire",
                artist: "Field Tape",
                album: "DSD Sampler",
                trackNumber: 1,
                year: 2023,
                duration: 401,
                format: .dsf,
                sampleRateHz: 2_822_400,
                bitDepth: 1,
                url: URL(fileURLWithPath: "/demo/dsd/night-wire.dsf")
            ),
            Track(
                title: "Harbor Light",
                artist: "Field Tape",
                album: "Analog Sketches",
                trackNumber: 3,
                year: 2022,
                duration: 276,
                format: .alac,
                sampleRateHz: 48000,
                bitDepth: 24,
                url: URL(fileURLWithPath: "/demo/analog/harbor-light.m4a")
            ),
        ]
        tracks = demo
        reindexLookups()
        rebuildAlbums()
    }
}

struct IndexedTrackRecord: Sendable {
    var path: String
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
    var fileSize: Int64
    var mtime: TimeInterval
    var artworkHash: String?
    var filename: String
    var labels: [String]

    func asTrack(labelsByPath: [String: [String]]) -> Track {
        Track(
            title: title,
            artist: artist,
            album: album,
            trackNumber: trackNumber,
            year: year,
            duration: duration,
            format: format,
            sampleRateHz: sampleRateHz,
            bitDepth: bitDepth,
            channelCount: channelCount,
            url: URL(fileURLWithPath: path),
            artworkHash: artworkHash,
            labels: labelsByPath[path] ?? labels
        )
    }
}

struct FileFingerprint: Sendable {
    var url: URL
    var path: String
    var fileSize: Int64
    var mtime: TimeInterval
}

struct StoredFingerprint: Sendable {
    var path: String
    var fileSize: Int64
    var mtime: TimeInterval
}

/// Persistent catalogue: WAL SQLite + FTS5, incremental by path/mtime/size.
actor CatalogueIndexStore {
    static let shared = CatalogueIndexStore()

    private var db: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let schemaVersion = "2"

    init() {
        db = Self.connect()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func loadAll() -> [IndexedTrackRecord] {
        guard let db else { return [] }
        let sql = """
        SELECT path, title, artist, album, track_number, year, duration, format,
               sample_rate, bit_depth, channel_count, file_size, mtime, artwork_hash, filename, labels
        FROM tracks
        ORDER BY artist COLLATE NOCASE, album COLLATE NOCASE, track_number ASC, title COLLATE NOCASE
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [IndexedTrackRecord] = []
        rows.reserveCapacity(4096)
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(record(from: stmt))
        }
        return rows
    }

    func fingerprints(underPrefix prefix: String? = nil) -> [String: StoredFingerprint] {
        guard let db else { return [:] }
        let sql: String
        if prefix != nil {
            sql = "SELECT path, file_size, mtime FROM tracks WHERE path LIKE ? ESCAPE '\\'"
        } else {
            sql = "SELECT path, file_size, mtime FROM tracks"
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [:] }
        defer { sqlite3_finalize(stmt) }
        if let prefix {
            bindText(stmt, 1, likePrefix(prefix))
        }

        var map: [String: StoredFingerprint] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = string(stmt, 0)
            map[path] = StoredFingerprint(
                path: path,
                fileSize: sqlite3_column_int64(stmt, 1),
                mtime: sqlite3_column_double(stmt, 2)
            )
        }
        return map
    }

    func upsert(_ records: [IndexedTrackRecord]) {
        guard let db, !records.isEmpty else { return }
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        let sql = """
        INSERT INTO tracks (
            path, title, artist, album, track_number, year, duration, format,
            sample_rate, bit_depth, channel_count, file_size, mtime, artwork_hash, filename, labels
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            title=excluded.title,
            artist=excluded.artist,
            album=excluded.album,
            track_number=excluded.track_number,
            year=excluded.year,
            duration=excluded.duration,
            format=excluded.format,
            sample_rate=excluded.sample_rate,
            bit_depth=excluded.bit_depth,
            channel_count=excluded.channel_count,
            file_size=excluded.file_size,
            mtime=excluded.mtime,
            artwork_hash=excluded.artwork_hash,
            filename=excluded.filename,
            labels=excluded.labels
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }

        for record in records {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            bindText(stmt, 1, record.path)
            bindText(stmt, 2, record.title)
            bindText(stmt, 3, record.artist)
            bindText(stmt, 4, record.album)
            bindOptionalInt(stmt, 5, record.trackNumber)
            bindOptionalInt(stmt, 6, record.year)
            sqlite3_bind_double(stmt, 7, record.duration)
            bindText(stmt, 8, record.format.rawValue)
            bindOptionalInt(stmt, 9, record.sampleRateHz)
            bindOptionalInt(stmt, 10, record.bitDepth)
            bindOptionalInt(stmt, 11, record.channelCount)
            sqlite3_bind_int64(stmt, 12, record.fileSize)
            sqlite3_bind_double(stmt, 13, record.mtime)
            if let hash = record.artworkHash {
                bindText(stmt, 14, hash)
            } else {
                sqlite3_bind_null(stmt, 14)
            }
            bindText(stmt, 15, record.filename)
            bindText(stmt, 16, encodeLabels(record.labels))
            sqlite3_step(stmt)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    func delete(paths: [String]) {
        guard let db, !paths.isEmpty else { return }
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM tracks WHERE path = ?", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        defer { sqlite3_finalize(stmt) }
        for path in paths {
            sqlite3_reset(stmt)
            bindText(stmt, 1, path)
            sqlite3_step(stmt)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    func delete(underPrefix prefix: String) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM tracks WHERE path LIKE ? ESCAPE '\\'", -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, likePrefix(prefix))
        sqlite3_step(stmt)
    }

    func updateLabels(path: String, labels: [String]) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE tracks SET labels = ? WHERE path = ?", -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, encodeLabels(labels))
        bindText(stmt, 2, path)
        sqlite3_step(stmt)
    }

    func searchPaths(query: String) -> [String] {
        let fts = Self.ftsQuery(from: query)
        guard let db, let fts else { return [] }
        let sql = """
        SELECT t.path
        FROM tracks_fts
        JOIN tracks t ON t.rowid = tracks_fts.rowid
        WHERE tracks_fts MATCH ?
        ORDER BY rank
        LIMIT 2000
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, fts)

        var paths: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            paths.append(string(stmt, 0))
        }
        return paths
    }

    func trackCount() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM tracks", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func artworkHashes() -> Set<String> {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT DISTINCT artwork_hash FROM tracks WHERE artwork_hash IS NOT NULL", -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        var hashes = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            hashes.insert(string(stmt, 0))
        }
        return hashes
    }

    private static func connect() -> OpaquePointer? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("AudioHarbor", isDirectory: true)
            .appendingPathComponent("CatalogueIndex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("catalogue.sqlite")

        var db: OpaquePointer?
        if sqlite3_open_v2(
            url.path,
            &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) != SQLITE_OK {
            if let db { sqlite3_close(db) }
            return nil
        }

        applyPragmas(db)
        if !migrateIfNeeded(db) {
            sqlite3_close(db)
            db = nil
            try? FileManager.default.removeItem(at: url)
            if sqlite3_open_v2(
                url.path,
                &db,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            ) != SQLITE_OK {
                if let db { sqlite3_close(db) }
                return nil
            }
            applyPragmas(db)
            _ = migrateIfNeeded(db)
        }
        return db
    }

    private static func applyPragmas(_ db: OpaquePointer?) {
        guard let db else { return }
        sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous = NORMAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA temp_store = MEMORY", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA cache_size = -16000", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA mmap_size = 268435456", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
    }

    private static func migrateIfNeeded(_ db: OpaquePointer?) -> Bool {
        guard let db else { return false }
        sqlite3_exec(
            db,
            "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)",
            nil, nil, nil
        )
        let version = metaValue(db, "schema_version")
        if version == schemaVersion {
            return true
        }
        if version != nil {
            sqlite3_exec(db, "DROP TABLE IF EXISTS tracks_fts", nil, nil, nil)
            sqlite3_exec(db, "DROP TABLE IF EXISTS tracks", nil, nil, nil)
        }
        return createSchema(db)
    }

    private static func createSchema(_ db: OpaquePointer?) -> Bool {
        guard let db else { return false }
        let ddl = """
        CREATE TABLE IF NOT EXISTS tracks (
            path TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT NOT NULL,
            track_number INTEGER,
            year INTEGER,
            duration REAL NOT NULL,
            format TEXT NOT NULL,
            sample_rate INTEGER,
            bit_depth INTEGER,
            channel_count INTEGER,
            file_size INTEGER NOT NULL,
            mtime REAL NOT NULL,
            artwork_hash TEXT,
            filename TEXT NOT NULL,
            labels TEXT NOT NULL DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS idx_tracks_album_artist ON tracks(album, artist);
        CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist);
        CREATE INDEX IF NOT EXISTS idx_tracks_filename ON tracks(filename);
        CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5(
            title, artist, album, filename, labels,
            content='tracks',
            content_rowid='rowid',
            tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER IF NOT EXISTS tracks_ai AFTER INSERT ON tracks BEGIN
            INSERT INTO tracks_fts(rowid, title, artist, album, filename, labels)
            VALUES (new.rowid, new.title, new.artist, new.album, new.filename, new.labels);
        END;
        CREATE TRIGGER IF NOT EXISTS tracks_ad AFTER DELETE ON tracks BEGIN
            INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album, filename, labels)
            VALUES ('delete', old.rowid, old.title, old.artist, old.album, old.filename, old.labels);
        END;
        CREATE TRIGGER IF NOT EXISTS tracks_au AFTER UPDATE ON tracks BEGIN
            INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album, filename, labels)
            VALUES ('delete', old.rowid, old.title, old.artist, old.album, old.filename, old.labels);
            INSERT INTO tracks_fts(rowid, title, artist, album, filename, labels)
            VALUES (new.rowid, new.title, new.artist, new.album, new.filename, new.labels);
        END;
        """
        guard sqlite3_exec(db, ddl, nil, nil, nil) == SQLITE_OK else { return false }
        setMeta(db, "schema_version", schemaVersion)
        return true
    }

    private static func metaValue(_ db: OpaquePointer?, _ key: String) -> String? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = ?", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    private static func setMeta(_ db: OpaquePointer?, _ key: String, _ value: String) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, key, -1, transient)
        sqlite3_bind_text(stmt, 2, value, -1, transient)
        sqlite3_step(stmt)
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
    }

    private func bindOptionalInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int64(stmt, index, Int64(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func string(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    private func optionalString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let c = sqlite3_column_text(stmt, index)
        else { return nil }
        return String(cString: c)
    }

    private func optionalInt(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, index))
    }

    private func record(from stmt: OpaquePointer?) -> IndexedTrackRecord {
        IndexedTrackRecord(
            path: string(stmt, 0),
            title: string(stmt, 1),
            artist: string(stmt, 2),
            album: string(stmt, 3),
            trackNumber: optionalInt(stmt, 4),
            year: optionalInt(stmt, 5),
            duration: sqlite3_column_double(stmt, 6),
            format: AudioFormat(rawValue: string(stmt, 7)) ?? .unknown,
            sampleRateHz: optionalInt(stmt, 8),
            bitDepth: optionalInt(stmt, 9),
            channelCount: optionalInt(stmt, 10),
            fileSize: sqlite3_column_int64(stmt, 11),
            mtime: sqlite3_column_double(stmt, 12),
            artworkHash: optionalString(stmt, 13),
            filename: string(stmt, 14),
            labels: decodeLabels(string(stmt, 15))
        )
    }

    private func likePrefix(_ path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "\(escaped)/%"
    }

    private func encodeLabels(_ labels: [String]) -> String {
        labels.joined(separator: "\u{1f}")
    }

    private func decodeLabels(_ raw: String) -> [String] {
        raw.split(separator: "\u{1f}", omittingEmptySubsequences: true).map(String.init)
    }

    static func ftsQuery(from raw: String) -> String? {
        let tokens = raw
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens
            .map { token in
                let cleaned = token.replacingOccurrences(of: "\"", with: "")
                return "\"\(cleaned)\"*"
            }
            .joined(separator: " ")
    }
}

/// In-memory inverted index for instant catalogue search (AND of prefix tokens).
struct CatalogueSearchIndex: Sendable {
    private var postings: [String: Set<Int>] = [:]

    mutating func rebuild(from tracks: [Track]) {
        postings.removeAll(keepingCapacity: true)
        for (index, track) in tracks.enumerated() {
            var tokens = Set<String>()
            for field in [track.title, track.artist, track.album, track.url.lastPathComponent] {
                tokens.formUnion(Self.tokenize(field))
            }
            for label in track.labels {
                tokens.formUnion(Self.tokenize(label))
            }
            for token in tokens {
                postings[token, default: []].insert(index)
            }
        }
    }

    func matchingIndices(query: String, trackCount: Int) -> Set<Int>? {
        let tokens = Self.tokenize(query)
        guard !tokens.isEmpty else { return nil }

        var result: Set<Int>?
        for token in tokens {
            var union = Set<Int>()
            if token.count >= 3 {
                for (key, ids) in postings where key.hasPrefix(token) {
                    union.formUnion(ids)
                }
            } else if let exact = postings[token] {
                union = exact
            } else {
                for (key, ids) in postings where key.hasPrefix(token) {
                    union.formUnion(ids)
                    if union.count == trackCount { break }
                }
            }
            if let current = result {
                result = current.intersection(union)
            } else {
                result = union
            }
            if result?.isEmpty == true { break }
        }
        return result
    }

    static func tokenize(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

enum CatalogueIndexer {
    static let audioExtensions = Set(["flac", "m4a", "alac", "wav", "aiff", "aif", "aac", "mp3", "dsf", "dff"])

    static func enumerateAudioFiles(in roots: [URL]) -> [FileFingerprint] {
        let fm = FileManager.default
        var files: [FileFingerprint] = []
        files.reserveCapacity(2048)
        var seen = Set<String>()

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let item = enumerator.nextObject() as? URL {
                let ext = item.pathExtension.lowercased()
                guard audioExtensions.contains(ext) else { continue }
                let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
                guard values?.isRegularFile == true else { continue }
                let path = item.path
                guard seen.insert(path).inserted else { continue }
                files.append(
                    FileFingerprint(
                        url: item,
                        path: path,
                        fileSize: Int64(values?.fileSize ?? 0),
                        mtime: values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                    )
                )
            }
        }
        return files
    }

    static func plan(
        files: [FileFingerprint],
        existing: [String: StoredFingerprint],
        force: Bool
    ) -> (toRead: [FileFingerprint], toDelete: [String], unchanged: Int) {
        var toRead: [FileFingerprint] = []
        toRead.reserveCapacity(force ? files.count : 64)
        var live = Set<String>(minimumCapacity: files.count)
        var unchanged = 0

        for file in files {
            live.insert(file.path)
            if force {
                toRead.append(file)
                continue
            }
            if let stored = existing[file.path],
               stored.fileSize == file.fileSize,
               abs(stored.mtime - file.mtime) < 0.6 {
                unchanged += 1
            } else {
                toRead.append(file)
            }
        }

        let toDelete = existing.keys.filter { !live.contains($0) }
        return (toRead, toDelete, unchanged)
    }

    static func readMetadata(
        files: [FileFingerprint],
        labelsByPath: [String: [String]],
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async -> [IndexedTrackRecord] {
        guard !files.isEmpty else { return [] }
        let chunkSize = max(4, min(8, ProcessInfo.processInfo.activeProcessorCount))
        var records: [IndexedTrackRecord] = []
        records.reserveCapacity(files.count)

        var processed = 0
        for chunk in files.chunked(into: chunkSize) {
            let batch = await withTaskGroup(of: IndexedTrackRecord.self, returning: [IndexedTrackRecord].self) { group in
                for file in chunk {
                    group.addTask {
                        await readOne(file: file, labelsByPath: labelsByPath)
                    }
                }
                var out: [IndexedTrackRecord] = []
                out.reserveCapacity(chunk.count)
                for await record in group {
                    out.append(record)
                }
                return out
            }
            records.append(contentsOf: batch)
            processed += chunk.count
            await progress(processed, files.count)
        }
        return records
    }

    private static func readOne(file: FileFingerprint, labelsByPath: [String: [String]]) async -> IndexedTrackRecord {
        let meta = await MetadataReader.read(url: file.url)
        let artworkHash = meta.artworkData.flatMap { ArtworkCache.shared.store($0) }
        return IndexedTrackRecord(
            path: file.path,
            title: meta.title,
            artist: meta.artist,
            album: meta.album,
            trackNumber: meta.trackNumber,
            year: meta.year,
            duration: meta.duration,
            format: meta.format,
            sampleRateHz: meta.sampleRateHz,
            bitDepth: meta.bitDepth,
            channelCount: meta.channelCount,
            fileSize: file.fileSize,
            mtime: file.mtime,
            artworkHash: artworkHash,
            filename: file.url.lastPathComponent,
            labels: labelsByPath[file.path] ?? []
        )
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index..<next]))
            index = next
        }
        return chunks
    }
}
