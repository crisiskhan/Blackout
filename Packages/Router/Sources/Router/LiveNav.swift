import Foundation

/// Live remaining-distance and turn cues while a WALK or DRIVE line is plotted.
/// The full script still belongs to SPEAK. This only names the next move as YOU move.
public enum LiveNav: Sendable {
    public static let arriveMeters: Double = 25
    public static let turnCueMeters: Double = 50
    public static let offRouteMeters: Double = 80
    public static let replanSeconds: TimeInterval = 15

    public struct Cue: Sendable {
        public var remainingMeters: Double
        public var remainingCoords: [(lat: Double, lon: Double)]
        public var nearestIndex: Int
        public var metersToLine: Double
        public var metersToTurn: Double
        public var arrived: Bool
        public var offRoute: Bool
        public var speakTurn: String
        public var nextHUD: String
    }

    public static func progress(
        you: (lat: Double, lon: Double),
        dest: (lat: Double, lon: Double)?,
        coords: [(lat: Double, lon: Double)],
        streets: [String?] = [],
        travelMode: TravelMode = .walk
    ) -> Cue {
        let destPt = dest ?? coords.last ?? you
        guard coords.count >= 2 else {
            let span = GraphRouter.haversine(you.lat, you.lon, destPt.lat, destPt.lon)
            return Cue(
                remainingMeters: 0,
                remainingCoords: coords,
                nearestIndex: 0,
                metersToLine: 0,
                metersToTurn: 0,
                arrived: span < arriveMeters,
                offRoute: false,
                speakTurn: "",
                nextHUD: ""
            )
        }
        var bestDistance = Double.greatestFiniteMagnitude
        var bestIndex = 0
        var bestPoint = coords[0]
        for i in 0..<(coords.count - 1) {
            let point = project(you, onto: coords[i], coords[i + 1])
            let distance = GraphRouter.haversine(you.lat, you.lon, point.lat, point.lon)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i
                bestPoint = point
            }
        }
        var remaining = [bestPoint] + Array(coords.dropFirst(bestIndex + 1))
        var sliced = Array(streets.dropFirst(bestIndex))
        if remaining.count >= 2 {
            let firstLeg = GraphRouter.haversine(
                remaining[0].lat,
                remaining[0].lon,
                remaining[1].lat,
                remaining[1].lon
            )
            let turnHere = isTurn(coords, at: bestIndex + 1)
            if firstLeg < 1, !turnHere {
                remaining.removeFirst()
                if !sliced.isEmpty {
                    sliced.removeFirst()
                }
            }
        }
        let remainingMeters = meters(remaining)
        let toDest = GraphRouter.haversine(you.lat, you.lon, destPt.lat, destPt.lon)
        let onLine = bestDistance <= offRouteMeters
        let arrived = toDest < arriveMeters || (onLine && remainingMeters < arriveMeters)
        let offRoute = !arrived && bestDistance > offRouteMeters
        var metersToTurn = remainingMeters
        if remaining.count >= 3 {
            for i in 1..<(remaining.count - 1) where isTurn(remaining, at: i) {
                metersToTurn = meters(Array(remaining.prefix(i + 1)))
                break
            }
        }
        var speakTurn = ""
        if !arrived, !offRoute, metersToTurn <= turnCueMeters {
            speakTurn = VoiceNav.steps(remaining, travelMode: travelMode, streets: sliced)
                .first { $0.hasPrefix("Turn") } ?? ""
        }
        return Cue(
            remainingMeters: remainingMeters,
            remainingCoords: remaining,
            nearestIndex: bestIndex,
            metersToLine: bestDistance,
            metersToTurn: metersToTurn,
            arrived: arrived,
            offRoute: offRoute,
            speakTurn: speakTurn,
            nextHUD: VoiceNav.nextTurnHUD(remaining, streets: sliced)
        )
    }

    private static func project(
        _ point: (lat: Double, lon: Double),
        onto a: (lat: Double, lon: Double),
        _ b: (lat: Double, lon: Double)
    ) -> (lat: Double, lon: Double) {
        let dx = b.lat - a.lat
        let dy = b.lon - a.lon
        let length2 = dx * dx + dy * dy
        if length2 < 1e-18 { return a }
        let t = max(0, min(1, ((point.lat - a.lat) * dx + (point.lon - a.lon) * dy) / length2))
        return (a.lat + t * dx, a.lon + t * dy)
    }

    private static func isTurn(
        _ coords: [(lat: Double, lon: Double)],
        at index: Int
    ) -> Bool {
        guard index > 0, index < coords.count - 1 else { return false }
        let from = VoiceNav.bearing(from: coords[index - 1], to: coords[index])
        let to = VoiceNav.bearing(from: coords[index], to: coords[index + 1])
        switch VoiceNav.turn(from: from, to: to) {
        case .straight:
            return false
        case .left, .right, .uturn:
            return true
        }
    }

    private static func meters(_ coords: [(lat: Double, lon: Double)]) -> Double {
        zip(coords, coords.dropFirst()).reduce(0.0) { acc, pair in
            acc + GraphRouter.haversine(pair.0.lat, pair.0.lon, pair.1.lat, pair.1.lon)
        }
    }
}
