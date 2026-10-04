import Foundation
import Network

/// Low-level framed connection to a Harbor remote server.
actor RemoteClientConnection {
    enum State: Sendable {
        case idle
        case connecting
        case ready
        case failed(String)
        case cancelled
    }

    private let connection: NWConnection
    private var buffer = Data()
    private var closed = false
    private let frameStream: AsyncStream<DecodedFrame>
    private var frameContinuation: AsyncStream<DecodedFrame>.Continuation
    private var startContinuation: CheckedContinuation<Void, Error>?
    private(set) var state: State = .idle

    var frames: AsyncStream<DecodedFrame> { frameStream }

    init(endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        connection = NWConnection(to: endpoint, using: parameters)
        var cont: AsyncStream<DecodedFrame>.Continuation!
        frameStream = AsyncStream { cont = $0 }
        frameContinuation = cont
    }

    func start() async throws {
        state = .connecting
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            startContinuation = cont
            connection.stateUpdateHandler = { [weak self] newState in
                Task { await self?.handleState(newState) }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
        receiveLoop()
    }

    func sendJSON<T: Encodable>(_ value: T) async throws {
        let data = try FrameCodec.encodeJSON(value)
        try await sendRaw(data)
    }

    func cancel() {
        guard !closed else { return }
        closed = true
        state = .cancelled
        if let startContinuation {
            self.startContinuation = nil
            startContinuation.resume(throwing: CancellationError())
        }
        frameContinuation.finish()
        connection.cancel()
    }

    private func handleState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            guard case .connecting = state else { return }
            state = .ready
            startContinuation?.resume()
            startContinuation = nil
        case .failed(let error):
            state = .failed(error.localizedDescription)
            startContinuation?.resume(throwing: error)
            startContinuation = nil
            frameContinuation.finish()
        case .waiting(let error):
            // Refused or unreachable (Mac firewall, other network, local network access off).
            // NWConnection would retry forever behind a spinner; report it instead.
            guard case .connecting = state else { return }
            state = .failed(error.localizedDescription)
            startContinuation?.resume(throwing: error)
            startContinuation = nil
            frameContinuation.finish()
            closed = true
            connection.cancel()
        case .cancelled:
            state = .cancelled
            startContinuation?.resume(throwing: CancellationError())
            startContinuation = nil
            frameContinuation.finish()
        default:
            break
        }
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            Task {
                if let content, !content.isEmpty {
                    await self.handle(chunk: content)
                }
                if isComplete || error != nil {
                    await self.cancel()
                    return
                }
                await self.receiveLoop()
            }
        }
    }

    private func handle(chunk: Data) {
        do {
            let frames = try FrameCodec.feed(chunk: chunk, into: &buffer)
            for frame in frames {
                frameContinuation.yield(frame)
            }
        } catch {
            state = .failed(error.localizedDescription)
            cancel()
        }
    }

    private func sendRaw(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }
}
