import XCTest
@testable import BlackoutCore

final class ConvenienceHitsTests: XCTestCase {
    func testIdleTimerOnOffTransitions() {
        let heard = Date()
        XCTAssertTrue(
            IdleTimerPolicy.shouldDisable(
                navLockOn: true,
                pttTransmitting: false,
                pttLastHeard: nil,
                sosCoverPresented: false,
                inboundImDownOpen: false
            )
        )
        XCTAssertTrue(
            IdleTimerPolicy.shouldDisable(
                navLockOn: false,
                pttTransmitting: true,
                pttLastHeard: nil,
                sosCoverPresented: false,
                inboundImDownOpen: false
            )
        )
        XCTAssertTrue(
            IdleTimerPolicy.shouldDisable(
                navLockOn: false,
                pttTransmitting: false,
                pttLastHeard: heard,
                sosCoverPresented: false,
                inboundImDownOpen: false,
                now: heard.addingTimeInterval(4.9)
            )
        )
        XCTAssertFalse(
            IdleTimerPolicy.shouldDisable(
                navLockOn: false,
                pttTransmitting: false,
                pttLastHeard: heard,
                sosCoverPresented: false,
                inboundImDownOpen: false,
                now: heard.addingTimeInterval(5.1)
            )
        )
        XCTAssertTrue(
            IdleTimerPolicy.shouldDisable(
                navLockOn: false,
                pttTransmitting: false,
                pttLastHeard: nil,
                sosCoverPresented: true,
                inboundImDownOpen: false
            )
        )
        XCTAssertTrue(
            IdleTimerPolicy.shouldDisable(
                navLockOn: false,
                pttTransmitting: false,
                pttLastHeard: nil,
                sosCoverPresented: false,
                inboundImDownOpen: true
            )
        )
        XCTAssertFalse(
            IdleTimerPolicy.shouldDisable(
                navLockOn: false,
                pttTransmitting: false,
                pttLastHeard: nil,
                sosCoverPresented: false,
                inboundImDownOpen: false
            )
        )
    }

    func testBannerDismissedPersistenceUntilRadiosRecover() {
        var policy = MeshRadioBannerPolicy()
        XCTAssertTrue(policy.shouldShow(cannotRun: true))
        policy.applyRadios(cannotRun: true)
        policy.dismiss()
        XCTAssertFalse(policy.shouldShow(cannotRun: true))
        XCTAssertTrue(policy.dismissed)

        policy.applyRadios(cannotRun: true)
        XCTAssertTrue(policy.dismissed)
        XCTAssertFalse(policy.shouldShow(cannotRun: true))

        policy.applyRadios(cannotRun: false)
        XCTAssertFalse(policy.dismissed)
        XCTAssertFalse(policy.shouldShow(cannotRun: false))

        policy.applyRadios(cannotRun: true)
        XCTAssertTrue(policy.shouldShow(cannotRun: true))
    }

