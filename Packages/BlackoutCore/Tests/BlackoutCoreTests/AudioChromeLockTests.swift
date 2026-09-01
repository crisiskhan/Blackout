import XCTest
@testable import BlackoutCore

final class AudioChromeLockTests: XCTestCase {
    func testWalkLockVoiceIsInterruptibleAndDoesNotRestartOnRender() {
        XCTAssertTrue(AudioChromeLock.walkSpeakButton)
        XCTAssertTrue(AudioChromeLock.lockVoiceWhileLocked)
        XCTAssertEqual(AudioChromeLock.lockVoiceInterval, 2.2, accuracy: 0.001)
        XCTAssertEqual(AudioChromeLock.speechRateMin, 0.47, accuracy: 0.001)
        XCTAssertEqual(AudioChromeLock.speechRateMax, 0.52, accuracy: 0.001)
        XCTAssertEqual(AudioChromeLock.clampedLockRate(0.50), 0.50, accuracy: 0.001)
        XCTAssertEqual(AudioChromeLock.clampedLockRate(0.10), 0.47, accuracy: 0.001)
        XCTAssertEqual(AudioChromeLock.clampedLockRate(0.90), 0.52, accuracy: 0.001)
        XCTAssertTrue(AudioChromeLock.interruptible)
        XCTAssertFalse(AudioChromeLock.restartsTimerOnRender)
        XCTAssertTrue(AudioChromeLock.speakUsesLockPhrase(isLocked: true, hasTarget: true))
        XCTAssertFalse(AudioChromeLock.speakUsesLockPhrase(isLocked: false, hasTarget: true))
        XCTAssertFalse(AudioChromeLock.speakUsesLockPhrase(isLocked: true, hasTarget: false))
    }

    func testFieldAskAndPTTStayAirplane() {
        XCTAssertTrue(AudioChromeLock.fieldAskMic)
        XCTAssertTrue(AudioChromeLock.fieldAskMicDenyFallsBackToType)
        XCTAssertTrue(AudioChromeLock.fieldAskSpokenStep)
        XCTAssertFalse(AudioChromeLock.fieldAskUsesWAN)
        XCTAssertTrue(FieldAskHomeLock.micDenyFallsBackToType)
        XCTAssertTrue(FieldAskHomeLock.requiresOnDeviceRecognition)
        XCTAssertFalse(FieldAskHomeLock.usesURLSession)
        XCTAssertTrue(AudioChromeLock.pttOnComms)
        XCTAssertFalse(AudioChromeLock.pttOnMap)
        XCTAssertFalse(AudioChromeLock.sosSpeakOnChrome)
        XCTAssertFalse(AudioChromeLock.cloudTTS)
        XCTAssertTrue(RootChromeLock.sosChromeDeleted)
        XCTAssertFalse(RootChromeLock.liveActivitySOSEnabled)
    }
}
