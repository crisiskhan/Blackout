import XCTest
@testable import BlackoutCore

final class SOSConfirmTests: XCTestCase {
    func testConfirmActionsStayInSpecOrder() {
        XCTAssertEqual(SOSConfirmAction.allCases.map(\.title), [
            "SPEAK SOS",
            "SPEAK LOCATION",
            "SHARE",
            "COPY",
            "CALL 911",
            "STROBE",
        ])
        XCTAssertEqual(SOSConfirmAction.visualStrobe.stopTitle, "STOP")
    }

    func testShareMessageStartsWithBLACKOUTPlusCoords() {
        let fix = LocationFix(latitude: 31.76190, longitude: -106.48500)
        XCTAssertEqual(SOSConfirm.coordsLine(fix), "31.76190, -106.48500")
        XCTAssertEqual(SOSConfirm.shareMessage(fix: fix), "BLACKOUT 31.76190, -106.48500")
        XCTAssertTrue(SOSConfirm.shareMessage(fix: fix).hasPrefix("BLACKOUT"))
        XCTAssertEqual(SOSConfirm.shareMessage(fix: nil), "BLACKOUT NO FIX")
        XCTAssertEqual(SOSConfirm.speakSOS, "SOS")
        XCTAssertEqual(SOSConfirm.speakLocation(fix), "31.76190, -106.48500")
    }

    func testCall911IsTelLinkNotAutoDial() {
        XCTAssertEqual(SOSConfirm.emergencyTel, "tel:911")
        XCTAssertFalse(SOSConfirm.autoDials911)
        XCTAssertFalse(SOSConfirm.autoInvokesSystemEmergencySOS)
    }

    func testStrobeIs330msPulseOrReduceMotionSolid() {
        XCTAssertEqual(SOSConfirm.strobePeriodMs, 330)
        XCTAssertEqual(SOSConfirm.reduceMotionOpacity, 0.55, accuracy: 0.001)
        XCTAssertEqual(SOSConfirm.holdSeconds, 1.5)
    }

    func testFabSitsTabBarPlusEightAndChipClearsDisk() {
        XCTAssertEqual(SOSChrome.fab, 88)
        XCTAssertEqual(SOSChrome.chip, 56)
        XCTAssertEqual(SOSChrome.gap, 8)
        XCTAssertEqual(SOSChrome.trailing, 16)
        XCTAssertEqual(SOSChrome.tabBar, 49)
        XCTAssertEqual(SOSChrome.homeIndicator, 34)
        XCTAssertEqual(SOSChrome.fabBottomInset(hasTabBar: true), 8 + 49)
        XCTAssertEqual(SOSChrome.fabBottomInset(hasTabBar: false), 8)
        XCTAssertEqual(SOSChrome.chipDiskClearance, 88 + 8)
        XCTAssertGreaterThanOrEqual(SOSChrome.chipDiskClearance - SOSChrome.fab, SOSChrome.gap)
        XCTAssertGreaterThanOrEqual(SOSChrome.horizontalGap, 8)
        XCTAssertFalse(BrandChromeLock.fabShowsRedEyeO)
        XCTAssertEqual(BrandChromeLock.sosConfirmRedEye, 200)
        XCTAssertGreaterThan(BrandChromeLock.sosConfirmRedEye, 48)
    }

    func testCrisisLockCoverUsesFullEyeAndThumbZoneSOSNotTheMapFAB() {
        XCTAssertEqual(BrandChromeLock.sosConfirmRedEye, 200)
        XCTAssertGreaterThan(BrandChromeLock.sosConfirmRedEye, 48)
        XCTAssertFalse(BrandChromeLock.sosConfirmShowsSOSWordUnderEye)
        XCTAssertFalse(BrandChromeLock.sosConfirmStacksSOSDiskUnderEye)
        XCTAssertFalse(BrandChromeLock.sosConfirmUsesLockup)
        XCTAssertFalse(BrandChromeLock.sosConfirmUsesEmblem)
        XCTAssertFalse(BrandChromeLock.fabShowsRedEyeO)
        XCTAssertEqual(SOSChrome.fab, 88)
        XCTAssertEqual(SOSChrome.confirmHit, 64)
        XCTAssertNotEqual(SOSChrome.confirmHit, SOSChrome.fab)
        XCTAssertTrue(SOSChrome.confirmHit == 56 || SOSChrome.confirmHit == 64)
        XCTAssertEqual(SOSChrome.confirmThumbZone, 0.34, accuracy: 0.0001)
        XCTAssertEqual(SOSChrome.confirmPhrase, "SLIDE TO CONFIRM")
        XCTAssertTrue(SOSChrome.confirmKnobIsSOS)
        XCTAssertEqual(SOSCrisisLockControl.allCases.map(\.title), [
            "CANCEL",
            "STROBE",
            "SPEAK COORDS",
            "SHARE",
            "CALL 911",
        ])
        XCTAssertNil(SOSCrisisLockControl.cancel.confirmAction)
        XCTAssertEqual(SOSCrisisLockControl.strobe.confirmAction, .visualStrobe)
        XCTAssertEqual(SOSCrisisLockControl.speakCoords.confirmAction, .speakLocation)
        XCTAssertEqual(SOSCrisisLockControl.share.confirmAction, .sharePosition)
        XCTAssertEqual(SOSCrisisLockControl.call911.confirmAction, .call911)
        XCTAssertEqual(SOSCrisisLockControl.allCases.map(\.symbol), [
            "xmark",
            "sun.max.fill",
            "plus.viewfinder",
            "square.and.arrow.up",
            "phone.fill",
        ])
        XCTAssertFalse(SOSConfirm.autoDials911)
        XCTAssertFalse(SOSConfirm.autoInvokesSystemEmergencySOS)
        XCTAssertEqual(SOSConfirm.emergencyTel, "tel:911")
        XCTAssertEqual(RootChromeLock.tabCount, 4)
    }

