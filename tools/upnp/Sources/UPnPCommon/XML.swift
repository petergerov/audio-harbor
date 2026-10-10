import Foundation

/// Leaf element values by local name (last one wins), plus SCPD action names.
public final class XMLLeaves: NSObject, XMLParserDelegate {
    public private(set) var values: [String: String] = [:]
    public private(set) var actionNames: [String] = []
    private var stack: [String] = []
    private var text = ""

    public static func parse(_ data: Data) -> XMLLeaves {
        let delegate = XMLLeaves()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        return delegate
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                       qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        stack.append(elementName)
        text = ""
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                       qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { values[elementName] = value }
        if elementName == "name", stack.count >= 2, stack[stack.count - 2] == "action" {
            actionNames.append(value)
        }
        stack.removeLast()
        text = ""
    }
}

public func xmlEscape(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

/// Attribute value from a DIDL-Lite `<res …>` (e.g. `duration`), without a full DIDL parser.
public func resAttribute(_ name: String, in didl: String) -> String? {
    guard let res = didl.range(of: "<res"), let close = didl[res.upperBound...].range(of: ">") else { return nil }
    let tag = didl[res.upperBound..<close.lowerBound]
    guard let start = tag.range(of: "\(name)=\"") else { return nil }
    let rest = tag[start.upperBound...]
    guard let end = rest.firstIndex(of: "\"") else { return nil }
    return String(rest[..<end])
}
