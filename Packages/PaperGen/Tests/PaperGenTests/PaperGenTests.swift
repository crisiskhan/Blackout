import XCTest
import TripBrief
import RosterRoles
@testable import PaperGen

final class PaperGenTests: XCTestCase {
    func testExport() {
        let now = Date(timeIntervalSince1970: 1_779_163_200)
        var diary = DiaryLog()
        diary.upsert(DiaryLine(id: "a", from: "lead", name: "A", text: "loop", at: now))
        let roster = PartyRoster.create(lead: "A")
        let text = PaperGen.export(diary: diary, roster: roster, packName: "TX WEST", now: now)
        XCTAssertTrue(text.contains("TX WEST"))
        XCTAssertTrue(text.contains("LEAD A"))
        XCTAssertTrue(text.contains("loop"))
        XCTAssertTrue(text.contains("HERE"))
        XCTAssertFalse(text.contains("due "))
        let silent = PaperGen.export(diary: DiaryLog(), roster: roster, packName: "TX WEST", now: now)
        XCTAssertTrue(silent.contains("SILENT"))
    }
}
