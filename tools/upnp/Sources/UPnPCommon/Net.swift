import Darwin
import Foundation

public func hms(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
}

/// "0:01:23" or "0:01:23.456" → seconds; nil for NOT_IMPLEMENTED and friends.
public func parseTime(_ text: String) -> Double? {
    let parts = text.split(separator: ":")
    guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else {
        return nil
    }
    return h * 3600 + m * 60 + s
}

public func ipv4Address(_ address: sockaddr_in) -> String {
    String(cString: inet_ntoa(address.sin_addr))
}

public func makeIPv4(_ host: String, port: UInt16) -> sockaddr_in {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    address.sin_addr.s_addr = inet_addr(host)
    return address
}

/// This Mac's IPv4 address on the interface that routes to `host` — what `host` can reach us on.
public func localAddress(toward host: String) -> String? {
    let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var remote = makeIPv4(host, port: 1900)
    let connected = withUnsafePointer(to: &remote) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard connected == 0 else { return nil }
    var local = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &local) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
    }
    guard named == 0 else { return nil }
    return ipv4Address(local)
}

/// IPv4 addresses of the up, multicast-capable interfaces (loopback included, for same-Mac tests).
public func multicastInterfaces() -> [String] {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return [] }
    defer { freeifaddrs(head) }
    var result: [String] = []
    for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let flags = Int32(entry.pointee.ifa_flags)
        guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
              flags & IFF_UP != 0, flags & IFF_MULTICAST != 0 || flags & IFF_LOOPBACK != 0 else { continue }
        let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ipv4Address($0.pointee) }
        if !result.contains(ip) { result.append(ip) }
    }
    return result
}
