import Foundation

/// One entry of an M3U/M3U8 playlist, as written by foobar, VLC, Audirvāna, Roon, Music.app.
struct M3UEntry: Hashable, Sendable {
    /// Raw location line: absolute, relative, `file://` URL, or Windows path.
    var location: String
    /// From `#EXTINF:<seconds>,…`; nil when missing or negative (unknown).
    var duration: TimeInterval?
    /// Display text after the comma in `#EXTINF`, usually "Artist - Title".
    var displayName: String?
}

struct M3UDocument: Sendable {
    /// From `#PLAYLIST:`; callers fall back to the file name.
    var name: String?
    var entries: [M3UEntry]
}

enum M3UParser {
    /// UTF-8 first (with or without BOM) — most `.m3u` files are UTF-8 today; Latin-1 only as fallback.
    static func decode(_ data: Data) -> String? {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = bytes.dropFirst(3)
        }
        if let utf8 = String(data: bytes, encoding: .utf8) {
            return utf8
        }
        return String(data: bytes, encoding: .windowsCP1252)
            ?? String(data: bytes, encoding: .isoLatin1)
    }

    static func parse(_ text: String) -> M3UDocument {
        var name: String?
        var entries: [M3UEntry] = []
        var pendingDuration: TimeInterval?
        var pendingDisplay: String?

        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#") {
                if line.hasPrefix("#EXTINF:") {
                    let body = line.dropFirst("#EXTINF:".count)
                    let parts = body.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                    // Duration may carry attributes: `#EXTINF:545 tvg-id="…",Title`.
                    let secondsText = parts.first?.split(separator: " ").first.map(String.init) ?? ""
                    if let seconds = Double(secondsText), seconds >= 0 {
                        pendingDuration = seconds
                    } else {
                        pendingDuration = nil
                    }
                    let display = parts.count > 1
                        ? parts[1].trimmingCharacters(in: .whitespaces)
                        : ""
                    pendingDisplay = display.isEmpty ? nil : display
                } else if line.hasPrefix("#PLAYLIST:") {
                    let value = line.dropFirst("#PLAYLIST:".count).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty {
                        name = value
                    }
                }
                continue
            }

            entries.append(M3UEntry(location: line, duration: pendingDuration, displayName: pendingDisplay))
            pendingDuration = nil
            pendingDisplay = nil
        }
        return M3UDocument(name: name, entries: entries)
    }
}

struct M3UImportResult: Sendable {
    var name: String
    /// Catalogue paths in playlist order, duplicates removed.
    var trackPaths: [String]
    var entryCount: Int
    /// Entries that point at no catalogued file, in playlist order.
    var unmatched: [M3UEntry]
    /// Streams and other non-file entries, skipped on purpose.
    var skippedRemoteCount: Int
}

/// Maps playlist entries onto tracks already in the catalogue. Harbor never adds files
/// from a playlist — the folders stay the source of truth.
struct M3UMatcher {
    private let byPath: [String: [Track]]
    private let byFileName: [String: [Track]]
    private let byTitle: [String: [Track]]

    init(tracks: [Track]) {
        var byPath: [String: [Track]] = [:]
        var byFileName: [String: [Track]] = [:]
        var byTitle: [String: [Track]] = [:]
        for track in tracks {
            let path = track.url.standardizedFileURL.path
            byPath[path, default: []].append(track)
            byFileName[track.url.lastPathComponent.lowercased(), default: []].append(track)
            byTitle[Self.fold(track.title), default: []].append(track)
        }
        // SACD ISO / DFF chapters share one file: keep them in disc order.
        for (key, group) in byPath where group.count > 1 {
            byPath[key] = group.sorted { ($0.trackNumber ?? 9999) < ($1.trackNumber ?? 9999) }
        }
        self.byPath = byPath
        self.byFileName = byFileName
        self.byTitle = byTitle
    }

    func resolve(_ document: M3UDocument, playlistURL: URL) -> M3UImportResult {
        let baseDirectory = playlistURL.deletingLastPathComponent()
        var paths: [String] = []
        var seen: Set<String> = []
        var unmatched: [M3UEntry] = []
        var skipped = 0

        for entry in document.entries {
            guard let components = Self.pathComponents(of: entry.location, relativeTo: baseDirectory) else {
                skipped += 1
                continue
            }
            let matches = match(components: components, entry: entry)
            if matches.isEmpty {
                unmatched.append(entry)
                continue
            }
            for track in matches where seen.insert(track.cataloguePath).inserted {
                paths.append(track.cataloguePath)
            }
        }

        let fallbackName = playlistURL.deletingPathExtension().lastPathComponent
        return M3UImportResult(
            name: document.name ?? fallbackName,
            trackPaths: paths,
            entryCount: document.entries.count,
            unmatched: unmatched,
            skippedRemoteCount: skipped
        )
    }

