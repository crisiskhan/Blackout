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
    case rested
    case dizzy
    case notOK
    case imOK
}

public enum PartyVitalsCopy {
    public static let drank = "DRANK"
    public static let ate = "ATE"
    public static let rested = "RESTED"
    public static let dizzy = "DIZZY"
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
    public var restedAt: Date?
    public var dizzy: Bool
    public var dizzyAt: Date?
    public var latitude: Double?
    public var longitude: Double?
    public var updatedAt: Date
    /// Honest radio hops from the pipe. Not ciphertext.
    public var hops: Int

    public init(
        id: BlackoutID = BlackoutID(),
        displayName: String? = nil,
        band: PartyBand = .green,
        injury: Bool = false,
        drankAt: Date? = nil,
        ateAt: Date? = nil,
        restedAt: Date? = nil,
        dizzy: Bool = false,
        dizzyAt: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        updatedAt: Date = Date(),
        hops: Int = 1
    ) {
        self.id = id
        self.displayName = displayName
        self.band = band
        self.injury = injury
        self.drankAt = drankAt
        self.ateAt = ateAt
        self.restedAt = restedAt
        self.dizzy = dizzy
        self.dizzyAt = dizzyAt
        self.latitude = latitude
        self.longitude = longitude
        self.updatedAt = updatedAt
        self.hops = hops
    }

    /// Person name is the callsign. There is no second display-name field.
    public var callsign: String { Callsign.commit(displayName ?? "") }

    public var shortName: String { callsign }

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

/// G/Y/R math. RESTED / DIZZY stay here — not Map chips. Red is not an SOS fire.
public enum PartyVitals {
    public static let redFiresSOS = false

    public static func isMapChip(_ action: PartyVitalAction) -> Bool {
        switch action {
        case .imOK, .notOK:
            return true
        case .drank, .ate, .rested, .dizzy:
            return false
        }
    }

    public static func resolveBand(_ status: PartyMemberStatus) -> PartyBand {
        if status.injury { return .red }
        if status.dizzy { return .yellow }
        return .green
    }

