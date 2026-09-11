import Foundation
import Observation
import Security
import StoreKit

/// 7-day trial from first install, then a one-time StoreKit unlock.
@Observable
@MainActor
final class LicenseService {
    static let productID = "app.audioharbor.player.unlock"
    static let trialDuration: TimeInterval = 7 * 24 * 60 * 60

    enum Status: Equatable {
        case unlocked
        case trial(daysRemaining: Int)
        case expired
    }

    private(set) var status: Status
    private(set) var product: Product?
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var message: String?
    var isUnlockPresented = false

    var canPlay: Bool {
        switch status {
        case .unlocked, .trial: true
        case .expired: false
        }
    }

    var priceText: String {
        product?.displayPrice ?? "€9.90"
    }

    var statusHeadline: String {
        switch status {
        case .unlocked:
            "Unlocked"
        case .trial(let days):
            days == 1 ? "Trial · 1 day left" : "Trial · \(days) days left"
        case .expired:
            "Trial ended"
        }
    }

    var statusDetail: String {
        switch status {
        case .unlocked:
            "One-time unlock is active on this Apple ID. Restore on another Mac from here."
        case .trial:
            "Free to install. Full playback for seven days after you first opened Audio Harbor on this Mac."
        case .expired:
            "Playback needs a one-time unlock. Your catalogue stays. Restore if you already bought it."
        }
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        _ = TrialClock.recordFirstInstallIfNeeded()
        status = Self.status(unlocked: false)
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transaction: result)
            }
        }
        Task { await bootstrap() }
    }

    func requestUnlock() {
        guard !canPlay else { return }
        isUnlockPresented = true
    }

    func purchase() async {
        message = nil
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            if product == nil {
                await loadProduct()
            }
            guard let product else {
                message = "The unlock is not available yet. Try Restore, or open the app from a signed-in App Store."
                return
            }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(transaction: verification)
            case .userCancelled:
                break
            case .pending:
                message = "Purchase is pending approval."
            @unknown default:
                message = "Purchase did not complete."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        message = nil
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if case .unlocked = status {
                isUnlockPresented = false
                message = "Purchase restored."
            } else {
                message = "No unlock found for this Apple ID."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    #if DEBUG
    func debugExpireTrial() {
        TrialClock.setFirstInstall(Date().addingTimeInterval(-(Self.trialDuration + 60)))
        status = Self.status(unlocked: isUnlockedFromCache)
        if !canPlay { isUnlockPresented = true }
    }

    func debugResetTrial() {
        TrialClock.setFirstInstall(Date())
        isUnlockedFromCache = false
        status = Self.status(unlocked: false)
        message = "Trial clock reset on this Mac (debug)."
    }
    #endif

    private var isUnlockedFromCache = false

    private func bootstrap() async {
        await loadProduct()
        await refreshEntitlements()
    }

    private func loadProduct() async {
        do {
            let found = try await Product.products(for: [Self.productID])
            product = found.first
        } catch {
            product = nil
        }
    }

    private func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if let transaction = verified(result), transaction.productID == Self.productID {
                unlocked = transaction.revocationDate == nil
                break
            }
        }
        isUnlockedFromCache = unlocked
        status = Self.status(unlocked: unlocked)
        if canPlay {
            isUnlockPresented = false
        }
    }

    private func handle(transaction result: VerificationResult<Transaction>) async {
        guard let transaction = verified(result) else {
            message = "Could not verify the purchase with Apple."
            return
        }
        await transaction.finish()
        if transaction.productID == Self.productID {
            isUnlockedFromCache = transaction.revocationDate == nil
            status = Self.status(unlocked: isUnlockedFromCache)
            if canPlay {
                isUnlockPresented = false
                message = nil
            }
        }
    }

    private func verified(_ result: VerificationResult<Transaction>) -> Transaction? {
        switch result {
        case .verified(let transaction):
            transaction
        case .unverified:
            nil
        }
    }

    private static func status(unlocked: Bool) -> Status {
        if unlocked { return .unlocked }
        let start = TrialClock.installDate()
        let remaining = start.addingTimeInterval(trialDuration).timeIntervalSinceNow
        if remaining <= 0 { return .expired }
        let days = max(1, Int(ceil(remaining / 86_400)))
        return .trial(daysRemaining: days)
    }
}

/// First-open timestamp in the keychain so deleting the app does not reset the trial on the same Mac.
private enum TrialClock {
    private static let service = "app.audioharbor.player.trial"
    private static let account = "firstInstall"

    static func recordFirstInstallIfNeeded() -> Date {
        if let existing = read() { return existing }
        let now = Date()
        write(now)
        return now
    }

    static func installDate() -> Date {
        recordFirstInstallIfNeeded()
    }

    static func setFirstInstall(_ date: Date) {
        write(date)
    }

    private static func read() -> Date? {
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
        guard status == errSecSuccess, let data = item as? Data,
              let raw = Double(String(decoding: data, as: UTF8.self))
        else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    private static func write(_ date: Date) {
        let data = String(date.timeIntervalSince1970).data(using: .utf8) ?? Data()
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
}
