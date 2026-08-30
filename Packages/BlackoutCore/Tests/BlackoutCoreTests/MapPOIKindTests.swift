import XCTest
@testable import BlackoutCore

final class MapPOIKindTests: XCTestCase {
    func testCivilizationKindsIncludePackRoadsAndTowns() {
        XCTAssertTrue(poi("road").isCivilization)
        XCTAssertTrue(poi("rail").isCivilization)
        XCTAssertTrue(poi("town").isCivilization)
        XCTAssertTrue(poi("mill").isCivilization)
        XCTAssertTrue(poi("city").isCivilization)
        XCTAssertFalse(poi("spring").isCivilization)
        XCTAssertFalse(poi("summit").isCivilization)
    }

    func testWaterKindsIncludeSpringTankAndNamedWater() {
        XCTAssertTrue(poi("spring").isWater)
        XCTAssertTrue(poi("tank").isWater)
        XCTAssertTrue(poi("water").isWater)
        XCTAssertFalse(poi("town").isWater)
        XCTAssertFalse(poi("road").isWater)
    }

    func testAmenityKindsAreStoresNotAddresses() {
        XCTAssertTrue(poi("restaurant").isAmenity)
        XCTAssertTrue(poi("cafe").isAmenity)
        XCTAssertTrue(poi("grocery").isAmenity)
        XCTAssertTrue(poi("fuel").isAmenity)
        XCTAssertTrue(poi("lodging").isAmenity)
        XCTAssertTrue(poi("restaurant").isCivilization)
        XCTAssertFalse(poi("summit").isAmenity)
        XCTAssertFalse(poi("address").isAmenity)
    }

    private func poi(_ kind: String) -> MapPOI {
        MapPOI(id: kind, name: kind, kind: kind, latitude: 0, longitude: 0)
    }
}
