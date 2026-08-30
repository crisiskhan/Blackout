import XCTest
@testable import BlackoutCore

final class BrandChromeLockTests: XCTestCase {
    func testLockedAssetsStayOriginalWordmarkAndRedEyeO() {
        XCTAssertEqual(BrandChromeLock.wordmarkAsset, "Wordmark")
        XCTAssertEqual(BrandChromeLock.redEyeOAsset, "RedEyeO")
        XCTAssertEqual(BrandChromeLock.lockupAsset, "Lockup")
        XCTAssertEqual(BrandChromeLock.lockupMaxPoint, 280)
        XCTAssertFalse(BrandChromeLock.redEyeOIsTemplate)
        XCTAssertTrue(BrandChromeLock.usesLockupInApp)
        XCTAssertTrue(LaunchLock.usesLockupImage)
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
        XCTAssertEqual(RootChromeLock.coldLaunchDestination, "unlock")
        XCTAssertFalse(LaunchLock.coldLaunchShowsSplash)
        XCTAssertFalse(LaunchLock.usesBitmapLockUI)
    }

    func testReduceMotionNeverPulsesTheO() {
        XCTAssertFalse(BrandChromeLock.splashPulsesO(reduceMotion: true))
        XCTAssertFalse(BrandChromeLock.splashPulsesO(reduceMotion: false))
    }

    func testAboutWordmarkSitsAboveCallsign() {
        XCTAssertEqual(BrandChromeLock.aboutWordmarkMaxWidth, 240)
        XCTAssertEqual(BrandChromeLock.aboutTitle, "About")
        XCTAssertLessThan(BrandChromeLock.aboutWordmarkMaxWidth, BrandChromeLock.splashWordmarkMaxWidth)
        XCTAssertEqual(BrandChromeLock.wordmarkAsset, "Wordmark")
        XCTAssertTrue(BrandChromeLock.aboutUsesSameWordmarkPNG)
        XCTAssertEqual(BrandChromeLock.aboutPlateRadius, 12)
        XCTAssertEqual(BrandChromeLock.aboutPlateEdge, 1)
        XCTAssertEqual(BrandChromeLock.aboutPlateSunEdge, 2)
        XCTAssertEqual(BrandChromeLock.aboutPlateEdgeWidth(sun: false), 1)
        XCTAssertEqual(BrandChromeLock.aboutPlateEdgeWidth(sun: true), 2)
        XCTAssertFalse(BrandChromeLock.aboutPlateHasDropShadow)
    }

    func testRedEyeOLivesOnConfirmCoverAndNoPackOnly() {
        XCTAssertEqual(BrandChromeLock.sosConfirmRedEye, 200)
        XCTAssertGreaterThan(BrandChromeLock.sosConfirmRedEye, 48)
        XCTAssertFalse(BrandChromeLock.sosConfirmShowsSOSWordUnderEye)
        XCTAssertFalse(BrandChromeLock.sosConfirmStacksSOSDiskUnderEye)
        XCTAssertFalse(BrandChromeLock.sosConfirmUsesLockup)
        XCTAssertFalse(BrandChromeLock.sosConfirmUsesEmblem)
        XCTAssertTrue(BrandChromeLock.usesLockupInApp)
        XCTAssertEqual(BrandChromeLock.lockupAsset, "Lockup")
        XCTAssertEqual(BrandChromeLock.noPackRedEye, 24)
        XCTAssertFalse(BrandChromeLock.fabShowsRedEyeO)
        XCTAssertEqual(SOSChrome.fab, 88)
        XCTAssertEqual(BrandChromeLock.markSurfaces, [
            "splash-wordmark",
            "about-wordmark",
            "sos-confirm",
            "map-empty-no-pack",
            "lock-gate"
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
