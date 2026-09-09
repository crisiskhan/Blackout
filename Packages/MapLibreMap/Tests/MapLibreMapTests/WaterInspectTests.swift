import BlackBox
import PackIO
import XCTest

@testable import MapLibreMap

/// Hold-to-inspect: the gesture, the zoom gates, what the card is allowed to
/// claim, and the shipped water it reads. Everything here runs off Foundation,
/// so it runs on the simulator in CI and on a Linux box through
/// `swift test --package-path tools/swiftcheck`.
final class WaterInspectTests: XCTestCase {

    // MARK: - A press that stays put, against a finger that is moving the map

    func testAStillFingerPastTheClockAsksAboutTheGround() {
        XCTAssertEqual(
            InspectGesture.verdict(elapsedSeconds: 0.46, movedPoints: 0),
            .inspect
        )
    }

    func testTheClockAloneIsNotEnough() {
        XCTAssertEqual(
            InspectGesture.verdict(elapsedSeconds: 0.44, movedPoints: 0),
            .waiting
        )
    }

    func testADragIsAPanNoMatterHowLongItIsHeld() {
        // The whole point: holding still longer does not turn a pan into a
        // question. Once the finger has travelled, it has answered already.
        for seconds in [0.0, 0.44, 0.46, 3.0] {
            XCTAssertEqual(
                InspectGesture.verdict(elapsedSeconds: seconds, movedPoints: 40),
                .pan,
                "held \(seconds)s"
            )
        }
    }

    func testTheMovementBoundaryIsInclusive() {
        let slop = InspectGesture.allowableMovementPoints
        XCTAssertEqual(InspectGesture.verdict(elapsedSeconds: 1, movedPoints: slop), .inspect)
        XCTAssertEqual(InspectGesture.verdict(elapsedSeconds: 1, movedPoints: slop + 0.1), .pan)
    }

    func testTheSlopIsSmallerThanAnythingWorthCallingAPan() {
        // MapLibre's own pan starts around ten points. A press that is really
        // the beginning of a pan has to lose this race, so the slop cannot be
        // generous.
        XCTAssertLessThanOrEqual(InspectGesture.allowableMovementPoints, 16)
        XCTAssertGreaterThan(InspectGesture.minimumPressSeconds, 0.3)
        XCTAssertLessThan(InspectGesture.minimumPressSeconds, 0.8)
    }

    func testMovedIsTheDistanceNotTheAxes() {
        XCTAssertEqual(InspectGesture.moved(dx: 3, dy: 4), 5, accuracy: 1e-9)
    }

    // MARK: - What is drawn at which zoom

    func testFarOutTheWaterIsFillAndNothingElse() {
        XCTAssertEqual(WaterZoom.bands(atZoom: 6), [.fill])
        XCTAssertEqual(WaterZoom.bands(atZoom: 10.9), [.fill])
    }

    func testTheLinesArriveWhereTheTilesActuallyCarryThem() {
        // Under 11 the archive holds no waterway at all, so a line layer drawn
        // below it was promising geometry that is not in the file.
        XCTAssertEqual(WaterZoom.lineMinZoom, 11)
        XCTAssertEqual(WaterZoom.bands(atZoom: 11), [.fill, .line])
        XCTAssertEqual(WaterZoom.bands(atZoom: 13.9), [.fill, .line])
    }

    func testCloseInTheClassMarksArrive() {
        XCTAssertEqual(WaterZoom.bands(atZoom: 14), [.fill, .line, .detail])
        XCTAssertEqual(WaterZoom.bands(atZoom: 17), [.fill, .line, .detail])
    }

    func testTheBandsOnlyEverGrowWithZoom() {
        var previous = WaterZoom.bands(atZoom: 0)
        for step in stride(from: 0.0, through: 20.0, by: 0.5) {
            let bands = WaterZoom.bands(atZoom: step)
            XCTAssertTrue(previous.isSubset(of: bands), "bands shrank at z\(step)")
            previous = bands
        }
    }

    func testNamesFollowTheMarksRatherThanLandingWithThem() {
        XCTAssertGreaterThan(WaterZoom.labelMinZoom, WaterZoom.detailMinZoom)
    }

