import XCTest
import BlackBox
@testable import Instruments

final class InstrumentsTests: XCTestCase {
    func testTorch3() {
        let i = Instruments(box: BlackBox())
        i.torchTap(); i.torchTap(); i.torchTap()
        XCTAssertEqual(i.state.torchClicks, 3)
        i.torchTap()
        XCTAssertEqual(i.state.torchClicks, 0)
    }
}
