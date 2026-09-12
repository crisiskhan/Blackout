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

    func testPrefixFindsHospital() {
        let idx = SearchIndex(pois: [
            ["name": "County Hospital", "kind": "hospital", "lat": 31.7, "lon": -106.4],
            ["name": "Spring", "kind": "drinking_water", "lat": 31.8, "lon": -106.5],
        ])
        XCTAssertEqual(idx.lookup("hosp").first?.name, "County Hospital")
    }

    func testDiacriticFoldsNinos() {
        let idx = SearchIndex(pois: [
            ["name": "Niños Heroes de Chapultepec", "kind": "place", "lat": 30.96, "lon": -107.49],
        ])
        XCTAssertEqual(idx.lookup("ninos").first?.name, "Niños Heroes de Chapultepec")
    }

    func testProximityRanksNearer() {
        let idx = SearchIndex(pois: [
            ["name": "Far Hospital", "kind": "hospital", "lat": 32.5, "lon": -106.4],
            ["name": "Near Hospital", "kind": "hospital", "lat": 31.76, "lon": -106.49],
        ])
        let hits = idx.lookup("hospital", you: (lat: 31.76, lon: -106.49))
        XCTAssertEqual(hits.first?.name, "Near Hospital")
        XCTAssertNotNil(hits.first?.meters)
        XCTAssertLessThan(hits.first?.meters ?? 9e9, 2_000)
    }

    func testCoordinatePasteIsAHit() {
        let idx = SearchIndex(pois: [])
        let hits = idx.lookup("31.76190, -106.49000")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.kind, "coordinates")
        XCTAssertEqual(hits.first?.lat ?? 0, 31.76190, accuracy: 0.00001)
        XCTAssertEqual(hits.first?.lon ?? 0, -106.49000, accuracy: 0.00001)
        XCTAssertEqual(SearchHUDWord.from(packed: "coordinates").title, "COORDINATES")
    }

    func testEmptyQueryIsNotADump() {
        let idx = SearchIndex(pois: [
            ["name": "County Hospital", "kind": "hospital", "lat": 31.7, "lon": -106.4],
        ])
        XCTAssertFalse(SearchIndex.asking("  "))
        XCTAssertTrue(idx.lookup("").isEmpty)
        XCTAssertTrue(idx.lookup("   ").isEmpty)
        XCTAssertEqual(SearchHUDWord.from(packed: "drinking_water").title, "WATER")
        XCTAssertEqual(SearchHUDWord.from(packed: "residential").title, "STREET")
        XCTAssertEqual(SearchIndex.rangeLabel(340), "340 M")
        XCTAssertEqual(SearchIndex.rangeLabel(12_400), "12.4 KM")
    }

    func testAvenueAliasAndNamePrefix() {
        let idx = SearchIndex(pois: [
            ["name": "Montana Avenue", "kind": "street", "lat": 31.78, "lon": -106.42],
            ["name": "West Montana", "kind": "street", "lat": 31.76, "lon": -106.49],
        ])
        XCTAssertEqual(idx.lookup("montana ave").first?.name, "Montana Avenue")
        let hits = idx.lookup("montana", you: (lat: 31.76, lon: -106.49))
        XCTAssertEqual(hits.first?.name, "Montana Avenue")
    }

    func testTypoFindsGardner() {
        let idx = SearchIndex(pois: [
            ["name": "Gardner Peak", "kind": "peak", "lat": 32.82, "lon": -106.56],
        ])
        XCTAssertEqual(idx.lookup("gardnr").first?.name, "Gardner Peak")
        XCTAssertEqual(idx.lookup("gardner peak").first?.name, "Gardner Peak")
    }
}
