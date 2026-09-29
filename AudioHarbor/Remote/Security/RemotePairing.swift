import Foundation
import Security

/// Application-layer pairing for LAN remote.
/// Slice 1: 6-digit code → 32-byte token in Keychain. TLS-PSK lands before public release.
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

/// Persists paired remote tokens. Mirrors the LicenseService Keychain style.
enum RemotePairingStore {
    private static let service = "com.gerov.audioharbor.remote.pairing"
    private static let devicesAccount = "paired-devices"
    private static let tokenAccountPrefix = "token."

    static func loadDevices() -> [RemotePairing.PairedDevice] {
        guard let data = readData(account: devicesAccount),
              let devices = try? JSONDecoder().decode([RemotePairing.PairedDevice].self, from: data)
        else { return [] }
        return devices
    }

    static func saveDevices(_ devices: [RemotePairing.PairedDevice]) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        writeData(data, account: devicesAccount)
    }

    static func storeToken(_ token: Data, for clientID: UUID) {
        writeData(token, account: tokenAccountPrefix + clientID.uuidString)
    }

    static func token(for clientID: UUID) -> Data? {
        readData(account: tokenAccountPrefix + clientID.uuidString)
    }

    static func revoke(clientID: UUID) {
        delete(account: tokenAccountPrefix + clientID.uuidString)
        var devices = loadDevices()
        devices.removeAll { $0.id == clientID }
        saveDevices(devices)
    }

    static func revokeAll() {
        for device in loadDevices() {
            delete(account: tokenAccountPrefix + device.id.uuidString)
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

    // MARK: - Keychain

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
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
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
