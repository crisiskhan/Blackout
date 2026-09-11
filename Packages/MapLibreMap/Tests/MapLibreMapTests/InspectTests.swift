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

    /// Nothing in OSM is tagged as a tinaja, so the map cannot call anything
    /// one. What it can do is pass on the size of the outline it drew, which
    /// is the difference between a rock pool and a ranch reservoir and is the
    /// only part of the question the record can actually answer.
    func testUnnamedWaterCarriesTheSizeOfItsOwnOutline() {
        let pool = Inspect.read(tags: ["natural": "water", "span_m": "9"])
        XCTAssertTrue(pool.why.contains("9m across"), pool.why)
        XCTAssertTrue(pool.why.contains("rock pool"), pool.why)

        let tank = Inspect.read(tags: ["natural": "water", "span_m": "70"])
        XCTAssertTrue(tank.why.contains("70m across"), tank.why)
        XCTAssertFalse(tank.why.contains("rock pool"), "a 70m pool is not a rock pool: \(tank.why)")

        // Size is a fact about the outline and must not move confidence in the
        // record, or shrink into a verdict on the water.
        XCTAssertEqual(pool.sure, tank.sure)
        XCTAssertEqual(pool.advice, .treat)
        XCTAssertEqual(pool.klass, "Water body")

        // A record whose outline was never measured still has to read.
        let unmeasured = Inspect.read(tags: ["natural": "water"])
        XCTAssertFalse(unmeasured.why.isEmpty)
        XCTAssertFalse(unmeasured.why.contains("across"), unmeasured.why)

        // A name beats a measurement: if the record knows what it is, say that.
        let named = Inspect.read(tags: ["natural": "water", "span_m": "9", "name": "Ascarate Lake"])
        XCTAssertEqual(named.title, "Ascarate Lake")
        XCTAssertFalse(named.why.contains("across"), named.why)
    }

    func testGroundTheMapColoursInIsNeverReadAsOpenGround() {
        // Every record below is one the tiler gives a class and a colour. When
        // the reader has no branch for one, the map paints the ground and
        // holding it answers "nothing is mapped at this point" — which is what
        // 8,107 `landuse=residential` polygons across the three packs did.
        for tags in Self.everyKindOfThing where !tags.isEmpty {
            XCTAssertNotEqual(
                Inspect.read(tags: tags).kind, .nothing,
                "\(tags) is drawn on the map and reads back as open ground"
            )
        }
    }

    func testATownReadsAsBuiltUpGroundAndASaltPondAsASaltFlat() {
        let town = Inspect.read(tags: ["landuse": "residential"])
        XCTAssertEqual(town.klass, "Built-up ground")
        XCTAssertEqual(town.kind, .land)
        XCTAssertEqual(town.fieldCardID, Inspect.lostCard)

        let salt = Inspect.read(tags: ["landuse": "salt_pond"])
        XCTAssertEqual(salt.klass, "Salt flat")
        XCTAssertEqual(salt.kind, .land)
    }

    func testWaterSaysTreatAndRunoffSaysLeaveItAndGroundSendsYouToField() {
        XCTAssertEqual(Inspect.read(tags: ["natural": "spring"]).advice, .treat)
        XCTAssertEqual(Inspect.read(tags: ["waterway": "canal"]).advice, .treat)
        // A drain carries whatever ran off the ground above it.
        XCTAssertEqual(Inspect.read(tags: ["waterway": "drain"]).advice, .leave)
        XCTAssertEqual(Inspect.read(tags: ["natural": "scrub"]).advice, .field)
    }

    func testANamedRiverDoLineIsTheRiverNotTheGenericTreat() {
        let card = Inspect.read(tags: ["waterway": "river", "name": "Rio Grande"])
        XCTAssertEqual(card.doLine, WaterClass.river.doLine)
        XCTAssertNotEqual(card.doLine, Inspect.Advice.treat.line)
    }

    func testEveryCardOpensAFieldCardThatEveryStateShips() {
        // Field books are core plus one state. A state card answers the ground
        // better where it ships — the heat island in Texas, ice on rock in New
        // Mexico — so the card may ask for one first. But the state book that
        // has it may not be the one that is loaded, so the walk down the list
        // only ends somewhere if the last id on it is in every book.
        let core: Set<String> = [
            Inspect.waterCard, Inspect.plantCard, Inspect.heatCard,
            Inspect.coldCard, Inspect.lostCard, Inspect.plantUseCard,
            Inspect.caveCard, Inspect.biteCard, Inspect.shelterCard,
            Inspect.fungiCard, Inspect.gameCard,
        ]
        for tags in Self.everyKindOfThing {
            let card = Inspect.read(tags: tags)
            XCTAssertEqual(card.fieldRoute.last, card.fieldCardID)
            XCTAssertTrue(core.contains(card.fieldCardID), "\(tags) opens \(card.fieldCardID)")
            for preferred in card.localCardIDs {
                XCTAssertFalse(
                    core.contains(preferred),
                    "\(preferred) is a core card, so preferring it over one is a no-op"
                )
            }
            for extra in card.extraCoreIDs {
                XCTAssertTrue(core.contains(extra), "\(extra) is not a core card")
                XCTAssertNotEqual(extra, card.fieldCardID, "\(tags) lists \(extra) twice")
            }
            XCTAssertEqual(
                Set(card.fieldRoute).count, card.fieldRoute.count,
                "\(tags) asks for the same card twice"
            )
        }
    }

    func testGroundWithAStateCardOfItsOwnAsksForThatFirst() {
        // A subdivision at three in the afternoon is the heat island card, not
        // "stop and locate". A track is a ranch road, and a ranch road is where
        // the cattle guard takes an ankle. Rock in New Mexico ices over.
        XCTAssertEqual(
            Inspect.read(tags: ["landuse": "residential"]).fieldRoute,
            [Inspect.heatIslandCard, Inspect.lostCard]
        )
        XCTAssertEqual(
            Inspect.read(tags: ["highway": "track"]).fieldRoute,
            [Inspect.ranchRoadCard, Inspect.lostCard]
        )
        XCTAssertEqual(
            Inspect.read(tags: ["natural": "bare_rock"]).fieldRoute,
            [Inspect.iceRockCard, Inspect.mammalNMCard, Inspect.mammalTXCard, Inspect.coldCard]
        )
        // Water is the one thing that never diverts. Holding a spring asks the
        // treat tree and nothing else, because that is what the DO line just
        // promised.
        for tags in Self.everyKindOfThing where Inspect.read(tags: tags).kind == .water {
            XCTAssertEqual(
                Inspect.read(tags: tags).fieldRoute, [Inspect.waterCard],
                "\(tags) says treat and then opens something other than the water card"
            )
        }
    }

    func testWoodlandOpensThePacksPlantCardsBeforeUnknown() {
        // Tree cover is not a meal. The state's plant-danger card is the one
        // that names oleander or datura; plant-use is shade and deadfall; the
        // unknown-plant card is last so FIELD still lands with only the core book.
        let wood = Inspect.read(tags: ["natural": "wood"])
        XCTAssertEqual(wood.klass, "Woodland")
        XCTAssertEqual(
            Array(wood.fieldRoute.prefix(2)),
            [Inspect.plantTXCard, Inspect.plantNMCard]
        )
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.plantUseCard))
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.shelterCard))
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.biteCard))
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.gameTXCard))
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.mammalTXCard))
        XCTAssertEqual(wood.fieldRoute.last, Inspect.plantCard)
        XCTAssertEqual(InspectField.label(for: wood.fieldRoute[0]), "FIELD · PLANT")
        XCTAssertFalse(wood.doLine.lowercased().contains("edible"), wood.doLine)
    }

    func testDesertScrubOpensThePacksBiteCardsBeforeHeat() {
        // Open country is where this pack's snakes actually live. The map
        // must not draw an animal; it must open the bite cards.
        let scrub = Inspect.read(tags: ["natural": "scrub"])
        XCTAssertEqual(scrub.klass, "Desert scrub")
        XCTAssertEqual(
            Array(scrub.fieldRoute.prefix(2)),
            [Inspect.snakeTXCard, Inspect.snakeNMCard]
        )
        XCTAssertTrue(scrub.fieldRoute.contains(Inspect.biteCard))
        XCTAssertTrue(scrub.fieldRoute.contains(Inspect.plantTXCard))
        XCTAssertTrue(scrub.fieldRoute.contains(Inspect.plantUseCard))
        XCTAssertTrue(scrub.fieldRoute.contains(Inspect.mammalTXCard))
        XCTAssertTrue(scrub.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertTrue(scrub.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertTrue(scrub.fieldRoute.contains(Inspect.gameTXCard))
        XCTAssertEqual(scrub.fieldRoute.last, Inspect.heatCard)
        XCTAssertEqual(InspectField.label(for: scrub.fieldRoute[0]), "FIELD · BITE")
        XCTAssertFalse(scrub.why.lowercased().contains("edible"), scrub.why)
    }

    func testACaveRecordOpensTheCaveCardAndAPeakStaysCold() {
        let cave = Inspect.read(tags: ["natural": "cave", "name": "Hueco Tanks Cave"])
        XCTAssertEqual(cave.klass, "Cave or hole")
        XCTAssertEqual(cave.fieldRoute, [Inspect.caveCard])
        XCTAssertEqual(InspectField.label(for: cave.fieldRoute[0]), "FIELD · CAVE")

        let hole = Inspect.read(tags: ["natural": "sinkhole"])
        XCTAssertEqual(hole.klass, "Cave or hole")
        XCTAssertEqual(hole.fieldRoute.last, Inspect.caveCard)

        let peak = Inspect.read(tags: ["natural": "peak", "name": "North Franklin"])
        XCTAssertEqual(peak.klass, "Peak")
        XCTAssertEqual(peak.fieldRoute, [
            Inspect.iceRockCard, Inspect.mammalNMCard, Inspect.mammalTXCard, Inspect.coldCard,
        ])
        XCTAssertEqual(InspectField.label(for: peak.fieldRoute[0]), "FIELD · COLD")
    }

    func testANamedTreeIsPlantGroundNotAMeal() {
        let tree = Inspect.read(tags: ["natural": "tree", "name": "El Paso Cottonwood"])
        XCTAssertEqual(tree.title, "El Paso Cottonwood")
        XCTAssertEqual(tree.klass, "Named tree")
        XCTAssertEqual(tree.fieldRoute.last, Inspect.plantCard)
        XCTAssertTrue(tree.fieldRoute.contains(Inspect.plantTXCard))
        XCTAssertFalse(tree.doLine.lowercased().contains("edible"), tree.doLine)
    }

    func testTheOpenPackNamesItsTreesAndAnimalsAsRangeNotPins() {
        // The hold names the Field book of the open pack. It does not pin a
        // javelina to a coordinate.
        let txWood = Inspect.read(tags: ["natural": "wood"], state: "TX")
        XCTAssertTrue(txWood.doLine.contains("Mesquite"), txWood.doLine)
        XCTAssertTrue(txWood.doLine.contains("not a meal"), txWood.doLine)
        XCTAssertFalse(txWood.doLine.lowercased().contains("edible"), txWood.doLine)

        let nmWood = Inspect.read(tags: ["natural": "wood"], state: "NM")
        XCTAssertTrue(nmWood.doLine.contains("Cottonwood") || nmWood.doLine.contains("piñon") || nmWood.doLine.contains("Piñon") || nmWood.doLine.contains("juniper") || nmWood.doLine.contains("Juniper"), nmWood.doLine)

        let txScrub = Inspect.read(tags: ["natural": "scrub"], state: "TX")
        XCTAssertTrue(txScrub.doLine.contains("Javelina") || txScrub.doLine.contains("Diamondback"), txScrub.doLine)
        XCTAssertFalse(txScrub.doLine.lowercased().contains("edible"), txScrub.doLine)
        XCTAssertFalse(txScrub.doLine.lowercased().contains("lives here"), txScrub.doLine)
        XCTAssertFalse(txScrub.doLine.lowercased().contains("standing here"), txScrub.doLine)
        XCTAssertTrue(txScrub.doLine.contains("Yucca") || txScrub.doLine.contains("prickly"), txScrub.doLine)

        let nmPeak = Inspect.read(tags: ["natural": "peak", "name": "Wheeler"], state: "NM")
        XCTAssertTrue(nmPeak.doLine.lowercased().contains("bear"), nmPeak.doLine)
        XCTAssertEqual(InspectField.label(for: Inspect.mammalNMCard), "FIELD · ANIMAL")
    }

    func testTheLoadedBookDropsTheOtherStatesCardAndKeepsTheCoreTrail() {
        // A Texas pack has no New Mexico plant-danger card. The hold still
        // named both; FIELD has to skip the missing one and keep plant-use,
        // shelter, fungi and game so DONE can walk the rest of the ground.
        let wood = Inspect.read(tags: ["natural": "wood"]).fieldRoute
        let texas: Set<String> = [
            Inspect.plantTXCard, Inspect.treeUseTXCard, Inspect.cactusTXCard,
            Inspect.mammalTXCard, Inspect.gameTXCard, Inspect.plantUseCard,
            Inspect.biteCard, Inspect.shelterCard, Inspect.fungiCard,
            Inspect.gameCard, Inspect.plantCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(wood, in: texas),
            [
                Inspect.plantTXCard, Inspect.treeUseTXCard, Inspect.cactusTXCard,
                Inspect.mammalTXCard, Inspect.gameTXCard, Inspect.plantUseCard,
                Inspect.biteCard, Inspect.shelterCard, Inspect.fungiCard,
                Inspect.gameCard, Inspect.plantCard,
            ]
        )
        XCTAssertEqual(InspectField.nextAction(for: Inspect.plantUseCard), "NEXT · PLANT")
        XCTAssertEqual(InspectField.nextAction(for: Inspect.mammalTXCard), "NEXT · ANIMAL")
        XCTAssertEqual(InspectField.nextAction(for: Inspect.shelterCard), "NEXT · SHELTER")
        XCTAssertEqual(InspectField.nextAction(for: Inspect.fungiCard), "NEXT · FUNGI")
        XCTAssertEqual(InspectField.nextAction(for: Inspect.gameCard), "NEXT · FOOD")

        let scrub = Inspect.read(tags: ["natural": "scrub"]).fieldRoute
        let nm: Set<String> = [
            Inspect.snakeNMCard, Inspect.mammalNMCard, Inspect.cactusNMCard,
            Inspect.treeUseNMCard, Inspect.plantNMCard, Inspect.biteCard,
            Inspect.gameCard, Inspect.heatCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(scrub, in: nm).prefix(3).map { $0 },
            [Inspect.snakeNMCard, Inspect.mammalNMCard, Inspect.cactusNMCard]
        )
        XCTAssertEqual(InspectField.nextAction(for: Inspect.biteCard), "NEXT · BITE")
        XCTAssertEqual(InspectField.nextAction(for: Inspect.heatCard), "NEXT · HEAT")

        // Water is one card. DONE stays DONE.
        XCTAssertEqual(
            InspectField.presentRoute([Inspect.waterCard], in: [Inspect.waterCard]),
            [Inspect.waterCard]
        )
    }

    func testWaterOutranksEverythingElseUnderTheThumb() {
        // Holding where a wash crosses a named road is a question about the
        // wash. The road already has its name written along it, and finding
        // water is what holding a place is for.
        let found: [[String: String]] = [
            ["highway": "residential", "name": "Alameda Ave"],
            ["natural": "scrub"],
            ["waterway": "stream"],
        ]
        XCTAssertEqual(Inspect.pick(found)["waterway"], "stream")
    }

    func testATownPolygonDoesNotSwallowTheStreetYouHeld() {
        // `landuse=residential` is a sheet under every street in the city, so
        // on kind alone it would answer every hold downtown with the same
        // anonymous ground.
        let downtown: [[String: String]] = [
            ["landuse": "residential"],
            ["highway": "secondary", "name": "Alameda Ave"],
        ]
        XCTAssertEqual(Inspect.pick(downtown)["name"], "Alameda Ave")

        // Naming the subdivision must not put it back in front. This is the
        // real Las Cruces case: Gramercy Park over East Amador Avenue.
        let named: [[String: String]] = [
            ["landuse": "residential", "name": "Gramercy Park"],
            ["highway": "secondary", "name": "East Amador Avenue"],
        ]
        XCTAssertEqual(Inspect.pick(named)["highway"], "secondary")

        // Out of town the rule flips: an unnamed track is not the answer to
        // "what is this ground", and the biome is.
        let backcountry: [[String: String]] = [
            ["natural": "scrub"],
            ["highway": "track"],
        ]
        XCTAssertEqual(Inspect.pick(backcountry)["natural"], "scrub")

        // A named piece of ground still beats a track nobody named.
        XCTAssertEqual(
            Inspect.pick([["natural": "wetland", "name": "Mesilla Bosque"], ["highway": "track"]])["name"],
            "Mesilla Bosque"
        )

        // Water outranks all of it, named or not.
        XCTAssertEqual(Inspect.pick(named + [["waterway": "ditch"]])["waterway"], "ditch")
    }

    func testANamedRecordWinsOverAnUnnamedOneOfTheSameKind() {
        let found: [[String: String]] = [
            ["waterway": "canal"],
            ["waterway": "canal", "name": "Franklin Canal"],
        ]
        XCTAssertEqual(Inspect.pick(found)["name"], "Franklin Canal")
    }

    func testACaveOrPeakUnderTheThumbBeatsTheStreetBesideIt() {
        // A surveyed hole is the question. The road next to it already has
        // its name on the canvas.
        XCTAssertEqual(
            Inspect.pick([
                ["highway": "residential", "name": "Alameda Ave"],
                ["natural": "sinkhole"],
            ])["natural"],
            "sinkhole"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["highway": "track", "name": "North Franklin Trail"],
                ["natural": "peak", "name": "North Franklin"],
            ])["natural"],
            "peak"
        )
        // Water still outranks a cave. Finding water is what holding is for.
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "sinkhole"],
                ["natural": "spring"],
            ])["natural"],
            "spring"
        )
    }

    func testTheHoldNamesThePointClassesTheTilerEmits() {
        XCTAssertEqual(Inspect.packSourceID, "osm")
        XCTAssertEqual(Inspect.packPointSourceLayers, ["water", "place"])
        XCTAssertEqual(
            Inspect.packPointClasses,
            ["spring", "well", "tank", "tank_other", "tap"]
        )
        XCTAssertEqual(
            Inspect.packGroundPointNaturals,
            ["peak", "sinkhole", "cave", "cave_entrance", "tree"]
        )
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
        XCTAssertTrue(Inspect.overlayLayerIDs.contains(PartyPips.haloLayerID))
        XCTAssertTrue(Inspect.overlayLayerIDs.contains(PartyPips.coreLayerID))
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
        ["natural": "cave", "name": "Hueco Tanks Cave"],
        ["natural": "cave_entrance"],
        ["natural": "sinkhole"],
        ["natural": "tree", "name": "El Paso Cottonwood"],
        ["natural": "wood"],
        ["natural": "scrub"],
        ["natural": "heath"],
        ["natural": "sand"],
        ["natural": "dune"],
        ["natural": "wetland"],
        ["natural": "bare_rock"],
        ["natural": "scree"],
        ["natural": "cliff"],
        ["natural": "grassland"],
        ["boundary": "protected_area"],
        ["boundary": "national_park"],
        ["leisure": "nature_reserve"],
        ["leisure": "park"],
        ["landuse": "forest"],
        ["landuse": "farmland"],
        ["landuse": "orchard"],
        ["landuse": "meadow"],
        ["landuse": "vineyard"],
        ["landuse": "basin"],
        ["landuse": "salt_pond"],
        ["landuse": "residential"],
        ["place": "city", "name": "El Paso"],
        ["place": "hamlet"],
        ["highway": "residential", "name": "Alameda Ave"],
        ["highway": "track"],
        ["highway": "path"],
        ["highway": "service"],
    ]
}
