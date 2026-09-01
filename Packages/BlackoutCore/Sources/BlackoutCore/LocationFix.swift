import Foundation

public enum LocationFixSource: String, Codable, Sendable {
    case gps
    case deadReckoning
    case manualPin
    case lastKnown
}

/// Coordinate fields are optional. Denied GPS and nil breadcrumbs are valid.
public struct LocationFix: Hashable, Codable, Sendable {
    public var latitude: Double?
    public var longitude: Double?
    public var altitudeMeters: Double?
    public var horizontalAccuracyMeters: Double?
    public var courseDegrees: Double?
    public var headingDegrees: Double?
    public var timestamp: Date
    public var source: LocationFixSource

    public init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitudeMeters: Double? = nil,
        horizontalAccuracyMeters: Double? = nil,
        courseDegrees: Double? = nil,
        headingDegrees: Double? = nil,
        timestamp: Date = Date(),
        source: LocationFixSource = .lastKnown
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.courseDegrees = courseDegrees
        self.headingDegrees = headingDegrees
        self.timestamp = timestamp
        self.source = source
    }

    public var hasCoordinate: Bool {
        latitude != nil && longitude != nil
    }

    /// Prefer this over `latitude!` after `hasCoordinate`.
    public var latLon: (Double, Double)? {
        guard let latitude, let longitude else { return nil }
        return (latitude, longitude)
    }

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, altitudeMeters, horizontalAccuracyMeters
        case courseDegrees, headingDegrees, timestamp, source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        altitudeMeters = try container.decodeIfPresent(Double.self, forKey: .altitudeMeters)
        horizontalAccuracyMeters = try container.decodeIfPresent(Double.self, forKey: .horizontalAccuracyMeters)
        courseDegrees = try container.decodeIfPresent(Double.self, forKey: .courseDegrees)
        headingDegrees = try container.decodeIfPresent(Double.self, forKey: .headingDegrees)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        source = try container.decodeIfPresent(LocationFixSource.self, forKey: .source) ?? .lastKnown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(altitudeMeters, forKey: .altitudeMeters)
        try container.encodeIfPresent(horizontalAccuracyMeters, forKey: .horizontalAccuracyMeters)
        try container.encodeIfPresent(courseDegrees, forKey: .courseDegrees)
        try container.encodeIfPresent(headingDegrees, forKey: .headingDegrees)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(source, forKey: .source)
    }
}

public enum LocationAuthorization: String, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}
