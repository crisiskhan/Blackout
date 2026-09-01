import Foundation

public enum Guidance {
    public static let offRouteMeters = 40.0

    public static func tick(
        position: RoutingCoordinate,
        route: Route,
        pack: RoutingPack?,
        canReroute: Bool
    ) -> GuidanceTick {
        let remaining = Geo.remainingMeters(from: position, along: route.polyline)
        let off = Geo.closestDistance(point: position, polyline: route.polyline) > offRouteMeters
        var reroute: RouteOutcome?
        if off, canReroute {
            if let last = route.polyline.last {
                reroute = PackRouter.route(from: position, to: last, profile: route.profile, pack: pack)
            } else {
                reroute = .offGraph
            }
        }
        let next = nextManeuver(position: position, route: route)
        let toTurn: Double
        if let next {
            toTurn = Geo.haversine(position, next.coordinate)
        } else {
            toTurn = remaining
        }
        let fraction = route.distanceMeters > 0 ? min(1, remaining / route.distanceMeters) : 0
        return GuidanceTick(
            remainingMeters: remaining,
            etaSeconds: route.etaSeconds * fraction,
            nextManeuver: next,
            distanceToTurnMeters: toTurn,
            offRoute: off,
            reroute: reroute
        )
    }

    private static func nextManeuver(position: RoutingCoordinate, route: Route) -> Maneuver? {
        let upcoming = route.maneuvers.filter { $0.kind != .depart }
        guard !upcoming.isEmpty else { return nil }
        var best: Maneuver?
        var bestAhead = Double.greatestFiniteMagnitude
        for maneuver in upcoming {
            let d = Geo.haversine(position, maneuver.coordinate)
            if d < bestAhead {
                bestAhead = d
                best = maneuver
            }
        }
        return best
    }
}

public enum VoicePrompt {
    public static func phrase(for maneuver: Maneuver, distanceMeters: Double) -> String {
        let dist = distanceCopy(distanceMeters)
        let onto: String
        if let name = maneuver.streetName, !name.isEmpty {
            onto = " onto \(name)"
        } else {
            onto = ""
        }
        switch maneuver.kind {
        case .depart:
            if let name = maneuver.streetName, !name.isEmpty {
                return "Head toward \(name)"
            }
            return "Start navigation"
        case .arrive:
            return "You have arrived"
        case .left:
            return "In \(dist), turn left\(onto)"
        case .right:
            return "In \(dist), turn right\(onto)"
        case .slightLeft:
            return "In \(dist), keep left\(onto)"
        case .slightRight:
            return "In \(dist), keep right\(onto)"
        case .uTurn:
            return "In \(dist), make a U-turn"
        case .straight:
            return "In \(dist), continue straight\(onto)"
        }
    }

    public static func distanceCopy(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f kilometers", meters / 1000)
        }
        let rounded = max(10, (meters / 10).rounded() * 10)
        return "\(Int(rounded)) meters"
    }
}

public enum Formatters {
    public static func distance(_ meters: Double) -> String {
        if meters >= 1000 { return String(format: "%.1f km", meters / 1000) }
        return "\(Int(meters.rounded())) m"
    }

    public static func eta(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "<1 min"
    }
}

/// Walk TBT copy. Mock SoT: 0.4 mi / RAVEN ROCK RD. Not the idle metric scale bar.
public enum WalkChrome {
    public static func distance(_ meters: Double) -> String {
        let miles = meters / 1609.344
        if miles >= 10 { return String(format: "%.0f mi", miles.rounded()) }
        if miles >= 0.1 { return String(format: "%.1f mi", miles) }
        let feet = meters * 3.28084
        let rounded = max(10, (feet / 10).rounded() * 10)
        return "\(Int(rounded)) ft"
    }

    public static func roadName(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return "CONTINUE" }
        return trimmed.uppercased()
    }

    public static func arrowSystemName(_ kind: ManeuverKind) -> String {
        switch kind {
        case .right, .slightRight:
            return "arrow.turn.up.right"
        case .left, .slightLeft:
            return "arrow.turn.up.left"
        case .uTurn:
            return "arrow.uturn.left"
        case .straight, .depart:
            return "arrow.up"
        case .arrive:
            return "flag.checkered"
        }
    }

    public static func scaleLine(meters: Double, etaSeconds: Double) -> String {
        let eta = Formatters.eta(etaSeconds).replacingOccurrences(of: "min", with: "MIN")
        return "\(distance(meters)) / \(eta)"
    }
}

/// Return breadcrumb: GPS segments solid, estimated segments dashed.
/// A start→self line with no walked crumbs is estimated (straight-line, not GPS).
public enum WalkReturnBreadcrumb {
    public struct Node: Equatable {
        public var latitude: Double
        public var longitude: Double
        public var estimated: Bool

        public init(latitude: Double, longitude: Double, estimated: Bool) {
            self.latitude = latitude
            self.longitude = longitude
            self.estimated = estimated
        }
    }

    public struct Segment: Equatable {
        public var from: Node
        public var to: Node
        public var dashed: Bool

        public init(from: Node, to: Node, dashed: Bool) {
            self.from = from
            self.to = to
            self.dashed = dashed
        }
    }

    public static func segments(
        start: Node?,
        crumbs: [Node],
        end: Node?
    ) -> [Segment] {
        var nodes: [Node] = []
        if let start { nodes.append(start) }
        nodes.append(contentsOf: crumbs)
        if let end { nodes.append(end) }
        guard nodes.count >= 2 else { return [] }
        let onlyEstimatedReturn = crumbs.isEmpty && start != nil && end != nil
        var out: [Segment] = []
        for index in 0..<(nodes.count - 1) {
            let a = nodes[index]
            let b = nodes[index + 1]
            out.append(Segment(from: a, to: b, dashed: onlyEstimatedReturn || a.estimated || b.estimated))
        }
        return out
    }
}
