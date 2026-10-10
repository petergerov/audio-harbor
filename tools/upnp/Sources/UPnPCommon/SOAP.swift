import Foundation

/// A UPnP error a device answers an action with (HTTP 500 + a SOAP fault).
public struct UPnPError: Error, Sendable {
    public let code: Int
    public let text: String

    public init(code: Int, text: String) {
        self.code = code
        self.text = text
    }

    public static let invalidAction = UPnPError(code: 401, text: "Invalid Action")
    public static let invalidArgs = UPnPError(code: 402, text: "Invalid Args")
    public static let actionFailed = UPnPError(code: 501, text: "Action Failed")
    public static let transitionNotAvailable = UPnPError(code: 701, text: "Transition not available")
    public static let noSuchObject = UPnPError(code: 701, text: "No such object")
    public static let seekModeNotSupported = UPnPError(code: 710, text: "Seek mode not supported")
    public static let noSuchContainer = UPnPError(code: 710, text: "No such container")
    public static let illegalSeekTarget = UPnPError(code: 711, text: "Illegal seek target")
    public static let resourceNotFound = UPnPError(code: 716, text: "Resource not found")
    public static let invalidInstanceID = UPnPError(code: 718, text: "Invalid InstanceID")
}

/// The XML a device sends back for actions, and its service descriptions.
public enum SOAPText {
    public static func envelope(_ body: String) -> String {
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
            + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>\(body)</s:Body></s:Envelope>"
    }

    public static func response(_ action: String, serviceType: String, _ values: [(String, String)]) -> String {
        envelope("<u:\(action)Response xmlns:u=\"\(serviceType)\">"
            + values.map { "<\($0.0)>\(xmlEscape($0.1))</\($0.0)>" }.joined() + "</u:\(action)Response>")
    }

    public static func fault(_ error: UPnPError) -> String {
        envelope("<s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail>"
            + "<UPnPError xmlns=\"urn:schemas-upnp-org:control-1-0\"><errorCode>\(error.code)</errorCode>"
            + "<errorDescription>\(xmlEscape(error.text))</errorDescription></UPnPError></detail></s:Fault>")
    }

    /// "Browse" from a SOAPACTION header such as `"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"`.
    public static func action(fromHeader header: String?) -> String {
        let trimmed = header?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) ?? ""
        return trimmed.split(separator: "#").last.map(String.init) ?? ""
    }

    /// (name, [(argument, "in"/"out", related state variable)])
    public typealias Action = (String, [(String, String, String)])

    /// A service description built from the action table, so it cannot disagree with what the
    /// device answers. Evented variables are added even when no action names them.
    public static func scpd(_ actions: [Action], dataType: (String) -> String, evented: Set<String> = []) -> String {
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
}

/// "AVTransport" from "urn:schemas-upnp-org:service:AVTransport:1".
public func serviceShortName(_ serviceType: String) -> String {
    let parts = serviceType.split(separator: ":")
    return parts.count >= 2 ? String(parts[parts.count - 2]) : serviceType
}
