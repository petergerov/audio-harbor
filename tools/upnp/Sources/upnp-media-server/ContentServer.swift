import Foundation
import UPnPCommon

/// ContentDirectory and ConnectionManager over the shared folder, and the files themselves.
final class ContentServer: Sendable {
    static let dlnaFeatures = "DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000"

    let library: Library
    let name: String
    let udn: String
    let port: UInt16

    init(library: Library, name: String, udn: String, port: UInt16) {
        self.library = library
        self.name = name
        self.udn = udn
        self.port = port
    }

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let parts = path.split(separator: "/").map(String.init)
        switch (request.method, parts.first ?? "", parts.count) {
        case ("GET", "description.xml", 1), ("HEAD", "description.xml", 1):
            say("http ← \(request.peer) description")
            return .xml(Documents.description(name: name, udn: udn))
        case ("GET", "scpd", 2):
            return Documents.scpd(parts[1].replacingOccurrences(of: ".xml", with: "")).map { .xml($0) } ?? .notFound
        case ("POST", "ctl", 2):
            return soap(parts[1], request)
        case ("GET", "media", 2), ("HEAD", "media", 2):
            return media(parts[1], request)
        case ("GET", "art", 2), ("HEAD", "art", 2):
            guard let url = library.url(forToken: parts[1]) else { return .notFound }
            let type = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            return .file(url, type: type, rangeHeader: request.headers["RANGE"])
        case ("SUBSCRIBE", "evt", 2):
            // The folder is read live, so there is nothing to announce; accepting keeps control points from retrying.
            return HTTPResponse(status: "200 OK", headers: [("SID", request.headers["SID"] ?? "uuid:" + UUID().uuidString.lowercased()),
                                                           ("TIMEOUT", "Second-1800")])
        case ("UNSUBSCRIBE", "evt", 2):
            return HTTPResponse(status: "200 OK")
        default:
            say("http ← \(request.peer) \(request.method) \(path) → 404")
            return .notFound
        }
    }

    // MARK: - SOAP

    private func soap(_ service: String, _ request: HTTPRequest) -> HTTPResponse {
        let action = SOAPText.action(fromHeader: request.headers["SOAPACTION"])
        let args = XMLLeaves.parse(request.body).values
        guard let serviceType = Documents.services.first(where: { serviceShortName($0) == service }) else { return .notFound }
        do {
            guard Documents.actions(service).contains(where: { $0.0 == action }) else { throw UPnPError.invalidAction }
            let output = try perform(service, action, args, request: request)
            return .xml(SOAPText.response(action, serviceType: serviceType, output))
        } catch {
            let upnp = error as? UPnPError ?? .actionFailed
            say("soap ✗ \(service).\(action) → \(upnp.code) \(upnp.text)")
            return .xml(SOAPText.fault(upnp), status: "500 Internal Server Error")
        }
    }

    private func perform(_ service: String, _ action: String, _ args: [String: String],
                         request: HTTPRequest) throws -> [(String, String)] {
        switch (service, action) {
        case ("ContentDirectory", "Browse"):
            return try browse(args, request: request)
        case ("ContentDirectory", "GetSearchCapabilities"):
            return [("SearchCaps", "")]
        case ("ContentDirectory", "GetSortCapabilities"):
            return [("SortCaps", "")]
        case ("ContentDirectory", "GetSystemUpdateID"):
            return [("Id", "1")]
        case ("ConnectionManager", "GetProtocolInfo"):
            let source = Set(Library.audioTypes.values).sorted().map { "http-get:*:\($0):*" }.joined(separator: ",")
            return [("Source", source), ("Sink", "")]
        case ("ConnectionManager", "GetCurrentConnectionIDs"):
            return [("ConnectionIDs", "0")]
        case ("ConnectionManager", "GetCurrentConnectionInfo"):
            return [("RcsID", "-1"), ("AVTransportID", "-1"), ("ProtocolInfo", ""), ("PeerConnectionManager", ""),
                    ("PeerConnectionID", "-1"), ("Direction", "Output"), ("Status", "OK")]
        default:
            throw UPnPError.invalidAction
        }
    }

    private func browse(_ args: [String: String], request: HTTPRequest) throws -> [(String, String)] {
        let id = args["ObjectID"] ?? "0"
        guard let object = library.object(for: id) else { throw UPnPError.noSuchObject }
        let base = baseURL(for: request)
        switch args["BrowseFlag"] ?? "" {
        case "BrowseMetadata":
            say("browse ← \(request.peer) \(object.title) (metadata)")
            return [("Result", didl([object], base: base)), ("NumberReturned", "1"), ("TotalMatches", "1"), ("UpdateID", "1")]
        case "BrowseDirectChildren":
            guard object.isFolder else { throw UPnPError.noSuchContainer }
            let start = max(0, Int(args["StartingIndex"] ?? "") ?? 0)
            let requested = max(0, Int(args["RequestedCount"] ?? "") ?? 0)
            let children = library.children(of: object)
            let page = Array(children.dropFirst(start).prefix(requested == 0 ? children.count : requested))
            say("browse ← \(request.peer) \(object.id == "0" ? "/" : object.title): \(page.count) of \(children.count) from \(start)")
            return [("Result", didl(page, base: base)), ("NumberReturned", String(page.count)),
                    ("TotalMatches", String(children.count)), ("UpdateID", "1")]
        default:
            throw UPnPError.invalidArgs
        }
    }

    // MARK: - DIDL-Lite

    private func didl(_ objects: [Library.Object], base: String) -> String {
        var covers: [URL: URL?] = [:]
        func coverURL(in folder: URL) -> String? {
            let cover: URL?
            if let cached = covers[folder] {
                cover = cached
            } else {
                cover = library.cover(in: folder)
                covers[folder] = cover
            }
            return cover.flatMap { library.token(for: $0) }.map { "\(base)/art/\($0)" }
        }
        var xml = "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" "
            + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\">"
        for object in objects {
            if object.isFolder {
                xml += "<container id=\"\(xmlEscape(object.id))\" parentID=\"\(xmlEscape(object.parentID))\" restricted=\"1\" "
                    + "searchable=\"0\" childCount=\"\(library.children(of: object).count)\">"
                    + "<dc:title>\(xmlEscape(object.title))</dc:title><upnp:class>object.container.storageFolder</upnp:class>"
                if let art = coverURL(in: object.url) { xml += "<upnp:albumArtURI>\(xmlEscape(art))</upnp:albumArtURI>" }
                xml += "</container>"
            } else if let item = item(object, base: base, art: coverURL(in: object.url.deletingLastPathComponent())) {
                xml += item
            }
        }
        return xml + "</DIDL-Lite>"
    }

    private func item(_ object: Library.Object, base: String, art: String?) -> String? {
        guard let token = library.token(for: object.url),
              let mime = Library.audioTypes[object.url.pathExtension.lowercased()] else { return nil }
        let tags = Tags(object.url)
        var xml = "<item id=\"\(xmlEscape(object.id))\" parentID=\"\(xmlEscape(object.parentID))\" restricted=\"1\">"
            + "<dc:title>\(xmlEscape(tags.title ?? object.title))</dc:title>"
        if let artist = tags.artist ?? tags.albumArtist {
            xml += "<dc:creator>\(xmlEscape(artist))</dc:creator><upnp:artist>\(xmlEscape(artist))</upnp:artist>"
        }
        if let albumArtist = tags.albumArtist {
            xml += "<upnp:artist role=\"AlbumArtist\">\(xmlEscape(albumArtist))</upnp:artist>"
        }
        if let album = tags.album { xml += "<upnp:album>\(xmlEscape(album))</upnp:album>" }
        if let track = tags.track { xml += "<upnp:originalTrackNumber>\(track)</upnp:originalTrackNumber>" }
        xml += "<upnp:class>object.item.audioItem.musicTrack</upnp:class>"
        if let art { xml += "<upnp:albumArtURI>\(xmlEscape(art))</upnp:albumArtURI>" }
        let attributes = FileInfo(object.url).resAttributes(mime: mime, features: Self.dlnaFeatures)
        return xml + "<res \(attributes)>\(xmlEscape("\(base)/media/\(token)"))</res></item>"
    }

    // MARK: - Files

    private func media(_ token: String, _ request: HTTPRequest) -> HTTPResponse {
        guard let url = library.url(forToken: token), let mime = Library.audioTypes[url.pathExtension.lowercased()] else {
            say("stream ✗ \(token): not in the shared folder")
            return .notFound
        }
        say("stream → \(request.peer) \(library.relativePath(of: url) ?? url.lastPathComponent) "
            + "(\(request.headers["RANGE"] ?? "whole file"))")
        return .file(url, type: mime, rangeHeader: request.headers["RANGE"],
                     headers: [("transferMode.dlna.org", "Streaming"), ("contentFeatures.dlna.org", Self.dlnaFeatures)])
    }

    /// The address the control point reached us on, so the URLs work from where it stands.
    private func baseURL(for request: HTTPRequest) -> String {
        if let host = request.headers["HOST"], !host.isEmpty { return "http://\(host)" }
        let peer = request.peer.split(separator: ":").first.map(String.init) ?? ""
        return "http://\(localAddress(toward: peer) ?? "127.0.0.1"):\(port)"
    }
}
