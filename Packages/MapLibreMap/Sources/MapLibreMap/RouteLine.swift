import Foundation
import Router

public enum RouteLine {
    public static let sourceID = "route-line-src"
    public static let casingLayerID = "route-line-casing"
    public static let layerID = "route-line"
    public static let coreLayerID = "route-line-core"
    public static let offGraph = GraphPlan.offGraph
    /// Void halo has to beat the street casing at walking zoom (10.6 at z15).
    public static let casingWidth: Double = 12.5
    /// Silver fill has to beat the major street fill at walking zoom (6.6 at z15).
    public static let fillWidth: Double = 7.4
    /// Scarce accent thread so the path still reads on an arterial.
    public static let coreWidth: Double = 2.4
    /// The annotation is a hook. Style layers carry the paint, so this stays
    /// thin enough not to cover the void casing or the accent core.
    public static let annotationWidth: Double = 0.01
    /// Multiples of the accent core width. WALK is a broken thread so it
    /// never reads as another arterial; DRIVE stays continuous.
    public static let walkDash: [Double] = [2.2, 1.6]

    public static func dashPattern(_ mode: TravelMode) -> [Double]? {
        switch mode {
        case .walk: return walkDash
        case .drive: return nil
        }
    }

    public static func shouldDraw(_ coords: [(lat: Double, lon: Double)]) -> Bool {
        coords.count >= 2
    }

    public static func needsReapply(
        stored: [(lat: Double, lon: Double)]?,
        route: [(lat: Double, lon: Double)],
        storedMode: TravelMode? = nil,
        mode: TravelMode = .walk
    ) -> Bool {
        if let storedMode, storedMode != mode { return true }
        guard let stored else { return true }
        if stored.count != route.count { return true }
        for (a, b) in zip(stored, route) {
            if a.lat != b.lat || a.lon != b.lon { return true }
        }
        return false
    }
}

/// The chosen destination, drawn on the canvas so the map does not need to
/// print raw latitude and longitude to say where you are headed.
/// The place the inspect card is about. Drawn brighter and wider than the
/// destination pin because it has to read through the card's own scrim.
public enum HoldPin {
    public static let sourceID = "hold-pin-src"
    public static let ringLayerID = "hold-pin-ring"
    public static let coreLayerID = "hold-pin-core"
    public static let ringRadius: Double = 19
    public static let coreRadius: Double = 6

    public static func needsReapply(
        stored: (lat: Double, lon: Double)?,
        held: (lat: Double, lon: Double)?
    ) -> Bool {
        DestinationPin.needsReapply(stored: stored, destination: held)
    }
}

public enum DestinationPin {
    public static let sourceID = "dest-pin-src"
    public static let ringLayerID = "dest-pin-ring"
    public static let coreLayerID = "dest-pin-core"
    public static let ringRadius: Double = 13
    public static let coreRadius: Double = 5

    public static func needsReapply(
        stored: (lat: Double, lon: Double)?,
        destination: (lat: Double, lon: Double)?
    ) -> Bool {
        switch (stored, destination) {
        case (nil, nil):
            return false
        case let (a?, b?):
            return a.lat != b.lat || a.lon != b.lon
        default:
            return true
        }
    }
}

/// A party body on the canvas. Heading is live when the peer sent it.
public struct PartyBody: Equatable, Sendable {
    public var id: String
    public var lat: Double
    public var lon: Double
    public var headingDeg: Double?
    public var emblem: String?

    public init(
        id: String,
        lat: Double,
        lon: Double,
        headingDeg: Double? = nil,
        emblem: String? = nil
    ) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.headingDeg = headingDeg
        self.emblem = emblem
    }
}

/// Bodies on the canvas. Silver only — red stays scarce.
public enum PartyPips {
    public static let sourceID = "party-pips-src"
    public static let haloLayerID = "party-pips-halo"
    public static let coreLayerID = "party-pips-core"
    public static let haloRadius: Double = 16
    public static let coreRadius: Double = 7
    public static let titlePrefix = "PARTY·"

