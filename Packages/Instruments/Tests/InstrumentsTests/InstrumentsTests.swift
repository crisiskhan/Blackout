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

    func testFiveSpeakVoicesAndUnknownFallsToSteel() {
        let i = InstrumentBoard(box: EventLog())
        XCTAssertEqual(NavVoice.allCases.count, 5)
        XCTAssertEqual(NavVoice.steel.title, "STEEL")
        XCTAssertEqual(NavVoice.night.title, "NIGHT")
        XCTAssertEqual(NavVoice.range.title, "RANGE")
        XCTAssertEqual(NavVoice.mesh.title, "MESH")
        XCTAssertEqual(NavVoice.desert.title, "DESERT")
        XCTAssertEqual(NavVoice.parse(nil), .steel)
        XCTAssertEqual(NavVoice.parse("ghost"), .steel)
        i.setVoice(.desert)
        XCTAssertEqual(i.state.voice, .desert)
        i.setVoice(.steel)
        XCTAssertEqual(i.state.voice, .steel)
        XCTAssertFalse(NavVoice.desert.rate > NavVoice.range.rate)
        XCTAssertGreaterThan(NavVoice.desert.postDelay, NavVoice.range.postDelay)
    }
}