    func testPingSpeakDoesNotFireForOutbound() {
        XCTAssertFalse(FieldPing.shouldSpeak(isOutbound: true))
        XCTAssertTrue(FieldPing.shouldSpeak(isOutbound: false))
        XCTAssertEqual(
            FieldPing.announcePhrase(callsign: "Raven", id: .down),
            "Raven. I'm down."
        )
        XCTAssertEqual(FieldPing.speechRate, 0.50, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(FieldPing.speechRate, FieldPing.speechRateMin)
        XCTAssertLessThanOrEqual(FieldPing.speechRate, FieldPing.speechRateMax)
        XCTAssertEqual(FieldPing.haptic(.ok), .light)
        XCTAssertEqual(FieldPing.haptic(.warn), .medium)
        XCTAssertEqual(FieldPing.haptic(.red), .heavy)
        XCTAssertEqual(FieldPing.hapticRepeats(.danger), 1)
        XCTAssertEqual(FieldPing.hapticRepeats(.down), 2)
        XCTAssertFalse(FieldPing.shouldPlayHaptic(supportsHaptics: false))
    }

    func testReturnDisabledWithNoStart() {
        XCTAssertFalse(MapQuickNav.returnEnabled(hasStart: false))
        XCTAssertEqual(MapQuickNav.returnDisabledReason(hasStart: false), "No start fix this outing.")
        XCTAssertTrue(MapQuickNav.returnEnabled(hasStart: true))
        XCTAssertNil(MapQuickNav.returnDisabledReason(hasStart: true))
        XCTAssertFalse(MapQuickNav.lastMarkEnabled(hasMark: false))
        XCTAssertEqual(MapQuickNav.lastMarkDisabledReason(hasMark: false), "No MARK yet.")
        XCTAssertNil(
            MapQuickNav.outingStart(
                crumbs: [(nil, nil)],
                startLatitude: nil,
                startLongitude: nil
            )
        )
        let fromCrumb = MapQuickNav.outingStart(
            crumbs: [(31.76, -106.48)],
            startLatitude: 1,
            startLongitude: 2
        )
        XCTAssertEqual(fromCrumb?.latitude, 31.76)
        XCTAssertEqual(fromCrumb?.longitude, -106.48)
    }

    func testImDownStillNotSOS() {
        XCTAssertEqual(FieldPing.envelopeKind, .message)
        XCTAssertNotEqual(FieldPing.envelopeKind, .sosAlert)
        XCTAssertFalse(FieldPing.armsSOS)
        XCTAssertFalse(FieldPing.autoDials911)
        XCTAssertFalse(FieldPing.downSetsInjury)
        XCTAssertNotEqual(FieldPing.envelopeKind, SOSConfirm.meshKind)
        XCTAssertFalse(FieldPing.label(.down).localizedCaseInsensitiveContains("sos"))
        XCTAssertFalse(FieldPing.label(.down).contains("911"))
        let inbound = LatestInboundPing(
            id: BlackoutID(),
            ping: .down,
            callsign: "Raven",
            createdAt: Date(),
            thread: .group(partyCode: "AB12CD")
        )
        XCTAssertTrue(inbound.keepsScreenAwake())
        XCTAssertTrue(inbound.holdsMapChrome())
        XCTAssertTrue(LiveActivityPolicy.shouldBeActive(partyCode: nil, inboundPing: inbound))
    }

    func testBLACKOUTCoordStringMatchesSOSFormat() {
        let live = LocationFix(latitude: 31.76190, longitude: -106.48500, source: .gps)
        XCTAssertEqual(
            BlackoutCoordShare.message(live: live, lastKnown: nil),
            SOSConfirm.shareMessage(fix: live)
        )
        XCTAssertEqual(
            BlackoutCoordShare.message(live: live, lastKnown: nil),
            "BLACKOUT 31.76190, -106.48500"
        )
        let last = LocationFix(latitude: 31.76190, longitude: -106.48500, source: .lastKnown)
        XCTAssertEqual(
            BlackoutCoordShare.message(live: nil, lastKnown: last),
            SOSConfirm.shareMessage(fix: last)
        )
        let pin = LocationFix(latitude: 39.74, longitude: -105.25, source: .manualPin)
        XCTAssertEqual(
            BlackoutCoordShare.message(live: nil, lastKnown: pin),
            SOSConfirm.shareMessage(fix: nil)
        )
        XCTAssertEqual(BlackoutCoordShare.message(live: nil, lastKnown: nil), "BLACKOUT NO FIX")
        XCTAssertEqual(SOSConfirm.shareMessage(fix: nil), "BLACKOUT NO FIX")
    }

    func testPartyQRIsLocalCodeOnly() {
        XCTAssertEqual(PartyQR.payload(code: "ab-12"), "AB12")
        XCTAssertEqual(PartyQR.parse("AB12CD"), "AB12CD")
        XCTAssertNil(PartyQR.parse("no"))
    }

    func testFlashlightDoesNotEmitSOS() {
        XCTAssertFalse(MapTorchPolicy.emitsSOS)
        XCTAssertFalse(MapTorchPolicy.armsSOS)
        XCTAssertFalse(MapTorchPolicy.startsSOSStrobe)
        XCTAssertTrue(MapTorchPolicy.allowedInExtremeSaver)
        XCTAssertFalse(MapTorchPolicy.showsOnCriticalShell)
        XCTAssertNil(MapTorchPolicy.envelopeKind)
        XCTAssertNotEqual(MapTorchPolicy.envelopeKind, .sosAlert)
        XCTAssertNotEqual(MapTorchPolicy.envelopeKind, SOSConfirm.meshKind)
        XCTAssertTrue(MapTorchPolicy.showsControl(hasTorch: true))
        XCTAssertFalse(MapTorchPolicy.showsControl(hasTorch: false))
    }

    func testNFCMissingHardwareHidesControls() {
        XCTAssertFalse(PartyNFC.showsControls(readingAvailable: false))
        XCTAssertTrue(PartyNFC.showsControls(readingAvailable: true))
        XCTAssertEqual(PartyNFC.payload(code: "ab-12"), PartyQR.payload(code: "ab-12"))
        XCTAssertEqual(PartyNFC.parse("AB12CD"), "AB12CD")
        XCTAssertEqual(PartyNFC.parse("blackout://join/AB12CD"), "AB12CD")
        XCTAssertEqual(PartyNFC.parseMessagePayloads(["no", "AB12CD"]), "AB12CD")
        XCTAssertNil(PartyNFC.parse("no"))
        XCTAssertEqual(PartyNFC.holdToShare, "Hold to share")
        XCTAssertEqual(PartyNFC.tapToJoin, "Tap to join")
    }

    func testPTTAppIntentRefusesZeroPeers() {
        let refused = PTTIntentPolicy.evaluate(
            nearbyPeerCount: 0,
            partyCode: "AB12CD",
            meshRunning: true,
            microphoneAllowed: true
        )
        XCTAssertFalse(refused.allowsTransmit)
        XCTAssertFalse(refused.shouldBuffer)
        XCTAssertEqual(refused.pressMessage, PTTCopy.noMeshPress)
        XCTAssertFalse(PTTIntentPolicy.firesSOS)
        XCTAssertFalse(PTTIntentPolicy.sendsImDown)
        let ok = PTTIntentPolicy.evaluate(
            nearbyPeerCount: 1,
            partyCode: "AB12CD",
            meshRunning: true,
            microphoneAllowed: true
        )
        XCTAssertTrue(ok.allowsTransmit)
        XCTAssertFalse(ok.shouldBuffer)
        var hint = ActionButtonHintPolicy()
        XCTAssertTrue(hint.shouldShow())
        hint.dismiss()
        XCTAssertFalse(hint.shouldShow())
        XCTAssertEqual(PTTIntentPolicy.actionHint, "Set Action Button to PTT in Settings")
    }
}
