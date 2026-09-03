import XCTest
import BlackBox
@testable import TimerSync

final class TimerSyncTests: XCTestCase {
    func testMax4AndOverdueNotSOS() {
        let b = TimerBoard(box: EventLog())
        for i in 0..<4 { XCTAssertNotNil(b.add(who: "p\(i)", task: "water", duration: 7200, subjectAll: true)) }
        XCTAssertNil(b.add(who: "x", task: "x", duration: 1, subjectAll: false))
        let t = b.timers[0]
        XCTAssertFalse(b.isSOS(t))
        let old = Date().addingTimeInterval(-7300)
        let late = PartyTimer(id: "1", who: "a", task: "water", duration: 7200, started: old, subjectAllTurnaround: true)
        XCTAssertTrue(late.overdue)
    }
}
