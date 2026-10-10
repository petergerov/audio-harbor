import Foundation
import Network

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data
    public let peer: String
}

public struct HTTPResponse: Sendable {
    /// Part of a file, streamed from disk instead of held in memory.
    public struct FileSlice: Sendable {
        public let url: URL
        public let offset: UInt64
        public let length: UInt64
    }

    public var status: String
    public var headers: [(String, String)]
    public var body: Data
    public var file: FileSlice?

    public init(status: String, headers: [(String, String)] = [], body: Data = Data(), file: FileSlice? = nil) {
        self.status = status
        self.headers = headers
        self.body = body
        self.file = file
    }

    public static func xml(_ text: String, status: String = "200 OK") -> HTTPResponse {
        HTTPResponse(status: status, headers: [("Content-Type", "text/xml; charset=\"utf-8\"")], body: Data(text.utf8))
    }

    public static let notFound = HTTPResponse(status: "404 Not Found")

    /// The whole file (200), or the part a `Range` header asks for (206); 416 when that part does not exist.
    public static func file(_ url: URL, type: String, rangeHeader: String?, headers extra: [(String, String)] = []) -> HTTPResponse {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes?[.size] as? NSNumber)?.uint64Value else { return .notFound }
        let common = [("Content-Type", type), ("Accept-Ranges", "bytes")] + extra
        guard let rangeHeader else {
            return HTTPResponse(status: "200 OK", headers: common, file: FileSlice(url: url, offset: 0, length: size))
        }
        guard let bounds = parseByteRange(rangeHeader, size: size) else {
            return HTTPResponse(status: "416 Range Not Satisfiable", headers: [("Content-Range", "bytes */\(size)")])
        }
        let (start, end) = bounds
        return HTTPResponse(status: "206 Partial Content", headers: common + [("Content-Range", "bytes \(start)-\(end)/\(size)")],
                            file: FileSlice(url: url, offset: start, length: end - start + 1))
    }
}

/// `bytes=a-b`, `bytes=a-` or `bytes=-n` → the first range, clamped to the file; nil when it lies outside.
public func parseByteRange(_ value: String, size: UInt64) -> (UInt64, UInt64)? {
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

/// One request per connection (`Connection: close`) — enough for UPnP control points and renderers.
public final class HTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let listener: NWListener
    private let queue = DispatchQueue(label: "upnp.http")
    private let handler: Handler
    private let serverName: String
    private let lock = NSLock()
    private var reachable = true

    /// Off = connections are dropped, like a powered-off device.
    public var online: Bool {
        get { lock.lock(); defer { lock.unlock() }; return reachable }
        set { lock.lock(); reachable = newValue; lock.unlock() }
    }

    public init(port: UInt16, serverName: String = "macOS UPnP/1.0 AudioHarbor/0.1", handler: @escaping Handler) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw ToolError("bad port \(port)") }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: endpointPort)
        self.serverName = serverName
        self.handler = handler
    }

    public func start() {
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { say("http: listener failed: \(error) — try another --port") }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            guard self.online else {
                connection.cancel()
                return
            }
            connection.start(queue: self.queue)
            self.receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if complete || error != nil { connection.cancel() } else { receive(connection, buffer: buffer) }
                return
            }
            let lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()] =
                    line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let length = Int(headers["CONTENT-LENGTH"] ?? "") ?? 0
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
            let request = HTTPRequest(method: parts[0].uppercased(), path: parts[1], headers: headers,
                                      body: body.prefix(length), peer: "\(connection.endpoint)")
            Task {
                let response = await handler(request)
                send(response, on: connection, request: request)
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection, request: HTTPRequest) {
        let length = response.file?.length ?? UInt64(response.body.count)
        var head = "HTTP/1.1 \(response.status)\r\n"
        for (name, value) in response.headers { head += "\(name): \(value)\r\n" }
        head += "Content-Length: \(length)\r\nServer: \(serverName)\r\nConnection: close\r\n\r\n"
        var data = Data(head.utf8)
        if request.method != "HEAD", response.file == nil { data.append(response.body) }
        connection.send(content: data, completion: .contentProcessed { [self] error in
            guard error == nil, request.method != "HEAD", let slice = response.file, slice.length > 0,
                  let file = try? FileHandle(forReadingFrom: slice.url),
                  (try? file.seek(toOffset: slice.offset)) != nil else {
                connection.cancel()
                return
            }
            pump(connection, file, label: request.path, remaining: slice.length, sent: 0, started: Date())
        })
    }

    /// 256 KB at a time; the next read waits for the previous send, so the client sets the pace.
    private func pump(_ connection: NWConnection, _ file: FileHandle, label: String,
                      remaining: UInt64, sent: UInt64, started: Date) {
        let summary = { (bytes: UInt64) in
            String(format: "%.1f MB in %.1f s", Double(bytes) / 1_048_576, Date().timeIntervalSince(started))
        }
        guard remaining > 0 else {
            try? file.close()
            say("http ✓ \(label) to \(connection.endpoint): \(summary(sent))")
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let chunk = file.readData(ofLength: Int(min(remaining, 256 * 1024)))
        guard !chunk.isEmpty else {
            try? file.close()
            connection.cancel()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [self] error in
            let total = sent + UInt64(chunk.count)
            if error != nil {
                try? file.close()
                say("http ✗ \(label) to \(connection.endpoint): closed after \(summary(total))")
                connection.cancel()
                return
            }
            pump(connection, file, label: label, remaining: remaining - UInt64(chunk.count), sent: total, started: started)
        })
    }
}
