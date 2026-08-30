import Foundation
import Observation

/// Party lane. Manual DRANK / ATE / I AM NOT OK always work. Heart-rate opt-in is not a gate.
public enum PartyBand: String, Codable, Sendable, CaseIterable {
    case green
    case yellow
    case red
}

public enum PartyVitalAction: String, Sendable, CaseIterable {
    case drank
    case ate
    case notOK
    case imOK
}

public enum PartyVitalsCopy {
    public static let drank = "DRANK"
    public static let ate = "ATE"
    public static let notOK = "I AM NOT OK"
    public static let imOK = "I AM OK"
    public static let imNot = "I AM NOT"
    public static let tapAgain = "Tap again"
    public static let message = "Message"
    public static let navigateTo = "Navigate-to"
    public static let chipHeight: Double = 56
    public static let sosHeight: Double = 88
}

public struct PartyMemberStatus: Hashable, Codable, Sendable, Identifiable {
    public var id: BlackoutID
    public var displayName: String?
    public var band: PartyBand
    public var injury: Bool
    public var drankAt: Date?
    public var ateAt: Date?
    public var latitude: Double?
    public var longitude: Double?
    public var updatedAt: Date

    public init(
        id: BlackoutID = BlackoutID(),
        displayName: String? = nil,
        band: PartyBand = .green,
        injury: Bool = false,
        drankAt: Date? = nil,
        ateAt: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.band = band
        self.injury = injury
        self.drankAt = drankAt
        self.ateAt = ateAt
        self.latitude = latitude
        self.longitude = longitude
        self.updatedAt = updatedAt
    }

    public var shortName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return String(id.rawValue.uuidString.prefix(8))
    }

    public var drankLatched: Bool { drankAt != nil }
    public var ateLatched: Bool { ateAt != nil }
}

/// First tap arms, same control again commits. Accidental red is expensive.
public struct PartyTapState: Equatable, Sendable {
    public var pending: PartyVitalAction?

    public init(pending: PartyVitalAction? = nil) {
        self.pending = pending
    }

    public mutating func tap(_ action: PartyVitalAction) -> Bool {
        if pending == action {
            pending = nil
            return true
        }
        pending = action
        return false
    }
}

/// Existing G/Y/R rules are absent — injury=true → red. DRANK / ATE stamp only.
public enum PartyVitals {
    public static func apply(_ action: PartyVitalAction, to status: inout PartyMemberStatus, at now: Date = Date()) {
        switch action {
        case .drank:
            status.drankAt = now
            status.updatedAt = now
        case .ate:
            status.ateAt = now
            status.updatedAt = now
        case .notOK:
            status.injury = true
            status.band = .red
            status.updatedAt = now
        case .imOK:
            status.injury = false
            status.band = .green
            status.updatedAt = now
        }
    }

    public static func shouldBroadcast(before: PartyMemberStatus, after: PartyMemberStatus) -> Bool {
        before.band != after.band
    }
}

public enum PartyInboundSignal: Equatable, Sendable {
    case ignored
    case updated
    case becameRed(BlackoutID)
}

/// Packet v1 body. Mesh transports this as Envelope.ciphertext and does not inspect it.
public enum PartyStatusWire {
    public static func encode(_ status: PartyMemberStatus) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return (try? encoder.encode(WireV1(status: status))) ?? Data()
    }

    public static func decode(_ data: Data) -> PartyMemberStatus? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode(WireV1.self, from: data))?.status
    }

    public static func envelope(
        status: PartyMemberStatus,
        sender: BlackoutID,
        recipient: BlackoutID
    ) -> Envelope {
        Envelope(
            kind: .partyStatus,
            ciphertext: encode(status),
            sender: sender,
            recipient: recipient
        )
    }

    private struct WireV1: Codable {
        var v: Int
        var id: BlackoutID
        var displayName: String?
        var band: PartyBand
        var injury: Bool
        var drankAt: Date?
        var ateAt: Date?
        var latitude: Double?
        var longitude: Double?
        var updatedAt: Date

        init(status: PartyMemberStatus) {
            v = 1
            id = status.id
            displayName = status.displayName
            band = status.band
            injury = status.injury
            drankAt = status.drankAt
            ateAt = status.ateAt
            latitude = status.latitude
            longitude = status.longitude
            updatedAt = status.updatedAt
        }

        var status: PartyMemberStatus {
            PartyMemberStatus(
                id: id,
                displayName: displayName,
                band: band,
                injury: injury,
                drankAt: drankAt,
                ateAt: ateAt,
                latitude: latitude,
                longitude: longitude,
                updatedAt: updatedAt
            )
        }
    }
}

public enum PartyRadar {
    public static func pipIsRed(_ blip: RadarBlip) -> Bool {
        blip.band == .red && blip.kind != .selfDot
    }

