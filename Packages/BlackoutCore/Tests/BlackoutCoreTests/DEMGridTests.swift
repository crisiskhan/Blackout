import XCTest
@testable import BlackoutCore

final class DEMGridTests: XCTestCase {
    func testEmptyAxesReturnNil() {
        XCTAssertNil(DEMGrid.sample(latitude: 39.7, longitude: -105.3, lons: [], lats: [39.7], grid: [[1]]))
        XCTAssertNil(DEMGrid.sample(latitude: 39.7, longitude: -105.3, lons: [-105.3], lats: [], grid: []))
    }

    func testJaggedGridReturnsNil() {
        let value = DEMGrid.sample(
            latitude: 39.7,
            longitude: -105.3,
            lons: [-105.4, -105.2],
            lats: [39.6, 39.8],
            grid: [[1_600]]
        )
        XCTAssertNil(value)
    }

    func testValidCellReturnsInterpolatedElevation() {
        let value = DEMGrid.sample(
            latitude: 39.7,
            longitude: -105.3,
            lons: [-105.4, -105.2],
            lats: [39.6, 39.8],
            grid: [
                [1_600, 1_700],
                [1_800, 1_900]
            ]
        )
        XCTAssertEqual(value ?? 0, 1_750, accuracy: 1)
    }
}
