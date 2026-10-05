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

/// AES-GCM wrap for device-local secrets. Magic BO2 so a mesh BO1
/// body is never a vault blob.
public enum DeviceSeal {
    public static let magic = Data([0x42, 0x4F, 0x32])

    public enum SealError: Error {
        case combined
        case plain
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

/// Keychain hook. AppRuntime attaches this phone's device key at boot.
/// Package tests leave it nil and persist plaintext into isolated suites.
public enum DeviceKey {
    public static var resolve: (() -> SymmetricKey?)? {
        get { Box.shared.resolve }
        set { Box.shared.resolve = newValue }
    }

    private final class Box: @unchecked Sendable {
        static let shared = Box()
        var resolve: (() -> SymmetricKey?)?
    }
}

/// One door for user-written and location persist. Fail closed: if the
/// hook is set and Keychain cannot mint a key, nothing is written.
public enum SealedPersist {
    public static func put(_ data: Data, forKey key: String, defaults: UserDefaults = .standard) {
        if let resolve = DeviceKey.resolve {
            guard let bits = resolve(), let sealed = try? DeviceSeal.wrap(data, key: bits) else {
                return
            }
            defaults.set(sealed, forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    public static func get(forKey key: String, defaults: UserDefaults = .standard) -> Data? {
        guard let data = defaults.data(forKey: key) else { return nil }
        if DeviceSeal.isSealed(data) {
            guard let bits = DeviceKey.resolve?() else { return nil }
            return DeviceSeal.openBody(data, key: bits)
        }
        if let resolve = DeviceKey.resolve, let bits = resolve(),
           let sealed = try? DeviceSeal.wrap(data, key: bits)
        {
            defaults.set(sealed, forKey: key)
        }
        return data
    }

    public static func putText(_ text: String, forKey key: String, defaults: UserDefaults = .standard) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            remove(forKey: key, defaults: defaults)
            return
        }
        put(Data(trimmed.utf8), forKey: key, defaults: defaults)
    }

    public static func getText(forKey key: String, defaults: UserDefaults = .standard) -> String? {
        if let data = get(forKey: key, defaults: defaults),
           let text = String(data: data, encoding: .utf8)
        {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let saved = defaults.string(forKey: key), !saved.isEmpty {
            putText(saved, forKey: key, defaults: defaults)
            return saved
        }
        return nil
    }

    public static func putPair(
        lat: Double,
        lon: Double,
        forKey key: String,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode([lat, lon]) else { return }
        put(data, forKey: key, defaults: defaults)
    }

    public static func getPair(
        forKey key: String,
        defaults: UserDefaults = .standard
    ) -> (Double, Double)? {
        if let data = get(forKey: key, defaults: defaults),
           let pair = try? JSONDecoder().decode([Double].self, from: data),
           pair.count == 2
        {
            return (pair[0], pair[1])
        }
        if let pair = defaults.array(forKey: key) as? [Double], pair.count == 2 {
            putPair(lat: pair[0], lon: pair[1], forKey: key, defaults: defaults)
            return (pair[0], pair[1])
        }
        return nil
    }

    public static func putDoubles(
        _ values: [Double],
        forKey key: String,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        put(data, forKey: key, defaults: defaults)
    }

    public static func getDoubles(
        forKey key: String,
        defaults: UserDefaults = .standard
    ) -> [Double]? {
        if let data = get(forKey: key, defaults: defaults),
           let values = try? JSONDecoder().decode([Double].self, from: data)
        {
            return values
        }
        if let values = defaults.array(forKey: key) as? [Double] {
            putDoubles(values, forKey: key, defaults: defaults)
            return values
        }
        return nil
    }

    public static func putStrings(
        _ values: [String],
        forKey key: String,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        put(data, forKey: key, defaults: defaults)
    }

    public static func getStrings(
        forKey key: String,
        defaults: UserDefaults = .standard
    ) -> [String]? {
        if let data = get(forKey: key, defaults: defaults),
           let values = try? JSONDecoder().decode([String].self, from: data)
        {
            return values
        }
        if let values = defaults.stringArray(forKey: key) {
            putStrings(values, forKey: key, defaults: defaults)
            return values
        }
        return nil
    }

    public static func remove(forKey key: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
