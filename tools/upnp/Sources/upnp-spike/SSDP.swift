import Darwin
import Foundation
import UPnPCommon

struct SSDPResponse: Sendable {
    let address: String
    let headers: [String: String]
    var location: String? { headers["LOCATION"] }
}

/// Plain BSD sockets: the least magic, and errors (e.g. no Local Network permission) show as errno.
enum SSDP {
    /// The answers, and the error of a send that failed (nil when every send went out).
    static func search(seconds: Double, targets: [String]) -> (responses: [SSDPResponse], sendError: String?) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            let error = String(cString: strerror(errno))
            say("ssdp: socket failed: \(error)")
            return ([], error)
        }
        defer { close(fd) }
        var ttl: UInt8 = 4
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var group = makeIPv4("239.255.255.250", port: 1900)
        var sendError: String?

        func send(_ target: String) {
            let message = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\n"
                + "ST: \(target)\r\nUSER-AGENT: macOS UPnP/1.1 AudioHarborSpike/0.1\r\n\r\n"
            let bytes = Array(message.utf8)
            let sent = withUnsafePointer(to: &group) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if sent < 0 {
                sendError = String(cString: strerror(errno))
                say("ssdp: send failed: \(sendError ?? "?") — Local Network permission for the terminal app?")
            }
        }

        targets.forEach(send)
        var results: [SSDPResponse] = []
        var buffer = [UInt8](repeating: 0, count: 8192)
        let started = Date()
        var resent = false
        while Date().timeIntervalSince(started) < seconds {
            // UDP gets lost; ask a second time halfway.
            if !resent, Date().timeIntervalSince(started) > seconds / 2 {
                targets.forEach(send)
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
            var headers: [String: String] = [:]
            for line in text.components(separatedBy: "\r\n").dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
                headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            results.append(SSDPResponse(address: ipv4Address(from), headers: headers))
        }
        return (results, sendError)
    }
}
