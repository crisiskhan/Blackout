import XCTest
@testable import Tokens

final class TokensTests: XCTestCase {
    func testSOSGeometry() {
        XCTAssertEqual(BlackoutTokens.Chrome.sosDiameter, 56)
        XCTAssertEqual(BlackoutTokens.Chrome.sosHoldMs, 800)
        XCTAssertEqual(BlackoutTokens.Tab.allCases.count, 4)
    }
}
