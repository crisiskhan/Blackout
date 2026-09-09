import XCTest
@testable import MapLibreMap

/// The hold card is the first thing in this app that offers an opinion about
/// water, so most of what is worth testing is what it refuses to say.
final class InspectTests: XCTestCase {
    func testANamedRiverReadsAsItself() {
        let card = Inspect.read(tags: ["waterway": "river", "name": "Rio Grande"])
        XCTAssertEqual(card.title, "Rio Grande")
        XCTAssertEqual(card.klass, "River")
        XCTAssertEqual(card.kind, .water)
        XCTAssertGreaterThan(card.sure, 80)
    }

    func testAnUnnamedStreamIsAWashAndSaysSoWithLessConfidence() {
        let creek = Inspect.read(tags: ["waterway": "stream", "name": "Ash Creek"])
        let wash = Inspect.read(tags: ["waterway": "stream"])
        XCTAssertEqual(creek.klass, "Creek")
        XCTAssertEqual(wash.klass, "Wash or stream")
        XCTAssertEqual(wash.title, Inspect.unnamed)
        // The record says less about the unnamed one, so the card claims less.
        XCTAssertLessThan(wash.sure, creek.sure)
        XCTAssertTrue(wash.why.contains("dry between rains"), wash.why)
    }

    func testAnEmptyHoldIsStillAnAnswer() {
        // A hold that finds nothing must not be a dead press. It reports the
        // ground and still offers Field and Mark.
        let card = Inspect.read(tags: [:])
        XCTAssertEqual(card.title, Inspect.unnamed)
        XCTAssertEqual(card.klass, "Open ground")
        XCTAssertEqual(card.kind, .nothing)
        XCTAssertFalse(card.why.isEmpty)
    }

    func testSureIsAboutTheRecordAndNeverAboutDrinking() {
        let claims = ["safe", "potable", "drinkable", "drink", "clean", "pure", "edible", "poison"]
        for tags in Self.everyKindOfThing {
            let card = Inspect.read(tags: tags)
            let sentence = (card.why + " " + card.klass).lowercased()
            for claim in claims {
                XCTAssertFalse(
                    sentence.contains(claim),
                    "SURE for \(tags) says \(claim.uppercased()) in: \(card.why)"
                )
            }
            XCTAssertTrue((5...97).contains(card.sure), "\(tags) -> \(card.sure)")
        }
    }

    func testATankIsOnlyWaterIfTheRecordSaysSo() {
        // Around El Paso only 110 of 585 storage tanks say `content=water`.
        // 470 say nothing, and a few say fuel. The silent ones must not be
        // offered as a supply.
        let silent = Inspect.read(tags: ["man_made": "storage_tank"])
        XCTAssertEqual(silent.klass, "Tank, contents unrecorded")
        XCTAssertEqual(silent.advice, .leave)
        XCTAssertLessThan(silent.sure, 50)

        let water = Inspect.read(tags: ["man_made": "storage_tank", "content": "water"])
        XCTAssertEqual(water.klass, "Water tank")
        XCTAssertEqual(water.advice, .treat)
        XCTAssertGreaterThan(water.sure, silent.sure)

        let fuel = Inspect.read(tags: ["man_made": "storage_tank", "content": "fuel"])
        XCTAssertEqual(fuel.advice, .leave)
        XCTAssertTrue(fuel.klass.contains("fuel"), fuel.klass)

        // A tank tagged as water outright needs no content to be believed.
        XCTAssertEqual(Inspect.read(tags: ["man_made": "water_tank"]).advice, .treat)
        XCTAssertEqual(Inspect.read(tags: ["man_made": "storage_tank", "content": "sewage"]).advice, .leave)
    }

    func testWaterSaysTreatAndRunoffSaysLeaveItAndGroundSendsYouToField() {
        XCTAssertEqual(Inspect.read(tags: ["natural": "spring"]).advice, .treat)
        XCTAssertEqual(Inspect.read(tags: ["waterway": "canal"]).advice, .treat)
        // A drain carries whatever ran off the ground above it.
        XCTAssertEqual(Inspect.read(tags: ["waterway": "drain"]).advice, .leave)
        XCTAssertEqual(Inspect.read(tags: ["natural": "scrub"]).advice, .field)
    }

    func testEveryCardOpensAFieldCardThatEveryStateShips() {
        // Field books are core plus one state. Routing a hold at a TX-only card
        // would open nothing in New Mexico.
        let core: Set<String> = [
            Inspect.waterCard, Inspect.plantCard, Inspect.heatCard,
            Inspect.coldCard, Inspect.lostCard,
        ]
        for tags in Self.everyKindOfThing {
            XCTAssertTrue(
                core.contains(Inspect.read(tags: tags).fieldCardID),
                "\(tags) opens \(Inspect.read(tags: tags).fieldCardID)"
            )
        }
    }

