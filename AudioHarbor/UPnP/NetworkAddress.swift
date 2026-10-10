#if os(macOS)
import Darwin
import Foundation

/// IPv4 helpers for SSDP: socket addresses, this Mac's address toward a peer, multicast interfaces.
enum NetworkAddress {
    static func ipv4(_ host: String, port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = inet_addr(host)
        return address
    }

    static func string(_ address: sockaddr_in) -> String {
        String(cString: inet_ntoa(address.sin_addr))
    }

    /// This Mac's IPv4 address on the interface that routes to `host` — the one `host` can reach.
    static func local(toward host: String) -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var remote = ipv4(host, port: 1900)
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
        return named == 0 ? string(local) : nil
    }

    /// IPv4 addresses of the interfaces that are up and take multicast, loopback included.
    static func multicastInterfaces() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  flags & IFF_UP != 0, flags & (IFF_MULTICAST | IFF_LOOPBACK) != 0 else { continue }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { string($0.pointee) }
            if !result.contains(ip) { result.append(ip) }
        }
        return result
    }
}
#endif
