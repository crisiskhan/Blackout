import Foundation
import Router

public enum RouteLine {
    public static let sourceID = "route-line-src"
    public static let layerID = "route-line"
    public static let offGraph = GraphPlan.offGraph

    public static func shouldDraw(_ coords: [(lat: Double, lon: Double)]) -> Bool {
        coords.count >= 2
    }

    public static func needsReapply(
        stored: [(lat: Double, lon: Double)]?,
        route: [(lat: Double, lon: Double)]
    ) -> Bool {
        guard let stored else { return true }
        if stored.count != route.count { return true }
        for (a, b) in zip(stored, route) {
            if a.lat != b.lat || a.lon != b.lon { return true }
        }
        return false
    }
}

public enum WalkDriveChip {
    public static func isEnabled(hasUsableGraph: Bool, hasDestination: Bool) -> Bool {
        hasUsableGraph && hasDestination
    }

    public static func chrome(hasUsableGraph: Bool, hasDestination: Bool, planChrome: String) -> String {
        if !hasUsableGraph || !hasDestination { return RouteLine.offGraph }
        return planChrome
    }
}

public enum MapRuler {
    public static func chrome(
        from: (lat: Double, lon: Double)?,
        to: (lat: Double, lon: Double)?
    ) -> String {
        guard let from, let to else { return "RULER —" }
        let meters = GraphRouter.haversine(from.lat, from.lon, to.lat, to.lon)
        return String(format: "RULER %.0f m", meters)
    }
}

public enum MagTrueChip {
    public static func chrome(magNorth: Bool) -> String { magNorth ? "MAG" : "TRUE" }
}

public enum RouteTarget {
    public static func pick(
        explicit: (lat: Double, lon: Double)?,
        lastMark: (lat: Double, lon: Double)?,
        origin: (lat: Double, lon: Double)
    ) -> (lat: Double, lon: Double)? {
        _ = origin
        if let explicit { return explicit }
        if let lastMark { return lastMark }
        return nil
    }
}
