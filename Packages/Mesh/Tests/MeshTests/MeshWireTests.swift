import BlackoutCore
@testable import BlackoutMesh
import XCTest

final class MeshWireTests: XCTestCase {
    func testEnvelopeRoundtrip() throws {
        let envelope = Envelope(
            kind: .message,
            ciphertext: Data([0xAA, 0xBB]),
            sender: BlackoutID(),
            recipient: BlackoutID()
        )
        let frame = try XCTUnwrap(MeshWire.encodeEnvelope(envelope))
        guard case .envelope(let decoded) = MeshWire.decode(frame) else {
            return XCTFail("expected envelope frame")
        }
        XCTAssertEqual(decoded.id, envelope.id)
        XCTAssertEqual(decoded.kind, .message)
        XCTAssertEqual(decoded.ciphertext, envelope.ciphertext)
        XCTAssertEqual(decoded.sender, envelope.sender)
        XCTAssertEqual(decoded.recipient, envelope.recipient)
    }

    func testAdvertisementRoundtrip() {
        let payload = Data([1, 2, 3, 4])
        let frame = MeshWire.encodeAdvertisement(payload)
        guard case .advertisement(let decoded) = MeshWire.decode(frame) else {
            return XCTFail("expected advertisement frame")
        }
        XCTAssertEqual(decoded, payload)
    }

    func testRejectsGarbage() {
        XCTAssertNil(MeshWire.decode(Data("not-a-frame".utf8)))
        XCTAssertNil(MeshWire.decode(Data()))
    }

    func testPartyStatusEnvelopeRoundtrip() throws {
        let status = PartyMemberStatus(id: BlackoutID(), band: .red, injury: true)
        let envelope = PartyStatusWire.envelope(
            status: status,
            sender: BlackoutID(),
            recipient: BlackoutID()
        )
        XCTAssertEqual(envelope.kind, .partyStatus)
        let frame = try XCTUnwrap(MeshWire.encodeEnvelope(envelope))
        guard case .envelope(let decoded) = MeshWire.decode(frame) else {
            return XCTFail("expected envelope frame")
        }
        XCTAssertEqual(decoded.kind, .partyStatus)
        XCTAssertEqual(PartyStatusWire.decode(decoded.ciphertext)?.band, .red)
    }

    func testPartyDiscoveryMatchesSameCodeOnly() {
        let id = BlackoutID()
        let info = MeshRadio.discoveryInfo(partyCode: "AB12CD", deviceID: id)
        XCTAssertTrue(MeshRadio.matchesParty(info, partyCode: "AB12CD"))
        XCTAssertFalse(MeshRadio.matchesParty(info, partyCode: "ZZZZZZ"))
        XCTAssertFalse(MeshRadio.matchesParty(nil, partyCode: "AB12CD"))
        XCTAssertFalse(MeshGate.allowsTraffic(partyCode: nil))
        XCTAssertTrue(MeshGate.allowsTraffic(partyCode: "AB12CD"))
    }

    func testSafeResourceNames() {
        XCTAssertTrue(MeshRadio.isSafeResourceName("el-paso"))
        XCTAssertTrue(MeshRadio.isSafeResourceName("las-cruces"))
        XCTAssertTrue(MeshRadio.isSafeResourceName("albuquerque"))
        XCTAssertFalse(MeshRadio.isSafeResourceName("../secret"))
        XCTAssertFalse(MeshRadio.isSafeResourceName("el paso"))
        XCTAssertFalse(MeshRadio.isSafeResourceName(""))
    }
}
