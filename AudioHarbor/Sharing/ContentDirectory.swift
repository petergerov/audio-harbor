#if os(macOS)
import Foundation

/// The catalogue as a UPnP ContentDirectory: Albums, Artists, Directories, Playlists and Labels
/// under the root, tracks below them, as DIDL-Lite pages.
///
/// IDs come from what the catalogue keys on (album UUID, artist / label name, folder path,
/// `cataloguePath`), so they survive a rescan and players can keep favourites. A track's ID ends
/// in `|t:<token>` after its container's ID, so the same track can sit in several containers.
@MainActor
final class ContentDirectory {
    struct Page: Sendable {
        let didl: String
        let returned: Int
        let total: Int
        let updateID: Int
    }

    /// Where a track's bytes come from.
    enum MediaSource: Sendable {
        case file(URL, mime: String)
        /// A SACD ISO track: extracted to a cached DFF first.
        case sacd(Track)
        /// A DST-compressed DFF: decoded to a cached DFF first.
        case compressedDFF(Track)
    }

    nonisolated static let dlnaFeatures = "DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000"

    private let catalogue: SharedCatalogue

    init(catalogue: SharedCatalogue) {
        self.catalogue = catalogue
    }

    var updateID: Int { catalogue.revision }

    // MARK: - Browse

    func browse(_ id: String, flag: String, start: Int, count: Int, base: String) throws -> Page {
        switch flag {
        case "BrowseMetadata":
            let entry = try metadata(for: id)
            return Page(didl: didl([entry], base: base), returned: 1, total: 1, updateID: updateID)
        case "BrowseDirectChildren":
            guard let node = Node(id: id) else {
                throw Self.isTrackID(id) ? UPnPError.noSuchContainer : UPnPError.noSuchObject
            }
            let children = try self.children(of: node)
            let page = Array(children.dropFirst(max(0, start)).prefix(count > 0 ? count : children.count))
            return Page(didl: didl(page, base: base), returned: page.count, total: children.count, updateID: updateID)
        default:
            throw UPnPError.invalidArgs
        }
    }

    /// The source for a `/media/<token>` request, or nil when the token names nothing shared.
    func media(for token: String) -> MediaSource? {
        guard let path = Self.path(fromToken: token) else { return nil }
        if let track = catalogue.track(forCataloguePath: path) {
            return Self.source(for: track)
        }
        // A file the index does not have yet, listed from disk under Directories.
        let url = URL(fileURLWithPath: path)
        let format = AudioFormat.infer(from: url)
        guard !VirtualTrackPath.isVirtual(path), format != .sacd, let mime = Self.mime(for: format),
              FileManager.default.fileExists(atPath: url.path), catalogue.isInConnectedFolder(url) else { return nil }
        return .file(url, mime: mime)
    }

    // MARK: - Nodes

    private enum Node {
        case root, albums, artists, folders, playlists, labels
        case album(UUID)
        case artist(String)
        case playlist(UUID)
        case label(String)
        case folder(UUID, [String])

        init?(id: String) {
            switch id {
            case "0": self = .root
            case "albums": self = .albums
            case "artists": self = .artists
            case "folders": self = .folders
            case "playlists": self = .playlists
            case "labels": self = .labels
            default:
                if let rest = Self.value(of: id, after: "album:"), let uuid = UUID(uuidString: rest) {
                    self = .album(uuid)
                } else if let rest = Self.value(of: id, after: "artist:") {
                    self = .artist(rest)
                } else if let rest = Self.value(of: id, after: "playlist:"), let uuid = UUID(uuidString: rest) {
                    self = .playlist(uuid)
                } else if let rest = Self.value(of: id, after: "label:") {
                    self = .label(rest)
                } else if let rest = Self.value(of: id, after: "folder:"), let ref = RemoteFolderRef.parse(rest) {
                    self = .folder(ref.rootID, ref.components)
                } else {
                    return nil
                }
            }
        }

        private static func value(of id: String, after prefix: String) -> String? {
            guard id.hasPrefix(prefix), !Self.isTrack(id) else { return nil }
            return String(id.dropFirst(prefix.count))
        }

        private static func isTrack(_ id: String) -> Bool { id.range(of: "|t:") != nil }