    public static func needsReapply(
        stored: [PartyBody]?,
        pips: [PartyBody]
    ) -> Bool {
        // Position and heading move in place via syncPartyMarks. Rebuilding
        // style sources on every peer POS is the same class as tearing YOU
        // down on GPS ticks.
        guard let stored else { return true }
        if stored.count != pips.count { return true }
        for (a, b) in zip(stored, pips) {
            if a.id != b.id || a.emblem != b.emblem {
                return true
            }
        }
        return false
    }
}

/// Why a WALK or DRIVE tap could not draw a street line. The chips are never
/// disabled, so every tap either draws or says one of these out loud.
public enum RouteBlock: String, Equatable, Sendable, CaseIterable {
    case noPack
    case noGraph
    case noDestination
    case destinationOffPack
    case noPath

    /// Plan state handed to VoiceNav. Only a real routing failure is OFF GRAPH;
    /// an unset destination is a prompt, not a dead end.
    public var planChrome: String {
        switch self {
        case .noDestination:
            return ""
        case .noPack, .noGraph, .destinationOffPack, .noPath:
            return RouteLine.offGraph
        }
    }

    public func chrome(mode: TravelMode, packName: String) -> String {
        let verb = WalkDriveChip.verb(mode)
        let pack = packName.isEmpty ? "THIS PACK" : packName.uppercased()
        switch self {
        case .noPack:
            return "\(verb) — NO MAP PACK ON THIS PHONE"
        case .noGraph:
            return "\(verb) — \(pack) HAS NO STREET GRAPH"
        case .noDestination:
            return "\(verb) — TAP THE MAP TO SET A DESTINATION"
        case .destinationOffPack:
            return "\(verb) — DESTINATION IS OUTSIDE \(pack)"
        case .noPath:
            return "\(RouteLine.offGraph) — NO \(verb) PATH FROM YOU"
        }
    }
}

public enum WalkDriveChip {
    /// WALK and DRIVE always tap. A dead control tells the field nothing.
    public static let alwaysTappable = true

    public static func verb(_ mode: TravelMode) -> String {
        switch mode {
        case .walk: return "WALK"
        case .drive: return "DRIVE"
        }
    }

    public static func block(
        hasPack: Bool,
        hasUsableGraph: Bool,
        hasDestination: Bool,
        destinationOnPack: Bool
    ) -> RouteBlock? {
        if !hasPack { return .noPack }
        if !hasUsableGraph { return .noGraph }
        if !hasDestination { return .noDestination }
        if !destinationOnPack { return .destinationOffPack }
        return nil
    }

    public static func working(mode: TravelMode) -> String {
        "\(verb(mode)) — PLOTTING…"
    }

    /// `OFF GRAPH` is a routing failure, not "you have not picked a DEST yet". Reporting
    /// it before there is a destination sprayed a permanent false alarm down the field.
    public static func chrome(hasUsableGraph: Bool, hasDestination: Bool, planChrome: String) -> String {
        if !hasUsableGraph { return RouteLine.offGraph }
        if !hasDestination { return "" }
        return planChrome
    }
}

public enum RouteSummary {
    public static let walkMetersPerSecond = 1.25
    public static let driveMetersPerSecond = 11.0

    public static func meters(_ coords: [(lat: Double, lon: Double)]) -> Double {
        guard coords.count >= 2 else { return 0 }
        return zip(coords, coords.dropFirst()).reduce(0.0) { total, leg in
            total + GraphRouter.haversine(leg.0.lat, leg.0.lon, leg.1.lat, leg.1.lon)
        }
    }

    public static func chrome(mode: TravelMode, coords: [(lat: Double, lon: Double)]) -> String {
        guard RouteLine.shouldDraw(coords) else {
            return RouteBlock.noPath.chrome(mode: mode, packName: "")
        }
        let total = meters(coords)
        let speed = mode == .walk ? walkMetersPerSecond : driveMetersPerSecond
        let minutes = max(1, Int((total / speed / 60).rounded()))
        return "\(WalkDriveChip.verb(mode)) \(distancePhrase(total)) · ~\(minutes) min"
    }

