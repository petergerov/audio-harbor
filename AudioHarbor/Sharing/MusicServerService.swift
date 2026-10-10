#if os(macOS)
import AppKit
import Foundation
import Observation

/// Shares the catalogue on the home network as a UPnP / DLNA music server: players such as
/// mconnect on an iPhone browse it and play the files themselves. Off until turned on in Settings.
@Observable
@MainActor
final class MusicServerService {
    private(set) var isEnabled = false
    private(set) var statusText = "Off"
    /// Files being sent to players right now.
    private(set) var activeStreams = 0
    /// The name players list the server under.
    let serverName: String

    private let library: LibraryService
    private let playlists: PlaylistService
    private let license: LicenseService
    private let udn: String
    private var http: UPnPHTTPServer?
    private var ssdp: SSDPResponder?
    private var awake: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?

    private static let serverHeader = "macOS UPnP/1.0 AudioHarbor/1.0"

    init(library: LibraryService, playlists: PlaylistService, license: LicenseService) {
        self.library = library
        self.playlists = playlists
        self.license = license
        serverName = "Audio Harbor (\(Host.current().localizedName ?? "Mac"))"
        // One UDN for this Mac, so players recognise the server after a restart.
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.sharingDeviceID), let id = UUID(uuidString: raw) {
            udn = "uuid:" + id.uuidString.lowercased()
        } else {
            let id = UUID()
            UserDefaults.standard.set(id.uuidString, forKey: DefaultsKey.sharingDeviceID)
            udn = "uuid:" + id.uuidString.lowercased()
        }
        isEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.sharingEnabled)
        // Say goodbye on the network when the app quits, so players drop the server at once.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopServing() }
        }
        if isEnabled {
            startServing()
        }
    }

    /// True while sharing is on but the trial has ended: players can browse, not play.
    var isBlockedByLicense: Bool { isEnabled && !license.canPlay }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled, !license.canPlay {
            license.requestUnlock()
            return
        }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.sharingEnabled)
        if enabled {
            startServing()
        } else {
            stopServing()
        }
    }

    private func startServing() {
        guard http == nil else { return }
        statusText = "Starting…"
        let directory = ContentDirectory(catalogue: LibraryCatalogue(library: library, playlists: playlists))
        let router = MusicServerRouter(name: serverName, udn: udn, icon: Self.iconPNG(), directory: directory, license: license)
        let server = UPnPHTTPServer(
            serverName: Self.serverHeader,
            handler: { request in await router.handle(request) },
            onStreamsChanged: { [weak self] count in
                Task { @MainActor in self?.streamsChanged(count) }
            }
        )
        http = server
        // The port of the last run: players that cached the server's address keep reaching it.
        let saved = UInt16(clamping: UserDefaults.standard.integer(forKey: DefaultsKey.sharingPort))
        server.start(preferredPort: saved) { [weak self] result in
            Task { @MainActor in self?.listening(result, server: server) }
        }
    }

    private func listening(_ result: Result<UInt16, Error>, server: UPnPHTTPServer) {
        guard http === server else { return }
        switch result {
        case .success(let port):
            UserDefaults.standard.set(Int(port), forKey: DefaultsKey.sharingPort)
            let responder = SSDPResponder(uuid: udn, httpPort: port, deviceType: MusicServerDocuments.deviceType,
                                          serviceTypes: MusicServerDocuments.services, server: Self.serverHeader)
            do {
                try responder.start()
                ssdp = responder
                statusText = "Sharing as “\(serverName)”"
            } catch {
                statusText = "Players cannot find this Mac: \(error.localizedDescription)"
            }
        case .failure(let error):
            http = nil
            statusText = "Failed: \(error.localizedDescription)"
        }
    }

    private func stopServing() {
        ssdp?.stop()
        ssdp = nil
        http?.stop()
        http = nil
        streamsChanged(0)
        statusText = "Off"
    }

    /// Keeps the Mac from idle sleep while a player streams; nobody touches the Mac meanwhile.
    private func streamsChanged(_ count: Int) {
        activeStreams = count
        if count > 0, awake == nil {
            awake = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled],
                                                          reason: "Streaming music to a player on the network")
        } else if count == 0, let token = awake {
            ProcessInfo.processInfo.endActivity(token)
            awake = nil
        }
    }

    /// The app icon at 120 px, for players that show the server with its icon.
    private static func iconPNG() -> Data? {
        let icon = NSApplication.shared.applicationIconImage
        guard let icon, let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 120, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: 120, height: 120)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(x: 0, y: 0, width: 120, height: 120))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