        var id: String {
            switch self {
            case .root: "0"
            case .albums: "albums"
            case .artists: "artists"
            case .folders: "folders"
            case .playlists: "playlists"
            case .labels: "labels"
            case .album(let uuid): "album:" + uuid.uuidString
            case .artist(let name): "artist:" + name
            case .playlist(let uuid): "playlist:" + uuid.uuidString
            case .label(let name): "label:" + name
            case .folder(let root, let components): "folder:" + RemoteFolderRef.encode(rootID: root, components: components)
            }
        }

        var parentID: String {
            switch self {
            case .root: "-1"
            case .albums, .artists, .folders, .playlists, .labels: "0"
            case .album: "albums"
            case .artist: "artists"
            case .playlist: "playlists"
            case .label: "labels"
            case .folder(let root, let components):
                components.isEmpty ? "folders" : Node.folder(root, Array(components.dropLast())).id
            }
        }
    }

    private enum Entry {
        case container(id: String, parentID: String, title: String, kind: String, childCount: Int?,
                       artist: String?, artwork: String?)
        case track(Track, parentID: String)
    }

    private static func isTrackID(_ id: String) -> Bool { id.range(of: "|t:", options: .backwards) != nil }

    private func children(of node: Node) throws -> [Entry] {
        switch node {
        case .root:
            return [
                container(.albums, "Albums", count: catalogue.albums.count),
                container(.artists, "Artists", count: catalogue.artists.count),
                container(.folders, "Directories", count: catalogue.folderRoots.count),
                container(.playlists, "Playlists", count: catalogue.playlists.count),
                container(.labels, "Labels", count: catalogue.labels.count),
            ]
        case .albums:
            return catalogue.albums.map(albumEntry)
        case .artists:
            return catalogue.artists.map { container(.artist($0.name), $0.name, count: $0.count, kind: Self.artistClass) }
        case .playlists:
            return catalogue.playlists.map {
                container(.playlist($0.id), $0.name, count: catalogue.tracks(inPlaylist: $0.id)?.count, kind: Self.playlistClass)
            }
        case .labels:
            return catalogue.labels.map { container(.label($0.name), $0.name, count: $0.count) }
        case .folders:
            return catalogue.folderRoots.map { container(.folder($0.id, []), $0.name, count: nil) }
        case .album(let id):
            guard let album = catalogue.albums.first(where: { $0.id == id }) else { throw UPnPError.noSuchObject }
            return tracks(album.tracks, in: node)
        case .artist(let name):
            return tracks(catalogue.tracks(forArtist: name), in: node)
        case .playlist(let id):
            guard let list = catalogue.tracks(inPlaylist: id) else { throw UPnPError.noSuchObject }
            return tracks(list, in: node)
        case .label(let name):
            return tracks(catalogue.tracks(forLabel: name), in: node)
        case .folder(let root, let components):
            guard let listing = catalogue.folderListing(rootID: root, components: components) else {
                throw UPnPError.noSuchObject
            }
            return listing.compactMap { entry in
                switch entry.kind {
                case .directory:
                    // No child count: it would mean listing every subfolder on each page.
                    return container(.folder(root, components + [entry.name]), entry.name, count: nil)
                case .audioFile(let track):
                    return Self.isShareable(track) ? .track(track, parentID: node.id) : nil
                }
            }
        }
    }

    private func metadata(for id: String) throws -> Entry {
        if let marker = id.range(of: "|t:", options: .backwards) {
            let parentID = String(id[..<marker.lowerBound])
            let token = String(id[marker.upperBound...])
            guard Node(id: parentID) != nil, let path = Self.path(fromToken: token) else { throw UPnPError.noSuchObject }
            let track = catalogue.track(forCataloguePath: path) ?? Self.unindexedTrack(at: path)
            guard let track, Self.isShareable(track) else { throw UPnPError.noSuchObject }
            return .track(track, parentID: parentID)
        }
        guard let node = Node(id: id) else { throw UPnPError.noSuchObject }
        switch node {
        case .root:
            return .container(id: "0", parentID: "-1", title: "Audio Harbor", kind: Self.folderClass, childCount: 5,
                              artist: nil, artwork: nil)
        case .album(let uuid):
            guard let album = catalogue.albums.first(where: { $0.id == uuid }) else { throw UPnPError.noSuchObject }
            return albumEntry(album)
        case .artist(let name):
            return container(node, name, count: catalogue.tracks(forArtist: name).count, kind: Self.artistClass)
        case .playlist(let uuid):
            guard let playlist = catalogue.playlists.first(where: { $0.id == uuid }) else { throw UPnPError.noSuchObject }
            return container(node, playlist.name, count: catalogue.tracks(inPlaylist: uuid)?.count, kind: Self.playlistClass)
        case .label(let name):
            return container(node, name, count: catalogue.tracks(forLabel: name).count)
        case .folder(let root, let components):
            let name = components.last ?? catalogue.folderRoots.first { $0.id == root }?.name ?? "Directory"
            return container(node, name, count: nil)
        case .albums, .artists, .folders, .playlists, .labels:
            for entry in try children(of: .root) {
                if case .container(let entryID, _, _, _, _, _, _) = entry, entryID == id { return entry }
            }
            throw UPnPError.noSuchObject
        }
    }

