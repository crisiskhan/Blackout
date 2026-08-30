import Foundation
import Observation

/// One local profile. deviceID + callsign + optional party code.
/// Persisted as `blackout-field-v1`. Not an account.
public struct LocalIdentity: Hashable, Codable, Sendable {
    public var deviceID: BlackoutID
    public var callsign: String
    public var partyCode: String?

    public init(
        deviceID: BlackoutID,
        callsign: String = Callsign.defaultValue,
        partyCode: String? = nil
    ) {
        self.deviceID = deviceID
        self.callsign = Callsign.commit(callsign)
        self.partyCode = PartyCode.isValid(partyCode) ? partyCode : nil
    }

    public var isSolo: Bool { partyCode == nil }
}

public enum Callsign {
    public static let defaultValue = "YOU"
    public static let maxLength = 12

    public static func commit(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return defaultValue }
        return String(trimmed.prefix(maxLength))
    }

    public static func last4(_ id: BlackoutID) -> String {
        let hex = id.rawValue.uuidString.replacingOccurrences(of: "-", with: "")
        return String(hex.suffix(4)).uppercased()
    }

    /// Multipeer display name. Default YOU always carries last-4 so two YOUs can radio.
    public static func radioName(_ callsign: String, id: BlackoutID) -> String {
        let name = commit(callsign)
        if name == defaultValue {
            return "\(name) · \(last4(id))"
        }
        return name
    }

    public static func collides(
        _ callsign: String,
        id: BlackoutID,
        among: [(BlackoutID, String)]
    ) -> Bool {
        let name = commit(callsign)
        guard name == defaultValue else { return false }
        return among.contains { $0.0 != id && commit($0.1) == defaultValue }
    }
}

/// Roster / Radar / Comms label. Footnote is silver.dim, not a badge, not on SOS.
public struct CallsignLabel: Equatable, Sendable {
    public var name: String
    public var footnote: String?

    public init(name: String, footnote: String? = nil) {
        self.name = name
        self.footnote = footnote
    }

    public static func resolve(
        callsign: String,
        id: BlackoutID,
        among: [(BlackoutID, String)]
    ) -> CallsignLabel {
        let name = Callsign.commit(callsign)
        if Callsign.collides(name, id: id, among: among) {
            return CallsignLabel(name: name, footnote: "\(name) · \(Callsign.last4(id))")
        }
        return CallsignLabel(name: name, footnote: nil)
    }
}

public enum PartyCode {
    public static let minLength = 4
    public static let maxLength = 8
    public static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    public static func normalize(_ raw: String) -> String {
        String(raw.uppercased().filter { alphabet.contains($0) })
    }

    public static func isValid(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return (minLength...maxLength).contains(raw.count)
            && raw.unicodeScalars.allSatisfy { PartyCodeScalars.allowed.contains($0) }
    }

    public static func generate(length: Int = 6) -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(length: length, using: &rng)
    }

    public static func generate(length: Int = 6, using rng: inout some RandomNumberGenerator) -> String {
        let n = min(max(length, minLength), maxLength)
        return String((0..<n).map { _ in alphabet.randomElement(using: &rng)! })
    }
}

private enum PartyCodeScalars {
    static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
}

public enum MeshGate {
    /// Party code is required before any mesh traffic. Solo without a code is valid.
    public static func allowsTraffic(partyCode: String?) -> Bool {
        PartyCode.isValid(partyCode)
    }
}

public enum PartyIdentityCopy {
    public static let callsign = "Callsign"
    public static let partyCode = "Party code"
    public static let create = "Create"
    public static let join = "Join"
    public static let leave = "Leave"
    public static let end = "End"
    public static let save = "Save"
    public static let soloValid = "Solo. Mesh is off until you Create or Join."
    public static let noParty = "No party"
    public static let outingNameHint = "Outing name. Not your callsign."
}

/// Single profile store. Crypto keeps Keychain keys; this is the field name + party.
@MainActor
@Observable
public final class LocalIdentityStore {
    public private(set) var identity: LocalIdentity
    private let defaults: UserDefaults
    private let fileRoot: URL?

    public init(
        deviceID: BlackoutID,
        defaults: UserDefaults = .standard,
        fileRoot: URL? = nil
    ) {
        self.defaults = defaults
        self.fileRoot = fileRoot
        if let stored = Self.loadV1(defaults: defaults, fileRoot: fileRoot) {
            identity = LocalIdentity(
                deviceID: stored.deviceID,
                callsign: stored.callsign,
                partyCode: stored.partyCode
            )
            return
        }
        if let legacy = Self.loadV3(defaults: defaults, fileRoot: fileRoot) {
            identity = LocalIdentity(
                deviceID: legacy.deviceID ?? deviceID,
                callsign: legacy.callsign ?? Callsign.defaultValue,
                partyCode: legacy.partyCode
            )
            Self.writeV1(identity, defaults: defaults, fileRoot: fileRoot)
            return
        }
        identity = LocalIdentity(deviceID: deviceID)
        Self.writeV1(identity, defaults: defaults, fileRoot: fileRoot)
    }

