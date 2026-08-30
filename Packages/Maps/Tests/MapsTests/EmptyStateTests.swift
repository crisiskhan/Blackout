import XCTest
@testable import MapsRouting

final class EmptyStateTests: XCTestCase {
    func testExactEmptyCopy() {
        XCTAssertEqual(NavigateCopy.noGraphTitle, "No turns in this pack.")
        XCTAssertEqual(NavigateCopy.noGraphBody, "El Paso pack has routing; this pack does not.")
        XCTAssertEqual(NavigateCopy.offGraph, "Off pack. Bearing to destination.")
        XCTAssertEqual(NavigateCopy.searchMiss, "No matches in this pack.")
        XCTAssertEqual(NavigateCopy.noGPS, "No GPS.")
        XCTAssertEqual(NavigateCopy.bearingOnly, "Bearing only")
        XCTAssertEqual(NavigateCopy.packManager, "Pack manager")
        XCTAssertEqual(NavigateEmpty.noGraph.title, "No turns in this pack.")
        XCTAssertEqual(NavigateEmpty.noGraph.body, "El Paso pack has routing; this pack does not.")
        XCTAssertEqual(NavigateEmpty.offGraph.title, "Off pack. Bearing to destination.")
        XCTAssertEqual(NavigateEmpty.searchMiss.title, "No matches in this pack.")
        XCTAssertEqual(NavigateEmpty.noGPS.title, "No GPS.")
        XCTAssertEqual(NavigateEmpty.noCivilization.title, "No civilization in this pack")
        XCTAssertEqual(NavigateEmpty.noWater.title, "No water mapped here")
        XCTAssertEqual(MapEmptyCopy.noTiles, "No tiles for this location")
        XCTAssertEqual(MapEmptyCopy.noPack, "No pack for this area")
    }

    func testSearchHitAndMissWithoutNetwork() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ToyRouting.writePack(to: root)
        let pack = try XCTUnwrap(RoutingPackLoader.load(packRoot: root))
        let pois = [
            RoutingPOI(id: "civic", name: "Civic Center", kind: "poi", coordinate: ToyRouting.n1)
        ]
        let hit = PackSearch.query("mesa", pack: pack, pois: pois)
        XCTAssertNil(hit.empty)
        XCTAssertEqual(hit.hits.first?.title, "Mesa Street")
        let poi = PackSearch.query("civic", pack: pack, pois: pois)
        XCTAssertEqual(poi.hits.first?.title, "Civic Center")
        let miss = PackSearch.query("zzzz", pack: pack, pois: pois)
        XCTAssertTrue(miss.hits.isEmpty)
        XCTAssertEqual(miss.empty, .searchMiss)
        let noGraph = PackSearch.query("mesa", pack: nil, pois: pois)
        XCTAssertEqual(noGraph.empty, .noGraph)
        XCTAssertTrue(noGraph.hits.isEmpty)
    }

    func testVoicePromptDoesNotInventTurns() {
        let arrive = Maneuver(
            kind: .arrive,
            streetName: nil,
            distanceMeters: 0,
            coordinate: ToyRouting.n2
        )
        XCTAssertEqual(VoicePrompt.phrase(for: arrive, distanceMeters: 0), "You have arrived")
        let left = Maneuver(
            kind: .left,
            streetName: "Mesa Street",
            distanceMeters: 80,
            coordinate: ToyRouting.n1
        )
        XCTAssertEqual(VoicePrompt.phrase(for: left, distanceMeters: 80), "In 80 meters, turn left onto Mesa Street")
    }

    func testGuidanceOffRouteAsksOnPackRerouteOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ToyRouting.writePack(to: root)
        let pack = try XCTUnwrap(RoutingPackLoader.load(packRoot: root))
        let routed = PackRouter.route(from: ToyRouting.n0, to: ToyRouting.n1, profile: .drive, pack: pack)
        guard case .routed(let route) = routed else {
            return XCTFail("need a route")
        }
        let far = RoutingCoordinate(latitude: 31.80, longitude: -106.40)
        let tick = Guidance.tick(position: far, route: route, pack: pack, canReroute: true)
        XCTAssertTrue(tick.offRoute)
        XCTAssertEqual(tick.reroute, .offGraph)
    }
}
