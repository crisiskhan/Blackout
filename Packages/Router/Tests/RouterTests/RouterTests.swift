import XCTest
@testable import Router

final class RouterTests: XCTestCase {
    func testOnGraphAndBearing() {
        let g = RouteGraph(
            nodes: [.init(id: 1, lon: 0, lat: 0), .init(id: 2, lon: 0.01, lat: 0)],
            edges: [.init(a: 1, b: 2, m: 100, walk: true, drive: true)]
        )
        let r = GraphRouter.route(graph: g, from: 1, to: 2, mode: .walk)!
        XCTAssertEqual(r.fallback, .onGraph)
        XCTAssertEqual(r.nodeIds, [1, 2])
        let b = GraphRouter.bearingFallback(fromLat: 0, fromLon: 0, toLat: 0, toLon: 1)
        XCTAssertEqual(b.fallback, .bearingOffGraph)
        XCTAssertGreaterThan(b.meters, 1000)
    }

    func testWalkFindsTwoHopPathAndDriveIgnoresWalkOnlyEdges() {
        let g = twoHopWalkOnly()
        let walk = GraphRouter.route(graph: g, from: 1, to: 3, mode: .walk)
        XCTAssertEqual(walk?.fallback, .onGraph)
        XCTAssertEqual(walk?.nodeIds, [1, 2, 3])
        XCTAssertEqual(walk?.meters, 200)
        XCTAssertNil(GraphRouter.route(graph: g, from: 1, to: 3, mode: .drive))
        XCTAssertNil(GraphRouter.route(graph: g, from: 1, to: 99, mode: .walk))
    }

    func testNearestNodeAndCoordinatesFollowGraphIds() {
        let g = twoHopWalkOnly()
        XCTAssertEqual(GraphRouter.nearestNode(graph: g, lat: 0, lon: 0.009), 2)
        XCTAssertEqual(GraphRouter.nearestNode(graph: g, lat: 0, lon: 0.021), 3)
        let coords = GraphRouter.coordinates(graph: g, nodeIds: [1, 2, 3])
        XCTAssertEqual(coords.map(\.lon), [0, 0.01, 0.02])
        XCTAssertEqual(coords.map(\.lat), [0, 0, 0])
        XCTAssertNil(GraphRouter.nearestNode(graph: RouteGraph(nodes: [], edges: []), lat: 0, lon: 0))
    }

    /// Weights are the true distance between the points. That is the only shape
    /// in which the search's straight-line estimate stays under the road left to
    /// run, and so the only shape in which it still returns the shortest route.
    private func measuredGraph(
        _ points: [Int: (lat: Double, lon: Double)],
        _ links: [(Int, Int)]
    ) -> RouteGraph {
        let nodes = points.map { GraphNode(id: $0.key, lon: $0.value.lon, lat: $0.value.lat) }
        var edges: [GraphEdge] = []
        for (a, b) in links {
            let m = GraphRouter.haversine(points[a]!.lat, points[a]!.lon, points[b]!.lat, points[b]!.lon)
            edges.append(GraphEdge(a: a, b: b, m: m, walk: true, drive: true))
            edges.append(GraphEdge(a: b, b: a, m: m, walk: true, drive: true))
        }
        return RouteGraph(nodes: nodes, edges: edges)
    }

    func testRouteTakesTheShorterWayNotTheOnePointingAtTheDestination() {
        // Both ways reach node 4. Going through 2 bulges much further north, so
        // steering by the straight line must not be what picks the route.
        let g = measuredGraph(
            [1: (0, 0), 2: (0.010, 0.010), 3: (0.001, 0.010), 4: (0, 0.020)],
            [(1, 2), (2, 4), (1, 3), (3, 4)]
        )
        let r = GraphRouter.route(graph: g, from: 1, to: 4, mode: .walk)
        XCTAssertEqual(r?.nodeIds, [1, 3, 4])
        let long = GraphRouter.route(graph: g, from: 1, to: 4, mode: .walk, avoid: [3])
        XCTAssertEqual(long?.nodeIds, [1, 2, 4])
        XCTAssertGreaterThan(long!.meters, r!.meters)
    }

    func testRouteWalksAwayFromTheDestinationWhenThatIsTheOnlyWay() {
        // 3 and 4 do not touch. The only path leaves the direct line entirely.
        let g = measuredGraph(
            [1: (0, 0), 2: (0, 0.01), 3: (0, 0.02), 4: (0, 0.04), 5: (0.03, 0.03)],
            [(1, 2), (2, 3), (3, 5), (5, 4)]
        )
        XCTAssertEqual(GraphRouter.route(graph: g, from: 1, to: 4, mode: .walk)?.nodeIds, [1, 2, 3, 5, 4])
    }

