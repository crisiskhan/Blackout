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
}
