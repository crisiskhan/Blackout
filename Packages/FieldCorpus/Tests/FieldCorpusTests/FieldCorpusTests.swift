import XCTest
@testable import FieldCorpus

final class FieldCorpusTests: XCTestCase {
    func testRejectsBadSchema() {
        let bad = Data(#"{"schema":"1.0","id":"x","cards":[]}"#.utf8)
        XCTAssertTrue(((try? FieldCorpus.load(core: bad, state: bad)) ?? []).isEmpty)
    }

    func testChapterHidesTheOtherPacksRangeCards() {
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

    func testAskEmptyQueryReturnsTheChapterUnchanged() {
        let cards = [
            card("water-disinfect", category: "water", title: "Make water less bad"),
            card("fire-stove", category: "fire", title: "Stove and small fire"),
        ]
        XCTAssertEqual(FieldCorpus.ask(cards, query: "", locale: "en").map(\.id), cards.map(\.id))
        XCTAssertEqual(FieldCorpus.ask(cards, query: "   ", locale: "en").map(\.id), cards.map(\.id))
        XCTAssertEqual(FieldCorpus.ask(cards, query: "how do I", locale: "en").map(\.id), cards.map(\.id))
    }

    func testAskRanksATitleHitAndDropsGibberish() {
        let water = card("water-disinfect", category: "water", title: "Make water less bad", situation: "creek or tank")
        let fire = card("fire-stove", category: "fire", title: "Stove and small fire", situation: "heat for water")
        let cards = [water, fire]
        XCTAssertEqual(FieldCorpus.ask(cards, query: "stove", locale: "en").map(\.id), ["fire-stove"])
        XCTAssertTrue(FieldCorpus.ask(cards, query: "xyzzy plugh", locale: "en").isEmpty)
    }

    func testAskThirstFindsWaterEvenWhenTheTitleOmitsTheWord() {
        let water = card("water-disinfect", category: "water", title: "Make water less bad")
        let fire = card("fire-stove", category: "fire", title: "Stove and small fire")
        let hit = FieldCorpus.ask([water, fire], query: "I am thirsty", locale: "en")
        XCTAssertEqual(hit.map(\.id), ["water-disinfect"])
    }

    func testAskSnakeFindsBiteWithoutInventingACardOutsideTheList() {
        let bite = card("animal-bite", title: "Bite or envenomation")
        let cook = card("food-cook", category: "food", title: "Cook what you already trust")
        XCTAssertEqual(FieldCorpus.ask([bite, cook], query: "snake", locale: "en").map(\.id), ["animal-bite"])
        XCTAssertTrue(FieldCorpus.ask([cook], query: "snake", locale: "en").isEmpty)
    }

    func testAskSpanishFindsTheBilingualCard() {
        let bite = card(
            "animal-bite",
            title: "Bite or envenomation",
            titleEs: "Mordedura o veneno"
        )
        let hit = FieldCorpus.ask([bite], query: "víbora", locale: "es")
        XCTAssertEqual(hit.map(\.id), ["animal-bite"])
        XCTAssertEqual(FieldCorpus.ask([bite], query: "vibora", locale: "en").map(\.id), ["animal-bite"])
    }

    func testAskDoesNotUnlockAMeal() {
        let unknown = card("plant-unknown", title: "Unknown plant", situation: "do not eat it")
        let fungi = card("fungi-leave", title: "Fungi — leave it")
        let cook = card("food-cook", category: "food", title: "Cook what you already trust")
        let hit = FieldCorpus.ask([unknown, fungi, cook], query: "forage berries mushroom", locale: "en").map(\.id)
        XCTAssertTrue(hit.contains("plant-unknown"))
        XCTAssertTrue(hit.contains("fungi-leave"))
        XCTAssertFalse(hit.contains("food-cook"))
    }

    func testAskStartingFromNothingFindsTheOrderOfWork() {
        let start = card("camp-start", title: "Starting from nothing")
        let hunt = card("food-game", title: "Meat you already have")
        let hit = FieldCorpus.ask([start, hunt], query: "starting from nothing", locale: "en")
        XCTAssertEqual(hit.first?.id, "camp-start")
    }

    func testAskWildfireFindsAlreadyBurnedGround() {
        let wild = card("env-wildfire", title: "Already-burned ground, not uphill")
        let cook = card("food-cook", category: "food", title: "Cook what you already trust")
        XCTAssertEqual(
            FieldCorpus.ask([wild, cook], query: "wildfire", locale: "en").map(\.id),
            ["env-wildfire"]
        )
    }

    func testAskWoolFindsTheLayerCard() {
        let layers = card("camp-layers", title: "Clothing is a system")
        let cook = card("food-cook", category: "food", title: "Cook what you already trust")
        XCTAssertEqual(
            FieldCorpus.ask([layers, cook], query: "wet wool", locale: "en").map(\.id),
            ["camp-layers"]
        )
    }

    private func card(
        _ id: String,
        category: String = "water",
        title: String = "a",
        titleEs: String? = nil,
        situation: String = "sit",
        packs: [String]? = nil
    ) -> FieldCard {
        let loc = FieldLoc(en: title, es: titleEs ?? title)
        let sit = FieldLoc(en: situation, es: situation)
        let step = FieldStep(
            do: loc, why: loc, child: loc, stop: loc, image: "x.png"
        )
        return FieldCard(
            schema: "1.4", id: id, category: category, states: ["TX"],
            title: loc, situation: sit, stop_if: [], get_to_care: loc,
            speak: true, sendToParty: true, steps: [step], packs: packs
        )
    }
}
