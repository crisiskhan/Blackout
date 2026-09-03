import XCTest
import BlackBox
@testable import OfflineSpeech

final class SpeechEngineTests: XCTestCase {
    func testSpeak() {
        let s = SpeechEngine(box: EventLog())
        s.speak("STOP", locale: "es")
        XCTAssertTrue(s.lastUtterance.contains("STOP"))
    }
}
