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

    func testOneMinuteTimerOverdueAndDone() {
        let b = TimerBoard(box: EventLog())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNotNil(b.add(who: "ALL", task: "1min", duration: 60, subjectAll: true, now: start))
        XCTAssertTrue(b.overduePlate(now: start).isEmpty)
        XCTAssertEqual(b.overduePlate(now: start.addingTimeInterval(61)).count, 1)
        b.markDoneTask("1min")
        XCTAssertTrue(b.overduePlate(now: start.addingTimeInterval(61)).isEmpty)
    }

    func testEmptyWhoBecomesALLAndDoneIsSafe() {
        let b = TimerBoard(box: EventLog())
        let t = b.add(who: "", task: "1min", duration: 60, subjectAll: true)
        XCTAssertEqual(t?.who, "ALL")
        XCTAssertNotEqual(t?.overdueRowID, t?.id)
        b.markDone("missing")
        b.markDoneTask("no-such-task")
        XCTAssertEqual(b.timers.count, 1)
        if let id = t?.id { b.markDone(id) }
        XCTAssertTrue(b.timers.isEmpty)
        XCTAssertFalse(b.isSOS(PartyTimer(id: "x", who: "ALL", task: "1min", duration: 60, started: Date(), subjectAllTurnaround: true)))
    }

    func testOneRowPerTimerTaskAndDoneId() {
        let b = TimerBoard(box: EventLog())
        XCTAssertNotNil(b.add(who: "ALL", task: "1min", duration: 60, subjectAll: true))
        XCTAssertNil(b.add(who: "ALL", task: "1min", duration: 60, subjectAll: true))
        XCTAssertEqual(b.timers.count, 1)
        let id = b.timers[0].id
        b.markDone(id)
        b.markDone(id)
        XCTAssertEqual(b.doneLines(id: id), ["1min ALL DONE"])
        XCTAssertEqual(b.doneLines().count, 1)
    }

    func testNamedTimerProgressAndProfile() {
        let b = TimerBoard(box: EventLog())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNotNil(b.add(who: "Khan", task: "COOK", duration: 60, subjectAll: true, now: start))
        XCTAssertEqual(b.timers[0].remaining(now: start), 60, accuracy: 0.001)
        XCTAssertEqual(b.timers[0].remainingFraction(now: start), 1, accuracy: 0.001)
        XCTAssertEqual(b.timers[0].remainingFraction(now: start.addingTimeInterval(30)), 0.5, accuracy: 0.001)
        XCTAssertEqual(b.timers[0].remaining(now: start.addingTimeInterval(61)), 0, accuracy: 0.001)
        let mine = b.onProfile(personID: "YOU", name: "Khan", isYou: false)
        XCTAssertEqual(mine.map(\.task), ["COOK"])
        XCTAssertTrue(b.onProfile(personID: "peer", name: "Sam", isYou: false).isEmpty)
        XCTAssertNotNil(b.add(who: "ALL", task: "1min", duration: 60, subjectAll: true, now: start))
        XCTAssertEqual(b.onProfile(personID: "YOU", name: "", isYou: true).map(\.task), ["1min"])
        XCTAssertFalse(b.onProfile(personID: "peer", name: "Sam", isYou: false).contains(where: { $0.task == "1min" }))
    }

    func testGroupPresetShowsOnTheSetterProfile() {
        let b = TimerBoard(box: EventLog())
        XCTAssertNotNil(
            b.add(who: "ALL", task: "1min", duration: 60, subjectAll: true, owner: "Khan")
        )
        XCTAssertEqual(
            b.onProfile(personID: "peer-1", name: "Khan", isYou: false).map(\.task),
            ["1min"]
        )
        XCTAssertTrue(b.onProfile(personID: "peer-2", name: "Sam", isYou: false).isEmpty)
        let id = b.timers[0].id
        b.markDone(id)
        XCTAssertEqual(b.doneLines(id: id), ["1min ALL DONE"])
    }
}
