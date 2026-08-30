import XCTest
@testable import MapsRouting

final class PackFindTests: XCTestCase {
    private let elPaso = RoutingBBox(
        west: RoutingLayout.ElPaso.west,
        south: RoutingLayout.ElPaso.south,
        east: RoutingLayout.ElPaso.east,
        north: RoutingLayout.ElPaso.north
    )
    private let origin = RoutingCoordinate(latitude: 31.7619, longitude: -106.4850)

    func testMatchesPackKindsOnly() {
        XCTAssertTrue(PackFind.matches(kind: "road", mode: .civilization))
        XCTAssertTrue(PackFind.matches(kind: "rail", mode: .civilization))
        XCTAssertTrue(PackFind.matches(kind: "town", mode: .civilization))
        XCTAssertTrue(PackFind.matches(kind: "mill", mode: .civilization))
        XCTAssertTrue(PackFind.matches(kind: "city", mode: .civilization))
        XCTAssertTrue(PackFind.matches(kind: "spring", mode: .water))
        XCTAssertTrue(PackFind.matches(kind: "tank", mode: .water))
        XCTAssertTrue(PackFind.matches(kind: "water", mode: .water))
        XCTAssertFalse(PackFind.matches(kind: "spring", mode: .civilization))
        XCTAssertFalse(PackFind.matches(kind: "town", mode: .water))
        XCTAssertFalse(PackFind.matches(kind: "summit", mode: .civilization))
        XCTAssertFalse(PackFind.matches(kind: "trailhead", mode: .water))
    }

    func testCivilizationScoresTownAheadOfFartherRoad() {
        let pois = [
            poi("road-near", "Farm road", "road", origin),
            poi("town-far", "Anthony", "town", RoutingCoordinate(latitude: 31.7889, longitude: -106.5983)),
        ]
        let result = PackFind.query(
            mode: .civilization,
            origin: origin,
            packBounds: elPaso,
            pois: pois
        )
        XCTAssertNil(result.empty)
        XCTAssertEqual(result.hits.map(\.title), ["Anthony", "Farm road"])
        XCTAssertEqual(result.hits.map(\.kind), ["town", "road"])
        XCTAssertFalse(result.hits.contains(where: { $0.title == "El Paso invented" }))
    }

    func testWaterScoresSpringAheadOfNamedWater() {
        let pois = [
            poi("res", "Rio Grande", "water", origin),
            poi("sp", "Hueco Spring", "spring", RoutingCoordinate(latitude: 31.7700, longitude: -106.4800)),
            poi("tk", "Ranch tank", "tank", RoutingCoordinate(latitude: 31.7650, longitude: -106.4820)),
        ]
        let result = PackFind.query(
            mode: .water,
            origin: origin,
            packBounds: elPaso,
            pois: pois
        )
        XCTAssertNil(result.empty)
        XCTAssertEqual(result.hits.map(\.kind), ["spring", "tank", "water"])
    }

    func testEmptyWhenPackHasNoMatchingKind() {
        let pois = [
            poi("peak", "Franklin", "summit", origin),
            poi("th", "Trailhead", "trailhead", origin),
        ]
        let civ = PackFind.query(mode: .civilization, origin: origin, packBounds: elPaso, pois: pois)
        XCTAssertTrue(civ.hits.isEmpty)
        XCTAssertEqual(civ.empty, .noCivilization)
        XCTAssertEqual(civ.empty?.title, MapEmptyCopy.noCivilization)
        let water = PackFind.query(mode: .water, origin: origin, packBounds: elPaso, pois: pois)
        XCTAssertTrue(water.hits.isEmpty)
        XCTAssertEqual(water.empty, .noWater)
        XCTAssertEqual(water.empty?.title, MapEmptyCopy.noWater)
    }

    func testOutsidePackIsTheSameHonestEmpty() {
        let denverTown = poi(
            "denver",
            "Denver",
            "city",
            RoutingCoordinate(latitude: 39.7392, longitude: -104.9903)
        )
        let kansas = RoutingCoordinate(latitude: 38.5, longitude: -98.0)
        let result = PackFind.query(
            mode: .civilization,
            origin: kansas,
            packBounds: elPaso,
            pois: [denverTown]
        )
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertEqual(result.empty, .noCivilization)
        XCTAssertEqual(result.empty?.title, MapEmptyCopy.noCivilization)
    }

