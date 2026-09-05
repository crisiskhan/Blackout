import XCTest
@testable import Tokens

final class TokensTests: XCTestCase {
    func testSOSGeometry() {
        XCTAssertEqual(BlackoutTokens.Chrome.sosDiameter, 56)
        XCTAssertEqual(BlackoutTokens.Chrome.sosHoldMs, 800)
        XCTAssertEqual(BlackoutTokens.Tab.allCases.count, 4)
    }

    func testCrisisPaletteAndTabCaption() {
        XCTAssertEqual(BlackoutTokens.Color.void, BlackoutTokens.RGBA(r: 0, g: 0, b: 0, a: 1))
        XCTAssertEqual(BlackoutTokens.Color.accent, BlackoutTokens.RGBA(r: 225.0 / 255.0, g: 6.0 / 255.0, b: 0, a: 1))
        XCTAssertEqual(BlackoutTokens.Color.sos, BlackoutTokens.Color.accent)
        XCTAssertEqual(BlackoutTokens.Color.silver.r, BlackoutTokens.Color.metal.r)
        XCTAssertEqual(BlackoutTokens.Chrome.tabCaptionPoints, 10)
    }
}
