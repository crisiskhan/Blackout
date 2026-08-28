import Foundation

/// Visual language for the Map radar HUD. Wave 1.5 has 0 peers — only `selfDot` is drawn.
public enum RadarBlipKind: String, Sendable, Codable {
    /// Filled silver disk. Party / known member. Wave 2.
    case member
    /// Hollow silver.edge ring. Stranger radio. Wave 2 — do not invent these.
    case stranger
    case selfDot
}

public struct RadarBlip: Hashable, Sendable, Identifiable {
    public var id: BlackoutID
    public var kind: RadarBlipKind
    public var displayName: String?
    public var bearingDegrees: Double
    public var rangeMeters: Double
    public var pingAge: TimeInterval?
    public var hops: Int?

    public init(
        id: BlackoutID = BlackoutID(),
        kind: RadarBlipKind,
        displayName: String? = nil,
        bearingDegrees: Double,
        rangeMeters: Double,
        pingAge: TimeInterval? = nil,
        hops: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bearingDegrees = bearingDegrees
        self.rangeMeters = rangeMeters
        self.pingAge = pingAge
        self.hops = hops
    }

    public var isUnknown: Bool { displayName == nil || displayName?.isEmpty == true }
}
