import XCTest
@testable import BlackoutPacks

final class PackZipTests: XCTestCase {
    func testArchiveExtractRoundtrip() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("packzip-\(UUID().uuidString)", isDirectory: true)
        let tiles = root.appendingPathComponent("tiles/10/1", isDirectory: true)
        try fm.createDirectory(at: tiles, withIntermediateDirectories: true)
        try Data("{\"id\":\"el-paso\"}".utf8).write(to: root.appendingPathComponent("manifest.json"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tiles.appendingPathComponent("1.png"))

        let zip = fm.temporaryDirectory.appendingPathComponent("packzip-\(UUID().uuidString).zip")
        try PackZip.archive(directory: root, to: zip)
        let dest = fm.temporaryDirectory.appendingPathComponent("packzip-out-\(UUID().uuidString)", isDirectory: true)
        try PackZip.extract(zipURL: zip, to: dest)

        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("tiles/10/1/1.png").path))
        XCTAssertEqual(
            try Data(contentsOf: dest.appendingPathComponent("tiles/10/1/1.png")),
            Data([0x89, 0x50, 0x4E, 0x47])
        )
    }

    func testExtractKeepsRoutingDirectoryAndManifestAttribution() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("packzip-rt-\(UUID().uuidString)", isDirectory: true)
        let tiles = root.appendingPathComponent("tiles/10/1", isDirectory: true)
        let routing = root.appendingPathComponent("routing", isDirectory: true)
        try fm.createDirectory(at: tiles, withIntermediateDirectories: true)
        try fm.createDirectory(at: routing, withIntermediateDirectories: true)
        try Data(
            "{\"id\":\"el-paso\",\"routing\":\"routing/routing.json\",\"attribution\":\"© OpenStreetMap contributors\"}".utf8
        ).write(to: root.appendingPathComponent("manifest.json"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tiles.appendingPathComponent("1.png"))
        try Data("{\"format\":\"blackout-routing-v1\"}".utf8)
            .write(to: routing.appendingPathComponent("routing.json"))
        try Data("BLRG0001".utf8).write(to: routing.appendingPathComponent("graph.bin"))
        try Data("BLNM0001".utf8).write(to: routing.appendingPathComponent("names.bin"))
        try Data("BLGM0001".utf8).write(to: routing.appendingPathComponent("geometry.bin"))

        let zip = fm.temporaryDirectory.appendingPathComponent("packzip-rt-\(UUID().uuidString).zip")
        try PackZip.archive(directory: root, to: zip)
        let dest = fm.temporaryDirectory.appendingPathComponent("packzip-rt-out-\(UUID().uuidString)", isDirectory: true)
        try PackZip.extract(zipURL: zip, to: dest)

        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("routing/graph.bin").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("routing/names.bin").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("routing/geometry.bin").path))
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: dest.appendingPathComponent("manifest.json"))
        ) as? [String: Any]
        XCTAssertEqual(manifest?["routing"] as? String, "routing/routing.json")
        XCTAssertEqual(manifest?["attribution"] as? String, "© OpenStreetMap contributors")
    }

    func testExtractRootFlattensWrapperFolder() throws {
        let fm = FileManager.default
        let wrapped = fm.temporaryDirectory.appendingPathComponent("packzip-wrap-\(UUID().uuidString)", isDirectory: true)
        let inner = wrapped.appendingPathComponent("us-fl", isDirectory: true)
        let tiles = inner.appendingPathComponent("tiles/8/1", isDirectory: true)
        try fm.createDirectory(at: tiles, withIntermediateDirectories: true)
        try Data("{\"id\":\"us-fl\"}".utf8).write(to: inner.appendingPathComponent("manifest.json"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tiles.appendingPathComponent("1.png"))

        let zip = fm.temporaryDirectory.appendingPathComponent("packzip-wrap-\(UUID().uuidString).zip")
        try PackZip.archive(directory: wrapped, to: zip)
        let dest = fm.temporaryDirectory.appendingPathComponent("packzip-flat-\(UUID().uuidString)", isDirectory: true)
        try PackZip.extract(zipURL: zip, to: dest)

        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("tiles/8/1/1.png").path))
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("us-fl/manifest.json").path))
    }
}
