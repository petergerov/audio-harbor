#if os(macOS)
import Foundation

/// Fields pulled from a device description XML for a MediaRenderer.
struct ParsedDeviceDescription: Sendable {
    var friendlyName = ""
    var manufacturer = ""
    var modelName = ""
    var udn = ""
    var urlBase: URL?
    var services: [ParsedService] = []

    struct ParsedService: Sendable {
        var serviceType = ""
        var controlURL = ""
        var eventSubURL = ""
        var scpdURL = ""

        var shortName: String { UPnPXML.shortName(serviceType) }
    }

    func service(_ name: String) -> ParsedService? {
        services.first { $0.shortName == name }
    }

    func url(_ path: String, relativeTo location: URL) -> URL? {
        URL(string: path, relativeTo: urlBase ?? location)?.absoluteURL
    }
}

/// Root device fields plus every service (embedded devices included; root wins on identity).
final class DeviceDescriptionParser: NSObject, XMLParserDelegate {
    private var device = ParsedDeviceDescription()
    private var stack: [String] = []
    private var text = ""
    private var service: ParsedDeviceDescription.ParsedService?

    static func parse(_ data: Data) -> ParsedDeviceDescription {
        let delegate = DeviceDescriptionParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        return delegate.device
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        stack.append(elementName)
        text = ""
        if elementName == "service" {
            service = ParsedDeviceDescription.ParsedService()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
        if var current = service {
            switch elementName {
            case "serviceType": current.serviceType = value
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
            switch elementName {
            case "friendlyName" where device.friendlyName.isEmpty: device.friendlyName = value
            case "manufacturer" where device.manufacturer.isEmpty: device.manufacturer = value
            case "modelName" where device.modelName.isEmpty: device.modelName = value
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
#endif