    private func container(_ node: Node, _ title: String, count: Int?, kind: String = ContentDirectory.folderClass) -> Entry {
        .container(id: node.id, parentID: node.parentID, title: title, kind: kind, childCount: count, artist: nil, artwork: nil)
    }

    private func albumEntry(_ album: Album) -> Entry {
        let node = Node.album(album.id)
        return .container(id: node.id, parentID: node.parentID, title: album.title, kind: Self.albumClass,
                          childCount: album.tracks.count, artist: CatalogueUnknown.isArtist(album.artist) ? nil : album.artist,
                          artwork: album.artworkHash ?? album.tracks.first?.artworkHash)
    }

    private func tracks(_ tracks: [Track], in node: Node) -> [Entry] {
        tracks.filter(Self.isShareable).map { .track($0, parentID: node.id) }
    }

    // MARK: - DIDL-Lite

    nonisolated private static let folderClass = "object.container.storageFolder"
    nonisolated private static let albumClass = "object.container.album.musicAlbum"
    nonisolated private static let artistClass = "object.container.person.musicArtist"
    nonisolated private static let playlistClass = "object.container.playlistContainer"

    private func didl(_ entries: [Entry], base: String) -> String {
        var xml = "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" "
            + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\">"
        for entry in entries {
            switch entry {
            case let .container(id, parentID, title, kind, childCount, artist, artwork):
                xml += "<container id=\"\(e(id))\" parentID=\"\(e(parentID))\" restricted=\"1\" searchable=\"0\""
                if let childCount { xml += " childCount=\"\(childCount)\"" }
                xml += "><dc:title>\(e(title))</dc:title>"
                if let artist { xml += "<upnp:artist>\(e(artist))</upnp:artist>" }
                xml += "<upnp:class>\(kind)</upnp:class>"
                if let artwork, Self.isArtworkHash(artwork) { xml += "<upnp:albumArtURI>\(e("\(base)/art/\(artwork).jpg"))</upnp:albumArtURI>" }
                xml += "</container>"
            case let .track(track, parentID):
                xml += item(track, parentID: parentID, base: base)
            }
        }
        return xml + "</DIDL-Lite>"
    }

