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
}
