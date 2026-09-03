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
    public static func advance(_ fix: DRFix) -> (lat: Double, lon: Double) {
        let dist = Double(fix.steps) * fix.strideMeters
        let rad = fix.headingDeg * .pi / 180
        let dLat = (dist * cos(rad)) / 111_320.0
        let dLon = (dist * sin(rad)) / (111_320.0 * cos(fix.lat * .pi / 180))
        return (fix.lat + dLat, fix.lon + dLon)
    }

    public static func calibrateStride(knownMeters: Double, steps: Int) -> Double {
        guard steps > 0 else { return 0.75 }
        return knownMeters / Double(steps)
    }
}
