import XCTest
@testable import MapsRouting

final class PackAmenityTests: XCTestCase {
    func testAmenityKindsAreSearchableAndNotEveryAddress() {
        XCTAssertTrue(PackAmenityPolicy.isAmenity("restaurant"))
        XCTAssertTrue(PackAmenityPolicy.isAmenity("cafe"))
        XCTAssertTrue(PackAmenityPolicy.isAmenity("shop"))
        XCTAssertTrue(PackAmenityPolicy.isAmenity("grocery"))
        XCTAssertTrue(PackAmenityPolicy.isAmenity("fuel"))
        XCTAssertTrue(PackAmenityPolicy.isAmenity("lodging"))
        XCTAssertTrue(PackAmenityPolicy.isAmenity("hospital"))
        XCTAssertFalse(PackAmenityPolicy.isAmenity("address"))
        XCTAssertFalse(PackAmenityPolicy.isAmenity("house"))
        XCTAssertFalse(PackAmenityPolicy.paintsOnMap("address"))
        XCTAssertTrue(PackAmenityPolicy.paintsOnMap("restaurant"))
        XCTAssertTrue(PackAmenityPolicy.paintsOnMap("water"))
        XCTAssertTrue(PackAmenityPolicy.paintsOnMap("town"))
    }

    func testPinsOnlyAtCloseZoomAndDensityCap() {
        XCTAssertFalse(PackAmenityPolicy.showsPins(zoom: 10))
        XCTAssertTrue(PackAmenityPolicy.showsPins(zoom: 11))
        XCTAssertTrue(PackAmenityPolicy.showsPins(zoom: 12))
        let pins = (0..<80).map { i in
            RoutingPOI(
                id: "p\(i)",
                name: "Cafe \(i)",
                kind: "cafe",
                coordinate: RoutingCoordinate(latitude: 31.76 + Double(i) * 0.001, longitude: -106.48)
            )
        }
        XCTAssertEqual(PackAmenityPolicy.cap(pins, limit: 48).count, 48)
    }

    func testSearchHitsRestaurantAndHouseNumberWithoutLiveGeocoder() {
        let cafe = RoutingPOI(
            id: "cafe-1",
            name: "H&H Car Wash",
            kind: "restaurant",
            coordinate: RoutingCoordinate(latitude: 31.758, longitude: -106.487)
        )
        let addresses = [
            RoutingAddress(
                id: "addr-1",
                house: "221",
                street: "Mesa Street",
                coordinate: RoutingCoordinate(latitude: 31.760, longitude: -106.490)
            )
        ]
        let byName = PackSearch.query("h&h", pack: nil, pois: [cafe], addresses: addresses)
        XCTAssertEqual(byName.hits.first?.title, "H&H Car Wash")
        XCTAssertNil(byName.empty)

        let byAddress = PackSearch.query("221 mesa", pack: nil, pois: [cafe], addresses: addresses)
        XCTAssertEqual(byAddress.hits.first?.title, "221 Mesa Street")
        XCTAssertEqual(byAddress.hits.first?.kind, "address")

        let miss = PackSearch.query("zzzz", pack: nil, pois: [cafe], addresses: addresses)
        XCTAssertEqual(miss.empty, .searchMiss)
    }

    func testNewerPOISchemaFailsClosed() {
        let v1 = Data("{\"schema\":1,\"pois\":[{\"id\":\"a\",\"name\":\"Cafe\",\"kind\":\"cafe\",\"lat\":31.7,\"lon\":-106.4}]}".utf8)
        let v2 = Data("{\"schema\":2,\"pois\":[{\"id\":\"a\",\"name\":\"Cafe\",\"kind\":\"cafe\",\"lat\":31.7,\"lon\":-106.4}]}".utf8)
        XCTAssertEqual(PackPOIFile.places(from: v1)?.count, 1)
        XCTAssertNil(PackPOIFile.places(from: v2))
        XCTAssertEqual(PackPOIFile.places(from: Data("{\"pois\":[]}".utf8))?.count, 0)
        let addrV2 = Data("{\"schema\":2,\"addresses\":[]}".utf8)
        XCTAssertNil(PackPOIFile.addresses(from: addrV2))
    }

    func testFindCivilizationIncludesStores() {
        XCTAssertTrue(PackFind.matches(kind: "restaurant", mode: .civilization))
        XCTAssertTrue(PackFind.matches(kind: "grocery", mode: .civilization))
        XCTAssertFalse(PackFind.matches(kind: "address", mode: .civilization))
    }
}
