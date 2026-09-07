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
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = [.minimalBookmark]
        #endif
        let data = try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return FolderBookmark(displayPath: url.path, bookmarkData: data)
    }

    /// Resolves and starts security-scoped access. Caller must eventually `stopAccess`.
    func startAccess(for bookmark: FolderBookmark) throws -> URL {
        if let existing = activeURLs[bookmark.id] {
            return existing
        }

        var isStale = false
        #if os(macOS)
        let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let resolveOptions: URL.BookmarkResolutionOptions = []
        #endif
        let url = try URL(
            resolvingBookmarkData: bookmark.bookmarkData,
            options: resolveOptions,
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
