import XCTest
@testable import Router

final class RouterTests: XCTestCase {
    func testOnGraphAndBearing() {
        let g = RouteGraph(
            nodes: ["1": .init(id: 1, lon: 0, lat: 0), "2": .init(id: 2, lon: 0.01, lat: 0)],
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
        XCTAssertNil(GraphRouter.nearestNode(graph: RouteGraph(nodes: [:], edges: []), lat: 0, lon: 0))
    }

    /// Weights are the true distance between the points. That is the only shape
    /// in which the search's straight-line estimate stays under the road left to
    /// run, and so the only shape in which it still returns the shortest route.
    private func measuredGraph(
        _ points: [Int: (lat: Double, lon: Double)],
        _ links: [(Int, Int)]
    ) -> RouteGraph {
        var nodes: [String: GraphNode] = [:]
        for (id, c) in points { nodes[String(id)] = GraphNode(id: id, lon: c.lon, lat: c.lat) }
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
        var nodes: [String: GraphNode] = [:]
        for i in 0..<40 {
            nodes[String(i + 1)] = GraphNode(id: i + 1, lon: -106.0 - Double(i) * 0.05, lat: 31.0 + Double(i) * 0.03)
        }
        let g = RouteGraph(nodes: nodes, edges: [])
        XCTAssertEqual(GraphRouter.nearestNode(graph: g, lat: 31.0, lon: -106.0), 1)
        XCTAssertEqual(GraphRouter.nearestNode(graph: g, lat: 32.17, lon: -107.95), 40)
        for probe in [(lat: 30.0, lon: -104.0), (lat: 31.5, lon: -106.9), (lat: 35.0, lon: -110.0)] {
            var best = (id: -1, metres: Double.infinity)
            for n in g.nodes.values {
                let d = GraphRouter.haversine(probe.lat, probe.lon, n.lat, n.lon)
                if d < best.metres { best = (n.id, d) }
            }
            XCTAssertEqual(GraphRouter.nearestNode(graph: g, lat: probe.lat, lon: probe.lon), best.id)
        }
    }

    func testIndexKeepsTheTwoModesApart() {
        let g = twoHopWalkOnly()
        XCTAssertFalse(g.index.links(.walk).isEmpty)
        XCTAssertTrue(g.index.links(.drive).isEmpty)
        XCTAssertEqual(g.index.point.count, g.nodes.count)
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
            graph: RouteGraph(nodes: [:], edges: []),
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
        XCTAssertEqual(RouteGraph.load(from: ok)?.edges.count, 1)
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
        XCTAssertEqual(g.nodes.count, 3)
        XCTAssertEqual(g.edges.count, 3)
        XCTAssertEqual(g.nodes["2"]?.lon, 0.02)

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

    private func twoHopWalkOnly() -> RouteGraph {
        RouteGraph(
            nodes: [
                "1": .init(id: 1, lon: 0, lat: 0),
                "2": .init(id: 2, lon: 0.01, lat: 0),
                "3": .init(id: 3, lon: 0.02, lat: 0),
            ],
            edges: [
                .init(a: 1, b: 2, m: 100, walk: true, drive: false),
                .init(a: 2, b: 3, m: 100, walk: true, drive: false),
            ]
        )
    }
}
