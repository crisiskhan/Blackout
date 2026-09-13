import XCTest
@testable import NightRed

final class NightRedTests: XCTestCase {
    func testFilter() {
        let on = NightRedState(enabled: true)
        XCTAssertEqual(on.filter.r, 1, accuracy: 0.01)
        XCTAssertEqual(on.filter.g, 0.07, accuracy: 0.02)
        XCTAssertLessThan(on.filter.b, 0.05)
        XCTAssertEqual(on.filter, on.multiply)
        let off = NightRedState(enabled: false)
        XCTAssertEqual(off.multiply, NightRedState.identity)
        XCTAssertEqual(off.filter.g, 1, accuracy: 0.01)
        XCTAssertLessThan(NightRedState.dim, 0)
        XCTAssertGreaterThan(NightRedState.dim, -0.12)
    }
}
