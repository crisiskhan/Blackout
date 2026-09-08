import BlackoutCore
@testable import BlackoutMesh
import XCTest

final class MeshVersionTests: XCTestCase {
    func testBK1IsEnvelopeV1() throws {
        XCTAssertEqual(MeshWire.unsupportedVersionCopy, "Mesh version unknown.")
        let envelope = Envelope(
            kind: .message,
            ciphertext: Data([0xAA]),
            sender: BlackoutID(),
            recipient: BlackoutID()
        )
        let frame = try XCTUnwrap(MeshWire.encodeEnvelope(envelope))
        XCTAssertEqual(Array(frame.prefix(3)), [0x42, 0x4B, 0x31])
        guard case .envelope(let decoded) = MeshWire.decode(frame) else {
            return XCTFail("v1 envelope must still load")
        }
        XCTAssertEqual(decoded.ciphertext, envelope.ciphertext)
    }

    func testNewerMagicIsUnsupportedVersionNotSilentSkip() {
        var frame = Data([0x42, 0x4B, 0x32, MeshWire.Kind.envelope.rawValue])
        frame.append(contentsOf: [1, 2, 3])
        guard case .unsupportedVersion = MeshWire.decode(frame) else {
            return XCTFail("BK2 must fail closed")
        }
    }

    func testUnknownKindOnBK1IsUnsupportedVersion() {
        let frame = Data([0x42, 0x4B, 0x31, 99, 0x00])
        guard case .unsupportedVersion = MeshWire.decode(frame) else {
            return XCTFail("unknown kind must fail closed")
        }
    }

    func testGarbageIsStillIgnored() {
        XCTAssertNil(MeshWire.decode(Data("not-a-frame".utf8)))
        XCTAssertNil(MeshWire.decode(Data()))
        XCTAssertNil(MeshWire.decode(Data([0x00, 0x01, 0x02, 0x03])))
    }
}
