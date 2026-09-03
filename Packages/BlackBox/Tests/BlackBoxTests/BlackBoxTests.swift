import XCTest
@testable import BlackBox

final class BlackBoxTests: XCTestCase {
    func testAppend() throws {
        let box = BlackBox()
        box.log("airplane", "deny-all sockets")
        XCTAssertEqual(box.all().count, 1)
        XCTAssertTrue(try box.jsonl().contains("deny-all"))
    }
}