    func testNearestNodeWidensUntilItCanBeatEveryCellItHasNotRead() {
        // Spread wider than one grid cell so the search has to expand, and probe
        // from a point outside every cell holding a node.
        let nodes = (0..<40).map {
            GraphNode(id: $0 + 1, lon: -106.0 - Double($0) * 0.05, lat: 31.0 + Double($0) * 0.03)
        }
        let g = RouteGraph(nodes: nodes, edges: [])
        XCTAssertEqual(GraphRouter.nearestNode(graph: g, lat: 31.0, lon: -106.0), 1)
        XCTAssertEqual(GraphRouter.nearestNode(graph: g, lat: 32.17, lon: -107.95), 40)
        for probe in [(lat: 30.0, lon: -104.0), (lat: 31.5, lon: -106.9), (lat: 35.0, lon: -110.0)] {
            var best = (id: -1, metres: Double.infinity)
            for id in 0..<g.nodeCount {
                guard let p = g.point(id) else { continue }
                let d = GraphRouter.haversine(probe.lat, probe.lon, p.lat, p.lon)
                if d < best.metres { best = (id, d) }
            }
            XCTAssertEqual(GraphRouter.nearestNode(graph: g, lat: probe.lat, lon: probe.lon), best.id)
        }
    }

    func testIndexKeepsTheTwoModesApart() {
        let g = twoHopWalkOnly()
        XCTAssertTrue(g.index.hasAnyLink(.walk))
        XCTAssertFalse(g.index.hasAnyLink(.drive))
        XCTAssertEqual(g.index.neighbours(of: 1, mode: .walk).map(\.to), [2])
        XCTAssertTrue(g.index.neighbours(of: 1, mode: .drive).isEmpty)
    }

    func testGraphPlanDrawsOnGraphLineAndStaysHonestOffGraph() {
        let g = twoHopWalkOnly()
        let walk = GraphPlan.line(graph: g, from: (lat: 0, lon: 0), to: (lat: 0, lon: 0.02), mode: .walk)
        XCTAssertEqual(walk.chrome, "")
        XCTAssertEqual(walk.coords.count, 3)
        XCTAssertEqual(walk.coords.first?.lon, 0)
        XCTAssertEqual(walk.coords.last?.lon, 0.02)

        let drive = GraphPlan.line(graph: g, from: (lat: 0, lon: 0), to: (lat: 0, lon: 0.02), mode: .drive)
        XCTAssertEqual(drive.chrome, GraphPlan.offGraph)
        XCTAssertTrue(drive.coords.isEmpty)

        let missing = GraphPlan.line(graph: nil, from: (lat: 0, lon: 0), to: (lat: 1, lon: 1), mode: .walk)
        XCTAssertEqual(missing.chrome, GraphPlan.offGraph)
        XCTAssertTrue(missing.coords.isEmpty)

        let empty = GraphPlan.line(
            graph: RouteGraph(nodes: [], edges: []),
            from: (lat: 0, lon: 0),
            to: (lat: 0, lon: 0.02),
            mode: .walk
        )
        XCTAssertEqual(empty.chrome, GraphPlan.offGraph)
        XCTAssertTrue(empty.coords.isEmpty)
        XCTAssertEqual(GraphPlan.offGraph, "OFF GRAPH")
    }

    func testRouteGraphLoadRejectsEmptyOrMissing() throws {
        XCTAssertNil(RouteGraph.load(from: nil))
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("empty-graph-\(UUID().uuidString).json")
        try Data("{\"nodes\":{},\"edges\":[]}".utf8).write(to: empty)
        XCTAssertNil(RouteGraph.load(from: empty))
        let ok = FileManager.default.temporaryDirectory.appendingPathComponent("ok-graph-\(UUID().uuidString).json")
        try Data("{\"nodes\":{\"1\":{\"id\":1,\"lon\":0,\"lat\":0}},\"edges\":[{\"a\":1,\"b\":1,\"m\":0,\"walk\":true,\"drive\":true}]}".utf8).write(to: ok)
        XCTAssertEqual(RouteGraph.load(from: ok)?.linkCount, 1)
    }

