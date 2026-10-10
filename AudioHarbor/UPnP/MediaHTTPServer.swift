#if os(macOS)
import Foundation
import OSLog

/// One registered stream the renderer can pull over HTTP (`/t/<token>.<ext>`).
struct MediaStreamHandle: Sendable, Hashable {
    var id: String
    var path: String
    var mime: String
}

/// Serves track files (and generated WAV) to a UPnP renderer: opaque tokens, `Range` / `HEAD`,
/// DLNA streaming headers, and URLs whose host is the Mac address toward the renderer.
@Observable
@MainActor
final class MediaHTTPServer {
    static let dlnaFeatures = ContentDirectory.dlnaFeatures
    private static let preferredPort: UInt16 = 49_153
    private static let serverName = "macOS UPnP/1.1 AudioHarbor/1.1"

    private(set) var port: UInt16 = 0
    private(set) var isRunning = false
    private(set) var lastError: String?
    private(set) var activeStreams = 0

    private let logger = Logger(subsystem: "com.gerov.audioharbor.player", category: "UPnP")
    private var http: UPnPHTTPServer?
    private var routes: [String: Route] = [:]
    private var counter = 0

    private enum Route: Sendable {
        case file(id: String, url: URL, mime: String)
        case wav(id: String, source: WAVPCMBodySource)
        case artwork(id: String, data: Data, mime: String)
    }

    func start() {
        guard !isRunning, http == nil else { return }
        let saved = UInt16(clamping: UserDefaults.standard.integer(forKey: DefaultsKey.mediaHTTPPort))
        let preferred = saved == 0 ? Self.preferredPort : saved
        let server = UPnPHTTPServer(
            serverName: Self.serverName,
            handler: { [weak self] request in
                await self?.handle(request) ?? .notFound
            },
            onStreamsChanged: { [weak self] count in
                Task { @MainActor in self?.activeStreams = count }
            }
        )
        http = server
        server.start(preferredPort: preferred) { [weak self] result in
            Task { @MainActor in
                self?.listening(result)
            }
        }
    }

    func stop() {
        http?.stop()
        http = nil
        isRunning = false
        port = 0
        routes.removeAll()
        activeStreams = 0
    }

    /// Registers `file` for pull by the renderer. Pass `mime` when known; otherwise derived from
    /// the extension. Returns a handle whose `path` is what goes into SetAVTransportURI.
    @discardableResult
    func register(file: URL, mime: String? = nil) -> MediaStreamHandle {
        let resolvedMime = mime ?? Self.mime(forExtension: file.pathExtension) ?? "application/octet-stream"
        let ext = Self.extension(forMime: resolvedMime, fallback: file.pathExtension)
        let (id, path) = nextPath(ext: ext)
        routes[path] = .file(id: id, url: file, mime: resolvedMime)
        logger.info("media register \(path, privacy: .public) → \(file.lastPathComponent, privacy: .public)")
        return MediaStreamHandle(id: id, path: path, mime: resolvedMime)
    }

    /// Registers a generated 24-bit WAV (DSD→PCM or decoded PCM) with a computed Content-Length.
    @discardableResult
    func register(wav source: WAVPCMBodySource) -> MediaStreamHandle {
        let (id, path) = nextPath(ext: "wav")
        routes[path] = .wav(id: id, source: source)
        logger.info("media register \(path, privacy: .public) → \(source.label, privacy: .public) \(source.sampleRate) Hz")
        return MediaStreamHandle(id: id, path: path, mime: source.mime)
    }

    /// Registers cover art for DIDL `albumArtURI`.
    @discardableResult
    func registerArtwork(_ data: Data, mime: String = "image/jpeg") -> MediaStreamHandle? {
        guard !data.isEmpty else { return nil }
        let ext = mime.contains("png") ? "png" : "jpg"
        let (id, path) = nextPath(prefix: "/a/", ext: ext)
        routes[path] = .artwork(id: id, data: data, mime: mime)
        return MediaStreamHandle(id: id, path: path, mime: mime)
    }

    func unregister(_ handle: MediaStreamHandle) {
        routes.removeValue(forKey: handle.path)
    }

    func unregisterAll() {
        routes.removeAll()
    }

    /// Absolute URL the renderer can reach: host = this Mac on the route toward `peerHost`.
    func url(for handle: MediaStreamHandle, toward peerHost: String) -> URL? {
        guard isRunning, port > 0,
              let host = NetworkAddress.local(toward: peerHost) else { return nil }
        return URL(string: "http://\(host):\(port)\(handle.path)")
    }

    // MARK: - HTTP

    private func nextPath(prefix: String = "/t/", ext: String) -> (id: String, path: String) {
        counter += 1
        let id = "\(counter)-\(UUID().uuidString.prefix(8))"
        let clean = ext.isEmpty ? "bin" : ext.lowercased()
        return (id, "\(prefix)\(id).\(clean)")
    }

    private func listening(_ result: Result<UInt16, Error>) {
        switch result {
        case .success(let bound):
            port = bound
            isRunning = true
            lastError = nil
            UserDefaults.standard.set(Int(bound), forKey: DefaultsKey.mediaHTTPPort)
            logger.info("Media HTTP listening on \(bound)")
        case .failure(let error):
            http = nil
            isRunning = false
            lastError = error.localizedDescription
            logger.error("Media HTTP failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ request: UPnPHTTPRequest) -> UPnPHTTPResponse {
        guard request.method == "GET" || request.method == "HEAD" else {
            return UPnPHTTPResponse(status: "405 Method Not Allowed")
        }
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        guard let route = routes[path] else { return .notFound }
        let dlna = [
            ("transferMode.dlna.org", "Streaming"),
            ("contentFeatures.dlna.org", Self.dlnaFeatures),
        ]
        switch route {
        case .file(_, let url, let mime):
            return UPnPHTTPResponse.file(
                url,
                type: mime,
                rangeHeader: request.headers["RANGE"],
                headers: dlna
            )
        case .wav(_, let source):
            return UPnPHTTPResponse.generated(
                type: source.mime,
                totalSize: source.totalSize,
                label: source.label,
                rangeHeader: request.headers["RANGE"],
                headers: dlna,
                read: { offset, maxLength in
                    try source.read(offset: offset, maxLength: maxLength)
                }
            )
        case .artwork(_, let data, let mime):
            let size = UInt64(data.count)
            return UPnPHTTPResponse.generated(
                type: mime,
                totalSize: size,
                label: "artwork",
                rangeHeader: request.headers["RANGE"],
                headers: dlna,
                read: { offset, maxLength in
                    guard offset < size else { return Data() }
                    let start = Int(offset)
                    let end = min(start + maxLength, data.count)
                    return data.subdata(in: start..<end)
                }
            )
        }
    }

    // MARK: - MIME

    nonisolated static func mime(forExtension ext: String) -> String? {
        mime(for: AudioFormat.infer(from: URL(fileURLWithPath: "x.\(ext.lowercased())")))
    }

    nonisolated static func mime(for format: AudioFormat) -> String? {
        ContentDirectory.mime(for: format)
    }

    nonisolated private static func `extension`(forMime mime: String, fallback: String) -> String {
        switch mime {
        case "audio/flac": return "flac"
        case "audio/mp4": return "m4a"
        case "audio/wav": return "wav"
        case "audio/aiff": return "aiff"
        case "audio/mpeg": return "mp3"
        case "audio/x-dsf": return "dsf"
        case "audio/x-dff": return "dff"
        case "audio/ogg": return "ogg"
        default:
            let clean = fallback.lowercased()
            return clean.isEmpty ? "bin" : clean
        }
    }
}
#endif
