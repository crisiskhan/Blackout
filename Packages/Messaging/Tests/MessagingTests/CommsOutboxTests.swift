import BlackoutCore
@testable import Messaging
import XCTest

@MainActor
final class CommsOutboxTests: XCTestCase {
    func testQueueSurvivesSaveReload() throws {
        let store = MemoryPersistence()
        let crypto = FakeCrypto()
        var sent: [Envelope] = []
        let first = CommsOutbox(
            persistence: store,
            crypto: crypto,
            transmit: { envelope in
                sent.append(envelope)
                return .notRunning
            },
            meshState: { (false, 0) }
        )
        let saved = try first.send(text: "hold the ridge", pin: nil, thread: .group(partyCode: "AB12CD"))
        XCTAssertEqual(saved.status, .queued)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(try store.messages().count, 1)

        let reloaded = CommsOutbox(
            persistence: store,
            crypto: crypto,
            transmit: { _ in .sent },
            meshState: { (false, 0) }
        )
        let rows = try reloaded.messages(in: .group(partyCode: "AB12CD"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].status, .queued)
        XCTAssertEqual(reloaded.openBody(rows[0]).text, "hold the ridge")
    }

    func testInboundEnvelopePersists() throws {
        let store = MemoryPersistence()
        let crypto = FakeCrypto()
        let outbox = CommsOutbox(
            persistence: store,
            crypto: crypto,
            transmit: { _ in .sent },
            meshState: { (true, 1) }
        )
        let sender = BlackoutID()
        let plaintext = SealedChatBody(text: "two-phone").encodePlaintext()
        let wire = try crypto.seal(plaintext, partyCode: "AB12CD")
        let envelope = Envelope(
            kind: .message,
            ciphertext: wire,
            sender: sender,
            recipient: PartyThread.groupID(partyCode: "AB12CD")
        )
        let ingested = try XCTUnwrap(outbox.ingest(envelope))
        XCTAssertEqual(ingested.id, envelope.id)
        XCTAssertEqual(try store.messages().count, 1)
        XCTAssertEqual(try store.messages()[0].senderID, sender)
        XCTAssertEqual(outbox.openBody(ingested).text, "two-phone")

        _ = try outbox.ingest(envelope)
        XCTAssertEqual(try store.messages().count, 1)
    }

    func testMeshOffSendIsQueuedNotDropped() throws {
        let store = MemoryPersistence()
        let crypto = FakeCrypto()
        var sent: [Envelope] = []
        let outbox = CommsOutbox(
            persistence: store,
            crypto: crypto,
            transmit: { envelope in
                sent.append(envelope)
                return .notRunning
            },
            meshState: { (false, 0) }
        )
        let saved = try outbox.send(text: "queued in the draw", pin: nil, thread: .group(partyCode: "AB12CD"))
        XCTAssertEqual(saved.status, .queued)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(try store.messages().count, 1)
        XCTAssertNotEqual(saved.status, .failed)
    }

    func testFlushQueuedWhenPeerAppears() throws {
        let store = MemoryPersistence()
        let crypto = FakeCrypto()
        var running = false
        var nearby = 0
        var result = MeshSendResult.notRunning
        let outbox = CommsOutbox(
            persistence: store,
            crypto: crypto,
            transmit: { _ in result },
            meshState: { (running, nearby) }
        )
        _ = try outbox.send(text: "wait", pin: nil, thread: .group(partyCode: "AB12CD"))
        XCTAssertEqual(try store.messages().first?.status, .queued)

        running = true
        nearby = 1
        result = .sent
        let flushed = try outbox.flushQueued()
        XCTAssertEqual(flushed.count, 1)
        XCTAssertEqual(try store.messages().first?.status, .onMesh)
    }

    func testSendFailureIsFailedWithRetry() throws {
        let store = MemoryPersistence()
        let crypto = FakeCrypto()
        var result = MeshSendResult.failed
        let outbox = CommsOutbox(
            persistence: store,
            crypto: crypto,
            transmit: { _ in result },
            meshState: { (true, 1) }
        )
        let saved = try outbox.send(text: "no radio", pin: nil, thread: .group(partyCode: "AB12CD"))
        XCTAssertEqual(saved.status, .failed)
        result = .sent
        let retried = try XCTUnwrap(outbox.retry(saved.id))
        XCTAssertEqual(retried.status, .onMesh)
    }
}

@MainActor
final class MemoryPersistence: PersistenceServing {
    var stored: [MessageRecordDTO] = []

    func expeditions() throws -> [ExpeditionRecordDTO] { [] }
    func upsertExpedition(_ record: ExpeditionRecordDTO) throws {}
    func breadcrumbs(expeditionID: BlackoutID) throws -> [BreadcrumbRecordDTO] { [] }
    func appendBreadcrumb(_ record: BreadcrumbRecordDTO) throws {}
    func sosEvents() throws -> [SOSEventRecordDTO] { [] }
    func logSOS(_ record: SOSEventRecordDTO) throws {}
    func messages() throws -> [MessageRecordDTO] {
        stored.sorted { $0.createdAt > $1.createdAt }
    }
    func saveMessage(_ record: MessageRecordDTO) throws {
        if let index = stored.firstIndex(where: { $0.id == record.id }) {
            stored[index] = record
        } else {
            stored.append(record)
        }
    }
    func voiceClips() throws -> [VoiceClipRecordDTO] { [] }
    func saveVoiceClip(_ record: VoiceClipRecordDTO) throws {}
}

@MainActor
final class FakeCrypto: CryptoServing {
    let localIdentity = BlackoutID()
    var localAdvertisement: Data { Data([1]) }
    var preferredRecipient: BlackoutID { localIdentity }

    func registerPeerAdvertisement(_ data: Data) { _ = data }
    func setPartyCode(_ code: String?) { _ = code }

    func seal(_ plaintext: Data, to recipient: BlackoutID) throws -> Data {
        var out = Data([1])
        out.append(recipient.rawValue.uuidString.data(using: .utf8) ?? Data())
        out.append(0)
        out.append(plaintext)
        return out
    }

    func seal(_ plaintext: Data, partyCode: String) throws -> Data {
        var out = Data([3])
        out.append(Data(partyCode.utf8))
        out.append(0)
        out.append(plaintext)
        return out
    }

    func open(_ ciphertext: Data) throws -> Data {
        guard let zero = ciphertext.dropFirst().firstIndex(of: 0) else {
            throw CryptoLoopbackOpenError.bad
        }
        return Data(ciphertext[(zero + 1)...])
    }
}

private enum CryptoLoopbackOpenError: Error {
    case bad
}
