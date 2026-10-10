#if os(macOS)
import Foundation
import OSLog

enum UPnPControlError: Error, LocalizedError, Sendable {
    case missingService(String)
    case http(Int, String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingService(let name): "Renderer has no \(name) service"
        case .http(let code, let detail): "UPnP HTTP \(code): \(detail)"
        case .badResponse(let detail): detail
        }
    }
}

struct UPnPTransportInfo: Sendable {
    var state: String
    var status: String
    var speed: String
}

struct UPnPPositionInfo: Sendable {
    var track: String
    var duration: TimeInterval?
    var relTime: TimeInterval?
    var uri: String
}

/// SOAP control-point calls against a MediaRenderer (AVTransport, RenderingControl, ConnectionManager).
actor UPnPControlPoint {
    private let logger = Logger(subsystem: "com.gerov.audioharbor.player", category: "UPnP")
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        // Play / SetAVTransportURI often block while the renderer buffers HTTP (Bose, Sonos).
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    // MARK: - AVTransport

    func setAVTransportURI(_ renderer: UPnPRenderer, uri: String, metadata: String) async throws {
        _ = try await call(
            renderer,
            service: .avTransport,
            action: "SetAVTransportURI",
            [("InstanceID", "0"), ("CurrentURI", uri), ("CurrentURIMetaData", metadata)],
            timeout: 30
        )
    }

    func setNextAVTransportURI(_ renderer: UPnPRenderer, uri: String, metadata: String) async throws {
        _ = try await call(
            renderer,
            service: .avTransport,
            action: "SetNextAVTransportURI",
            [("InstanceID", "0"), ("NextURI", uri), ("NextURIMetaData", metadata)],
            timeout: 15
        )
    }

    func play(_ renderer: UPnPRenderer, speed: String = "1") async throws {
        _ = try await call(
            renderer,
            service: .avTransport,
            action: "Play",
            [("InstanceID", "0"), ("Speed", speed)],
            timeout: 45
        )
    }

    func pause(_ renderer: UPnPRenderer) async throws {
        _ = try await call(
            renderer,
            service: .avTransport,
            action: "Pause",
            [("InstanceID", "0")]
        )
    }

    func stop(_ renderer: UPnPRenderer) async throws {
        _ = try await call(
            renderer,
            service: .avTransport,
            action: "Stop",
            [("InstanceID", "0")]
        )
    }

    func seek(_ renderer: UPnPRenderer, to seconds: TimeInterval) async throws {
        let target = Self.formatTime(seconds)
        _ = try await call(
            renderer,
            service: .avTransport,
            action: "Seek",
            [("InstanceID", "0"), ("Unit", "REL_TIME"), ("Target", target)]
        )
    }

    func getTransportInfo(_ renderer: UPnPRenderer) async throws -> UPnPTransportInfo {
        let values = try await call(
            renderer,
            service: .avTransport,
            action: "GetTransportInfo",
            [("InstanceID", "0")]
        )
        return UPnPTransportInfo(
            state: values["CurrentTransportState"] ?? "?",
            status: values["CurrentTransportStatus"] ?? "?",
            speed: values["CurrentSpeed"] ?? "1"
        )
    }

    func getPositionInfo(_ renderer: UPnPRenderer) async throws -> UPnPPositionInfo {
        let values = try await call(
            renderer,
            service: .avTransport,
            action: "GetPositionInfo",
            [("InstanceID", "0")]
        )
        return UPnPPositionInfo(
            track: values["Track"] ?? "?",
            duration: Self.parseTime(values["TrackDuration"]),
            relTime: Self.parseTime(values["RelTime"]),
            uri: values["TrackURI"] ?? ""
        )
    }

    // MARK: - RenderingControl

    func getVolume(_ renderer: UPnPRenderer) async throws -> Int {
        let values = try await call(
            renderer,
            service: .renderingControl,
            action: "GetVolume",
            [("InstanceID", "0"), ("Channel", "Master")]
        )
        return Int(values["CurrentVolume"] ?? "") ?? 0
    }

    func setVolume(_ renderer: UPnPRenderer, level: Int) async throws {
        let clamped = min(100, max(0, level))
        _ = try await call(
            renderer,
            service: .renderingControl,
            action: "SetVolume",
            [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", "\(clamped)")]
        )
    }

    // MARK: - ConnectionManager

    func getProtocolInfo(_ renderer: UPnPRenderer) async throws -> (source: String, sink: String) {
        let values = try await call(
            renderer,
            service: .connectionManager,
            action: "GetProtocolInfo",
            []
        )
        return (values["Source"] ?? "", values["Sink"] ?? "")
    }

    // MARK: - SOAP

    private enum Service {
        case avTransport
        case renderingControl
        case connectionManager
    }

    private func call(
        _ renderer: UPnPRenderer,
        service: Service,
        action: String,
        _ arguments: [(String, String)],
        timeout: TimeInterval = 10
    ) async throws -> [String: String] {
        let (url, serviceType) = try endpoint(renderer, service: service)
        var body = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
            + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
            + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>"
            + "<u:\(action) xmlns:u=\"\(serviceType)\">"
        for (name, value) in arguments {
            body += "<\(name)>\(UPnPXML.escape(value))</\(name)>"
        }
        body += "</u:\(action)></s:Body></s:Envelope>"

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let values = UPnPXML.leaves(data)
        guard status == 200 else {
            let detail = values["errorDescription"]
                ?? values["errorCode"].map { "UPnP error \($0)" }
                ?? String(decoding: data.prefix(400), as: UTF8.self)
            // Many renderers (e.g. Bose) omit SetNext — expected, not a fault.
            let expectedOptional = action == "SetNextAVTransportURI"
                && (detail.localizedCaseInsensitiveContains("Invalid Action")
                    || values["errorCode"] == "401")
            if expectedOptional {
                logger.debug("\(action) → HTTP \(status): \(detail, privacy: .public)")
            } else {
                logger.warning("\(action) → HTTP \(status): \(detail, privacy: .public)")
            }
            throw UPnPControlError.http(status, detail)
        }
        return values
    }

    private func endpoint(
        _ renderer: UPnPRenderer,
        service: Service
    ) throws -> (URL, String) {
        switch service {
        case .avTransport:
            return (renderer.avTransportControlURL, renderer.avTransportServiceType)
        case .renderingControl:
            return (renderer.renderingControlURL, renderer.renderingControlServiceType)
        case .connectionManager:
            guard let url = renderer.connectionManagerURL,
                  let type = renderer.connectionManagerServiceType else {
                throw UPnPControlError.missingService("ConnectionManager")
            }
            return (url, type)
        }
    }

    // MARK: - Time

    /// `H:MM:SS` or `HH:MM:SS` for Seek / RelTime.
    nonisolated static func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    /// Parses `H:MM:SS[.F]` / `HH:MM:SS`; nil for empty or `NOT_IMPLEMENTED`.
    nonisolated static func parseTime(_ text: String?) -> TimeInterval? {
        guard let text, !text.isEmpty,
              text.uppercased() != "NOT_IMPLEMENTED" else { return nil }
        let parts = text.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]) else { return nil }
        let secPart = parts[2].split(separator: ".")
        guard let s = Double(secPart[0]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}
#endif
