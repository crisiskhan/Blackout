import XCTest
@testable import VisionCoreML

final class VisionCoreMLTests: XCTestCase {
    func testNoModelNotHashID() throws {
        XCTAssertFalse(VisionCoreML.onDeviceModelPresent)
        let book = txBook()
        let g = VisionCoreML.classify(features: [0.2, 0.8], book: book)
        XCTAssertTrue(g.noModel)
        XCTAssertEqual(g.name, "NO VISION MODEL")
        XCTAssertEqual(g.percent, 0)
        XCTAssertFalse(g.edible)
        XCTAssertTrue(g.leaveIt)
        XCTAssertEqual(g.labelId, "no-model")
    }

    func testCactusKindIsCactusNotTheOnlyBookSpecies() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Cactus", confidence: 0.8)],
            book: txBook()
        )
        XCTAssertFalse(g.noModel)
        XCTAssertFalse(g.edible)
        XCTAssertEqual(g.percent, 0)
        XCTAssertEqual(g.name, "CACTUS")
        XCTAssertEqual(g.labelId, "kind:cactus")
        XCTAssertNotEqual(g.name, "PRICKLY PEAR")
    }

    func testPricklyPearNameIsStillTheBookName() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Prickly pear", confidence: 0.8)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "PRICKLY PEAR")
        XCTAssertEqual(g.labelId, "tx-prickly-pear")
        XCTAssertFalse(g.edible)
    }

    func testFungiIsLeaveItNeverASpeciesPick() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "mushroom", confidence: 0.9)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "FUNGI")
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.edible)
        XCTAssertEqual(g.labelId, "kind:fungi")
    }

    func testUnknownWhenNothingMatches() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "office chair", confidence: 0.9)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "UNKNOWN")
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.edible)
        XCTAssertFalse(g.noModel)
    }

    func testCoyoteHitsTheBookName() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "coyote", confidence: 0.7)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "COYOTE")
        XCTAssertFalse(g.edible)
    }

    func testRattlesnakeIsKindLeaveItNeverASpeciesPick() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Western diamondback rattlesnake", confidence: 0.88)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "SNAKE")
        XCTAssertEqual(g.labelId, "kind:snake")
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.edible)
        XCTAssertEqual(g.percent, 0)
    }

    func testAPearStillIsCactusEvenWhenAppleRanksTreeFirst() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Plant", confidence: 0.92),
                VisionObservation(identifier: "Tree", confidence: 0.88),
                VisionObservation(identifier: "Cactus", confidence: 0.41),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "CACTUS")
        XCTAssertEqual(g.labelId, "kind:cactus")
        XCTAssertNotEqual(g.name, "TREE")
        XCTAssertNotEqual(g.name, "PRICKLY PEAR")
        XCTAssertFalse(g.edible)
        XCTAssertEqual(g.percent, 0)
    }

    func testFungiBeatsATreeOnTheSameStill() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Tree", confidence: 0.9),
                VisionObservation(identifier: "mushroom", confidence: 0.35),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "FUNGI")
        XCTAssertEqual(g.labelId, "kind:fungi")
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.edible)
    }

    func testATreeStillStillWorksWhenThatIsAllAppleSaid() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Tree", confidence: 0.8)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "TREE")
        XCTAssertEqual(g.labelId, "kind:tree")
        XCTAssertFalse(g.edible)
        XCTAssertEqual(g.percent, 0)
    }

    func testSucculentBeatsATreeOnTheSameStill() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Tree", confidence: 0.9),
                VisionObservation(identifier: "Succulent plant", confidence: 0.34),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "CACTUS")
        XCTAssertEqual(g.labelId, "kind:cactus")
        XCTAssertNotEqual(g.name, "TREE")
        XCTAssertNotEqual(g.name, "PRICKLY PEAR")
        XCTAssertFalse(g.edible)
    }

    func testYuccaBeatsATreeOnTheSameStill() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Tree", confidence: 0.88),
                VisionObservation(identifier: "Yucca", confidence: 0.31),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "YUCCA")
        XCTAssertNotEqual(g.name, "TREE")
        XCTAssertFalse(g.edible)
    }

    func testPeccaryHitsJavelina() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Collared peccary", confidence: 0.7)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "JAVELINA")
        XCTAssertFalse(g.edible)
    }

    func testBoarIsMammalNotATree() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Tree", confidence: 0.8),
                VisionObservation(identifier: "Wild boar", confidence: 0.33),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "MAMMAL")
        XCTAssertNotEqual(g.name, "TREE")
        XCTAssertFalse(g.edible)
    }

    func testScorpionIsStingLeaveIt() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Scorpion", confidence: 0.8)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "STING")
        XCTAssertEqual(g.labelId, "kind:sting")
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.edible)
        XCTAssertEqual(g.percent, 0)
    }

    func testWaspBeatsATreeOnTheSameStill() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Tree", confidence: 0.9),
                VisionObservation(identifier: "Wasp", confidence: 0.3),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "STING")
        XCTAssertEqual(g.labelId, "kind:sting")
        XCTAssertTrue(g.leaveIt)
        XCTAssertNotEqual(g.name, "TREE")
        XCTAssertFalse(g.edible)
    }

    func testAlligatorIsGatorLeaveIt() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Tree", confidence: 0.7),
                VisionObservation(identifier: "American alligator", confidence: 0.4),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "GATOR")
        XCTAssertEqual(g.labelId, "kind:gator")
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.edible)
        XCTAssertEqual(g.percent, 0)
    }

    func testLakeIsWaterNotLeaveIt() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Tree", confidence: 0.85),
                VisionObservation(identifier: "Lake", confidence: 0.4),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "WATER")
        XCTAssertEqual(g.labelId, "kind:water")
        XCTAssertFalse(g.leaveIt)
        XCTAssertFalse(g.edible)
        XCTAssertEqual(g.percent, 0)
    }

    func testBodyOfWaterIsWater() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Body of water", confidence: 0.7)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "WATER")
        XCTAssertEqual(g.labelId, "kind:water")
        XCTAssertFalse(g.edible)
    }

    func testFoxIsMammal() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Red fox", confidence: 0.7)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "MAMMAL")
        XCTAssertEqual(g.labelId, "kind:mammal")
        XCTAssertFalse(g.edible)
    }

    func testWildfireIsFireLeaveIt() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Tree", confidence: 0.8),
                VisionObservation(identifier: "Wildfire", confidence: 0.4),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "FIRE")
        XCTAssertEqual(g.labelId, "kind:fire")
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.edible)
    }

    func testFloodBeatsATreeOnTheSameStill() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Tree", confidence: 0.9),
                VisionObservation(identifier: "Flood", confidence: 0.35),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "FLOOD")
        XCTAssertEqual(g.labelId, "kind:flood")
        XCTAssertFalse(g.edible)
    }

    func testLightningIsLeaveIt() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Lightning", confidence: 0.8)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "LIGHTNING")
        XCTAssertEqual(g.labelId, "kind:lightning")
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.edible)
    }

    func testCampfireIsNotFire() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Campfire", confidence: 0.9)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "UNKNOWN")
        XCTAssertNotEqual(g.labelId, "kind:fire")
        XCTAssertFalse(g.edible)
    }

    func testLacerationIsWoundLeaveIt() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Tree", confidence: 0.8),
                VisionObservation(identifier: "Laceration", confidence: 0.4),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "WOUND")
        XCTAssertEqual(g.labelId, "kind:wound")
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.edible)
    }

    func testHedgehogIsNotAMammal() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Hedgehog", confidence: 0.9)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "UNKNOWN")
        XCTAssertNotEqual(g.name, "MAMMAL")
        XCTAssertFalse(g.edible)
    }

    func testPorcupineIsNotAPineOrATree() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Porcupine", confidence: 0.9)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "UNKNOWN")
        XCTAssertNotEqual(g.name, "TREE")
        XCTAssertFalse(g.name.contains("PINE"))
        XCTAssertFalse(g.edible)
    }

    func testStreetIsNotATree() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Street", confidence: 0.9)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "UNKNOWN")
        XCTAssertNotEqual(g.name, "TREE")
        XCTAssertFalse(g.edible)
    }

    func testBirdKindIsBirdNotATree() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Tree", confidence: 0.9),
                VisionObservation(identifier: "Bird", confidence: 0.36),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "BIRD")
        XCTAssertEqual(g.labelId, "kind:bird")
        XCTAssertFalse(g.edible)
        XCTAssertFalse(g.leaveIt)
        XCTAssertEqual(g.percent, 0)
    }

    func testTurkeyNameIsStillTheBookName() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Wild turkey", confidence: 0.8)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "TURKEY")
        XCTAssertEqual(g.labelId, "tx-turkey")
        XCTAssertFalse(g.edible)
    }

    func testBassIsFishNotWater() {
        let g = VisionCoreML.classify(
            observations: [
                VisionObservation(identifier: "Lake", confidence: 0.8),
                VisionObservation(identifier: "Largemouth bass", confidence: 0.4),
            ],
            book: txBook()
        )
        XCTAssertEqual(g.name, "FISH")
        XCTAssertEqual(g.labelId, "kind:fish")
        XCTAssertNotEqual(g.name, "WATER")
        XCTAssertFalse(g.edible)
        XCTAssertFalse(g.leaveIt)
    }

    func testGilaIsLizardLeaveIt() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Gila monster", confidence: 0.8)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "LIZARD")
        XCTAssertEqual(g.labelId, "kind:lizard")
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.edible)
        XCTAssertEqual(g.percent, 0)
    }

    func testFrogIsLeaveItNotAMeal() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Toad", confidence: 0.8)],
            book: txBook()
        )
        XCTAssertEqual(g.name, "FROG")
        XCTAssertEqual(g.labelId, "kind:frog")
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.edible)
    }

    func testWoodIsNotACottonwood() {
        let book = VisionBook(
            state: "NM",
            neverEdibleUnlock: true,
            fungiDefault: "LEAVE_IT",
            labels: [
                VisionLabel(
                    id: "nm-cottonwood",
                    kind: "tree",
                    lookalikes: [],
                    leaveIt: false,
                    edibleUnlock: false,
                    name: ["en": "Rio Grande cottonwood"]
                ),
            ]
        )
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Wood", confidence: 0.9)],
            book: book
        )
        XCTAssertEqual(g.name, "UNKNOWN")
        XCTAssertFalse(g.edible)
    }

    private func txBook() -> VisionBook {
        VisionBook(state: "TX", neverEdibleUnlock: true, fungiDefault: "LEAVE_IT", labels: [
            VisionLabel(id: "tx-prickly-pear", kind: "cactus", lookalikes: ["glochid-lookalike"], leaveIt: false, edibleUnlock: false, name: ["en": "Prickly pear"]),
            VisionLabel(id: "tx-yucca", kind: "cacti_yucca", lookalikes: ["sotol-lookalike"], leaveIt: false, edibleUnlock: false, name: ["en": "Yucca"]),
            VisionLabel(id: "tx-coyote", kind: "mammal", lookalikes: ["dog-lookalike"], leaveIt: false, edibleUnlock: false, name: ["en": "Coyote"]),
            VisionLabel(id: "tx-javelina", kind: "mammal", lookalikes: ["feral-hog-lookalike"], leaveIt: false, edibleUnlock: false, name: ["en": "Javelina"]),
            VisionLabel(id: "tx-turkey", kind: "bird", lookalikes: ["vulture-lookalike"], leaveIt: false, edibleUnlock: false, name: ["en": "Turkey"]),
            VisionLabel(id: "tx-western-diamondback", kind: "snake", lookalikes: ["bullsnake-lookalike"], leaveIt: false, edibleUnlock: false, name: ["en": "Western diamondback"]),
            VisionLabel(id: "tx-amanita", kind: "fungi", lookalikes: ["x"], leaveIt: true, edibleUnlock: false, name: ["en": "Amanita"]),
        ])
    }
}
