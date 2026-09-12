import XCTest
import FieldCorpus
@testable import FieldStepper

final class FieldStepperTests: XCTestCase {
    func testAdvance() {
        let loc = FieldLoc(en: "a", es: "a")
        let step = FieldStep(do: loc, why: loc, child: loc, stop: loc, image: "x.png", tickSeconds: 1, metronomeBpm: 110, party: ["1": "solo"])
        let card = FieldCard(schema: "1.4", id: "c", category: "medical", states: ["TX"], title: loc, situation: loc, stop_if: [loc], get_to_care: loc, speak: true, sendToParty: true, steps: [step, step])
        var s = StepperState(card: card, index: 0, speaking: false, sentToParty: false)
        s.next(); s.speak(); s.send()
        XCTAssertEqual(s.index, 1)
        XCTAssertTrue(s.speaking)
        XCTAssertEqual(s.step.metronomeBpm, 110)
        var stale = StepperState(card: card, index: 99, speaking: false, sentToParty: false)
        XCTAssertEqual(stale.step.metronomeBpm, 110)
        XCTAssertTrue(stale.isLast)
        let emptyCard = FieldCard(schema: "1.4", id: "empty", category: "medical", states: ["TX"], title: loc, situation: loc, stop_if: [loc], get_to_care: loc, speak: true, sendToParty: true, steps: [])
        var empty = StepperState(card: emptyCard, index: 0, speaking: false, sentToParty: false)
        XCTAssertTrue(empty.isLast)
        XCTAssertEqual(empty.step.image, "")
        empty.next()
        XCTAssertEqual(empty.index, 0)
    }
}
