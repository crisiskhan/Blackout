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

    /// `OFF GRAPH` is a routing failure, not "you have not picked a DEST yet". Reporting
    /// it before there is a destination sprayed a permanent false alarm down the field.
    public static func chrome(hasUsableGraph: Bool, hasDestination: Bool, planChrome: String) -> String {
        if !hasUsableGraph { return RouteLine.offGraph }
        if !hasDestination { return "" }
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
    /// A bare `MAG` / `TRUE` token read as stack junk on the field. Say which north.
    public static func chrome(magNorth: Bool) -> String { magNorth ? "MAG NORTH" : "TRUE NORTH" }
}

public struct MapFieldLine: Equatable, Sendable, Identifiable {
    public var text: String
    public var warn: Bool
    public var id: String { text }

    public init(text: String, warn: Bool) {
        self.text = text
        self.warn = warn
    }
}

/// The MAP field chrome stack. Lock, route and tool statuses collapse into one deduped
/// line and DEST carries its own bearing, so a second `OFF GRAPH` or a stale `TRUE`
/// cannot spray extra rows down the canvas.
public enum MapFieldChrome: Sendable {
    public static let separator = " · "
    public static let maxLines = 2
    public static let alerts = [RouteLine.offGraph, PackChrome.offPack, "SPEECH FAILED"]

    public static func statusLine(lock: String, route: String, tool: String) -> String {
        joined([lock, route, tool])
    }

    public static func destLine(dest: (lat: Double, lon: Double)?, bearingDeg: Double?) -> String {
        var parts: [String] = []
        if let dest {
            parts.append(String(format: "DEST %.4f, %.4f", dest.lat, dest.lon))
        }
        if let bearingDeg {
            parts.append(String(format: "BEARING %.0f°", bearingDeg))
        }
        return joined(parts)
    }

    public static func lines(
        lock: String,
        route: String,
        tool: String,
        dest: (lat: Double, lon: Double)?,
        bearingDeg: Double?
    ) -> [MapFieldLine] {
        [
            statusLine(lock: lock, route: route, tool: tool),
            destLine(dest: dest, bearingDeg: bearingDeg),
        ]
        .filter { !$0.isEmpty }
        .map { MapFieldLine(text: $0, warn: isAlert($0)) }
    }

    public static func isAlert(_ line: String) -> Bool {
        alerts.contains { line.contains($0) }
    }

    public static func joined(_ parts: [String]) -> String {
        var seen: Set<String> = []
        var kept: [String] = []
        for raw in parts {
            let piece = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty, seen.insert(piece).inserted else { continue }
            kept.append(piece)
        }
        return kept.joined(separator: separator)
    }
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
