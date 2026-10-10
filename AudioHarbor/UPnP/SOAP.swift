#if os(macOS)
import Foundation

/// A UPnP error an action answers with (HTTP 500 and a SOAP fault).
struct UPnPError: Error, Sendable {
    let code: Int
    let text: String

    static let invalidAction = UPnPError(code: 401, text: "Invalid Action")
    static let invalidArgs = UPnPError(code: 402, text: "Invalid Args")
    static let actionFailed = UPnPError(code: 501, text: "Action Failed")
    static let noSuchObject = UPnPError(code: 701, text: "No such object")
    static let noSuchContainer = UPnPError(code: 710, text: "No such container")
}

/// The XML of SOAP answers and service descriptions, and the little XML reading UPnP needs.
enum UPnPXML {
    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func envelope(_ body: String) -> String {
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
            + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>\(body)</s:Body></s:Envelope>"
    }

    static func response(_ action: String, serviceType: String, _ values: [(String, String)]) -> String {
        envelope("<u:\(action)Response xmlns:u=\"\(serviceType)\">"
            + values.map { "<\($0.0)>\(escape($0.1))</\($0.0)>" }.joined() + "</u:\(action)Response>")
    }

    static func fault(_ error: UPnPError) -> String {
        envelope("<s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail>"
            + "<UPnPError xmlns=\"urn:schemas-upnp-org:control-1-0\"><errorCode>\(error.code)</errorCode>"
            + "<errorDescription>\(escape(error.text))</errorDescription></UPnPError></detail></s:Fault>")
    }

    /// "Browse" from a SOAPACTION header such as `"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"`.
    static func action(fromHeader header: String?) -> String {
        let trimmed = header?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) ?? ""
        return trimmed.split(separator: "#").last.map(String.init) ?? ""
    }

    /// "ContentDirectory" from "urn:schemas-upnp-org:service:ContentDirectory:1".
    static func shortName(_ serviceType: String) -> String {
        let parts = serviceType.split(separator: ":")
        return parts.count >= 2 ? String(parts[parts.count - 2]) : serviceType
    }

    /// (name, [(argument, "in" or "out", related state variable)])
    typealias Action = (String, [(String, String, String)])

    /// A service description built from the action table, so it cannot disagree with the answers.
    static func scpd(_ actions: [Action], dataType: (String) -> String, evented: Set<String> = []) -> String {
        let actionXML = actions.map { name, arguments in
            "<action><name>\(name)</name><argumentList>" + arguments.map { argument, direction, variable in
                "<argument><name>\(argument)</name><direction>\(direction)</direction>"
                    + "<relatedStateVariable>\(variable)</relatedStateVariable></argument>"
            }.joined() + "</argumentList></action>"
        }.joined()
        let variables = Set(actions.flatMap { $0.1.map { $0.2 } }).union(evented)
        let variableXML = variables.sorted().map { variable in
            "<stateVariable sendEvents=\"\(evented.contains(variable) ? "yes" : "no")\"><name>\(variable)</name>"
                + "<dataType>\(dataType(variable))</dataType></stateVariable>"
        }.joined()
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <scpd xmlns="urn:schemas-upnp-org:service-1-0"><specVersion><major>1</major><minor>0</minor></specVersion>
        <actionList>\(actionXML)</actionList><serviceStateTable>\(variableXML)</serviceStateTable></scpd>
        """
    }

    /// Leaf element values by local name — what SOAP arguments need. The last one with a name wins.
    static func leaves(_ data: Data) -> [String: String] {
        let collector = LeafCollector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = collector
        parser.parse()
        return collector.values
    }
}

private final class LeafCollector: NSObject, XMLParserDelegate {
    private(set) var values: [String: String] = [:]
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { values[elementName] = value }
        text = ""
    }
}
#endif
