import XCTest
@testable import CommsUI

final class CommsUITests: XCTestCase {
    func testWhisperAndFormUp() {
        var s = CommsState()
        XCTAssertTrue(s.whisperOK)
        s.formUp()
        s.lostKid()
        XCTAssertEqual(s.chips.contains(.formUp), true)
        s.setChannel("1:1")
        XCTAssertEqual(s.channel, "1:1")
    }
}
