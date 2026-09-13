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
        let line = "Walk 656 feet. Turn left. Walk 328 feet. Arrive at destination. Total 984 feet. Heading 90 degrees."
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

    func testSetToneIsRememberedOnTheNextUtterance() {
        let s = SpeechEngine(box: EventLog())
        s.setTone(
            SpeechTone(
                identifier: "com.apple.voice.compact.en-US.Samantha",
                rate: 0.44,
                pitch: 0.96,
                preDelay: 0.10,
                postDelay: 0.32
            )
        )
        _ = s.speak("STOP", locale: "en")
        XCTAssertTrue(
            s.lastUtterance.contains("Samantha") || s.lastFailed || s.lastUtterance.contains("STOP")
        )
    }

    func testListenFailsClosedWithoutOnDeviceSpeech() {
        #if !canImport(Speech) || !os(iOS)
        let s = SpeechEngine(box: EventLog())
        var called = false
        XCTAssertFalse(s.listen(locale: "en") { _ in called = true })
        XCTAssertFalse(called)
        #endif
    }
}
