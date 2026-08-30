import XCTest
@testable import BlackoutCore

final class MapPackSchemaTests: XCTestCase {
    func testMissingSchemaIsV1() {
        XCTAssertEqual(MapPackLayout.schema, 1)
        XCTAssertEqual(MapPackLayout.tooNewCopy, "Pack too new.")
        XCTAssertEqual(MapPackLayout.schema(from: ["name": "Front Range sample"]), 1)
        XCTAssertTrue(MapPackLayout.isSupported(1))
        XCTAssertTrue(MapPackLayout.isSupported(MapPackLayout.schema(from: [:])))
    }

    func testExplicitSchemaOneIsSupported() {
        XCTAssertTrue(MapPackLayout.isSupported(MapPackLayout.schema(from: ["schema": 1])))
    }

    func testNewerSchemaIsTooNew() {
        XCTAssertFalse(MapPackLayout.isSupported(MapPackLayout.schema(from: ["schema": 2])))
        XCTAssertFalse(MapPackLayout.isSupported(2))
        XCTAssertFalse(MapPackLayout.isSupported(0))
    }

    func testContainsTilePNGsReturnsOnFirstPNG() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blackout-tile-probe-\(UUID().uuidString)", isDirectory: true)
        let tiles = root.appendingPathComponent("tiles/8/0", isDirectory: true)
        try FileManager.default.createDirectory(at: tiles, withIntermediateDirectories: true)
        let png = tiles.appendingPathComponent("0.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: png)
        XCTAssertTrue(MapPackLayout.containsTilePNGs(root: root))
        XCTAssertFalse(MapPackLayout.containsTilePNGs(root: root.appendingPathComponent("missing")))
        try? FileManager.default.removeItem(at: root)
    }
}
