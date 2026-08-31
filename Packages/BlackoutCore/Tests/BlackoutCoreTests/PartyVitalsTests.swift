import XCTest
@testable import BlackoutCore

final class PartyVitalsTests: XCTestCase {
    func testNotOKSetsInjuryAndRed() {
        var status = PartyMemberStatus(id: BlackoutID())
        XCTAssertEqual(status.band, .green)
        XCTAssertFalse(status.injury)
        PartyVitals.apply(.notOK, to: &status, at: Date(timeIntervalSince1970: 10))
        XCTAssertTrue(status.injury)
        XCTAssertEqual(status.band, .red)
    }

    func testDrankAndAteDoNotGoRed() {
        var status = PartyMemberStatus(id: BlackoutID())
        let now = Date(timeIntervalSince1970: 20)
        PartyVitals.apply(.drank, to: &status, at: now)
        PartyVitals.apply(.ate, to: &status, at: now)
        XCTAssertEqual(status.band, .green)
        XCTAssertFalse(status.injury)
        XCTAssertEqual(status.drankAt, now)
        XCTAssertEqual(status.ateAt, now)
    }

    func testDrankAndAteDoNotClearInjury() {
        var status = PartyMemberStatus(id: BlackoutID(), band: .red, injury: true)
        PartyVitals.apply(.drank, to: &status, at: Date())
        PartyVitals.apply(.ate, to: &status, at: Date())
        XCTAssertEqual(status.band, .red)
        XCTAssertTrue(status.injury)
    }

    func testDrankAndAtePipsStayIndependentOfRed() {
        var status = PartyMemberStatus(id: BlackoutID())
        let now = Date(timeIntervalSince1970: 40)
        PartyVitals.apply(.drank, to: &status, at: now)
        PartyVitals.apply(.ate, to: &status, at: now)
        PartyVitals.apply(.notOK, to: &status, at: now)
        XCTAssertTrue(status.drankLatched)
        XCTAssertTrue(status.ateLatched)
        XCTAssertEqual(status.band, .red)
    }

    func testImOKClearsInjuryToGreen() {
        var status = PartyMemberStatus(id: BlackoutID(), band: .red, injury: true)
        PartyVitals.apply(.imOK, to: &status, at: Date())
        XCTAssertEqual(status.band, .green)
        XCTAssertFalse(status.injury)
    }

    func testRestedStaysInMathAndDoesNotGoRed() {
        var status = PartyMemberStatus(id: BlackoutID())
        let now = Date(timeIntervalSince1970: 50)
        PartyVitals.apply(.rested, to: &status, at: now)
        XCTAssertEqual(status.restedAt, now)
        XCTAssertEqual(status.band, .green)
        XCTAssertFalse(status.injury)
        XCTAssertFalse(PartyVitals.isMapChip(.rested))
    }

    func testDizzySetsYellowNotRedAndNotSOS() {
        var status = PartyMemberStatus(id: BlackoutID())
        let now = Date(timeIntervalSince1970: 60)
        PartyVitals.apply(.dizzy, to: &status, at: now)
        XCTAssertTrue(status.dizzy)
        XCTAssertEqual(status.dizzyAt, now)
        XCTAssertEqual(status.band, .yellow)
        XCTAssertFalse(status.injury)
        XCTAssertFalse(PartyVitals.isMapChip(.dizzy))
        XCTAssertFalse(PartyVitals.redFiresSOS)
        let envelope = PartyStatusWire.envelope(
            status: status,
            sender: BlackoutID(),
            recipient: BlackoutID()
        )
        XCTAssertEqual(envelope.kind, .partyStatus)
        XCTAssertNotEqual(envelope.kind, .sosAlert)
    }

    func testDizzyDoesNotOverrideInjuryRed() {
        var status = PartyMemberStatus(id: BlackoutID(), band: .red, injury: true)
        PartyVitals.apply(.dizzy, to: &status, at: Date())
        XCTAssertEqual(status.band, .red)
        XCTAssertTrue(status.injury)
        XCTAssertTrue(status.dizzy)
    }

    func testGoingRedIsPartyStatusNotSOSFire() {
        var status = PartyMemberStatus(id: BlackoutID())
        PartyVitals.apply(.notOK, to: &status, at: Date())
        XCTAssertEqual(status.band, .red)
        XCTAssertFalse(PartyVitals.redFiresSOS)
        let envelope = PartyStatusWire.envelope(
            status: status,
            sender: BlackoutID(),
            recipient: BlackoutID()
        )
        XCTAssertEqual(envelope.kind, .partyStatus)
        XCTAssertNotEqual(envelope.kind, .sosAlert)
    }

    func testTwoTapRequiresSecondTapToCommit() {
        var taps = PartyTapState()
        XCTAssertFalse(taps.tap(.notOK))
        XCTAssertEqual(taps.pending, .notOK)
        XCTAssertTrue(taps.tap(.notOK))
        XCTAssertNil(taps.pending)
    }

