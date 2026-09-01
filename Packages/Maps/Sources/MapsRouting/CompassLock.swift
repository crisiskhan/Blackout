import Foundation

/// Single field-steer seed list. Do not add a second hardcoded waypoint table.
public enum CompassLockStandards {
    public static let waypoints: [CompassLockWaypoint] = [
        CompassLockWaypoint(
            id: "th",
            name: "Trailhead",
            latitude: 31.8924,
            longitude: -106.4401,
            kind: .standard
        ),
        CompassLockWaypoint(
            id: "wc",
            name: "Water cache",
            latitude: 31.8964,
            longitude: -106.4428,
            kind: .standard
        ),
    ]
}

public enum CompassLockKind: String, Codable, Sendable {
    case standard
    case mark
    case peer
    case poi
}

public struct CompassLockWaypoint: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var kind: CompassLockKind

    public init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        kind: CompassLockKind
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.kind = kind
    }

    public var coordinate: RoutingCoordinate {
        RoutingCoordinate(latitude: latitude, longitude: longitude)
    }

    public var canDelete: Bool {
        switch kind {
        case .standard, .peer:
            return false
        case .poi:
            return false
        case .mark:
            return true
        }
    }
}

public enum CompassLockCopy {
    public static let nothingToLock = "Nothing to lock. MARK a point or wait for a peer."
    public static let speak = "SPEAK"
    public static let steer = "STEER"
    public static let mark = "MARK"
    public static let lock = "LOCK"
    public static let locked = "LOCKED"
    public static let saveCurrent = "SAVE CURRENT"
    public static let delete = "DELETE"
}

public enum CompassLockMath {
    public static let holdDegrees = 8.0
    public static let voiceInterval: TimeInterval = 2.2
    public static let speechRateMin: Float = 0.47
    public static let speechRateMax: Float = 0.52
    public static let speechRate: Float = 0.50

    /// `((target - heading + 540) % 360) - 180`
    public static func relBearing(target: Double, heading: Double) -> Double {
        (target - heading + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    public static func turnPhrase(rel: Double) -> String {
        if abs(rel) <= holdDegrees { return "Hold course" }
        let deg = Int(abs(rel).rounded())
        if rel > 0 { return "Right \(deg)°" }
        return "Left \(deg)°"
    }

    public static func fmtDist(_ meters: Double) -> String {
        Formatters.distance(meters)
    }

    public static func phrase(name: String, meters: Double, rel: Double) -> String {
        "\(name). \(fmtDist(meters)). \(turnPhrase(rel: rel))."
    }

    public static func phrase(
        name: String,
        origin: RoutingCoordinate,
        target: RoutingCoordinate,
        heading: Double
    ) -> String {
        let meters = Geo.haversine(origin, target)
        let bearing = Geo.bearing(origin, target)
        return phrase(name: name, meters: meters, rel: relBearing(target: bearing, heading: heading))
    }

    public static func defaultMarkName(at date: Date = Date(), calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d%02d", hour, minute)
    }

    public static func committedName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    public static func lockHeading(
        origin: RoutingCoordinate?,
        dest: RoutingCoordinate?,
        fallback: Double?
    ) -> Double? {
        if let origin, let dest {
            return Geo.bearing(origin, dest)
        }
        return fallback
    }

    public static func lockOnLine(headingDegrees: Double?) -> String {
        guard let headingDegrees, headingDegrees.isFinite else { return "LOCK ON" }
        var deg = headingDegrees.truncatingRemainder(dividingBy: 360)
        if deg < 0 { deg += 360 }
        let rounded = Int(deg.rounded()) % 360
        return "LOCK ON • \(rounded)° \(cardinal(rounded))"
    }

    public static func cardinal(_ degrees: Int) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int((Double((degrees % 360 + 360) % 360) / 45.0).rounded()) % 8
        return dirs[idx]
    }
}
