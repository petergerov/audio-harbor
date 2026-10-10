#if os(macOS)
import Foundation

/// A UPnP MediaRenderer found on the LAN — enough to show in the output picker and, later, to
/// drive AVTransport / RenderingControl.
struct UPnPRenderer: Identifiable, Hashable, Sendable {
    var udn: String
    var name: String
    var manufacturer: String
    var modelName: String
    var location: URL
    /// Peer IPv4 from the SSDP packet — used for interface-correct HTTP URLs later.
    var host: String
    var avTransportControlURL: URL
    var avTransportServiceType: String
    var renderingControlURL: URL
    var renderingControlServiceType: String
    var connectionManagerURL: URL?
    var connectionManagerServiceType: String?
    var expiresAt: Date

    var id: String { udn }

    /// Stable pick key stored in `DefaultsKey.outputDevice`.
    var outputUID: String { "upnp:\(udn)" }

    var asOutputDevice: OutputDevice {
        OutputDevice(
            uid: outputUID,
            name: name,
            supportsExclusive: false,
            supportsDoP: false,
            kind: .network
        )
    }
}

extension String {
    /// `uuid:…` from a USN such as `uuid:…::urn:schemas-upnp-org:device:MediaRenderer:1`.
    var ssdpUDN: String {
        let parts = split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].lowercased() == "uuid" else { return self }
        let rest = String(parts[1])
        if let cut = rest.range(of: "::") {
            return "uuid:" + rest[..<cut.lowerBound]
        }
        return "uuid:" + rest
    }
}
#endif
