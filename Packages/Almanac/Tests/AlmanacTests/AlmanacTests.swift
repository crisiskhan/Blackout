import XCTest
@testable import Almanac

final class AlmanacTests: XCTestCase {
    func testElPasoJuneHasLongDay() {
        let s = Almanac.sun(lat: 31.76, lon: -106.49, dayOfYear: 172)
        XCTAssertLessThan(s.sunriseHour, s.sunsetHour)
        XCTAssertTrue(Almanac.shadePreferSummer(month: 7))
        XCTAssertFalse(Almanac.shadePreferSummer(month: 1))
    }
}
