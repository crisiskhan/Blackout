import XCTest
@testable import MapsRouting

final class RoutingVersionTests: XCTestCase {
    func testKnownV1FormatAndMagicStayCompatible() throws {
        XCTAssertEqual(RoutingLayout.format, "blackout-routing-v1")
        XCTAssertEqual(RoutingLayout.tooNewCopy, "Pack too new.")
        XCTAssertEqual(RoutingLayout.formatStatus(RoutingLayout.format), .compatible)
        XCTAssertEqual(RoutingLayout.magicStatus(RoutingLayout.graphMagic, expected: RoutingLayout.graphMagic), .compatible)
        let root = makeTemp()
        try ToyRouting.writePack(to: root)
        XCTAssertEqual(RoutingPackLoader.inspect(packRoot: root), .compatible)
        XCTAssertNotNil(RoutingPackLoader.load(packRoot: root))
    }

    func testNewerRoutingFormatIsTooNewNotSilentEmpty() throws {
        let root = makeTemp()
        try ToyRouting.writePack(to: root)
        let url = root.appendingPathComponent("routing/routing.json")
        try Data("{\"format\":\"blackout-routing-v2\",\"nodeCount\":3,\"edgeCount\":2}".utf8).write(to: url)
        XCTAssertEqual(RoutingLayout.formatStatus("blackout-routing-v2"), .tooNew)
        XCTAssertEqual(RoutingPackLoader.inspect(packRoot: root), .tooNew)
        XCTAssertNil(RoutingPackLoader.load(packRoot: root))
    }

    func testUnknownFormatOnPresentRoutingIsTooNew() throws {
        let root = makeTemp()
        try ToyRouting.writePack(to: root)
        let url = root.appendingPathComponent("routing/routing.json")
        try Data("{\"format\":\"not-this\",\"nodeCount\":3,\"edgeCount\":2}".utf8).write(to: url)
        XCTAssertEqual(RoutingLayout.formatStatus("not-this"), .tooNew)
        XCTAssertEqual(RoutingPackLoader.inspect(packRoot: root), .tooNew)
    }

    func testNewerGraphMagicIsTooNew() throws {
        XCTAssertEqual(RoutingLayout.magicStatus("BLRG0002", expected: RoutingLayout.graphMagic), .tooNew)
        let root = makeTemp()
        try ToyRouting.writePack(to: root, newerGraphMagic: true)
        XCTAssertEqual(RoutingPackLoader.inspect(packRoot: root), .tooNew)
        XCTAssertNil(RoutingPackLoader.load(packRoot: root))
    }

    func testCorruptMagicIsStillUnreadableEmpty() throws {
        XCTAssertEqual(RoutingLayout.magicStatus("XXXX0001", expected: RoutingLayout.graphMagic), .unreadable)
        let root = makeTemp()
        try ToyRouting.writePack(to: root, badGraphMagic: true)
        XCTAssertEqual(RoutingPackLoader.inspect(packRoot: root), .unreadable)
        XCTAssertNil(RoutingPackLoader.load(packRoot: root))
    }

    func testMissingRoutingIsMissingNotTooNew() throws {
        let root = makeTemp()
        try Data("{\"name\":\"no-routing\"}".utf8).write(to: root.appendingPathComponent("manifest.json"))
        XCTAssertEqual(RoutingPackLoader.inspect(packRoot: root), .missing)
        XCTAssertNil(RoutingPackLoader.load(packRoot: root))
    }

    private func makeTemp() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rv-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
