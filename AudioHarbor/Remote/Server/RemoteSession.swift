import Foundation
import Network

/// One authenticated TCP session. Reads frames, routes commands, pushes snapshots.
actor RemoteSession {
    nonisolated let id = UUID()
    private let connection: NWConnection
    private let serverID: UUID
    private let serverName: String
    private let pairing: RemotePairingGate
    private let router: RemoteCommandRouter
    private let onClose: @Sendable (UUID) -> Void
    private let onSubscribed: (@Sendable (RemoteSession) async -> Void)?

    private var buffer = Data()
    private var authenticated = false
    private var clientID: UUID?
    private var topics: Set<RemoteTopic> = []
    private var closed = false

    init(
        connection: NWConnection,
        serverID: UUID,
        serverName: String,
        pairing: RemotePairingGate,
        router: RemoteCommandRouter,
        onClose: @escaping @Sendable (UUID) -> Void,
        onSubscribed: (@Sendable (RemoteSession) async -> Void)? = nil
    ) {
        self.connection = connection
        self.serverID = serverID
        self.serverName = serverName
        self.pairing = pairing
        self.router = router
        self.onClose = onClose
        self.onSubscribed = onSubscribed
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                Task { await self.close() }
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receiveLoop()
        Task {
            await send(
                .hello(
                    serverName: serverName,
                    version: RemoteProtocol.version,
                    capabilities: Array(RemoteCapability.allCases),
                    serverID: serverID
                ),
                requestID: nil
            )
        }
    }

    func cancel() {
        close()
    }

    func pushNowPlaying(_ snapshot: NowPlayingSnapshot) async {
        guard authenticated, topics.contains(.nowPlaying) else { return }
        await send(.nowPlaying(snapshot: snapshot), requestID: nil)
    }

    func pushQueue(_ snapshot: QueueSnapshot) async {
        guard authenticated, topics.contains(.queue) else { return }
        await send(.queue(snapshot: snapshot), requestID: nil)
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            Task {
                if let content, !content.isEmpty {
                    await self.handle(chunk: content)
                }
                if isComplete || error != nil {
                    await self.close()
                    return
                }
                await self.receiveLoop()
            }
        }
    }

    private func handle(chunk: Data) async {
        do {
            let frames = try FrameCodec.feed(chunk: chunk, into: &buffer)
            for frame in frames {
                guard frame.kind == .json else { continue }
                // A message this Mac does not know — from a newer remote — is refused, not fatal:
                // the framing is intact, so the session carries on.
                guard let envelope = try? FrameCodec.decodeJSON(
                    RemoteEnvelope<ClientMessage>.self,
                    from: frame.payload
                ) else {
                    await send(
                        .error(code: .unsupported, message: "This Mac does not support that request"),
                        requestID: nil
                    )
                    continue
                }
                await process(envelope)
            }
        } catch {
            await send(
                .error(code: .badRequest, message: error.localizedDescription),
                requestID: nil
            )
            await close()
        }
    }

    private func process(_ envelope: RemoteEnvelope<ClientMessage>) async {
        let requestID = envelope.id
        switch envelope.body {
        case let .hello(clientID, name, platform, version, auth):
            guard version >= RemoteProtocol.minimumSupported else {
                await send(
                    .error(code: .unsupported, message: "Protocol version too old"),
                    requestID: requestID
                )
                await close()
                return
            }
            let result = await pairing.authenticate(
                clientID: clientID,
                name: name,
                platform: platform,
                auth: auth
            )
            switch result {
            case .ok(let token, _):
                authenticated = true
                self.clientID = clientID
                // Always ack so the client can subscribe only after auth is confirmed.
                await send(.paired(token: token), requestID: requestID)
            case .lockedOut:
                await send(
                    .error(code: .busy, message: "Too many failed attempts — try again shortly"),
                    requestID: requestID
                )
                await close()
            case .denied:
                await send(
                    .error(code: .unauthorized, message: "Invalid pairing code or token"),
                    requestID: requestID
                )
                await close()
            }

        case .subscribe(let list):
            guard authenticated else {
                await send(.error(code: .unauthorized, message: "Not paired"), requestID: requestID)
                return
            }
            topics = Set(list)
            if let onSubscribed {
                await onSubscribed(self)
            }

        default:
            guard authenticated else {
                await send(.error(code: .unauthorized, message: "Not paired"), requestID: requestID)
                return
            }
            let routed = await router.handle(envelope.body, requestID: requestID)
            switch routed {
            case .none:
                break
            case let .message(message, id):
                await send(message, requestID: id)
            case let .artwork(header, bytes, id):
                await send(header, requestID: id)
                await sendBinary(bytes)
            }
        }
    }

    private func send(_ message: ServerMessage, requestID: UInt32?) async {
        do {
            let envelope = RemoteEnvelope(id: requestID, body: message)
            let data = try FrameCodec.encodeJSON(envelope)
            try await sendRaw(data)
        } catch {
            await close()
        }
    }

    private func sendBinary(_ payload: Data) async {
        do {
            try await sendRaw(FrameCodec.encodeBinary(payload))
        } catch {
            await close()
        }
    }

    private func sendRaw(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose(id)
    }
}

/// Shared pairing gate used by all sessions.
actor RemotePairingGate {
    private var activeCode: RemotePairing.ActiveCode?
    private var failedAttempts = 0
    private var lockoutUntil: Date?

    func setActiveCode(_ code: RemotePairing.ActiveCode?) {
        activeCode = code
    }

    func currentCode() -> RemotePairing.ActiveCode? {
        guard let activeCode, activeCode.expiresAt > Date() else {
            return nil
        }
        return activeCode
    }

    enum AuthResult: Sendable {
        case ok(token: Data, newlyPaired: Bool)
        case denied
        case lockedOut
    }

    func authenticate(
        clientID: UUID,
        name: String,
        platform: String,
        auth: RemoteAuth
    ) -> AuthResult {
        if let lockoutUntil, lockoutUntil > Date() {
            return .lockedOut
        }

        switch auth {
        case .token(let token):
            guard let stored = RemotePairingStore.token(for: clientID), stored == token else {
                registerFailure()
                return .denied
            }
            failedAttempts = 0
            return .ok(token: token, newlyPaired: false)

        case .pairingCode(let code):
            guard let active = currentCode(), active.code == code else {
                registerFailure()
                return .denied
            }
            let token = RemotePairing.mintToken()
            let device = RemotePairing.PairedDevice(
                id: clientID,
                name: name,
                platform: platform,
                pairedAt: Date()
            )
            RemotePairingStore.upsertDevice(device, token: token)
            activeCode = nil
            failedAttempts = 0
            return .ok(token: token, newlyPaired: true)
        }
    }

    private func registerFailure() {
        failedAttempts += 1
        if failedAttempts >= RemotePairing.maxFailedAttempts {
            lockoutUntil = Date().addingTimeInterval(RemotePairing.lockoutDuration)
            failedAttempts = 0
        }
    }
}
