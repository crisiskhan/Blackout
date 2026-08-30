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

    func testImOKClearsInjuryToGreen() {
        var status = PartyMemberStatus(id: BlackoutID(), band: .red, injury: true)
        PartyVitals.apply(.imOK, to: &status, at: Date())
        XCTAssertEqual(status.band, .green)
        XCTAssertFalse(status.injury)
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
        XCTAssertTrue(roster.radarBlips(selfFix: LocationFix(latitude: 31.76, longitude: -106.48)).isEmpty)
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
        XCTAssertEqual(blips.count, 1)
        XCTAssertEqual(blips[0].band, .red)
        XCTAssertTrue(PartyRadar.pipIsRed(blips[0]))
        XCTAssertEqual(blips[0].kind, .member)
        XCTAssertNotNil(blips[0].latitude)
    }

    func testCopyLocksManualButtonsAndSheet() {
        XCTAssertEqual(PartyVitalsCopy.drank, "DRANK")
        XCTAssertEqual(PartyVitalsCopy.ate, "ATE")
        XCTAssertEqual(PartyVitalsCopy.notOK, "I'M NOT OK")
        XCTAssertEqual(PartyVitalsCopy.imOK, "I'M OK")
        XCTAssertEqual(PartyVitalsCopy.imNot, "I'M NOT")
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
