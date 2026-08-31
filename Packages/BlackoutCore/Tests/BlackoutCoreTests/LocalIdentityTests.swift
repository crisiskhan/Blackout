import XCTest
@testable import BlackoutCore

@MainActor
final class LocalIdentityTests: XCTestCase {
    func testDefaultCallsignIsYOU() {
        let defaults = freshDefaults("default-you")
        let store = LocalIdentityStore(deviceID: BlackoutID(), defaults: defaults)
        XCTAssertEqual(store.callsign, "YOU")
        XCTAssertEqual(Callsign.defaultValue, "YOU")
        XCTAssertEqual(Callsign.commit(""), "YOU")
        XCTAssertEqual(Callsign.commit("   "), "YOU")
        XCTAssertNil(store.partyCode)
        XCTAssertTrue(store.isSolo)
    }

    func testCallsignMax12() {
        XCTAssertEqual(Callsign.maxLength, 12)
        XCTAssertEqual(Callsign.commit("THIRTEENCHARS"), "THIRTEENCHAR")
        XCTAssertEqual(Callsign.commit("FOX"), "FOX")
        let defaults = freshDefaults("max-12")
        let store = LocalIdentityStore(deviceID: BlackoutID(), defaults: defaults)
        store.commitCallsign("THIRTEENCHARS")
        XCTAssertEqual(store.callsign, "THIRTEENCHAR")
        XCTAssertEqual(store.callsign.count, 12)
    }

    func testPartyCodeCharset() {
        XCTAssertTrue(PartyCode.isValid("AB12"))
        XCTAssertTrue(PartyCode.isValid("ABCDEF12"))
        XCTAssertTrue(PartyCode.isValid("A1B2C3"))
        XCTAssertFalse(PartyCode.isValid(nil))
        XCTAssertFalse(PartyCode.isValid("AB1"))
        XCTAssertFalse(PartyCode.isValid("ABCDEFGHI"))
        XCTAssertFalse(PartyCode.isValid("ab12"))
        XCTAssertFalse(PartyCode.isValid("AB-12"))
        XCTAssertFalse(PartyCode.isValid("AB 12"))
        XCTAssertEqual(PartyCode.normalize("ab12"), "AB12")
        XCTAssertEqual(PartyCode.normalize("ab-12"), "AB12")
        var rng = SeededGenerator(seed: 7)
        let generated = PartyCode.generate(length: 6, using: &rng)
        XCTAssertTrue(PartyCode.isValid(generated))
        XCTAssertEqual(generated.count, 6)
        XCTAssertFalse(MeshGate.allowsTraffic(partyCode: nil))
        XCTAssertTrue(MeshGate.allowsTraffic(partyCode: generated))
    }

    func testPersistAcrossRelaunchInUserDefaults() throws {
        let defaults = freshDefaults("relaunch")
        let device = BlackoutID()
        let first = LocalIdentityStore(deviceID: device, defaults: defaults)
        XCTAssertEqual(first.callsign, "YOU")
        first.commitCallsign("RIDGE")
        XCTAssertTrue(first.createParty())
        let code = try XCTUnwrap(first.partyCode)
        XCTAssertNotNil(defaults.data(forKey: BlackoutKeys.fieldIdentityV1))

        let relaunched = LocalIdentityStore(deviceID: device, defaults: defaults)
        XCTAssertEqual(relaunched.deviceID, device)
        XCTAssertEqual(relaunched.callsign, "RIDGE")
        XCTAssertEqual(relaunched.partyCode, code)
        XCTAssertFalse(relaunched.isSolo)
    }

    func testMigratesRedlineFieldV3ThenWritesV1() throws {
        let defaults = freshDefaults("v3-migrate")
        let device = BlackoutID()
        let legacy = """
        {"deviceID":"\(device.rawValue.uuidString)","callsign":"MIG","partyCode":"ZX9K"}
        """.data(using: .utf8)!
        defaults.set(legacy, forKey: BlackoutKeys.fieldIdentityLegacyV3)
        XCTAssertNil(defaults.data(forKey: BlackoutKeys.fieldIdentityV1))

        let store = LocalIdentityStore(deviceID: BlackoutID(), defaults: defaults)
        XCTAssertEqual(store.callsign, "MIG")
        XCTAssertEqual(store.partyCode, "ZX9K")
        XCTAssertEqual(store.deviceID, device)
        let v1 = try XCTUnwrap(defaults.data(forKey: BlackoutKeys.fieldIdentityV1))
        XCTAssertFalse(v1.isEmpty)
        let again = LocalIdentityStore(deviceID: BlackoutID(), defaults: defaults)
        XCTAssertEqual(again.callsign, "MIG")
        XCTAssertEqual(again.partyCode, "ZX9K")
    }

