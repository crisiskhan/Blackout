import XCTest
import BlackBox
@testable import BatteryAuction

final class BatteryAuctionTests: XCTestCase {
    func testModes() {
        let a = BatteryAuction(box: BlackBox())
        XCTAssertFalse(a.state.screenBuffer)
        a.set(.search)
        XCTAssertEqual(a.state.mode, .search)
        XCTAssertTrue(a.hotSparePayload().contains("hotspare"))
    }
}
