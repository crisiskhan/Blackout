import Foundation

public enum TravelMode: String, Sendable { case walk, drive }

public struct GraphNode: Codable, Sendable {
    public var id: Int
    public var lon: Double
    public var lat: Double
    public init(id: Int, lon: Double, lat: Double) {
        self.id = id
        self.lon = lon
        self.lat = lat
    }
}
public struct GraphEdge: Codable, Sendable {
    public var a: Int
    public var b: Int
    public var m: Double
    public var walk: Bool
    public var drive: Bool
    public init(a: Int, b: Int, m: Double, walk: Bool, drive: Bool) {
        self.a = a
        self.b = b
        self.m = m
        self.walk = walk
        self.drive = drive
    }
}
public struct RouteGraph: Codable, Sendable {
    public var nodes: [String: GraphNode]
    public var edges: [GraphEdge]
    public init(nodes: [String: GraphNode], edges: [GraphEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
}

public struct RouteResult: Equatable, Sendable {
    public var nodeIds: [Int]
    public var meters: Double
    public var mode: TravelMode
    public var fallback: RouteFallback

    public init(nodeIds: [Int], meters: Double, mode: TravelMode, fallback: RouteFallback) {
        self.nodeIds = nodeIds
        self.meters = meters
        self.mode = mode
        self.fallback = fallback
    }
}

public enum RouteFallback: String, Equatable, Sendable { case onGraph, bearingOffGraph }

public enum GraphRouter {
    public static func route(graph: RouteGraph, from: Int, to: Int, mode: TravelMode, avoid: Set<Int> = []) -> RouteResult? {
        var adj: [Int: [(Int, Double)]] = [:]
        for e in graph.edges {
            let ok: Bool
            switch mode {
            case .walk: ok = e.walk
            case .drive: ok = e.drive
            }
            if ok { adj[e.a, default: []].append((e.b, e.m)) }
        }
        var dist: [Int: Double] = [from: 0]
        var prev: [Int: Int] = [:]
        var heap = MinHeap()
        heap.push(from, 0)
        var seen: Set<Int> = []
        while let (u, du) = heap.pop() {
            if du > (dist[u] ?? .infinity) { continue }
            if seen.contains(u) { continue }
            seen.insert(u)
            if u == to { break }
            for (v, w) in adj[u] ?? [] {
                if avoid.contains(v) { continue }
                let alt = (dist[u] ?? .infinity) + w
                if alt < (dist[v] ?? .infinity) {
                    dist[v] = alt
                    prev[v] = u
                    heap.push(v, alt)
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

    public static func nearestNode(graph: RouteGraph, lat: Double, lon: Double) -> Int? {
        var best: (Int, Double)?
        for n in graph.nodes.values {
            let d = haversine(lat, lon, n.lat, n.lon)
            if best == nil || d < best!.1 {
                best = (n.id, d)
            }
        }
        return best?.0
    }

    public static func coordinates(graph: RouteGraph, nodeIds: [Int]) -> [(lat: Double, lon: Double)] {
        nodeIds.compactMap { id in
            graph.nodes[String(id)].map { (lat: $0.lat, lon: $0.lon) }
        }
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

public enum GraphPlan {
    public static let offGraph = "OFF GRAPH"

    public static func line(
        graph: RouteGraph?,
        from: (lat: Double, lon: Double),
        to: (lat: Double, lon: Double),
        mode: TravelMode
    ) -> (coords: [(lat: Double, lon: Double)], chrome: String) {
        guard let graph, !graph.edges.isEmpty, !graph.nodes.isEmpty,
              let a = GraphRouter.nearestNode(graph: graph, lat: from.lat, lon: from.lon),
              let b = GraphRouter.nearestNode(graph: graph, lat: to.lat, lon: to.lon),
              let r = GraphRouter.route(graph: graph, from: a, to: b, mode: mode),
              r.fallback == .onGraph
        else {
            return ([], offGraph)
        }
        let coords = GraphRouter.coordinates(graph: graph, nodeIds: r.nodeIds)
        if coords.count < 2 { return ([], offGraph) }
        return (coords, "")
    }
}

/// graph.json as the packs ship it. Nodes are dense indices into parallel
/// lat/lon arrays, and a street segment is one `a, b, metres, flags` record
/// rather than two directed edges spelling out their own permissions. The
/// flags say which way you may walk and which way you may drive, so a one-way
/// street survives the squeeze intact.
///
/// Mirrored by `pack_graph` in tools/v3/fetch_packs.py. Change one, change both.
struct PackedGraph: Decodable {
    static let wireVersion = 2
    static let walkForward = 1
    static let driveForward = 2
    static let walkBack = 4
    static let driveBack = 8
    /// a, b, metres, flags.
    static let stride = 4

    var version: Int
    var lat: [Double]
    var lon: [Double]
    var segments: [Double]

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case lat
        case lon
        case segments = "e"
    }

    func unpacked() -> RouteGraph? {
        guard version == Self.wireVersion, lat.count == lon.count, !lat.isEmpty else { return nil }
        var nodes: [String: GraphNode] = [:]
        nodes.reserveCapacity(lat.count)
        for i in lat.indices {
            nodes[String(i)] = GraphNode(id: i, lon: lon[i], lat: lat[i])
        }
        var edges: [GraphEdge] = []
        edges.reserveCapacity(segments.count / 2)
        var i = 0
        while i + Self.stride <= segments.count {
            let a = Int(segments[i])
            let b = Int(segments[i + 1])
            let metres = segments[i + 2]
            let flags = Int(segments[i + 3])
            i += Self.stride
            guard a >= 0, a < lat.count, b >= 0, b < lat.count else { continue }
            let walkAB = flags & Self.walkForward != 0
            let driveAB = flags & Self.driveForward != 0
            if walkAB || driveAB {
                edges.append(GraphEdge(a: a, b: b, m: metres, walk: walkAB, drive: driveAB))
            }
            let walkBA = flags & Self.walkBack != 0
            let driveBA = flags & Self.driveBack != 0
            if walkBA || driveBA {
                edges.append(GraphEdge(a: b, b: a, m: metres, walk: walkBA, drive: driveBA))
            }
        }
        return RouteGraph(nodes: nodes, edges: edges)
    }
}

extension RouteGraph {
    public static func load(from url: URL?) -> RouteGraph? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        var g: RouteGraph?
        if let packed = try? decoder.decode(PackedGraph.self, from: data) {
            g = packed.unpacked()
        } else {
            g = try? decoder.decode(RouteGraph.self, from: data)
        }
        guard let g, !g.edges.isEmpty, !g.nodes.isEmpty else { return nil }
        return g
    }
}

private struct MinHeap {
    private var keys: [Int] = []
    private var vals: [Double] = []

    mutating func push(_ key: Int, _ val: Double) {
        keys.append(key)
        vals.append(val)
        siftUp(keys.count - 1)
    }

    mutating func pop() -> (Int, Double)? {
        guard !keys.isEmpty else { return nil }
        let k = keys[0]
        let v = vals[0]
        let lastK = keys.removeLast()
        let lastV = vals.removeLast()
        if !keys.isEmpty {
            keys[0] = lastK
            vals[0] = lastV
            siftDown(0)
        }
        return (k, v)
    }

    private mutating func siftUp(_ i: Int) {
        var i = i
        while i > 0 {
            let p = (i - 1) / 2
            if vals[i] >= vals[p] { break }
            keys.swapAt(i, p)
            vals.swapAt(i, p)
            i = p
        }
    }

    private mutating func siftDown(_ i: Int) {
        var i = i
        while true {
            let l = i * 2 + 1
            let r = l + 1
            var smallest = i
            if l < vals.count && vals[l] < vals[smallest] { smallest = l }
            if r < vals.count && vals[r] < vals[smallest] { smallest = r }
            if smallest == i { break }
            keys.swapAt(i, smallest)
            vals.swapAt(i, smallest)
            i = smallest
        }
    }
}
