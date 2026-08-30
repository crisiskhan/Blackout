import BlackoutCore
@testable import BlackoutMesh
import XCTest

final class StoreAndForwardTests: XCTestCase {
    func testDuplicateIdIsNotReForwarded() {
        let queue = StoreAndForwardQueue(fileURL: tempURL())
        let envelope = Envelope(
            kind: .message,
            ciphertext: Data([0xAA, 0xBB]),
            sender: BlackoutID(),
            recipient: BlackoutID()
        )
        switch queue.acceptInbound(envelope) {
        case .deliverAndForward(let first):
            XCTAssertEqual(first.id, envelope.id)
            XCTAssertEqual(first.hopCount, 1)
            XCTAssertEqual(first.ciphertext, envelope.ciphertext)
        case .duplicate:
            XCTFail("first inbound should deliver")
        }
        XCTAssertEqual(queue.acceptInbound(envelope), .duplicate)
        XCTAssertEqual(queue.acceptInbound(envelope.forwarded()), .duplicate)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testOfflineQueueFlushesWhenPeerAppears() {
        let url = tempURL()
        let queue = StoreAndForwardQueue(fileURL: url)
        let envelope = Envelope(
            kind: .sosAlert,
            ciphertext: Data([0x01]),
            sender: BlackoutID(),
            recipient: BlackoutID()
        )
        queue.noteOutbound(envelope)
        XCTAssertTrue(queue.hasSeen(envelope.id))
        XCTAssertEqual(queue.flushPending().map(\.id), [envelope.id])

        let reloaded = StoreAndForwardQueue(fileURL: url)
        XCTAssertTrue(reloaded.hasSeen(envelope.id))
        XCTAssertEqual(reloaded.flushPending().first?.ciphertext, Data([0x01]))
        XCTAssertEqual(reloaded.acceptInbound(envelope), .duplicate)
    }

    func testSafeResourceNamesIncludeStatewide() {
        XCTAssertTrue(MeshRadio.isSafeResourceName("el-paso"))
        XCTAssertTrue(MeshRadio.isSafeResourceName("us-tx"))
        XCTAssertTrue(MeshRadio.isSafeResourceName("us-nm"))
        XCTAssertFalse(MeshRadio.isSafeResourceName("../secret"))
        XCTAssertFalse(MeshRadio.isSafeResourceName("el paso"))
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("saf-\(UUID().uuidString).json")
    }
}