    private func match(components: [String], entry: M3UEntry) -> [Track] {
        // 1. Same file on this Mac.
        let absolute = "/" + components.joined(separator: "/")
        if let exact = byPath[URL(fileURLWithPath: absolute).standardizedFileURL.path] {
            return exact
        }
        // 2. Same file under another root (`/Volumes/Music 1`, `D:\Music`, another Mac).
        if let bySuffix = matchBySuffix(components) {
            return bySuffix
        }
        // 3. Tags from `#EXTINF` — the file was renamed or re-ripped.
        if let byTags = matchByDisplayName(entry) {
            return [byTags]
        }
        return []
    }

    /// Longest shared tail of path components wins; needs file name + parent folder, and one clear winner.
    private func matchBySuffix(_ components: [String]) -> [Track]? {
        guard let fileName = components.last?.lowercased(),
              let candidates = byFileName[fileName]
        else { return nil }

        let wanted = components.reversed().map { $0.lowercased() }
        var best = 0
        var winners: [String: [Track]] = [:]
        for track in candidates {
            let have = track.url.standardizedFileURL.pathComponents.reversed().map { $0.lowercased() }
            let shared = zip(wanted, have).prefix { $0 == $1 }.count
            let key = track.url.standardizedFileURL.path
            if shared > best {
                best = shared
                winners = [key: [track]]
            } else if shared == best {
                winners[key, default: []].append(track)
            }
        }
        guard best >= 2, winners.count == 1, let group = winners.values.first else { return nil }
        return group.sorted { ($0.trackNumber ?? 9999) < ($1.trackNumber ?? 9999) }
    }

    private func matchByDisplayName(_ entry: M3UEntry) -> Track? {
        guard let display = entry.displayName else { return nil }

        // "Artist - Title" is the de-facto convention; titles can contain " - " too, so try each split.
        var splits: [(artist: String?, title: String)] = [(nil, display)]
        var searchRange = display.startIndex..<display.endIndex
        while let dash = display.range(of: " - ", range: searchRange) {
            splits.append((String(display[..<dash.lowerBound]), String(display[dash.upperBound...])))
            searchRange = dash.upperBound..<display.endIndex
        }

        for split in splits.reversed() {
            // Title alone is too weak without artist or duration to back it up.
            if split.artist == nil, entry.duration == nil { continue }
            guard let candidates = byTitle[Self.fold(split.title)] else { continue }
            let hits = candidates.filter { track in
                if let artist = split.artist, Self.fold(track.artist) != Self.fold(artist) {
                    return false
                }
                if let duration = entry.duration, duration > 0, track.duration > 0,
                   abs(track.duration - duration) > 2 {
                    return false
                }
                return true
            }
            if hits.count == 1 {
                return hits[0]
            }
        }
        return nil
    }

    /// Normalised absolute path components, or nil for streams / non-file URLs.
    static func pathComponents(of location: String, relativeTo base: URL) -> [String]? {
        var raw = location

        if let schemeEnd = raw.range(of: "://") {
            let scheme = raw[..<schemeEnd.lowerBound].lowercased()
            guard scheme == "file", let url = URL(string: raw) else { return nil }
            raw = url.path
        }

        raw = raw.replacingOccurrences(of: "\\", with: "/")

        // Windows drive (`C:/Music/…`): the drive means nothing here, only the tail can match.
        let isDrivePath = raw.count >= 2
            && raw[raw.startIndex].isLetter
            && raw[raw.index(after: raw.startIndex)] == ":"
        if isDrivePath {
            raw = String(raw.dropFirst(2))
        }

        let absolute: String
        if raw.hasPrefix("/") {
            absolute = raw
        } else {
            absolute = base.appendingPathComponent(raw).path
        }

        var stack: [String] = []
        for part in absolute.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": _ = stack.popLast()
            default: stack.append(String(part))
            }
        }
        return stack.isEmpty ? nil : stack
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

enum M3UWriter {
    /// Extended M3U8: UTF-8, `\n`, absolute paths — what foobar, VLC and Harbor's own import read back.
    /// SACD ISO / DFF chapters share one file path, so they are written once per container.
    static func render(name: String, tracks: [Track]) -> String {
        var lines = ["#EXTM3U", "#PLAYLIST:\(singleLine(name))"]
        var writtenContainers: Set<String> = []
        for track in tracks {
            let path = track.url.standardizedFileURL.path
            if track.cataloguePath != path {
                guard writtenContainers.insert(path).inserted else { continue }
            }
            let seconds = track.duration > 0 ? Int(track.duration.rounded()) : -1
            let display = track.artist.isEmpty ? track.title : "\(track.artist) - \(track.title)"
            lines.append("#EXTINF:\(seconds),\(singleLine(display))")
            lines.append(path)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
    }
}
