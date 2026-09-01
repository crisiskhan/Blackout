import XCTest
@testable import BlackoutCore

final class PackPaintPolicyTests: XCTestCase {
    private let denver = MapRegion(
        name: "Front Range sample",
        centerLatitude: 39.74,
        centerLongitude: -105.3,
        spanLatitude: 0.32,
        spanLongitude: 0.5,
        minZoom: 10,
        maxZoom: 12
    )
    private let texas = MapRegion(
        name: "Texas",
        centerLatitude: 31.17,
        centerLongitude: -100.08,
        spanLatitude: 10.6636,
        spanLongitude: 13.1378,
        minZoom: 8,
        maxZoom: 12
    )
    private let elPaso = MapRegion(
        name: "El Paso",
        centerLatitude: 31.7619,
        centerLongitude: -106.485,
        spanLatitude: 0.8,
        spanLongitude: 0.8,
        minZoom: 10,
        maxZoom: 12
    )
    private let florida = MapRegion(
        name: "Florida",
        centerLatitude: 27.6986,
        centerLongitude: -83.8046,
        spanLatitude: 6.6047,
        spanLongitude: 7.6606,
        minZoom: 8,
        maxZoom: 12
    )

    func testTexasGPSPaintsTexasNotDenver() {
        let regions = [denver, texas]
        let index = PackPaintPolicy.coveringIndex(
            regions: regions,
            latitude: 31.76,
            longitude: -106.48
        )
        XCTAssertEqual(index, 1)
        XCTAssertEqual(regions[index!].name, "Texas")
    }

    func testTightestBBoxWinsOverStatewide() {
        let regions = [denver, texas, elPaso]
        let index = PackPaintPolicy.coveringIndex(
            regions: regions,
            latitude: 31.7619,
            longitude: -106.485
        )
        XCTAssertEqual(index, 2)
        XCTAssertEqual(regions[index!].name, "El Paso")
    }

    func testOutsideAllPacksIsEmptyNotDefault() {
        let regions = [denver, texas]
        let index = PackPaintPolicy.coveringIndex(
            regions: regions,
            latitude: 37.77,
            longitude: -122.42
        )
        XCTAssertNil(index)
        XCTAssertFalse(PackPaintPolicy.paintsDefaultWhenUncovered)
        XCTAssertFalse(PackPaintPolicy.recenterForcesDefaultPack)
    }

    func testNoCoordinateIsEmptyNotDenver() {
        XCTAssertNil(PackPaintPolicy.coveringIndex(regions: [denver, texas], latitude: nil, longitude: nil))
        XCTAssertNil(PackPaintPolicy.coveringIndex(regions: [denver], latitude: 39.74, longitude: nil))
    }

    func testLastKnownFloridaPaintsFlorida() {
        let regions = [denver, texas, florida]
        let index = PackPaintPolicy.coveringIndex(
            regions: regions,
            latitude: 27.77,
            longitude: -82.64
        )
        XCTAssertEqual(regions[index!].name, "Florida")
    }

    func testRecenterUsesSameCoveringRule() {
        let regions = [denver, texas]
        let launch = PackPaintPolicy.coveringIndex(regions: regions, latitude: 29.76, longitude: -95.37)
        let recenter = PackPaintPolicy.coveringIndex(regions: regions, latitude: 29.76, longitude: -95.37)
        XCTAssertEqual(launch, recenter)
        XCTAssertEqual(regions[launch!].name, "Texas")
        XCTAssertFalse(PackPaintPolicy.recenterForcesDefaultPack)
    }
}
