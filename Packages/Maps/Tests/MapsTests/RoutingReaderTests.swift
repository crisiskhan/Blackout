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

    func testChecksumMismatchIsHonestEmpty() throws {
        let root = makeTemp()
        try ToyRouting.writePack(to: root, checksums: ["graph.bin": "deadbeef"])
        XCTAssertNil(RoutingPackLoader.load(packRoot: root))
        XCTAssertNil(
            RoutingPackLoader.coveringRoot(
                among: [root],
                latitude: RoutingLayout.ElPaso.centerLat,
                longitude: RoutingLayout.ElPaso.centerLon
            )
        )
    }

    func testCoveringRootReadsFieldPackNotDefaultPack() throws {
        let denver = makeTemp()
        try Data("{\"name\":\"Front Range sample\"}".utf8)
            .write(to: denver.appendingPathComponent("manifest.json"))
        let elPaso = makeTemp()
        try ToyRouting.writePack(to: elPaso)
        let root = RoutingPackLoader.coveringRoot(
            among: [denver, elPaso],
            latitude: RoutingLayout.ElPaso.centerLat,
            longitude: RoutingLayout.ElPaso.centerLon
        )
        XCTAssertEqual(root?.standardizedFileURL.path, elPaso.standardizedFileURL.path)
        XCTAssertNil(
            RoutingPackLoader.coveringRoot(
                among: [denver, elPaso],
                latitude: 39.74,
                longitude: -105.3
            )
        )
        let pack = try XCTUnwrap(
            RoutingPackLoader.loadCovering(
                among: [denver, elPaso],
                latitude: RoutingLayout.ElPaso.centerLat,
                longitude: RoutingLayout.ElPaso.centerLon
            )
        )
        XCTAssertEqual(pack.manifest.packId, RoutingLayout.ElPaso.packId)
        XCTAssertEqual(pack.manifest.attribution, "© OpenStreetMap contributors")
        XCTAssertTrue(pack.manifest.profiles.contains(.walk))
        XCTAssertTrue(pack.manifest.profiles.contains(.drive))
    }

    func testCoveringRootUsesRoutingBBoxNotTileSpan() throws {
        let texas = makeTemp()
        try ToyRouting.writePack(to: texas)
        let westElPaso = RoutingPackLoader.coveringRoot(
            among: [texas],
            latitude: 31.7619,
            longitude: -106.88
        )
        XCTAssertEqual(westElPaso?.standardizedFileURL.path, texas.standardizedFileURL.path)
    }

    func testCoveringRootPrefersSmallerRoutingBBox() throws {
        let metro = makeTemp()
        try ToyRouting.writePack(to: metro)
        let wide = makeTemp()
        try ToyRouting.writePack(
            to: wide,
            bbox: RoutingBBox(west: -110, south: 29, east: -100, north: 35)
        )
        let root = RoutingPackLoader.coveringRoot(
            among: [wide, metro],
            latitude: RoutingLayout.ElPaso.centerLat,
            longitude: RoutingLayout.ElPaso.centerLon
        )
        XCTAssertEqual(root?.standardizedFileURL.path, metro.standardizedFileURL.path)
    }

    private func makeTemp() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
