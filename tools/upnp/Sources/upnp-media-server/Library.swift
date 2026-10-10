import Foundation
import UPnPCommon

/// One shared folder as a tree of UPnP objects. An object's ID is its path below the folder
/// ("p:" + path), so IDs survive restarts and control points can keep favourites; "0" is the folder.
struct Library: Sendable {
    struct Object: Sendable {
        let id: String
        let parentID: String
        let url: URL
        let isFolder: Bool
        let title: String
    }

    static let audioTypes: [String: String] = [
        "flac": "audio/flac", "wav": "audio/wav", "aif": "audio/aiff", "aiff": "audio/aiff",
        "m4a": "audio/mp4", "mp3": "audio/mpeg", "dsf": "audio/x-dsf", "dff": "audio/x-dff",
    ]

    let root: URL
    var name: String { root.lastPathComponent }

    init(root: URL) throws {
        let resolved = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ToolError("\(root.path) is not a folder")
        }
        self.root = resolved
    }

    func object(for id: String) -> Object? {
        if id == "0" { return Object(id: "0", parentID: "-1", url: root, isFolder: true, title: name) }
        guard id.hasPrefix("p:"), let url = url(forRelativePath: String(id.dropFirst(2))) else { return nil }
        return object(at: url)
    }

    /// The object for a file or folder inside the shared folder; nil for anything else.
    func object(at url: URL) -> Object? {
        guard let relative = relativePath(of: url) else { return nil }
        if relative.isEmpty { return object(for: "0") }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        let parent = (relative as NSString).deletingLastPathComponent
        let parentID = parent.isEmpty ? "0" : "p:" + parent
        if isDirectory.boolValue {
            return Object(id: "p:" + relative, parentID: parentID, url: url, isFolder: true, title: url.lastPathComponent)
        }
        guard Self.audioTypes[url.pathExtension.lowercased()] != nil else { return nil }
        return Object(id: "p:" + relative, parentID: parentID, url: url, isFolder: false,
                      title: url.deletingPathExtension().lastPathComponent)
    }

    /// Folders first, then audio files, each in Finder order; hidden files and other types left out.
    func children(of folder: Object) -> [Object] {
        guard folder.isFolder,
              let urls = try? FileManager.default.contentsOfDirectory(at: folder.url, includingPropertiesForKeys: nil,
                                                                      options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { object(at: $0) }.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }
    }

    /// cover / folder / front as .jpg, .jpeg or .png — the names the app's catalogue looks for.
    func cover(in folder: URL) -> URL? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        let byLowercase = Dictionary(names.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        for base in ["cover", "folder", "front"] {
            for ext in ["jpg", "jpeg", "png"] {
                if let match = byLowercase["\(base).\(ext)"] { return folder.appendingPathComponent(match) }
            }
        }
        return nil
    }

    // MARK: - Paths

    /// The path below the shared folder; nil for anything outside it (`..`, a symlink out).
    func relativePath(of url: URL) -> String? {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path == root.path { return "" }
        guard path.hasPrefix(root.path + "/") else { return nil }
        return String(path.dropFirst(root.path.count + 1))
    }

    func url(forRelativePath relative: String) -> URL? {
        let url = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        return relativePath(of: url) == nil ? nil : url
    }

    /// A URL-safe name for a file: its path below the folder as base64url, plus the extension
    /// (some players go by the extension).
    func token(for url: URL) -> String? {
        guard let relative = relativePath(of: url) else { return nil }
        let encoded = Data(relative.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? encoded : encoded + "." + ext
    }

    func url(forToken token: String) -> URL? {
        var encoded = (token.split(separator: ".").first.map(String.init) ?? token)
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded += "=" }
        guard let data = Data(base64Encoded: encoded), let relative = String(data: data, encoding: .utf8) else { return nil }
        return url(forRelativePath: relative)
    }
}
