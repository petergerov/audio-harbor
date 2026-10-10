import Foundation
import Network
import UPnPCommon

/// Serves registered files to the renderer and receives GENA event NOTIFYs.
/// Every request is logged with all headers — how the renderer reads (ranges, re-requests,
/// read-ahead) is half of what the spike is for.
final class MediaServer: @unchecked Sendable {
    static let dlnaFeatures = "DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000"

    private(set) var port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "spike.http")
    private let lock = NSLock()
    private var routes: [String: (url: URL, mime: String)] = [:]
    private var hitCounts: [String: Int] = [:]
    private var eventLog: [(date: Date, path: String, change: String)] = []
    private var counter = 0
    private var override: String?

    /// A MIME type to send instead of the one from the extension (nil = by extension).
    var mimeOverride: String? {
        get { lock.lock(); defer { lock.unlock() }; return override }
        set { lock.lock(); override = newValue; lock.unlock() }
    }

    init(preferredPort: UInt16) {
        port = preferredPort
    }

    /// Opens the preferred port, or any free one when it is taken (a second copy running).
    func start() throws {
        let candidates = [NWEndpoint.Port(rawValue: port), NWEndpoint.Port.any].compactMap { $0 }
        for candidate in candidates {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            guard let listener = try? NWListener(using: parameters, on: candidate) else { continue }
            let settled = DispatchSemaphore(value: 0)
            let failure = Box<NWError?>(nil)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    settled.signal()
                case .failed(let error):
                    failure.value = error
                    settled.signal()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
            if settled.wait(timeout: .now() + 3) == .success, failure.value == nil, let bound = listener.port {
                self.listener = listener
                port = bound.rawValue
                say("http: listening on port \(port)")
                return
            }
            say("http: port \(candidate) unavailable (\(failure.value.map { "\($0)" } ?? "timeout"))")
            listener.cancel()
        }
        throw ToolError("could not open an HTTP port for the renderer")
    }

    func register(_ file: URL) -> (path: String, mime: String) {
        lock.lock()
        defer { lock.unlock() }
        counter += 1
        let ext = file.pathExtension.lowercased()
        let path = "/f/\(counter).\(ext.isEmpty ? "bin" : ext)"
        let mime = override ?? Self.mime(for: ext)
        routes[path] = (file, mime)
        return (path, mime)
    }

    /// How often the renderer asked for a path (GET or HEAD) — zero means it never reached us.
    func hits(_ path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return hitCounts[path] ?? 0
    }

    func events(since date: Date) -> [(path: String, change: String)] {
        lock.lock()
        defer { lock.unlock() }
        return eventLog.filter { $0.date >= date }.map { ($0.path, $0.change) }
    }

    static func mime(for ext: String) -> String {
        switch ext {
        case "flac": "audio/flac"
        case "wav": "audio/wav"
        case "aif", "aiff": "audio/aiff"
        case "m4a", "alac": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "dsf": "audio/x-dsf"
        case "dff": "audio/x-dff"
        case "ogg": "audio/ogg"
        default: "application/octet-stream"
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHead(connection, buffer: Data())
    }

    private func receiveHead(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                handle(connection, head: head, body: Data(buffer[end.upperBound...]))
            } else if complete || error != nil {
                connection.cancel()
            } else {
                receiveHead(connection, buffer: buffer)
            }
        }
    }

    private func handle(_ connection: NWConnection, head: String, body: Data) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ").map(String.init)
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }
        let method = parts[0].uppercased()
        let path = parts[1]
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        say("http ← \(connection.endpoint) \(lines[0])\n" + lines.dropFirst().map { "            \($0)" }.joined(separator: "\n"))

        switch method {
        case "NOTIFY":
            let length = Int(headers["CONTENT-LENGTH"] ?? "") ?? 0
            readBody(connection, have: body, length: length) { [self] data in
                let values = XMLLeaves.parse(data).values
                let change = values["LastChange"] ?? String(decoding: data, as: UTF8.self)
                lock.lock()
                eventLog.append((Date(), path, change))
                lock.unlock()
                say("gena ← \(path) SEQ=\(headers["SEQ"] ?? "?")\n            \(change)")
                reply(connection, "200 OK")
            }
        case "GET", "HEAD":
            serve(connection, method: method, path: path, headers: headers)
        default:
            reply(connection, "405 Method Not Allowed")
        }
    }

    private func readBody(_ connection: NWConnection, have: Data, length: Int, done: @escaping (Data) -> Void) {
        guard have.count < length else {
            done(have)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
            var have = have
            if let data { have.append(data) }
            if complete || error != nil { done(have) } else { readBody(connection, have: have, length: length, done: done) }
        }
    }

    private func reply(_ connection: NWConnection, _ status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Files

    private func serve(_ connection: NWConnection, method: String, path: String, headers: [String: String]) {
        lock.lock()
        let route = routes[path]
        if route != nil { hitCounts[path, default: 0] += 1 }
        lock.unlock()
        guard let route else {
            say("http → 404 \(path)")
            reply(connection, "404 Not Found")
            return
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: route.url.path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0

        var start: UInt64 = 0
        var end: UInt64 = size > 0 ? size - 1 : 0
        var partial = false
        if let rangeHeader = headers["RANGE"] {
            guard let range = parseByteRange(rangeHeader, size: size) else {
                say("http → 416 \(path) \(rangeHeader)")
                let response = "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(size)\r\n"
                    + "Content-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            (start, end) = range
            partial = true
        }
        let length = size == 0 ? 0 : end - start + 1

        var head = partial ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: \(route.mime)\r\nContent-Length: \(length)\r\nAccept-Ranges: bytes\r\n"
        if partial { head += "Content-Range: bytes \(start)-\(end)/\(size)\r\n" }
        head += "transferMode.dlna.org: Streaming\r\ncontentFeatures.dlna.org: \(Self.dlnaFeatures)\r\n"
        head += "Server: macOS UPnP/1.0 AudioHarborSpike/0.1\r\nConnection: close\r\n\r\n"
        say("http → \(partial ? 206 : 200) \(method) \(path) bytes \(start)-\(end)/\(size) \(route.mime)")

        connection.send(content: Data(head.utf8), completion: .contentProcessed { [self] error in
            guard error == nil, method == "GET", length > 0,
                  let file = try? FileHandle(forReadingFrom: route.url),
                  (try? file.seek(toOffset: start)) != nil else {
                connection.cancel()
                return
            }
            pump(connection, file, path: path, remaining: length, sent: 0, started: Date())
        })
    }

    /// Sends in 256 KB chunks; the next read waits for the previous send, so the renderer's
    /// read rate is what we see. Logs how far it got when the renderer hangs up.
    private func pump(_ connection: NWConnection, _ file: FileHandle, path: String,
                      remaining: UInt64, sent: UInt64, started: Date) {
        let elapsed = { String(format: "%.1f s", Date().timeIntervalSince(started)) }
        let megabytes = { (bytes: UInt64) in String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if remaining == 0 {
            try? file.close()
            say("http ✓ \(path) to \(connection.endpoint): \(megabytes(sent)) in \(elapsed())")
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
            if let error {
                try? file.close()
                say("http ✗ \(path) to \(connection.endpoint): closed after \(megabytes(total)) in \(elapsed()) (\(error))")
                connection.cancel()
                return
            }
            pump(connection, file, path: path, remaining: remaining - UInt64(chunk.count), sent: total, started: started)
        })
    }
}

/// A value a callback on another queue can set, read after a semaphore says it has.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
