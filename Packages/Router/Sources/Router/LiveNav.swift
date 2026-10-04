import Foundation

/// Live remaining-distance and turn cues while a WALK or DRIVE line is plotted.
/// The full script still belongs to SPEAK. This only names the next move as YOU move.
public enum LiveNav: Sendable {
    public static let arriveMeters: Double = 25
    public static let arriveDriveMeters: Double = 40
    public static let turnCueMeters: Double = 50
    public static let turnCueDriveMeters: Double = 160
    public static let offRouteMeters: Double = 80
    public static let offRouteWalkMeters: Double = 45
    public static let replanSeconds: TimeInterval = 8
    public static let farOffFactor: Double = 2

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

    public static func offRouteLimit(_ mode: TravelMode) -> Double {
        switch mode {
        case .walk: return offRouteWalkMeters
        case .drive: return offRouteMeters
        }
    }

    public static func turnCueLimit(_ mode: TravelMode) -> Double {
        switch mode {
        case .walk: return turnCueMeters
        case .drive: return turnCueDriveMeters
        }
    }

    public static func arriveLimit(_ mode: TravelMode) -> Double {
        switch mode {
        case .walk: return arriveMeters
        case .drive: return arriveDriveMeters
        }
    }

    public static func shouldReplan(
        now: TimeInterval,
        lastReplanAt: TimeInterval,
        metersToLine: Double,
        mode: TravelMode
    ) -> Bool {
        if lastReplanAt == 0 { return true }
        if metersToLine > offRouteLimit(mode) * farOffFactor { return true }
        return now - lastReplanAt >= replanSeconds
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
                arrived: span < arriveLimit(travelMode),
                offRoute: false,
                speakTurn: "",
                nextHUD: ""
            )
        }
        var bestDistance = Double.greatestFiniteMagnitude
        var bestIndex = 0
        var bestPoint = coords[0]
        for i in 0..<(coords.count - 1) {
            let hit = GraphRouter.projectOnSegment(
                lat: you.lat,
                lon: you.lon,
                aLat: coords[i].lat,
                aLon: coords[i].lon,
                bLat: coords[i + 1].lat,
                bLon: coords[i + 1].lon
            )
            if hit.metres < bestDistance {
                bestDistance = hit.metres
                bestIndex = i
                bestPoint = (hit.lat, hit.lon)
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
        let limit = offRouteLimit(travelMode)
        let arrive = arriveLimit(travelMode)
        let onLine = bestDistance <= limit
        let arrived = toDest < arrive || (onLine && remainingMeters < arrive)
        let offRoute = !arrived && bestDistance > limit
        var metersToTurn = remainingMeters
        if remaining.count >= 3 {
            for i in 1..<(remaining.count - 1) where isTurn(remaining, at: i) {
                metersToTurn = meters(Array(remaining.prefix(i + 1)))
                break
            }
        }
        var speakTurn = ""
        if !arrived, !offRoute {
            let spoken = VoiceNav.steps(remaining, travelMode: travelMode, streets: sliced)
            if metersToTurn <= turnCueLimit(travelMode) {
                speakTurn = spoken.first { $0.hasPrefix("Turn") } ?? ""
            }
            if speakTurn.isEmpty {
                speakTurn = spoken.first { $0.hasPrefix("Walk") || $0.hasPrefix("Drive") } ?? ""
            }
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