    public var deviceID: BlackoutID { identity.deviceID }
    public var callsign: String { identity.callsign }
    public var partyCode: String? { identity.partyCode }
    public var isSolo: Bool { identity.isSolo }

    @discardableResult
    public func commitCallsign(_ raw: String) -> String {
        identity.callsign = Callsign.commit(raw)
        persist()
        return identity.callsign
    }

    @discardableResult
    public func createParty() -> Bool {
        identity.partyCode = PartyCode.generate()
        persist()
        return identity.partyCode != nil
    }

    @discardableResult
    public func joinParty(_ raw: String) -> Bool {
        let code = PartyCode.normalize(raw)
        guard PartyCode.isValid(code) else { return false }
        identity.partyCode = code
        persist()
        return true
    }

    public func leaveParty() {
        identity.partyCode = nil
        persist()
    }

    private func persist() {
        Self.writeV1(identity, defaults: defaults, fileRoot: fileRoot)
    }

    private struct WireV1: Codable {
        var v: Int
        var format: String
        var deviceID: BlackoutID
        var callsign: String
        var partyCode: String?
    }

    private struct LegacyV3: Codable {
        var deviceID: String?
        var callsign: String?
        var partyCode: String?
        var identity: Nested?

        struct Nested: Codable {
            var deviceID: String?
            var callsign: String?
            var partyCode: String?
        }

        var resolvedDeviceID: BlackoutID? {
            let raw = deviceID ?? identity?.deviceID
            guard let raw, let uuid = UUID(uuidString: raw) else { return nil }
            return BlackoutID(uuid)
        }

        var resolvedCallsign: String? { callsign ?? identity?.callsign }
        var resolvedPartyCode: String? { partyCode ?? identity?.partyCode }
    }

    private static func loadV1(defaults: UserDefaults, fileRoot: URL?) -> LocalIdentity? {
        if let data = defaults.data(forKey: BlackoutKeys.fieldIdentityV1),
           let wire = try? JSONDecoder().decode(WireV1.self, from: data),
           wire.v == 1 {
            return LocalIdentity(
                deviceID: wire.deviceID,
                callsign: wire.callsign,
                partyCode: wire.partyCode
            )
        }
        if let data = readFile(named: BlackoutKeys.fieldIdentityV1, root: fileRoot),
           let wire = try? JSONDecoder().decode(WireV1.self, from: data),
           wire.v == 1 {
            return LocalIdentity(
                deviceID: wire.deviceID,
                callsign: wire.callsign,
                partyCode: wire.partyCode
            )
        }
        return nil
    }

    private static func loadV3(defaults: UserDefaults, fileRoot: URL?) -> (
        deviceID: BlackoutID?,
        callsign: String?,
        partyCode: String?
    )? {
        let blobs: [Data] = [
            defaults.data(forKey: BlackoutKeys.fieldIdentityLegacyV3),
            readFile(named: BlackoutKeys.fieldIdentityLegacyV3, root: fileRoot)
        ].compactMap { $0 }
        for data in blobs {
            if let legacy = try? JSONDecoder().decode(LegacyV3.self, from: data) {
                return (legacy.resolvedDeviceID, legacy.resolvedCallsign, legacy.resolvedPartyCode)
            }
        }
        return nil
    }

    private static func writeV1(_ identity: LocalIdentity, defaults: UserDefaults, fileRoot: URL?) {
        let wire = WireV1(
            v: 1,
            format: BlackoutKeys.fieldIdentityV1,
            deviceID: identity.deviceID,
            callsign: identity.callsign,
            partyCode: identity.partyCode
        )
        guard let data = try? JSONEncoder().encode(wire) else { return }
        defaults.set(data, forKey: BlackoutKeys.fieldIdentityV1)
        if let fileRoot {
            let url = fileRoot.appendingPathComponent(BlackoutKeys.fieldIdentityV1)
            try? FileManager.default.createDirectory(at: fileRoot, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func readFile(named name: String, root: URL?) -> Data? {
        guard let root else { return nil }
        let url = root.appendingPathComponent(name)
        return try? Data(contentsOf: url)
    }
}
