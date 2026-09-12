import XCTest
@testable import Tokens

final class TokensTests: XCTestCase {
    func testSOSGeometry() {
        XCTAssertEqual(BlackoutTokens.Chrome.sosDiameter, 64)
        XCTAssertEqual(BlackoutTokens.Chrome.sosHoldMs, 800)
        XCTAssertEqual(BlackoutTokens.Tab.allCases.count, 4)
    }

    func testCrisisPaletteAndTabCaption() {
        XCTAssertEqual(BlackoutTokens.Color.void, BlackoutTokens.RGBA(r: 0, g: 0, b: 0, a: 1))
        XCTAssertEqual(BlackoutTokens.Color.accent, BlackoutTokens.RGBA(r: 225.0 / 255.0, g: 6.0 / 255.0, b: 0, a: 1))
        XCTAssertEqual(BlackoutTokens.Color.sos, BlackoutTokens.Color.accent)
        XCTAssertEqual(BlackoutTokens.Color.warn, BlackoutTokens.Color.silver)
        XCTAssertNotEqual(BlackoutTokens.Color.caution, BlackoutTokens.Color.silver)
        XCTAssertNotEqual(BlackoutTokens.Color.caution, BlackoutTokens.Color.accent)
        XCTAssertGreaterThan(BlackoutTokens.Color.caution.g, 0.45)
        XCTAssertLessThan(BlackoutTokens.Color.caution.b, 0.25)
        XCTAssertEqual(BlackoutTokens.Color.heat, BlackoutTokens.RGBA(r: 0.93, g: 0.32, b: 0.04, a: 1))
        XCTAssertNotEqual(BlackoutTokens.Color.heat, BlackoutTokens.Color.caution)
        XCTAssertNotEqual(BlackoutTokens.Color.heat, BlackoutTokens.Color.accent)
        XCTAssertGreaterThan(BlackoutTokens.Color.heat.r, 0.85)
        XCTAssertLessThan(BlackoutTokens.Color.heat.g, BlackoutTokens.Color.caution.g)
        XCTAssertGreaterThan(BlackoutTokens.Color.heat.g, BlackoutTokens.Color.accent.g)
        XCTAssertEqual(BlackoutTokens.Color.silver.r, BlackoutTokens.Color.metal.r)
        XCTAssertEqual(BlackoutTokens.Color.nightRed.r, 1.0, accuracy: 0.01)
        XCTAssertEqual(BlackoutTokens.Color.nightRed.g, 0.07, accuracy: 0.01)
        XCTAssertLessThan(BlackoutTokens.Color.nightRed.b, 0.05)
        XCTAssertEqual(BlackoutTokens.Chrome.tabCaptionPoints, 10)
        XCTAssertEqual(BlackoutTokens.Chrome.hudMarkPoints, 20)
        XCTAssertEqual(BlackoutTokens.Chrome.hudReticlePoints, 10)
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

    func testMapInstrumentChipsAreDockPlusSheet() {
        XCTAssertEqual(BlackoutTokens.Chrome.bootLogoPoints, 196)
        XCTAssertEqual(BlackoutTokens.Chrome.bootActivateHeight, 56)
        XCTAssertEqual(BlackoutTokens.Chrome.bootMinSeconds, 0.8)
        XCTAssertEqual(BlackoutTokens.Chrome.hudTabReservePoints, 52)
        XCTAssertEqual(BlackoutTokens.Chrome.hudSideReservePoints, 72)
        XCTAssertEqual(BlackoutTokens.Chrome.mapChipHitPoints, 44)
        XCTAssertEqual(BlackoutTokens.MapDock.allCases.count, 4)
        XCTAssertEqual(BlackoutTokens.MapOverlay.instrumentsTitle, "INSTRUMENTS")
        XCTAssertEqual(BlackoutTokens.MapOverlay.lockOnTitle, "LOCK-ON")
        XCTAssertEqual(BlackoutTokens.MapOverlay.lockTitle(locked: false), "LOCK-ON")
        XCTAssertEqual(BlackoutTokens.MapOverlay.lockTitle(locked: true), "LOCKED")
        XCTAssertEqual(
            BlackoutTokens.MapDock.allCases.map(\.title),
            ["MARK", "WALK", "DRIVE", "SPEAK"]
        )
        XCTAssertEqual(
            BlackoutTokens.MapInstrument.allCases.map(\.title),
            ["RULER", "USNG", "MAG/TRUE"]
        )
        XCTAssertTrue(BlackoutTokens.MapDock.walk.requiresGraph)
        XCTAssertTrue(BlackoutTokens.MapDock.drive.requiresGraph)
        XCTAssertFalse(BlackoutTokens.MapDock.mark.requiresGraph)
        XCTAssertFalse(BlackoutTokens.MapDock.speak.requiresGraph)
    }

    func testMapInkIsVoidRedSilver() {
        XCTAssertEqual(BlackoutTokens.MapInk.voidHex, "#000000")
        XCTAssertEqual(BlackoutTokens.MapInk.silverHex, "#B8BDC2")
        XCTAssertEqual(BlackoutTokens.MapInk.accentHex, "#E10600")
        XCTAssertEqual(BlackoutTokens.MapInk.fixHex, "#2EE67A")
        XCTAssertEqual(BlackoutTokens.MapInk.heatHex, "#ED510A")
        XCTAssertEqual(
            BlackoutTokens.Color.fix,
            BlackoutTokens.RGBA(r: 46.0 / 255.0, g: 230.0 / 255.0, b: 122.0 / 255.0, a: 1)
        )
        XCTAssertNotEqual(BlackoutTokens.Color.fix, BlackoutTokens.Color.accent)
        XCTAssertNotEqual(BlackoutTokens.Color.fix, BlackoutTokens.Color.caution)
        XCTAssertGreaterThan(BlackoutTokens.Color.fix.g, 0.7)
        XCTAssertLessThan(BlackoutTokens.Color.fix.r, 0.3)
        XCTAssertEqual(BlackoutTokens.Chrome.destChipBeatSeconds, 1.05)
        XCTAssertEqual(BlackoutTokens.Distance.hud(340), "1115 FT")
        XCTAssertEqual(BlackoutTokens.Distance.hud(12_400), "7.7 MI")
        XCTAssertEqual(BlackoutTokens.Distance.hud(1600), "5249 FT")
        XCTAssertEqual(BlackoutTokens.Distance.hud(1609.344), "1.0 MI")
        XCTAssertEqual(BlackoutTokens.Distance.spoken(200), "656 feet")
        XCTAssertEqual(BlackoutTokens.Distance.spoken(100), "328 feet")
        XCTAssertEqual(BlackoutTokens.Distance.spoken(12_400), "7.7 miles")
        XCTAssertEqual(BlackoutTokens.MapInk.roadLabelMinZoom, 12)
        XCTAssertGreaterThanOrEqual(BlackoutTokens.MapInk.roadLabelWalkingSize, 16)
        XCTAssertGreaterThanOrEqual(
            BlackoutTokens.MapInk.roadLabelCloseWalkSize,
            BlackoutTokens.MapInk.roadLabelWalkingSize
        )
        XCTAssertGreaterThanOrEqual(BlackoutTokens.MapInk.roadLabelHaloWidth, 1.8)
        XCTAssertLessThanOrEqual(BlackoutTokens.MapInk.roadLabelSpacing, 110)
        XCTAssertEqual(BlackoutTokens.MapInk.placeLabelMaxZoom, 16)
    }

    func testMapFieldStaysShortStatusChromeNotAHUD() {
        XCTAssertEqual(BlackoutTokens.Chrome.fieldChromeMaxLines, 3)
        XCTAssertGreaterThan(
            BlackoutTokens.Chrome.mapActionChipTextPoints,
            BlackoutTokens.Chrome.tabCaptionPoints
        )
        XCTAssertGreaterThan(BlackoutTokens.Chrome.mapActionChipGutterPoints, 0)
    }

    func testSOSFABIsCommsOnlyNotBrowseMap() {
        XCTAssertFalse(BlackoutTokens.Chrome.sosFAB(tab: .map, lockOn: false))
        XCTAssertFalse(BlackoutTokens.Chrome.sosFAB(tab: .map, lockOn: true))
        XCTAssertTrue(BlackoutTokens.Chrome.sosFAB(tab: .map, lockOn: false, arranging: true))
        XCTAssertTrue(BlackoutTokens.Chrome.sosFAB(tab: .comms, lockOn: false))
        XCTAssertTrue(BlackoutTokens.Chrome.sosFAB(tab: .comms, lockOn: true))
        XCTAssertFalse(BlackoutTokens.Chrome.sosFAB(tab: .field, lockOn: false))
        XCTAssertFalse(BlackoutTokens.Chrome.sosFAB(tab: .field, lockOn: false, arranging: true))
        XCTAssertFalse(BlackoutTokens.Chrome.sosFAB(tab: .expedition, lockOn: false))
        XCTAssertFalse(BlackoutTokens.Chrome.sosFAB(tab: .expedition, lockOn: false, arranging: true))
    }
}
