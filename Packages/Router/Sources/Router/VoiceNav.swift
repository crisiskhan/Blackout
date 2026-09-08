import Foundation

public enum VoiceTurn: String, Equatable, Sendable {
    case straight
    case left
    case right
    case uturn
}

public enum VoiceNav: Sendable {
    public static let arrive = "Arrive at destination."
    public static let offGraphPath = "No walkable street path from YOU."
    public static let startHint = "Set a destination, then WALK, then SPEAK for turn by turn."
    public static let destHint = "Tap WALK for the street path, then SPEAK."
    public static let minLegMeters: Double = 8
    public static let straightDeg: Double = 35
    public static let uturnDeg: Double = 135

    public static func prompt(
        packName: String,
        headingDeg: Double?,
        routeCoords: [(lat: Double, lon: Double)],
        planChrome: String,
        destination: (lat: Double, lon: Double)?,
        you: (lat: Double, lon: Double)?,
        locale: String
    ) -> String {
        _ = locale
        let headingBit: String
        if let headingDeg {
            headingBit = "Heading \(metersPhrase(headingDeg, asHeading: true))."
        } else {
            headingBit = "Heading unavailable."
        }
        if routeCoords.count >= 2 {
            let total = zip(routeCoords, routeCoords.dropFirst()).reduce(0.0) { acc, pair in
                acc + GraphRouter.haversine(pair.0.lat, pair.0.lon, pair.1.lat, pair.1.lon)
            }
            let body = steps(routeCoords).joined(separator: " ")
            return "\(body) Total \(metersPhrase(total)). \(headingBit)"
        }
        if planChrome == GraphPlan.offGraph {
            return "OFF GRAPH. \(offGraphPath) \(packName). \(headingBit)"
        }
        if let destination, let you {
            let span = GraphRouter.haversine(you.lat, you.lon, destination.lat, destination.lon)
            return "Destination set. \(metersPhrase(span)). \(packName). \(headingBit) \(destHint)"
        }
        return "\(packName). \(headingBit) \(startHint)"
    }

    public static func steps(_ coords: [(lat: Double, lon: Double)]) -> [String] {
        guard coords.count >= 2 else { return [] }
        var lines: [String] = []
        var acc = 0.0
        var prevBearing: Double?
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
                    lines.append("Walk \(metersPhrase(acc)).")
                }
                switch kind {
                case .left:
                    lines.append("Turn left.")
                case .right:
                    lines.append("Turn right.")
                case .uturn:
                    lines.append("Turn around.")
                case .straight:
                    break
                }
                acc = m
                prevBearing = brg
            }
        }
        if acc >= minLegMeters {
            lines.append("Walk \(metersPhrase(acc)).")
        }
        lines.append(arrive)
        return lines
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
        return String(format: "%.0f meters", value.rounded())
    }
}

/// Lays a spoken VoiceNav prompt out as banner rows. One sentence per row, wrapped on
/// spaces, so the MAP banner never has to tail-truncate a word the way `INSTRUME…` did.
public enum SpeakBanner: Sendable {
    public static let maxLineCharacters = 46
    public static let ellipsis = "…"

    public static func lines(_ text: String, maxCharacters: Int = maxLineCharacters) -> [String] {
        sentences(text).flatMap { wrapped($0, maxCharacters: maxCharacters) }
    }

    public static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            guard character == "." || character == "!" || character == "?" else { continue }
            let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { out.append(piece) }
            current = ""
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out
    }

    /// Breaks only on spaces. A word longer than the row keeps its own row whole rather
    /// than losing its tail.
    public static func wrapped(_ sentence: String, maxCharacters: Int = maxLineCharacters) -> [String] {
        let limit = max(1, maxCharacters)
        let words = sentence.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var rows: [String] = []
        var row = ""
        for word in words {
            if row.isEmpty {
                row = word
            } else if row.count + 1 + word.count <= limit {
                row += " " + word
            } else {
                rows.append(row)
                row = word
            }
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    /// True when a banner row lost characters — the tip-67 `INSTRUME…` failure mode.
    public static func isClipped(_ text: String) -> Bool {
        text.contains(ellipsis) || text.contains("...")
    }
}
