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
    }
}
