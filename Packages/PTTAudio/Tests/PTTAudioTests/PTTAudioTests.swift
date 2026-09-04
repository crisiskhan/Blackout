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
}
