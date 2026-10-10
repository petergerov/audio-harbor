#if os(macOS)
import Darwin
import Foundation
import OSLog

/// Discovers UPnP MediaRenderers on the LAN (M-SEARCH + NOTIFY) and keeps a live list for the
/// output picker. Does not play — that is Phase 3.
@Observable
@MainActor
final class SSDPBrowser {
    private(set) var renderers: [UPnPRenderer] = []
    /// Set when Local Network permission is missing or the search socket fails.
    private(set) var lastError: String?
    private(set) var isRunning = false

    /// Called whenever the published list changes (add / remove / refresh).
    var onChange: (([UPnPRenderer]) -> Void)?

    private let logger = Logger(subsystem: "com.gerov.audioharbor.player", category: "UPnP")
    private let searchTarget = "urn:schemas-upnp-org:device:MediaRenderer:1"
    private let userAgent = "macOS/14.0 UPnP/1.1 AudioHarbor/1.1"
    private let searchInterval: TimeInterval = 30
    private let defaultMaxAge: TimeInterval = 1800

    private var searchTask: Task<Void, Never>?
    private var pruneTask: Task<Void, Never>?
    private var notifySocket: Int32 = -1
    private var notifyStopped = false
    private var inFlight: Set<String> = []

    func start() {
        guard !isRunning else { return }
        isRunning = true
        notifyStopped = false
        startNotifyListener()
        searchTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isRunning {
                await self.searchOnce()
                try? await Task.sleep(for: .seconds(self.searchInterval))
            }
        }
        pruneTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isRunning {
                try? await Task.sleep(for: .seconds(15))
                self.pruneExpired()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        searchTask?.cancel()
        searchTask = nil
        pruneTask?.cancel()
        pruneTask = nil
        notifyStopped = true
        let socket = notifySocket
        notifySocket = -1
        if socket >= 0 {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { close(socket) }
        }
        renderers = []
        lastError = nil
        inFlight = []
        onChange?([])
    }

    /// One M-SEARCH round — also used after the Local Network prompt.
    func searchNow() {
        guard isRunning else { return }
        Task { await searchOnce() }
    }

    // MARK: - M-SEARCH

    private func searchOnce() async {
        let result = await Task.detached(priority: .utility) { [searchTarget, userAgent] in
            Self.multicastSearch(target: searchTarget, userAgent: userAgent, seconds: 3)
        }.value
        if let error = result.sendError {
            lastError = error
            logger.warning("SSDP search send failed: \(error, privacy: .public)")
        } else if lastError != nil {
            lastError = nil
        }
        for hit in result.hits {
            await considerLocation(hit.location, host: hit.host, maxAge: hit.maxAge, usn: hit.usn)
        }
    }

    private struct SearchHit: Sendable {
        var location: URL
        var host: String
        var maxAge: TimeInterval
        var usn: String
    }

