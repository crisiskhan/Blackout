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
