import XCTest
import BlackBox
@testable import OfflineSpeech

final class SpeechEngineTests: XCTestCase {
    func testSpeak() {
        let s = SpeechEngine(box: EventLog())
        _ = s.speak("STOP", locale: "es")
        XCTAssertTrue(s.lastUtterance.contains("STOP"))
    }

    func testEmptySpeakIsFailureNotFakeAudio() {
        let s = SpeechEngine(box: EventLog())
        XCTAssertFalse(s.speak("   ", locale: "en"))
        XCTAssertTrue(s.lastFailed)
        XCTAssertTrue(s.lastUtterance.contains("SPEECH FAILED") || s.lastFailed)
    }
}
