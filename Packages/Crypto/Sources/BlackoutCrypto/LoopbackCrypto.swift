import BlackoutCore
import CryptoKit
import Foundation
import Security

/// Device-local CryptoKit. Self-seal uses a Keychain ChaCha key.
/// One nearby peer: X25519 advertisement + ECDH box. Mesh never sees keys.
@MainActor
public final class LoopbackCrypto: CryptoServing {
    public let localIdentity: BlackoutID
    private let key: SymmetricKey
    private let agreement: Curve25519.KeyAgreement.PrivateKey
    private var peers: [BlackoutID: Curve25519.KeyAgreement.PublicKey] = [:]
    private var partyCode: String?

    public init() throws {
        let blob = try Self.loadOrCreateBlob()
        self.localIdentity = blob.identity
        self.key = blob.key
        self.agreement = blob.agreement
    }

    /// In-memory keys only. Two instances can prove ECDH without sharing Keychain.
    public init(inMemoryForTesting: Bool) {
        precondition(inMemoryForTesting, "in-memory crypto is test-only")
        self.localIdentity = BlackoutID()
        self.key = SymmetricKey(size: .bits256)
        self.agreement = Curve25519.KeyAgreement.PrivateKey()
    }

    public var localAdvertisement: Data {
        Self.encodeAdvertisement(id: localIdentity, agreementPublic: agreement.publicKey.rawRepresentation)
    }

    public var preferredRecipient: BlackoutID {
        peers.keys.min { $0.rawValue.uuidString < $1.rawValue.uuidString } ?? localIdentity
    }