    func testPackedGraphKeepsEveryTurnIncludingOneWays() throws {
        // Three nodes in a line. The first segment is two-way (flags 15); the
        // second may only be taken west to east (flags 3), like a one-way street.
        let packed = """
        {"v":2,"engine":"osm-graph","lat":[0,0,0],"lon":[0,0.01,0.02],\
        "e":[0,1,100,15,1,2,100,3]}
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("packed-graph-\(UUID().uuidString).json")
        try Data(packed.utf8).write(to: url)

        let g = try XCTUnwrap(RouteGraph.load(from: url))
        XCTAssertEqual(g.nodeCount, 3)
        XCTAssertEqual(g.linkCount, 3)
        XCTAssertEqual(g.point(2)?.lon, 0.02)

        let out = try XCTUnwrap(GraphRouter.route(graph: g, from: 0, to: 2, mode: .walk))
        XCTAssertEqual(out.nodeIds, [0, 1, 2])
        XCTAssertEqual(out.meters, 200)
        XCTAssertNotNil(GraphRouter.route(graph: g, from: 0, to: 2, mode: .drive))
        XCTAssertNil(GraphRouter.route(graph: g, from: 2, to: 0, mode: .walk))
    }

    func testPackedGraphRefusesAnUnknownWireVersion() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("future-graph-\(UUID().uuidString).json")
        try Data("{\"v\":99,\"lat\":[0],\"lon\":[0],\"e\":[0,0,0,1]}".utf8).write(to: url)
        XCTAssertNil(RouteGraph.load(from: url))
    }

    func testVoiceNavOnGraphLeftTurnIsCompleteNotTruncated() {
        let coords: [(lat: Double, lon: Double)] = [
            (0.0, 0.0),
            (0.0, 0.0017966),
            (0.0008993, 0.0017966),
        ]
        let text = VoiceNav.prompt(
            packName: "TX WEST",
            headingDeg: 90,
            routeCoords: coords,
            planChrome: "",
            destination: nil,
            you: nil,
            locale: "en"
        )
        XCTAssertTrue(text.contains("Walk 200 meters."))
        XCTAssertTrue(text.contains("Turn left."))
        XCTAssertTrue(text.contains("Walk 100 meters."))
        XCTAssertTrue(text.contains("Arrive at destination."))
        XCTAssertTrue(text.contains("Total 300 meters."))
        XCTAssertTrue(text.contains("Heading 90 degrees."))
        XCTAssertFalse(text.hasSuffix("Walk"))
        XCTAssertNotEqual(text, "TX WEST 90 degrees")
        XCTAssertGreaterThan(text.count, 40)
    }

    func testVoiceNavOffGraphIsFullHonestSentence() {
        let text = VoiceNav.prompt(
            packName: "TX WEST",
            headingDeg: 45,
            routeCoords: [],
            planChrome: GraphPlan.offGraph,
            destination: (31.8, -106.5),
            you: (31.76, -106.49),
            locale: "en"
        )
        XCTAssertTrue(text.hasPrefix("OFF GRAPH."))
        XCTAssertTrue(text.contains("No walkable street path from YOU."))
        XCTAssertTrue(text.contains("TX WEST."))
        XCTAssertTrue(text.contains("Heading 45 degrees."))
        XCTAssertGreaterThan(text.count, 24)
    }

    func testVoiceNavNoRouteExplainsHowToStart() {
        let text = VoiceNav.prompt(
            packName: "TX WEST",
            headingDeg: nil,
            routeCoords: [],
            planChrome: "",
            destination: nil,
            you: nil,
            locale: "en"
        )
        XCTAssertTrue(text.contains("TX WEST."))
        XCTAssertTrue(text.contains("Heading unavailable."))
        XCTAssertTrue(text.contains("Set a destination, then WALK, then SPEAK for turn by turn."))
        XCTAssertNotEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "TX WEST no heading")
    }

    func testVoiceNavDestWithoutLineDoesNotInventStreets() {
        let text = VoiceNav.prompt(
            packName: "TX WEST",
            headingDeg: 12,
            routeCoords: [],
            planChrome: "",
            destination: (31.80, -106.50),
            you: (31.76, -106.49),
            locale: "en"
        )
        XCTAssertTrue(text.contains("Destination set."))
        XCTAssertTrue(text.contains("Tap WALK for the street path, then SPEAK."))
        XCTAssertFalse(text.contains("Turn left."))
        XCTAssertFalse(text.contains("Arrive at destination."))
    }

    func testSpeakStatusIsOneShortLineNotTheWalkScript() {
        let coords: [(lat: Double, lon: Double)] = [
            (0.0, 0.0),
            (0.0, 0.0017966),
            (0.0008993, 0.0017966),
        ]
        let chrome = SpeakStatus.chrome(
            spoke: true,
            routeCoords: coords,
            planChrome: "",
            destination: (0.0008993, 0.0017966),
            you: (0.0, 0.0)
        )
        XCTAssertEqual(chrome, "SPEAK · 1 TURN · 300 M")
        XCTAssertEqual(SpeakStatus.turns(coords), 1)
        // The script the voice speaks must never reach the field.
        for phrase in ["Walk 200 meters.", "Turn left.", "Arrive at destination."] {
            XCTAssertFalse(chrome.contains(phrase))
        }
        XCTAssertFalse(chrome.contains("\n"))
        XCTAssertFalse(SpeakStatus.isClipped(chrome))
        XCTAssertLessThanOrEqual(chrome.count, SpeakStatus.maxCharacters)
    }

    func testSpeakStatusStaysShortAcrossEveryOutcome() {
        let outcomes = [
            SpeakStatus.chrome(
                spoke: false,
                routeCoords: [],
                planChrome: "",
                destination: nil,
                you: nil
            ),
            SpeakStatus.chrome(
                spoke: true,
                routeCoords: [],
                planChrome: GraphPlan.offGraph,
                destination: (31.8, -106.5),
                you: (31.76, -106.49)
            ),
            SpeakStatus.chrome(
                spoke: true,
                routeCoords: [],
                planChrome: "",
                destination: (31.8, -106.5),
                you: (31.76, -106.49)
            ),
            SpeakStatus.chrome(
                spoke: true,
                routeCoords: [],
                planChrome: "",
                destination: nil,
                you: nil
            ),
        ]
        XCTAssertEqual(outcomes[0], SpeakStatus.failed)
        XCTAssertEqual(outcomes[1], "SPEAK · OFF GRAPH")
        XCTAssertTrue(outcomes[2].hasPrefix("SPEAK · DEST "))
        XCTAssertEqual(outcomes[3], "SPEAK · SET DEST")
        for outcome in outcomes {
            XCTAssertFalse(outcome.isEmpty)
            XCTAssertFalse(SpeakStatus.isClipped(outcome))
            XCTAssertLessThanOrEqual(outcome.count, SpeakStatus.maxCharacters)
        }
    }

    func testVoiceKeepsTheWholeScriptEvenThoughTheFieldDoesNot() {
        let text = VoiceNav.prompt(
            packName: "TX WEST",
            headingDeg: 90,
            routeCoords: [
                (0.0, 0.0),
                (0.0, 0.0017966),
                (0.0008993, 0.0017966),
            ],
            planChrome: "",
            destination: nil,
            you: nil,
            locale: "en"
        )
        XCTAssertTrue(text.contains("Walk 200 meters."))
        XCTAssertTrue(text.contains("Turn left."))
        XCTAssertTrue(text.contains("Arrive at destination."))
        XCTAssertGreaterThan(text.count, SpeakStatus.maxCharacters)
    }

    /// The binary reader trusts two numbers in the header to size every array
    /// after it, so anything that does not add up has to be refused before it
    /// is believed rather than read past the end of the file.
    func testTheBinaryReaderRefusesBytesThatDoNotAddUp() throws {
        let dir = FileManager.default.temporaryDirectory
        func write(_ bytes: [UInt8], _ name: String) throws -> URL {
            let url = dir.appendingPathComponent("\(name)-\(UUID().uuidString).bin")
            try Data(bytes).write(to: url)
            return url
        }
        // One node at 0,0 with no links: a real header, but a graph with
        // nothing to route on, which load() reports as no graph at all.
        var good: [UInt8] = Array("BLKTGRF".utf8) + [1]
        good += [3, 0, 0, 0]  // version
        good += [1, 0, 0, 0]  // one node
        good += [0, 0, 0, 0]  // no links
        good += [0, 0, 0, 0]  // reserved
        good += [0, 0, 0, 0]  // latE7
        good += [0, 0, 0, 0]  // lonE7
        good += [0, 0, 0, 0]  // rowStart[0]
        good += [0, 0, 0, 0]  // rowStart[1]
        XCTAssertNil(RouteGraph.load(from: try write(good, "linkless")))

        var wrongMagic = good
        wrongMagic[0] = 0x42
        XCTAssertNil(RouteGraph.load(from: try write(wrongMagic, "magic")))

        var wrongVersion = good
        wrongVersion[8] = 99
        XCTAssertNil(RouteGraph.load(from: try write(wrongVersion, "version")))

        // Header claims far more than the file carries.
        var overclaims = good
        overclaims[16] = 0xFF
        XCTAssertNil(RouteGraph.load(from: try write(overclaims, "overclaims")))

        XCTAssertNil(RouteGraph.load(from: try write(Array(good.prefix(20)), "truncated")))
        XCTAssertNil(RouteGraph.load(from: try write([], "empty")))

        // Right length, sane header, nonsense table: two nodes and one link,
        // with the rows running backwards and the link pointing off the end.
        // Believing either builds a Range that traps or reads past an array.
        var twoNodes: [UInt8] = Array("BLKTGRF".utf8) + [1]
        twoNodes += [3, 0, 0, 0] + [2, 0, 0, 0] + [1, 0, 0, 0] + [0, 0, 0, 0]
        twoNodes += [0, 0, 0, 0, 0, 0, 0, 0]  // latE7 x2
        twoNodes += [0, 0, 0, 0, 0, 0, 0, 0]  // lonE7 x2
        let rowsOK: [UInt8] = [0, 0, 0, 0] + [1, 0, 0, 0] + [1, 0, 0, 0]
        let rowsBackwards: [UInt8] = [1, 0, 0, 0] + [0, 0, 0, 0] + [1, 0, 0, 0]
        let linkInRange: [UInt8] = [1, 0, 0, 0]
        let linkOffTheEnd: [UInt8] = [9, 0, 0, 0]
        let tail: [UInt8] = [10, 0, 0, 0] + [3]  // one millimetre value, one mode byte

        XCTAssertNotNil(RouteGraph.load(from: try write(twoNodes + rowsOK + linkInRange + tail, "sane")))
        XCTAssertNil(RouteGraph.load(from: try write(twoNodes + rowsBackwards + linkInRange + tail, "backwards")))
        XCTAssertNil(RouteGraph.load(from: try write(twoNodes + rowsOK + linkOffTheEnd + tail, "offend")))
    }

    /// Ids are positions, so a set that skips one leaves a hole. The hole must
    /// stay a hole: holding lat/lon 0,0 there would put a phantom node off the
    /// coast of Africa that every tap in an empty area snapped to.
    func testASkippedIdIsAHoleAndNotANodeAtNullIsland() {
        let g = RouteGraph(
            nodes: [
                .init(id: 0, lon: -106.49, lat: 31.76),
                .init(id: 3, lon: -106.48, lat: 31.77),
            ],
            edges: [
                .init(a: 0, b: 3, m: 1400, walk: true, drive: true),
                // Points at a slot nobody placed; must be dropped, not followed.
                .init(a: 0, b: 1, m: 5, walk: true, drive: true),
            ]
        )
        XCTAssertNil(g.point(1))
        XCTAssertNil(g.point(2))
        XCTAssertNotNil(g.point(3))
        XCTAssertEqual(g.linkCount, 1, "a link into an empty slot was kept")
        XCTAssertEqual(g.index.neighbours(of: 0, mode: .walk).map(\.to), [3])

        XCTAssertEqual(GraphRouter.nearestNode(graph: g, lat: 31.76, lon: -106.49), 0)
        // Standing on 0,0 finds nothing at all, and that is the proof: an
        // unfilled slot left holding 0,0 would be the closest thing here.
        // El Paso is far outside the ring search's reach, so nil is the honest
        // answer rather than a node a hemisphere away.
        XCTAssertNil(GraphRouter.nearestNode(graph: g, lat: 0, lon: 0))
        XCTAssertNil(GraphRouter.route(graph: g, from: 0, to: 1, mode: .walk))
        XCTAssertEqual(GraphRouter.route(graph: g, from: 0, to: 3, mode: .walk)?.nodeIds, [0, 3])
        XCTAssertEqual(GraphRouter.coordinates(graph: g, nodeIds: [0, 1, 3]).count, 2)
    }

    private func twoHopWalkOnly() -> RouteGraph {
        RouteGraph(
            nodes: [
                .init(id: 1, lon: 0, lat: 0),
                .init(id: 2, lon: 0.01, lat: 0),
                .init(id: 3, lon: 0.02, lat: 0),
            ],
            edges: [
                .init(a: 1, b: 2, m: 100, walk: true, drive: false),
                .init(a: 2, b: 3, m: 100, walk: true, drive: false),
            ]
        )
    }
}