    public static func distancePhrase(_ meters: Double) -> String {
        if meters < 1000 { return String(format: "%.0f m", meters.rounded()) }
        return String(format: "%.1f km", meters / 1000)
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

public enum MapFieldDestMode: String, CaseIterable, Sendable {
    case bearing
    case coordinates

    public var title: String {
        switch self {
        case .bearing:
            return "BEARING"
        case .coordinates:
            return "COORDINATES"
        }
    }
}

public struct MapFieldLine: Equatable, Sendable, Identifiable {
    public enum Slot: String, CaseIterable, Sendable {
        case status, dest, speak
    }

    public var slot: Slot
    public var text: String
    public var warn: Bool
    public var id: String { slot.rawValue }

    public init(slot: Slot, text: String, warn: Bool) {
        self.slot = slot
        self.text = text
        self.warn = warn
    }
}

/// The MAP field chrome stack: at most three short lines, each one deduped. Lock, route
/// and tool statuses share a line, the heading gets its own, and Speak gets one status
/// line — never a turn-by-turn paragraph over the canvas.
public enum MapFieldChrome: Sendable {
    public static let separator = " · "
    public static let maxLines = MapFieldLine.Slot.allCases.count
    public static let alerts = [RouteLine.offGraph, PackChrome.offPack, "SPEECH FAILED"]

    public static func statusLine(lock: String, route: String, tool: String) -> String {
        joined([lock, route, tool])
    }

    /// Dest chips mount when there is somewhere to walk, even if heading is
    /// unusable — COORDINATES still has a line to print.
    public static func destRailVisible(
        hasDestination: Bool,
        lockOn: Bool,
        hasRoute: Bool
    ) -> Bool {
        hasDestination || lockOn || hasRoute
    }

    /// Heading token for the dest slot. The pin stays on the canvas. Live YOU
    /// is destValue on COORDINATES — this string is never a DEST pair. Dest
    /// chips still mount without a course so the COORDINATES line can print.
    public static func destLine(
        bearingDeg: Double?,
        you: (lat: Double, lon: Double)? = nil,
        destActive: Bool = false
    ) -> String {
        _ = you
        if let bearingDeg, bearingDeg >= 0 {
            return String(format: "BEARING %.0f°", bearingDeg)
        }
        return destActive ? "NO HEADING" : ""
    }

    /// Dest-line field. Bearing is the course. Coordinates are live GNSS.
    public static func destValue(
        mode: MapFieldDestMode,
        bearingDeg: Double?,
        you: (lat: Double, lon: Double)?
    ) -> String {
        switch mode {
        case .bearing:
            guard let bearingDeg, bearingDeg >= 0 else { return "NO HEADING" }
            return String(format: "%.0f°", bearingDeg)
        case .coordinates:
            guard let you else { return "NO FIX" }
            return String(format: "%.5f, %.5f", you.lat, you.lon)
        }
    }

    /// Inactive chrome stays quiet: no BEARING row unless there is somewhere
    /// to walk (dest, drawn route, or LOCK-ON). An unusable heading is not a
    /// course — Apple's `-1°` must not print as 359°.
    public static func activeBearing(
        headingDeg: Double?,
        hasDestination: Bool,
        lockOn: Bool,
        hasRoute: Bool
    ) -> Double? {
        guard hasDestination || lockOn || hasRoute else { return nil }
        guard let headingDeg, headingDeg >= 0 else { return nil }
        return headingDeg
    }

    public static func lines(
        lock: String,
        route: String,
        tool: String,
        bearingDeg: Double?,
        speak: String,
        you: (lat: Double, lon: Double)? = nil,
        destActive: Bool = false
    ) -> [MapFieldLine] {
        [
            (MapFieldLine.Slot.status, statusLine(lock: lock, route: route, tool: tool)),
            (.dest, destLine(bearingDeg: bearingDeg, you: you, destActive: destActive)),
            (.speak, speak.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        .filter { !$0.1.isEmpty }
        .map { MapFieldLine(slot: $0.0, text: $0.1, warn: isAlert($0.1)) }
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
