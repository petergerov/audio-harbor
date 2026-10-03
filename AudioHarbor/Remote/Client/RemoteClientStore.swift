import Foundation
import Security

/// Client-side identity and tokens for servers this device has paired with.
/// UserDefaults is the source of truth (survives debug runs reliably); Keychain is mirrored.
enum RemoteClientStore {
    private static let defaultsSuite = UserDefaults.standard
    private static let clientIDKey = "audioharbor.remote.client.id"
    private static let tokenPrefix = "audioharbor.remote.client.token."
    private static let namePrefix = "audioharbor.remote.client.name."
    private static let keychainService = "com.gerov.audioharbor.remote.client"

    static func clientID() -> UUID {
        if let raw = defaultsSuite.string(forKey: clientIDKey),
           let id = UUID(uuidString: raw) {
            return id
        }
        if let data = keychainRead(account: "client-id"),
           let raw = String(data: data, encoding: .utf8),
           let id = UUID(uuidString: raw) {
            defaultsSuite.set(id.uuidString, forKey: clientIDKey)
            return id
        }
        let id = UUID()
        defaultsSuite.set(id.uuidString, forKey: clientIDKey)
        keychainWrite(Data(id.uuidString.utf8), account: "client-id")
        return id
    }

    static func token(forServerID id: UUID) -> Data? {
        if let data = defaultsSuite.data(forKey: tokenPrefix + id.uuidString), !data.isEmpty {
            return data
        }
        if let data = keychainRead(account: "server-token." + id.uuidString), !data.isEmpty {
            defaultsSuite.set(data, forKey: tokenPrefix + id.uuidString)
            return data
        }
        return nil
    }

    static func storeToken(_ token: Data, serverID: UUID, serverName: String) {
        defaultsSuite.set(token, forKey: tokenPrefix + serverID.uuidString)
        defaultsSuite.set(serverName, forKey: namePrefix + serverID.uuidString)
        keychainWrite(token, account: "server-token." + serverID.uuidString)
        keychainWrite(Data(serverName.utf8), account: "server-name." + serverID.uuidString)
    }

    static func forget(serverID: UUID) {
        defaultsSuite.removeObject(forKey: tokenPrefix + serverID.uuidString)
        defaultsSuite.removeObject(forKey: namePrefix + serverID.uuidString)
        keychainDelete(account: "server-token." + serverID.uuidString)
        keychainDelete(account: "server-name." + serverID.uuidString)
    }

    static func hasToken(forServerID id: UUID) -> Bool {
        token(forServerID: id) != nil
    }

    static func rememberedServerName(_ serverID: UUID) -> String? {
        defaultsSuite.string(forKey: namePrefix + serverID.uuidString)
            ?? keychainRead(account: "server-name." + serverID.uuidString).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func isPaired(with server: RemoteServerEndpoint) -> Bool {
        if let id = server.serverID, hasToken(forServerID: id) { return true }
        // TXT sometimes omits id — match by remembered name.
        return defaultsSuite.dictionaryRepresentation().keys.contains { key in
            guard key.hasPrefix(namePrefix) else { return false }
            return defaultsSuite.string(forKey: key) == server.name
        }
    }

    /// Resolve a stored token when Bonjour did not include the server id in TXT.
    static func tokenMatching(serverName: String) -> (serverID: UUID, token: Data)? {
        let prefix = namePrefix
        for (key, value) in defaultsSuite.dictionaryRepresentation() {
            guard key.hasPrefix(prefix), let name = value as? String, name == serverName else { continue }
            let idString = String(key.dropFirst(prefix.count))
            guard let serverID = UUID(uuidString: idString),
                  let token = token(forServerID: serverID)
            else { continue }
            return (serverID, token)
        }
        return nil
    }

    // MARK: - Keychain mirror

    private static func keychainRead(account: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
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

    private static func keychainWrite(_ data: Data, account: String) {
        var base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
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

    private static func keychainDelete(account: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        SecItemDelete(query as CFDictionary)
    }
}
