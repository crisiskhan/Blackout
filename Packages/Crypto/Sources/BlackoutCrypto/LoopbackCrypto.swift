import BlackoutCore
import CryptoKit
import Foundation
import Security

/// Device-local CryptoKit loopback. Seal to self → persist → open.
@MainActor
public final class LoopbackCrypto: CryptoServing {
    public let localIdentity: BlackoutID
    private let key: SymmetricKey

    public init() {
        let identity = LoopbackCrypto.loadOrCreateIdentity()
        self.localIdentity = identity
        self.key = LoopbackCrypto.loadOrCreateKey()
    }

    public func seal(_ plaintext: Data, to recipient: BlackoutID) throws -> Data {
        _ = recipient
        let box = try ChaChaPoly.seal(plaintext, using: key)
        var packed = Data([1])
        packed.append(box.nonce.withUnsafeBytes { Data($0) })
        packed.append(box.ciphertext)
        packed.append(box.tag)
        return packed
    }

    public func open(_ ciphertext: Data) throws -> Data {
        guard ciphertext.count > 1 + 12 + 16, ciphertext[0] == 1 else {
            throw CryptoLoopbackError.malformed
        }
        let nonceData = ciphertext[1..<13]
        let tag = ciphertext.suffix(16)
        let body = ciphertext[13..<(ciphertext.count - 16)]
        let nonce = try ChaChaPoly.Nonce(data: nonceData)
        let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: body, tag: tag)
        return try ChaChaPoly.open(box, using: key)
    }

    private static let identityKey = "com.crisiskhan.blackout.crypto.identity"
    private static let keychainAccount = "com.crisiskhan.blackout.crypto.chacha-key"

    private static func loadOrCreateIdentity() -> BlackoutID {
        if let raw = UserDefaults.standard.string(forKey: identityKey),
           let uuid = UUID(uuidString: raw) {
            return BlackoutID(uuid)
        }
        let id = BlackoutID()
        UserDefaults.standard.set(id.rawValue.uuidString, forKey: identityKey)
        return id
    }

    private static func loadOrCreateKey() -> SymmetricKey {
        if let existing = readKeychain(), existing.count == 32 {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        storeKeychain(data)
        return key
    }

    private static func readKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func storeKeychain(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

public enum CryptoLoopbackError: Error {
    case malformed
}
