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

    func testCactusStillIsThePackCactus() {
        let g = VisionCoreML.classify(
            observations: [VisionObservation(identifier: "Cactus", confidence: 0.8)],
            book: txBook()
        )
        XCTAssertFalse(g.noModel)
        XCTAssertFalse(g.edible)
        XCTAssertEqual(g.percent, 0)
        XCTAssertEqual(g.name, "PRICKLY PEAR")
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

    private func txBook() -> VisionBook {
        VisionBook(state: "TX", neverEdibleUnlock: true, fungiDefault: "LEAVE_IT", labels: [
            VisionLabel(id: "tx-prickly-pear", kind: "cactus", lookalikes: ["glochid-lookalike"], leaveIt: false, edibleUnlock: false, name: ["en": "Prickly pear"]),
            VisionLabel(id: "tx-coyote", kind: "mammal", lookalikes: ["dog-lookalike"], leaveIt: false, edibleUnlock: false, name: ["en": "Coyote"]),
            VisionLabel(id: "tx-western-diamondback", kind: "snake", lookalikes: ["bullsnake-lookalike"], leaveIt: false, edibleUnlock: false, name: ["en": "Western diamondback"]),
            VisionLabel(id: "tx-amanita", kind: "fungi", lookalikes: ["x"], leaveIt: true, edibleUnlock: false, name: ["en": "Amanita"]),
        ])
    }
}
