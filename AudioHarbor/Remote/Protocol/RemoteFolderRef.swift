import Foundation

/// Wire ID for a connected folder location: `rootUUID` or `rootUUID/rel/path`.
enum RemoteFolderRef {
    static func encode(rootID: UUID, components: [String] = []) -> String {
        if components.isEmpty { return rootID.uuidString }
        return rootID.uuidString + "/" + components.joined(separator: "/")
    }

    static func parse(_ raw: String) -> (rootID: UUID, components: [String])? {
        guard raw.count >= 36 else { return nil }
        let uuidPart = String(raw.prefix(36))
        guard let rootID = UUID(uuidString: uuidPart) else { return nil }
        if raw.count == 36 { return (rootID, []) }
        let idx = raw.index(raw.startIndex, offsetBy: 36)
        guard raw[idx] == "/" else { return nil }
        let rest = String(raw[raw.index(after: idx)...])
        let components = rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return (rootID, components)
    }

    static func childID(parent: String, directoryName: String) -> String {
        parent + "/" + directoryName
    }

    static func parentID(of wireID: String) -> String? {
        guard let parsed = parse(wireID) else { return nil }
        if parsed.components.isEmpty { return nil }
        return encode(rootID: parsed.rootID, components: Array(parsed.components.dropLast()))
    }
}