    @MainActor
    func testCallsignChangeVisibleToRosterAndMeshEnvelope() throws {
        let defaults = freshDefaults("callsign-mesh")
        let local = BlackoutID()
        let identity = LocalIdentityStore(deviceID: local, defaults: defaults)
        let roster = PartyRoster(
            localID: local,
            defaults: defaults,
            identity: identity
        )
        XCTAssertEqual(roster.selfVitals.displayName, "YOU")
        XCTAssertEqual(roster.selfStatus.shortName, "YOU")

        let committed = roster.commitCallsign("WOLF")
        XCTAssertEqual(committed, "WOLF")
        XCTAssertEqual(identity.callsign, "WOLF")
        XCTAssertEqual(roster.selfVitals.displayName, "WOLF")
        XCTAssertEqual(roster.selfStatus.shortName, "WOLF")

        XCTAssertTrue(roster.createParty())
        let envelope = try XCTUnwrap(
            roster.broadcastSelf(fix: LocationFix(latitude: 31.76, longitude: -106.48))
        )
        XCTAssertEqual(envelope.kind, .partyStatus)
        XCTAssertEqual(envelope.sender, local)
        let decoded = try XCTUnwrap(PartyStatusWire.decode(envelope.ciphertext))
        XCTAssertEqual(decoded.displayName, "WOLF")

        let sos = SOSConfirm.meshEnvelope(
            sender: roster.localID,
            recipient: roster.recipientID,
            callsign: roster.identity.callsign
        )
        XCTAssertEqual(SOSMeshBody.callsign(in: sos.ciphertext), "WOLF")
    }

    @MainActor
    func testLeaveEndsMeshGateAndFreezesRosterKeepsCallsign() {
        let defaults = freshDefaults("leave-end")
        let local = BlackoutID()
        let roster = PartyRoster(
            localID: local,
            defaults: defaults,
            identity: LocalIdentityStore(deviceID: local, defaults: defaults)
        )
        roster.commitCallsign("HAWK")
        XCTAssertTrue(roster.createParty())
        XCTAssertTrue(MeshGate.allowsTraffic(partyCode: roster.identity.partyCode))
        XCTAssertFalse(roster.isFrozen)

        let peer = BlackoutID()
        let inbound = PartyStatusWire.envelope(
            status: PartyMemberStatus(id: peer, displayName: "OWL", latitude: 31.7, longitude: -106.4),
            sender: peer,
            recipient: local
        )
        XCTAssertEqual(roster.ingest(inbound), .updated)
        XCTAssertEqual(roster.peerCount, 1)

        roster.leaveParty()
        XCTAssertEqual(roster.identity.callsign, "HAWK")
        XCTAssertNil(roster.identity.partyCode)
        XCTAssertTrue(roster.isSolo)
        XCTAssertTrue(roster.isFrozen)
        XCTAssertFalse(MeshGate.allowsTraffic(partyCode: roster.identity.partyCode))
        XCTAssertEqual(roster.peerCount, 1)
        XCTAssertEqual(roster.ingest(inbound), .ignored)
        XCTAssertEqual(roster.peers.first?.displayName, "OWL")
    }

    @MainActor
    func testSoloWithoutPartyCodeIsValidAndMeshWaits() {
        let roster = PartyRoster(
            localID: BlackoutID(),
            defaults: freshDefaults("solo")
        )
        XCTAssertTrue(roster.identity.isSolo)
        XCTAssertTrue(roster.peers.isEmpty)
        XCTAssertFalse(MeshGate.allowsTraffic(partyCode: roster.identity.partyCode))
        XCTAssertFalse(roster.isFrozen)
    }

    func testSOSOverlayIsNotInsideTabView() {
        XCTAssertFalse(RootChromeLock.sosOverlayIsInsideTabView)
        XCTAssertTrue(RootChromeLock.sosIsRootViewSibling)
        XCTAssertEqual(RootChromeLock.tabCount, 4)
        XCTAssertEqual(RootChromeLock.chromeCollapseFlag, "battery.isCritical")
        XCTAssertEqual(RootChromeLock.sosPlacement, "RootView.ZStack.sibling")
        XCTAssertFalse(RootChromeLock.autoPresentsFirstOpenPackSheet)
        XCTAssertEqual(RootChromeLock.coldLaunchDestination, "map")
    }

    func testPersonNameIsCallsignNotUUIDPrefix() {
        let id = BlackoutID()
        let unnamed = PartyMemberStatus(id: id)
        XCTAssertEqual(unnamed.callsign, "YOU")
        XCTAssertEqual(unnamed.shortName, "YOU")
        XCTAssertFalse(unnamed.shortName.contains(id.rawValue.uuidString.prefix(8)))
        var named = PartyMemberStatus(id: id, displayName: "RIDGE")
        XCTAssertEqual(named.callsign, "RIDGE")
        named.displayName = nil
        XCTAssertEqual(named.callsign, "YOU")
    }