    nonisolated private static func multicastSearch(
        target: String,
        userAgent: String,
        seconds: Double
    ) -> (hits: [SearchHit], sendError: String?) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            return ([], String(cString: strerror(errno)))
        }
        defer { close(fd) }
        var ttl: UInt8 = 4
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var group = NetworkAddress.ipv4("239.255.255.250", port: 1900)
        var sendError: String?

        func send() {
            let message = """
                M-SEARCH * HTTP/1.1\r
                HOST: 239.255.255.250:1900\r
                MAN: "ssdp:discover"\r
                MX: 2\r
                ST: \(target)\r
                USER-AGENT: \(userAgent)\r
                \r

                """
            let bytes = Array(message.utf8)
            let sent = withUnsafePointer(to: &group) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if sent < 0 {
                sendError = String(cString: strerror(errno))
            }
        }

        send()
        var hits: [SearchHit] = []
        var seen = Set<String>()
        var buffer = [UInt8](repeating: 0, count: 8192)
        let started = Date()
        var resent = false
        while Date().timeIntervalSince(started) < seconds {
            if !resent, Date().timeIntervalSince(started) > seconds / 2 {
                send()
                resent = true
            }
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &length)
                }
            }
            guard count > 0 else { continue }
            let text = String(decoding: buffer[0..<count], as: UTF8.self)
            let headers = Self.headers(from: text)
            guard let locationString = headers["LOCATION"],
                  let location = URL(string: locationString),
                  seen.insert(locationString).inserted else { continue }
            hits.append(SearchHit(
                location: location,
                host: NetworkAddress.string(from),
                maxAge: Self.maxAge(from: headers) ?? 1800,
                usn: headers["USN"] ?? ""
            ))
        }
        return (hits, sendError)
    }

    // MARK: - NOTIFY listener (port 1900, shares with the music server via SO_REUSEPORT)

    private func startNotifyListener() {
        let socket = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socket >= 0 else {
            logger.error("SSDP notify socket failed: \(String(cString: strerror(errno)), privacy: .public)")
            return
        }
        var yes: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socket, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var any = NetworkAddress.ipv4("0.0.0.0", port: 1900)
        let bound = withUnsafePointer(to: &any) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(socket)
            logger.error("SSDP notify bind :1900 failed: \(String(cString: strerror(code)), privacy: .public)")
            return
        }
        for ip in NetworkAddress.multicastInterfaces() {
            var request = ip_mreq(
                imr_multiaddr: in_addr(s_addr: inet_addr("239.255.255.250")),
                imr_interface: in_addr(s_addr: inet_addr(ip))
            )
            setsockopt(socket, IPPROTO_IP, IP_ADD_MEMBERSHIP, &request, socklen_t(MemoryLayout<ip_mreq>.size))
        }
        notifySocket = socket
        Thread.detachNewThread { [weak self] in
            self?.notifyLoop(socket)
        }
    }

    private nonisolated func notifyLoop(_ socket: Int32) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(socket, &buffer, buffer.count, 0, $0, &length)
                }
            }
            if count <= 0 {
                if errno == EBADF { break }
                let stillOurs = DispatchQueue.main.sync { [weak self] in
                    self?.notifySocket == socket && self?.notifyStopped == false
                }
                if !stillOurs { break }
                continue
            }
            let text = String(decoding: buffer[0..<count], as: UTF8.self)
            guard text.hasPrefix("NOTIFY") else { continue }
            let headers = Self.headers(from: text)
            let host = NetworkAddress.string(from)
            Task { @MainActor [weak self] in
                self?.handleNotify(headers: headers, host: host)
            }
        }
    }

    private func handleNotify(headers: [String: String], host: String) {
        let nts = headers["NTS"]?.lowercased() ?? ""
        let usn = headers["USN"] ?? ""
        let udn = usn.ssdpUDN
        if nts.contains("byebye") {
            removeRenderer(udn: udn)
            return
        }
        guard nts.contains("alive") || nts.contains("update") else { return }
        let nt = headers["NT"] ?? ""
        let isRenderer = nt.contains("MediaRenderer") || usn.contains("MediaRenderer")
            || nt == "upnp:rootdevice" || usn.hasPrefix("uuid:")
        guard isRenderer, let locationString = headers["LOCATION"],
              let location = URL(string: locationString) else { return }
        let maxAge = Self.maxAge(from: headers) ?? defaultMaxAge
        Task { await considerLocation(location, host: host, maxAge: maxAge, usn: usn) }
    }

    // MARK: - Description fetch

    private func considerLocation(_ location: URL, host: String, maxAge: TimeInterval, usn: String) async {
        let key = location.absoluteString
        if let existing = renderers.first(where: { $0.location == location }) {
            touchExpiry(udn: existing.udn, maxAge: maxAge)
            return
        }
        if let udn = usn.isEmpty ? nil : usn.ssdpUDN,
           let existing = renderers.first(where: { $0.udn == udn }) {
            touchExpiry(udn: existing.udn, maxAge: maxAge)
            return
        }
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        var request = URLRequest(url: location, timeoutInterval: 8)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                logger.debug("Description \(location.absoluteString, privacy: .public) → HTTP \(status)")
                return
            }
            let parsed = DeviceDescriptionParser.parse(data)
            guard let avt = parsed.service("AVTransport"),
                  let rcs = parsed.service("RenderingControl"),
                  let avtURL = parsed.url(avt.controlURL, relativeTo: location),
                  let rcsURL = parsed.url(rcs.controlURL, relativeTo: location),
                  !parsed.udn.isEmpty else {
                return
            }
            let name = parsed.friendlyName.isEmpty ? parsed.modelName : parsed.friendlyName
            guard !name.isEmpty else { return }
            let cm = parsed.service("ConnectionManager")
            let cmURL = cm.flatMap { parsed.url($0.controlURL, relativeTo: location) }
            let renderer = UPnPRenderer(
                udn: parsed.udn,
                name: name,
                manufacturer: parsed.manufacturer,
                modelName: parsed.modelName,
                location: location,
                host: host,
                avTransportControlURL: avtURL,
                avTransportServiceType: avt.serviceType.isEmpty
                    ? "urn:schemas-upnp-org:service:AVTransport:1" : avt.serviceType,
                renderingControlURL: rcsURL,
                renderingControlServiceType: rcs.serviceType.isEmpty
                    ? "urn:schemas-upnp-org:service:RenderingControl:1" : rcs.serviceType,
                connectionManagerURL: cmURL,
                connectionManagerServiceType: cm?.serviceType,
                expiresAt: Date().addingTimeInterval(maxAge)
            )
            upsert(renderer)
        } catch {
            logger.debug("Description fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func upsert(_ renderer: UPnPRenderer) {
        if let index = renderers.firstIndex(where: { $0.udn == renderer.udn }) {
            renderers[index] = renderer
        } else {
            renderers.append(renderer)
            renderers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            logger.info("Renderer found: \(renderer.name, privacy: .public) (\(renderer.udn, privacy: .public))")
        }
        onChange?(renderers)
    }

    private func touchExpiry(udn: String, maxAge: TimeInterval) {
        guard let index = renderers.firstIndex(where: { $0.udn == udn }) else { return }
        renderers[index].expiresAt = Date().addingTimeInterval(maxAge)
    }

    private func removeRenderer(udn: String) {
        let before = renderers.count
        renderers.removeAll { $0.udn == udn || $0.udn.ssdpUDN == udn.ssdpUDN }
        guard renderers.count != before else { return }
        logger.info("Renderer left: \(udn, privacy: .public)")
        onChange?(renderers)
    }

    private func pruneExpired() {
        let now = Date()
        let before = renderers.count
        renderers.removeAll { $0.expiresAt < now }
        guard renderers.count != before else { return }
        onChange?(renderers)
    }

    // MARK: - Headers

    nonisolated private static func headers(from message: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in message.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            result[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    nonisolated private static func maxAge(from headers: [String: String]) -> TimeInterval? {
        guard let cache = headers["CACHE-CONTROL"]?.lowercased() else { return nil }
        for part in cache.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("max-age=") else { continue }
            let value = trimmed.dropFirst("max-age=".count)
            if let seconds = TimeInterval(value) { return max(60, seconds) }
        }
        return nil
    }
}
#endif
