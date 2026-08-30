import XCTest
@testable import BlackoutCore

final class BrandChromeLockTests: XCTestCase {
    func testLockedAssetsStayOriginalWordmarkAndRedEyeO() {
        XCTAssertEqual(BrandChromeLock.wordmarkAsset, "Wordmark")
        XCTAssertEqual(BrandChromeLock.redEyeOAsset, "RedEyeO")
        XCTAssertFalse(BrandChromeLock.redEyeOIsTemplate)
        XCTAssertFalse(BrandChromeLock.usesLockupInApp)
        XCTAssertFalse(BrandChromeLock.typesetsBlackoutInSFPro)
        XCTAssertFalse(BrandChromeLock.substitutesSFSymbolForO)
    }

    func testSplashUsesWordmarkOnVoidThenMap() {
        XCTAssertEqual(BrandChromeLock.splashWordmarkMaxWidth, 280)
        XCTAssertEqual(BrandChromeLock.splashHoldSeconds, 1.2)
        XCTAssertLessThanOrEqual(BrandChromeLock.splashHoldSeconds, 1.2)
        XCTAssertFalse(BrandChromeLock.splashHasEmblem)
        XCTAssertFalse(BrandChromeLock.splashHasLockup)
        XCTAssertFalse(BrandChromeLock.splashUsesStandaloneRedEyeO)
        XCTAssertEqual(RootChromeLock.coldLaunchDestination, "map")
    }

    func testReduceMotionNeverPulsesTheO() {
        XCTAssertFalse(BrandChromeLock.splashPulsesO(reduceMotion: true))
        XCTAssertFalse(BrandChromeLock.splashPulsesO(reduceMotion: false))
    }

    func testAboutWordmarkSitsAboveCallsign() {
        XCTAssertEqual(BrandChromeLock.aboutWordmarkMaxWidth, 240)
        XCTAssertEqual(BrandChromeLock.aboutTitle, "About")
        XCTAssertLessThan(BrandChromeLock.aboutWordmarkMaxWidth, BrandChromeLock.splashWordmarkMaxWidth)
    }

    func testRedEyeOLivesOnConfirmCoverAndNoPackOnly() {
        XCTAssertEqual(BrandChromeLock.sosConfirmRedEye, 48)
        XCTAssertEqual(BrandChromeLock.noPackRedEye, 24)
        XCTAssertFalse(BrandChromeLock.fabShowsRedEyeO)
        XCTAssertEqual(SOSChrome.fab, 88)
        XCTAssertEqual(BrandChromeLock.markSurfaces, [
            "splash-wordmark",
            "about-wordmark",
            "sos-confirm",
            "map-empty-no-pack"
        ])
        XCTAssertTrue(BrandChromeLock.forbiddenMarkSurfaces.contains("sos-fab-disk"))
        XCTAssertTrue(BrandChromeLock.forbiddenMarkSurfaces.contains("tab-bar"))
        XCTAssertTrue(BrandChromeLock.forbiddenMarkSurfaces.contains("map-empty-no-turns"))
        XCTAssertTrue(BrandChromeLock.forbiddenMarkSurfaces.contains("map-empty-no-civ"))
        XCTAssertTrue(BrandChromeLock.forbiddenMarkSurfaces.contains("map-empty-no-water"))
        XCTAssertTrue(BrandChromeLock.forbiddenMarkSurfaces.contains("guide-cards"))
        XCTAssertTrue(BrandChromeLock.forbiddenMarkSurfaces.contains("packs-plate"))
        XCTAssertTrue(BrandChromeLock.forbiddenMarkSurfaces.contains("comms-bubbles"))
    }
}
