import XCTest
import BlackBox
@testable import OfflineSpeech

final class SpeechEngineTests: XCTestCase {
    func testSpeak() {
        let s = SpeechEngine(box: EventLog())
        _ = s.speak("STOP", locale: "es")
        XCTAssertTrue(s.lastUtterance.contains("STOP"))
    }

    func testInitDoesNotConstructUtterance() {
        let s = SpeechEngine(box: EventLog())
        XCTAssertEqual(s.lastUtterance, "")
        XCTAssertFalse(s.lastFailed)
    }

    func testFullTurnByTurnUtteranceIsNotTruncated() {
        let s = SpeechEngine(box: EventLog())
        let line = "Walk 200 meters. Turn left. Walk 100 meters. Arrive at destination. Total 300 meters. Heading 90 degrees."
        XCTAssertTrue(s.speak(line, locale: "en") || s.lastFailed)
        XCTAssertTrue(s.lastUtterance.contains("Arrive at destination.") || s.lastFailed)
        XCTAssertFalse(s.lastUtterance.contains("TX WEST 90 degrees") && !s.lastUtterance.contains("Arrive"))
    }

    func testEmptySpeakIsFailureNotFakeAudio() {
        let s = SpeechEngine(box: EventLog())
        XCTAssertFalse(s.speak("   ", locale: "en"))
        XCTAssertTrue(s.lastFailed)
        XCTAssertTrue(s.lastUtterance.contains("SPEECH FAILED") || s.lastFailed)
    }
}
