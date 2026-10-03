import Foundation
import Security

/// Application-layer pairing for LAN remote.
enum RemotePairing {
    static let codeTTL: TimeInterval = 3 * 60
    static let maxFailedAttempts = 5
    static let lockoutDuration: TimeInterval = 60

    struct ActiveCode: Sendable {
        var code: String
        var expiresAt: Date
    }

    struct PairedDevice: Codable, Sendable, Identifiable, Equatable {
        var id: UUID
        var name: String
        var platform: String
        var pairedAt: Date
    }

    static func generateCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    static func mintToken() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}

/// Persists paired remote tokens on the Mac engine.
/// UserDefaults is primary so re-pairing survives debug runs; Keychain is mirrored.
enum RemotePairingStore {
    private static let defaults = UserDefaults.standard
    private static let devicesKey = "audioharbor.remote.server.pairedDevices"
    private static let tokenPrefix = "audioharbor.remote.server.token."
    private static let keychainService = "com.gerov.audioharbor.remote.pairing"

    static func loadDevices() -> [RemotePairing.PairedDevice] {
        if let data = defaults.data(forKey: devicesKey),
           let devices = try? JSONDecoder().decode([RemotePairing.PairedDevice].self, from: data) {
            return devices
        }
        if let data = keychainRead(account: "paired-devices"),
           let devices = try? JSONDecoder().decode([RemotePairing.PairedDevice].self, from: data) {
            defaults.set(data, forKey: devicesKey)
            return devices
        }
        return []
    }

    static func saveDevices(_ devices: [RemotePairing.PairedDevice]) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: devicesKey)
        keychainWrite(data, account: "paired-devices")
    }

    static func storeToken(_ token: Data, for clientID: UUID) {
        defaults.set(token, forKey: tokenPrefix + clientID.uuidString)
        keychainWrite(token, account: "token." + clientID.uuidString)
    }

    static func token(for clientID: UUID) -> Data? {
        if let data = defaults.data(forKey: tokenPrefix + clientID.uuidString), !data.isEmpty {
            return data
        }
        if let data = keychainRead(account: "token." + clientID.uuidString), !data.isEmpty {
            defaults.set(data, forKey: tokenPrefix + clientID.uuidString)
            return data
        }
        return nil
    }

    static func revoke(clientID: UUID) {
        defaults.removeObject(forKey: tokenPrefix + clientID.uuidString)
        keychainDelete(account: "token." + clientID.uuidString)
        var devices = loadDevices()
        devices.removeAll { $0.id == clientID }
        saveDevices(devices)
    }

    static func revokeAll() {
        for device in loadDevices() {
            defaults.removeObject(forKey: tokenPrefix + device.id.uuidString)
            keychainDelete(account: "token." + device.id.uuidString)
        }
        saveDevices([])
    }

    static func upsertDevice(_ device: RemotePairing.PairedDevice, token: Data) {
        storeToken(token, for: device.id)
        var devices = loadDevices().filter { $0.id != device.id }
        devices.append(device)
        devices.sort { $0.pairedAt > $1.pairedAt }
        saveDevices(devices)
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