    func testTwoTapSwitchResetsPending() {
        var taps = PartyTapState()
        XCTAssertFalse(taps.tap(.drank))
        XCTAssertFalse(taps.tap(.ate))
        XCTAssertEqual(taps.pending, .ate)
        XCTAssertTrue(taps.tap(.ate))
    }

    func testBroadcastOnlyWhenBandChanges() {
        let green = PartyMemberStatus(id: BlackoutID())
        var red = green
        PartyVitals.apply(.notOK, to: &red, at: Date())
        XCTAssertTrue(PartyVitals.shouldBroadcast(before: green, after: red))
        XCTAssertTrue(PartyVitals.shouldBroadcast(before: red, after: green))
        var drank = green
        PartyVitals.apply(.drank, to: &drank, at: Date())
        XCTAssertFalse(PartyVitals.shouldBroadcast(before: green, after: drank))
    }

    func testRedPacketIsPartyStatusNotSOS() throws {
        let status = PartyMemberStatus(id: BlackoutID(), band: .red, injury: true)
        let sender = BlackoutID()
        let recipient = BlackoutID()
        let envelope = PartyStatusWire.envelope(status: status, sender: sender, recipient: recipient)
        XCTAssertEqual(envelope.kind, .partyStatus)
        XCTAssertNotEqual(envelope.kind, .sosAlert)
        XCTAssertTrue(PayloadKind.allCases.contains(.partyStatus))
        XCTAssertTrue(PayloadKind.allCases.contains(.sosAlert))
        let decoded = try XCTUnwrap(PartyStatusWire.decode(envelope.ciphertext))
        XCTAssertEqual(decoded.band, .red)
        XCTAssertTrue(decoded.injury)
        XCTAssertEqual(decoded.id, status.id)
    }

    @MainActor
    func testRadarBlipsAreHonestEmptyWithoutPeersOrFix() {
        let roster = PartyRoster(
            localID: BlackoutID(),
            defaults: UserDefaults(suiteName: "party-empty-\(UUID().uuidString)")!
        )
        XCTAssertTrue(roster.radarBlips(selfFix: nil).isEmpty)
        let selfOnly = roster.radarBlips(selfFix: LocationFix(latitude: 31.76, longitude: -106.48))
        XCTAssertEqual(selfOnly.count, 1)
        XCTAssertEqual(selfOnly[0].kind, .selfDot)
        XCTAssertEqual(selfOnly[0].rangeMeters, 0)
        XCTAssertTrue(roster.peers.isEmpty)
    }

    @MainActor
    func testRedPeerBuildsRedPipOnceHaptic() {
        let local = BlackoutID()
        let roster = PartyRoster(
            localID: local,
            defaults: UserDefaults(suiteName: "party-red-\(UUID().uuidString)")!
        )
        let peer = BlackoutID()
        let status = PartyMemberStatus(
            id: peer,
            band: .red,
            injury: true,
            latitude: 31.77,
            longitude: -106.49
        )
        let envelope = PartyStatusWire.envelope(status: status, sender: peer, recipient: local)
        XCTAssertEqual(roster.ingest(envelope), .becameRed(peer))
        XCTAssertEqual(roster.ingest(envelope), .updated)
        let blips = roster.radarBlips(selfFix: LocationFix(latitude: 31.76, longitude: -106.48))
        XCTAssertEqual(blips.count, 2)
        XCTAssertEqual(blips[0].kind, .selfDot)
        let member = blips.first { $0.kind == .member }
        XCTAssertEqual(member?.band, .red)
        XCTAssertTrue(PartyRadar.pipIsRed(member!))
        XCTAssertEqual(member?.kind, .member)
        XCTAssertNotNil(member?.latitude)
    }

    func testCopyLocksManualButtonsAndSheet() {
        XCTAssertEqual(PartyVitalsCopy.drank, "DRANK")
        XCTAssertEqual(PartyVitalsCopy.ate, "ATE")
        XCTAssertEqual(PartyVitalsCopy.rested, "RESTED")
        XCTAssertEqual(PartyVitalsCopy.dizzy, "DIZZY")
        XCTAssertFalse(PartyVitals.isMapChip(.rested))
        XCTAssertFalse(PartyVitals.isMapChip(.dizzy))
        XCTAssertEqual(PartyVitalsCopy.notOK, "I AM NOT OK")
        XCTAssertEqual(PartyVitalsCopy.imOK, "I AM OK")
        XCTAssertEqual(PartyVitalsCopy.imNot, "I AM NOT")
        XCTAssertEqual(PartyVitalsCopy.message, "Message")
        XCTAssertEqual(PartyVitalsCopy.navigateTo, "Navigate-to")
        XCTAssertEqual(PartyVitalsCopy.chipHeight, 56)
        XCTAssertEqual(PartyVitalsCopy.sosHeight, 88)
    }

    func testManualPathDoesNotMentionHealthKit() {
        XCTAssertFalse(PartyVitalsCopy.drank.localizedCaseInsensitiveContains("health"))
        XCTAssertFalse(PartyVitalsCopy.notOK.localizedCaseInsensitiveContains("health"))
    }
}
