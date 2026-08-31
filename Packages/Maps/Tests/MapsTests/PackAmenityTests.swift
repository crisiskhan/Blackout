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

    func testFullCivicShopAndFieldKindsPaintAtCloseZoom() {
        let kinds = [
            "shop", "grocery", "supermarket", "convenience", "mall", "hardware", "clothes",
            "fuel", "pharmacy", "hospital", "clinic", "dentist", "dentists",
            "police", "fire_station", "post_office", "school", "bank", "atm",
            "cafe", "fast_food", "restaurant", "bar", "pub",
            "toilets", "parking", "charging_station",
            "hotel", "motel", "lodging", "camp_site", "information",
            "office", "craft",
            "water", "spring", "town", "ranger", "mill", "road", "rail"
        ]
        for kind in kinds {
            XCTAssertTrue(PackAmenityPolicy.paintsOnMap(kind), kind)
            XCTAssertTrue(PackAmenityPolicy.showsPins(zoom: 11))
        }
        XCTAssertFalse(PackAmenityPolicy.paintsOnMap("address"))
        let pharmacy = RoutingPOI(
            id: "rx-1",
            name: "Mesa Pharmacy",
            kind: "pharmacy",
            coordinate: RoutingCoordinate(latitude: 31.76, longitude: -106.48)
        )
        let hit = PackSearch.query("mesa pharmacy", pack: nil, pois: [pharmacy], addresses: [])
        XCTAssertEqual(hit.hits.first?.kind, "pharmacy")
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

    func testPinHitSelectsNearbyPackPOIAndMissesEmptyTap() {
        let cafe = RoutingPOI(
            id: "cafe-1",
            name: "H&H Car Wash",
            kind: "restaurant",
            coordinate: RoutingCoordinate(latitude: 31.758, longitude: -106.487)
        )
        XCTAssertEqual(
            PackAmenityPolicy.pinHit(
                latitude: 31.75805,
                longitude: -106.487,
                pins: [cafe],
                zoom: 12
            )?.name,
            "H&H Car Wash"
        )
        XCTAssertNil(
            PackAmenityPolicy.pinHit(
                latitude: 31.80,
                longitude: -106.40,
                pins: [cafe],
                zoom: 12
            )
        )
        XCTAssertNil(
            PackAmenityPolicy.pinHit(
                latitude: 31.75805,
                longitude: -106.487,
                pins: [cafe],
                zoom: 10
            )
        )
    }

    func testFindCivilizationIncludesStores() {
        XCTAssertTrue(PackFind.matches(kind: "restaurant", mode: .civilization))
        XCTAssertTrue(PackFind.matches(kind: "grocery", mode: .civilization))
        XCTAssertTrue(PackFind.matches(kind: "pharmacy", mode: .civilization))
        XCTAssertTrue(PackFind.matches(kind: "school", mode: .civilization))
        XCTAssertTrue(PackFind.matches(kind: "police", mode: .civilization))
        XCTAssertTrue(PackFind.matches(kind: "hotel", mode: .civilization))
        XCTAssertTrue(PackFind.matches(kind: "office", mode: .civilization))
        XCTAssertFalse(PackFind.matches(kind: "address", mode: .civilization))
        XCTAssertFalse(PackFind.matches(kind: "spring", mode: .civilization))
    }
}
