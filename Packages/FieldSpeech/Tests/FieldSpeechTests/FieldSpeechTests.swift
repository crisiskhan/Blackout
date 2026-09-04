import XCTest
import FieldCorpus
import OfflineSpeech
import BlackBox
@testable import FieldSpeech

final class FieldSpeechTests: XCTestCase {
    func testESTitle() {
        let loc = FieldLoc(en: "CPR", es: "RCP")
        let step = FieldStep(do: loc, why: loc, child: loc, stop: loc, image: "x.png", tickSeconds: nil, metronomeBpm: nil, party: nil)
        let card = FieldCard(schema: "1.4", id: "c", category: "medical", states: ["TX"], title: loc, situation: loc, stop_if: [], get_to_care: loc, speak: true, sendToParty: true, steps: [step])
        XCTAssertEqual(FieldSpeech.line(card, locale: "es"), "RCP")
        let eng = SpeechEngine(box: EventLog())
        FieldSpeech.speak(card, locale: "es", engine: eng)
        XCTAssertTrue(eng.lastUtterance.contains("RCP"))
    }
}
