import Foundation

/// Coordinate fields are optional. Denied GPS and nil breadcrumbs are valid.
public struct LocationFix: Hashable, Codable, Sendable {
    public var latitude: Double?
    public var longitude: Double?
    public var altitudeMeters: Double?
    public var horizontalAccuracyMeters: Double?
    public var courseDegrees: Double?
    public var headingDegrees: Double?
    public var timestamp: Date

    public init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitudeMeters: Double? = nil,
        horizontalAccuracyMeters: Double? = nil,
        courseDegrees: Double? = nil,
        headingDegrees: Double? = nil,
        timestamp: Date = Date()
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.courseDegrees = courseDegrees
        self.headingDegrees = headingDegrees
        self.timestamp = timestamp
    }

    public var hasCoordinate: Bool {
        latitude != nil && longitude != nil
    }
}

public enum LocationAuthorization: String, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}
