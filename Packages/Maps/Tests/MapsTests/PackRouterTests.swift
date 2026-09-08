import XCTest
@testable import MapsRouting

final class PackRouterTests: XCTestCase {
    func testWalkUsesWalkMsAndWalkBit() throws {
        let pack = try loadToy()
        let outcome = PackRouter.route(from: ToyRouting.n0, to: ToyRouting.n2, profile: .walk, pack: pack)
        guard case .routed(let route) = outcome else {
            return XCTFail("expected walk route, got \(outcome)")
        }
        XCTAssertEqual(route.edgeIndexes, [0, 1])
        XCTAssertEqual(route.distanceMeters, 200, accuracy: 0.01)
        XCTAssertEqual(route.etaSeconds, 2.5, accuracy: 0.01)
        XCTAssertEqual(route.profile, .walk)
    }

    func testDriveSkipsWalkOnlyEdge() throws {
        let pack = try loadToy()
        let blocked = PackRouter.route(from: ToyRouting.n0, to: ToyRouting.n2, profile: .drive, pack: pack)
        XCTAssertEqual(blocked, .offGraph)
        let ok = PackRouter.route(from: ToyRouting.n0, to: ToyRouting.n1, profile: .drive, pack: pack)
        guard case .routed(let route) = ok else {
            return XCTFail("expected drive on first edge")
        }
        XCTAssertEqual(route.edgeIndexes, [0])
        XCTAssertEqual(route.etaSeconds, 0.2, accuracy: 0.01)
    }

    func testBidirectionalWhenOnewayBitClear() throws {
        let pack = try loadToy()
        let back = PackRouter.route(from: ToyRouting.n1, to: ToyRouting.n0, profile: .drive, pack: pack)
        guard case .routed(let route) = back else {
            return XCTFail("expected reverse drive")
        }
        XCTAssertEqual(route.edgeIndexes, [0])
        XCTAssertEqual(route.reversed, [true])
    }

    func testOnewayForwardOnly() throws {
        let root = makeTemp()
        try ToyRouting.writePack(to: root, onewayFirstEdge: true)
        let pack = try XCTUnwrap(RoutingPackLoader.load(packRoot: root))
        let forward = PackRouter.route(from: ToyRouting.n0, to: ToyRouting.n1, profile: .drive, pack: pack)
        XCTAssertNotNil(forward.route)
        let reverse = PackRouter.route(from: ToyRouting.n1, to: ToyRouting.n0, profile: .drive, pack: pack)
        XCTAssertEqual(reverse, .offGraph)
    }

    func testCorruptNodeOrEdgeIndexDoesNotTrap() throws {
        let pack = try loadToy()
        XCTAssertNil(pack.node(at: 9_999))
        XCTAssertNil(pack.edge(at: 9_999))
        XCTAssertEqual(
            ManeuverBuilder.make(nodeIds: [9_999], edgeIndexes: [0], reversed: [false], pack: pack),
            []
        )
    }

    func testMissingPackIsNoGraph() {
        XCTAssertEqual(
            PackRouter.route(from: ToyRouting.n0, to: ToyRouting.n1, profile: .walk, pack: nil),
            .noGraph
        )
    }

    func testOutsideBBoxIsOffGraph() throws {
        let pack = try loadToy()
        let outside = RoutingCoordinate(latitude: 39.74, longitude: -105.3)
        XCTAssertEqual(
            PackRouter.route(from: outside, to: ToyRouting.n1, profile: .walk, pack: pack),
            .offGraph
        )
    }

    func testNoNetworkSymbolsInRouterSources() throws {
        let here = URL(fileURLWithPath: #filePath)
        let sources = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MapsRouting")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty)
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file)
            let sessionType = ["URL", "Session"].joined()
            XCTAssertFalse(text.contains(sessionType), file.lastPathComponent)
            XCTAssertFalse(text.contains(["MK", "Directions"].joined()), file.lastPathComponent)
            XCTAssertFalse(text.contains(["MK", "LocalSearch"].joined()), file.lastPathComponent)
            XCTAssertFalse(text.contains("import Mesh"), file.lastPathComponent)
            XCTAssertFalse(text.contains("BlackoutMesh"), file.lastPathComponent)
        }
    }

    private func loadToy() throws -> RoutingPack {
        let root = makeTemp()
        try ToyRouting.writePack(to: root)
        return try XCTUnwrap(RoutingPackLoader.load(packRoot: root))
    }

    private func makeTemp() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rr-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
