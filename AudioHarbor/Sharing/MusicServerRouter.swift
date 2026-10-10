#if os(macOS)
import Foundation
import OSLog

/// Answers a player's HTTP requests: the descriptions, the SOAP actions, the files and the artwork.
final class MusicServerRouter: Sendable {
    private let name: String
    private let udn: String
    private let icon: Data?
    private let directory: ContentDirectory
    private let license: LicenseService
    private let logger = Logger(subsystem: "com.gerov.audioharbor.player", category: "Sharing")

    init(name: String, udn: String, icon: Data?, directory: ContentDirectory, license: LicenseService) {
        self.name = name
        self.udn = udn
        self.icon = icon
        self.directory = directory
        self.license = license
    }

    func handle(_ request: UPnPHTTPRequest) async -> UPnPHTTPResponse {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let parts = path.split(separator: "/").map(String.init)
        switch (request.method, parts.first ?? "", parts.count) {
        case ("GET", "description.xml", 1), ("HEAD", "description.xml", 1):
            return .xml(MusicServerDocuments.description(name: name, udn: udn, hasIcon: icon != nil))
        case ("GET", "icon.png", 1), ("HEAD", "icon.png", 1):
            guard let icon else { return .notFound }
            return UPnPHTTPResponse(status: "200 OK", headers: [("Content-Type", "image/png")], body: icon)
        case ("GET", "scpd", 2):
            return MusicServerDocuments.scpd(parts[1].replacingOccurrences(of: ".xml", with: "")).map { .xml($0) } ?? .notFound
        case ("POST", "ctl", 2):
            return await soap(parts[1], request)
        case ("GET", "media", 2), ("HEAD", "media", 2):
            return await media(parts[1], request)
        case ("GET", "art", 2), ("HEAD", "art", 2):
            return artwork(parts[1])
        case ("SUBSCRIBE", "evt", 2):
            // Players subscribe to SystemUpdateID; accepting keeps them from retrying. They re-read
            // GetSystemUpdateID when they browse, so no events are sent.
            let sid = request.headers["SID"] ?? "uuid:" + UUID().uuidString.lowercased()
            return UPnPHTTPResponse(status: "200 OK", headers: [("SID", sid), ("TIMEOUT", "Second-1800")])
        case ("UNSUBSCRIBE", "evt", 2):
            return UPnPHTTPResponse(status: "200 OK")
        default:
            return .notFound
        }
    }

    // MARK: - SOAP

    private func soap(_ service: String, _ request: UPnPHTTPRequest) async -> UPnPHTTPResponse {
        let action = UPnPXML.action(fromHeader: request.headers["SOAPACTION"])
        guard let serviceType = MusicServerDocuments.services.first(where: { UPnPXML.shortName($0) == service }) else {
            return .notFound
        }
        do {
            guard MusicServerDocuments.actions(service).contains(where: { $0.0 == action }) else { throw UPnPError.invalidAction }
            let output = try await perform(service, action, UPnPXML.leaves(request.body), base: baseURL(for: request))
            return .xml(UPnPXML.response(action, serviceType: serviceType, output))
        } catch {
            let upnp = error as? UPnPError ?? .actionFailed
            logger.debug("\(service, privacy: .public).\(action, privacy: .public) → \(upnp.code)")
            return .xml(UPnPXML.fault(upnp), status: "500 Internal Server Error")
        }
    }

    private func perform(_ service: String, _ action: String, _ args: [String: String],
                         base: String) async throws -> [(String, String)] {
        switch (service, action) {
        case ("ContentDirectory", "Browse"):
            let page = try await directory.browse(
                args["ObjectID"] ?? "0",
                flag: args["BrowseFlag"] ?? "",
                start: Int(args["StartingIndex"] ?? "") ?? 0,
                count: Int(args["RequestedCount"] ?? "") ?? 0,
                base: base
            )
            return [("Result", page.didl), ("NumberReturned", String(page.returned)),
                    ("TotalMatches", String(page.total)), ("UpdateID", String(page.updateID))]
        case ("ContentDirectory", "GetSearchCapabilities"):
            return [("SearchCaps", "")]
        case ("ContentDirectory", "GetSortCapabilities"):
            return [("SortCaps", "")]
        case ("ContentDirectory", "GetSystemUpdateID"):
            return [("Id", String(await directory.updateID))]
        case ("ConnectionManager", "GetProtocolInfo"):
            let types = Set(AudioFormat.allCases.compactMap(ContentDirectory.mime(for:))).sorted()
            return [("Source", types.map { "http-get:*:\($0):*" }.joined(separator: ",")), ("Sink", "")]
        case ("ConnectionManager", "GetCurrentConnectionIDs"):
            return [("ConnectionIDs", "0")]
        case ("ConnectionManager", "GetCurrentConnectionInfo"):
            return [("RcsID", "-1"), ("AVTransportID", "-1"), ("ProtocolInfo", ""), ("PeerConnectionManager", ""),
                    ("PeerConnectionID", "-1"), ("Direction", "Output"), ("Status", "OK")]
        default:
            throw UPnPError.invalidAction
        }
    }

    // MARK: - Files

    private func media(_ token: String, _ request: UPnPHTTPRequest) async -> UPnPHTTPResponse {
        // Sharing is playback: after the trial, only with the unlock.
        guard await license.canPlay else { return .forbidden }
        guard let source = await directory.media(for: token) else { return .notFound }
        let url: URL
        let type: String
        switch source {
        case .file(let file, let mime):
            url = file
            type = mime
        case .sacd(let track):
            guard let extracted = await Self.prepared({ try SACDISO.playbackURL(for: track) }) else { return .notFound }
            url = extracted
            type = "audio/x-dff"
        case .compressedDFF(let track):
            guard let decoded = await Self.prepared({ try DFFDST.playbackURL(for: track) }) else { return .notFound }
            url = decoded
            type = "audio/x-dff"
        }
        logger.info("stream \(url.lastPathComponent, privacy: .public) to \(request.peer, privacy: .public)")
        return .file(url, type: type, rangeHeader: request.headers["RANGE"],
                     headers: [("transferMode.dlna.org", "Streaming"), ("contentFeatures.dlna.org", ContentDirectory.dlnaFeatures)])
    }

    /// Extracting a SACD track or decoding DST takes seconds — off the main actor and the server's queue.
    private static func prepared(_ work: @escaping @Sendable () throws -> URL) async -> URL? {
        await Task.detached(priority: .userInitiated) { try? work() }.value
    }

    private func artwork(_ name: String) -> UPnPHTTPResponse {
        let hash = name.split(separator: ".").first.map(String.init) ?? name
        guard ContentDirectory.isArtworkHash(hash), let data = ArtworkCache.shared.load(hash) else { return .notFound }
        return UPnPHTTPResponse(status: "200 OK", headers: [("Content-Type", "image/jpeg")], body: data)
    }

    /// The address the player reached us on, so the URLs in the answers work from where it stands.
    private func baseURL(for request: UPnPHTTPRequest) -> String {
        if let host = request.headers["HOST"], !host.isEmpty { return "http://\(host)" }
        let peer = request.peer.split(separator: ":").first.map(String.init) ?? ""
        return "http://\(NetworkAddress.local(toward: peer) ?? "127.0.0.1")"
    }
}
#endif