    private func item(_ track: Track, parentID: String, base: String) -> String {
        guard let mime = Self.mime(for: track) else { return "" }
        let token = Self.token(for: track.cataloguePath, mime: mime)
        var xml = "<item id=\"\(e(parentID + "|t:" + token))\" parentID=\"\(e(parentID))\" restricted=\"1\">"
            + "<dc:title>\(e(track.title))</dc:title>"
        if !CatalogueUnknown.isArtist(track.artist) {
            xml += "<dc:creator>\(e(track.artist))</dc:creator><upnp:artist>\(e(track.artist))</upnp:artist>"
        }
        if let albumArtist = track.albumArtist, !CatalogueUnknown.isArtist(albumArtist) {
            xml += "<upnp:artist role=\"AlbumArtist\">\(e(albumArtist))</upnp:artist>"
        }
        if !CatalogueUnknown.isAlbum(track.album) { xml += "<upnp:album>\(e(track.album))</upnp:album>" }
        if let number = track.trackNumber { xml += "<upnp:originalTrackNumber>\(number)</upnp:originalTrackNumber>" }
        if let year = track.year { xml += "<dc:date>\(year)-01-01</dc:date>" }
        xml += "<upnp:class>object.item.audioItem.musicTrack</upnp:class>"
        if let hash = track.artworkHash, Self.isArtworkHash(hash) {
            xml += "<upnp:albumArtURI>\(e("\(base)/art/\(hash).jpg"))</upnp:albumArtURI>"
        }
        var attributes = "protocolInfo=\"http-get:*:\(mime):\(Self.dlnaFeatures)\""
        // A SACD track's size is only known once it is extracted.
        if Self.source(for: track).map({ if case .file = $0 { true } else { false } }) == true,
           let size = (try? FileManager.default.attributesOfItem(atPath: track.url.path))?[.size] as? NSNumber {
            attributes += " size=\"\(size.uint64Value)\""
        }
        if track.duration > 0 {
            let whole = Int(track.duration)
            attributes += String(format: " duration=\"%d:%02d:%02d.%03d\"", whole / 3600, (whole / 60) % 60, whole % 60,
                                 Int(track.duration.truncatingRemainder(dividingBy: 1) * 1000))
        }
        if let rate = track.sampleRateHz { attributes += " sampleFrequency=\"\(rate)\"" }
        if let bits = (track.format.isDSD ? 1 : track.bitDepth) { attributes += " bitsPerSample=\"\(bits)\"" }
        if let channels = track.channelCount { attributes += " nrAudioChannels=\"\(channels)\"" }
        return xml + "<res \(attributes)>\(e("\(base)/media/\(token)"))</res></item>"
    }

    private func e(_ text: String) -> String { UPnPXML.escape(text) }

    // MARK: - Files

    /// DFF files with chapter markers are left out: serving the file would play every chapter.
    private static func isShareable(_ track: Track) -> Bool {
        VirtualTrackPath.dffTrack(from: track.cataloguePath) == nil && mime(for: track) != nil
    }

    private static func source(for track: Track) -> MediaSource? {
        if track.format == .sacd || VirtualTrackPath.sacdTrack(from: track.cataloguePath) != nil {
            return .sacd(track)
        }
        guard VirtualTrackPath.dffTrack(from: track.cataloguePath) == nil, let mime = mime(for: track) else { return nil }
        if track.format == .dff, DFFDST.isCompressed(url: track.url) {
            return .compressedDFF(track)
        }
        return .file(track.url, mime: mime)
    }

    private static func mime(for track: Track) -> String? {
        if track.format == .sacd || VirtualTrackPath.sacdTrack(from: track.cataloguePath) != nil { return "audio/x-dff" }
        return mime(for: track.format)
    }

    nonisolated static func mime(for format: AudioFormat) -> String? {
        switch format {
        case .flac: "audio/flac"
        case .alac, .aac: "audio/mp4"
        case .wav: "audio/wav"
        case .aiff: "audio/aiff"
        case .mp3: "audio/mpeg"
        case .dsf: "audio/x-dsf"
        case .dff, .sacd: "audio/x-dff"
        case .unknown: nil
        }
    }

    private static func fileExtension(forMime mime: String) -> String {
        switch mime {
        case "audio/flac": "flac"
        case "audio/mp4": "m4a"
        case "audio/wav": "wav"
        case "audio/aiff": "aiff"
        case "audio/mpeg": "mp3"
        case "audio/x-dsf": "dsf"
        default: "dff"
        }
    }

    /// The catalogue path as base64url, plus the file type's extension (some players go by it).
    private static func token(for path: String, mime: String) -> String {
        Data(path.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "") + "." + fileExtension(forMime: mime)
    }

    private static func path(fromToken token: String) -> String? {
        var encoded = (token.split(separator: ".").first.map(String.init) ?? token)
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded += "=" }
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// A listing's stand-in for a file not indexed yet, for BrowseMetadata on its ID.
    private static func unindexedTrack(at path: String) -> Track? {
        let url = URL(fileURLWithPath: path)
        guard !VirtualTrackPath.isVirtual(path), FileManager.default.fileExists(atPath: path) else { return nil }
        return Track(title: url.deletingPathExtension().lastPathComponent, artist: CatalogueUnknown.display,
                     album: CatalogueUnknown.display, duration: 0, format: AudioFormat.infer(from: url), url: url)
    }

    /// Artwork names are content hashes (hex); anything else could point outside the cache.
    nonisolated static func isArtworkHash(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value.allSatisfy { $0.isHexDigit }
    }
}
#endif
