import XCTest
@testable import Search

final class SearchTests: XCTestCase {
    func testFTSAndSemantic() {
        let idx = SearchIndex(pois: [
            ["name": "County Hospital", "kind": "hospital", "lat": 31.7, "lon": -106.4],
            ["name": "Spring", "kind": "drinking_water", "lat": 31.8, "lon": -106.5],
        ])
        XCTAssertEqual(idx.fts("hospital").first?.name, "County Hospital")
        XCTAssertEqual(idx.semantic("water").first?.kind, "drinking_water")
    }
}
