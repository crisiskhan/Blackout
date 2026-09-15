import XCTest
@testable import Almanac

final class AlmanacTests: XCTestCase {
    func testElPasoJuneHasLongDay() {
        let s = Almanac.sun(lat: 31.76, lon: -106.49, dayOfYear: 172)
        XCTAssertLessThan(s.sunriseHour, s.sunsetHour)
        XCTAssertTrue(Almanac.shadePreferSummer(month: 7))
        XCTAssertFalse(Almanac.shadePreferSummer(month: 1))
    }

    func testClockUsesThePhoneZone() {
        let tz = TimeZone(secondsFromGMT: -7 * 3600)!
        XCTAssertEqual(Almanac.clock(19.0, now: Date(timeIntervalSince1970: 0), timeZone: tz), "12:00")
    }
}
