import Foundation

public struct DRFix: Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    public var headingDeg: Double
    public var strideMeters: Double
    public var steps: Int

    public init(lat: Double, lon: Double, headingDeg: Double, strideMeters: Double, steps: Int) {
        self.lat = lat
        self.lon = lon
        self.headingDeg = headingDeg
        self.strideMeters = strideMeters
        self.steps = steps
    }
}

public enum DeadReckoning {
    public static let capMeters: Double = 200
    public static let maxAgeSeconds: TimeInterval = 60
    public static let lastFix = "LAST FIX"
    public static let defaultStride: Double = 0.75

    public static func advance(_ fix: DRFix) -> (lat: Double, lon: Double) {
        let dist = Double(fix.steps) * fix.strideMeters
        let rad = fix.headingDeg * .pi / 180
        let dLat = (dist * cos(rad)) / 111_320.0
        let dLon = (dist * sin(rad)) / (111_320.0 * cos(fix.lat * .pi / 180))
        return (fix.lat + dLat, fix.lon + dLon)
    }

    public static func calibrateStride(knownMeters: Double, steps: Int) -> Double {
        guard steps > 0 else { return defaultStride }
        return knownMeters / Double(steps)
    }

    /// Last GNSS plus steps, or the last fix itself. Never invents a walk.
    public static func hold(
        last: (lat: Double, lon: Double),
        headingDeg: Double?,
        strideMeters: Double,
        steps: Int,
        ageSeconds: Double
    ) -> (lat: Double, lon: Double, chrome: String, advanced: Bool) {
        guard ageSeconds.isFinite, ageSeconds >= 0, ageSeconds <= maxAgeSeconds else {
            return (last.lat, last.lon, lastFix, false)
        }
        guard steps > 0, let headingDeg, headingDeg >= 0, headingDeg.isFinite else {
            return (last.lat, last.lon, lastFix, false)
        }
        let dist = Double(steps) * strideMeters
        guard dist > 0, dist <= capMeters else {
            return (last.lat, last.lon, lastFix, false)
        }
        let next = advance(
            DRFix(
                lat: last.lat,
                lon: last.lon,
                headingDeg: headingDeg,
                strideMeters: strideMeters,
                steps: steps
            )
        )
        return (next.lat, next.lon, lastFix, true)
    }
}
