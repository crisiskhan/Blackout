import XCTest
@testable import VisionCoreML

final class VisionCoreMLTests: XCTestCase {
    func testNoModelNotHashID() throws {
        XCTAssertFalse(VisionCoreML.onDeviceModelPresent)
        let book = VisionBook(state: "TX", neverEdibleUnlock: true, fungiDefault: "LEAVE_IT", labels: [
            VisionLabel(id: "tx-amanita", kind: "fungi", lookalikes: ["x"], leaveIt: true, edibleUnlock: false, marineOrGatorFL: false, name: ["en": "Amanita"])
        ])
        let g = VisionCoreML.classify(features: [0.2, 0.8], book: book)
        XCTAssertTrue(g.noModel)
        XCTAssertEqual(g.name, "NO VISION MODEL")
        XCTAssertEqual(g.percent, 0)
        XCTAssertFalse(g.edible)
        XCTAssertTrue(g.leaveIt)
        XCTAssertEqual(g.labelId, "no-model")
    }
}
