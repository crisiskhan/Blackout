import BlackoutCore
import XCTest
@testable import BlackoutPacks

@MainActor
final class PackSchemaTests: XCTestCase {
    func testMissingSchemaStillReady() throws {
        let store = try makeStore(schemaJSON: "{\"name\":\"Texas\"}")
        store.refreshStates()
        XCTAssertEqual(store.states["us-tx"], .ready)
        XCTAssertTrue(store.isReady("us-tx"))
        XCTAssertNotEqual(store.messages["us-tx"], MapPackLayout.tooNewCopy)
    }

    func testSchemaOneStillReady() throws {
        let store = try makeStore(schemaJSON: "{\"name\":\"Texas\",\"schema\":1}")
        store.refreshStates()
        XCTAssertEqual(store.states["us-tx"], .ready)
        XCTAssertTrue(store.isReady("us-tx"))
    }

    func testSchemaTwoIsFailedPackTooNewNotReady() throws {
        let store = try makeStore(schemaJSON: "{\"name\":\"Texas\",\"schema\":2}")
        store.refreshStates()
        XCTAssertEqual(store.states["us-tx"], .failed)
        XCTAssertFalse(store.isReady("us-tx"))
        XCTAssertEqual(store.messages["us-tx"], "Pack too new.")
        XCTAssertNil(store.packRoot(for: "us-tx"))
    }

    private func makeStore(schemaJSON: String) throws -> PackStore {
        let fm = FileManager.default
        let bundle = fm.temporaryDirectory.appendingPathComponent("ps-\(UUID().uuidString)", isDirectory: true)
        let disk = fm.temporaryDirectory.appendingPathComponent("pd-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: disk, withIntermediateDirectories: true)
        let tiles = bundle.appendingPathComponent("us-tx/tiles/8/1", isDirectory: true)
        try fm.createDirectory(at: tiles, withIntermediateDirectories: true)
        try Data(schemaJSON.utf8).write(to: bundle.appendingPathComponent("us-tx/manifest.json"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tiles.appendingPathComponent("1.png"))
        return PackStore(bundledRoot: nil, bundledPacksRoot: bundle, diskRoot: disk)
    }
}
