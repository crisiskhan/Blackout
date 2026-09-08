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

    func testMapStillScoreBarIsFiveBarsOnly() {
        XCTAssertEqual(BlackoutTokens.MapStillBar.allCases.count, 5)
        XCTAssertEqual(
            BlackoutTokens.MapStillBar.allCases.map(\.rawValue),
            [
                "full-height canvas",
                "pack outline+puck",
                "single MARK",
                "no CALL SOS on browse MAP",
                "no solid-red slab",
            ]
        )
        XCTAssertEqual(
            BlackoutTokens.MapStillBar.scoreBar,
            "[full-height canvas] [pack outline+puck] [single MARK] [no CALL SOS on browse MAP] [no solid-red slab]"
        )
    }

    func testSOSFABIsCommsOnlyNotBrowseMap() {
        XCTAssertFalse(BlackoutTokens.Chrome.sosFAB(tab: .map, lockOn: false))
        XCTAssertFalse(BlackoutTokens.Chrome.sosFAB(tab: .map, lockOn: true))
        XCTAssertTrue(BlackoutTokens.Chrome.sosFAB(tab: .comms, lockOn: false))
        XCTAssertTrue(BlackoutTokens.Chrome.sosFAB(tab: .comms, lockOn: true))
        XCTAssertFalse(BlackoutTokens.Chrome.sosFAB(tab: .field, lockOn: false))
        XCTAssertFalse(BlackoutTokens.Chrome.sosFAB(tab: .expedition, lockOn: false))
    }
}
