import XCTest
import PackIO
@testable import MapLibreMap

final class MapLibreMapTests: XCTestCase {
    func testToolsAndUSNG() {
        let pack = PackManifest(id: "tx-west", name: "TX WEST", state: "TX", bytes: 1, banners: [], center: .init(lat: 31.76, lon: -106.49), bbox: .init(south: 31, west: -107, north: 32, east: -106))
        let s = MapSession(pack: pack)
        XCTAssertEqual(s.tools.count, MapTool.allCases.count)
        XCTAssertTrue(USNG.label(lat: 31.76, lon: -106.49).contains("USNG"))
        XCTAssertTrue(s.styleRelativePath().contains("style.json"))
    }

    func testMarkStorePersistsAcrossLoad() {
        let suite = UserDefaults(suiteName: "map.marks.test.\(UUID().uuidString)")!
        let marks = [MapMark(id: "m1", lat: 31.76, lon: -106.49, label: "TX WEST")]
        MarkStore.save(marks, defaults: suite)
        let back = MarkStore.load(defaults: suite)
        XCTAssertEqual(back, marks)
        XCTAssertEqual(LockOnChrome.banner(hasGPS: false, hasGraph: false), "OFF GRAPH")
        XCTAssertEqual(LockOnChrome.banner(hasGPS: true, hasGraph: false), "")
        XCTAssertEqual(LockOnChrome.banner(hasGPS: false, hasGraph: true), "")
    }

    func testPackStyleWritesWritableCacheNotBundle() throws {
        let fm = FileManager.default
        let pack = fm.temporaryDirectory.appendingPathComponent("pack-style-\(UUID().uuidString)")
        let cache = fm.temporaryDirectory.appendingPathComponent("cache-style-\(UUID().uuidString)")
        try fm.createDirectory(at: pack, withIntermediateDirectories: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let geo = pack.appendingPathComponent("osm.geojson")
        try Data("{\"type\":\"FeatureCollection\",\"features\":[]}".utf8).write(to: geo)
        let style = pack.appendingPathComponent("style.json")
        let obj: [String: Any] = [
            "version": 8,
            "sources": ["osm": ["type": "geojson", "data": "osm.geojson"]],
            "layers": [],
        ]
        try JSONSerialization.data(withJSONObject: obj).write(to: style)
        let resolved = try PackStyle.resolved(styleAt: style, packRoot: pack, cacheDirectory: cache)
        XCTAssertTrue(resolved.path.hasPrefix(cache.path))
        XCTAssertFalse(fm.fileExists(atPath: pack.appendingPathComponent("style.resolved.json").path))
        let ring = PackGeometry.bboxRing(south: 30, west: -82, north: 31, east: -81)
        XCTAssertEqual(ring.count, 5)
        XCTAssertEqual(ring.first?.lat, ring.last?.lat)
    }

    func testUserPuckFallsBackToPackCenterWhenGPSMissing() {
        let pack = (lat: 29.95, lon: -81.34)
        let you = UserPuck.coordinate(lastKnown: nil, packCenter: pack)
        XCTAssertEqual(you.lat, pack.lat)
        XCTAssertEqual(you.lon, pack.lon)
        XCTAssertEqual(UserPuck.title, "YOU")
    }

    func testUserPuckPrefersLastKnownFix() {
        let last = (lat: 30.10, lon: -81.50)
        let you = UserPuck.coordinate(lastKnown: last, packCenter: (29.95, -81.34))
        XCTAssertEqual(you.lat, last.lat)
        XCTAssertEqual(you.lon, last.lon)
    }

    func testUserPuckHaloRingClosesAroundCoordinate() {
        let ring = UserPuck.haloRing(lat: 29.95, lon: -81.34)
        XCTAssertEqual(ring.count, UserPuck.haloSteps + 1)
        XCTAssertEqual(ring.first?.lat, ring.last?.lat)
        XCTAssertEqual(ring.first?.lon, ring.last?.lon)
        XCTAssertTrue(ring.contains { abs($0.lat - 29.95) > 0.0001 })
    }

    func testUserPuckReappliesWhenMapLostTheAnnotation() {
        let pack = (south: 29.0, west: -82.0, north: 31.0, east: -80.0)
        let puck = (lat: 29.95, lon: -81.34)
        XCTAssertTrue(
            UserPuck.needsReapply(
                storedPack: pack,
                storedPuck: puck,
                pack: pack,
                puck: puck,
                mapHasPuck: false
            )
        )
        XCTAssertFalse(
            UserPuck.needsReapply(
                storedPack: pack,
                storedPuck: puck,
                pack: pack,
                puck: puck,
                mapHasPuck: true
            )
        )
    }
}
