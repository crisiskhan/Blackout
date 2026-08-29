import XCTest
@testable import MapsRouting

final class RoutingReaderTests: XCTestCase {
    func testElPasoGraphSizeMatchesPublishedBytes() {
        XCTAssertEqual(
            RoutingLayout.graphByteCount(
                nodes: RoutingLayout.ElPaso.nodeCount,
                edges: RoutingLayout.ElPaso.edgeCount
            ),
            RoutingLayout.ElPaso.graphBytes
        )
        XCTAssertEqual(RoutingLayout.edgeStride, 26)
        XCTAssertEqual(RoutingLayout.graphMagic, "BLRG0001")
        XCTAssertEqual(RoutingLayout.namesMagic, "BLNM0001")
        XCTAssertEqual(RoutingLayout.geometryMagic, "BLGM0001")
        XCTAssertEqual(RoutingLayout.format, "blackout-routing-v1")
    }

    func testReadsHandBuiltThreeNodeTwoEdgeLayout() throws {
        let root = makeTemp()
        try ToyRouting.writePack(to: root)
        let pack = try XCTUnwrap(RoutingPackLoader.load(packRoot: root))
        XCTAssertEqual(pack.nodes.count, 3)
        XCTAssertEqual(pack.edges.count, 2)
        XCTAssertEqual(pack.names, ["", "Mesa Street", "Arroyo Path"])
        XCTAssertEqual(pack.edges[0].from, 0)
        XCTAssertEqual(pack.edges[0].to, 1)
        XCTAssertEqual(pack.edges[0].nameId, 1)
        XCTAssertEqual(pack.edges[0].flags, RoutingLayout.walkFlag | RoutingLayout.driveFlag)
        XCTAssertEqual(pack.edges[0].lengthCm, 8_000)
        XCTAssertEqual(pack.edges[0].walkMs, 1_000)
        XCTAssertEqual(pack.edges[0].driveMs, 200)
        XCTAssertEqual(pack.edges[1].flags, RoutingLayout.walkFlag)
        XCTAssertEqual(pack.geometries[0].count, 2)
        XCTAssertEqual(pack.manifest.attribution, "© OpenStreetMap contributors")
        XCTAssertEqual(pack.manifest.packId, "us-tx-el-paso")
    }

    func testPackedEdgeIsTwentySixBytes() {
        let edge = RoutingEdge(from: 1, to: 2, nameId: 3, flags: 7, lengthCm: 9, walkMs: 11, driveMs: 13)
        let data = RoutingBinary.writeGraph(nodes: [], edges: [edge])
        XCTAssertEqual(data.count, RoutingLayout.headerBytes + RoutingLayout.edgeStride)
        let parsed = try? RoutingBinary.readGraph(data)
        XCTAssertEqual(parsed?.edges.first, edge)
    }

    func testMagicMismatchIsHonestEmpty() throws {
        let root = makeTemp()
        try ToyRouting.writePack(to: root, badGraphMagic: true)
        XCTAssertNil(RoutingPackLoader.load(packRoot: root))
    }

    func testMissingRoutingDirectoryIsHonestEmpty() throws {
        let root = makeTemp()
        try Data("{\"name\":\"no-routing\"}".utf8).write(to: root.appendingPathComponent("manifest.json"))
        XCTAssertNil(RoutingPackLoader.load(packRoot: root))
    }

    func testWrongFormatIsHonestEmpty() throws {
        let root = makeTemp()
        try ToyRouting.writePack(to: root)
        let url = root.appendingPathComponent("routing/routing.json")
        try Data("{\"format\":\"not-this\",\"nodeCount\":3,\"edgeCount\":2}".utf8).write(to: url)
        XCTAssertNil(RoutingPackLoader.load(packRoot: root))
    }

    private func makeTemp() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