    func testTheSevenClassesTheCloseZoomDrawsAreExactlyTheDetailOnes() {
        let detail = WaterClass.allCases.filter(\.isDetail)
        XCTAssertEqual(
            Set(detail),
            [.spring, .tank, .acequia, .drain, .playa, .tinaja, .canal]
        )
    }

    // MARK: - What the style ends up holding

    func testAPackWithAWaterLayerGetsTheClassMarksAndTheirNames() throws {
        let pack = try packRoot(named: "water-detail", water: true)
        var sources: [String: Any] = ["osm": ["type": "vector", "url": "pmtiles://osm.pmtiles"]]
        var layers: [[String: Any]] = [["id": "roads", "type": "line", "source": "osm"]]
        PackStyle.attachWaterLayers(&sources, &layers, packRoot: pack)

        let detail = try XCTUnwrap(sources[PackStyle.waterDetailSourceID] as? [String: Any])
        XCTAssertEqual(detail["type"] as? String, "geojson")
        XCTAssertEqual(
            detail["data"] as? String,
            pack.appendingPathComponent("layers/water.geojson").absoluteString
        )

        let points = try XCTUnwrap(layers.first { $0["id"] as? String == PackStyle.waterDetailPointsLayerID })
        XCTAssertEqual(points["type"] as? String, "circle")
        XCTAssertEqual(points["minzoom"] as? Double, WaterZoom.detailMinZoom)

        let labels = try XCTUnwrap(layers.first { $0["id"] as? String == PackStyle.waterDetailLabelsLayerID })
        XCTAssertEqual(labels["type"] as? String, "symbol")
        XCTAssertEqual(labels["minzoom"] as? Double, WaterZoom.labelMinZoom)
        let layout = try XCTUnwrap(labels["layout"] as? [String: Any])
        XCTAssertEqual(layout["text-font"] as? [String], ["Open Sans Regular"])
    }

    func testAPackWithoutTheFileGetsNoMarksRatherThanAnEmptySource() throws {
        let pack = try packRoot(named: "water-none", water: false)
        var sources: [String: Any] = [:]
        var layers: [[String: Any]] = []
        PackStyle.attachWaterLayers(&sources, &layers, packRoot: pack)
        XCTAssertNil(sources[PackStyle.waterDetailSourceID])
        XCTAssertTrue(layers.isEmpty)
    }

    func testAnOlderPackStillGetsItsWaterLinesGated() throws {
        // The pack on a phone today draws water lines from zoom 10, under the
        // zoom its own tiles start carrying waterways. Gating it here is what
        // makes "far is fill only" true on that pack too.
        let pack = try packRoot(named: "water-old", water: false)
        var sources: [String: Any] = [:]
        var layers: [[String: Any]] = [
            ["id": PackStyle.waterLineLayerID, "type": "line", "source": "osm"],
        ]
        PackStyle.attachWaterLayers(&sources, &layers, packRoot: pack)
        XCTAssertEqual(layers[0]["minzoom"] as? Double, WaterZoom.lineMinZoom)
    }

    func testAStyleThatAlreadySaysWhenToDrawWaterIsLeftAlone() throws {
        let pack = try packRoot(named: "water-set", water: false)
        var sources: [String: Any] = [:]
        var layers: [[String: Any]] = [
            ["id": PackStyle.waterLineLayerID, "type": "line", "source": "osm", "minzoom": 12],
        ]
        PackStyle.attachWaterLayers(&sources, &layers, packRoot: pack)
        XCTAssertEqual(layers[0]["minzoom"] as? Int, 12)
    }

