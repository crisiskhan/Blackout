import XCTest
@testable import VisionCoreML

final class VisionCoreMLTests: XCTestCase {
    func testNeverEdible() throws {
        let book = VisionBook(state: "TX", neverEdibleUnlock: true, fungiDefault: "LEAVE_IT", labels: [
            VisionLabel(id: "tx-amanita", kind: "fungi", lookalikes: ["x"], leaveIt: true, edibleUnlock: false, marineOrGatorFL: false, name: ["en": "Amanita"])
        ])
        let g = VisionCoreML.classify(features: [0.2, 0.8], book: book)
        XCTAssertFalse(g.edible)
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.lookalikes.isEmpty)
    }
}