    public static func bearingDegrees(from: LocationFix, toLat: Double, toLon: Double) -> Double? {
        guard from.hasCoordinate, let lat = from.latitude, let lon = from.longitude else { return nil }
        return PartyGeo.bearing(fromLat: lat, fromLon: lon, toLat: toLat, toLon: toLon)
    }

    public static func rangeMeters(from: LocationFix, toLat: Double, toLon: Double) -> Double? {
        guard from.hasCoordinate, let lat = from.latitude, let lon = from.longitude else { return nil }
        return PartyGeo.haversine(fromLat: lat, fromLon: lon, toLat: toLat, toLon: toLon)
    }
}

enum PartyGeo {
    static let earthMeters = 6_371_000.0

    static func haversine(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Double {
        let φ1 = fromLat * .pi / 180
        let φ2 = toLat * .pi / 180
        let Δφ = (toLat - fromLat) * .pi / 180
        let Δλ = (toLon - fromLon) * .pi / 180
        let s = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * earthMeters * atan2(sqrt(s), sqrt(1 - s))
    }

    static func bearing(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Double {
        let φ1 = fromLat * .pi / 180
        let φ2 = toLat * .pi / 180
        let Δλ = (toLon - fromLon) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let θ = atan2(y, x)
        return (θ * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

@MainActor
@Observable
public final class PartyRoster {
    public var selfStatus: PartyMemberStatus
    public var peers: [PartyMemberStatus]
    public var pending: PartyVitalAction?
    public var recipientID: BlackoutID
    public let localID: BlackoutID

    private var alertedRed: Set<BlackoutID> = []
    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        localID: BlackoutID,
        recipientID: BlackoutID? = nil,
        defaults: UserDefaults = .standard,
        storageKey: String = BlackoutKeys.partySelfStatus
    ) {
        self.localID = localID
        self.recipientID = recipientID ?? localID
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let stored = PartyStatusWire.decode(data) {
            var restored = stored
            restored.id = localID
            selfStatus = restored
        } else {
            selfStatus = PartyMemberStatus(id: localID)
        }
        peers = []
    }

    public var isRed: Bool { selfStatus.band == .red }

    /// First tap arms. Second tap on the same action commits. Returns a packet only on band change.
    public func tap(_ action: PartyVitalAction, fix: LocationFix?) -> Envelope? {
        var taps = PartyTapState(pending: pending)
        let commit = taps.tap(action)
        pending = taps.pending
        guard commit else { return nil }
        let before = selfStatus
        PartyVitals.apply(action, to: &selfStatus)
        if let fix, fix.hasCoordinate {
            selfStatus.latitude = fix.latitude
            selfStatus.longitude = fix.longitude
        }
        selfStatus.id = localID
        persistSelf()
        guard PartyVitals.shouldBroadcast(before: before, after: selfStatus) else { return nil }
        return PartyStatusWire.envelope(
            status: selfStatus,
            sender: localID,
            recipient: recipientID
        )
    }

    public func ingest(_ envelope: Envelope) -> PartyInboundSignal {
        guard envelope.kind == .partyStatus else { return .ignored }
        guard envelope.sender != localID else { return .ignored }
        guard var member = PartyStatusWire.decode(envelope.ciphertext) else { return .ignored }
        member.id = envelope.sender
        let previous = peers.first(where: { $0.id == member.id })
        if let index = peers.firstIndex(where: { $0.id == member.id }) {
            peers[index] = member
        } else {
            peers.append(member)
        }
        if member.band == .red, previous?.band != .red, !alertedRed.contains(member.id) {
            alertedRed.insert(member.id)
            return .becameRed(member.id)
        }
        if member.band != .red {
            alertedRed.remove(member.id)
        }
        return .updated
    }

    public func radarBlips(selfFix: LocationFix?, now: Date = Date()) -> [RadarBlip] {
        guard let selfFix, selfFix.hasCoordinate else { return [] }
        return peers.compactMap { peer in
            guard let lat = peer.latitude, let lon = peer.longitude else { return nil }
            guard let range = PartyRadar.rangeMeters(from: selfFix, toLat: lat, toLon: lon),
                  let bearing = PartyRadar.bearingDegrees(from: selfFix, toLat: lat, toLon: lon) else {
                return nil
            }
            return RadarBlip(
                id: peer.id,
                kind: .member,
                displayName: peer.shortName,
                bearingDegrees: bearing,
                rangeMeters: range,
                pingAge: now.timeIntervalSince(peer.updatedAt),
                hops: 1,
                band: peer.band,
                latitude: lat,
                longitude: lon
            )
        }
    }

    private func persistSelf() {
        defaults.set(PartyStatusWire.encode(selfStatus), forKey: storageKey)
    }
}
