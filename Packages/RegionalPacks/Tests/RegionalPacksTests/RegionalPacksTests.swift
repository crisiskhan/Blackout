import XCTest
@testable import RegionalPacks

final class RegionalPacksTests: XCTestCase {
    func testBannersStayOnGroundWeShip() {
        XCTAssertTrue(RegionalPacks.assertNoLeaks())
        XCTAssertEqual(RegionalPacks.shippedStates, ["TX", "NM"])
        XCTAssertTrue(RegionalPacks.visible(state: "FL").isEmpty)
        XCTAssertTrue(RegionalPacks.visible(state: "NY").isEmpty)
        XCTAssertTrue(RegionalPacks.visible(state: "TX").map(\.id).contains("heat-island"))
        XCTAssertTrue(RegionalPacks.visible(state: "NM").map(\.id).contains("monsoon"))
    }
}
