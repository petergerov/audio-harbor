import Foundation
import Security

/// Client-side identity and tokens for servers this device has paired with.
enum RemoteClientStore {
    private static let service = "com.gerov.audioharbor.remote.client"
    private static let clientIDAccount = "client-id"
    private static let tokenPrefix = "server-token."
    private static let namePrefix = "server-name."

    static func clientID() -> UUID {
        if let data = readData(account: clientIDAccount),
           let raw = String(data: data, encoding: .utf8),
           let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        writeData(Data(id.uuidString.utf8), account: clientIDAccount)
        return id
    }

    static func token(forServerID id: UUID) -> Data? {
        readData(account: tokenPrefix + id.uuidString)
    }

    static func storeToken(_ token: Data, serverID: UUID, serverName: String) {
        writeData(token, account: tokenPrefix + idString(serverID))
        writeData(Data(serverName.utf8), account: namePrefix + idString(serverID))
    }

    static func forget(serverID: UUID) {
        delete(account: tokenPrefix + idString(serverID))
        delete(account: namePrefix + idString(serverID))
    }

    static func rememberedServerName(_ serverID: UUID) -> String? {
        guard let data = readData(account: namePrefix + idString(serverID)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func idString(_ id: UUID) -> String { id.uuidString }

    private static func readData(account: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func writeData(_ data: Data, account: String) {
        var base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        #if os(macOS)
        base[kSecUseDataProtectionKeychain as String] = true
        #endif
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func delete(account: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        SecItemDelete(query as CFDictionary)
    }
}
