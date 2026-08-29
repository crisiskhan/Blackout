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
}
