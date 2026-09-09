import Foundation

public enum TravelMode: String, Sendable { case walk, drive }

/// A node as callers describe one when building a graph by hand. Storage keeps
/// nothing of this shape — see `RouteGraph`.
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

/// One directed link, likewise a description rather than how it is held.
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

/// Adjacency and a lookup grid, both as flat arrays indexed by node.
///
/// This used to be four dictionaries whose values were per-node arrays, which
/// meant one heap allocation for every node in the pack — around 700,000 of
/// them for NM — and a hash on every step of every search. Node ids coming off
/// the wire are already dense, so none of that bought anything.
///
/// Links are held once in source order (the compressed-sparse-row layout):
/// `span(of:)` gives the slice of `target`/`metres`/`mode` belonging to a node.
/// Both travel modes share one set of links with a bit each, because nearly
/// every street is walkable and drivable and storing them apart duplicated the
/// larger half of the structure.
public struct GraphIndex: Sendable {
    static let walkBit: UInt8 = 1
    static let driveBit: UInt8 = 2

    static let cellDegrees = 0.02
    private static let cellStride: Int64 = 100_000

    /// `offset[n] ..< offset[n + 1]` are node n's links. Count is nodes + 1.
    let offset: [Int32]
    let target: [Int32]
    let metres: [Double]
    let mode: [UInt8]

    /// Node ids grouped by grid cell, and where each cell's group sits.
    let cellNode: [Int32]
    let cellSpan: [Int64: Range<Int>]

    init(nodeCount: Int, edges: [GraphEdge], lat: [Double], lon: [Double]) {
        // Both passes below have to agree on which edges count, or the second
        // leaves unfilled slots that read as links to node zero. A link to a
        // slot no node was placed in is dropped here rather than left to turn
        // the search's distance estimate into NaN later.
        func usable(_ e: GraphEdge) -> Bool {
            e.a >= 0 && e.a < nodeCount && e.b >= 0 && e.b < nodeCount
                && !lat[e.a].isNaN && !lat[e.b].isNaN
        }
        var counts = [Int32](repeating: 0, count: nodeCount + 1)
        for e in edges where usable(e) {
            counts[e.a] += 1
        }
        var offset = [Int32](repeating: 0, count: nodeCount + 1)
        var running: Int32 = 0
        for n in 0..<nodeCount {
            offset[n] = running
            running += counts[n]
        }
        offset[nodeCount] = running

        let total = Int(running)
        var target = [Int32](repeating: 0, count: total)
        var metres = [Double](repeating: 0, count: total)
        var mode = [UInt8](repeating: 0, count: total)
        var cursor = offset
        for e in edges where usable(e) {
            let slot = Int(cursor[e.a])
            cursor[e.a] += 1
            target[slot] = Int32(e.b)
            metres[slot] = e.m
            mode[slot] = (e.walk ? Self.walkBit : 0) | (e.drive ? Self.driveBit : 0)
        }
        self.offset = offset
        self.target = target
        self.metres = metres
        self.mode = mode

        var keyed = [(key: Int64, node: Int32)]()
        keyed.reserveCapacity(nodeCount)
        for n in 0..<nodeCount where !lat[n].isNaN {
            keyed.append((Self.cell(lat: lat[n], lon: lon[n]), Int32(n)))
        }
        keyed.sort { $0.key < $1.key }
        var cellNode = [Int32](repeating: 0, count: keyed.count)
        var cellSpan: [Int64: Range<Int>] = [:]
        var start = 0
        for i in 0..<keyed.count {
            cellNode[i] = keyed[i].node
            let last = i == keyed.count - 1
            if last || keyed[i].key != keyed[i + 1].key {
                cellSpan[keyed[i].key] = start..<(i + 1)
                start = i + 1
            }
        }
        self.cellNode = cellNode
        self.cellSpan = cellSpan
    }

    static func cell(lat: Double, lon: Double) -> Int64 {
        cell(y: Int64((lat / cellDegrees).rounded(.down)), x: Int64((lon / cellDegrees).rounded(.down)))
    }

    static func cell(y: Int64, x: Int64) -> Int64 { y &* cellStride &+ x }

    static func bit(_ mode: TravelMode) -> UInt8 {
        switch mode {
        case .walk: return walkBit
        case .drive: return driveBit
        }
    }

    func span(of node: Int) -> Range<Int> {
        guard node >= 0, node + 1 < offset.count else { return 0..<0 }
        return Int(offset[node])..<Int(offset[node + 1])
    }

    /// Where a node's links go, for the one mode. Builds an array, so it is for
    /// tests and callers who want to look — searches read the storage directly.
    public func neighbours(of node: Int, mode travel: TravelMode) -> [(to: Int, metres: Double)] {
        let want = Self.bit(travel)
        return span(of: node).compactMap { i -> (to: Int, metres: Double)? in
            guard mode[i] & want != 0 else { return nil }
            return (to: Int(target[i]), metres: metres[i])
        }
    }

    /// Whether the graph can be travelled this way at all.
    public func hasAnyLink(_ travel: TravelMode) -> Bool {
        let want = Self.bit(travel)
        return mode.contains { $0 & want != 0 }
    }
}

/// A pack's street network, held the way the wire format already describes it:
/// parallel `lat`/`lon` arrays addressed by a dense node id, plus the links.
public struct RouteGraph: Sendable {
    public let lat: [Double]
    public let lon: [Double]
    public let index: GraphIndex