    public static func apply(_ action: PartyVitalAction, to status: inout PartyMemberStatus, at now: Date = Date()) {
        switch action {
        case .drank:
            status.drankAt = now
        case .ate:
            status.ateAt = now
        case .rested:
            status.restedAt = now
        case .dizzy:
            status.dizzy = true
            status.dizzyAt = now
        case .notOK:
            status.injury = true
        case .imOK:
            status.injury = false
            status.dizzy = false
        }
        status.updatedAt = now
        status.band = resolveBand(status)
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
        var restedAt: Date?
        var dizzy: Bool
        var dizzyAt: Date?
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
            restedAt = status.restedAt
            dizzy = status.dizzy
            dizzyAt = status.dizzyAt
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
                restedAt: restedAt,
                dizzy: dizzy,
                dizzyAt: dizzyAt,
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
    public let identity: LocalIdentityStore
    public private(set) var isFrozen = false

    private var alertedRed: Set<BlackoutID> = []
    private let defaults: UserDefaults
    private let storageKey: String

    public var localID: BlackoutID { identity.deviceID }
    /// One SelfVitals object. Map I AM OK and Expedition DRANK / ATE / I AM NOT OK write this.
    public var selfVitals: PartyMemberStatus {
        get { selfStatus }
        set { selfStatus = newValue }
    }
    public var peerCount: Int { peers.count }
    public var liveCallsigns: [(BlackoutID, String)] {
        [(localID, identity.callsign)] + peers.map { ($0.id, $0.callsign) }
    }

    public func label(for id: BlackoutID, callsign: String) -> CallsignLabel {
        CallsignLabel.resolve(callsign: callsign, id: id, among: liveCallsigns)
    }

    public func label(for member: PartyMemberStatus) -> CallsignLabel {
        label(for: member.id, callsign: member.callsign)
    }

    public var selfLabel: CallsignLabel {
        label(for: localID, callsign: identity.callsign)
    }

    public init(
        localID: BlackoutID,
        recipientID: BlackoutID? = nil,
        defaults: UserDefaults = .standard,
        storageKey: String = BlackoutKeys.partySelfStatus,
        identity: LocalIdentityStore? = nil
    ) {
        let profile = identity ?? LocalIdentityStore(deviceID: localID, defaults: defaults)
        self.identity = profile
        self.recipientID = recipientID ?? profile.deviceID
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let stored = PartyStatusWire.decode(data) {
            var restored = stored
            restored.id = profile.deviceID
            restored.displayName = profile.callsign
            selfStatus = restored
        } else {
            selfStatus = PartyMemberStatus(id: profile.deviceID, displayName: profile.callsign)
        }
        peers = []
    }

    public var isRed: Bool { selfStatus.band == .red }

    @discardableResult
    public func commitCallsign(_ raw: String) -> String {
        let next = identity.commitCallsign(raw)
        selfStatus.displayName = next
        persistSelf()
        return next
    }

    @discardableResult
    public func createParty() -> Bool {
        let ok = identity.createParty()
        if ok {
            isFrozen = false
            peers = []
            alertedRed = []
        }
        return ok
    }

    @discardableResult
    public func joinParty(_ raw: String) -> Bool {
        let ok = identity.joinParty(raw)
        if ok {
            isFrozen = false
            peers = []
            alertedRed = []
        }
        return ok
    }

    /// Mesh stops at the composition root. Roster freezes. Callsign stays.
    public func leaveParty() {
        identity.leaveParty()
        isFrozen = true
        pending = nil
    }

    /// Emit current SelfVitals so a callsign change reaches the mesh without a band change.
    public func broadcastSelf(fix: LocationFix?) -> Envelope? {
        guard MeshGate.allowsTraffic(partyCode: identity.partyCode), !isFrozen else { return nil }
        applyFix(fix)
        selfStatus.id = localID
        selfStatus.displayName = identity.callsign
        persistSelf()
        return PartyStatusWire.envelope(
            status: selfStatus,
            sender: localID,
            recipient: recipientID
        )
    }

    /// SOS strobe / CALL set injury immediately. Not the two-tap Map chip. Not an SOS arm.
    @discardableResult
    public func markInjured(fix: LocationFix?) -> Envelope? {
        pending = nil
        let before = selfStatus
        PartyVitals.apply(.notOK, to: &selfStatus)
        if let fix, fix.hasCoordinate {
            selfStatus.latitude = fix.latitude
            selfStatus.longitude = fix.longitude
        }
        selfStatus.id = localID
        selfStatus.displayName = identity.callsign
        persistSelf()
        guard PartyVitals.shouldBroadcast(before: before, after: selfStatus) else { return nil }
        return PartyStatusWire.envelope(
            status: selfStatus,
            sender: localID,
            recipient: recipientID
        )
    }

    /// First tap arms. Second tap on the same action commits. Returns a packet only on band change.
    public func tap(_ action: PartyVitalAction, fix: LocationFix?) -> Envelope? {
        var taps = PartyTapState(pending: pending)
        let commit = taps.tap(action)
        pending = taps.pending
        guard commit else { return nil }
        let before = selfStatus
        PartyVitals.apply(action, to: &selfStatus)
        applyFix(fix)
        selfStatus.id = localID
        selfStatus.displayName = identity.callsign
        persistSelf()
        guard PartyVitals.shouldBroadcast(before: before, after: selfStatus) else { return nil }
        return PartyStatusWire.envelope(
            status: selfStatus,
            sender: localID,
            recipient: recipientID
        )
    }

    public func ingest(_ envelope: Envelope) -> PartyInboundSignal {
        guard !isFrozen else { return .ignored }
        guard envelope.sender != localID else { return .ignored }
        switch envelope.kind {
        case .partyStatus:
            guard var member = PartyStatusWire.decode(envelope.ciphertext) else { return .ignored }
            member.id = envelope.sender
            member.displayName = Callsign.commit(member.displayName ?? "")
            member.hops = max(1, envelope.hopCount)
            return upsertPeer(member)
        case .sosAlert:
            var member = peers.first(where: { $0.id == envelope.sender })
                ?? PartyMemberStatus(
                    id: envelope.sender,
                    displayName: SOSMeshBody.callsign(in: envelope.ciphertext)
                )
            member.displayName = SOSMeshBody.callsign(in: envelope.ciphertext)
            member.hops = max(1, envelope.hopCount)
            PartyVitals.apply(.notOK, to: &member)
            return upsertPeer(member)
        case .message, .pttClip, .locationFix, .breadcrumb, .guideCard, .followTrack:
            return .ignored
        }
    }

    public func radarBlips(selfFix: LocationFix?, now: Date = Date()) -> [RadarBlip] {
        guard let selfFix, selfFix.hasCoordinate else { return [] }
        let selfDot = RadarBlip(
            id: localID,
            kind: .selfDot,
            displayName: selfLabel.name,
            footnote: selfLabel.footnote,
            bearingDegrees: 0,
            rangeMeters: 0,
            band: selfStatus.band,
            latitude: selfFix.latitude,
            longitude: selfFix.longitude
        )
        let members = peers.compactMap { peer -> RadarBlip? in
            guard let lat = peer.latitude, let lon = peer.longitude else { return nil }
            guard let range = PartyRadar.rangeMeters(from: selfFix, toLat: lat, toLon: lon),
                  let bearing = PartyRadar.bearingDegrees(from: selfFix, toLat: lat, toLon: lon) else {
                return nil
            }
            return RadarBlip(
                id: peer.id,
                kind: .member,
                displayName: peer.callsign,
                footnote: label(for: peer).footnote,
                bearingDegrees: bearing,
                rangeMeters: range,
                pingAge: now.timeIntervalSince(peer.updatedAt),
                hops: peer.hops,
                band: peer.band,
                latitude: lat,
                longitude: lon
            )
        }
        return [selfDot] + members
    }

    @discardableResult
    private func upsertPeer(_ member: PartyMemberStatus) -> PartyInboundSignal {
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

    private func applyFix(_ fix: LocationFix?) {
        if let fix, fix.hasCoordinate {
            selfStatus.latitude = fix.latitude
            selfStatus.longitude = fix.longitude
        }
    }

    private func persistSelf() {
        defaults.set(PartyStatusWire.encode(selfStatus), forKey: storageKey)
    }
}
