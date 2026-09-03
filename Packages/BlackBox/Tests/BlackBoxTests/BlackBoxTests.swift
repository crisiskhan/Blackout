import XCTest
@testable import BlackBox

final class EventLogTests: XCTestCase {
    func testAppend() throws {
        let box = EventLog()
        box.log("airplane", "deny-all sockets")
        XCTAssertEqual(box.all().count, 1)
        XCTAssertTrue(try box.jsonl().contains("deny-all"))
    }
}
