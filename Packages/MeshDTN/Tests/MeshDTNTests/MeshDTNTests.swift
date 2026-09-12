import XCTest
import BlackBox
@testable import MeshDTN

final class MeshDTNTests: XCTestCase {
    func testNoPeerEnqueueStaysLocalAndDoesNotSend() {
        let box = EventLog()
        let net = MeshNet(box: box)
        let radio = LoopbackRadio(path: .ble)
        net.attach(radio)
        net.partyCode = "ABC123"
        net.startLocal()
        XCTAssertFalse(net.joined)
        XCTAssertEqual(net.chromeNet, "NET · NONE")
        XCTAssertTrue(radio.sent.isEmpty)
        net.sendChip(from: net.localID, chip: "rally")
        net.sendRED(from: net.localID, on: true)
        net.sendTimer(from: net.localID, task: "water", done: false)
        net.sendPOS(from: net.localID, lat: 31.7, lon: -106.4)
        XCTAssertTrue(radio.sent.isEmpty)
        XCTAssertEqual(net.store.count, 4)
        XCTAssertEqual(net.chromeNet, "NO PEERS · LOGGED")
        XCTAssertTrue(box.all().contains { $0.detail.contains("NO PEERS") })
        net.sendChip(from: net.localID, chip: "field:med-bleed-pack")
        net.sendChip(from: net.localID, chip: "ptt")
        XCTAssertTrue(radio.sent.isEmpty)
        XCTAssertEqual(net.chromeNet, "NO PEERS · LOGGED")
        XCTAssertEqual(net.nearby.count, 0)
    }

    func testListeningIsNotAFakePeer() {
        let net = MeshNet(box: EventLog())
        let radio = LoopbackRadio(path: .ble)
        net.attach(radio)
        net.partyCode = "ABC123"
        net.startLocal()
        XCTAssertTrue(net.listening)
        XCTAssertFalse(net.joined)
        XCTAssertEqual(net.chromeNet, "NET · NONE")
        net.stopLocal()
        XCTAssertFalse(net.listening)
        XCTAssertEqual(net.chromeNet, "NET · NONE")
    }

    func testVoiceAndOneToOneStayLocalWithoutAPeer() {
        let net = MeshNet(box: EventLog())
        let radio = LoopbackRadio(path: .ble)
        net.attach(radio)
        net.startLocal()
        net.sendChip(from: net.localID, chip: "rally", to: "peer-1")
        net.sendVoice(from: net.localID, opus: Data([0x4F, 0x50, 0x55, 0x53, 0, 0, 0, 0]))
        XCTAssertTrue(radio.sent.isEmpty)
        XCTAssertEqual(net.store.map(\.kind), ["chip", "voice"])
        XCTAssertEqual(net.store.first?.to, "peer-1")
        XCTAssertEqual(net.chromeNet, "NO PEERS · LOGGED")
    }

    func testConnectedRadioSendsChipRedTimerPOS() throws {
        let net = MeshNet(box: EventLog())
        let radio = LoopbackRadio(path: .ble)
        net.attach(radio)
        net.partyCode = "ABC123"
        net.startLocal()
        radio.appearPeer("peer-1")
        XCTAssertTrue(net.joined)
        XCTAssertEqual(net.chromeNet, "NET · BLE")
        net.sendChip(from: net.localID, chip: "down")
        net.sendRED(from: net.localID, on: true)
        net.sendTimer(from: net.localID, task: "water", done: false)
        net.sendTimer(from: net.localID, task: "water", done: true)
        net.sendPOS(from: net.localID, lat: 31.76, lon: -106.49)
        XCTAssertEqual(radio.sent.count, 5)
        XCTAssertEqual(Set(radio.sent.map(\.kind)), ["chip", "red", "timer.set", "timer.done", "pos"])
        XCTAssertTrue(net.pips.isEmpty)
    }

    func testSoloPOSDoesNotPaintABodyOnYou() {
        let net = MeshNet(box: EventLog())
        let radio = LoopbackRadio(path: .ble)
        net.attach(radio)
        net.startLocal()
        net.sendPOS(from: net.localID, lat: 31.7, lon: -106.4)
        XCTAssertTrue(net.pips.isEmpty)
        XCTAssertEqual(net.chromeNet, "NO PEERS · LOGGED")
    }

