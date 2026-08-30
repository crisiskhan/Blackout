import XCTest
@testable import BlackoutPacks

@MainActor
final class PackStoreBundledTests: XCTestCase {
    func testBundledStatewideIsReadyWithoutDownload() throws {
        let fm = FileManager.default
        let bundle = fm.temporaryDirectory.appendingPathComponent("fp-bundle-\(UUID().uuidString)", isDirectory: true)
        let disk = fm.temporaryDirectory.appendingPathComponent("fp-disk-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: disk, withIntermediateDirectories: true)
        for id in ["us-tx", "us-nm", "us-fl", "us-ny"] {
            let tiles = bundle.appendingPathComponent("\(id)/tiles/8/1", isDirectory: true)
            try fm.createDirectory(at: tiles, withIntermediateDirectories: true)
            try Data("{\"id\":\"\(id)\"}".utf8).write(
                to: bundle.appendingPathComponent("\(id)/manifest.json")
            )
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tiles.appendingPathComponent("1.png"))
        }

        let store = PackStore(bundledRoot: nil, bundledPacksRoot: bundle, diskRoot: disk)
        store.refreshStates()

        for id in ["us-tx", "us-nm", "us-fl", "us-ny"] {
            XCTAssertEqual(store.states[id], .ready)
            XCTAssertTrue(store.isInstalled(id))
            XCTAssertNotNil(store.packRoot(for: id))
        }
        let roots = store.installedPackRoots
        XCTAssertEqual(Set(roots.map(\.lastPathComponent)), ["us-tx", "us-nm", "us-fl", "us-ny"])
        XCTAssertFalse(roots.contains(where: { $0.lastPathComponent == "tiles" }))
        XCTAssertFalse(store.isInstalled("el-paso"))
        XCTAssertNotEqual(store.states["el-paso"], .ready)
        XCTAssertTrue(store.isReady("us-tx"))
        XCTAssertFalse(store.isReady("el-paso"))
        let snapshot = store.readySnapshot
        XCTAssertTrue(snapshot.isReady("us-fl"))
        XCTAssertEqual(store.readyRoots.map(\.lastPathComponent).sorted(), roots.map(\.lastPathComponent).sorted())
    }

    func testFourStatesOnDiskNoSkip() {
        XCTAssertEqual(
            Set(FieldPackRowState.allCases),
            [.noWifi, .downloading, .ready, .failed]
        )
    }
}
