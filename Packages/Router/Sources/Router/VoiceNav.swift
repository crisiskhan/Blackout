import Foundation
import Tokens

public enum VoiceTurn: String, Equatable, Sendable {
    case straight
    case left
    case right
    case uturn
}

public enum VoiceNav: Sendable {
    public static let arrive = "Arrive at destination."
    public static let offGraphPath = "No walkable street path from YOU."
    public static let offGraphDrivePath = "No drivable street path from YOU."
    public static let startHint = "Set a destination, then WALK or DRIVE, then SPEAK for turn by turn."
    public static let destHint = "Tap WALK or DRIVE for the street path, then SPEAK."
    public static let minLegMeters: Double = 8
    public static let straightDeg: Double = 35
    public static let uturnDeg: Double = 135

    public static func pathFailure(_ mode: TravelMode) -> String {
        switch mode {
        case .walk: return offGraphPath
        case .drive: return offGraphDrivePath
        }
    }

    public static func legVerb(_ mode: TravelMode) -> String {
        switch mode {
        case .walk: return "Walk"
        case .drive: return "Drive"
        }
    }

    public static func prompt(
        packName: String,
        headingDeg: Double?,
        routeCoords: [(lat: Double, lon: Double)],
        planChrome: String,
        destination: (lat: Double, lon: Double)?,
        you: (lat: Double, lon: Double)?,
        locale: String,
        travelMode: TravelMode = .walk,
        streets: [String?] = []
    ) -> String {
        _ = locale
        let headingBit: String
        if let headingDeg, headingDeg >= 0 {
            headingBit = "Heading \(metersPhrase(headingDeg, asHeading: true))."
        } else {
            headingBit = "Heading unavailable."
        }
        if routeCoords.count >= 2 {
            let total = zip(routeCoords, routeCoords.dropFirst()).reduce(0.0) { acc, pair in
                acc + GraphRouter.haversine(pair.0.lat, pair.0.lon, pair.1.lat, pair.1.lon)
            }
            let body = steps(routeCoords, travelMode: travelMode, streets: streets).joined(separator: " ")
            return "\(body) Total \(metersPhrase(total)). \(headingBit)"
        }
        if planChrome == GraphPlan.offGraph {
            return "OFF GRAPH. \(pathFailure(travelMode)) \(packName). \(headingBit)"
        }
        if let destination, let you {
            let span = GraphRouter.haversine(you.lat, you.lon, destination.lat, destination.lon)
            return "Destination set. \(metersPhrase(span)). \(packName). \(headingBit) \(destHint)"
        }
        return "\(packName). \(headingBit) \(startHint)"
    }

    public static func steps(
        _ coords: [(lat: Double, lon: Double)],
        travelMode: TravelMode = .walk,
        streets: [String?] = []
    ) -> [String] {
        walk(coords, travelMode: travelMode, streets: streets, spoken: true)
    }

    /// HUD words for the glass TURNS plate. Never the spoken script.
    public static func hudTurns(
        _ coords: [(lat: Double, lon: Double)],
        travelMode: TravelMode = .walk,
        streets: [String?] = []
    ) -> [String] {
        walk(coords, travelMode: travelMode, streets: streets, spoken: false)
    }

    /// The next named turn for the dest rail. Empty when the line is straight in.
    public static func nextTurnHUD(
        _ coords: [(lat: Double, lon: Double)],
        streets: [String?] = []
    ) -> String {
        for line in hudTurns(coords, streets: streets) {
            if line.hasPrefix("LEFT") || line.hasPrefix("RIGHT") || line.hasPrefix("AROUND") {
                return line
            }
        }
        return ""
    }

    private static func walk(
        _ coords: [(lat: Double, lon: Double)],
        travelMode: TravelMode,
        streets: [String?],
        spoken: Bool
    ) -> [String] {
        guard coords.count >= 2 else { return [] }
        var lines: [String] = []
        var acc = 0.0
        var prevBearing: Double?
        var legStreet = streetAt(streets, 0)
        for i in 0..<(coords.count - 1) {
            let a = coords[i]
            let b = coords[i + 1]
            let m = GraphRouter.haversine(a.lat, a.lon, b.lat, b.lon)
            let brg = bearing(from: a, to: b)
            guard let last = prevBearing else {
                acc += m
                prevBearing = brg
                continue
            }
            let kind = turn(from: last, to: brg)
            switch kind {
            case .straight:
                acc += m
                prevBearing = brg
            case .left, .right, .uturn:
                if acc >= minLegMeters {
                    lines.append(legLine(travelMode, acc, legStreet, spoken: spoken))
                }
                let onto = streetAt(streets, i)
                lines.append(turnLine(kind, onto, spoken: spoken))
                acc = m
                prevBearing = brg
                legStreet = onto
            }
        }
        if acc >= minLegMeters {
            lines.append(legLine(travelMode, acc, legStreet, spoken: spoken))
        }
        lines.append(spoken ? arrive : "ARRIVE")
        return lines
    }

