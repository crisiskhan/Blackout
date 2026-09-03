import XCTest
import BlackBox
@testable import BatteryAuction

final class AuctionBoardTests: XCTestCase {
    func testModes() {
        let a = AuctionBoard(box: EventLog())
        XCTAssertFalse(a.state.screenBuffer)
        a.set(.search)
        XCTAssertEqual(a.state.mode, .search)
        XCTAssertTrue(a.hotSparePayload().contains("hotspare"))
    }
}
