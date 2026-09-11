import XCTest
@testable import FieldCorpus

final class FieldCorpusTests: XCTestCase {
    func testRejectsBadSchema() {
        let bad = Data(#"{"schema":"1.0","id":"x","cards":[]}"#.utf8)
        XCTAssertTrue(((try? FieldCorpus.load(core: bad, state: bad)) ?? []).isEmpty)
    }

    func testChapterHidesTheOtherPacksRangeCards() {
        let loc = FieldLoc(en: "a", es: "a")
        let step = FieldStep(
            do: loc, why: loc, child: loc, stop: loc, image: "x.png"
        )
        func card(_ id: String, packs: [String]?) -> FieldCard {
            FieldCard(
                schema: "1.4", id: id, category: "animals", states: ["TX"],
                title: loc, situation: loc, stop_if: [], get_to_care: loc,
                speak: true, sendToParty: true, steps: [step], packs: packs
            )
        }
        let west = card("tx-mammal", packs: ["tx-west"])
        let east = card("tx-east-mammal", packs: ["tx-east"])
        let shared = card("tx-plant-danger", packs: nil)
        let cards = [west, east, shared]
        let eastList = FieldCorpus.chapter(cards, pack: "tx-east")
        XCTAssertEqual(eastList.map(\.id), ["tx-east-mammal", "tx-plant-danger"])
        let westList = FieldCorpus.chapter(cards, pack: "tx-west")
        XCTAssertEqual(westList.map(\.id), ["tx-mammal", "tx-plant-danger"])
        XCTAssertEqual(FieldCorpus.chapter(cards, pack: nil).count, 3)
    }
}
