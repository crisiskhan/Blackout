import XCTest
@testable import CommsUI

final class CommsUITests: XCTestCase {
    func testWhisperAndFormUp() {
        var s = CommsState()
        XCTAssertTrue(s.whisperOK)
        s.formUp()
        s.lostKid()
        s.sos()
        XCTAssertEqual(s.chips.contains(.formUp), true)
        XCTAssertEqual(s.chips.contains(.sos), true)
        s.setChannel("1:1")
        XCTAssertEqual(s.channel, "1:1")
    }

    func testRailIsTheTenFieldWords() {
        XCTAssertEqual(Chip.rail.count, 10)
        XCTAssertEqual(
            Chip.rail,
            [.here, .wait, .moving, .come, .rally, .down, .hurt, .water, .lost, .found]
        )
        XCTAssertFalse(Chip.rail.contains(.sos))
        XCTAssertFalse(Chip.rail.contains(.ok))
        XCTAssertFalse(Chip.rail.contains(.formUp))
        XCTAssertFalse(Chip.rail.contains(.lostKid))
        XCTAssertFalse(Chip.rail.contains(.overdue))
        XCTAssertEqual(Chip(rawValue: "formUp"), .formUp)
        XCTAssertEqual(Chip(rawValue: "lostKid"), .lostKid)
        XCTAssertEqual(Chip.here.wordKey, "chip.here")
        XCTAssertEqual(Chip.found.wordKey, "chip.found")
        XCTAssertEqual(Chip.ok.wordKey, "ok.chip")
        var s = CommsState()
        s.here()
        s.found()
        XCTAssertEqual(s.chips, [.here, .found])
    }

    func testRadioCheckDoesNotInventAPeer() {
        var s = CommsState()
        s.radioCheck()
        XCTAssertFalse(s.radioCheckOK)
        s.radioCheck(heard: true)
        XCTAssertTrue(s.radioCheckOK)
        XCTAssertEqual(s.meshTo(nearby: []), "*")
        s.setChannel("1:1")
        XCTAssertEqual(s.meshTo(nearby: []), "*")
        XCTAssertEqual(s.meshTo(nearby: ["A", "B"]), "A")
        s.pickPeer("B")
        XCTAssertEqual(s.meshTo(nearby: ["A", "B"]), "B")
        XCTAssertEqual(s.meshTo(nearby: []), "B")
        XCTAssertEqual(s.channel, "1:1")
        s.pickPeer("YOU")
        XCTAssertEqual(s.meshTo(nearby: []), "YOU")
        XCTAssertEqual(s.meshTo(nearby: ["A", "B"]), "YOU")
    }
}
