#if os(macOS)
import Foundation
import Network
import OSLog

struct UPnPHTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    let peer: String
}

struct UPnPHTTPResponse: Sendable {
    /// Part of a file, streamed from disk instead of held in memory.
    struct FileSlice: Sendable {
        let url: URL
        let offset: UInt64
        let length: UInt64
    }

    /// Part of a generated body (e.g. WAV transcode) with a known total size for `Range`.
    struct GeneratedSlice: Sendable {
        let label: String
        let totalSize: UInt64
        let offset: UInt64
        let length: UInt64
        let read: @Sendable (UInt64, Int) throws -> Data
    }

    var status: String
    var headers: [(String, String)] = []
    var body = Data()
    var file: FileSlice?
    var generated: GeneratedSlice?

    static func xml(_ text: String, status: String = "200 OK") -> UPnPHTTPResponse {
        UPnPHTTPResponse(status: status, headers: [("Content-Type", "text/xml; charset=\"utf-8\"")], body: Data(text.utf8))
    }

    static let notFound = UPnPHTTPResponse(status: "404 Not Found")
    static let forbidden = UPnPHTTPResponse(status: "403 Forbidden")

    /// The whole file (200), or the part a `Range` header asks for (206); 416 when that part does not exist.
    static func file(_ url: URL, type: String, rangeHeader: String?, headers extra: [(String, String)] = []) -> UPnPHTTPResponse {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes?[.size] as? NSNumber)?.uint64Value else { return .notFound }
        let common = [("Content-Type", type), ("Accept-Ranges", "bytes")] + extra
        guard let rangeHeader else {
            return UPnPHTTPResponse(status: "200 OK", headers: common, file: FileSlice(url: url, offset: 0, length: size))
        }
        guard let bounds = byteRange(rangeHeader, size: size) else {
            return UPnPHTTPResponse(status: "416 Range Not Satisfiable", headers: [("Content-Range", "bytes */\(size)")])
        }
        let (start, end) = bounds
        return UPnPHTTPResponse(status: "206 Partial Content", headers: common + [("Content-Range", "bytes \(start)-\(end)/\(size)")],
                                file: FileSlice(url: url, offset: start, length: end - start + 1))
    }

    /// Generated body with computed `Content-Length` — `read(absoluteOffset, maxBytes)`.
    static func generated(
        type: String,
        totalSize: UInt64,
        label: String,
        rangeHeader: String?,
        headers extra: [(String, String)] = [],
        read: @escaping @Sendable (UInt64, Int) throws -> Data
    ) -> UPnPHTTPResponse {
        let common = [("Content-Type", type), ("Accept-Ranges", "bytes")] + extra
        guard let rangeHeader else {
            return UPnPHTTPResponse(
                status: "200 OK",
                headers: common,
                generated: GeneratedSlice(label: label, totalSize: totalSize, offset: 0, length: totalSize, read: read)
            )
        }
        guard let bounds = byteRange(rangeHeader, size: totalSize) else {
            return UPnPHTTPResponse(status: "416 Range Not Satisfiable", headers: [("Content-Range", "bytes */\(totalSize)")])
        }
        let (start, end) = bounds
        return UPnPHTTPResponse(
            status: "206 Partial Content",
            headers: common + [("Content-Range", "bytes \(start)-\(end)/\(totalSize)")],
            generated: GeneratedSlice(
                label: label,
                totalSize: totalSize,
                offset: start,
                length: end - start + 1,
                read: read
            )
        )
    }

    /// `bytes=a-b`, `bytes=a-` or `bytes=-n` → the first range, clamped to the file; nil when it lies outside.
    static func byteRange(_ value: String, size: UInt64) -> (UInt64, UInt64)? {
        guard size > 0, value.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = value.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            guard let suffix = UInt64(parts[1]), suffix > 0 else { return nil }
            return (size - min(suffix, size), size - 1)
        }
        guard let start = UInt64(parts[0]), start < size else { return nil }
        let end = UInt64(parts[1]).map { min($0, size - 1) } ?? size - 1
        return end >= start ? (start, end) : nil
    }
}

