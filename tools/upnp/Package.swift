// swift-tools-version:5.9
import PackageDescription

// Dev tools for docs/UPNP.md. Not part of the app target.
// - upnp-spike: control point that tests a real renderer (phase 0).
// - upnp-renderer-sim: a fake UPnP MediaRenderer to develop against without the device.
// - upnp-media-server: a prototype of Audio Harbor as a UPnP / DLNA music server.
let package = Package(
    name: "upnp-tools",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "UPnPCommon", path: "Sources/UPnPCommon"),
        .executableTarget(name: "upnp-spike", dependencies: ["UPnPCommon"], path: "Sources/upnp-spike"),
        .executableTarget(name: "upnp-renderer-sim", dependencies: ["UPnPCommon"], path: "Sources/upnp-renderer-sim"),
        .executableTarget(name: "upnp-media-server", dependencies: ["UPnPCommon"], path: "Sources/upnp-media-server"),
    ]
)
