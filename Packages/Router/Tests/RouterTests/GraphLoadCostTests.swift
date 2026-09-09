import XCTest

@testable import Router

/// What a real pack's graph costs to hold and to search.
///
/// Routing is the one part of the app whose cost scales with how much ground a
/// pack covers, so it is the thing that decides whether the map can keep
/// growing. Numbers here come from the graphs that actually ship, measured on a
/// simulator, and are printed so a change that makes them worse is visible in
/// the CI log rather than only on someone's phone.
final class GraphLoadCostTests: XCTestCase {
    private static var packsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // RouterTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // Router
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Resources/Packs")
    }

    /// El Paso and Albuquerque downtown, where a route is worth asking for.
    private static let probes: [String: (from: (lat: Double, lon: Double), to: (lat: Double, lon: Double))] = [
        "tx-west": ((31.7587, -106.4869), (31.7960, -106.4270)),
        "nm": ((35.0844, -106.6504), (35.1100, -106.6100)),
        "tx-east": ((30.2672, -97.7431), (30.2980, -97.7100)),
    ]

    func testWhatEachShippedGraphCostsToLoadAndSearch() throws {
        var measured = 0
        for pack in ["tx-west", "nm", "tx-east"] {
            let url = Self.packsRoot.appendingPathComponent("\(pack)/graph.bin")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            measured += 1

            let before = Self.footprintMB()
            let loadStart = Date()
            let graph = try XCTUnwrap(RouteGraph.load(from: url), "\(pack) graph did not load")
            let loadMs = Date().timeIntervalSince(loadStart) * 1000
            let held = Self.footprintMB() - before

            let probe = try XCTUnwrap(Self.probes[pack])
            let snapStart = Date()
            let a = try XCTUnwrap(GraphRouter.nearestNode(graph: graph, lat: probe.from.lat, lon: probe.from.lon))
            let b = try XCTUnwrap(GraphRouter.nearestNode(graph: graph, lat: probe.to.lat, lon: probe.to.lon))
            let snapMs = Date().timeIntervalSince(snapStart) * 1000

            let routeStart = Date()
            let walk = GraphRouter.route(graph: graph, from: a, to: b, mode: .walk)
            let routeMs = Date().timeIntervalSince(routeStart) * 1000

            print(
                "GRAPH-COST \(pack) nodes=\(graph.nodeCount) links=\(graph.linkCount) "
                + "load=\(Self.ms(loadMs)) held=\(String(format: "%.0f", held))MB "
                + "snap=\(Self.ms(snapMs)) route=\(Self.ms(routeMs)) "
                + "hops=\(walk?.nodeIds.count ?? 0) metres=\(String(format: "%.0f", walk?.meters ?? 0))"
            )

            XCTAssertNotNil(walk, "\(pack): no walking route between two downtown points")
            XCTAssertGreaterThan(walk?.nodeIds.count ?? 0, 2, "\(pack): route is a straight hop, not a path")
        }
        try XCTSkipIf(measured == 0, "no shipped graphs in this checkout")
    }

    /// A route has to come back inside the time a thumb waits, on the largest
    /// pack we ship, or the map cannot grow any further.
    func testRoutingStaysQuickOnTheBiggestPack() throws {
        let url = Self.packsRoot.appendingPathComponent("nm/graph.bin")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "no nm graph in this checkout")
        let graph = try XCTUnwrap(RouteGraph.load(from: url))
        let probe = try XCTUnwrap(Self.probes["nm"])
        let a = try XCTUnwrap(GraphRouter.nearestNode(graph: graph, lat: probe.from.lat, lon: probe.from.lon))
        let b = try XCTUnwrap(GraphRouter.nearestNode(graph: graph, lat: probe.to.lat, lon: probe.to.lon))

        let start = Date()
        for _ in 0..<10 {
            _ = GraphRouter.route(graph: graph, from: a, to: b, mode: .walk)
        }
        let each = Date().timeIntervalSince(start) * 1000 / 10
        print("GRAPH-COST nm repeat-route avg=\(Self.ms(each))")
        XCTAssertLessThan(each, 400, "a walking route on NM took \(Self.ms(each)); that is a visible wait")
    }

    private static func ms(_ value: Double) -> String { String(format: "%.0fms", value) }

    /// Resident footprint, the number that decides whether iOS kills the app.
    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard ok == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }
}