    private static func streetAt(_ streets: [String?], _ index: Int) -> String? {
        guard streets.indices.contains(index) else { return nil }
        let name = streets[index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    private static func legLine(
        _ mode: TravelMode,
        _ meters: Double,
        _ street: String?,
        spoken: Bool
    ) -> String {
        if spoken {
            if let street {
                return "\(legVerb(mode)) \(metersPhrase(meters)) on \(street)."
            }
            return "\(legVerb(mode)) \(metersPhrase(meters))."
        }
        let verb = mode == .drive ? "DRIVE" : "WALK"
        return hudFit([verb, BlackoutTokens.Distance.hud(meters)] + (street.map { [$0.uppercased()] } ?? []))
    }

    private static func turnLine(_ kind: VoiceTurn, _ onto: String?, spoken: Bool) -> String {
        switch kind {
        case .straight:
            return spoken ? "" : ""
        case .left:
            if spoken {
                return onto.map { "Turn left onto \($0)." } ?? "Turn left."
            }
            return hudFit(["LEFT"] + (onto.map { [$0.uppercased()] } ?? []))
        case .right:
            if spoken {
                return onto.map { "Turn right onto \($0)." } ?? "Turn right."
            }
            return hudFit(["RIGHT"] + (onto.map { [$0.uppercased()] } ?? []))
        case .uturn:
            if spoken {
                return onto.map { "Turn around onto \($0)." } ?? "Turn around."
            }
            return hudFit(["AROUND"] + (onto.map { [$0.uppercased()] } ?? []))
        }
    }

    private static func hudFit(_ parts: [String]) -> String {
        var parts = parts.filter { !$0.isEmpty }
        var line = parts.joined(separator: " · ")
        while line.count > 44, parts.count > 1 {
            parts.removeLast()
            line = parts.joined(separator: " · ")
        }
        return line
    }

    public static func turn(from: Double, to: Double) -> VoiceTurn {
        let delta = ((to - from + 540).truncatingRemainder(dividingBy: 360)) - 180
        if abs(delta) < straightDeg { return .straight }
        if abs(delta) > uturnDeg { return .uturn }
        return delta < 0 ? .left : .right
    }

    public static func bearing(
        from: (lat: Double, lon: Double),
        to: (lat: Double, lon: Double)
    ) -> Double {
        let y = sin((to.lon - from.lon) * .pi / 180) * cos(to.lat * .pi / 180)
        let x = cos(from.lat * .pi / 180) * sin(to.lat * .pi / 180)
            - sin(from.lat * .pi / 180) * cos(to.lat * .pi / 180) * cos((to.lon - from.lon) * .pi / 180)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func metersPhrase(_ value: Double, asHeading: Bool = false) -> String {
        if asHeading {
            return String(format: "%.0f degrees", value)
        }
        return BlackoutTokens.Distance.spoken(value)
    }
}

/// One short line of Speak status for the MAP field. The turn-by-turn script belongs to
/// the voice and the silver route line — never to a paragraph painted over the canvas.
public enum SpeakStatus: Sendable {
    public static let prefix = "SPEAK"
    public static let separator = " · "
    public static let failed = "SPEECH FAILED"
    public static let offGraph = GraphPlan.offGraph
    public static let setDest = "SET DEST"
    public static let ellipsis = "…"
    /// Wide enough for `SPEAK · 999 TURNS · 99999 FT`, narrow enough that no phone has to
    /// wrap it. Anything longer is a text wall, not status.
    public static let maxCharacters = 32

    public static func chrome(
        spoke: Bool,
        routeCoords: [(lat: Double, lon: Double)],
        planChrome: String,
        destination: (lat: Double, lon: Double)?,
        you: (lat: Double, lon: Double)?
    ) -> String {
        guard spoke else { return failed }
        if routeCoords.count >= 2 {
            let meters = zip(routeCoords, routeCoords.dropFirst()).reduce(0.0) { acc, pair in
                acc + GraphRouter.haversine(pair.0.lat, pair.0.lon, pair.1.lat, pair.1.lon)
            }
            return line([turnsPhrase(routeCoords), metersPhrase(meters)])
        }
        if planChrome == offGraph {
            return line([offGraph])
        }
        if let destination, let you {
            let span = GraphRouter.haversine(you.lat, you.lon, destination.lat, destination.lon)
            return line(["DEST", metersPhrase(span)])
        }
        return line([setDest])
    }

    public static func turns(_ coords: [(lat: Double, lon: Double)]) -> Int {
        VoiceNav.steps(coords).filter { $0.hasPrefix("Turn") }.count
    }

    /// True when a status line lost characters — the tip-67 `INSTRUME…` failure mode.
    public static func isClipped(_ text: String) -> Bool {
        text.contains(ellipsis) || text.contains("...")
    }

    private static func line(_ parts: [String]) -> String {
        ([prefix] + parts).joined(separator: separator)
    }

    private static func turnsPhrase(_ coords: [(lat: Double, lon: Double)]) -> String {
        let count = turns(coords)
        return count == 1 ? "1 TURN" : "\(count) TURNS"
    }

    private static func metersPhrase(_ meters: Double) -> String {
        BlackoutTokens.Distance.hud(meters)
    }
}
