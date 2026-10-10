#if os(macOS)
import Darwin
import Foundation
import OSLog

/// Answers M-SEARCH on 239.255.255.250:1900 and announces the device with NOTIFY alive / byebye,
/// so players on the network find it.
final class SSDPResponder: @unchecked Sendable {
    private let uuid: String
    private let httpPort: UInt16
    private let deviceType: String
    private let serviceTypes: [String]
    private let server: String
    private let logger = Logger(subsystem: "com.gerov.audioharbor.player", category: "Sharing")
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var stopped = false
    private var announcer: DispatchSourceTimer?

    init(uuid: String, httpPort: UInt16, deviceType: String, serviceTypes: [String], server: String) {
        self.uuid = uuid
        self.httpPort = httpPort
        self.deviceType = deviceType
        self.serviceTypes = serviceTypes
        self.server = server
    }

    /// (NT/ST, USN) pairs this device answers to and announces.
    private var targets: [(String, String)] {
        [("upnp:rootdevice", "\(uuid)::upnp:rootdevice"), (uuid, uuid), (deviceType, "\(uuid)::\(deviceType)")]
            + serviceTypes.map { ($0, "\(uuid)::\($0)") }
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func start() throws {
        let socket = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socket >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var yes: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socket, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        // Wake up once a second, so `stop()` is noticed without closing the socket under the reader.
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var any = NetworkAddress.ipv4("0.0.0.0", port: 1900)
        let bound = withUnsafePointer(to: &any) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else {
            let code = errno
            close(socket)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EADDRINUSE)
        }
        for ip in NetworkAddress.multicastInterfaces() {
            var request = ip_mreq(imr_multiaddr: in_addr(s_addr: inet_addr("239.255.255.250")),
                                  imr_interface: in_addr(s_addr: inet_addr(ip)))
            setsockopt(socket, IPPROTO_IP, IP_ADD_MEMBERSHIP, &request, socklen_t(MemoryLayout<ip_mreq>.size))
        }
        lock.lock()
        fd = socket
        stopped = false
        lock.unlock()

        Thread.detachNewThread { [self] in receiveLoop(socket) }
        announce(alive: true)
        // Re-announce well inside max-age, as devices do.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak self] in self?.announce(alive: true) }
        timer.resume()
        lock.lock()
        announcer = timer
        lock.unlock()
    }

    /// Says goodbye on the network and closes the socket.
    func stop() {
        lock.lock()
        guard !stopped, fd >= 0 else {
            lock.unlock()
            return
        }
        stopped = true
        let socket = fd
        fd = -1
        let timer = announcer
        announcer = nil
        lock.unlock()
        timer?.cancel()
        announce(alive: false)
        // The reader notices `stopped` within a second; close after it can no longer use the socket.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { close(socket) }
    }

    private func receiveLoop(_ socket: Int32) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while !isStopped {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(socket, &buffer, buffer.count, 0, $0, &length) }
            }
            guard count > 0, !isStopped else { continue }
            let text = String(decoding: buffer[0..<count], as: UTF8.self)
            guard text.hasPrefix("M-SEARCH") else { continue }
            var headers: [String: String] = [:]
            for line in text.components(separatedBy: "\r\n").dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()] =
                    line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let searchTarget = headers["ST"] ?? ""
            let matches = searchTarget == "ssdp:all" ? targets : targets.filter { $0.0 == searchTarget }
            guard !matches.isEmpty else { continue }
            let sender = NetworkAddress.string(from)
            let port = UInt16(bigEndian: from.sin_port)
            let location = "http://\(NetworkAddress.local(toward: sender) ?? "127.0.0.1"):\(httpPort)/description.xml"
            logger.debug("M-SEARCH \(searchTarget, privacy: .public) from \(sender, privacy: .public)")
            // Spread the answers over a little time, as MX asks.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(Int.random(in: 20...300))) { [self] in
                for (st, usn) in matches {
                    send("HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nDATE: \(Self.httpDate())\r\nEXT:\r\n"
                         + "LOCATION: \(location)\r\nSERVER: \(server)\r\nST: \(st)\r\nUSN: \(usn)\r\n"
                         + "BOOTID.UPNP.ORG: 1\r\n\r\n", to: sender, port: port)
                }
            }
        }
    }

    private func announce(alive: Bool) {
        for ip in NetworkAddress.multicastInterfaces() {
            let location = "http://\(ip):\(httpPort)/description.xml"
            for (nt, usn) in targets {
                var message = "NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nNT: \(nt)\r\n"
                    + "NTS: \(alive ? "ssdp:alive" : "ssdp:byebye")\r\nUSN: \(usn)\r\n"
                if alive {
                    message += "CACHE-CONTROL: max-age=1800\r\nLOCATION: \(location)\r\nSERVER: \(server)\r\n"
                }
                send(message + "\r\n", to: "239.255.255.250", port: 1900, via: ip)
            }
        }
    }

    private func send(_ message: String, to host: String, port: UInt16, via interface: String? = nil) {
        let out = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard out >= 0 else { return }
        defer { close(out) }
        if let interface {
            var address = in_addr(s_addr: inet_addr(interface))
            setsockopt(out, IPPROTO_IP, IP_MULTICAST_IF, &address, socklen_t(MemoryLayout<in_addr>.size))
            var ttl: UInt8 = 4
            setsockopt(out, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        }
        var destination = NetworkAddress.ipv4(host, port: port)
        let bytes = Array(message.utf8)
        _ = withUnsafePointer(to: &destination) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(out, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    private static func httpDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: Date())
    }
}
#endif