    func testWaterOutranksGroundAndGroundOutranksRoad() {
        // Holding where a wash crosses a road is a question about the wash. The
        // road already has its name written along it.
        let found: [[String: String]] = [
            ["highway": "residential", "name": "Alameda Ave"],
            ["natural": "scrub"],
            ["waterway": "stream"],
        ]
        XCTAssertEqual(Inspect.pick(found)["waterway"], "stream")
    }

    func testANamedRecordWinsOverAnUnnamedOneOfTheSameKind() {
        let found: [[String: String]] = [
            ["waterway": "canal"],
            ["waterway": "canal", "name": "Franklin Canal"],
        ]
        XCTAssertEqual(Inspect.pick(found)["name"], "Franklin Canal")
    }

    func testPickIgnoresTheAppsOwnOverlays() {
        // The puck, the route and the pins carry no record. They are excluded
        // by layer before the probe ever sees them, and an empty bag of tags
        // must not win if one slips through.
        XCTAssertTrue(Inspect.pick([[:], [:]]).isEmpty)
        XCTAssertEqual(Inspect.pick([[:], ["natural": "spring"]])["natural"], "spring")
        XCTAssertTrue(Inspect.overlayLayerIDs.contains(RouteLine.layerID))
        XCTAssertTrue(Inspect.overlayLayerIDs.contains(HoldPin.ringLayerID))
        XCTAssertTrue(Inspect.overlayLayerIDs.contains(DestinationPin.coreLayerID))
    }

    func testTheHoldIsShortEnoughToFeelInstantAndTightEnoughToStayAPan() {
        XCTAssertEqual(Inspect.holdSeconds, 0.4, accuracy: 0.001)
        // Past this drift the thumb was panning, and the map keeps the drag.
        XCTAssertGreaterThan(Inspect.holdDriftPoints, 0)
        XCTAssertLessThanOrEqual(Inspect.holdDriftPoints, 16)
        // A thumb is fatter than a pixel, so the probe reads a box.
        XCTAssertGreaterThanOrEqual(Inspect.holdProbePoints, 40)
    }

    func testALowHoldIsLiftedAboveWhereTheCardWillBe() {
        // Lifting has to move the point up, never down.
        XCTAssertLessThan(Inspect.holdLiftTo, Inspect.holdLiftBelow)
        // The card takes the bottom half, so a point already in the top half is
        // left where it is. This module cannot see Tokens; the guard in
        // tools/test_hold_and_water.py ties this to the card's actual cap.
        XCTAssertLessThanOrEqual(Inspect.holdLiftBelow, 0.5)
        XCTAssertGreaterThan(Inspect.holdLiftTo, 0)
    }

    func testThePackDateIsPrintedWhenThereIsOneAndOmittedWhenThereIsNot() {
        XCTAssertEqual(Inspect.read(tags: [:], packDate: "2026-09-09").packDate, "2026-09-09")
        // A pack with no recorded fetch says nothing rather than inventing a day.
        XCTAssertNil(Inspect.read(tags: [:]).packDate)
    }

    /// One of every branch the reader has, so the honesty checks above run over
    /// the whole table rather than the two cases someone remembered.
    static let everyKindOfThing: [[String: String]] = [
        [:],
        ["natural": "spring"],
        ["natural": "spring", "name": "Hueco Spring"],
        ["man_made": "water_well"],
        ["man_made": "water_tank"],
        ["man_made": "cistern"],
        ["man_made": "storage_tank"],
        ["man_made": "storage_tank", "content": "water"],
        ["man_made": "storage_tank", "content": "fuel"],
        ["man_made": "storage_tank", "content": "sewage"],
        ["man_made": "storage_tank", "content": "unknown"],
        ["man_made": "reservoir_covered"],
        ["amenity": "drinking_water"],
        ["waterway": "river", "name": "Rio Grande"],
        ["waterway": "stream"],
        ["waterway": "stream", "name": "Ash Creek"],
        ["waterway": "canal", "name": "Franklin Canal"],
        ["waterway": "ditch"],
        ["waterway": "drain"],
        ["waterway": "dam"],
        ["waterway": "weir"],
        ["waterway": "wadi"],
        ["waterway": "fish_ladder"],
        ["landuse": "reservoir"],
        ["natural": "water"],
        ["natural": "water", "name": "Elephant Butte"],
        ["natural": "peak", "name": "North Franklin"],
        ["natural": "wood"],
        ["natural": "scrub"],
        ["natural": "sand"],
        ["natural": "wetland"],
        ["natural": "bare_rock"],
        ["natural": "grassland"],
        ["boundary": "protected_area"],
        ["leisure": "park"],
        ["landuse": "forest"],
        ["landuse": "farmland"],
        ["place": "city", "name": "El Paso"],
        ["place": "hamlet"],
        ["highway": "residential", "name": "Alameda Ave"],
        ["highway": "track"],
        ["highway": "path"],
        ["highway": "service"],
    ]
}
