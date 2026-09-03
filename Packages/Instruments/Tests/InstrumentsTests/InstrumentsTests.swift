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
}
