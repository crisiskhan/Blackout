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
    /// YOU · last-4 when two live identities are still YOU. Not a second person name.
    public var footnote: String?
    public var bearingDegrees: Double
    public var rangeMeters: Double
    public var pingAge: TimeInterval?
    public var hops: Int?
    public var band: PartyBand
    public var latitude: Double?
    public var longitude: Double?

    public init(
        id: BlackoutID = BlackoutID(),
        kind: RadarBlipKind,
        displayName: String? = nil,
        footnote: String? = nil,
        bearingDegrees: Double,
        rangeMeters: Double,
        pingAge: TimeInterval? = nil,
        hops: Int? = nil,
        band: PartyBand = .green,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.footnote = footnote
        self.bearingDegrees = bearingDegrees
        self.rangeMeters = rangeMeters
        self.pingAge = pingAge
        self.hops = hops
        self.band = band
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isUnknown: Bool { displayName == nil || displayName?.isEmpty == true }
}
