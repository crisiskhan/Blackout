import XCTest
@testable import BlackoutCore

final class MapPackSchemaTests: XCTestCase {
    func testMissingSchemaIsV1() {
        XCTAssertEqual(MapPackLayout.schema, 1)
        XCTAssertEqual(MapPackLayout.tooNewCopy, "Pack too new.")
        XCTAssertEqual(MapPackLayout.schema(from: ["name": "Front Range sample"]), 1)
        XCTAssertTrue(MapPackLayout.isSupported(1))
        XCTAssertTrue(MapPackLayout.isSupported(MapPackLayout.schema(from: [:])))
    }

    func testExplicitSchemaOneIsSupported() {
        XCTAssertTrue(MapPackLayout.isSupported(MapPackLayout.schema(from: ["schema": 1])))
    }

    func testNewerSchemaIsTooNew() {
        XCTAssertFalse(MapPackLayout.isSupported(MapPackLayout.schema(from: ["schema": 2])))
        XCTAssertFalse(MapPackLayout.isSupported(2))
        XCTAssertFalse(MapPackLayout.isSupported(0))
    }
}