    public func registerPeerAdvertisement(_ data: Data) {
        guard let parsed = Self.decodeAdvertisement(data) else { return }
        guard parsed.id != localIdentity else { return }
        guard let pub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: parsed.agreementPublic) else {
            return
        }
        peers[parsed.id] = pub
    }

    public func setPartyCode(_ code: String?) {
        partyCode = PartyCode.isValid(code) ? code : nil
    }

    public func seal(_ plaintext: Data, to recipient: BlackoutID) throws -> Data {
        if recipient != localIdentity, let peerPublic = peers[recipient] {
            return try sealToPeer(plaintext, peerPublic: peerPublic)
        }
        return try sealLocal(plaintext)
    }

    public func seal(_ plaintext: Data, partyCode: String) throws -> Data {
        guard PartyCode.isValid(partyCode) else { throw CryptoLoopbackError.malformed }
        let box = try ChaChaPoly.seal(plaintext, using: Self.partyKey(partyCode))
        var packed = Data([3])
        packed.append(box.nonce.withUnsafeBytes { Data($0) })
        packed.append(box.ciphertext)
        packed.append(box.tag)
        return packed
    }

    public func open(_ ciphertext: Data) throws -> Data {
        guard !ciphertext.isEmpty else { throw CryptoLoopbackError.malformed }
        switch ciphertext[0] {
        case 1:
            return try openLocal(ciphertext)
        case 2:
            return try openPeer(ciphertext)
        case 3:
            return try openParty(ciphertext)
        default:
            throw CryptoLoopbackError.malformed
        }
    }

    private func sealLocal(_ plaintext: Data) throws -> Data {
        let box = try ChaChaPoly.seal(plaintext, using: key)
        var packed = Data([1])
        packed.append(box.nonce.withUnsafeBytes { Data($0) })
        packed.append(box.ciphertext)
        packed.append(box.tag)
        return packed
    }

    private func openLocal(_ ciphertext: Data) throws -> Data {
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

    private func sealToPeer(_ plaintext: Data, peerPublic: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        let secret = try agreement.sharedSecretFromKeyAgreement(with: peerPublic)
        let box = try ChaChaPoly.seal(plaintext, using: Self.meshKey(from: secret))
        var packed = Data([2])
        packed.append(agreement.publicKey.rawRepresentation)
        packed.append(box.nonce.withUnsafeBytes { Data($0) })
        packed.append(box.ciphertext)
        packed.append(box.tag)
        return packed
    }

    private func openPeer(_ ciphertext: Data) throws -> Data {
        guard ciphertext.count > 1 + 32 + 12 + 16, ciphertext[0] == 2 else {
            throw CryptoLoopbackError.malformed
        }
        let pub = ciphertext[1..<33]
        let nonceData = ciphertext[33..<45]
        let tag = ciphertext.suffix(16)
        let body = ciphertext[45..<(ciphertext.count - 16)]
        let senderPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pub)
        let secret = try agreement.sharedSecretFromKeyAgreement(with: senderPublic)
        let nonce = try ChaChaPoly.Nonce(data: nonceData)
        let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: body, tag: tag)
        return try ChaChaPoly.open(box, using: Self.meshKey(from: secret))
    }

    private static func meshKey(from secret: SharedSecret) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("blackout-mesh-v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )
    }

    private static func partyKey(_ partyCode: String) -> SymmetricKey {
        var material = Data("blackout-party-v1:".utf8)
        material.append(Data(partyCode.utf8))
        let digest = SHA256.hash(data: material)
        return SymmetricKey(data: Data(digest))
    }

    private func openParty(_ ciphertext: Data) throws -> Data {
        guard ciphertext.count > 1 + 12 + 16, ciphertext[0] == 3 else {
            throw CryptoLoopbackError.malformed
        }
        guard let partyCode else { throw CryptoLoopbackError.malformed }
        let nonceData = ciphertext[1..<13]
        let tag = ciphertext.suffix(16)
        let body = ciphertext[13..<(ciphertext.count - 16)]
        let nonce = try ChaChaPoly.Nonce(data: nonceData)
        let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: body, tag: tag)
        return try ChaChaPoly.open(box, using: Self.partyKey(partyCode))
    }

    static func encodeAdvertisement(id: BlackoutID, agreementPublic: Data) -> Data {
        var data = Data([1])
        var uuid = id.rawValue.uuid
        withUnsafeBytes(of: &uuid) { data.append(contentsOf: $0) }
        data.append(agreementPublic)
        return data
    }

    static func decodeAdvertisement(_ data: Data) -> (id: BlackoutID, agreementPublic: Data)? {
        guard data.count == 1 + 16 + 32, data[0] == 1 else { return nil }
        let uuidBytes = [UInt8](data[1..<17])
        let uuid = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
        return (BlackoutID(uuid), Data(data[17..<49]))
    }

    private static let keychainAccount = "com.crisiskhan.blackout.crypto.blob-v1"
    private static let legacyIdentityKey = "com.crisiskhan.blackout.crypto.identity"
    private static let legacyKeyAccount = "com.crisiskhan.blackout.crypto.chacha-key"

    private struct Blob {
        var identity: BlackoutID
        var key: SymmetricKey
        var agreement: Curve25519.KeyAgreement.PrivateKey
    }

    private static func loadOrCreateBlob() throws -> Blob {
        let statusAndData = copyItem(account: keychainAccount)
        switch statusAndData.0 {
        case errSecSuccess:
            guard let data = statusAndData.1, let loaded = decode(data) else {
                throw CryptoLoopbackError.keychainReadFailed(errSecSuccess)
            }
            if loaded.needsUpgrade {
                let status = addItem(account: keychainAccount, data: encode(loaded.blob))
                guard status == errSecSuccess else {
                    throw CryptoLoopbackError.keychainWriteFailed(status)
                }
            }
            return loaded.blob
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
        let blob = Blob(
            identity: BlackoutID(),
            key: SymmetricKey(size: .bits256),
            agreement: Curve25519.KeyAgreement.PrivateKey()
        )
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
        let blob = Blob(
            identity: identity,
            key: SymmetricKey(data: keyData),
            agreement: Curve25519.KeyAgreement.PrivateKey()
        )
        let status = addItem(account: keychainAccount, data: encode(blob))
        guard status == errSecSuccess else {
            throw CryptoLoopbackError.keychainWriteFailed(status)
        }
        return blob
    }

    private static func encode(_ blob: Blob) -> Data {
        var data = Data([2])
        var uuid = blob.identity.rawValue.uuid
        withUnsafeBytes(of: &uuid) { data.append(contentsOf: $0) }
        blob.key.withUnsafeBytes { data.append(contentsOf: $0) }
        data.append(blob.agreement.rawRepresentation)
        return data
    }

    private static func decode(_ data: Data) -> (blob: Blob, needsUpgrade: Bool)? {
        if data.count == 1 + 16 + 32 + 32, data[0] == 2 {
            let uuidBytes = [UInt8](data[1..<17])
            let uuid = UUID(uuid: (
                uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
                uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
                uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
                uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
            ))
            let keyData = data[17..<49]
            guard let agreement = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data[49..<81]) else {
                return nil
            }
            return (
                Blob(
                    identity: BlackoutID(uuid),
                    key: SymmetricKey(data: keyData),
                    agreement: agreement
                ),
                false
            )
        }
        if data.count == 1 + 16 + 32, data[0] == 1 {
            let uuidBytes = [UInt8](data[1..<17])
            let uuid = UUID(uuid: (
                uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
                uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
                uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
                uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
            ))
            let keyData = data[17..<49]
            return (
                Blob(
                    identity: BlackoutID(uuid),
                    key: SymmetricKey(data: keyData),
                    agreement: Curve25519.KeyAgreement.PrivateKey()
                ),
                true
            )
        }
        return nil
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
    public var localAdvertisement: Data { Data() }
    public var preferredRecipient: BlackoutID { localIdentity }

    public init() {}

    public func registerPeerAdvertisement(_ data: Data) {
        _ = data
    }

    public func setPartyCode(_ code: String?) {
        _ = code
    }

    public func seal(_ plaintext: Data, to recipient: BlackoutID) throws -> Data {
        throw CryptoLoopbackError.keychainUnavailable
    }

    public func seal(_ plaintext: Data, partyCode: String) throws -> Data {
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
