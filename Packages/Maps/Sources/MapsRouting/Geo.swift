import Foundation

enum Geo {
    static let earthMeters = 6_371_000.0

    static func haversine(_ a: RoutingCoordinate, _ b: RoutingCoordinate) -> Double {
        let φ1 = a.latitude * .pi / 180
        let φ2 = b.latitude * .pi / 180
        let Δφ = (b.latitude - a.latitude) * .pi / 180
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let s = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * earthMeters * atan2(sqrt(s), sqrt(1 - s))
    }

    static func bearing(_ a: RoutingCoordinate, _ b: RoutingCoordinate) -> Double {
        let φ1 = a.latitude * .pi / 180
        let φ2 = b.latitude * .pi / 180
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let θ = atan2(y, x)
        return (θ * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func turnDelta(incoming: Double, outgoing: Double) -> Double {
        var d = outgoing - incoming
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    static func closestDistance(point: RoutingCoordinate, polyline: [RoutingCoordinate]) -> Double {
        guard !polyline.isEmpty else { return .greatestFiniteMagnitude }
        if polyline.count == 1 { return haversine(point, polyline[0]) }
        var best = Double.greatestFiniteMagnitude
        for i in 0..<(polyline.count - 1) {
            best = min(best, distanceToSegment(point: point, a: polyline[i], b: polyline[i + 1]))
        }
        return best
    }

    static func remainingMeters(from point: RoutingCoordinate, along polyline: [RoutingCoordinate]) -> Double {
        guard polyline.count >= 2 else { return 0 }
        var bestI = 0
        var bestT = 0.0
        var bestD = Double.greatestFiniteMagnitude
        for i in 0..<(polyline.count - 1) {
            let proj = project(point: point, a: polyline[i], b: polyline[i + 1])
            if proj.distance < bestD {
                bestD = proj.distance
                bestI = i
                bestT = proj.t
            }
        }
        var meters = (1 - bestT) * haversine(polyline[bestI], polyline[bestI + 1])
        if bestI + 1 < polyline.count - 1 {
            for i in (bestI + 1)..<(polyline.count - 1) {
                meters += haversine(polyline[i], polyline[i + 1])
            }
        }
        return meters
    }

    private static func distanceToSegment(point: RoutingCoordinate, a: RoutingCoordinate, b: RoutingCoordinate) -> Double {
        project(point: point, a: a, b: b).distance
    }

    private static func project(
        point: RoutingCoordinate,
        a: RoutingCoordinate,
        b: RoutingCoordinate
    ) -> (t: Double, distance: Double) {
        let ax = a.longitude
        let ay = a.latitude
        let bx = b.longitude
        let by = b.latitude
        let dx = bx - ax
        let dy = by - ay
        let len2 = dx * dx + dy * dy
        let t: Double
        if len2 < 1e-18 {
            t = 0
        } else {
            t = min(1, max(0, ((point.longitude - ax) * dx + (point.latitude - ay) * dy) / len2))
        }
        let proj = RoutingCoordinate(latitude: ay + t * dy, longitude: ax + t * dx)
        return (t, haversine(point, proj))
    }
}