    func testStrobeOrCallSendsMeshKindSOSWhenPeersExist() {
        XCTAssertEqual(SOSConfirm.meshKind, .sosAlert)
        XCTAssertEqual(SOSConfirm.meshKind.rawValue, "sosAlert")
        XCTAssertTrue(SOSConfirm.shouldSendMesh(peerCount: 1))
        XCTAssertFalse(SOSConfirm.shouldSendMesh(peerCount: 0))
        let envelope = SOSConfirm.meshEnvelope(
            sender: BlackoutID(),
            recipient: BlackoutID(),
            callsign: "RIDGE"
        )
        XCTAssertEqual(envelope.kind, .sosAlert)
        XCTAssertEqual(SOSMeshBody.callsign(in: envelope.ciphertext), "RIDGE")
    }

    @MainActor
    func testStrobeOrCallMarksLocalInjuryRedWithoutTwoTap() {
        let roster = PartyRoster(
            localID: BlackoutID(),
            defaults: UserDefaults(suiteName: "sos-injury-\(UUID().uuidString)")!
        )
        XCTAssertFalse(roster.isRed)
        XCTAssertFalse(roster.selfStatus.injury)
        let party = roster.markInjured(fix: LocationFix(latitude: 31.76, longitude: -106.48))
        XCTAssertTrue(roster.isRed)
        XCTAssertTrue(roster.selfStatus.injury)
        XCTAssertEqual(roster.selfStatus.band, .red)
        XCTAssertEqual(party?.kind, .partyStatus)
        XCTAssertNotEqual(party?.kind, .sosAlert)
        XCTAssertFalse(PartyVitals.redFiresSOS)
        XCTAssertNil(roster.pending)
    }

    func testNewBinaryLaunchDoesNotAutoPresentPersistedArmedOverlay() {
        XCTAssertTrue(SOSArmedRestore.isNewBinaryLaunch(currentBuild: "30", lastSeenBuild: nil))
        XCTAssertTrue(SOSArmedRestore.isNewBinaryLaunch(currentBuild: "30", lastSeenBuild: "25"))
        XCTAssertTrue(SOSArmedRestore.isNewBinaryLaunch(currentBuild: "", lastSeenBuild: "30"))
        XCTAssertFalse(SOSArmedRestore.isNewBinaryLaunch(currentBuild: "30", lastSeenBuild: "30"))
        XCTAssertFalse(SOSArmedRestore.shouldAutoPresentArmedOverlay(
            persistedArmed: true,
            presentRequested: true,
            newBinaryLaunch: true
        ))
        XCTAssertFalse(SOSArmedRestore.shouldAutoPresentArmedOverlay(
            persistedArmed: true,
            presentRequested: false,
            newBinaryLaunch: false
        ))
        XCTAssertFalse(SOSArmedRestore.shouldAutoPresentArmedOverlay(
            persistedArmed: false,
            presentRequested: true,
            newBinaryLaunch: false
        ))
        XCTAssertFalse(SOSArmedRestore.shouldAutoPresentArmedOverlay(
            persistedArmed: true,
            presentRequested: true,
            newBinaryLaunch: false
        ))
        XCTAssertFalse(SOSArmedRestore.autoPresentOnColdLaunch)
        XCTAssertFalse(LaunchLock.persistedSOSArmedStealsFirstOpen)
        XCTAssertFalse(SOSArmedRestore.shouldRequestConfirmAfterMissedCheckIn(
            persistedArmed: true,
            newBinaryLaunch: true
        ))
        XCTAssertTrue(SOSArmedRestore.shouldRequestConfirmAfterMissedCheckIn(
            persistedArmed: false,
            newBinaryLaunch: true
        ))
        XCTAssertFalse(SOSArmedRestore.shouldRequestConfirmAfterMissedCheckIn(
            persistedArmed: true,
            newBinaryLaunch: false
        ))
    }