    func testPeerPOSPaintsADotAndLostPeerClearsIt() {
        let net = MeshNet(box: EventLog())
        let radio = LoopbackRadio(path: .ble)
        net.attach(radio)
        net.startLocal()
        radio.appearPeer("peer-1")
        radio.deliver(MeshEnvelope(
            id: "p1",
            from: "peer-1",
            to: "*",
            kind: "pos",
            body: Data("31.76,-106.49".utf8)
        ))
        XCTAssertEqual(net.pips.count, 1)
        XCTAssertEqual(try XCTUnwrap(net.pips.first).from, "peer-1")
        XCTAssertEqual(try XCTUnwrap(net.pips.first).lat, 31.76, accuracy: 0.01)
        XCTAssertNil(try XCTUnwrap(net.pips.first).headingDeg)
        XCTAssertNil(try XCTUnwrap(net.pips.first).emblem)
        radio.deliver(MeshEnvelope(
            id: "p2",
            from: "peer-1",
            to: "*",
            kind: "pos",
            body: Data("31.77,-106.50,90,owl".utf8)
        ))
        XCTAssertEqual(net.pips.count, 1)
        XCTAssertEqual(try XCTUnwrap(net.pips.first).headingDeg, 90)
        XCTAssertEqual(try XCTUnwrap(net.pips.first).emblem, "owl")
        XCTAssertEqual(MeshPOS.parse("31.76,-106.49,,wolf")?.emblem, "wolf")
        XCTAssertNil(MeshPOS.parse("31.76,-106.49,,wolf")?.headingDeg)
        XCTAssertNil(MeshPOS.parse("31.76,-106.49,-1,wolf")?.headingDeg)
        XCTAssertTrue(MeshPOS.body(lat: 31.7, lon: -106.4, headingDeg: 12, emblem: "wolf").contains("wolf"))
        let invalid = MeshPOS.body(lat: 31.7, lon: -106.4, headingDeg: -1, emblem: "wolf")
        XCTAssertFalse(invalid.contains(",-1,"))
        XCTAssertNil(MeshPOS.parse(invalid)?.headingDeg)
        radio.losePeer("peer-1")
        XCTAssertTrue(net.pips.isEmpty)
        net.sendPOS(from: net.localID, lat: 31.8, lon: -106.5)
        XCTAssertTrue(net.pips.isEmpty)
        net.stopLocal()
        XCTAssertTrue(net.pips.isEmpty)
    }

    func testPartyMeshUUIDStableForCode() {
        let a = PartyMeshUUID.uuid(for: "abc123")
        let b = PartyMeshUUID.uuid(for: "ABC123")
        let c = PartyMeshUUID.uuid(for: "ZZZZZZ")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(PartyMeshUUID.characteristic(for: "ABC123"), a)
        XCTAssertEqual(PartyMeshUUID.characteristic(for: "abc123"), PartyMeshUUID.characteristic(for: "ABC123"))
    }

    func testEnvelopeRoundtripAndChunks() throws {
        let env = MeshEnvelope(
            id: "e1",
            from: "A1",
            to: "*",
            kind: "chip",
            body: Data("rally".utf8),
            created: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(env)
        let back = try JSONDecoder().decode(MeshEnvelope.self, from: data)
        XCTAssertEqual(back, env)
        let frames = BLEEnvelopeCodec.chunk(data)
        XCTAssertFalse(frames.isEmpty)
        var asm = BLEEnvelopeCodec.Assembler()
        var out: Data?
        for f in frames { out = asm.push(f) }
        XCTAssertEqual(out, data)
        XCTAssertEqual(try JSONDecoder().decode(MeshEnvelope.self, from: out!), env)
    }

    func testDoesNotEchoSelfAsDelivery() {
        let net = MeshNet(box: EventLog())
        let radio = LoopbackRadio(path: .mpc)
        net.attach(radio)
        net.startLocal()
        radio.appearPeer("p")
        let env = MeshEnvelope(id: "x", from: net.localID, to: "*", kind: "chip", body: Data("rally".utf8))
        radio.deliver(env)
        XCTAssertTrue(net.inbox.isEmpty)
    }

    func testInboundRedTimerChipVisibleAndDeduped() {
        let net = MeshNet(box: EventLog())
        let radio = LoopbackRadio(path: .ble)
        net.attach(radio)
        net.startLocal()
        radio.appearPeer("peer-1")
        let red = MeshEnvelope(id: "r1", from: "peer-1", to: "*", kind: "red", body: Data("on".utf8))
        radio.deliver(red)
        radio.deliver(red)
        radio.deliver(MeshEnvelope(id: "t1", from: "peer-1", to: "*", kind: "timer.set", body: Data("water".utf8)))
        radio.deliver(MeshEnvelope(id: "t2", from: "peer-1", to: "*", kind: "timer.done", body: Data("water".utf8)))
        radio.deliver(MeshEnvelope(id: "c1", from: "peer-1", to: "*", kind: "chip", body: Data("down".utf8)))
        XCTAssertEqual(net.lastRedOn, true)
        XCTAssertEqual(net.inboundTimers.map(\.done), [true])
        XCTAssertEqual(net.inboundTimers.count, 1)
        XCTAssertEqual(net.inboundChips, ["down"])
        XCTAssertEqual(net.inbox.count, 4)
        net.clearInboundChip("down")
        XCTAssertTrue(net.inboundChips.isEmpty)
    }

    func testInboundTimerDoneIsOneRowPerTask() {
        let net = MeshNet(box: EventLog())
        let radio = LoopbackRadio(path: .ble)
        net.attach(radio)
        net.startLocal()
        radio.appearPeer("peer-1")
        radio.deliver(MeshEnvelope(id: "t1", from: "peer-1", to: "*", kind: "timer.done", body: Data("1min".utf8)))
        radio.deliver(MeshEnvelope(id: "t2", from: "peer-1", to: "*", kind: "timer.done", body: Data("1min".utf8)))
        XCTAssertEqual(net.inboundTimers.count, 1)
        XCTAssertEqual(net.inboundTimers.first?.task, "1min")
        XCTAssertTrue(net.inboundTimers.first?.done == true)
    }
}
