import Foundation
import UPnPCommon

struct UPnPService {
    var serviceType = ""
    var serviceId = ""
    var controlURL = ""
    var eventSubURL = ""
    var scpdURL = ""
    var actions: [String] = []

    /// "AVTransport" from "urn:schemas-upnp-org:service:AVTransport:1".
    var shortName: String {
        let parts = serviceType.split(separator: ":")
        return parts.count >= 2 ? String(parts[parts.count - 2]) : serviceType
    }
}

struct UPnPDevice {
    var location: URL
    var address: String
    var server: String
    var friendlyName = ""
    var manufacturer = ""
    var modelName = ""
    var modelNumber = ""
    var udn = ""
    var urlBase: URL?
    var services: [UPnPService] = []

    var isRenderer: Bool { service("AVTransport") != nil }

    func service(_ name: String) -> UPnPService? {
        services.first { $0.shortName == name }
    }

    func url(_ path: String) -> URL? {
        URL(string: path, relativeTo: urlBase ?? location)?.absoluteURL
    }

    var summary: String {
        "\(friendlyName) — \(manufacturer) \(modelName) \(modelNumber) @ \(address) [\(server)]"
    }
}

/// Root device fields plus every service, embedded devices included.
final class DescriptionParser: NSObject, XMLParserDelegate {
    private var device: UPnPDevice
    private var stack: [String] = []
    private var text = ""
    private var service: UPnPService?

    private init(_ device: UPnPDevice) { self.device = device }

    static func parse(_ data: Data, into device: UPnPDevice) -> UPnPDevice {
        let delegate = DescriptionParser(device)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        return delegate.device
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        stack.append(elementName)
        text = ""
        if elementName == "service" { service = UPnPService() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
        if var current = service {
            switch elementName {
            case "serviceType": current.serviceType = value
            case "serviceId": current.serviceId = value
            case "controlURL": current.controlURL = value
            case "eventSubURL": current.eventSubURL = value
            case "SCPDURL": current.scpdURL = value
            default: break
            }
            if elementName == "service" {
                device.services.append(current)
                service = nil
            } else {
                service = current
            }
        } else if parent == "device" {
            // The root device comes first; embedded devices do not overwrite it.
            switch elementName {
            case "friendlyName" where device.friendlyName.isEmpty: device.friendlyName = value
            case "manufacturer" where device.manufacturer.isEmpty: device.manufacturer = value
            case "modelName" where device.modelName.isEmpty: device.modelName = value
            case "modelNumber" where device.modelNumber.isEmpty: device.modelNumber = value
            case "UDN" where device.udn.isEmpty: device.udn = value
            default: break
            }
        } else if elementName == "URLBase" {
            device.urlBase = URL(string: value)
        }
        stack.removeLast()
        text = ""
    }
}

enum SOAP {
    /// The POST for one action — built apart from sending, so the ctrl-C handler can send a Stop.
    static func request(_ device: UPnPDevice, _ serviceName: String, _ action: String,
                        _ arguments: [(String, String)]) throws -> URLRequest {
        guard let service = device.service(serviceName), let url = device.url(service.controlURL) else {
            throw ToolError("the renderer has no \(serviceName) service")
        }
        var body = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
            + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
            + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>"
            + "<u:\(action) xmlns:u=\"\(service.serviceType)\">"
        for (name, value) in arguments {
            body += "<\(name)>\(xmlEscape(value))</\(name)>"
        }
        body += "</u:\(action)></s:Body></s:Envelope>"

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.serviceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)
        return request
    }

    static func call(_ device: UPnPDevice, _ serviceName: String, _ action: String,
                     _ arguments: [(String, String)]) async throws -> [String: String] {
        let urlRequest = try request(device, serviceName, action, arguments)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let values = XMLLeaves.parse(data).values
        guard status == 200 else {
            let detail = values["errorCode"].map { "UPnP error \($0) \(values["errorDescription"] ?? "")" }
                ?? String(decoding: data.prefix(400), as: UTF8.self)
            throw ToolError("\(action) → HTTP \(status): \(detail)")
        }
        return values
    }
}