    func testTwoYOUGetLast4SuffixUntilEdit() {
        let a = BlackoutID(UUID(uuidString: "00000000-0000-4000-8000-00000000A1F3")!)
        let b = BlackoutID(UUID(uuidString: "00000000-0000-4000-8000-000000009C00")!)
        let among: [(BlackoutID, String)] = [(a, "YOU"), (b, "YOU")]
        let labelA = CallsignLabel.resolve(callsign: "YOU", id: a, among: among)
        XCTAssertEqual(labelA.name, "YOU")
        XCTAssertEqual(labelA.footnote, "YOU · A1F3")
        XCTAssertEqual(Callsign.last4(a), "A1F3")
        let edited = CallsignLabel.resolve(callsign: "WOLF", id: a, among: among)
        XCTAssertEqual(edited.name, "WOLF")
        XCTAssertNil(edited.footnote)
        let solo = CallsignLabel.resolve(callsign: "YOU", id: a, among: [(a, "YOU")])
        XCTAssertNil(solo.footnote)
        XCTAssertEqual(Callsign.radioName("YOU", id: a), "YOU · A1F3")
        XCTAssertEqual(Callsign.radioName("WOLF", id: a), "WOLF")
    }

    @MainActor
    func testTwoYOUFootnoteDropsOnCallsignCommit() {
        let local = BlackoutID(UUID(uuidString: "00000000-0000-4000-8000-00000000A1F3")!)
        let peer = BlackoutID(UUID(uuidString: "00000000-0000-4000-8000-000000009C00")!)
        let roster = PartyRoster(
            localID: local,
            defaults: freshDefaults("two-you-commit")
        )
        let inbound = PartyStatusWire.envelope(
            status: PartyMemberStatus(
                id: peer,
                displayName: "YOU",
                latitude: 31.7,
                longitude: -106.4
            ),
            sender: peer,
            recipient: local
        )
        XCTAssertEqual(roster.ingest(inbound), .updated)
        XCTAssertEqual(roster.selfLabel.footnote, "YOU · A1F3")
        XCTAssertEqual(roster.label(for: roster.peers[0]).footnote, "YOU · 9C00")
        let blips = roster.radarBlips(
            selfFix: LocationFix(latitude: 31.76, longitude: -106.48)
        )
        XCTAssertEqual(blips.first { $0.kind == .member }?.footnote, "YOU · 9C00")
        roster.commitCallsign("WOLF")
        XCTAssertNil(roster.selfLabel.footnote)
        XCTAssertEqual(roster.selfLabel.name, "WOLF")
        XCTAssertEqual(roster.label(for: roster.peers[0]).footnote, "YOU · 9C00")
        let sos = SOSConfirm.meshEnvelope(
            sender: roster.localID,
            recipient: roster.recipientID,
            callsign: roster.identity.callsign
        )
        XCTAssertEqual(SOSMeshBody.callsign(in: sos.ciphertext), "WOLF")
        XCTAssertFalse((SOSMeshBody.callsign(in: sos.ciphertext) ?? "").contains("·"))
    }

    func testCallsignSurvivesKillAcceptance() {
        let defaults = freshDefaults("night-kill")
        let device = BlackoutID()
        let night = LocalIdentityStore(deviceID: device, defaults: defaults)
        night.commitCallsign("NIGHT")
        XCTAssertTrue(night.createParty())
        let code = night.partyCode
        let relaunched = LocalIdentityStore(deviceID: device, defaults: defaults)
        XCTAssertEqual(relaunched.callsign, "NIGHT")
        XCTAssertEqual(relaunched.partyCode, code)
    }

    @MainActor
    func testSOSMeshPaintsSameRoster() {
        let local = BlackoutID()
        let roster = PartyRoster(localID: local, defaults: freshDefaults("sos-ingest"))
        let sender = BlackoutID()
        let envelope = SOSConfirm.meshEnvelope(
            sender: sender,
            recipient: local,
            callsign: "YOU"
        )
        XCTAssertEqual(roster.ingest(envelope), .becameRed(sender))
        XCTAssertEqual(roster.peerCount, 1)
        XCTAssertEqual(roster.peers.first?.callsign, "YOU")
        XCTAssertEqual(roster.peers.first?.band, .red)
        XCTAssertTrue(roster.peers.first?.injury == true)
    }

    func testOnePackReadySnapshot() {
        let ready = PackReadySnapshot(readyIDs: ["us-tx", "us-fl"])
        XCTAssertTrue(ready.isReady("us-tx"))
        XCTAssertFalse(ready.isReady("el-paso"))
        XCTAssertEqual(PackReadySnapshot.empty.readyIDs, [])
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "local-identity-\(suffix)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
