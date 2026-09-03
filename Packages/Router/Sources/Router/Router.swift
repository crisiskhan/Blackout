import Foundation

public enum TravelMode: String, Sendable { case walk, drive }

public struct GraphNode: Codable, Sendable { public var id: Int; public var lon: Double; public var lat: Double }
public struct GraphEdge: Codable, Sendable {
    public var a: Int; public var b: Int; public var m: Double; public var walk: Bool; public var drive: Bool
}
public struct RouteGraph: Codable, Sendable {
    public var nodes: [String: GraphNode]
    public var edges: [GraphEdge]
}

public struct RouteResult: Equatable, Sendable {
    public var nodeIds: [Int]
    public var meters: Double
    public var mode: TravelMode
    public var fallback: RouteFallback
}

public enum RouteFallback: String, Equatable, Sendable { case onGraph, bearingOffGraph }

public enum GraphRouter {
    public static func route(graph: RouteGraph, from: Int, to: Int, mode: TravelMode, avoid: Set<Int> = []) -> RouteResult? {
        var adj: [Int: [(Int, Double)]] = [:]
        for e in graph.edges {
            let ok = (mode == .walk && e.walk) || (mode == .drive && e.drive)
            if ok { adj[e.a, default: []].append((e.b, e.m)) }
        }
        var dist: [Int: Double] = [from: 0]
        var prev: [Int: Int] = [:]
        var q: [Int] = [from]
        var seen: Set<Int> = []
        while let u = q.min(by: { (dist[$0] ?? .infinity) < (dist[$1] ?? .infinity) }) {
            q.removeAll { $0 == u }
            if seen.contains(u) { continue }
            seen.insert(u)
            if u == to { break }
            for (v, w) in adj[u] ?? [] {
                if avoid.contains(v) { continue }
                let alt = (dist[u] ?? .infinity) + w
                if alt < (dist[v] ?? .infinity) {
                    dist[v] = alt
                    prev[v] = u
                    q.append(v)
                }
            }
        }
        guard dist[to] != nil else { return nil }
        var path = [to]
        var cur = to
        while let p = prev[cur] {
            path.append(p)
            cur = p
        }
        path.reverse()
        return RouteResult(nodeIds: path, meters: dist[to] ?? 0, mode: mode, fallback: .onGraph)
    }

    public static func bearingFallback(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> RouteResult {
        let m = haversine(fromLat, fromLon, toLat, toLon)
        return RouteResult(nodeIds: [], meters: m, mode: .walk, fallback: .bearingOffGraph)
    }

    public static func haversine(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let r = 6371000.0
        let p1 = a * .pi / 180, p2 = c * .pi / 180
        let dp = (c - a) * .pi / 180, dl = (d - b) * .pi / 180
        let x = sin(dp/2)*sin(dp/2) + cos(p1)*cos(p2)*sin(dl/2)*sin(dl/2)
        return 2 * r * asin(min(1, sqrt(x)))
    }
}
