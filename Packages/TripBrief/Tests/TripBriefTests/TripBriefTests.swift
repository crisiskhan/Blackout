import XCTest
@testable import TripBrief

final class TripBriefTests: XCTestCase {
    func testLineStampsTheGivenNow() {
        let now = Date(timeIntervalSince1970: 1_779_163_200)
        let line = DiaryLine(from: "you", name: "YOU", text: "  tank is full  ", at: now)
        XCTAssertEqual(line.text, "tank is full")
        XCTAssertEqual(line.at, now)
    }

    func testFeedIsNewestFirst() {
        var log = DiaryLog()
        log.upsert(DiaryLine(id: "a", from: "you", name: "YOU", text: "morning", at: Date(timeIntervalSince1970: 100)))
        log.upsert(DiaryLine(id: "b", from: "rui", name: "RUI", text: "ridge", at: Date(timeIntervalSince1970: 300)))
        log.upsert(DiaryLine(id: "c", from: "you", name: "YOU", text: "tank", at: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(log.feed().map(\.text), ["ridge", "tank", "morning"])
    }

    func testAttendanceIsHereOrSilentForTheLocalDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = Date(timeIntervalSince1970: 1_779_163_200)
        let yesterday = today.addingTimeInterval(-86_400)
        var log = DiaryLog()
        log.upsert(DiaryLine(id: "a", from: "you", name: "YOU", text: "here", at: today))
        log.upsert(DiaryLine(id: "b", from: "rui", name: "RUI", text: "old", at: yesterday))
        let rows = log.attend(
            roster: [
                (id: "you", name: "YOU"),
                (id: "rui", name: "RUI"),
                (id: "sam", name: "SAM"),
            ],
            now: today,
            calendar: cal
        )
        XCTAssertEqual(rows.map(\.mark), [.here, .silent, .silent])
        XCTAssertEqual(rows.map(\.name), ["YOU", "RUI", "SAM"])
    }
}
