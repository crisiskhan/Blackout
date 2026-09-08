import XCTest
import PackIO
import Router
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
        let points = layers.first { $0["id"] as? String == PackStyle.osmPointsLayerID }
        let pointsLayout = points?["layout"] as? [String: Any]
        XCTAssertEqual(pointsLayout?["visibility"] as? String, "none")
        XCTAssertTrue(layers.contains { $0["id"] as? String == PackStyle.roadLabelsLayerID && $0["type"] as? String == "symbol" })
        XCTAssertTrue(layers.contains { $0["id"] as? String == PackStyle.roadRefsLayerID && $0["type"] as? String == "symbol" })
        XCTAssertTrue(layers.contains { $0["id"] as? String == PackStyle.placeLabelsLayerID && $0["type"] as? String == "symbol" })
        XCTAssertTrue(layers.contains { $0["id"] as? String == PackStyle.tracksLayerID && $0["type"] as? String == "line" })
        let roadLabel = layers.first { $0["id"] as? String == PackStyle.roadLabelsLayerID }
        let roadPaint = roadLabel?["paint"] as? [String: Any]
        let roadLayout = roadLabel?["layout"] as? [String: Any]
        XCTAssertEqual(roadPaint?["text-color"] as? String, PackStyle.silverInk)
        XCTAssertEqual(roadPaint?["text-halo-color"] as? String, PackStyle.voidInk)
        XCTAssertGreaterThanOrEqual(roadPaint?["text-halo-width"] as? Double ?? 0, 2.0)
        XCTAssertLessThanOrEqual(roadLayout?["symbol-spacing"] as? Int ?? 999, 110)
        XCTAssertGreaterThanOrEqual(roadLayout?["text-max-angle"] as? Int ?? 0, 40)
        let refs = layers.first { $0["id"] as? String == PackStyle.roadRefsLayerID }
        let refPaint = refs?["paint"] as? [String: Any]
        XCTAssertEqual(refPaint?["text-color"] as? String, PackStyle.accentInk)
        XCTAssertEqual(refPaint?["text-halo-color"] as? String, PackStyle.silverInk)
        XCTAssertEqual(OSMCredit.line, "© OpenStreetMap contributors")
    }

    func testPackStyleRewritesLocalGlyphsAndHillshadeNotTileHosts() throws {
        let fm = FileManager.default
        let pack = fm.temporaryDirectory.appendingPathComponent("pack-glyphs-\(UUID().uuidString)")
        let cache = fm.temporaryDirectory.appendingPathComponent("cache-glyphs-\(UUID().uuidString)")
        try fm.createDirectory(at: pack, withIntermediateDirectories: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("{\"type\":\"FeatureCollection\",\"features\":[]}".utf8).write(to: pack.appendingPathComponent("osm.geojson"))
        try Data("png".utf8).write(to: pack.appendingPathComponent("hillshade.png"))
        let style = pack.appendingPathComponent("style.json")
        let obj: [String: Any] = [
            "version": 8,
            "glyphs": "glyphs/{fontstack}/{range}.pbf",
            "sources": [
                "osm": ["type": "geojson", "data": "osm.geojson"],
                "hillshade": ["type": "image", "url": "hillshade.png"],
            ],
            "layers": [["id": "roads", "type": "line", "source": "osm"]],
        ]
        try JSONSerialization.data(withJSONObject: obj).write(to: style)
        let resolved = try PackStyle.resolved(styleAt: style, packRoot: pack, cacheDirectory: cache)
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: resolved)) as? [String: Any]
        let glyphs = parsed?["glyphs"] as? String ?? ""
        XCTAssertTrue(glyphs.hasPrefix("file:"))
        XCTAssertTrue(glyphs.contains("glyphs/{fontstack}/{range}.pbf"))
        XCTAssertFalse(glyphs.contains("googleapis"))
        XCTAssertFalse(glyphs.contains("apple.com"))
        let sources = parsed?["sources"] as? [String: Any]
        let hill = sources?["hillshade"] as? [String: Any]
        XCTAssertEqual(hill?["url"] as? String, pack.appendingPathComponent("hillshade.png").absoluteString)
    }

    func testMarkStoreLoadUniquesPersistedDuplicateCoords() {
        let suite = UserDefaults(suiteName: "map.marks.dedupe.\(UUID().uuidString)")!
        let clones = (0..<9).map { i in
            MapMark(id: "m\(i)", lat: 31.8705, lon: -106.5973, label: "FL NORTH")
        }
        MarkStore.save(clones, defaults: suite)
        let back = MarkStore.load(defaults: suite)
        XCTAssertEqual(back.count, 1)
        XCTAssertTrue(MarkDrop.sameCoord((back[0].lat, back[0].lon), (31.8705, -106.5973)))
    }

    func testMarkDropDedupesIdenticalCoordsFromOneTap() {
        var marks: [MapMark] = []
        for _ in 0..<9 {
            marks = MarkDrop.merging(
                marks,
                lat: 31.8705,
                lon: -106.5973,
                label: PackChrome.offPack
            )
        }
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].label, PackChrome.offPack)
        XCTAssertEqual(MarkDrop.rounded(31.87054), 31.8705)
        XCTAssertTrue(MarkDrop.sameCoord((31.87054, -106.59731), (31.8705, -106.5973)))
    }

    func testPackChromeLabelsElPasoOffFLSouthNotFLNorth() {
        let elPaso = (lat: 31.8705, lon: -106.5973)
        let flSouth = (south: 25.72, west: -80.8, north: 25.82, east: -80.18)
        XCTAssertEqual(
            PackChrome.banner(fix: elPaso, bbox: flSouth),
            PackChrome.offPack
        )
        XCTAssertEqual(
            PackChrome.markLabel(lat: elPaso.lat, lon: elPaso.lon, packName: "FL SOUTH", bbox: flSouth),
            PackChrome.offPack
        )
        XCTAssertNotEqual(
            PackChrome.markLabel(lat: elPaso.lat, lon: elPaso.lon, packName: "FL SOUTH", bbox: flSouth),
            "FL NORTH"
        )
        let txWest = (south: 31.7, west: -106.62, north: 32.0, east: -106.35)
        XCTAssertEqual(PackChrome.banner(fix: elPaso, bbox: txWest), "")
        XCTAssertEqual(
            PackChrome.markLabel(lat: elPaso.lat, lon: elPaso.lon, packName: "TX WEST", bbox: txWest),
            "TX WEST"
        )
        XCTAssertEqual(PackChrome.banner(fix: nil, bbox: flSouth), "")
    }

    func testPackBBoxIsOutlineNotFilledSlab() {
        XCTAssertFalse(PackOverlay.fillsBBox)
    }

    func testRouteLineSourceHooksAndOffGraphHasNoDrawableCoords() {
        XCTAssertEqual(RouteLine.sourceID, "route-line-src")
        XCTAssertEqual(RouteLine.layerID, "route-line")
        XCTAssertEqual(RouteLine.offGraph, "OFF GRAPH")
        XCTAssertTrue(RouteLine.shouldDraw([(lat: 31.76, lon: -106.49), (lat: 31.80, lon: -106.50)]))
        XCTAssertFalse(RouteLine.shouldDraw([]))
        XCTAssertFalse(RouteLine.shouldDraw([(lat: 31.76, lon: -106.49)]))
        XCTAssertTrue(
            RouteLine.needsReapply(
                stored: [],
                route: [(lat: 31.76, lon: -106.49), (lat: 31.80, lon: -106.50)]
            )
        )
        XCTAssertFalse(
            RouteLine.needsReapply(
                stored: [(lat: 31.76, lon: -106.49)],
                route: [(lat: 31.76, lon: -106.49)]
            )
        )
        let pack = PackManifest(
            id: "tx-west",
            name: "TX WEST",
            state: "TX",
            bytes: 1,
            banners: [],
            center: .init(lat: 31.76, lon: -106.49),
            bbox: .init(south: 31, west: -107, north: 32, east: -106)
        )
        let session = MapSession(pack: pack)
        let empty = RouteGraph(nodes: [:], edges: [])
        let bearing = session.navigate(graph: empty, from: 1, to: 2, mode: .walk)
        XCTAssertEqual(bearing.fallback, .bearingOffGraph)
        XCTAssertFalse(RouteLine.shouldDraw(GraphRouter.coordinates(graph: empty, nodeIds: bearing.nodeIds)))
    }

    func testWalkDriveChipDisablesWithoutGraphAndNeverDrawsBearing() {
        XCTAssertFalse(WalkDriveChip.isEnabled(hasUsableGraph: false, hasDestination: true))
        XCTAssertFalse(WalkDriveChip.isEnabled(hasUsableGraph: true, hasDestination: false))
        XCTAssertTrue(WalkDriveChip.isEnabled(hasUsableGraph: true, hasDestination: true))
        XCTAssertEqual(
            WalkDriveChip.chrome(hasUsableGraph: true, hasDestination: false, planChrome: ""),
            RouteLine.offGraph
        )
        XCTAssertEqual(
            WalkDriveChip.chrome(hasUsableGraph: false, hasDestination: true, planChrome: ""),
            RouteLine.offGraph
        )
        XCTAssertEqual(
            WalkDriveChip.chrome(hasUsableGraph: true, hasDestination: true, planChrome: ""),
            ""
        )
        XCTAssertEqual(
            WalkDriveChip.chrome(hasUsableGraph: true, hasDestination: true, planChrome: RouteLine.offGraph),
            RouteLine.offGraph
        )
        XCTAssertEqual(MapRuler.chrome(from: nil, to: (lat: 31.80, lon: -106.50)), "RULER —")
        let span = MapRuler.chrome(from: (lat: 31.76, lon: -106.49), to: (lat: 31.76, lon: -106.49))
        XCTAssertTrue(span.hasPrefix("RULER "))
        XCTAssertTrue(span.hasSuffix(" m"))
        XCTAssertEqual(MagTrueChip.chrome(magNorth: true), "MAG")
        XCTAssertEqual(MagTrueChip.chrome(magNorth: false), "TRUE")
    }

    func testRouteTargetPrefersExplicitThenMark() {
        let origin = (lat: 31.76, lon: -106.49)
        let dest = (lat: 31.80, lon: -106.50)
        let picked = RouteTarget.pick(explicit: dest, lastMark: origin, origin: origin)
        XCTAssertEqual(picked?.lat, dest.lat)
        XCTAssertEqual(picked?.lon, dest.lon)
        let fromMark = RouteTarget.pick(explicit: nil, lastMark: dest, origin: origin)
        XCTAssertEqual(fromMark?.lat, dest.lat)
        XCTAssertNil(RouteTarget.pick(explicit: nil, lastMark: nil, origin: origin))
    }

    func testPackStyleSecondResolveDoesNotRewriteCachedFile() throws {
        let fm = FileManager.default
        let pack = fm.temporaryDirectory.appendingPathComponent("pack-style-cache-\(UUID().uuidString)")
        let cache = fm.temporaryDirectory.appendingPathComponent("cache-style-cache-\(UUID().uuidString)")
        try fm.createDirectory(at: pack, withIntermediateDirectories: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("{\"type\":\"FeatureCollection\",\"features\":[]}".utf8)
            .write(to: pack.appendingPathComponent("osm.geojson"))
        let style = pack.appendingPathComponent("style.json")
        try JSONSerialization.data(withJSONObject: [
            "version": 8,
            "sources": ["osm": ["type": "geojson", "data": "osm.geojson"]],
            "layers": [],
        ]).write(to: style)
        let first = try PackStyle.resolved(styleAt: style, packRoot: pack, cacheDirectory: cache)
        try Data("STALE".utf8).write(to: first)
        XCTAssertFalse(PackStyle.needsResolve(styleModified: Date(timeIntervalSince1970: 1), outputModified: Date(timeIntervalSince1970: 2)))
        XCTAssertTrue(PackStyle.needsResolve(styleModified: Date(timeIntervalSince1970: 3), outputModified: Date(timeIntervalSince1970: 2)))
        XCTAssertTrue(PackStyle.needsResolve(styleModified: Date(timeIntervalSince1970: 1), outputModified: nil))
        let second = try PackStyle.resolved(styleAt: style, packRoot: pack, cacheDirectory: cache)
        XCTAssertEqual(second, first)
        XCTAssertEqual(try Data(contentsOf: second), Data("STALE".utf8))
    }

    func testOverlaySyncSkipsStyleMutationWhenPuckAndRouteHold() {
        XCTAssertFalse(
            OverlaySync.needsStyleMutation(force: false, puckNeedsReapply: false, routeNeedsReapply: false)
        )
        XCTAssertTrue(
            OverlaySync.needsStyleMutation(force: true, puckNeedsReapply: false, routeNeedsReapply: false)
        )
        XCTAssertTrue(
            OverlaySync.needsStyleMutation(force: false, puckNeedsReapply: true, routeNeedsReapply: false)
        )
        XCTAssertTrue(
            OverlaySync.needsStyleMutation(force: false, puckNeedsReapply: false, routeNeedsReapply: true)
        )
    }

    func testFixPublishThrottlesHeadingJitterAndKeepsFirstFix() {
        XCTAssertTrue(
            FixPublish.shouldPublish(
                now: 10,
                lastPublished: nil,
                heading: 10,
                lastHeading: nil,
                coord: (31.76, -106.49),
                lastCoord: nil
            )
        )
        XCTAssertFalse(
            FixPublish.shouldPublish(
                now: 10.1,
                lastPublished: 10,
                heading: 11,
                lastHeading: 10,
                coord: (31.76, -106.49),
                lastCoord: (31.76, -106.49)
            )
        )
        XCTAssertFalse(
            FixPublish.shouldPublish(
                now: 10.4,
                lastPublished: 10,
                heading: 10.4,
                lastHeading: 10,
                coord: (31.76, -106.49),
                lastCoord: (31.76, -106.49)
            )
        )
        XCTAssertTrue(
            FixPublish.shouldPublish(
                now: 10.4,
                lastPublished: 10,
                heading: 14,
                lastHeading: 10,
                coord: (31.76, -106.49),
                lastCoord: (31.76, -106.49)
            )
        )
        XCTAssertEqual(FixPublish.headingDelta(359, 1), 2)
        XCTAssertTrue(MapKeepAwake.idleTimerDisabled(mapInstrumentActive: true))
        XCTAssertFalse(MapKeepAwake.idleTimerDisabled(mapInstrumentActive: false))
    }

    func testPackCameraRefitsWhenCanvasGrowsPastStrip() {
        let pack = (south: 30.3, west: -81.7, north: 30.52, east: -81.38)
        XCTAssertFalse(
            PackCamera.shouldRefit(
                fittedPack: pack,
                pack: pack,
                fittedSize: (width: 390, height: 120),
                size: (width: 0, height: 0)
            )
        )
        XCTAssertTrue(
            PackCamera.shouldRefit(
                fittedPack: pack,
                pack: pack,
                fittedSize: (width: 390, height: 120),
                size: (width: 390, height: 640)
            )
        )
        XCTAssertFalse(
            PackCamera.shouldRefit(
                fittedPack: pack,
                pack: pack,
                fittedSize: (width: 390, height: 640),
                size: (width: 390, height: 640)
            )
        )
    }
}
