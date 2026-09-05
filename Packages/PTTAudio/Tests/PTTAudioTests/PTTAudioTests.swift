import XCTest
import BlackBox
@testable import PTTAudio

final class PTTAudioTests: XCTestCase {
    func testClipCap15() {
        let d = PTTDeck(box: EventLog())
        let pcm = Data(repeating: 0, count: 16 * 16000 * 2)
        let c = d.recordClip(pcm: pcm, sampleRate: 16000)
        XCTAssertLessThanOrEqual(c.seconds, 15)
        XCTAssertEqual(OpusLite.decode(c.opus)?.count, pcm.count)
    }

    func testSoloClipZeroRateAndNoPeerBeginEnd() {
        let d = PTTDeck(box: EventLog())
        d.beginLive()
        XCTAssertTrue(d.live)
        let clip = d.recordClip(pcm: Data(repeating: 0, count: 3200), sampleRate: 0)
        XCTAssertTrue(clip.seconds.isFinite)
        XCTAssertGreaterThanOrEqual(clip.seconds, 0)
        XCTAssertLessThanOrEqual(clip.seconds, 15)
        d.endLive()
        XCTAssertFalse(d.live)
        d.endLive()
        XCTAssertFalse(d.live)
    }
}