    func testColdLaunchLandsOnUnlockNotArmedOrBitmap() {
        XCTAssertEqual(RootChromeLock.coldLaunchDestination, "unlock")
        XCTAssertEqual(LaunchLock.destination, "unlock")
        XCTAssertFalse(LaunchLock.usesBitmapLockUI)
        XCTAssertFalse(LaunchLock.usesFullScreenLockImage)
        XCTAssertTrue(LaunchLock.usesLockupImage)
        XCTAssertFalse(LaunchLock.metalRingIsSwiftUI)
        XCTAssertTrue(LaunchLock.sliderHasSOSTwin)
        XCTAssertTrue(LaunchLock.handleIsMetal)
        XCTAssertFalse(LaunchLock.sosTwinIsMapFAB)
        XCTAssertEqual(LaunchLock.trackHit, 56)
        XCTAssertEqual(LaunchLock.handleHit, 56)
        XCTAssertEqual(LaunchLock.sosTwinHit, 56)
        XCTAssertEqual(LaunchLock.trackHit, LaunchLock.sosTwinHit)
        XCTAssertNotEqual(LaunchLock.sosTwinHit, SOSChrome.fab)
        XCTAssertEqual(LaunchLock.phrase, "SLIDE TO UNLOCK")
        XCTAssertFalse(LaunchLock.slideArmsSOS)
        XCTAssertTrue(LaunchLock.twinHoldPresentsUnarmedCover)
        XCTAssertFalse(LaunchLock.twinHoldArmsSOS)
        XCTAssertEqual(LaunchLock.twinHoldSeconds, SOSChrome.holdSeconds)
        XCTAssertEqual(LaunchLock.twinHoldSeconds, 1.5)
        XCTAssertFalse(LaunchLock.coldLaunchShowsSplash)
        XCTAssertFalse(LaunchLock.persistedSOSArmedStealsFirstOpen)
        XCTAssertFalse(LaunchLock.startsSensorsBeforeUnlock)
        XCTAssertFalse(LaunchLock.startsLiveActivityBeforeUnlock)
        XCTAssertFalse(LaunchLock.sosFabMountsOnLockFrame)
        XCTAssertFalse(LaunchLock.startsRadioProbeBeforeUnlock)
        XCTAssertFalse(LaunchLock.touchesLiveActivityOnNewBinary)
        XCTAssertFalse(LaunchLock.walksAllTilesOnBoot)
        XCTAssertFalse(RootChromeLock.sosOverlayMounts(isUnlocked: false, coverRequested: false))
        XCTAssertTrue(RootChromeLock.sosOverlayMounts(isUnlocked: false, coverRequested: true))
        XCTAssertTrue(RootChromeLock.sosOverlayMounts(isUnlocked: true, coverRequested: false))
        XCTAssertFalse(LiveActivityPolicy.shouldTouchActivityKit(newBinaryLaunch: true))
        XCTAssertTrue(LiveActivityPolicy.shouldTouchActivityKit(newBinaryLaunch: false))
        XCTAssertFalse(SOSConfirm.autoDials911)
        XCTAssertEqual(RootChromeLock.tabCount, 4)
        XCTAssertEqual(SOSChrome.fab, 88)
        XCTAssertEqual(BrandChromeLock.lockupMaxPoint, 280)
    }

    func testDismissArmedPanelDoesNotDisarm() {
        XCTAssertFalse(SOSArmedRestore.dismissDisarms)
        XCTAssertEqual(BlackoutKeys.sosArmed, "com.crisiskhan.blackout.sos.armed")
        XCTAssertEqual(BlackoutKeys.sosLastSeenBuild, "com.crisiskhan.blackout.sos.lastSeenBuild")
    }

    func testArmedOverlayAppearIsIdleWithZeroPeersAndNoFix() {
        XCTAssertFalse(SOSConfirm.shouldSendMesh(peerCount: 0))
        XCTAssertEqual(SOSConfirm.speakLocation(nil), SOSConfirm.noFix)
        XCTAssertEqual(SOSConfirm.shareMessage(fix: nil), "BLACKOUT NO FIX")
        XCTAssertEqual(SOSConfirm.coordsLine(nil), SOSConfirm.noFix)
        XCTAssertFalse(SOSArmedRestore.appearStartsSpeech)
        XCTAssertFalse(SOSArmedRestore.appearStartsStrobe)
        XCTAssertFalse(SOSArmedRestore.appearRequiresPeers)
        XCTAssertFalse(SOSArmedRestore.appearRequiresLocation)
    }
}
