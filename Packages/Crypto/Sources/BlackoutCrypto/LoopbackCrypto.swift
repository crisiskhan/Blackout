import BlackoutCore
import CryptoKit
import Foundation
import Security

/// Device-local CryptoKit loopback. Seal to self → persist → open.
/// Identity and key live in one Keychain item so a failed write cannot mint
/// a new identity that cannot open old ciphertext.
@MainActor
public final class LoopbackCrypto: CryptoServing {
    public let localIdentity: BlackoutID
    private let key: SymmetricKey

    public init() throws {
        let blob = try Self.loadOrCreateBlob()
        self.localIdentity = blob.identity
        self.key = blob.key
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

    private static let keychainAccount = "com.crisiskhan.blackout.crypto.blob-v1"
    private static let legacyIdentityKey = "com.crisiskhan.blackout.crypto.identity"
    private static let legacyKeyAccount = "com.crisiskhan.blackout.crypto.chacha-key"

    private struct Blob {
        var identity: BlackoutID
        var key: SymmetricKey
    }

    private static func loadOrCreateBlob() throws -> Blob {
        let statusAndData = copyItem(account: keychainAccount)
        switch statusAndData.0 {
        case errSecSuccess:
            guard let data = statusAndData.1, let blob = decode(data) else {
                throw CryptoLoopbackError.keychainReadFailed(errSecSuccess)
            }
            return blob
        case errSecItemNotFound:
            if let migrated = try migrateLegacyIfPresent() {
                return migrated
            }
            return try createAndStore()
        default:
            throw CryptoLoopbackError.keychainReadFailed(statusAndData.0)
        }
    }

    private static func createAndStore() throws -> Blob {
        let identity = BlackoutID()
        let key = SymmetricKey(size: .bits256)
        let blob = Blob(identity: identity, key: key)
        let status = addItem(account: keychainAccount, data: encode(blob))
        guard status == errSecSuccess else {
            throw CryptoLoopbackError.keychainWriteFailed(status)
        }
        UserDefaults.standard.removeObject(forKey: legacyIdentityKey)
        return blob
    }

    private static func migrateLegacyIfPresent() throws -> Blob? {
        let legacy = copyItem(account: legacyKeyAccount)
        guard legacy.0 == errSecSuccess, let keyData = legacy.1, keyData.count == 32 else {
            return nil
        }
        let identity: BlackoutID
        if let raw = UserDefaults.standard.string(forKey: legacyIdentityKey),
           let uuid = UUID(uuidString: raw) {
            identity = BlackoutID(uuid)
        } else {
            identity = BlackoutID()
        }
        let blob = Blob(identity: identity, key: SymmetricKey(data: keyData))
        let status = addItem(account: keychainAccount, data: encode(blob))
        guard status == errSecSuccess else {
            throw CryptoLoopbackError.keychainWriteFailed(status)
        }
        return blob
    }

    private static func encode(_ blob: Blob) -> Data {
        var data = Data([1])
        var uuid = blob.identity.rawValue.uuid
        withUnsafeBytes(of: &uuid) { data.append(contentsOf: $0) }
        blob.key.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    private static func decode(_ data: Data) -> Blob? {
        guard data.count == 1 + 16 + 32, data[0] == 1 else { return nil }
        let uuidBytes = [UInt8](data[1..<17])
        let uuid = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
        let keyData = data[17..<49]
        return Blob(identity: BlackoutID(uuid), key: SymmetricKey(data: keyData))
    }

    private static func copyItem(account: String) -> (OSStatus, Data?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    private static func addItem(account: String, data: Data) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let find: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account
            ]
            return SecItemUpdate(find as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        return status
    }
}

@MainActor
public final class UnavailableCrypto: CryptoServing {
    public let localIdentity = BlackoutID(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)

    public init() {}

    public func seal(_ plaintext: Data, to recipient: BlackoutID) throws -> Data {
        throw CryptoLoopbackError.keychainUnavailable
    }

    public func open(_ ciphertext: Data) throws -> Data {
        throw CryptoLoopbackError.keychainUnavailable
    }
}

public enum CryptoLoopbackError: Error, LocalizedError {
    case malformed
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case keychainUnavailable

    public var errorDescription: String? {
        switch self {
        case .malformed:
            return "Ciphertext is malformed."
        case .keychainReadFailed(let status):
            return "Keychain read failed (\(status)). Existing identity was not replaced."
        case .keychainWriteFailed(let status):
            return "Keychain write failed (\(status)). No new identity was stored."
        case .keychainUnavailable:
            return "Crypto is unavailable. Messages will not mint a new identity that cannot open old ciphertext."
        }
    }
}
