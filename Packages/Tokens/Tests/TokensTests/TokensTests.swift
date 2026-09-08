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

    func testMapInstrumentChipsAreSixFortyFourPointTargets() {
        XCTAssertEqual(BlackoutTokens.Chrome.mapChipHitPoints, 44)
        XCTAssertEqual(BlackoutTokens.MapChip.allCases.count, 6)
        XCTAssertEqual(
            BlackoutTokens.MapChip.allCases.map(\.rawValue),
            ["mark", "walk", "drive", "ruler", "usng", "magTrue"]
        )
        XCTAssertEqual(
            BlackoutTokens.MapChip.allCases.map(\.title),
            ["MARK", "WALK", "DRIVE", "RULER", "USNG", "MAG/TRUE"]
        )
        XCTAssertTrue(BlackoutTokens.MapChip.walk.requiresGraph)
        XCTAssertTrue(BlackoutTokens.MapChip.drive.requiresGraph)
        XCTAssertFalse(BlackoutTokens.MapChip.mark.requiresGraph)
        XCTAssertFalse(BlackoutTokens.MapChip.ruler.requiresGraph)
        XCTAssertFalse(BlackoutTokens.MapChip.usng.requiresGraph)
        XCTAssertFalse(BlackoutTokens.MapChip.magTrue.requiresGraph)
    }

    func testMapInkIsVoidRedSilver() {
        XCTAssertEqual(BlackoutTokens.MapInk.voidHex, "#000000")
        XCTAssertEqual(BlackoutTokens.MapInk.silverHex, "#B8BDC2")
        XCTAssertEqual(BlackoutTokens.MapInk.accentHex, "#E10600")
        XCTAssertEqual(BlackoutTokens.MapInk.roadLabelMinZoom, 12)
        XCTAssertGreaterThanOrEqual(BlackoutTokens.MapInk.roadLabelWalkingSize, 16)
        XCTAssertGreaterThanOrEqual(BlackoutTokens.MapInk.roadLabelHaloWidth, 1.8)
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
