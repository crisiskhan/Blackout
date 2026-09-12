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
        i.setTrueNorth()
        XCTAssertFalse(i.state.magNorth)
    }

    func testBodyAttachesAndCalibrates() {
        let i = InstrumentBoard(box: EventLog())
        XCTAssertFalse(i.state.compassCalibrated)
        XCTAssertFalse(i.state.usbCPTT)
        XCTAssertFalse(i.state.externalGNSS)
        i.calibrateCompass()
        i.attachUSB_C_PTT(true)
        i.attachGNSSPuck(true)
        XCTAssertTrue(i.state.compassCalibrated)
        XCTAssertTrue(i.state.usbCPTT)
        XCTAssertTrue(i.state.externalGNSS)
        i.attachUSB_C_PTT(false)
        i.attachGNSSPuck(false)
        XCTAssertFalse(i.state.usbCPTT)
        XCTAssertFalse(i.state.externalGNSS)
    }
}