/// HTTP/1.1 for UPnP: one request per connection (`Connection: close`), file bodies streamed from
/// disk at the pace the player reads them.
final class UPnPHTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (UPnPHTTPRequest) async -> UPnPHTTPResponse

    private let queue = DispatchQueue(label: "app.audioharbor.sharing.http")
    private let handler: Handler
    private let serverName: String
    private let onStreamsChanged: @Sendable (Int) -> Void
    private let logger = Logger(subsystem: "com.gerov.audioharbor.player", category: "Sharing")
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var streams = 0

    /// `onStreamsChanged` gets the number of files being sent, on the server's queue.
    init(serverName: String, handler: @escaping Handler, onStreamsChanged: @escaping @Sendable (Int) -> Void) {
        self.serverName = serverName
        self.handler = handler
        self.onStreamsChanged = onStreamsChanged
    }

    /// Listens on `preferredPort`, or on any free port when that one is taken, and reports the port.
    func start(preferredPort: UInt16?, completion: @escaping @Sendable (Result<UInt16, Error>) -> Void) {
        let preferred = preferredPort.flatMap { $0 == 0 ? nil : NWEndpoint.Port(rawValue: $0) }
        queue.async { [self] in
            attempt([preferred, .any].compactMap { $0 }[...], completion: completion)
        }
    }

    func stop() {
        queue.async { [self] in
            lock.lock()
            let open = connections.values
            connections.removeAll()
            let listener = self.listener
            self.listener = nil
            lock.unlock()
            listener?.cancel()
            open.forEach { $0.cancel() }
        }
    }

    private func attempt(_ ports: ArraySlice<NWEndpoint.Port>, completion: @escaping @Sendable (Result<UInt16, Error>) -> Void) {
        guard let port = ports.first else {
            completion(.failure(NWError.posix(.EADDRINUSE)))
            return
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: port) else {
            attempt(ports.dropFirst(), completion: completion)
            return
        }
        let reported = Flag()
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else { return }
            switch state {
            case .ready where !reported.isSet:
                reported.set()
                completion(.success(listener.port?.rawValue ?? 0))
            case .failed(let error):
                listener.cancel()
                if reported.isSet {
                    logger.error("listener failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    reported.set()
                    attempt(ports.dropFirst(), completion: completion)
                }
            default:
                break
            }
        }
        lock.lock()
        self.listener = listener
        lock.unlock()
        listener.start(queue: queue)
    }

    // MARK: - Requests

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        lock.lock()
        connections[key] = connection
        lock.unlock()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                guard let self else { return }
                self.lock.lock()
                self.connections.removeValue(forKey: key)
                self.lock.unlock()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if complete || error != nil || buffer.count > 65536 { connection.cancel() } else { receive(connection, buffer: buffer) }
                return
            }
            let lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()] =
                    line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let length = min(Int(headers["CONTENT-LENGTH"] ?? "") ?? 0, 1 << 20)
            let body = Data(buffer[end.upperBound...])
            if body.count < length, !complete, error == nil {
                receive(connection, buffer: buffer)
                return
            }
            let parts = lines[0].split(separator: " ").map(String.init)
            guard parts.count >= 2 else {
                connection.cancel()
                return
            }
            let request = UPnPHTTPRequest(method: parts[0].uppercased(), path: parts[1], headers: headers,
                                          body: body.prefix(length), peer: "\(connection.endpoint)")
            Task {
                let response = await handler(request)
                send(response, on: connection, request: request)
            }
        }
    }

    private func send(_ response: UPnPHTTPResponse, on connection: NWConnection, request: UPnPHTTPRequest) {
        let length = response.file?.length ?? response.generated?.length ?? UInt64(response.body.count)
        var head = "HTTP/1.1 \(response.status)\r\n"
        for (name, value) in response.headers { head += "\(name): \(value)\r\n" }
        head += "Content-Length: \(length)\r\nServer: \(serverName)\r\nConnection: close\r\n\r\n"
        var data = Data(head.utf8)
        if request.method != "HEAD", response.file == nil, response.generated == nil {
            data.append(response.body)
        }
        connection.send(content: data, completion: .contentProcessed { [self] error in
            guard error == nil, request.method != "HEAD" else {
                connection.cancel()
                return
            }
            if let slice = response.file, slice.length > 0,
               let file = try? FileHandle(forReadingFrom: slice.url),
               (try? file.seek(toOffset: slice.offset)) != nil {
                changeStreams(by: 1)
                pumpFile(connection, file, label: slice.url.lastPathComponent, remaining: slice.length, sent: 0)
                return
            }
            if let slice = response.generated, slice.length > 0 {
                changeStreams(by: 1)
                pumpGenerated(connection, slice, cursor: slice.offset, remaining: slice.length, sent: 0)
                return
            }
            connection.cancel()
        })
    }

    /// 256 KB at a time; the next read waits for the previous send, so the player sets the pace.
    private func pumpFile(_ connection: NWConnection, _ file: FileHandle, label: String, remaining: UInt64, sent: UInt64) {
        guard remaining > 0 else {
            try? file.close()
            changeStreams(by: -1)
            logger.debug("sent \(label, privacy: .public): \(sent) bytes")
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let chunk = file.readData(ofLength: Int(min(remaining, 256 * 1024)))
        guard !chunk.isEmpty else {
            try? file.close()
            changeStreams(by: -1)
            connection.cancel()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [self] error in
            if error != nil {
                // The player hung up — it seeks with a new request, or stopped.
                try? file.close()
                changeStreams(by: -1)
                connection.cancel()
                return
            }
            pumpFile(connection, file, label: label, remaining: remaining - UInt64(chunk.count), sent: sent + UInt64(chunk.count))
        })
    }

    private func pumpGenerated(
        _ connection: NWConnection,
        _ slice: UPnPHTTPResponse.GeneratedSlice,
        cursor: UInt64,
        remaining: UInt64,
        sent: UInt64
    ) {
        guard remaining > 0 else {
            changeStreams(by: -1)
            logger.debug("sent \(slice.label, privacy: .public): \(sent) bytes")
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let want = Int(min(remaining, 256 * 1024))
        let chunk: Data
        do {
            chunk = try slice.read(cursor, want)
        } catch {
            changeStreams(by: -1)
            connection.cancel()
            return
        }
        guard !chunk.isEmpty else {
            changeStreams(by: -1)
            connection.cancel()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [self] error in
            if error != nil {
                changeStreams(by: -1)
                connection.cancel()
                return
            }
            pumpGenerated(
                connection,
                slice,
                cursor: cursor + UInt64(chunk.count),
                remaining: remaining - UInt64(chunk.count),
                sent: sent + UInt64(chunk.count)
            )
        })
    }

    private func changeStreams(by delta: Int) {
        lock.lock()
        streams = max(0, streams + delta)
        let count = streams
        lock.unlock()
        onStreamsChanged(count)
    }
}

/// Set once, read from the listener's callbacks.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
#endif
