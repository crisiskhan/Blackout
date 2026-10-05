import Foundation
import CryptoKit
import CryptoParty
import Security

/// Device-local AES-GCM for secrets the HUD typewriter persists.
/// The key lives in this phone's Keychain, never iCloud, never the box.
enum DeviceVault {
    static let service = "blackout.device.seal"
    static let account = "v1"
    static let partyPlainKey = "party.code"
    static let partySealedKey = "party.code.sealed"

    static func savePartyCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.removeObject(forKey: partyPlainKey)
        guard !trimmed.isEmpty else {
            UserDefaults.standard.removeObject(forKey: partySealedKey)
            return
        }
        guard let sealed = seal(Data(trimmed.utf8)) else { return }
        UserDefaults.standard.set(sealed, forKey: partySealedKey)
    }

    static func loadPartyCode() -> String? {
        if let data = UserDefaults.standard.data(forKey: partySealedKey),
           let plain = open(data),
           let text = String(data: plain, encoding: .utf8)
        {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let saved = UserDefaults.standard.string(forKey: partyPlainKey), !saved.isEmpty {
            savePartyCode(saved)
            return saved
        }
        return nil
    }

    static func seal(_ plain: Data) -> Data? {
        guard let key = key() else { return nil }
        return try? DeviceSeal.wrap(plain, key: key)
    }

    static func open(_ data: Data) -> Data? {
        if DeviceSeal.isSealed(data) {
            guard let key = key() else { return nil }
            return DeviceSeal.openBody(data, key: key)
        }
        return data
    }

    static func isSealed(_ data: Data) -> Bool {
        DeviceSeal.isSealed(data)
    }

    static func attach() {
        DeviceKey.resolve = { key() }
    }

    private static func key() -> SymmetricKey? {
        if let existing = readKey() { return existing }
        let fresh = SymmetricKey(size: .bits256)
        guard writeKey(fresh) else { return nil }
        return fresh
    }

    private static func readKey() -> SymmetricKey? {
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
            return nil
        }
        return SymmetricKey(data: data)
    }

    private static func writeKey(_ key: SymmetricKey) -> Bool {
        let blob = key.withUnsafeBytes { Data($0) }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        add[kSecValueData as String] = blob
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
