import XCTest
import BlackBox
@testable import Instruments

final class InstrumentBoardTests: XCTestCase {
    func testTorch3() {
        let i = InstrumentBoard(box: EventLog())
        i.torchTap(); i.torchTap(); i.torchTap()
        XCTAssertEqual(i.state.torchClicks, 3)
        i.torchTap()
        XCTAssertEqual(i.state.torchClicks, 0)
    }

    func testToggleMagTrueFlipsNorthReference() {
        let i = InstrumentBoard(box: EventLog())
        XCTAssertTrue(i.state.magNorth)
        i.toggleMagTrue()
        XCTAssertFalse(i.state.magNorth)
        i.toggleMagTrue()
        XCTAssertTrue(i.state.magNorth)
    }
}
