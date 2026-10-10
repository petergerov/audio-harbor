import Darwin
import Foundation

/// Answers M-SEARCH on 239.255.255.250:1900 and announces a device with NOTIFY alive / byebye.
public final class SSDPResponder: @unchecked Sendable {
    private let uuid: String
    private let httpPort: UInt16
    private let deviceType: String
    private let serviceTypes: [String]
    private let server: String
    private let lock = NSLock()
    private var isOnline = true
    private var fd: Int32 = -1

    public init(uuid: String, httpPort: UInt16, deviceType: String, serviceTypes: [String], server: String) {
        self.uuid = uuid
        self.httpPort = httpPort
        self.deviceType = deviceType
        self.serviceTypes = serviceTypes
        self.server = server
    }

    public var online: Bool {
        get { lock.lock(); defer { lock.unlock() }; return isOnline }
        set { lock.lock(); isOnline = newValue; lock.unlock() }
    }

    /// (NT/ST, USN) pairs this device answers to and announces.
    private var targets: [(String, String)] {
        [("upnp:rootdevice", "\(uuid)::upnp:rootdevice"), (uuid, uuid), (deviceType, "\(uuid)::\(deviceType)")]
            + serviceTypes.map { ($0, "\(uuid)::\($0)") }
    }

    public func start() throws {
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw ToolError("ssdp socket: \(String(cString: strerror(errno)))") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        var any = makeIPv4("0.0.0.0", port: 1900)
        let bound = withUnsafePointer(to: &any) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw ToolError("ssdp bind :1900: \(String(cString: strerror(errno)))") }

        let interfaces = multicastInterfaces()
        for ip in interfaces {
            var request = ip_mreq(imr_multiaddr: in_addr(s_addr: inet_addr("239.255.255.250")),
                                  imr_interface: in_addr(s_addr: inet_addr(ip)))
            if setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &request, socklen_t(MemoryLayout<ip_mreq>.size)) != 0 {
                say("ssdp: join on \(ip) failed: \(String(cString: strerror(errno)))")
            }
        }
        say("ssdp: listening on 239.255.255.250:1900 via \(interfaces.joined(separator: ", "))")
        Thread.detachNewThread { [self] in receiveLoop() }
        announce(alive: true)
        // Re-announce well inside max-age, like real devices do.
        Thread.detachNewThread { [self] in
            while true {
                Thread.sleep(forTimeInterval: 60)
                if online { announce(alive: true) }
            }
        }
    }

    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) }
            }
            guard count > 0, online else { continue }
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
            let sender = ipv4Address(from)
            let port = UInt16(bigEndian: from.sin_port)
            say("ssdp ← M-SEARCH ST=\(searchTarget) from \(sender):\(port) → \(matches.count) answer(s)")
            let location = "http://\(localAddress(toward: sender) ?? "127.0.0.1"):\(httpPort)/description.xml"
            // Spread answers over a little time, as MX asks for.
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int.random(in: 20...300))) { [self] in
                for (st, usn) in matches {
                    let reply = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nDATE: \(Self.httpDate())\r\nEXT:\r\n"
                        + "LOCATION: \(location)\r\nSERVER: \(server)\r\nST: \(st)\r\nUSN: \(usn)\r\n"
                        + "BOOTID.UPNP.ORG: 1\r\n\r\n"
                    send(reply, to: sender, port: port)
                }
            }
        }
    }

    public func announce(alive: Bool) {
        for ip in multicastInterfaces() {
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
        say("ssdp → NOTIFY \(alive ? "alive" : "byebye")")
    }

    private func send(_ message: String, to host: String, port: UInt16, via interface: String? = nil) {
        let out = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard out >= 0 else { return }
        defer { close(out) }
        if let interface {
            var address = in_addr(s_addr: inet_addr(interface))
            setsockopt(out, IPPROTO_IP, IP_MULTICAST_IF, &address, socklen_t(MemoryLayout<in_addr>.size))
            var ttl: UInt8 = 4
            setsockopt(out, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        }
        var destination = makeIPv4(host, port: port)
        let bytes = Array(message.utf8)
        _ = withUnsafePointer(to: &destination) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(out, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    static func httpDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: Date())
    }
}
