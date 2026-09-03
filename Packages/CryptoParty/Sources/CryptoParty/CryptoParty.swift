import Foundation
import CryptoKit

public struct SealedBlob: Equatable, Sendable {
    public var nonce: Data
    public var ciphertext: Data
}

public enum CryptoParty {
    public static func seal(plain: Data, key: SymmetricKey) throws -> SealedBox {
        try AES.GCM.seal(plain, using: key)
    }

    public static func open(_ box: SealedBox, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(box, using: key)
    }

    public static func guestDeadline(from now: Date = Date()) -> Date {
        now.addingTimeInterval(4 * 3600)
    }

    public static func guestValid(_ deadline: Date, now: Date = Date()) -> Bool {
        now < deadline
    }
}
