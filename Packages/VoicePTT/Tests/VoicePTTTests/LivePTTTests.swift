import BlackoutCore
import XCTest

final class LivePTTTests: XCTestCase {
    func testZeroPeersDoesNotBuffer() {
        let decision = PTTDecision.evaluate(
            nearbyPeerCount: 0,
            partyCode: "AB12CD",
            meshRunning: true,
            microphoneAllowed: true
        )
        var buffer = [Data([0xFF])]
        XCTAssertFalse(LivePTTLogic.beginTalk(decision: decision, buffer: &buffer))
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(LivePTTLogic.liveFrame(decision: decision, transmitting: true, frame: Data([1])))
        XCTAssertFalse(decision.shouldBuffer)
    }
}
