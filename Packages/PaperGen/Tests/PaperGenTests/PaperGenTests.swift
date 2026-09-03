import XCTest
import TripBrief
import RosterRoles
@testable import PaperGen

final class PaperGenTests: XCTestCase {
    func testExport() {
        let text = PaperGen.export(trip: TripBrief.make(brief: "loop", hours: 2), roster: PartyRoster.create(lead: "A"), packName: "TX WEST")
        XCTAssertTrue(text.contains("TX WEST"))
        XCTAssertTrue(text.contains("lead A"))
    }
}