    public var nodeCount: Int { lat.count }
    public var linkCount: Int { index.target.count }
    public var isEmpty: Bool { lat.isEmpty || index.target.isEmpty }

    public func point(_ id: Int) -> (lat: Double, lon: Double)? {
        guard id >= 0, id < lat.count, !lat[id].isNaN else { return nil }
        return (lat[id], lon[id])
    }

    /// Build from loose nodes and edges. An id is a position, so ids that skip
    /// leave unused slots rather than getting renumbered behind the caller's
    /// back — a route asked for by id has to come back under that same id.
    /// Unused slots hold NaN and are left out of the lookup grid, so nothing
    /// can snap to a node that was never placed.
    public init(nodes: [GraphNode], edges: [GraphEdge]) {
        let span = (nodes.map(\.id).max() ?? -1) + 1
        var lat = [Double](repeating: .nan, count: max(0, span))
        var lon = [Double](repeating: .nan, count: max(0, span))
        for n in nodes where n.id >= 0 {
            lat[n.id] = n.lat
            lon[n.id] = n.lon
        }
        self.init(lat: lat, lon: lon, edges: edges)
    }

    /// Straight from the wire, where ids are already positions.
    init(lat: [Double], lon: [Double], edges: [GraphEdge]) {
        self.lat = lat
        self.lon = lon
        self.index = GraphIndex(nodeCount: lat.count, edges: edges, lat: lat, lon: lon)
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
        let n = graph.nodeCount
        guard graph.point(from) != nil, let goal = graph.point(to) else { return nil }
        let index = graph.index
        let want = GraphIndex.bit(mode)
        let goalLat = goal.lat
        let goalLon = goal.lon

        // Straight line to the destination never overstates the road left to
        // run, so steering the search by it returns the same route plain
        // Dijkstra did while settling a fraction of the nodes.
        func remaining(_ node: Int) -> Double {
            haversine(graph.lat[node], graph.lon[node], goalLat, goalLon)
        }

        // Flat arrays rather than dictionaries: ids are positions, so there is
        // nothing to hash, and the search touches these on every relaxation.
        var dist = [Double](repeating: .infinity, count: n)
        var prev = [Int32](repeating: -1, count: n)
        var seen = [Bool](repeating: false, count: n)
        dist[from] = 0
        var heap = MinHeap()
        heap.push(from, remaining(from))

        while let (u, _) = heap.pop() {
            if seen[u] { continue }
            seen[u] = true
            if u == to { break }
            let du = dist[u]
            for i in index.span(of: u) {
                guard index.mode[i] & want != 0 else { continue }
                let v = Int(index.target[i])
                if avoid.contains(v) { continue }
                let alt = du + index.metres[i]
                if alt < dist[v] {
                    dist[v] = alt
                    prev[v] = Int32(u)
                    heap.push(v, alt + remaining(v))
                }
            }
        }
        guard dist[to] < .infinity else { return nil }
        var path = [to]
        var cur = to
        while prev[cur] >= 0 {
            cur = Int(prev[cur])
            path.append(cur)
        }
        path.reverse()
        return RouteResult(nodeIds: path, meters: dist[to], mode: mode, fallback: .onGraph)
    }

    /// Nearest node by way of the grid, so snapping a tap to the street network
    /// reads the cells around it rather than every node in the pack.
    public static func nearestNode(graph: RouteGraph, lat: Double, lon: Double) -> Int? {
        let index = graph.index
        if graph.nodeCount == 0 { return nil }
        let cy = Int64((lat / GraphIndex.cellDegrees).rounded(.down))
        let cx = Int64((lon / GraphIndex.cellDegrees).rounded(.down))
        // Shortest a degree gets at this latitude, so the ring bound below can
        // never claim more coverage than it has.
        let metresPerDegree = min(110_540.0, 111_320.0 * cos(lat * .pi / 180))
        var best: (id: Int, metres: Double)?
        func scan(_ y: Int64, _ x: Int64) {
            guard let span = index.cellSpan[GraphIndex.cell(y: y, x: x)] else { return }
            for slot in span {
                let id = Int(index.cellNode[slot])
                let d = haversine(lat, lon, graph.lat[id], graph.lon[id])
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
        nodeIds.compactMap { graph.point($0) }
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
        guard let graph, !graph.isEmpty,
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
        // Ids are already positions here, so skip the renumbering pass.
        return RouteGraph(lat: lat, lon: lon, edges: edges)
    }
}

/// The shape graphs shipped in before the packed wire format. Kept so an old
/// pack on a phone still routes; nothing generates it now.
private struct LooseGraph: Decodable {
    var nodes: [String: GraphNode]
    var edges: [GraphEdge]
}

extension RouteGraph {
    public static func load(from url: URL?) -> RouteGraph? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        var g: RouteGraph?
        if let packed = try? decoder.decode(PackedGraph.self, from: data) {
            g = packed.unpacked()
        } else if let loose = try? decoder.decode(LooseGraph.self, from: data) {
            // Ids are positions, so a file claiming id 10^9 for three nodes is
            // corrupt rather than sparse, and would ask for gigabytes.
            let ids = loose.nodes.values.map(\.id)
            guard let top = ids.max(), top >= 0, top < max(4096, ids.count * 8) else { return nil }
            g = RouteGraph(nodes: Array(loose.nodes.values), edges: loose.edges)
        }
        guard let g, !g.isEmpty else { return nil }
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
