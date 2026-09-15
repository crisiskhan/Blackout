import XCTest
import FieldCorpus
@testable import FieldAsk

final class FieldAskTests: XCTestCase {
    func testParseSanitizesAndGroundsAChildWalk() {
        let json = """
        {"title":{"en":"Eat this plant, it is edible","es":"Come"},
         "situation":{"en":"Call tel://000 now","es":"tel://000"},
         "stop_if":[{"en":"safe to eat","es":"edible"}],
         "get_to_care":{"en":"drinkable 98.6","es":"98.6"},
         "steps":[
           {"do":{"en":"Eat this plant","es":"Come"},
            "why":{"en":"edible","es":"edible"},
            "child":{"en":"","es":""},
            "stop":{"en":"tel://000","es":"tel://000"},
            "image":"bleed-pack.png"}
         ]}
        """
        let parsed = FieldAsk.parse(json)
        XCTAssertNotNil(parsed)
        let blob = "\(parsed!.title.en) \(parsed!.situation.en) \(parsed!.get_to_care.en)".lowercased()
        XCTAssertFalse(blob.contains("edible"))
        XCTAssertFalse(blob.contains("tel://"))
        XCTAssertFalse(blob.contains("98.6"))
        XCTAssertEqual(parsed?.id, FieldAsk.liveID)
        XCTAssertFalse(parsed?.sendToParty ?? true)
        XCTAssertFalse(parsed!.steps[0].child.en.isEmpty)
        XCTAssertGreaterThanOrEqual(parsed!.steps.count, 4)
    }

    func testAnswerIsNilWhenTheBookAlreadyHasTheCard() {
        let loc = FieldLoc(en: "Make water less bad", es: "Agua")
        let step = FieldStep(
            do: loc, why: loc, child: loc, stop: loc, image: "bleed-pack.png"
        )
        let water = FieldCard(
            schema: "1.4", id: "water-disinfect", category: "water", states: ["TX"],
            title: loc, situation: FieldLoc(en: "thirst", es: "sed"),
            stop_if: [], get_to_care: loc, speak: true, sendToParty: true,
            steps: [step]
        )
        XCTAssertNil(
            FieldAsk.answer(
                query: "thirst",
                chapter: [water],
                locale: "en",
                packName: "west",
                packId: "tx-west",
                modelURL: nil
            )
        )
        let live = FieldAsk.answer(
            query: "xyzzy plugh",
            chapter: [water],
            locale: "en",
            packName: "west",
            packId: "tx-west",
            modelURL: nil
        )
        XCTAssertEqual(live?.id, FieldAsk.liveID)
        XCTAssertGreaterThanOrEqual(live?.steps.count ?? 0, 4)
        XCTAssertFalse(live?.steps.first?.child.en.isEmpty ?? true)
    }

    func testPromptIsChatMLAndForbidsEdible() {
        let loc = FieldLoc(en: "Start", es: "Empieza")
        let step = FieldStep(do: loc, why: loc, child: loc, stop: loc, image: "bleed-pack.png")
        let card = FieldCard(
            schema: "1.4", id: "camp-start", category: "camp", states: ["TX"],
            title: loc, situation: loc, stop_if: [], get_to_care: loc,
            speak: true, sendToParty: false, steps: [step]
        )
        let prompt = FieldAsk.prompt(query: "xyzzy", packName: "west", excerpts: [card], locale: "en")
        XCTAssertTrue(prompt.contains("<|im_start|>system"))
        XCTAssertTrue(prompt.contains("<|im_end|>"))
        XCTAssertTrue(prompt.contains("<|im_start|>assistant"))
        XCTAssertTrue(prompt.contains("Never edible"))
        XCTAssertFalse(prompt.lowercased().contains("best in class"))
    }
}