    func testAirplaneUsesLastKnownOrPinWithoutInventing() {
        let pin = RoutingCoordinate(latitude: 31.7700, longitude: -106.4900)
        let pois = [
            poi("mill", "Cotton mill", "mill", RoutingCoordinate(latitude: 31.7720, longitude: -106.4910)),
            poi("fake", "Should not appear", "summit", pin),
        ]
        let result = PackFind.query(
            mode: .civilization,
            origin: pin,
            packBounds: elPaso,
            pois: pois
        )
        XCTAssertNil(result.empty)
        XCTAssertEqual(result.hits.map(\.title), ["Cotton mill"])
        XCTAssertEqual(result.hits.first?.meters ?? 0, Geo.haversine(pin, pois[0].coordinate), accuracy: 1)
    }

    func testMissingOriginStillListsPackPoints() {
        let pois = [poi("town", "Socorro", "town", origin)]
        let result = PackFind.query(
            mode: .civilization,
            origin: nil,
            packBounds: elPaso,
            pois: pois
        )
        XCTAssertNil(result.empty)
        XCTAssertEqual(result.hits.map(\.title), ["Socorro"])
        XCTAssertNil(result.hits.first?.meters)
    }

    func testNeverInventWhenPOIListIsEmpty() {
        let result = PackFind.query(
            mode: .civilization,
            origin: origin,
            packBounds: elPaso,
            pois: []
        )
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertEqual(result.empty, .noCivilization)
    }

    func testMapEmptyCopyIsExact() {
        XCTAssertEqual(MapEmptyCopy.eyebrow, "MAP")
        XCTAssertEqual(MapEmptyCopy.noPack, "No pack for this area")
        XCTAssertEqual(MapEmptyCopy.noTiles, "No tiles for this location")
        XCTAssertEqual(MapEmptyCopy.noTurns, "No turns for this area")
        XCTAssertEqual(MapEmptyCopy.noCivilization, "No civilization in this pack")
        XCTAssertEqual(MapEmptyCopy.noWater, "No water mapped here")
        XCTAssertEqual(MapEmptyCopy.packTooNew, "Pack too new.")
        XCTAssertEqual(MapEmptyKind.noPack.title, MapEmptyCopy.noPack)
        XCTAssertTrue(MapEmptyKind.noPack.showsRedEyeO)
        XCTAssertFalse(MapEmptyKind.noTurns.showsRedEyeO)
        XCTAssertFalse(MapEmptyKind.noCivilization.showsRedEyeO)
        XCTAssertFalse(MapEmptyKind.noWater.showsRedEyeO)
        XCTAssertFalse(MapEmptyKind.packTooNew.showsRedEyeO)
        XCTAssertEqual(MapEmptyKind.packTooNew.title, "Pack too new.")
        XCTAssertEqual(NavigateEmpty.noGraph.mapKind, .noTurns)
        XCTAssertEqual(NavigateEmpty.noCivilization.mapKind, .noCivilization)
        XCTAssertEqual(NavigateEmpty.noWater.mapKind, .noWater)
        XCTAssertEqual(NavigateEmpty.packTooNew.mapKind, .packTooNew)
    }

    func testSteerRoutesWhenRoutingCoversOtherwiseLockOn() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pf-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ToyRouting.writePack(to: root)
        let pack = try XCTUnwrap(RoutingPackLoader.load(packRoot: root))
        XCTAssertEqual(
            PackFind.action(
                destination: ToyRouting.n1,
                origin: ToyRouting.n0,
                pack: pack,
                profile: .walk
            ),
            .route
        )
        XCTAssertEqual(
            PackFind.action(
                destination: ToyRouting.n1,
                origin: ToyRouting.n0,
                pack: nil,
                profile: .walk
            ),
            .lockOn
        )
        let far = RoutingCoordinate(latitude: 39.74, longitude: -104.99)
        XCTAssertEqual(
            PackFind.action(
                destination: far,
                origin: ToyRouting.n0,
                pack: pack,
                profile: .walk
            ),
            .lockOn
        )
    }

    func testCopyStaysPackLocal() {
        XCTAssertEqual(PackFindCopy.civilization, "Find civilization")
        XCTAssertEqual(PackFindCopy.water, "Find water")
        XCTAssertEqual(PackFindCopy.empty, NavigateCopy.searchMiss)
        XCTAssertEqual(PackFindCopy.subtitle, "Pack points only. No geocoder, no network.")
    }

    private func poi(
        _ id: String,
        _ name: String,
        _ kind: String,
        _ coordinate: RoutingCoordinate
    ) -> RoutingPOI {
        RoutingPOI(id: id, name: name, kind: kind, coordinate: coordinate)
    }
}
