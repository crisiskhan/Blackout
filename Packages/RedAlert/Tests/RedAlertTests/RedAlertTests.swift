import XCTest
import Vitals
import BlackBox
@testable import RedAlert

final class RedAlertTests: XCTestCase {
    func testCancel() {
        let p = RedPlate(box: EventLog())
        p.apply(PartyVitals(water: 0.9, fatigue: 0.2, weatherExposure: 0.1))
        XCTAssertTrue(p.isRed)
        p.cancelRED()
        XCTAssertTrue(p.cancelled)
        XCTAssertFalse(p.isRed)
        XCTAssertFalse(p.isSOS())
    }

    func testCancelWhenNotRedIsSafeAndNotSOS() {
        let box = EventLog()
        let p = RedPlate(box: box)
        p.apply(PartyVitals(water: 0.2, fatigue: 0.2, weatherExposure: 0.2))
        XCTAssertFalse(p.isRed)
        p.cancelRED()
        XCTAssertFalse(p.isRed)
        XCTAssertTrue(p.cancelled)
        XCTAssertFalse(p.isSOS())
        XCTAssertFalse(box.all().contains { $0.detail.contains("911") || $0.kind == "sos" })
    }
}
