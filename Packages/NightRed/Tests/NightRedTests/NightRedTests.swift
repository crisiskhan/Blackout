import XCTest
@testable import NightRed

final class NightRedTests: XCTestCase {
    func testFilter() {
        XCTAssertEqual(NightRedState(enabled: true).filter.r, 0.55, accuracy: 0.01)
    }
}
