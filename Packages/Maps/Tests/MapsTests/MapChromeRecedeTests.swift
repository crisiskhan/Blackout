import XCTest
@testable import MapsChrome

final class MapChromeRecedeTests: XCTestCase {
    func testIdleTwoSecondsRecedesChrome() {
        var chrome = MapChromeRecede(now: 0)
        XCTAssertFalse(chrome.isReceded)
        chrome.tick(at: 1.99)
        XCTAssertFalse(chrome.isReceded)
        chrome.tick(at: 2)
        XCTAssertTrue(chrome.isReceded)
    }

    func testActivityRestoresImmediately() {
        var chrome = MapChromeRecede(now: 0)
        chrome.tick(at: 2)
        XCTAssertTrue(chrome.isReceded)
        chrome.noteActivity(at: 2.1)
        XCTAssertFalse(chrome.isReceded)
    }

    func testReduceMotionNeverRecedes() {
        var chrome = MapChromeRecede(reduceMotion: true, now: 0)
        chrome.tick(at: 10)
        XCTAssertFalse(chrome.isReceded)
    }

    func testReduceMotionRestoresIfAlreadyReceded() {
        var chrome = MapChromeRecede(now: 0)
        chrome.tick(at: 2)
        XCTAssertTrue(chrome.isReceded)
        chrome.reduceMotion = true
        chrome.tick(at: 3)
        XCTAssertFalse(chrome.isReceded)
    }

    func testIdleIntervalIsTwoSeconds() {
        XCTAssertEqual(MapChromeRecede.idleInterval, 2)
    }

    func testMotionDurationsMatchDesignLock() {
        XCTAssertEqual(MapChromeRecede.fadeDuration, 0.220)
        XCTAssertEqual(MapChromeRecede.restoreDuration, 0.120)
    }

    func testHoldBlocksRecede() {
        var chrome = MapChromeRecede(now: 0)
        chrome.hold = true
        chrome.tick(at: 10)
        XCTAssertFalse(chrome.isReceded)
    }

    func testHoldRestartsIdleAfterRelease() {
        var chrome = MapChromeRecede(now: 0)
        chrome.hold = true
        chrome.tick(at: 5)
        chrome.hold = false
        chrome.tick(at: 5)
        XCTAssertFalse(chrome.isReceded)
        chrome.tick(at: 6.9)
        XCTAssertFalse(chrome.isReceded)
        chrome.tick(at: 7)
        XCTAssertTrue(chrome.isReceded)
    }

    func testScaleBarNiceMeters() {
        XCTAssertEqual(MapScaleBarMath.niceMeters(metersPerPoint: 1, targetPoints: 80), 50)
        XCTAssertEqual(MapScaleBarMath.niceMeters(metersPerPoint: 10, targetPoints: 80), 500)
        XCTAssertEqual(MapScaleBarMath.niceMeters(metersPerPoint: 20, targetPoints: 80), 1_000)
    }
}
