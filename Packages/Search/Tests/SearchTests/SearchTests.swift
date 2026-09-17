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
        XCTAssertEqual(SearchIndex.rangeLabel(340), "1115 FT")
        XCTAssertEqual(SearchIndex.rangeLabel(12_400), "7.7 MI")
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

    func testLookupCapsAndStillFindsAPrefix() {
        var pois: [[String: Any]] = (1...40).map { i in
            ["name": "Street \(i)", "kind": "street", "lat": 31.0, "lon": -106.0]
        }
        pois.append(["name": "Montana Avenue", "kind": "street", "lat": 31.78, "lon": -106.42])
        let idx = SearchIndex(pois: pois)
        let hits = idx.lookup("street", cap: 5)
        XCTAssertEqual(hits.count, 5)
        XCTAssertEqual(idx.lookup("montana ave").first?.name, "Montana Avenue")
        let mark = SearchExtra(name: "HOME", kind: "mark", lat: 31.76, lon: -106.49)
        XCTAssertEqual(idx.lookup("home", extra: [mark]).first?.kind, "mark")
    }

    func testHouseNumberFindsMontanaAddress() {
        let packed: [String: Any] = [
            "docs": [[
                "Montana Avenue", "street", 31.78, -106.45,
            ]],
            "addr": [
                "streets": ["Montana Avenue"],
                "zips": ["79902"],
                "ranges": [[0, 201, 299, 0, 3_176_000, -10_650_000, 3_178_000, -10_640_000]],
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: packed)
        let book = SearchIndex.load(data: data)
        let hit = book.lookup("221 montana").first
        XCTAssertEqual(hit?.kind, "address")
        XCTAssertEqual(hit?.name, "221 Montana Avenue")
        XCTAssertEqual(hit?.city, "El Paso")
        XCTAssertEqual(hit?.post, "79902")
        XCTAssertGreaterThanOrEqual(hit?.sure ?? 0, 70)
        XCTAssertEqual(SearchHUDWord.from(packed: "address").title, "ADDRESS")
        XCTAssertNotNil(SearchIndex.houseQuery("221 montana"))
    }

    func testTypeOnlyStreetIsNotEveryDoor() {
        let packed: [String: Any] = [
            "docs": [[
                "Main Street", "street", 31.76, -106.49,
            ]],
            "addr": [
                "streets": ["Main Street", "Kansas Street", "Montana Avenue"],
                "zips": ["79901", "79902"],
                "ranges": [
                    [0, 201, 299, 0, 3_176_000, -10_649_000, 3_176_100, -10_648_000],
                    [1, 201, 299, 0, 3_176_200, -10_649_500, 3_176_300, -10_648_500],
                    [2, 201, 299, 1, 3_177_700, -10_647_500, 3_177_900, -10_645_500],
                ],
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: packed)
        let book = SearchIndex.load(data: data)
        XCTAssertFalse(book.lookup("221 st").contains { $0.kind == "address" })
        XCTAssertTrue(book.lookup("221").isEmpty)
        let hit = book.lookup("221 montana").first
        XCTAssertEqual(hit?.kind, "address")
        XCTAssertEqual(hit?.name, "221 Montana Avenue")
        XCTAssertTrue(hit?.lat.isFinite ?? false)
        XCTAssertTrue(hit?.lon.isFinite ?? false)
    }

    func testCutAddrRangeDoesNotCrash() {
        let packed: [String: Any] = [
            "docs": [],
            "addr": [
                "streets": ["Montana Avenue"],
                "zips": ["79902"],
                "ranges": [[0, 201]],
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: packed)
        let book = SearchIndex.load(data: data)
        XCTAssertTrue(book.lookup("221 montana").isEmpty)
    }

    func testStreetNameNearAPackedStreetAndNotAtNullIsland() {
        let idx = SearchIndex(pois: [
            ["name": "Montana Avenue", "kind": "street", "lat": 31.783693, "lon": -106.419278],
            ["name": "Piedras Street", "kind": "street", "lat": 31.780000, "lon": -106.419278],
        ])
        XCTAssertEqual(
            idx.streetName(near: 31.783693, lon: -106.419278),
            "Montana Avenue"
        )
        XCTAssertNil(idx.streetName(near: 0, lon: 0))
        let names = idx.streetNames(along: [
            (31.783693, -106.419278),
            (31.783693, -106.418000),
        ])
        XCTAssertEqual(names, ["Montana Avenue"])
    }
}
