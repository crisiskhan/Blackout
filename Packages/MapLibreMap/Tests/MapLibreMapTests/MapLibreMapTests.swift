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
        // A mark must come back off disk as the same mark. Deduping the reload
        // through MarkDrop.merging used to mint a fresh id on every launch.
        XCTAssertEqual(back.first?.id, "m1")
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
        MarkStore.save([MapMark(id: "m2", lat: 35.0844, lon: -106.6504, label: "NM")], defaults: suite)
        let back = MarkStore.load(defaults: suite)
        XCTAssertEqual(back.first?.label, "NM")
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
        let albuquerque = (lat: 35.155, lon: -106.53)
        let you = UserPuck.coordinate(
            lastKnown: elPaso,
            packCenter: albuquerque,
            packSouth: 35.06,
            packWest: -106.68,
            packNorth: 35.25,
            packEast: -106.38
        )
        XCTAssertEqual(you.lat, albuquerque.lat)
        XCTAssertEqual(you.lon, albuquerque.lon)
        XCTAssertFalse(
            UserPuck.contains(
                lat: elPaso.lat,
                lon: elPaso.lon,
                south: 35.06,
                west: -106.68,
                north: 35.25,
                east: -106.38
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
            MapMark(id: "m\(i)", lat: 31.8705, lon: -106.5973, label: "TX WEST")
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

    func testPackChromeLabelsElPasoOffTheNMPackNotOntoIt() {
        // Two packs we actually ship, close enough to confuse: a fix in El Paso
        // must read OFF PACK against Albuquerque, never borrow that pack's name.
        let elPaso = (lat: 31.8705, lon: -106.5973)
        let nm = (south: 34.95, west: -106.85, north: 35.35, east: -106.35)
        XCTAssertEqual(
            PackChrome.banner(fix: elPaso, bbox: nm),
            PackChrome.offPack
        )
        XCTAssertEqual(
            PackChrome.markLabel(lat: elPaso.lat, lon: elPaso.lon, packName: "NM", bbox: nm),
            PackChrome.offPack
        )
        XCTAssertNotEqual(
            PackChrome.markLabel(lat: elPaso.lat, lon: elPaso.lon, packName: "NM", bbox: nm),
            "NM"
        )
        let txWest = (south: 31.65, west: -106.85, north: 32.4, east: -106.2)
        XCTAssertEqual(PackChrome.banner(fix: elPaso, bbox: txWest), "")
        XCTAssertEqual(
            PackChrome.markLabel(lat: elPaso.lat, lon: elPaso.lon, packName: "TX WEST", bbox: txWest),
            "TX WEST"
        )
        XCTAssertEqual(PackChrome.banner(fix: nil, bbox: nm), "")
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
        let empty = RouteGraph(nodes: [], edges: [])
        let bearing = session.navigate(graph: empty, from: 1, to: 2, mode: .walk)
        XCTAssertEqual(bearing.fallback, .bearingOffGraph)
        XCTAssertFalse(RouteLine.shouldDraw(GraphRouter.coordinates(graph: empty, nodeIds: bearing.nodeIds)))
    }

    func testWalkDriveChipAlwaysTapsAndNamesTheBlocker() {
        XCTAssertTrue(WalkDriveChip.alwaysTappable)
        let ready = WalkDriveChip.block(
            hasPack: true,
            hasUsableGraph: true,
            hasDestination: true,
            destinationOnPack: true
        )
        XCTAssertNil(ready)
        XCTAssertEqual(
            WalkDriveChip.block(hasPack: false, hasUsableGraph: true, hasDestination: true, destinationOnPack: true),
            .noPack
        )
        XCTAssertEqual(
            WalkDriveChip.block(hasPack: true, hasUsableGraph: false, hasDestination: true, destinationOnPack: true),
            .noGraph
        )
        XCTAssertEqual(
            WalkDriveChip.block(hasPack: true, hasUsableGraph: true, hasDestination: false, destinationOnPack: false),
            .noDestination
        )
        // OFF GRAPH is a routing failure, never "you have not picked a DEST yet".
        XCTAssertEqual(WalkDriveChip.chrome(hasUsableGraph: true, hasDestination: false, planChrome: ""), "")
        XCTAssertEqual(WalkDriveChip.chrome(hasUsableGraph: false, hasDestination: false, planChrome: ""), RouteLine.offGraph)
        XCTAssertEqual(WalkDriveChip.chrome(hasUsableGraph: true, hasDestination: true, planChrome: ""), "")
        XCTAssertEqual(
            WalkDriveChip.block(hasPack: true, hasUsableGraph: true, hasDestination: true, destinationOnPack: false),
            .destinationOffPack
        )
        for block in RouteBlock.allCases {
            for mode in [TravelMode.walk, .drive] {
                let said = block.chrome(mode: mode, packName: "TX WEST")
                XCTAssertFalse(said.isEmpty)
                XCTAssertTrue(said.contains(WalkDriveChip.verb(mode)))
            }
        }
        XCTAssertTrue(RouteBlock.noPath.chrome(mode: .walk, packName: "").hasPrefix(RouteLine.offGraph))
        XCTAssertEqual(RouteBlock.noDestination.planChrome, "")
        XCTAssertEqual(RouteBlock.noPath.planChrome, RouteLine.offGraph)
        XCTAssertEqual(RouteBlock.noGraph.planChrome, RouteLine.offGraph)
        XCTAssertTrue(WalkDriveChip.working(mode: .drive).hasPrefix("DRIVE"))
        XCTAssertEqual(MapRuler.chrome(from: nil, to: (lat: 31.80, lon: -106.50)), "RULER —")
        let span = MapRuler.chrome(from: (lat: 31.76, lon: -106.49), to: (lat: 31.76, lon: -106.49))
        XCTAssertTrue(span.hasPrefix("RULER "))
        XCTAssertTrue(span.hasSuffix(" m"))
        XCTAssertEqual(MagTrueChip.chrome(magNorth: true), "MAG NORTH")
        XCTAssertEqual(MagTrueChip.chrome(magNorth: false), "TRUE NORTH")
    }

    func testMapFieldChromeCollapsesDestTrueStackSpray() {
        let sprayed = MapFieldChrome.lines(
            lock: RouteLine.offGraph,
            route: RouteLine.offGraph,
            tool: MagTrueChip.chrome(magNorth: false),
            bearingDeg: 45,
            speak: "SPEAK · 3 TURNS · 300 M"
        )
        XCTAssertEqual(sprayed.count, 3)
        XCTAssertLessThanOrEqual(sprayed.count, MapFieldChrome.maxLines)
        XCTAssertEqual(sprayed.map(\.slot), [.status, .dest, .speak])
        XCTAssertEqual(Set(sprayed.map(\.id)).count, sprayed.count)
        XCTAssertEqual(sprayed[0].text, "OFF GRAPH · TRUE NORTH")
        XCTAssertTrue(sprayed[0].warn)
        // The destination is a pin on the canvas, so this row spends itself on the
        // heading instead of on a latitude nobody can steer by.
        XCTAssertEqual(sprayed[1].text, "BEARING 45°")
        XCTAssertFalse(sprayed[1].warn)
        for line in sprayed {
            XCTAssertFalse(line.text.contains("DEST 31."))
        }
        XCTAssertEqual(sprayed[2].text, "SPEAK · 3 TURNS · 300 M")
        for line in sprayed {
            // Short status chrome, never a wrapped paragraph over the canvas.
            XCTAssertLessThanOrEqual(line.text.count, 44)
            XCTAssertFalse(line.text.contains("\n"))
        }
    }

    func testActiveBearingIsQuietWithoutSomewhereToWalk() {
        XCTAssertNil(
            MapFieldChrome.activeBearing(
                headingDeg: 12,
                hasDestination: false,
                lockOn: false,
                hasRoute: false
            )
        )
        XCTAssertEqual(
            MapFieldChrome.activeBearing(
                headingDeg: 45,
                hasDestination: true,
                lockOn: false,
                hasRoute: false
            ),
            45
        )
        XCTAssertEqual(
            MapFieldChrome.activeBearing(
                headingDeg: 10,
                hasDestination: false,
                lockOn: true,
                hasRoute: false
            ),
            10
        )
        XCTAssertEqual(
            MapFieldChrome.activeBearing(
                headingDeg: 8,
                hasDestination: false,
                lockOn: false,
                hasRoute: true
            ),
            8
        )
        XCTAssertNil(
            MapFieldChrome.activeBearing(
                headingDeg: nil,
                hasDestination: true,
                lockOn: false,
                hasRoute: false
            )
        )
    }

    func testMapFieldChromeIsSilentWhenNothingIsActive() {
        XCTAssertTrue(
            MapFieldChrome.lines(
                lock: "",
                route: "",
                tool: "",
                bearingDeg: nil,
                speak: ""
            ).isEmpty
        )
        let bearingOnly = MapFieldChrome.lines(
            lock: "",
            route: "",
            tool: "",
            bearingDeg: 12,
            speak: "   "
        )
        XCTAssertEqual(bearingOnly.map(\.text), ["BEARING 12°"])
        XCTAssertEqual(bearingOnly.map(\.slot), [.dest])
        XCTAssertEqual(
            MapFieldChrome.joined([" OFF GRAPH ", "OFF GRAPH", "", "RULER 40 m"]),
            "OFF GRAPH · RULER 40 m"
        )
        XCTAssertTrue(MapFieldChrome.isAlert("OFF PACK · TRUE NORTH"))
        XCTAssertTrue(MapFieldChrome.isAlert("SPEECH FAILED"))
        XCTAssertFalse(MapFieldChrome.isAlert("RULER 40 m"))
    }

    func testPackStyleKeepsLocalGlyphTemplateTokensLiteral() throws {
        let fm = FileManager.default
        let pack = fm.temporaryDirectory.appendingPathComponent("pack-glyphs-\(UUID().uuidString)")
        let cache = fm.temporaryDirectory.appendingPathComponent("cache-glyphs-\(UUID().uuidString)")
        try fm.createDirectory(at: pack, withIntermediateDirectories: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let style = pack.appendingPathComponent("style.json")
        try JSONSerialization.data(withJSONObject: [
            "version": 8,
            "glyphs": "glyphs/{fontstack}/{range}.pbf",
            "sources": [:],
            "layers": [],
        ]).write(to: style)
        let out = try PackStyle.resolved(styleAt: style, packRoot: pack, cacheDirectory: cache)
        let resolved = try JSONSerialization.jsonObject(with: Data(contentsOf: out)) as? [String: Any]
        let glyphs = resolved?["glyphs"] as? String ?? ""
        XCTAssertTrue(glyphs.hasPrefix("file:"))
        for token in PackStyle.glyphTokens {
            XCTAssertTrue(glyphs.contains(token), "glyph template lost \(token): \(glyphs)")
        }
        XCTAssertFalse(glyphs.contains("%7B"))
        XCTAssertFalse(glyphs.contains("%7D"))
        XCTAssertTrue(out.lastPathComponent.contains("v\(PackStyle.resolverVersion)"))
        XCTAssertEqual(
            PackStyle.localGlyphURL(template: "https://tiles/{fontstack}.pbf", packRoot: pack),
            "https://tiles/{fontstack}.pbf"
        )
    }

    func testRouteSummaryReportsDrawnLineAndStaysHonestWhenEmpty() {
        let leg = [(lat: 31.7600, lon: -106.4900), (lat: 31.7690, lon: -106.4900)]
        let meters = RouteSummary.meters(leg)
        XCTAssertGreaterThan(meters, 900)
        XCTAssertLessThan(meters, 1100)
        let walk = RouteSummary.chrome(mode: .walk, coords: leg)
        XCTAssertTrue(walk.hasPrefix("WALK "))
        XCTAssertTrue(walk.contains("km"))
        XCTAssertTrue(walk.contains("min"))
        let drive = RouteSummary.chrome(mode: .drive, coords: leg)
        XCTAssertTrue(drive.hasPrefix("DRIVE "))
        XCTAssertEqual(RouteSummary.distancePhrase(240), "240 m")
        XCTAssertEqual(RouteSummary.meters([]), 0)
        XCTAssertTrue(RouteSummary.chrome(mode: .walk, coords: []).hasPrefix(RouteLine.offGraph))
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
        XCTAssertTrue(
            OverlaySync.needsStyleMutation(
                force: false,
                puckNeedsReapply: false,
                routeNeedsReapply: false,
                destinationNeedsReapply: true
            )
        )
    }

    func testCanvasOpensWhereStreetNamesRender() {
        XCTAssertTrue(PackCamera.opensOnStreetNames())
        XCTAssertGreaterThanOrEqual(PackCamera.openZoom, PackCamera.streetNameMinZoom)
        XCTAssertFalse(PackCamera.opensOnStreetNames(openZoom: 11, labelMinZoom: 12))
    }

    func testDestinationPinTracksTheChosenTarget() {
        let dest = (lat: 31.7619, lon: -106.4850)
        XCTAssertFalse(DestinationPin.needsReapply(stored: nil, destination: nil))
        XCTAssertTrue(DestinationPin.needsReapply(stored: nil, destination: dest))
        XCTAssertTrue(DestinationPin.needsReapply(stored: dest, destination: nil))
        XCTAssertFalse(DestinationPin.needsReapply(stored: dest, destination: dest))
        XCTAssertTrue(
            DestinationPin.needsReapply(stored: dest, destination: (lat: 31.80, lon: -106.4850))
        )
        XCTAssertEqual(DestinationPin.sourceID, "dest-pin-src")
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
