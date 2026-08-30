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
}
