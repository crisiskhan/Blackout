import Foundation
import CryptoKit

public struct SealedBlob: Equatable, Sendable {
    public var nonce: Data
    public var ciphertext: Data
}

public enum CryptoParty {
    public static func seal(plain: Data, key: SymmetricKey) throws -> AES.GCM.SealedBox {
        try AES.GCM.seal(plain, using: key)
    }

    public static func open(_ box: AES.GCM.SealedBox, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(box, using: key)
    }

    public static func guestDeadline(from now: Date = Date()) -> Date {
        now.addingTimeInterval(4 * 3600)
    }

    public static func guestValid(_ deadline: Date, now: Date = Date()) -> Bool {
        now < deadline
    }
}

/// AES-GCM wrap for a party body. Magic prefix lets an older plaintext
/// envelope still open. Hop carries the sealed bytes without reading them.
public enum PartySeal {
    public static let magic = Data([0x42, 0x4F, 0x31])

    public enum SealError: Error {
        case combined
        case plain
    }

    public static func key(code: String) -> SymmetricKey {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(normalized.utf8)),
            salt: Data("blackout.party.v1".utf8),
            info: Data("mesh-body".utf8),
            outputByteCount: 32
        )
    }

    public static func isSealed(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    public static func wrap(_ plain: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plain, using: key)
        guard let combined = box.combined else { throw SealError.combined }
        return magic + combined
    }

    public static func unwrap(_ data: Data, key: SymmetricKey) throws -> Data {
        guard isSealed(data) else { throw SealError.plain }
        let box = try AES.GCM.SealedBox(combined: Data(data.dropFirst(magic.count)))
        return try AES.GCM.open(box, using: key)
    }

    public static func openBody(_ data: Data, key: SymmetricKey?) -> Data? {
        if isSealed(data) {
            guard let key else { return nil }
            return try? unwrap(data, key: key)
        }
        return data
    }
}