    func testResolvingAStyleLeavesTheStreetsExactlyWhereTheyWere() throws {
        // The water work must not have moved anything the map already proved.
        let fm = FileManager.default
        let pack = try packRoot(named: "water-regress", water: true)
        let cache = fm.temporaryDirectory.appendingPathComponent("cache-water-\(UUID().uuidString)")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let style = pack.appendingPathComponent("style.json")
        let obj: [String: Any] = [
            "version": 8,
            "sources": ["osm": ["type": "vector", "url": "pmtiles://osm.pmtiles"]],
            "layers": [["id": "roads", "type": "line", "source": "osm", "source-layer": "road"]],
        ]
        try JSONSerialization.data(withJSONObject: obj).write(to: style)
        let resolved = try PackStyle.resolved(styleAt: style, packRoot: pack, cacheDirectory: cache)
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: resolved)) as? [String: Any]
        let layers = parsed?["layers"] as? [[String: Any]] ?? []

        let roadLabels = try XCTUnwrap(layers.first { $0["id"] as? String == PackStyle.roadLabelsLayerID })
        XCTAssertEqual(roadLabels["source-layer"] as? String, PackStyle.roadSourceLayer)
        XCTAssertLessThanOrEqual(roadLabels["minzoom"] as? Int ?? 99, Int(PackCamera.streetNameMinZoom))
        XCTAssertTrue(layers.contains { $0["id"] as? String == PackStyle.tracksLayerID })
        XCTAssertTrue(layers.contains { $0["id"] as? String == PackStyle.placeLabelsLayerID })
        XCTAssertTrue(layers.contains { $0["id"] as? String == PackStyle.waterDetailPointsLayerID })
        // Every layer on the tile source still names its slice, water included.
        for layer in layers where layer["source"] as? String == "osm" {
            XCTAssertNotNil(layer["source-layer"], "\(layer["id"] ?? "?") lost its source-layer")
        }
        XCTAssertTrue(PackCamera.opensOnStreetNames())
        XCTAssertEqual(OSMCredit.line, "© OpenStreetMap contributors")
    }

    private func packRoot(named: String, water: Bool) throws -> URL {
        let fm = FileManager.default
        let pack = fm.temporaryDirectory.appendingPathComponent("pack-\(named)-\(UUID().uuidString)")
        try fm.createDirectory(at: pack.appendingPathComponent("layers"), withIntermediateDirectories: true)
        if water {
            let fc = #"{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"class":"tank","via":"named","name":"Fivemile Tank"},"geometry":{"type":"Point","coordinates":[-105.375,31.116]}}]}"#
            try Data(fc.utf8).write(to: pack.appendingPathComponent("layers/water.geojson"))
        }
        return pack
    }

    // MARK: - How far a press reaches

    func testAThumbClaimsLessGroundTheFurtherInTheMapIsZoomed() {
        let close = WaterZoom.pressRadiusMeters(zoom: 17, latitude: 31.76)
        let mid = WaterZoom.pressRadiusMeters(zoom: 15, latitude: 31.76)
        let far = WaterZoom.pressRadiusMeters(zoom: 12, latitude: 31.76)
        XCTAssertLessThan(close, mid)
        XCTAssertLessThan(mid, far)
    }

    func testTheReachIsClampedAtBothEnds() {
        XCTAssertEqual(WaterZoom.pressRadiusMeters(zoom: 22, latitude: 31.76), WaterZoom.minPressRadiusMeters)
        XCTAssertEqual(WaterZoom.pressRadiusMeters(zoom: 2, latitude: 31.76), WaterZoom.maxPressRadiusMeters)
    }

    // MARK: - SURE is about the record

    func testSureSaysWhatItIsAboutAndWhatItIsNot() {
        let said = WaterSure.disclaimer.lowercased()
        XCTAssertTrue(said.contains("record"), WaterSure.disclaimer)
        XCTAssertTrue(said.contains("drink"), WaterSure.disclaimer)
    }

    func testATagBeatsANameAndANameBeatsAShrug() {
        XCTAssertGreaterThan(
            WaterSure.classConfidence(.tagged),
            WaterSure.classConfidence(.named)
        )
        XCTAssertGreaterThan(
            WaterSure.classConfidence(.named),
            WaterSure.classConfidence(.generic)
        )
    }

    func testAPressFurtherOffIsLessLikelyToBeAboutThisRecord() {
        let under = WaterSure.percent(evidence: .tagged, distanceMeters: 0, radiusMeters: 100)
        let edge = WaterSure.percent(evidence: .tagged, distanceMeters: 100, radiusMeters: 100)
        XCTAssertEqual(under, 95)
        XCTAssertLessThan(edge, under)
        XCTAssertGreaterThan(edge, 0)
    }

    func testSureStaysAPercent() {
        for evidence in WaterEvidence.allCases {
            for distance in [0.0, 1, 50, 100, 400, 10_000] {
                let value = WaterSure.percent(
                    evidence: evidence,
                    distanceMeters: distance,
                    radiusMeters: 120
                )
                XCTAssertTrue((0...100).contains(value), "\(evidence) at \(distance) m gave \(value)")
            }
        }
    }

    func testGroundHasNoSureBecauseThereIsNoRecordToBeSureAbout() {
        let finding = MapInspect.resolve(lat: 31.76, lon: -106.49, zoom: 15, index: nil)
        XCTAssertNil(finding.sure)
        XCTAssertFalse(finding.isWater)
        XCTAssertEqual(finding.title, "LAND")
    }

    func testEveryClassSaysWhatToDoAndNoneOfItReadsAsPermission() {
        for kind in WaterClass.allCases {
            XCTAssertFalse(kind.title.isEmpty, "\(kind) has no title")
            let line = kind.doLine
            XCTAssertGreaterThan(line.count, 20, "\(kind) do-line is too thin: \(line)")
            let said = line.lowercased()
            XCTAssertFalse(said.contains("safe to drink"), "\(kind) reads as permission: \(line)")
            XCTAssertFalse(said.contains("potable"), "\(kind) reads as permission: \(line)")
        }
    }

    // MARK: - The index the press is measured against

    func testTheIndexRefusesRubbishRatherThanTrustingIt() {
        XCTAssertNil(WaterIndex.load(Data()))
        XCTAssertNil(WaterIndex.load(Data(repeating: 0, count: 64)))
        XCTAssertNil(WaterIndex.load(Data("BLKTGRF\u{01}".utf8) + Data(repeating: 0, count: 64)))
    }

    func testTheIndexRefusesAFileThatHasBeenCutShort() throws {
        let whole = try shippedIndexData("tx-west")
        XCTAssertNotNil(WaterIndex.load(whole))
        XCTAssertNil(WaterIndex.load(whole.prefix(whole.count - 1)))
        XCTAssertNil(WaterIndex.load(whole + Data([0])))
    }

    func testTheShippedIndexLoadsAndHoldsTheWaterTheToolCounted() throws {
        for (pack, records) in [("tx-west", 19_547), ("tx-east", 19_416), ("nm", 14_599)] {
            let index = try XCTUnwrap(WaterIndex.load(try shippedIndexData(pack)), pack)
            XCTAssertEqual(index.recordCount, records, pack)
            XCTAssertGreaterThan(index.pointTotal, index.recordCount, pack)
        }
    }

    func testAPressOnTheElPasoValleyDrainFindsTheDrain() throws {
        let index = try XCTUnwrap(WaterIndex.load(try shippedIndexData("tx-west")))
        // The drain running the valley below the Paso del Norte crossing.
        let hit = try XCTUnwrap(index.nearest(lat: 31.75959, lon: -106.48821, withinMeters: 60))
        XCTAssertEqual(hit.record.kind, .drain)
        XCTAssertEqual(hit.record.evidence, .tagged)
        XCTAssertEqual(hit.record.tag, "waterway=drain")
        XCTAssertLessThan(hit.distanceMeters, 1)
    }

    func testAPressInTheMiddleOfTheGulfFindsNothing() throws {
        let index = try XCTUnwrap(WaterIndex.load(try shippedIndexData("tx-west")))
        XCTAssertNil(index.nearest(lat: 25.0, lon: -90.0, withinMeters: 400))
    }

    func testTheNearestPointWinsRatherThanTheFirstOneFound() throws {
        let index = try XCTUnwrap(WaterIndex.load(try shippedIndexData("nm")))
        let hit = try XCTUnwrap(index.nearest(lat: 35.10, lon: -106.65, withinMeters: 2_000))
        let wider = try XCTUnwrap(index.nearest(lat: 35.10, lon: -106.65, withinMeters: 20_000))
        XCTAssertEqual(hit.record, wider.record)
        XCTAssertEqual(hit.distanceMeters, wider.distanceMeters, accuracy: 1e-6)
    }

    func testNewMexicoShipsItsAcequiasAsAcequias() throws {
        let index = try XCTUnwrap(WaterIndex.load(try shippedIndexData("nm")))
        var acequias = 0
        var madre: WaterRecord?
        for i in 0..<index.recordCount {
            guard let record = index.record(at: i), record.kind == .acequia else { continue }
            acequias += 1
            if record.name.lowercased().contains("acequia madre") { madre = record }
        }
        XCTAssertEqual(acequias, 213)
        let found = try XCTUnwrap(madre, "no Acequia Madre in the NM pack")
        // A name may rename a channel only when the name *is* the channel, and
        // the card has to be able to say which tag it read.
        XCTAssertEqual(found.evidence, .named)
        XCTAssertTrue(found.tag.hasPrefix("waterway="), found.tag)
    }

    func testTheClassTableAgreesWithTheDataItIsReading() throws {
        // A shifted code would silently rename every record. Reading the whole
        // shipped index proves each byte in it decodes to a class this build
        // knows, which is the half the loader cannot check on its own.
        let index = try XCTUnwrap(WaterIndex.load(try shippedIndexData("tx-west")))
        var seen: Set<WaterClass> = []
        for i in 0..<index.recordCount {
            let record = try XCTUnwrap(index.record(at: i), "record \(i)")
            seen.insert(record.kind)
            XCTAssertTrue(WaterTag.wire.contains(record.tag), record.tag)
        }
        // The classes tx-west actually has ground for.
        XCTAssertTrue(seen.isSuperset(of: [.canal, .drain, .ditch, .stream, .river, .tank, .acequia, .tap]))
    }

    func testAPressCostsLessThanAFrame() throws {
        // Ceilings, not measurements: unoptimised on a Linux box the whole
        // tx-west index loads in 21 ms and a press costs 5.4 ms, and released
        // it is 1.1 ms and 0.33 ms. These are ten times that, so they cannot
        // flake on a loaded runner but a real regression still trips them.
        let data = try shippedIndexData("tx-west")
        var clock = Date()
        let index = try XCTUnwrap(WaterIndex.load(data))
        let load = Date().timeIntervalSince(clock) * 1000
        XCTAssertLessThan(load, 250, "index load cost \(Int(load)) ms")

        clock = Date()
        for step in 0..<50 {
            _ = MapInspect.resolve(
                lat: 31.7 + Double(step) * 0.01,
                lon: -106.5 + Double(step) * 0.01,
                zoom: 16,
                index: index
            )
        }
        let each = Date().timeIntervalSince(clock) * 1000 / 50
        XCTAssertLessThan(each, 60, "a press cost \(each) ms")
    }

    func testRecordLookupRefusesAnIndexOffTheEnd() throws {
        let index = try XCTUnwrap(WaterIndex.load(try shippedIndexData("tx-west")))
        XCTAssertNil(index.record(at: -1))
        XCTAssertNil(index.record(at: index.recordCount))
    }

    // MARK: - What the card ends up saying

    func testAPressOnWaterNamesTheClassAndSaysWhichTagItRead() {
        let hit = WaterHit(
            record: WaterRecord(kind: .tank, evidence: .named, tag: "natural=water", name: "Fivemile Tank"),
            lat: 31.9,
            lon: -106.3,
            distanceMeters: 12
        )
        let finding = MapInspect.water(hit, at: (31.9001, -106.3001), radius: 120)
        XCTAssertTrue(finding.isWater)
        XCTAssertTrue(finding.title.contains("STOCK TANK"))
        XCTAssertTrue(finding.title.contains("Fivemile Tank"))
        XCTAssertTrue(finding.why.contains("natural=water"), finding.why)
        XCTAssertEqual(finding.doLine, WaterClass.tank.doLine)
        XCTAssertEqual(finding.fieldCardID, InspectField.water)
        XCTAssertNotNil(finding.sure)
    }

    func testAGenericRecordAdmitsItDoesNotKnowWhichKind() {
        let hit = WaterHit(
            record: WaterRecord(kind: .water, evidence: .generic, tag: "natural=water", name: ""),
            lat: 31.9,
            lon: -106.3,
            distanceMeters: 0
        )
        let finding = MapInspect.water(hit, at: (31.9, -106.3), radius: 120)
        XCTAssertEqual(finding.title, "WATER")
        XCTAssertTrue(finding.why.lowercased().contains("nothing saying which kind"), finding.why)
    }

    func testGroundPointsAtTheNearestWaterWhenThereIsSomeToPointAt() {
        let hit = WaterHit(
            record: WaterRecord(kind: .acequia, evidence: .named, tag: "waterway=ditch", name: "Acequia Madre"),
            lat: 35.11,
            lon: -106.65,
            distanceMeters: 640
        )
        let finding = MapInspect.land(at: (35.10, -106.65), radius: 120, nearest: hit)
        XCTAssertTrue(finding.why.contains("Acequia Madre"), finding.why)
        XCTAssertTrue(finding.why.contains("640 m"), finding.why)
        XCTAssertTrue(finding.why.contains("N"), finding.why)
        XCTAssertNil(finding.sure)
    }

    func testGroundWithNothingNearSaysSoRatherThanGuessing() {
        let finding = MapInspect.land(at: (31.0, -104.0), radius: 120, nearest: nil)
        XCTAssertTrue(finding.why.contains("No water record within 120 m"), finding.why)
        XCTAssertEqual(finding.fieldCardID, InspectField.land)
    }

    func testDistanceReadsInMetresCloseAndKilometresFar() {
        XCTAssertEqual(MapInspect.distance(640), "640 m")
        XCTAssertEqual(MapInspect.distance(1_450), "1.4 km")
    }

    func testTheCompassPointsTheRightWay() {
        XCTAssertEqual(MapInspect.compass(from: (31.0, -106.0), to: (32.0, -106.0)), "N")
        XCTAssertEqual(MapInspect.compass(from: (31.0, -106.0), to: (30.0, -106.0)), "S")
        XCTAssertEqual(MapInspect.compass(from: (31.0, -106.0), to: (31.0, -105.0)), "E")
        XCTAssertEqual(MapInspect.compass(from: (31.0, -106.0), to: (31.0, -107.0)), "W")
        XCTAssertEqual(MapInspect.compass(from: (31.0, -106.0), to: (31.0, -106.0)), "here")
    }

    func testResolveFallsBackToGroundWhenThePackHasNoWaterIndex() {
        let finding = MapInspect.resolve(lat: 31.76, lon: -106.49, zoom: 16, index: nil)
        XCTAssertEqual(finding.fieldCardID, InspectField.land)
        XCTAssertTrue(finding.why.contains("Nothing else within"), finding.why)
    }

    func testResolveOnTheShippedPackAnswersAnElPasoAcequiaEndToEnd() throws {
        let index = try XCTUnwrap(WaterIndex.load(try shippedIndexData("tx-west")))
        // A press on the Acequia Madre in the lower valley, at the zoom the map
        // opens at: pack on disk, no network, no model.
        let finding = MapInspect.resolve(lat: 31.73561, lon: -106.4382, zoom: 16, index: index)
        XCTAssertTrue(finding.isWater, finding.title)
        XCTAssertTrue(finding.title.contains("ACEQUIA"), finding.title)
        XCTAssertTrue(finding.title.contains("Acequia Madre"), finding.title)
        XCTAssertEqual(finding.doLine, WaterClass.acequia.doLine)
        XCTAssertEqual(finding.fieldCardID, InspectField.water)
        // Named rather than tagged, and the press is right on it.
        XCTAssertEqual(finding.sure, 78)
    }

    func testTheSamePressFurtherOffTheWaterIsLessSureOfItself() throws {
        let index = try XCTUnwrap(WaterIndex.load(try shippedIndexData("tx-west")))
        let onIt = MapInspect.resolve(lat: 31.73561, lon: -106.4382, zoom: 14, index: index)
        let beside = MapInspect.resolve(lat: 31.73661, lon: -106.4382, zoom: 14, index: index)
        let sureOnIt = try XCTUnwrap(onIt.sure)
        let sureBeside = try XCTUnwrap(beside.sure)
        XCTAssertTrue(onIt.isWater)
        XCTAssertTrue(beside.isWater)
        XCTAssertLessThan(sureBeside, sureOnIt)
    }

    // MARK: - The whole path, the way the app walks it

    func testAPressIsAnsweredFromThePackTheStoreOpened() throws {
        // Catalogue on disk, active pack, the file it names, the index, the
        // finding. This is the path AppRuntime takes and the only one that
        // proves `layers/water.bin` is where the store thinks it is.
        let root = try repoRoot().appendingPathComponent("Resources/Packs")
        let store = try PackStore(root: root, box: EventLog())
        XCTAssertEqual(store.active?.id, "tx-west")

        let url = try XCTUnwrap(store.packURL("layers/water.bin"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.path)
        let index = try XCTUnwrap(WaterIndex.load(from: url))
        let finding = MapInspect.resolve(lat: 31.73561, lon: -106.4382, zoom: 16, index: index)
        XCTAssertTrue(finding.isWater)
        XCTAssertTrue(finding.title.contains("Acequia Madre"), finding.title)
    }

    func testEveryShippedPackAnswersFromItsOwnWater() throws {
        let root = try repoRoot().appendingPathComponent("Resources/Packs")
        let store = try PackStore(root: root, box: EventLog())
        for pack in store.catalog.packs {
            try store.switchTo(pack.id)
            let url = try XCTUnwrap(store.packURL("layers/water.bin"), pack.id)
            let index = try XCTUnwrap(WaterIndex.load(from: url), pack.id)
            XCTAssertGreaterThan(index.recordCount, 10_000, pack.id)
            // Somewhere in the middle of the pack, water or not, the answer
            // comes back rather than throwing or hanging.
            let finding = MapInspect.resolve(
                lat: pack.center.lat,
                lon: pack.center.lon,
                zoom: 15,
                index: index
            )
            XCTAssertFalse(finding.title.isEmpty, pack.id)
            XCTAssertFalse(finding.doLine.isEmpty, pack.id)
            XCTAssertFalse(finding.fieldCardID.isEmpty, pack.id)
        }
    }

    func testThePackDecidesTheWaterRatherThanTheLastOneOpened() throws {
        let root = try repoRoot().appendingPathComponent("Resources/Packs")
        let store = try PackStore(root: root, box: EventLog())
        try store.switchTo("nm")
        let nm = try XCTUnwrap(WaterIndex.load(from: store.packURL("layers/water.bin")))
        try store.switchTo("tx-west")
        let tx = try XCTUnwrap(WaterIndex.load(from: store.packURL("layers/water.bin")))
        XCTAssertNotEqual(nm.recordCount, tx.recordCount)
        // An Albuquerque acequia is in the NM pack and not in the TX one.
        XCTAssertNotNil(nm.nearest(lat: 35.10, lon: -106.65, withinMeters: 2_000))
        XCTAssertNil(tx.nearest(lat: 35.10, lon: -106.65, withinMeters: 2_000))
    }

    // MARK: - Field and Mark

    func testTheFieldCardsThePressHandsOffToAreCardsTheAppActuallyShips() throws {
        let root = try repoRoot()
        let book = try Data(contentsOf: root.appendingPathComponent("Resources/Field/field.core.json"))
        let text = try XCTUnwrap(String(data: book, encoding: .utf8))
        for id in [InspectField.water, InspectField.land] {
            XCTAssertTrue(text.contains("\"id\": \"\(id)\""), "field.core.json has no card \(id)")
        }
    }

    func testWaterGoesToTheWaterCardAndGroundToTheNavigationOne() {
        let hit = WaterHit(
            record: WaterRecord(kind: .spring, evidence: .tagged, tag: "natural=spring", name: ""),
            lat: 0,
            lon: 0,
            distanceMeters: 0
        )
        XCTAssertEqual(InspectField.cardID(for: .water(hit)), "water-disinfect")
        XCTAssertEqual(InspectField.cardID(for: .land(nearest: nil)), "nav-lost")
        XCTAssertEqual(InspectField.cardID(for: .land(nearest: hit)), "nav-lost")
    }

    func testTheHandoffNamesTheProcedureBeforeItIsTaken() {
        XCTAssertEqual(InspectField.label(for: InspectField.water), "FIELD · WATER")
        XCTAssertEqual(InspectField.label(for: InspectField.land), "FIELD · LOST")
        XCTAssertEqual(InspectField.label(for: "something-else"), "FIELD")
    }

    func testAMarkKeepsWhatItWasOfWhenThePackIsReadAgain() {
        let relabelled = MarkLabel.relabel(
            existing: "ACEQUIA · Acequia Madre",
            packName: "TX WEST",
            packNames: ["TX WEST", "NM", "TX EAST"],
            offPack: false
        )
        XCTAssertEqual(relabelled, "ACEQUIA · Acequia Madre")
    }

    func testAnInspectMarkOffThePackIsFlaggedWithoutLosingItsName() {
        let flagged = MarkLabel.relabel(
            existing: "STOCK TANK · Fivemile Tank",
            packName: "NM",
            packNames: ["TX WEST", "NM", "TX EAST"],
            offPack: true
        )
        XCTAssertEqual(flagged, "STOCK TANK · Fivemile Tank · OFF PACK")
        XCTAssertEqual(MarkLabel.subject(of: flagged), "STOCK TANK · Fivemile Tank")
    }

    func testAMarkThatOnlyEverSaidWhichPackStillFollowsThePack() {
        // The old behaviour, unchanged: those labels described nothing, so they
        // keep being rewritten exactly as they were before.
        let names = ["TX WEST", "NM", "TX EAST"]
        XCTAssertEqual(
            MarkLabel.relabel(existing: "TX WEST", packName: "NM", packNames: names, offPack: false),
            "NM"
        )
        XCTAssertEqual(
            MarkLabel.relabel(existing: "TX WEST", packName: "NM", packNames: names, offPack: true),
            PackChrome.offPack
        )
        XCTAssertEqual(
            MarkLabel.relabel(existing: PackChrome.offPack, packName: "NM", packNames: names, offPack: false),
            "NM"
        )
    }

    // MARK: - The card keeps the map, and the pin, in view

    func testTheCardNeverTakesMoreThanHalfTheGlass() {
        XCTAssertEqual(InspectCard.maxHeightFraction, 0.5)
        XCTAssertEqual(InspectCard.maxHeight(screenHeight: 800), 400)
    }

    func testAPinAlreadyAboveTheCardDoesNotMoveTheMap() {
        XCTAssertEqual(
            InspectCard.liftPoints(pressY: 100, screenHeight: 800, cardHeight: 400),
            0
        )
    }

    func testAPinUnderTheCardLiftsJustEnoughToClearIt() {
        // 800 tall, 400 of card, 44 of margin: anything below y=356 has to come
        // up to 356 and no further.
        let lift = InspectCard.liftPoints(pressY: 700, screenHeight: 800, cardHeight: 400)
        XCTAssertEqual(lift, 344, accuracy: 1e-9)
        XCTAssertEqual(700 - lift, 800 - 400 - InspectCard.pinMarginPoints, accuracy: 1e-9)
    }

    func testAnOversizedCardIsStillOnlyHalfTheGlassForLiftPurposes() {
        XCTAssertEqual(
            InspectCard.liftPoints(pressY: 700, screenHeight: 800, cardHeight: 5_000),
            InspectCard.liftPoints(pressY: 700, screenHeight: 800, cardHeight: 400),
            accuracy: 1e-9
        )
    }

    func testThePinIsOnlyRedrawnWhenItHasActuallyMoved() {
        XCTAssertFalse(InspectPin.needsReapply(stored: nil, pin: nil))
        XCTAssertTrue(InspectPin.needsReapply(stored: nil, pin: (31.0, -106.0)))
        XCTAssertTrue(InspectPin.needsReapply(stored: (31.0, -106.0), pin: nil))
        XCTAssertFalse(InspectPin.needsReapply(stored: (31.0, -106.0), pin: (31.0, -106.0)))
        XCTAssertTrue(InspectPin.needsReapply(stored: (31.0, -106.0), pin: (31.0, -106.001)))
    }

    func testAMovedPinIsEnoughToMakeTheOverlaysResync() {
        XCTAssertTrue(
            OverlaySync.needsStyleMutation(
                force: false,
                puckNeedsReapply: false,
                routeNeedsReapply: false,
                destinationNeedsReapply: false,
                inspectNeedsReapply: true
            )
        )
        XCTAssertFalse(
            OverlaySync.needsStyleMutation(
                force: false,
                puckNeedsReapply: false,
                routeNeedsReapply: false,
                destinationNeedsReapply: false,
                inspectNeedsReapply: false
            )
        )
    }

    // MARK: - Reading the packs

    private func repoRoot(from file: String = #filePath) throws -> URL {
        var directory = URL(fileURLWithPath: file).deletingLastPathComponent()
        for _ in 0..<12 {
            let catalog = directory.appendingPathComponent("Resources/Packs/catalog.json")
            if FileManager.default.fileExists(atPath: catalog.path) { return directory }
            directory = directory.deletingLastPathComponent()
        }
        throw XCTSkip("no checkout with Resources/Packs above \(file)")
    }

    private func shippedIndexData(_ pack: String) throws -> Data {
        let url = try repoRoot().appendingPathComponent("Resources/Packs/\(pack)/layers/water.bin")
        return try Data(contentsOf: url)
    }
}
