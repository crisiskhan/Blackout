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
        XCTAssertEqual(s.channel, "1:1")
    }
}
