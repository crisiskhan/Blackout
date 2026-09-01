import XCTest
@testable import BlackoutCore

final class GuidePackSchemaTests: XCTestCase {
    func testMissingAndV1AreSupported() {
        XCTAssertEqual(GuidePackSchema.current, 1)
        XCTAssertEqual(GuidePackSchema.tooNewCopy, "Guide schema too new.")
        XCTAssertEqual(GuidePackSchema.inspect(manifest: [:], articles: [], inverted: [:]), .compatible)
        XCTAssertEqual(
            GuidePackSchema.inspect(manifest: ["schema": 1], articles: [["id": "a"]], inverted: ["water": ["a": 1]]),
            .compatible
        )
    }

    func testManifestNewerIsTooNew() {
        XCTAssertEqual(
            GuidePackSchema.inspect(manifest: ["schema": 2], articles: [["id": "a"]], inverted: [:]),
            .tooNew
        )
    }

    func testArticleNewerIsTooNewNotASilentSkip() {
        XCTAssertEqual(
            GuidePackSchema.inspect(
                manifest: ["schema": 1],
                articles: [["id": "a"], ["id": "b", "schema": 2]],
                inverted: [:]
            ),
            .tooNew
        )
    }

    func testInvertedWrapperNewerIsTooNew() {
        XCTAssertEqual(
            GuidePackSchema.inspect(
                manifest: ["schema": 1],
                articles: [["id": "a"]],
                inverted: ["schema": 2, "terms": ["water": ["a": 1]]]
            ),
            .tooNew
        )
    }

    func testInvertedTermNamedSchemaIsStillV1() {
        XCTAssertEqual(
            GuidePackSchema.inspect(
                manifest: ["schema": 1],
                articles: [["id": "a"]],
                inverted: ["schema": ["a": 1], "water": ["a": 2]]
            ),
            .compatible
        )
    }
}
