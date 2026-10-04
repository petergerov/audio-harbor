import Foundation
import Network
import Observation
#if os(iOS)
import UIKit
#endif

/// Owns the Bonjour listener, pairing UI state, and snapshot fan-out.
@Observable
@MainActor
final class RemoteControlService {
    private(set) var isEnabled = false
    private(set) var isListening = false
    private(set) var statusText = "Off"
    private(set) var pairingCode: String?
    private(set) var pairingExpiresAt: Date?
    private(set) var pairedDevices: [RemotePairing.PairedDevice] = []
    private(set) var connectedClientCount = 0

    private let appModel: AppModel
    private let serverID: UUID
    private let pairingGate = RemotePairingGate()
    private var listener: NWListener?
    private var sessions: [UUID: RemoteSession] = [:]
    private var observer: PlaybackObserver?
    private var router: RemoteCommandRouter?
    private var codeRefreshTimer: Timer?

    init(appModel: AppModel) {
        self.appModel = appModel
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.remoteServerID),
           let id = UUID(uuidString: raw) {
            serverID = id
        } else {
            let id = UUID()
            UserDefaults.standard.set(id.uuidString, forKey: DefaultsKey.remoteServerID)
            serverID = id
        }
        isEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.remoteEnabled)
        pairedDevices = RemotePairingStore.loadDevices()
        if isEnabled {
            start()
        }
    }

    var serverDisplayName: String {
        #if os(macOS)
        Host.current().localizedName ?? "Audio Harbor"
        #else
        UIDevice.current.name
        #endif
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.remoteEnabled)
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func refreshPairingCode() {
        let code = RemotePairing.generateCode()
        let expires = Date().addingTimeInterval(RemotePairing.codeTTL)
        pairingCode = code
        pairingExpiresAt = expires
        Task {
            await pairingGate.setActiveCode(.init(code: code, expiresAt: expires))
        }
        codeRefreshTimer?.invalidate()
        codeRefreshTimer = Timer.scheduledTimer(withTimeInterval: RemotePairing.codeTTL, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.pairingCode = nil
                self?.pairingExpiresAt = nil
                await self?.pairingGate.setActiveCode(nil)
            }
        }
    }

    func revoke(_ device: RemotePairing.PairedDevice) {
        RemotePairingStore.revoke(clientID: device.id)
        pairedDevices = RemotePairingStore.loadDevices()
    }

    func revokeAll() {
        RemotePairingStore.revokeAll()
        pairedDevices = []
    }

    func start() {
        guard listener == nil else { return }

        let router = RemoteCommandRouter(appModel: appModel)
        self.router = router

        let observer = PlaybackObserver(
            playback: appModel.playback,
            onNowPlaying: { [weak self] snapshot in
                self?.fanOutNowPlaying(snapshot)
            },
            onQueue: { [weak self] snapshot in
                self?.fanOutQueue(snapshot)
            }
        )
        self.observer = observer
        observer.start()

        let saved = UInt16(clamping: UserDefaults.standard.integer(forKey: DefaultsKey.remotePort))
        startListener(on: saved == 0 ? nil : NWEndpoint.Port(rawValue: saved))
    }

    /// Listens on `port`, or any free port when nil. The port is remembered and asked for again
    /// next launch: a Mac that quit without a Bonjour goodbye (crash, Xcode stop) leaves its old
    /// port in the phone's mDNS cache for minutes, and a new random port would be refused there.
    private func startListener(on port: NWEndpoint.Port?) {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = if let port {
                try NWListener(using: parameters, on: port)
            } else {
                try NWListener(using: parameters)
            }
            listener.service = NWListener.Service(
                name: serverDisplayName,
                type: RemoteProtocol.serviceType,
                txtRecord: NWTXTRecord([
                    "v": "\(RemoteProtocol.version)",
                    "id": serverID.uuidString,
                    "name": serverDisplayName,
                    "pair": "1"
                ])
            )
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                    guard let self, let listener, self.listener === listener else { return }
                    self.applyListenerState(state, retryOnAnyPort: port != nil)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            statusText = "Starting…"
        } catch {
            statusText = "Failed: \(error.localizedDescription)"
            isListening = false
        }
    }

    func stop() {
        codeRefreshTimer?.invalidate()
        codeRefreshTimer = nil
        pairingCode = nil
        pairingExpiresAt = nil
        Task { await pairingGate.setActiveCode(nil) }

        observer?.stop()
        observer = nil
        router = nil

        let open = sessions
        sessions.removeAll()
        connectedClientCount = 0
        for session in open.values {
            Task { await session.cancel() }
        }

        listener?.cancel()
        listener = nil
        isListening = false
        statusText = "Off"
    }

    private func accept(_ connection: NWConnection) {
        guard let router else {
            connection.cancel()
            return
        }
        let session = RemoteSession(
            connection: connection,
            serverID: serverID,
            serverName: serverDisplayName,
            pairing: pairingGate,
            router: router,
            onClose: { [weak self] id in
                Task { @MainActor in
                    self?.sessions.removeValue(forKey: id)
                    self?.connectedClientCount = self?.sessions.count ?? 0
                    self?.pairedDevices = RemotePairingStore.loadDevices()
                }
            },
            onSubscribed: { [weak self] session in
                guard let self else { return }
                let now = await MainActor.run { self.observer?.currentNowPlaying() }
                let queue = await MainActor.run { self.observer?.currentQueue() }
                if let now { await session.pushNowPlaying(now) }
                if let queue { await session.pushQueue(queue) }
            }
        )
        sessions[session.id] = session
        connectedClientCount = sessions.count
        Task { await session.start() }
    }

    private func applyListenerState(_ state: NWListener.State, retryOnAnyPort: Bool) {
        switch state {
        case .ready:
            isListening = true
            statusText = "Listening as \(serverDisplayName)"
            if let port = listener?.port {
                UserDefaults.standard.set(Int(port.rawValue), forKey: DefaultsKey.remotePort)
            }
        case .failed(let error):
            if retryOnAnyPort {
                // The remembered port is taken; any free one, remembered from now on.
                listener?.cancel()
                listener = nil
                startListener(on: nil)
                return
            }
            isListening = false
            statusText = "Failed: \(error.localizedDescription)"
        case .cancelled:
            isListening = false
            statusText = isEnabled ? "Stopped" : "Off"
        default:
            break
        }
    }

    private func fanOutNowPlaying(_ snapshot: NowPlayingSnapshot) {
        let sessions = self.sessions.values
        for session in sessions {
            Task { await session.pushNowPlaying(snapshot) }
        }
    }

    private func fanOutQueue(_ snapshot: QueueSnapshot) {
        let sessions = self.sessions.values
        for session in sessions {
            Task { await session.pushQueue(snapshot) }
        }
    }
}
