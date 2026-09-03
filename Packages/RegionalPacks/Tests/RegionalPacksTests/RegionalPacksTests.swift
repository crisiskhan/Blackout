import XCTest
@testable import RegionalPacks

final class RegionalPacksTests: XCTestCase {
    func testNoCrossCoastLeaks() {
        XCTAssertTrue(RegionalPacks.assertNoLeaks())
        XCTAssertFalse(RegionalPacks.visible(state: "FL").map(\.id).contains("ice-rock"))
        XCTAssertFalse(RegionalPacks.visible(state: "NY").map(\.id).contains("gator-dusk"))
        XCTAssertTrue(RegionalPacks.visible(state: "FL").map(\.id).contains("gator-dusk"))
    }
}
