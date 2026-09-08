import Foundation

public enum PackRouter {
    public static func route(
        from: RoutingCoordinate,
        to: RoutingCoordinate,
        profile: NavigateProfile,
        pack: RoutingPack?
    ) -> RouteOutcome {
        guard let pack else { return .noGraph }
        guard pack.manifest.profiles.contains(profile) else { return .noGraph }
        guard pack.manifest.bbox.contains(from), pack.manifest.bbox.contains(to) else {
            return .offGraph
        }
        guard let start = pack.nearestNode(to: from, maxMeters: profile.snapMeters),
              let goal = pack.nearestNode(to: to, maxMeters: profile.snapMeters) else {
            return .offGraph
        }
        if start == goal {
            guard let dest = pack.node(at: goal)?.coordinate else { return .offGraph }
            return .routed(
                Route(
                    profile: profile,
                    distanceMeters: 0,
                    etaSeconds: 0,
                    nodeIds: [start],
                    edgeIndexes: [],
                    reversed: [],
                    polyline: [dest],
                    maneuvers: [
                        Maneuver(kind: .arrive, streetName: nil, distanceMeters: 0, coordinate: dest)
                    ]
                )
            )
        }
        guard let path = astar(start: start, goal: goal, profile: profile, pack: pack) else {
            return .offGraph
        }
        return .routed(buildRoute(path: path, profile: profile, pack: pack))
    }

    private struct Path {
        var nodes: [UInt32]
        var edges: [Int]
        var reversed: [Bool]
        var costMs: Int
    }

    private static func astar(
        start: UInt32,
        goal: UInt32,
        profile: NavigateProfile,
        pack: RoutingPack
    ) -> Path? {
        guard let goalCoord = pack.node(at: goal)?.coordinate,
              let startCoord = pack.node(at: start)?.coordinate else { return nil }
        var gScore = [UInt32: Int]()
        gScore[start] = 0
        var cameEdge = [UInt32: (from: UInt32, edge: Int, reverse: Bool)]()
        var heap = MinHeap()
        heap.push(key: heuristicMs(from: startCoord, to: goalCoord, profile: profile), id: start)

        var visited = Set<UInt32>()
        while let current = heap.pop() {
            if current == goal {
                return reconstruct(goal: goal, start: start, cameEdge: cameEdge, costMs: gScore[goal] ?? 0)
            }
            if !visited.insert(current).inserted { continue }
            let currentG = gScore[current] ?? Int.max
            let arcs = Int(current) < pack.outgoing.count ? pack.outgoing[Int(current)] : []
            for arc in arcs {
                guard let edge = pack.edge(at: arc.edgeIndex) else { continue }
                guard profile.allows(edge.flags) else { continue }
                let step = profile.costMs(edge)
                guard step >= 0 else { continue }
                let next = arc.toward
                let tentative = currentG + step
                if tentative < (gScore[next] ?? Int.max) {
                    gScore[next] = tentative
                    cameEdge[next] = (current, arc.edgeIndex, arc.reverse)
                    guard let nextCoord = pack.node(at: next)?.coordinate else { continue }
                    let f = tentative + heuristicMs(
                        from: nextCoord,
                        to: goalCoord,
                        profile: profile
                    )
                    heap.push(key: f, id: next)
                }
            }
        }
        return nil
    }

    private static func reconstruct(
        goal: UInt32,
        start: UInt32,
        cameEdge: [UInt32: (from: UInt32, edge: Int, reverse: Bool)],
        costMs: Int
    ) -> Path {
        var nodes = [goal]
        var edges: [Int] = []
        var reversed: [Bool] = []
        var cursor = goal
        while cursor != start, let step = cameEdge[cursor] {
            edges.append(step.edge)
            reversed.append(step.reverse)
            nodes.append(step.from)
            cursor = step.from
        }
        nodes.reverse()
        edges.reverse()
        reversed.reverse()
        return Path(nodes: nodes, edges: edges, reversed: reversed, costMs: costMs)
    }

    private static func buildRoute(path: Path, profile: NavigateProfile, pack: RoutingPack) -> Route {
        var polyline: [RoutingCoordinate] = []
        var lengthCm: UInt32 = 0
        for (i, edgeIndex) in path.edges.enumerated() {
            guard let edge = pack.edge(at: edgeIndex) else { continue }
            lengthCm += edge.lengthCm
            var geom = pack.geometry(edgeIndex: edgeIndex, reverse: i < path.reversed.count ? path.reversed[i] : false)
            if !polyline.isEmpty, !geom.isEmpty {
                geom.removeFirst()
            }
            polyline.append(contentsOf: geom)
        }
        if polyline.isEmpty, let last = path.nodes.last, let coord = pack.node(at: last)?.coordinate {
            polyline = [coord]
        }
        let distance = Double(lengthCm) / 100
        let eta = Double(path.costMs) / 1000
        let maneuvers = ManeuverBuilder.make(
            nodeIds: path.nodes,
            edgeIndexes: path.edges,
            reversed: path.reversed,
            pack: pack
        )
        return Route(
            profile: profile,
            distanceMeters: distance,
            etaSeconds: eta,
            nodeIds: path.nodes,
            edgeIndexes: path.edges,
            reversed: path.reversed,
            polyline: polyline,
            maneuvers: maneuvers
        )
    }

    /// Admissible: underestimate ms using a faster-than-field speed.
    private static func heuristicMs(from: RoutingCoordinate, to: RoutingCoordinate, profile: NavigateProfile) -> Int {
        let meters = Geo.haversine(from, to)
        let msPerMeter: Double
        switch profile {
        case .walk: msPerMeter = 20
        case .drive: msPerMeter = 5
        }
        return Int(meters * msPerMeter)
    }
}

struct MinHeap {
    private var keys: [Int] = []
    private var ids: [UInt32] = []

    mutating func push(key: Int, id: UInt32) {
        keys.append(key)
        ids.append(id)
        siftUp(keys.count - 1)
    }

    mutating func pop() -> UInt32? {
        guard !ids.isEmpty else { return nil }
        let first = ids[0]
        let last = ids.count - 1
        if last > 0 {
            keys[0] = keys[last]
            ids[0] = ids[last]
        }
        keys.removeLast()
        ids.removeLast()
        if !ids.isEmpty { siftDown(0) }
        return first
    }

    private mutating func siftUp(_ index: Int) {
        var i = index
        while i > 0 {
            let p = (i - 1) / 2
            if keys[i] < keys[p] {
                keys.swapAt(i, p)
                ids.swapAt(i, p)
                i = p
            } else {
                break
            }
        }
    }

    private mutating func siftDown(_ index: Int) {
        var i = index
        while true {
            let l = i * 2 + 1
            let r = l + 1
            var smallest = i
            if l < keys.count, keys[l] < keys[smallest] { smallest = l }
            if r < keys.count, keys[r] < keys[smallest] { smallest = r }
            if smallest == i { break }
            keys.swapAt(i, smallest)
            ids.swapAt(i, smallest)
            i = smallest
        }
    }
}
