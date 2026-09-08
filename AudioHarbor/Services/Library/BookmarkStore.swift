import Foundation

struct FolderBookmark: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var displayPath: String
    var bookmarkData: Data

    init(id: UUID = UUID(), displayPath: String, bookmarkData: Data) {
        self.id = id
        self.displayPath = displayPath
        self.bookmarkData = bookmarkData
    }

    var name: String {
        URL(fileURLWithPath: displayPath).lastPathComponent
    }
}

/// Persists security-scoped bookmarks so sandboxed folder access survives relaunch.
actor BookmarkStore {
    static let shared = BookmarkStore()

    private let defaultsKey = "audioharbor.library.folderBookmarks"
    private var activeURLs: [UUID: URL] = [:]

    func load() -> [FolderBookmark] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([FolderBookmark].self, from: data)
        else { return [] }
        return decoded
    }

    func save(_ bookmarks: [FolderBookmark]) {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func makeBookmark(for url: URL) throws -> FolderBookmark {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var created: FolderBookmark?
        var coordError: NSError?
        var bookmarkError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [.withoutChanges],
            error: &coordError
        ) { coordinated in
            do {
                created = try Self.bookmark(from: coordinated)
            } catch {
                bookmarkError = error
            }
        }
        if let created {
            return created
        }
        if let bookmarkError {
            throw bookmarkError
        }
        if let coordError {
            throw coordError
        }
        return try Self.bookmark(from: url)
    }

    /// Resolves and starts security-scoped access. Caller must eventually `stopAccess`.
    func startAccess(for bookmark: FolderBookmark) throws -> URL {
        if let existing = activeURLs[bookmark.id] {
            return existing
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark.bookmarkData,
            options: Self.resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        guard url.startAccessingSecurityScopedResource() else {
            throw BookmarkError.accessDenied(url.path)
        }

        activeURLs[bookmark.id] = url
        return url
    }

    func stopAccess(for bookmarkID: UUID) {
        if let url = activeURLs.removeValue(forKey: bookmarkID) {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func stopAll() {
        for (_, url) in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeURLs.removeAll()
    }

    private static func bookmark(from url: URL) throws -> FolderBookmark {
        let data = try url.bookmarkData(
            options: creationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return FolderBookmark(displayPath: url.path, bookmarkData: data)
    }

    private static var creationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }

    private static var resolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }
}

enum BookmarkError: LocalizedError {
    case accessDenied(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let path):
            "Could not access folder: \(path)"
        }
    }
}

/// iCloud Drive placeholders are hidden `*.icloud` files until downloaded.
enum ICloudItem {
    static func resolvedAudioURL(from item: URL, extensions: Set<String>) -> URL? {
        let name = item.lastPathComponent
        if name.hasSuffix(".icloud") {
            var realName = (name as NSString).deletingPathExtension
            if realName.hasPrefix(".") {
                realName.removeFirst()
            }
            let ext = (realName as NSString).pathExtension.lowercased()
            guard extensions.contains(ext) else { return nil }
            return item.deletingLastPathComponent().appendingPathComponent(realName)
        }
        let ext = item.pathExtension.lowercased()
        guard extensions.contains(ext) else { return nil }
        return item
    }

    static func isHiddenJunk(_ item: URL) -> Bool {
        let name = item.lastPathComponent
        if name.hasSuffix(".icloud") { return false }
        return name.hasPrefix(".")
    }

    static func ensureDownloaded(_ url: URL) async {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true
        else { return }

        if values.ubiquitousItemDownloadingStatus == .current
            || values.ubiquitousItemDownloadingStatus == .downloaded {
            return
        }

        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        for _ in 0..<150 {
            try? await Task.sleep(for: .milliseconds(200))
            let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus
            if status == .current || status == .downloaded {
                return
            }
        }
    }
}
