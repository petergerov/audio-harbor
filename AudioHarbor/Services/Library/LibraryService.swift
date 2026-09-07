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

    private static let audioExtensions = Set(["flac", "m4a", "alac", "wav", "aiff", "aif", "aac", "mp3", "dsf", "dff"])

    var filteredTracks: [Track] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.artist.localizedCaseInsensitiveContains(q)
                || $0.album.localizedCaseInsensitiveContains(q)
                || $0.labels.contains { $0.localizedCaseInsensitiveContains(q) }
        }
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
        return albums.filter { album in
            album.title.localizedCaseInsensitiveContains(q)
                || album.artist.localizedCaseInsensitiveContains(q)
                ||                 album.tracks.contains {
                    $0.title.localizedCaseInsensitiveContains(q)
                        || $0.artist.localizedCaseInsensitiveContains(q)
                        || $0.labels.contains { $0.localizedCaseInsensitiveContains(q) }
                }
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

        for (root, base) in scopes {
            // Matching audio from the metadata index (title / artist / album / filename).
            for track in tracks where track.url.path.hasPrefix(base.path) {
                let fileName = track.url.lastPathComponent
                let matches =
                    track.title.localizedCaseInsensitiveContains(q)
                    || track.artist.localizedCaseInsensitiveContains(q)
                    || track.album.localizedCaseInsensitiveContains(q)
                    || fileName.localizedCaseInsensitiveContains(q)
                guard matches else { continue }
                guard seen.insert(track.url.path).inserted else { continue }
                let relative = relativePath(for: track.url, under: root)
                hits.append(
                    FolderSearchHit(
                        entry: FolderBrowseEntry(name: fileName, url: track.url, kind: .audioFile),
                        relativePath: relative
                    )
                )
            }

            // Matching directories under the current scope.
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: base,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let item = enumerator.nextObject() as? URL {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                guard isDir else { continue }
                guard item.lastPathComponent.localizedCaseInsensitiveContains(q) else { continue }
                guard directoryContainsSupportedAudio(item) else { continue }
                guard seen.insert(item.path).inserted else { continue }
                hits.append(
                    FolderSearchHit(
                        entry: FolderBrowseEntry(name: item.lastPathComponent, url: item, kind: .directory),
                        relativePath: relativePath(for: item, under: root)
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
        loadDemoLibrary()
        Task { await restoreBookmarks() }
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
        if let existing = tracks.first(where: { $0.url.path == url.path }) {
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
    }

    private func applyStoredLabelsToTracks() {
        tracks = tracks.map { track in
            var copy = track
            copy.labels = labelsByPath[track.url.path] ?? []
            return copy
        }
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
            // Drop tracks that lived under this folder path.
            let path = bookmark.displayPath
            tracks.removeAll { $0.url.path.hasPrefix(path) }
            if tracks.isEmpty {
                showsDemoLibrary = true
                loadDemoLibrary()
            } else {
                showsDemoLibrary = false
                rebuildAlbums()
            }
        }
    }

    private func listFolderContents(at url: URL) -> [FolderBrowseEntry] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let parentPrefix = {
            let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
            return path + "/"
        }()
        let audioChildNames = immediateChildDirectoryNamesContainingAudio(under: url)
        let parentIndexed = tracks.contains { $0.url.path.hasPrefix(parentPrefix) }

        var directories: [FolderBrowseEntry] = []
        var files: [FolderBrowseEntry] = []

        for item in items {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                // Only show folders that contain at least one supported audio file (recursively).
                let hasAudio = audioChildNames.contains(item.lastPathComponent)
                    || (!parentIndexed && directoryContainsSupportedAudioOnDisk(item))
                if hasAudio {
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

    private func restoreBookmarks() async {
        let stored = await BookmarkStore.shared.load()
        guard !stored.isEmpty else { return }
        folders = stored
        for bookmark in stored {
            do {
                let url = try await BookmarkStore.shared.startAccess(for: bookmark)
                accessibleFolderURLs[bookmark.id] = url
                await scan(url: url, replaceDemo: true)
            } catch {
                scanProgressText = error.localizedDescription
            }
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
            await scan(url: accessed, replaceDemo: true)
        } catch {
            scanProgressText = error.localizedDescription
        }
    }

    private func scan(url: URL, replaceDemo: Bool) async {
        isScanning = true
        scanProgressText = "Scanning \(url.lastPathComponent)…"
        defer {
            isScanning = false
            scanProgressText = nil
        }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var fileURLs: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard Self.audioExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            fileURLs.append(fileURL)
        }

        var found: [Track] = []
        for (index, fileURL) in fileURLs.enumerated() {
            scanProgressText = "Reading \(index + 1)/\(fileURLs.count)…"
            let meta = await MetadataReader.read(url: fileURL)
            found.append(
                labeled(
                    Track(
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
                        url: fileURL,
                        artworkData: meta.artworkData
                    )
                )
            )
        }

        if replaceDemo && showsDemoLibrary {
            tracks = found
            showsDemoLibrary = false
        } else {
            // Prefer newer scan results for same paths.
            let paths = Set(found.map(\.url.path))
            tracks.removeAll { paths.contains($0.url.path) }
            tracks.append(contentsOf: found)
            if !found.isEmpty { showsDemoLibrary = false }
        }
        rebuildAlbums()
    }

    private func rebuildAlbums() {
        let grouped = Dictionary(grouping: tracks) { "\($0.album)|\($0.artist)" }
        albums = grouped.values
            .map { list in
                let first = list[0]
                return Album(
                    title: first.album,
                    artist: first.artist,
                    year: first.year,
                    tracks: list.sorted { ($0.trackNumber ?? 9999) < ($1.trackNumber ?? 9999) },
                    artworkData: list.first(where: { $0.artworkData != nil })?.artworkData
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
        rebuildAlbums()
    }
}
