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
}
