import XCTest
@testable import BlackoutCore

final class SOSConfirmTests: XCTestCase {
    func testConfirmActionsStayInSpecOrder() {
        XCTAssertEqual(SOSConfirmAction.allCases.map(\.title), [
            "SPEAK SOS",
            "SPEAK MY LOCATION",
            "SHARE POSITION",
            "COPY COORDS",
            "CALL 911",
            "VISUAL SOS STROBE",
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
        XCTAssertEqual(SOSChrome.fabBottomInset(hasTabBar: true), 8 + 49 + 34)
        XCTAssertEqual(SOSChrome.fabBottomInset(hasTabBar: false), 8 + 34)
        XCTAssertEqual(SOSChrome.chipDiskClearance, 88 + 8)
        XCTAssertGreaterThanOrEqual(SOSChrome.chipDiskClearance - SOSChrome.fab, SOSChrome.gap)
        XCTAssertGreaterThanOrEqual(SOSChrome.horizontalGap, 8)
    }

    func testStrobeOrCallSendsMeshKindSOSWhenPeersExist() {
        XCTAssertEqual(SOSConfirm.meshKind, .sosAlert)
        XCTAssertEqual(SOSConfirm.meshKind.rawValue, "sosAlert")
        XCTAssertTrue(SOSConfirm.shouldSendMesh(peerCount: 1))
        XCTAssertFalse(SOSConfirm.shouldSendMesh(peerCount: 0))
        let envelope = SOSConfirm.meshEnvelope(sender: BlackoutID(), recipient: BlackoutID())
        XCTAssertEqual(envelope.kind, .sosAlert)
        XCTAssertEqual(envelope.ciphertext, Data("sos".utf8))
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
}
