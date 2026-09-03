import XCTest
@testable import TripBrief

final class TripBriefTests: XCTestCase {
    func testDue() {
        let s = TripBrief.make(brief: "water run", hours: 2, now: Date().addingTimeInterval(-3 * 3600))
        XCTAssertTrue(s.overdue())
    }
}
