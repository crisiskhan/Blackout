import XCTest
@testable import BlackoutCore

final class CommsContractTests: XCTestCase {
    func testMessageStatusCopyIsSealedQueuedOnMeshFailed() {
        XCTAssertEqual(MessageStatus.allCases.map(\.rawValue), [
            "Sealed", "Queued", "On mesh", "Failed"
        ])
    }

    func testGroupThreadIDIsStableForTheSamePartyCode() {
        let a = PartyThread.groupID(partyCode: "AB12CD")
        let b = PartyThread.groupID(partyCode: "AB12CD")
        let other = PartyThread.groupID(partyCode: "ZZZZ99")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, other)
        XCTAssertTrue(PartyThread.isGroupRecipient(a, partyCode: "AB12CD"))
        XCTAssertFalse(PartyThread.isGroupRecipient(a, partyCode: "ZZZZ99"))
    }

    func testGroupTitleUsesCallsignsNotUUID() {
        let title = PartyThread.groupTitle(selfCallsign: "RIDGE", peerCallsigns: ["FOX", "OWL"])
        XCTAssertEqual(title, "FOX, OWL")
        XCTAssertFalse(title.contains("-"))
        XCTAssertEqual(PartyThread.groupTitle(selfCallsign: "RIDGE", peerCallsigns: []), "RIDGE party")
        XCTAssertEqual(PartyThread.groupTitle(selfCallsign: "YOU", peerCallsigns: []), "Party")
    }

    func testStaleAfterNinetySeconds() {
        let heard = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(PartyThread.isStale(lastHeard: heard, now: heard.addingTimeInterval(89)))
        XCTAssertTrue(PartyThread.isStale(lastHeard: heard, now: heard.addingTimeInterval(91)))
    }

    func testPTTRefusesZeroPeersWithoutBuffering() {
        let decision = PTTDecision.evaluate(
            nearbyPeerCount: 0,
            partyCode: "AB12CD",
            meshRunning: true,
            microphoneAllowed: true
        )
        XCTAssertFalse(decision.allowsTransmit)
        XCTAssertTrue(decision.dimmed)
        XCTAssertFalse(decision.shouldBuffer)
        XCTAssertEqual(decision.pressMessage, PTTCopy.noMeshPress)
        XCTAssertEqual(decision.emptyMessage, PTTCopy.noMeshEmpty)

        var buffer: [Data] = [Data([1, 2, 3])]
        XCTAssertFalse(LivePTTLogic.beginTalk(decision: decision, buffer: &buffer))
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(LivePTTLogic.liveFrame(decision: decision, transmitting: false, frame: Data([9])))
    }

    func testPTTRefusesNoPartyAndMeshOff() {
        let noParty = PTTDecision.evaluate(
            nearbyPeerCount: 1,
            partyCode: nil,
            meshRunning: true,
            microphoneAllowed: true
        )
        XCTAssertFalse(noParty.allowsTransmit)
        XCTAssertFalse(noParty.shouldBuffer)

        let meshOff = PTTDecision.evaluate(
            nearbyPeerCount: 1,
            partyCode: "AB12CD",
            meshRunning: false,
            microphoneAllowed: true
        )
        XCTAssertFalse(meshOff.allowsTransmit)
        XCTAssertFalse(meshOff.shouldBuffer)
    }

    func testPTTLiveWhenPeersPartyAndMesh() {
        let decision = PTTDecision.evaluate(
            nearbyPeerCount: 1,
            partyCode: "AB12CD",
            meshRunning: true,
            microphoneAllowed: true
        )
        XCTAssertTrue(decision.allowsTransmit)
        XCTAssertFalse(decision.dimmed)
        XCTAssertFalse(decision.shouldBuffer)
        var buffer: [Data] = []
        XCTAssertTrue(LivePTTLogic.beginTalk(decision: decision, buffer: &buffer))
        XCTAssertEqual(LivePTTLogic.liveFrame(decision: decision, transmitting: true, frame: Data([7])), Data([7]))
    }

    func testMeshSendResultMapsToChatStatus() {
        XCTAssertEqual(MeshSendResult.sent.messageStatus, .onMesh)
        XCTAssertEqual(MeshSendResult.notRunning.messageStatus, .queued)
        XCTAssertEqual(MeshSendResult.noPeers.messageStatus, .queued)
        XCTAssertEqual(MeshSendResult.failed.messageStatus, .failed)
    }
}
