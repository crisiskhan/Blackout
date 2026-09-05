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

    func testMarkStoreCorruptOrWrongTypeIsHonestlyGone() {
        let suite = UserDefaults(suiteName: "map.marks.corrupt.\(UUID().uuidString)")!
        suite.set("not-json", forKey: MarkStore.key)
        XCTAssertEqual(MarkStore.load(defaults: suite), [])
        suite.set(Data([0x00, 0x01, 0x02]), forKey: MarkStore.key)
        XCTAssertEqual(MarkStore.load(defaults: suite), [])
        MarkStore.save([MapMark(id: "m2", lat: 30.4, lon: -81.5, label: "FL NORTH")], defaults: suite)
        let back = MarkStore.load(defaults: suite)
        XCTAssertEqual(back.first?.label, "FL NORTH")
        MarkStore.save([], defaults: suite)
        XCTAssertEqual(MarkStore.load(defaults: suite), [])
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

    func testUserPuckFallsBackToPackCenterWhenFixIsOutsideBBox() {
        let elPaso = (lat: 31.8705, lon: -106.5973)
        let jacksonville = (lat: 30.41, lon: -81.54)
        let you = UserPuck.coordinate(
            lastKnown: elPaso,
            packCenter: jacksonville,
            packSouth: 30.3,
            packWest: -81.7,
            packNorth: 30.52,
            packEast: -81.38
        )
        XCTAssertEqual(you.lat, jacksonville.lat)
        XCTAssertEqual(you.lon, jacksonville.lon)
        XCTAssertFalse(
            UserPuck.contains(
                lat: elPaso.lat,
                lon: elPaso.lon,
                south: 30.3,
                west: -81.7,
                north: 30.52,
                east: -81.38
            )
        )
    }

    func testUserPuckKeepsLastKnownWhenInsideBBox() {
        let inside = (lat: 30.41, lon: -81.54)
        let you = UserPuck.coordinate(
            lastKnown: inside,
            packCenter: (30.0, -82.0),
            packSouth: 30.3,
            packWest: -81.7,
            packNorth: 30.52,
            packEast: -81.38
        )
        XCTAssertEqual(you.lat, inside.lat)
        XCTAssertEqual(you.lon, inside.lon)
    }

    func testPackCameraFitsPackBBoxNotZoom13Center() {
        let fitted = PackCamera.bounds(south: 30.52, west: -81.38, north: 30.3, east: -81.7)
        XCTAssertEqual(fitted.south, 30.3)
        XCTAssertEqual(fitted.west, -81.7)
        XCTAssertEqual(fitted.north, 30.52)
        XCTAssertEqual(fitted.east, -81.38)
        XCTAssertGreaterThan(PackCamera.edgePaddingPoints, 0)
    }

    func testPackStyleAttachesWildStreetLinesAndOsmPoints() throws {
        let fm = FileManager.default
        let pack = fm.temporaryDirectory.appendingPathComponent("pack-wild-\(UUID().uuidString)")
        let cache = fm.temporaryDirectory.appendingPathComponent("cache-wild-\(UUID().uuidString)")
        try fm.createDirectory(at: pack, withIntermediateDirectories: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"highway\":\"crossing\"},\"geometry\":{\"type\":\"Point\",\"coordinates\":[-81.65,30.33]}}]}".utf8)
            .write(to: pack.appendingPathComponent("osm.geojson"))
        try Data("{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"highway\":\"residential\"},\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[-81.48,30.46],[-81.47,30.47]]}}]}".utf8)
            .write(to: pack.appendingPathComponent("wild.geojson"))
        let style = pack.appendingPathComponent("style.json")
        let obj: [String: Any] = [
            "version": 8,
            "sources": ["osm": ["type": "geojson", "data": "osm.geojson"]],
            "layers": [
                ["id": "roads", "type": "line", "source": "osm", "filter": ["has", "highway"]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: obj).write(to: style)
        let resolved = try PackStyle.resolved(styleAt: style, packRoot: pack, cacheDirectory: cache)
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: resolved)) as? [String: Any]
        let sources = parsed?["sources"] as? [String: Any]
        let wild = sources?["wild"] as? [String: Any]
        XCTAssertEqual(wild?["type"] as? String, "geojson")
        XCTAssertEqual(wild?["data"] as? String, pack.appendingPathComponent("wild.geojson").absoluteString)
        let layers = parsed?["layers"] as? [[String: Any]] ?? []
        XCTAssertTrue(layers.contains { $0["id"] as? String == PackStyle.wildRoadsLayerID && $0["type"] as? String == "line" })
        XCTAssertTrue(layers.contains { $0["id"] as? String == PackStyle.osmPointsLayerID && $0["type"] as? String == "circle" })
    }
}
