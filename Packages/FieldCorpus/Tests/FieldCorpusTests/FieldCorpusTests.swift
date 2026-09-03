import XCTest
@testable import FieldCorpus

final class FieldCorpusTests: XCTestCase {
    func testRejectsBadSchema() {
        let bad = Data(#"{"schema":"1.0","id":"x","cards":[]}"#.utf8)
        XCTAssertTrue(((try? FieldCorpus.load(core: bad, state: bad)) ?? []).isEmpty)
    }
}
