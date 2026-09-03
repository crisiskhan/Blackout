import XCTest
import BlackBox
@testable import OfflineSpeech

final class OfflineSpeechTests: XCTestCase {
    func testSpeak() {
        let s = OfflineSpeech(box: BlackBox())
        s.speak("STOP", locale: "es")
        XCTAssertTrue(s.lastUtterance.contains("STOP"))
    }
}
