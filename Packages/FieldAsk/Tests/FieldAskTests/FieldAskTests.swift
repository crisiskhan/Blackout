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

    func testCardiacWalkSitsThemBeforeCompressions() {
        let live = FieldAsk.grounded(
            query: "heart attack",
            chapter: [],
            packId: "tx-west",
            locale: "en"
        )
        XCTAssertEqual(live.id, FieldAsk.liveID)
        XCTAssertTrue(live.steps[0].do.en.lowercased().contains("sit"))
        XCTAssertTrue(live.steps[0].do.en.lowercased().contains("still"))
        let blob = live.steps.map { $0.do.en }.joined(separator: " ").lowercased()
        XCTAssertTrue(blob.contains("compress"))
        XCTAssertFalse(blob.contains("three slow breaths"))
    }

    func testAllergyWalkIsNotBackBlows() {
        let live = FieldAsk.grounded(
            query: "anaphylaxis",
            chapter: [],
            packId: "tx-west",
            locale: "en"
        )
        let first = live.steps[0].do.en.lowercased()
        let blob = live.steps.map { $0.do.en }.joined(separator: " ").lowercased()
        XCTAssertTrue(first.contains("injector") || first.contains("thigh"))
        XCTAssertTrue(blob.contains("thigh"))
        XCTAssertFalse(blob.contains("back hard"))
        XCTAssertFalse(blob.contains("between the shoulders"))
        XCTAssertGreaterThanOrEqual(live.steps.count, 4)
    }

    func testStrokeWalkSitsThemAndNotesTheTime() {
        let live = FieldAsk.grounded(
            query: "stroke",
            chapter: [],
            packId: "tx-west",
            locale: "en"
        )
        let first = live.steps[0].do.en.lowercased()
        let blob = live.steps.map { $0.do.en }.joined(separator: " ").lowercased()
        XCTAssertTrue(first.contains("sit"))
        XCTAssertTrue(first.contains("time"))
        XCTAssertTrue(blob.contains("food") || blob.contains("drink") || blob.contains("pills"))
        XCTAssertFalse(first.contains("compression"))
    }

    func testCantBreatheOpensAConnectedTree() {
        let live = FieldAsk.grounded(
            query: "I can't breathe",
            chapter: [],
            packId: "tx-west",
            locale: "en"
        )
        XCTAssertEqual(live.id, FieldAsk.liveID)
        let first = live.steps[0].do.en.lowercased()
        XCTAssertTrue(first.contains("sit"))
        let labels = (live.links ?? []).map(\.label)
        XCTAssertEqual(labels, ["CHOKE", "ALLERGY", "ASTHMA", "HEART", "SMOKE", "DROWN", "CPR", "STAY"])
        let choke = FieldTree.openLink(
            (live.links ?? []).first { $0.label == "CHOKE" } ?? FieldLink(
                id: "med-airway",
                label: "CHOKE",
                when: FieldLoc(en: "", es: ""),
                ask: "choking"
            ),
            chapter: [
                FieldCard(
                    schema: "1.4",
                    id: "med-airway",
                    category: "medical",
                    states: ["TX"],
                    title: FieldLoc(en: "Airway", es: "Via"),
                    situation: FieldLoc(en: "block", es: "bloqueo"),
                    stop_if: [],
                    get_to_care: FieldLoc(en: "care", es: "cuidado"),
                    speak: true,
                    sendToParty: false,
                    steps: [
                        FieldStep(
                            do: FieldLoc(en: "Back blows", es: "Golpes"),
                            why: FieldLoc(en: "block", es: "bloqueo"),
                            child: FieldLoc(en: "hands", es: "manos"),
                            stop: FieldLoc(en: "stop", es: "para"),
                            image: "airway.png"
                        )
                    ]
                )
            ],
            packId: "tx-west",
            locale: "en"
        )
        XCTAssertEqual(choke.id, "med-airway")
        XCTAssertEqual((choke.links ?? []).map(\.label).first, "INFANT")
    }

    func testHurtWalkLooksForBleedAndBreath() {
        let live = FieldAsk.grounded(
            query: "I'm hurt",
            chapter: [],
            packId: "tx-west",
            locale: "en"
        )
        let first = live.steps[0].do.en.lowercased()
        XCTAssertTrue(first.contains("blood") || first.contains("chest"))
        XCTAssertEqual((live.links ?? []).map(\.label).first, "BLEED")
    }

    func testInfantChokeIsBackAndChestNotBelly() {
        let live = FieldAsk.grounded(
            query: "baby choking",
            chapter: [],
            packId: "tx-west",
            locale: "en"
        )
        let blob = live.steps.map { $0.do.en }.joined(separator: " ").lowercased()
        XCTAssertTrue(blob.contains("back"))
        XCTAssertTrue(blob.contains("chest"))
        XCTAssertTrue(blob.contains("belly"))
        XCTAssertEqual((live.links ?? []).map(\.label).first, "CPR")
    }

    func testFindPeopleIsListenAndLouder() {
        for query in ["find people", "civilization", "anyone out there"] {
            let live = FieldAsk.grounded(
                query: query,
                chapter: [],
                packId: "tx-west",
                locale: "en"
            )
            XCTAssertEqual(live.id, FieldAsk.liveID, query)
            let first = live.steps[0].do.en.lowercased()
            let blob = live.steps.map { $0.do.en }.joined(separator: " ").lowercased()
            XCTAssertTrue(
                first.contains("listen") || first.contains("louder") || first.contains("radio")
                    || blob.contains("listen") || blob.contains("louder") || blob.contains("radio"),
                "\(query) first move \(first)"
            )
            XCTAssertEqual((live.links ?? []).map(\.label), ["SIGNAL", "STAY"], query)
        }
    }

    func testDrownWalkGetsThemOntoLandFirst() {
        let live = FieldAsk.grounded(
            query: "someone is drowning",
            chapter: [],
            packId: "tx-west",
            locale: "en"
        )
        XCTAssertTrue(live.steps[0].do.en.lowercased().contains("land"))
        let blob = live.steps.map { $0.do.en }.joined(separator: " ").lowercased()
        XCTAssertTrue(blob.contains("compression"))
    }
}
