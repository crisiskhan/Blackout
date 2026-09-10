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
/// Everything routing needs that the wire format does not carry: who adjoins
/// whom per travel mode, where each node sits without a dictionary of `String`
/// keys, and a coarse grid to find the nearest node without reading them all.
///
/// Built once when a pack's graph loads, on the thread that loaded it. Deriving
/// it per tap meant every WALK re-walked half a million edges before it started
/// searching, and that cost grows with the map.
public struct GraphIndex: Sendable {
    public struct Link: Sendable {
        public let to: Int
        public let m: Double
    }

    public struct Point: Sendable {
        public let lat: Double
        public let lon: Double
    }

    static let cellDegrees = 0.02
    private static let cellStride: Int64 = 100_000

    let walk: [Int: [Link]]
    let drive: [Int: [Link]]
    let point: [Int: Point]
    let cells: [Int64: [Int]]

    init(nodes: [String: GraphNode], edges: [GraphEdge]) {
        var walk: [Int: [Link]] = [:]
        var drive: [Int: [Link]] = [:]
        walk.reserveCapacity(nodes.count)
        drive.reserveCapacity(nodes.count)
        for e in edges {
            if e.walk { walk[e.a, default: []].append(Link(to: e.b, m: e.m)) }
            if e.drive { drive[e.a, default: []].append(Link(to: e.b, m: e.m)) }
        }
        var point: [Int: Point] = [:]
        var cells: [Int64: [Int]] = [:]
        point.reserveCapacity(nodes.count)
        for n in nodes.values {
            point[n.id] = Point(lat: n.lat, lon: n.lon)
            cells[Self.cell(lat: n.lat, lon: n.lon), default: []].append(n.id)
        }
        self.walk = walk
        self.drive = drive
        self.point = point
        self.cells = cells
    }

    static func cell(lat: Double, lon: Double) -> Int64 {
        cell(y: Int64((lat / cellDegrees).rounded(.down)), x: Int64((lon / cellDegrees).rounded(.down)))
    }

    static func cell(y: Int64, x: Int64) -> Int64 { y &* cellStride &+ x }

    func links(_ mode: TravelMode) -> [Int: [Link]] {
        switch mode {
        case .walk: return walk
        case .drive: return drive
        }
    }
}

public struct RouteGraph: Codable, Sendable {
    public let nodes: [String: GraphNode]
    public let edges: [GraphEdge]
    public let index: GraphIndex

    private enum CodingKeys: String, CodingKey { case nodes, edges }

    public init(nodes: [String: GraphNode], edges: [GraphEdge]) {
        self.nodes = nodes
        self.edges = edges
        self.index = GraphIndex(nodes: nodes, edges: edges)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            nodes: try c.decode([String: GraphNode].self, forKey: .nodes),
            edges: try c.decode([GraphEdge].self, forKey: .edges)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nodes, forKey: .nodes)
        try c.encode(edges, forKey: .edges)
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
        let index = graph.index
        let adj = index.links(mode)
        let goal = index.point[to]
        // Straight line to the destination never overstates the road left to
        // run, so steering the search by it returns the same route plain
        // Dijkstra did while settling a fraction of the nodes.
        func remaining(_ n: Int) -> Double {
            guard let goal, let p = index.point[n] else { return 0 }
            return haversine(p.lat, p.lon, goal.lat, goal.lon)
        }
        var dist: [Int: Double] = [from: 0]
        var prev: [Int: Int] = [:]
        var heap = MinHeap()
        heap.push(from, remaining(from))
        var seen: Set<Int> = []
        while let (u, _) = heap.pop() {
            if seen.contains(u) { continue }
            seen.insert(u)
            if u == to { break }
            let du = dist[u] ?? .infinity
            for link in adj[u] ?? [] {
                if avoid.contains(link.to) { continue }
                let alt = du + link.m
                if alt < (dist[link.to] ?? .infinity) {
                    dist[link.to] = alt
                    prev[link.to] = u
                    heap.push(link.to, alt + remaining(link.to))
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

    /// Nearest node by way of the grid, so snapping a tap to the street network
    /// reads the cells around it rather than every node in the pack.
    public static func nearestNode(graph: RouteGraph, lat: Double, lon: Double) -> Int? {
        let index = graph.index
        if index.point.isEmpty { return nil }
        let cy = Int64((lat / GraphIndex.cellDegrees).rounded(.down))
        let cx = Int64((lon / GraphIndex.cellDegrees).rounded(.down))
        // Shortest a degree gets at this latitude, so the ring bound below can
        // never claim more coverage than it has.
        let metresPerDegree = min(110_540.0, 111_320.0 * cos(lat * .pi / 180))
        var best: (id: Int, metres: Double)?
        func scan(_ y: Int64, _ x: Int64) {
            guard let ids = index.cells[GraphIndex.cell(y: y, x: x)] else { return }
            for id in ids {
                guard let p = index.point[id] else { continue }
                let d = haversine(lat, lon, p.lat, p.lon)
                if best == nil || d < best!.metres { best = (id, d) }
            }
        }
        var ring: Int64 = 0
        while ring <= maxRing {
            // Walk the ring's edge only. Re-reading its whole square each time
            // turned a widening search into a cubic one.
            if ring == 0 {
                scan(cy, cx)
            } else {
                for dx in -ring...ring {
                    scan(cy - ring, cx + dx)
                    scan(cy + ring, cx + dx)
                }
                if ring > 1 {
                    for dy in (-ring + 1)...(ring - 1) {
                        scan(cy + dy, cx - ring)
                        scan(cy + dy, cx + ring)
                    }
                }
            }
            // Everything still unread sits at least this far out, so once the
            // best is inside that, no further ring can beat it.
            if let best, best.metres <= Double(ring) * GraphIndex.cellDegrees * metresPerDegree {
                return best.id
            }
            ring += 1
        }
        return best?.id
    }

    /// Far enough to cross any pack we ship; stops a tap in open water from
    /// sweeping the grid forever.
    private static let maxRing: Int64 = 512

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
