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
            [
                Inspect.iceRockCard, Inspect.mammalNMCard, Inspect.mammalTXCard,
                Inspect.biteCard, Inspect.coldCard,
            ]
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
        // The trees this cover is, then don't chew. Oleander is not a
        // woodland. Unknown last so FIELD still lands with only the core book.
        let wood = Inspect.read(tags: ["natural": "wood"])
        XCTAssertEqual(wood.klass, "Woodland")
        XCTAssertEqual(
            Array(wood.fieldRoute.prefix(2)),
            [Inspect.treeUseTXCard, Inspect.treeUseNMCard]
        )
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.plantTXCard))
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.plantUseCard))
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.shelterCard))
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.biteCard))
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertFalse(wood.fieldRoute.contains(Inspect.cactusTXCard), "picnic woodland is not a cactus garden")
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.gameTXCard))
        XCTAssertTrue(wood.fieldRoute.contains(Inspect.mammalTXCard))
        XCTAssertFalse(wood.fieldRoute.contains(Inspect.snakeTXCard))
        XCTAssertEqual(wood.fieldRoute.last, Inspect.plantCard)
        XCTAssertEqual(InspectField.label(for: wood.fieldRoute[0]), "FIELD · PLANT")
        XCTAssertFalse(wood.doLine.lowercased().contains("edible"), wood.doLine)
        XCTAssertTrue(wood.doLine.lowercased().contains("bite card"), wood.doLine)
        XCTAssertTrue(wood.doLine.lowercased().contains("south-side"), wood.doLine)
        XCTAssertTrue(wood.doLine.lowercased().contains("wind break"), wood.doLine)
        XCTAssertTrue(wood.doLine.lowercased().contains("give it the road"), wood.doLine)
        XCTAssertFalse(wood.doLine.lowercased().contains("food card"), wood.doLine)
        XCTAssertFalse(wood.doLine.lowercased().contains("no ice"), wood.doLine)

        let westWet = Inspect.read(tags: ["natural": "wetland"], pack: "tx-west")
        XCTAssertEqual(westWet.klass, "Bosque or wetland")
        XCTAssertTrue(westWet.doLine.lowercased().contains("javelina"), westWet.doLine)
        XCTAssertTrue(westWet.doLine.lowercased().contains("deer"), westWet.doLine)
        XCTAssertTrue(westWet.doLine.lowercased().contains("bite card"), westWet.doLine)
        XCTAssertTrue(westWet.doLine.lowercased().contains("south-side"), westWet.doLine)
        XCTAssertTrue(westWet.doLine.lowercased().contains("give it the road"), westWet.doLine)
        XCTAssertFalse(westWet.doLine.lowercased().contains("food card"), westWet.doLine)
        XCTAssertFalse(westWet.doLine.lowercased().contains("no ice"), westWet.doLine)
        XCTAssertEqual(westWet.fieldRoute.first, Inspect.treeUseTXCard)
        XCTAssertFalse(westWet.fieldRoute.contains(Inspect.snakeTXCard))
        XCTAssertFalse(westWet.fieldRoute.contains(Inspect.snakeEastCard))

        let nmWet = Inspect.read(tags: ["natural": "wetland"], pack: "nm")
        XCTAssertEqual(nmWet.klass, "Bosque or wetland")
        XCTAssertEqual(nmWet.fieldRoute.first, Inspect.treeUseTXCard)
        XCTAssertFalse(nmWet.fieldRoute.contains(Inspect.snakeNMCard))
        XCTAssertFalse(nmWet.doLine.lowercased().contains("cottonmouth"), nmWet.doLine)
        XCTAssertTrue(nmWet.doLine.lowercased().contains("mule deer"), nmWet.doLine)
        XCTAssertTrue(nmWet.doLine.lowercased().contains("bear"), nmWet.doLine)
        XCTAssertTrue(nmWet.doLine.lowercased().contains("bite card"), nmWet.doLine)
        XCTAssertTrue(nmWet.doLine.lowercased().contains("south-side"), nmWet.doLine)
        XCTAssertTrue(nmWet.doLine.lowercased().contains("give it the road"), nmWet.doLine)
        XCTAssertFalse(nmWet.doLine.lowercased().contains("food card"), nmWet.doLine)
        XCTAssertFalse(nmWet.doLine.lowercased().contains("no ice"), nmWet.doLine)
        XCTAssertFalse(nmWet.doLine.lowercased().contains("elk"), nmWet.doLine)

        let rioBosqueForest = Inspect.read(
            tags: ["landuse": "forest", "name": "Rio Grande Bosque"],
            pack: "nm"
        )
        XCTAssertEqual(
            rioBosqueForest.klass,
            "Bosque or wetland",
            "named bosque tagged forest is cottonwoods, not picnic timber"
        )
        XCTAssertNotEqual(rioBosqueForest.klass, "Woodland")
        XCTAssertTrue(rioBosqueForest.doLine.lowercased().contains("cottonwood"), rioBosqueForest.doLine)
        XCTAssertTrue(rioBosqueForest.doLine.lowercased().contains("mule deer"), rioBosqueForest.doLine)
        XCTAssertTrue(rioBosqueForest.doLine.lowercased().contains("bear"), rioBosqueForest.doLine)
        XCTAssertFalse(rioBosqueForest.doLine.lowercased().contains("elk"), rioBosqueForest.doLine)
        XCTAssertFalse(rioBosqueForest.doLine.lowercased().contains("edible"), rioBosqueForest.doLine)
        XCTAssertEqual(rioBosqueForest.fieldRoute.first, Inspect.treeUseTXCard)
        XCTAssertFalse(rioBosqueForest.fieldRoute.contains(Inspect.snakeNMCard))

        let corrales = Inspect.read(
            tags: ["natural": "wood", "name": "Corrales Bosque"],
            pack: "nm"
        )
        XCTAssertEqual(corrales.klass, "Bosque or wetland")
        XCTAssertFalse(corrales.doLine.lowercased().contains("elk"), corrales.doLine)
        XCTAssertTrue(corrales.doLine.lowercased().contains("cottonwood"), corrales.doLine)

        let isletaForest = Inspect.read(
            tags: ["landuse": "forest", "name": "Isleta Rectangle"],
            pack: "nm"
        )
        XCTAssertEqual(isletaForest.klass, "Woodland")
        XCTAssertTrue(isletaForest.doLine.lowercased().contains("elk is high country"), isletaForest.doLine)

        let unnamedWood = Inspect.read(tags: ["natural": "wood"], pack: "nm")
        XCTAssertEqual(unnamedWood.klass, "Woodland")

        let farm = Inspect.read(tags: ["landuse": "farmland"])
        XCTAssertEqual(farm.klass, "Irrigated ground")
        XCTAssertEqual(farm.fieldRoute.first, Inspect.treeUseTXCard)
        XCTAssertTrue(farm.fieldRoute.contains(Inspect.plantTXCard))
        XCTAssertTrue(farm.fieldRoute.contains(Inspect.plantUseCard))
        XCTAssertFalse(farm.fieldRoute.contains(Inspect.mammalTXCard), "a field is not javelina country")
        XCTAssertFalse(farm.fieldRoute.contains(Inspect.gameTXCard))
        XCTAssertFalse(farm.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertFalse(farm.doLine.lowercased().contains("javelina"), farm.doLine)
        XCTAssertFalse(farm.doLine.lowercased().contains("edible"), farm.doLine)
        XCTAssertFalse(farm.doLine.lowercased().contains("bite card"), farm.doLine)
        XCTAssertTrue(farm.doLine.lowercased().contains("deadfall"), farm.doLine)
        XCTAssertEqual(InspectField.label(for: farm.fieldRoute[0]), "FIELD · PLANT")

        let eastFarm = Inspect.read(tags: ["landuse": "orchard"], pack: "tx-east")
        XCTAssertEqual(eastFarm.klass, "Irrigated ground")
        XCTAssertEqual(eastFarm.fieldRoute.first, Inspect.treeUseEastCard)
        XCTAssertFalse(eastFarm.fieldRoute.contains(Inspect.mammalEastCard), "an orchard is not hog country")
        XCTAssertFalse(eastFarm.fieldRoute.contains(Inspect.treeUseTXCard))
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
        XCTAssertEqual(cave.fieldRoute, [Inspect.caveCard, Inspect.coldCard])
        XCTAssertEqual(InspectField.label(for: cave.fieldRoute[0]), "FIELD · CAVE")
        XCTAssertEqual(InspectField.bookLine(for: cave.fieldRoute), "CAVE · COLD")

        let hole = Inspect.read(tags: ["natural": "sinkhole"])
        XCTAssertEqual(hole.klass, "Cave or hole")
        XCTAssertEqual(hole.fieldRoute.first, Inspect.caveCard)
        XCTAssertEqual(hole.fieldRoute.last, Inspect.coldCard)

        let peak = Inspect.read(tags: ["natural": "peak", "name": "North Franklin"])
        XCTAssertEqual(peak.klass, "Peak")
        XCTAssertEqual(peak.fieldRoute, [
            Inspect.iceRockCard, Inspect.mammalNMCard, Inspect.mammalTXCard,
            Inspect.biteCard, Inspect.coldCard,
        ])
        XCTAssertTrue(peak.fieldRoute.contains(Inspect.biteCard), "a peak walk includes bite treatment")
        XCTAssertEqual(InspectField.label(for: peak.fieldRoute[0]), "FIELD · COLD")
    }

    func testACavePreserveIsAHoleAndBeeCaveIsAPark() {
        let preserve = Inspect.read(
            tags: ["leisure": "park", "name": "Discovery Well Cave Preserve"],
            pack: "tx-east"
        )
        XCTAssertEqual(preserve.klass, "Cave or hole")
        XCTAssertEqual(preserve.fieldRoute, [Inspect.caveCard, Inspect.coldCard])
        XCTAssertEqual(InspectField.label(for: preserve.fieldRoute[0]), "FIELD · CAVE")
        XCTAssertTrue(preserve.why.contains("cave preserve"), preserve.why)
        XCTAssertFalse(preserve.why.lowercased().contains("edible"), preserve.why)
        XCTAssertFalse(preserve.doLine.lowercased().contains("edible"), preserve.doLine)
        XCTAssertTrue(preserve.doLine.lowercased().contains("do not go in alone"), preserve.doLine)
        XCTAssertTrue(preserve.doLine.lowercased().contains("stay in daylight"), preserve.doLine)
        XCTAssertTrue(preserve.doLine.lowercased().contains("dark"), preserve.doLine)

        let buttercup = Inspect.read(
            tags: ["leisure": "park", "name": "Buttercup Creek Cave Preserve"],
            pack: "tx-east"
        )
        XCTAssertEqual(buttercup.klass, "Cave or hole")
        XCTAssertEqual(buttercup.fieldRoute, [Inspect.caveCard, Inspect.coldCard])
        XCTAssertEqual(InspectField.label(for: buttercup.fieldRoute[0]), "FIELD · CAVE")
        XCTAssertTrue(buttercup.doLine.lowercased().contains("stay in daylight"), buttercup.doLine)
        XCTAssertFalse(buttercup.doLine.lowercased().contains("edible"), buttercup.doLine)

        let stoneWell = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Stone Well #1"],
            pack: "tx-east"
        )
        XCTAssertEqual(stoneWell.klass, "Cave or hole")
        XCTAssertEqual(stoneWell.fieldRoute.first, Inspect.caveCard)
        let buttercupSheet: [String: String] = [
            "leisure": "park",
            "name": "Buttercup Creek Cave Preserve",
        ]
        let stoneWellPoint: [String: String] = [
            "natural": "cave_entrance",
            "name": "Stone Well #1",
        ]
        XCTAssertEqual(Inspect.pick([buttercupSheet, stoneWellPoint])["natural"], "cave_entrance")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([buttercupSheet, stoneWellPoint]), pack: "tx-east").klass,
            "Cave or hole"
        )

        let pronoun = Inspect.read(
            tags: [
                "boundary": "protected_area",
                "leisure": "nature_reserve",
                "name": "Pronoun Cave Area of Critical Environmental Concern",
            ],
            pack: "nm"
        )
        XCTAssertEqual(pronoun.klass, "Cave or hole")
        XCTAssertEqual(pronoun.fieldRoute.first, Inspect.caveCard)

        let bee = Inspect.read(
            tags: ["leisure": "park", "name": "Bee Cave Central Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(bee.klass, "Park")
        XCTAssertEqual(bee.fieldRoute.first, Inspect.treeUseEastCard)
        XCTAssertFalse(bee.fieldRoute.contains(Inspect.caveCard))

        let coyote = Inspect.read(tags: ["leisure": "park", "name": "Coyote Cave Park"])
        XCTAssertEqual(coyote.klass, "Park")

        let bat = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Bat Cave"],
            pack: "tx-west"
        )
        XCTAssertEqual(bat.klass, "Cave or hole")
        XCTAssertNotEqual(bat.klass, "Park")
        XCTAssertEqual(bat.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(bat.doLine.lowercased().contains("edible"), bat.doLine)
        XCTAssertFalse(coyote.fieldRoute.contains(Inspect.caveCard))

        let manilla = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Manilla Thrilla Cave"],
            pack: "tx-west"
        )
        XCTAssertEqual(manilla.klass, "Cave or hole")
        XCTAssertNotEqual(manilla.klass, "Park")
        XCTAssertEqual(manilla.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(manilla.doLine.lowercased().contains("edible"), manilla.doLine)

        let apache = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Cueva del Apache"],
            pack: "tx-west"
        )
        XCTAssertEqual(apache.klass, "Cave or hole")
        XCTAssertEqual(apache.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(apache.doLine.lowercased().contains("edible"), apache.doLine)

        let apachePath = Inspect.read(
            tags: ["highway": "path", "name": "Cueva del Apache - La Ventana"],
            pack: "tx-west"
        )
        XCTAssertEqual(apachePath.klass, "Trail")
        XCTAssertFalse(apachePath.fieldRoute.contains(Inspect.caveCard))

        let indio = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Cueva del Indio"],
            pack: "tx-west"
        )
        XCTAssertEqual(indio.klass, "Cave or hole")
        XCTAssertNotEqual(indio.klass, "Park")
        XCTAssertEqual(indio.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(indio.doLine.lowercased().contains("edible"), indio.doLine)

        let aztec = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Aztec Cave"],
            pack: "tx-west"
        )
        XCTAssertEqual(aztec.klass, "Cave or hole")
        XCTAssertNotEqual(aztec.klass, "Open reserve")
        XCTAssertEqual(aztec.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(aztec.doLine.lowercased().contains("edible"), aztec.doLine)

        let aztecTrail = Inspect.read(
            tags: ["highway": "path", "name": "Aztec Caves Trail"],
            pack: "tx-west"
        )
        XCTAssertEqual(aztecTrail.klass, "Trail")
        XCTAssertFalse(aztecTrail.fieldRoute.contains(Inspect.caveCard))

        let embudo = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Embudo Cave"],
            pack: "nm"
        )
        XCTAssertEqual(embudo.klass, "Cave or hole")
        XCTAssertEqual(embudo.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(embudo.doLine.lowercased().contains("edible"), embudo.doLine)

        let bearCave = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Bear Cave"],
            pack: "nm"
        )
        XCTAssertEqual(bearCave.klass, "Cave or hole")
        XCTAssertEqual(bearCave.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(bearCave.doLine.lowercased().contains("edible"), bearCave.doLine)

        let winds = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Cave of the Winds"],
            pack: "nm"
        )
        XCTAssertEqual(winds.klass, "Cave or hole")
        XCTAssertEqual(winds.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(winds.doLine.lowercased().contains("edible"), winds.doLine)

        let windsTrail = Inspect.read(
            tags: ["highway": "path", "name": "Cave of the Winds Trail"],
            pack: "nm"
        )
        XCTAssertEqual(windsTrail.klass, "Trail")
        XCTAssertFalse(windsTrail.fieldRoute.contains(Inspect.caveCard))

        let ventana = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Cueva la Ventana"],
            pack: "tx-west"
        )
        XCTAssertEqual(ventana.klass, "Cave or hole")
        XCTAssertEqual(ventana.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(ventana.doLine.lowercased().contains("edible"), ventana.doLine)

        let pepperRock = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Pepper Rock Cave"],
            pack: "tx-east"
        )
        XCTAssertEqual(pepperRock.klass, "Cave or hole")
        XCTAssertNotEqual(pepperRock.klass, "Park")
        XCTAssertEqual(pepperRock.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(pepperRock.doLine.lowercased().contains("edible"), pepperRock.doLine)

        let pepperPark = Inspect.read(
            tags: ["leisure": "park", "name": "Pepper Rock Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(pepperPark.klass, "Park")
        XCTAssertFalse(pepperPark.fieldRoute.contains(Inspect.caveCard))

        let chathamWood = Inspect.read(
            tags: ["highway": "residential", "name": "Chatham Wood Drive"],
            pack: "tx-east"
        )
        XCTAssertEqual(chathamWood.klass, "Road")
        XCTAssertFalse(chathamWood.fieldRoute.contains(Inspect.caveCard))

        let airmen = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Airmen's Cave"],
            pack: "tx-east"
        )
        XCTAssertEqual(airmen.klass, "Cave or hole")
        XCTAssertEqual(airmen.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(airmen.doLine.lowercased().contains("edible"), airmen.doLine)

        let painted = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Painted Cave"],
            pack: "nm"
        )
        XCTAssertEqual(painted.klass, "Cave or hole")
        XCTAssertNotEqual(painted.klass, "Open reserve")
        XCTAssertEqual(painted.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(painted.doLine.lowercased().contains("edible"), painted.doLine)

        let paintedTrail = Inspect.read(
            tags: ["highway": "footway", "name": "Lower Capulin Trail"],
            pack: "nm"
        )
        XCTAssertEqual(paintedTrail.klass, "Trail")
        XCTAssertFalse(paintedTrail.fieldRoute.contains(Inspect.caveCard))

        let geronimo = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Geronimo"],
            pack: "tx-west"
        )
        XCTAssertEqual(geronimo.klass, "Cave or hole")
        XCTAssertNotEqual(geronimo.klass, "Open reserve")
        XCTAssertEqual(geronimo.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(geronimo.doLine.lowercased().contains("edible"), geronimo.doLine)

        let organMonument = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Organ Mountains-Desert Peaks National Monument",
            ],
            pack: "tx-west"
        )
        XCTAssertEqual(organMonument.klass, "Open reserve")
        XCTAssertFalse(organMonument.fieldRoute.contains(Inspect.caveCard))

        let treeHouse = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Tree House Cave"],
            pack: "tx-east"
        )
        XCTAssertEqual(treeHouse.klass, "Cave or hole")
        XCTAssertEqual(treeHouse.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(treeHouse.doLine.lowercased().contains("edible"), treeHouse.doLine)

        let andrewCove = Inspect.read(
            tags: ["highway": "residential", "name": "Andrew Cove"],
            pack: "tx-east"
        )
        XCTAssertEqual(andrewCove.klass, "Road")
        XCTAssertFalse(andrewCove.fieldRoute.contains(Inspect.caveCard))

        let hideaway = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Hideaway"],
            pack: "tx-east"
        )
        XCTAssertEqual(hideaway.klass, "Cave or hole")
        XCTAssertNotEqual(hideaway.klass, "Open reserve")
        XCTAssertEqual(hideaway.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(hideaway.doLine.lowercased().contains("edible"), hideaway.doLine)

        let westsidePreserve = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Westside Preserve"],
            pack: "tx-east"
        )
        XCTAssertEqual(westsidePreserve.klass, "Open reserve")
        XCTAssertFalse(westsidePreserve.fieldRoute.contains(Inspect.caveCard))

        let nelsonLoop = Inspect.read(
            tags: ["highway": "residential", "name": "Nelson Ranch Loop"],
            pack: "tx-east"
        )
        XCTAssertEqual(nelsonLoop.klass, "Road")
        XCTAssertFalse(nelsonLoop.fieldRoute.contains(Inspect.caveCard))

        let buttercupWind = Inspect.read(
            tags: ["natural": "cave_entrance", "name": "Buttercup Wind"],
            pack: "tx-east"
        )
        XCTAssertEqual(buttercupWind.klass, "Cave or hole")
        XCTAssertEqual(buttercupWind.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(buttercupWind.doLine.lowercased().contains("edible"), buttercupWind.doLine)

        let sheaDrive = Inspect.read(
            tags: ["highway": "residential", "name": "Shea Drive"],
            pack: "tx-east"
        )
        XCTAssertEqual(sheaDrive.klass, "Road")
        XCTAssertFalse(sheaDrive.fieldRoute.contains(Inspect.caveCard))

        let laurenTrail = Inspect.read(
            tags: ["highway": "residential", "name": "Lauren Trail"],
            pack: "tx-east"
        )
        XCTAssertEqual(laurenTrail.klass, "Road")
        XCTAssertNotEqual(laurenTrail.klass, "Trail")
        XCTAssertFalse(laurenTrail.fieldRoute.contains(Inspect.caveCard))

        let daffan = Inspect.read(
            tags: ["highway": "tertiary", "name": "Daffan Lane"],
            pack: "tx-east"
        )
        XCTAssertEqual(daffan.klass, "Road")
        XCTAssertNotEqual(daffan.klass, "Glasshouse")

        let embudoPark = Inspect.read(
            tags: ["leisure": "park", "name": "Embudo Hills Park"],
            pack: "nm"
        )
        XCTAssertEqual(embudoPark.klass, "Park")
        XCTAssertFalse(embudoPark.fieldRoute.contains(Inspect.caveCard))

        let blowing = Inspect.read(
            tags: ["natural": "wetland", "name": "Blowing Sink"],
            pack: "tx-east"
        )
        XCTAssertEqual(blowing.klass, "Cave or hole")
        XCTAssertEqual(blowing.fieldRoute, [Inspect.caveCard, Inspect.coldCard])
        XCTAssertEqual(InspectField.label(for: blowing.fieldRoute[0]), "FIELD · CAVE")
        XCTAssertTrue(blowing.why.contains("named sink"), blowing.why)
        XCTAssertFalse(blowing.doLine.lowercased().contains("cottonmouth"), blowing.doLine)
        XCTAssertFalse(blowing.doLine.lowercased().contains("edible"), blowing.doLine)

        let reservoir = Inspect.read(
            tags: ["natural": "wetland", "name": "Great Northern Reservoir"],
            pack: "tx-east"
        )
        XCTAssertEqual(reservoir.klass, "Bosque or wetland")
        XCTAssertFalse(reservoir.fieldRoute.contains(Inspect.caveCard))

        let sinkRoad = Inspect.read(
            tags: ["highway": "residential", "name": "Blowing Sink Road"],
            pack: "tx-east"
        )
        XCTAssertEqual(sinkRoad.klass, "Road")
        XCTAssertFalse(sinkRoad.fieldRoute.contains(Inspect.caveCard))

        let whirlpool = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Whirlpool Cave"],
            pack: "tx-east"
        )
        XCTAssertEqual(whirlpool.klass, "Cave or hole")
        XCTAssertEqual(whirlpool.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(whirlpool.doLine.lowercased().contains("edible"), whirlpool.doLine)

        let goat = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Goat Cave Karst Nature Preserve"],
            pack: "tx-east"
        )
        XCTAssertEqual(goat.klass, "Cave or hole")
        XCTAssertNotEqual(goat.klass, "Wildlife range")
        XCTAssertEqual(goat.fieldRoute.first, Inspect.caveCard)

        let russell = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "William H. Russell Karst Preserve"],
            pack: "tx-east"
        )
        XCTAssertEqual(russell.klass, "Cave or hole")
        XCTAssertNotEqual(russell.klass, "Wildlife range")
        XCTAssertEqual(russell.fieldRoute.first, Inspect.caveCard)
        XCTAssertFalse(russell.doLine.lowercased().contains("edible"), russell.doLine)

        let karstLane = Inspect.read(
            tags: ["highway": "residential", "name": "Karst Lane"],
            pack: "tx-east"
        )
        XCTAssertEqual(karstLane.klass, "Road")
        XCTAssertFalse(karstLane.fieldRoute.contains(Inspect.caveCard))

        let karst = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Village of Western Oaks Karst Preserve and Watershed Management Area",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(karst.klass, "Cave or hole")
        XCTAssertEqual(karst.fieldRoute.first, Inspect.caveCard)
    }

    func testAWildlifeManagementAreaIsRangeNotAPin() {
        let marquez = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Marquez Wildlife Management Area",
            ],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(marquez.klass, "Wildlife range")
        XCTAssertEqual(marquez.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(marquez.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertEqual(InspectField.label(for: Inspect.mammalNMCard), "FIELD · ANIMAL")
        let nmBook: Set<String> = [
            Inspect.mammalNMCard, Inspect.snakeNMCard, Inspect.gameNMCard,
            Inspect.treeUseNMCard, Inspect.plantNMCard, Inspect.biteCard,
            Inspect.plantUseCard, Inspect.gameCard, Inspect.plantCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(marquez.fieldRoute, in: nmBook).first,
            Inspect.mammalNMCard
        )
        XCTAssertEqual(
            InspectField.label(for: InspectField.presentRoute(marquez.fieldRoute, in: nmBook)[0]),
            "FIELD · ANIMAL"
        )
        XCTAssertEqual(
            InspectField.bookLine(for: InspectField.presentRoute(marquez.fieldRoute, in: nmBook)),
            "ANIMAL · BITE · FOOD · PLANT"
        )
        let doLine = marquez.doLine.lowercased()
        XCTAssertTrue(doLine.contains("bear") || doLine.contains("elk"), marquez.doLine)
        XCTAssertTrue(doLine.contains("diamondback") || doLine.contains("rattler"), marquez.doLine)
        XCTAssertTrue(doLine.contains("bite card"), marquez.doLine)
        XCTAssertTrue(doLine.contains("food card"), marquez.doLine)
        XCTAssertTrue(doLine.contains("give it the road"), marquez.doLine)
        XCTAssertTrue(doLine.contains("cook through"), marquez.doLine)
        XCTAssertTrue(doLine.contains("no ice"), marquez.doLine)
        XCTAssertTrue(doLine.contains("range") || doLine.contains("not a pin"), marquez.doLine)
        XCTAssertFalse(doLine.contains("cottonwood"), marquez.doLine)
        XCTAssertFalse(doLine.contains("lives here"), marquez.doLine)
        XCTAssertFalse(doLine.contains("edible"), marquez.doLine)
        XCTAssertFalse(marquez.why.lowercased().contains("edible"), marquez.why)

        let refuge = Inspect.read(
            tags: [
                "boundary": "protected_area",
                "name": "Balcones Canyonlands National Wildlife Refuge",
            ],
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(refuge.klass, "Wildlife range")
        XCTAssertEqual(refuge.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(refuge.fieldRoute.contains(Inspect.mammalTXCard))
        XCTAssertEqual(InspectField.label(for: refuge.fieldRoute[0]), "FIELD · ANIMAL")
        XCTAssertTrue(refuge.doLine.lowercased().contains("hog"), refuge.doLine)
        XCTAssertTrue(refuge.doLine.lowercased().contains("cottonmouth"), refuge.doLine)
        XCTAssertTrue(refuge.doLine.lowercased().contains("bite card"), refuge.doLine)
        XCTAssertTrue(refuge.doLine.lowercased().contains("food card"), refuge.doLine)
        XCTAssertTrue(refuge.doLine.lowercased().contains("give it the road"), refuge.doLine)
        XCTAssertTrue(refuge.doLine.lowercased().contains("cook through"), refuge.doLine)
        XCTAssertTrue(refuge.doLine.lowercased().contains("no ice"), refuge.doLine)
        XCTAssertFalse(refuge.doLine.lowercased().contains("javelina"), refuge.doLine)
        XCTAssertFalse(refuge.doLine.lowercased().contains("cottonwood"), refuge.doLine)
        XCTAssertFalse(refuge.doLine.lowercased().contains("lives here"), refuge.doLine)

        let westRange = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Franklin Mountains Wildlife Management Area",
            ],
            state: "TX",
            pack: "tx-west"
        )
        XCTAssertEqual(westRange.klass, "Wildlife range")
        XCTAssertEqual(westRange.fieldRoute.first, Inspect.mammalTXCard)
        let westDo = westRange.doLine.lowercased()
        XCTAssertTrue(westDo.contains("javelina"), westRange.doLine)
        XCTAssertTrue(westDo.contains("deer"), westRange.doLine)
        XCTAssertTrue(westDo.contains("diamondback"), westRange.doLine)
        XCTAssertTrue(westDo.contains("bite card"), westRange.doLine)
        XCTAssertTrue(westDo.contains("food card"), westRange.doLine)
        XCTAssertTrue(westDo.contains("give it the road"), westRange.doLine)
        XCTAssertTrue(westDo.contains("cook through"), westRange.doLine)
        XCTAssertTrue(westDo.contains("no ice"), westRange.doLine)
        XCTAssertFalse(westDo.contains("hog"), westRange.doLine)
        XCTAssertFalse(westDo.contains("cottonmouth"), westRange.doLine)
        XCTAssertFalse(westDo.contains("cottonwood"), westRange.doLine)
        XCTAssertFalse(westDo.contains("mesquite"), westRange.doLine)
        XCTAssertFalse(westDo.contains("lives here"), westRange.doLine)
        XCTAssertFalse(westDo.contains("edible"), westRange.doLine)

        let sanctuary = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "natural": "wood",
                "name": "Colorado River Park Wildlife Sanctuary",
            ],
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(sanctuary.klass, "Wildlife range")
        XCTAssertEqual(sanctuary.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertNotEqual(sanctuary.klass, "Woodland")
        XCTAssertEqual(InspectField.label(for: sanctuary.fieldRoute[0]), "FIELD · ANIMAL")
        XCTAssertTrue(sanctuary.doLine.lowercased().contains("hog"), sanctuary.doLine)
        XCTAssertTrue(sanctuary.doLine.lowercased().contains("cottonmouth"), sanctuary.doLine)
        XCTAssertFalse(sanctuary.doLine.lowercased().contains("javelina"), sanctuary.doLine)
        XCTAssertFalse(sanctuary.doLine.lowercased().contains("diamondback"), sanctuary.doLine)
        XCTAssertFalse(sanctuary.doLine.lowercased().contains("lives here"), sanctuary.doLine)

        let grass = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "natural": "scrub",
                "name": "Indiangrass Wildlife Sanctuary",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(grass.klass, "Wildlife range")
        XCTAssertEqual(grass.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertTrue(grass.doLine.lowercased().contains("hog"), grass.doLine)
        XCTAssertTrue(grass.doLine.lowercased().contains("cook through"), grass.doLine)
        XCTAssertTrue(grass.doLine.lowercased().contains("no ice"), grass.doLine)
        XCTAssertFalse(grass.doLine.lowercased().contains("cottonwood"), grass.doLine)

        let whitfield = Inspect.read(
            tags: [
                "boundary": "protected_area",
                "natural": "wetland",
                "name": "Whitfield Wildlife Conservation Area",
            ],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(whitfield.klass, "Wildlife range")
        XCTAssertNotEqual(whitfield.klass, "Bosque or wetland")
        XCTAssertTrue(whitfield.fieldRoute.contains(Inspect.mammalNMCard))

        let commission = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "State Game Commission Land",
            ],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(commission.klass, "Wildlife range")
        XCTAssertEqual(commission.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(commission.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertEqual(
            InspectField.presentRoute(commission.fieldRoute, in: nmBook).first,
            Inspect.mammalNMCard
        )
        XCTAssertEqual(
            InspectField.label(for: InspectField.presentRoute(commission.fieldRoute, in: nmBook)[0]),
            "FIELD · ANIMAL"
        )
        XCTAssertTrue(commission.doLine.lowercased().contains("bear") || commission.doLine.lowercased().contains("elk"), commission.doLine)
        XCTAssertFalse(commission.doLine.lowercased().contains("lives here"), commission.doLine)
        XCTAssertFalse(commission.doLine.lowercased().contains("edible"), commission.doLine)

        let office = Inspect.read(
            tags: ["leisure": "park", "name": "New Mexico Department of Game & Fish"],
            pack: "nm"
        )
        XCTAssertEqual(office.klass, "Park")
        XCTAssertEqual(office.fieldRoute.first, Inspect.treeUseTXCard)
        XCTAssertFalse(office.doLine.lowercased().contains("not a pin"), office.doLine)

        let drive = Inspect.read(
            tags: ["leisure": "park", "name": "Wildlife Drive Park"],
            pack: "nm"
        )
        XCTAssertEqual(drive.klass, "Park")
        XCTAssertEqual(drive.fieldRoute.first, Inspect.treeUseTXCard)
        XCTAssertFalse(drive.doLine.lowercased().contains("not a pin"), drive.doLine)

        let basin = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Wild Basin Wilderness Preserve",
            ],
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(basin.klass, "Wildlife range")
        XCTAssertEqual(basin.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(basin.fieldRoute.contains(Inspect.cactusTXCard), "Wild Basin is not a cactus garden")
        XCTAssertTrue(basin.doLine.lowercased().contains("hog"), basin.doLine)
        XCTAssertFalse(basin.doLine.lowercased().contains("javelina"), basin.doLine)

        let gate = Inspect.read(
            tags: ["landuse": "residential", "name": "Wilderness Gate"],
            pack: "nm"
        )
        XCTAssertEqual(gate.klass, "Built-up ground")
        XCTAssertNotEqual(gate.klass, "Wildlife range")

        let barrow = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "natural": "wood",
                "name": "Barrow Nature Preserve",
            ],
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(barrow.klass, "Wildlife range")
        XCTAssertNotEqual(barrow.klass, "Woodland")
        XCTAssertEqual(barrow.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(barrow.fieldRoute.contains(Inspect.cactusTXCard), "a nature preserve is not a cactus garden")
        XCTAssertTrue(barrow.doLine.lowercased().contains("hog"), barrow.doLine)
        XCTAssertFalse(barrow.doLine.lowercased().contains("javelina"), barrow.doLine)

        let overlayBarrow = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Barrow Nature Preserve",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(overlayBarrow.klass, "Wildlife range")
        XCTAssertNotEqual(overlayBarrow.klass, "Open reserve")
        XCTAssertEqual(overlayBarrow.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(overlayBarrow.doLine.lowercased().contains("edible"), overlayBarrow.doLine)

        let center = Inspect.read(
            tags: ["leisure": "park", "name": "Rio Grande Nature Center State Park"],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(center.klass, "Wildlife range")
        XCTAssertNotEqual(center.klass, "Park")
        XCTAssertTrue(center.fieldRoute.contains(Inspect.mammalNMCard))
        let nmWildlifeBook: Set<String> = [
            Inspect.mammalNMCard, Inspect.snakeNMCard, Inspect.gameNMCard,
            Inspect.treeUseNMCard, Inspect.plantNMCard, Inspect.biteCard,
            Inspect.plantUseCard, Inspect.gameCard, Inspect.plantCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(center.fieldRoute, in: nmWildlifeBook).first,
            Inspect.mammalNMCard
        )
        XCTAssertEqual(
            InspectField.label(for: InspectField.presentRoute(center.fieldRoute, in: nmWildlifeBook)[0]),
            "FIELD · ANIMAL"
        )
        XCTAssertTrue(center.doLine.lowercased().contains("elk is high country"), center.doLine)

        let leaf = Inspect.read(
            tags: [
                "leisure": "park",
                "natural": "wood",
                "name": "Bright Leaf Natural Area",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(leaf.klass, "Wildlife range")
        XCTAssertNotEqual(leaf.klass, "Open reserve")
        XCTAssertEqual(leaf.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(leaf.doLine.lowercased().contains("edible"), leaf.doLine)

        let godzilla = Inspect.read(
            tags: ["leisure": "park", "name": "Godzilla Preserve"],
            pack: "tx-east"
        )
        XCTAssertEqual(godzilla.klass, "Park")
        XCTAssertEqual(godzilla.fieldRoute.first, Inspect.treeUseEastCard)

        let visitor = Inspect.read(
            tags: ["leisure": "park", "name": "Open Space Visitor Center"],
            pack: "nm"
        )
        XCTAssertEqual(visitor.klass, "Park")
        XCTAssertNotEqual(visitor.klass, "Wildlife range")
        XCTAssertNotEqual(visitor.klass, "Open reserve")
        XCTAssertEqual(visitor.fieldRoute.first, Inspect.treeUseTXCard)

        let overlayCenter = Inspect.read(
            tags: [
                "boundary": "protected_area",
                "landuse": "recreation_ground",
                "name": "Rio Grande Nature Center State Park",
            ],
            pack: "nm"
        )
        XCTAssertEqual(overlayCenter.klass, "Wildlife range")
        XCTAssertNotEqual(overlayCenter.klass, "Irrigated ground")

        let whitestone = Inspect.read(
            tags: ["leisure": "park", "name": "Whitestone Preserve"],
            pack: "tx-east"
        )
        XCTAssertEqual(whitestone.klass, "Park")
        XCTAssertEqual(whitestone.fieldRoute.first, Inspect.treeUseEastCard)

        let nalle = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Nalle Bunny Run Wildlife Preserve"],
            pack: "tx-east"
        )
        XCTAssertEqual(nalle.klass, "Wildlife range")
        XCTAssertEqual(nalle.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(nalle.doLine.lowercased().contains("edible"), nalle.doLine)

        let audubon = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Randall Davey Audubon Center & Sanctuary"],
            pack: "nm"
        )
        XCTAssertEqual(audubon.klass, "Wildlife range")
        XCTAssertNotEqual(audubon.klass, "Open reserve")
        XCTAssertEqual(audubon.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(audubon.doLine.lowercased().contains("elk is high country"), audubon.doLine)

        let natureArea = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Sunset Valley Nature Area"],
            pack: "tx-east"
        )
        XCTAssertEqual(natureArea.klass, "Wildlife range")
        XCTAssertNotEqual(natureArea.klass, "Open reserve")
        XCTAssertEqual(natureArea.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(natureArea.doLine.lowercased().contains("edible"), natureArea.doLine)

        let habitat = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Barton Creek Habitat Preserve"],
            pack: "tx-east"
        )
        XCTAssertEqual(habitat.klass, "Wildlife range")
        XCTAssertNotEqual(habitat.klass, "Open reserve")
        XCTAssertEqual(habitat.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(habitat.doLine.lowercased().contains("edible"), habitat.doLine)

        let flora = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Área de Protección de Flora y Fauna Médanos de Samalayuca",
            ],
            pack: "tx-west"
        )
        XCTAssertEqual(flora.klass, "Wildlife range")
        XCTAssertNotEqual(flora.klass, "Open reserve")
        XCTAssertEqual(flora.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertFalse(flora.doLine.lowercased().contains("edible"), flora.doLine)

        let caldera = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Valles Caldera National Preserve",
            ],
            pack: "nm"
        )
        XCTAssertEqual(caldera.klass, "Wildlife range")
        XCTAssertNotEqual(caldera.klass, "Open reserve")
        XCTAssertEqual(caldera.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(caldera.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertTrue(caldera.doLine.lowercased().contains("elk is high country"), caldera.doLine)
        XCTAssertFalse(caldera.doLine.lowercased().contains("edible"), caldera.doLine)

        let wildernessPark = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Barton Creek Wilderness Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(wildernessPark.klass, "Wildlife range")
        XCTAssertNotEqual(wildernessPark.klass, "Open reserve")
        XCTAssertEqual(wildernessPark.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(wildernessPark.doLine.lowercased().contains("edible"), wildernessPark.doLine)

        let canyonlands = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Balcones Canyonlands Preserve - Grandview Hills",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(canyonlands.klass, "Wildlife range")
        XCTAssertNotEqual(canyonlands.klass, "Open reserve")
        XCTAssertEqual(canyonlands.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertTrue(canyonlands.doLine.lowercased().contains("hog"), canyonlands.doLine)
        XCTAssertFalse(canyonlands.doLine.lowercased().contains("cottonwood"), canyonlands.doLine)
        XCTAssertFalse(canyonlands.doLine.lowercased().contains("edible"), canyonlands.doLine)

        let blackmore = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Balcones Canyonlands Preserve - Blackmore",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(blackmore.klass, "Wildlife range")
        XCTAssertNotEqual(blackmore.klass, "Open reserve")
        XCTAssertEqual(blackmore.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(blackmore.doLine.lowercased().contains("edible"), blackmore.doLine)

        let lakePerspectives = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Balcones Canyonlands Preserve - Lake Perspectives",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(lakePerspectives.klass, "Wildlife range")
        XCTAssertNotEqual(lakePerspectives.klass, "Open reserve")
        XCTAssertEqual(lakePerspectives.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(lakePerspectives.doLine.lowercased().contains("edible"), lakePerspectives.doLine)

        let canyonTrailPark = Inspect.read(
            tags: ["leisure": "park", "natural": "wood", "name": "Canyonlands Trail Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(canyonTrailPark.klass, "Park")
        XCTAssertNotEqual(canyonTrailPark.klass, "Wildlife range")

        let curtin = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "natural": "wetland",
                "name": "Leonora Curtin Wetland Preserve",
            ],
            pack: "nm"
        )
        XCTAssertEqual(curtin.klass, "Wildlife range")
        XCTAssertNotEqual(curtin.klass, "Bosque or wetland")
        XCTAssertNotEqual(curtin.klass, "Open reserve")
        XCTAssertEqual(curtin.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(curtin.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertFalse(curtin.doLine.lowercased().contains("cottonwood"), curtin.doLine)
        XCTAssertFalse(curtin.doLine.lowercased().contains("edible"), curtin.doLine)

        let wetlandsPark = Inspect.read(
            tags: [
                "leisure": "park",
                "natural": "wetland",
                "name": "Rio Bosque Wetlands Park",
            ],
            pack: "tx-west"
        )
        XCTAssertEqual(wetlandsPark.klass, "Bosque or wetland")
        XCTAssertNotEqual(wetlandsPark.klass, "Wildlife range")

        let canyonPreserve = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Santa Fe Canyon Preserve",
            ],
            pack: "nm"
        )
        XCTAssertEqual(canyonPreserve.klass, "Wildlife range")
        XCTAssertNotEqual(canyonPreserve.klass, "Open reserve")
        XCTAssertEqual(canyonPreserve.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(canyonPreserve.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertFalse(canyonPreserve.doLine.lowercased().contains("edible"), canyonPreserve.doLine)

        let canyonLoop = Inspect.read(
            tags: ["highway": "path", "name": "Canyon Preserve Interpretive Loop Trail"],
            pack: "nm"
        )
        XCTAssertNotEqual(canyonLoop.klass, "Wildlife range")

        let losLunas = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "El Cerro de Los Lunas Preserve"],
            pack: "nm"
        )
        XCTAssertEqual(losLunas.klass, "Open reserve")
        XCTAssertNotEqual(losLunas.klass, "Wildlife range")

        let galisteo = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Galisteo Basin Preserve"],
            pack: "nm"
        )
        XCTAssertEqual(galisteo.klass, "Open reserve")
        XCTAssertNotEqual(galisteo.klass, "Wildlife range")

        let management = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Bear Creek Management Unit",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(management.klass, "Wildlife range")
        XCTAssertNotEqual(management.klass, "Open reserve")
        XCTAssertEqual(management.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertTrue(management.doLine.lowercased().contains("hog"), management.doLine)
        XCTAssertFalse(management.doLine.lowercased().contains("edible"), management.doLine)

        let hornsby = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Hornsby Bend Ecological Research Area",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(hornsby.klass, "Wildlife range")
        XCTAssertNotEqual(hornsby.klass, "Open reserve")
        XCTAssertEqual(hornsby.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(hornsby.doLine.lowercased().contains("edible"), hornsby.doLine)

        let hawk = Inspect.read(
            tags: ["leisure": "park", "name": "Hawk Watch Open Space"],
            pack: "nm"
        )
        XCTAssertEqual(hawk.klass, "Wildlife range")
        XCTAssertNotEqual(hawk.klass, "Open reserve")
        XCTAssertEqual(hawk.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(hawk.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertFalse(hawk.doLine.lowercased().contains("edible"), hawk.doLine)

        let hawkTrail = Inspect.read(
            tags: ["highway": "path", "name": "Hawk Watch Trail"],
            pack: "nm"
        )
        XCTAssertNotEqual(hawkTrail.klass, "Wildlife range")

        let jornada = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Jornada Experimental Range",
            ],
            pack: "tx-west"
        )
        XCTAssertEqual(jornada.klass, "Wildlife range")
        XCTAssertNotEqual(jornada.klass, "Open reserve")
        XCTAssertEqual(jornada.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(jornada.doLine.lowercased().contains("javelina"), jornada.doLine)
        XCTAssertFalse(jornada.doLine.lowercased().contains("edible"), jornada.doLine)

        let charlie = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Charlie Wakeem/Richard Teschner Nature Preserve of Resler Canyon",
            ],
            pack: "tx-west"
        )
        XCTAssertEqual(charlie.klass, "Wildlife range")
        XCTAssertNotEqual(charlie.klass, "Open reserve")
        XCTAssertEqual(charlie.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(charlie.doLine.lowercased().contains("javelina"), charlie.doLine)
        XCTAssertFalse(charlie.doLine.lowercased().contains("edible"), charlie.doLine)

        let cadiz = Inspect.read(
            tags: ["highway": "residential", "name": "Cadiz Street"],
            pack: "tx-west"
        )
        XCTAssertEqual(cadiz.klass, "Road")
        XCTAssertNotEqual(cadiz.klass, "Wildlife range")

        let fiestaDrive = Inspect.read(
            tags: ["highway": "tertiary", "name": "Fiesta Drive"],
            pack: "tx-west"
        )
        XCTAssertEqual(fiestaDrive.klass, "Road")
        XCTAssertNotEqual(fiestaDrive.klass, "Wildlife range")

        let sanAndres = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "San Andres National Wildlife Refuge",
            ],
            pack: "tx-west"
        )
        XCTAssertEqual(sanAndres.klass, "Wildlife range")
        XCTAssertNotEqual(sanAndres.klass, "Open reserve")
        XCTAssertEqual(sanAndres.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertFalse(sanAndres.doLine.lowercased().contains("edible"), sanAndres.doLine)

        let missileRoute = Inspect.read(
            tags: ["highway": "residential", "name": "White Sands Missile Range S Route 287"],
            pack: "tx-west"
        )
        XCTAssertEqual(missileRoute.klass, "Road")
        XCTAssertNotEqual(missileRoute.klass, "Wildlife range")

        let history = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Sandia Mountain Natural History Center",
            ],
            pack: "nm"
        )
        XCTAssertEqual(history.klass, "Wildlife range")
        XCTAssertNotEqual(history.klass, "Open reserve")
        XCTAssertEqual(history.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(history.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertFalse(history.doLine.lowercased().contains("edible"), history.doLine)

        let baker = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Baker Sanctuary"],
            pack: "tx-east"
        )
        XCTAssertEqual(baker.klass, "Wildlife range")
        XCTAssertNotEqual(baker.klass, "Open reserve")
        XCTAssertEqual(baker.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(baker.doLine.lowercased().contains("edible"), baker.doLine)

        let blair = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Blair Woods Sanctuary"],
            pack: "tx-east"
        )
        XCTAssertEqual(blair.klass, "Wildlife range")
        XCTAssertNotEqual(blair.klass, "Open reserve")
        XCTAssertEqual(blair.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(blair.doLine.lowercased().contains("edible"), blair.doLine)

        let beck = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Beck Preserve"],
            pack: "tx-east"
        )
        XCTAssertEqual(beck.klass, "Wildlife range")
        XCTAssertNotEqual(beck.klass, "Open reserve")
        XCTAssertEqual(beck.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(beck.doLine.lowercased().contains("edible"), beck.doLine)

        let brodie = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Brodie Wild"],
            pack: "tx-east"
        )
        XCTAssertEqual(brodie.klass, "Wildlife range")
        XCTAssertNotEqual(brodie.klass, "Open reserve")
        XCTAssertEqual(brodie.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(brodie.doLine.lowercased().contains("edible"), brodie.doLine)

        let brodieLane = Inspect.read(
            tags: ["highway": "secondary", "name": "Brodie Lane"],
            pack: "tx-east"
        )
        XCTAssertEqual(brodieLane.klass, "Road")
        XCTAssertNotEqual(brodieLane.klass, "Wildlife range")

        let dahlstrom = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Gay Ruby Dahlstrom Nature Preserve"],
            pack: "tx-east"
        )
        XCTAssertEqual(dahlstrom.klass, "Wildlife range")
        XCTAssertNotEqual(dahlstrom.klass, "Open reserve")
        XCTAssertEqual(dahlstrom.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(dahlstrom.doLine.lowercased().contains("edible"), dahlstrom.doLine)

        let dahlstromRoad = Inspect.read(
            tags: ["highway": "residential", "name": "Dahlstrom Road"],
            pack: "tx-east"
        )
        XCTAssertEqual(dahlstromRoad.klass, "Road")
        XCTAssertNotEqual(dahlstromRoad.klass, "Wildlife range")

        let dahlstromWay = Inspect.read(
            tags: ["highway": "service", "name": "Dahlstrom"],
            pack: "tx-east"
        )
        XCTAssertEqual(dahlstromWay.klass, "Service road")
        XCTAssertNotEqual(dahlstromWay.klass, "Wildlife range")

        let stephenson = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Stephenson Nature Preserve And Outdoor Education Center",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(stephenson.klass, "Wildlife range")
        XCTAssertNotEqual(stephenson.klass, "Open reserve")
        XCTAssertEqual(stephenson.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(stephenson.doLine.lowercased().contains("edible"), stephenson.doLine)

        let stephensonDrive = Inspect.read(
            tags: ["highway": "residential", "name": "Stephenson Drive"],
            pack: "tx-east"
        )
        XCTAssertEqual(stephensonDrive.klass, "Road")
        XCTAssertNotEqual(stephensonDrive.klass, "Wildlife range")

        let onionSanctuary = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Onion Creek Wildlife Sanctuary",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(onionSanctuary.klass, "Wildlife range")
        XCTAssertNotEqual(onionSanctuary.klass, "Open reserve")
        XCTAssertEqual(onionSanctuary.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(onionSanctuary.doLine.lowercased().contains("edible"), onionSanctuary.doLine)

        let onionDrive = Inspect.read(
            tags: ["highway": "residential", "name": "Onion Creek Drive"],
            pack: "tx-east"
        )
        XCTAssertEqual(onionDrive.klass, "Road")
        XCTAssertNotEqual(onionDrive.klass, "Wildlife range")

        let onionUnit = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Onion Creek Management Unit",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(onionUnit.klass, "Wildlife range")
        XCTAssertNotEqual(onionUnit.klass, "Open reserve")
        XCTAssertEqual(onionUnit.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(onionUnit.doLine.lowercased().contains("edible"), onionUnit.doLine)

        let maryGay = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Mary Gay Maxwell Management Unit",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(maryGay.klass, "Wildlife range")
        XCTAssertNotEqual(maryGay.klass, "Open reserve")
        XCTAssertEqual(maryGay.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(maryGay.doLine.lowercased().contains("edible"), maryGay.doLine)

        let bullCreek = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Bull Creek Management Unit",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(bullCreek.klass, "Wildlife range")
        XCTAssertNotEqual(bullCreek.klass, "Open reserve")
        XCTAssertEqual(bullCreek.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(bullCreek.doLine.lowercased().contains("edible"), bullCreek.doLine)

        let bullLoop = Inspect.read(
            tags: ["highway": "path", "name": "Bull Creek West Loop"],
            pack: "tx-east"
        )
        XCTAssertEqual(bullLoop.klass, "Trail")
        XCTAssertNotEqual(bullLoop.klass, "Wildlife range")

        let lowerBarton = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Lower Barton Creek Management Unit",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(lowerBarton.klass, "Wildlife range")
        XCTAssertNotEqual(lowerBarton.klass, "Open reserve")
        XCTAssertEqual(lowerBarton.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(lowerBarton.doLine.lowercased().contains("edible"), lowerBarton.doLine)

        let littleBear = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Little Bear Creek Management Unit",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(littleBear.klass, "Wildlife range")
        XCTAssertNotEqual(littleBear.klass, "Open reserve")
        XCTAssertEqual(littleBear.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(littleBear.doLine.lowercased().contains("edible"), littleBear.doLine)

        let stillhouse = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Stillhouse Hollow Nature Preserve",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(stillhouse.klass, "Wildlife range")
        XCTAssertNotEqual(stillhouse.klass, "Open reserve")
        XCTAssertEqual(stillhouse.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(stillhouse.doLine.lowercased().contains("edible"), stillhouse.doLine)

        let bigWalnut = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Big Walnut Creek Nature Preserve",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(bigWalnut.klass, "Wildlife range")
        XCTAssertNotEqual(bigWalnut.klass, "Open reserve")
        XCTAssertEqual(bigWalnut.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(bigWalnut.doLine.lowercased().contains("edible"), bigWalnut.doLine)

        let shadyHollow = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Shady Hollow West Nature Preserve",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(shadyHollow.klass, "Wildlife range")
        XCTAssertNotEqual(shadyHollow.klass, "Open reserve")
        XCTAssertNotEqual(shadyHollow.klass, "Cave or hole")
        XCTAssertEqual(shadyHollow.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(shadyHollow.doLine.lowercased().contains("edible"), shadyHollow.doLine)

        let redBluff = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Red Bluff Nature Preserve",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(redBluff.klass, "Wildlife range")
        XCTAssertNotEqual(redBluff.klass, "Open reserve")
        XCTAssertEqual(redBluff.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(redBluff.doLine.lowercased().contains("edible"), redBluff.doLine)

        let redBluffPark = Inspect.read(
            tags: ["leisure": "park", "name": "Red Bluff Neighborhood Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(redBluffPark.klass, "Park")
        XCTAssertNotEqual(redBluffPark.klass, "Wildlife range")

        let blunn = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Blunn Creek Nature Preserve",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(blunn.klass, "Wildlife range")
        XCTAssertNotEqual(blunn.klass, "Open reserve")
        XCTAssertEqual(blunn.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(blunn.doLine.lowercased().contains("edible"), blunn.doLine)

        let oltorf = Inspect.read(
            tags: ["highway": "secondary", "name": "East Oltorf Street"],
            pack: "tx-east"
        )
        XCTAssertEqual(oltorf.klass, "Road")
        XCTAssertNotEqual(oltorf.klass, "Wildlife range")

        let austinSimon = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Balcones Canyonlands Preserve - Austin Simon",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(austinSimon.klass, "Wildlife range")
        XCTAssertNotEqual(austinSimon.klass, "Open reserve")

        let limeCreek = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Balcones Canyonlands Preserve - Lime Creek",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(limeCreek.klass, "Wildlife range")
        XCTAssertNotEqual(limeCreek.klass, "Open reserve")

        let romberg = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Balcones Canyonlands Preserve - Romberg",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(romberg.klass, "Wildlife range")
        XCTAssertNotEqual(romberg.klass, "Open reserve")
        XCTAssertEqual(romberg.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(romberg.doLine.lowercased().contains("edible"), romberg.doLine)

        let mcgregor = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Balcones Canyonlands Preserve - McGregor",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(mcgregor.klass, "Wildlife range")
        XCTAssertNotEqual(mcgregor.klass, "Open reserve")
        XCTAssertEqual(mcgregor.fieldRoute.first, Inspect.mammalEastCard)
        XCTAssertFalse(mcgregor.doLine.lowercased().contains("edible"), mcgregor.doLine)

        let comancheTrail = Inspect.read(
            tags: ["highway": "unclassified", "name": "Comanche Trail"],
            pack: "tx-east"
        )
        XCTAssertEqual(comancheTrail.klass, "Road")
        XCTAssertNotEqual(comancheTrail.klass, "Wildlife range")

        let hippieHollow = Inspect.read(
            tags: ["leisure": "park", "name": "Hippie Hollow Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(hippieHollow.klass, "Park")
        XCTAssertNotEqual(hippieHollow.klass, "Wildlife range")

        let bernardo = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Bernardo Wildlife Management Area",
            ],
            pack: "nm"
        )
        XCTAssertEqual(bernardo.klass, "Wildlife range")
        XCTAssertNotEqual(bernardo.klass, "Park")
        XCTAssertEqual(bernardo.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(bernardo.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertFalse(bernardo.doLine.lowercased().contains("edible"), bernardo.doLine)

        let bernardoPark = Inspect.read(
            tags: ["leisure": "park", "name": "Bernardo Trails Park"],
            pack: "nm"
        )
        XCTAssertEqual(bernardoPark.klass, "Park")
        XCTAssertNotEqual(bernardoPark.klass, "Wildlife range")

        let donBernardo = Inspect.read(
            tags: ["highway": "residential", "name": "Don Bernardo Road"],
            pack: "nm"
        )
        XCTAssertEqual(donBernardo.klass, "Road")
        XCTAssertNotEqual(donBernardo.klass, "Wildlife range")

        let valle = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Valle de Oro National Wildlife Refuge",
            ],
            pack: "nm"
        )
        XCTAssertEqual(valle.klass, "Wildlife range")
        XCTAssertNotEqual(valle.klass, "Park")
        XCTAssertEqual(valle.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(valle.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertFalse(valle.doLine.lowercased().contains("edible"), valle.doLine)

        let valleBosque = Inspect.read(
            tags: ["leisure": "park", "name": "Valle del Bosque Park"],
            pack: "nm"
        )
        XCTAssertEqual(valleBosque.klass, "Park")
        XCTAssertNotEqual(valleBosque.klass, "Wildlife range")

        let sevilleta = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Sevilleta National Wildlife Refuge",
            ],
            pack: "nm"
        )
        XCTAssertEqual(sevilleta.klass, "Wildlife range")
        XCTAssertNotEqual(sevilleta.klass, "Open reserve")
        XCTAssertEqual(sevilleta.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(sevilleta.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertFalse(sevilleta.doLine.lowercased().contains("edible"), sevilleta.doLine)

        let oldHighway85 = Inspect.read(
            tags: ["highway": "unclassified", "name": "Old Highway 85"],
            pack: "nm"
        )
        XCTAssertEqual(oldHighway85.klass, "Road")
        XCTAssertNotEqual(oldHighway85.klass, "Wildlife range")

        let laJoya = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "La Joya Wildlife Management Area",
            ],
            pack: "nm"
        )
        XCTAssertEqual(laJoya.klass, "Wildlife range")
        XCTAssertNotEqual(laJoya.klass, "Park")
        XCTAssertEqual(laJoya.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(laJoya.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertFalse(laJoya.doLine.lowercased().contains("edible"), laJoya.doLine)

        let rioRancho = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Rio Rancho Bosque Nature Preserve",
            ],
            pack: "nm"
        )
        XCTAssertEqual(rioRancho.klass, "Wildlife range")
        XCTAssertNotEqual(rioRancho.klass, "Bosque or wetland")
        XCTAssertNotEqual(rioRancho.klass, "Open reserve")
        XCTAssertEqual(rioRancho.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(rioRancho.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertFalse(rioRancho.doLine.lowercased().contains("cottonwood"), rioRancho.doLine)
        XCTAssertFalse(rioRancho.doLine.lowercased().contains("edible"), rioRancho.doLine)

        let pecosComplex = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Pecos River Complex Wildlife Management Areas",
            ],
            pack: "nm"
        )
        XCTAssertEqual(pecosComplex.klass, "Wildlife range")
        XCTAssertNotEqual(pecosComplex.klass, "Open reserve")
        XCTAssertEqual(pecosComplex.fieldRoute.first, Inspect.mammalTXCard)
        XCTAssertTrue(pecosComplex.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertFalse(pecosComplex.doLine.lowercased().contains("edible"), pecosComplex.doLine)

        let pecosHighway = Inspect.read(
            tags: ["highway": "secondary", "name": "State Highway 63"],
            pack: "nm"
        )
        XCTAssertEqual(pecosHighway.klass, "Road")
        XCTAssertNotEqual(pecosHighway.klass, "Wildlife range")

        let stablesRoad = Inspect.read(
            tags: ["highway": "residential", "name": "Rio Grande Stables Road"],
            pack: "nm"
        )
        XCTAssertEqual(stablesRoad.klass, "Road")
        XCTAssertNotEqual(stablesRoad.klass, "Wildlife range")

        let calleDelBosque = Inspect.read(
            tags: ["highway": "residential", "name": "Calle del Bosque Northwest"],
            pack: "nm"
        )
        XCTAssertEqual(calleDelBosque.klass, "Road")
        XCTAssertNotEqual(calleDelBosque.klass, "Bosque or wetland")
        XCTAssertNotEqual(calleDelBosque.klass, "Wildlife range")

        let oakdale = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Brodie and Oakdale Properties"],
            pack: "tx-east"
        )
        XCTAssertEqual(oakdale.klass, "Open reserve")
        XCTAssertNotEqual(oakdale.klass, "Wildlife range")

        let waste = Inspect.read(
            tags: ["leisure": "nature_reserve", "name": "Waste Management Wildlife Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(waste.klass, "Open reserve")
        XCTAssertNotEqual(waste.klass, "Wildlife range")
    }

    func testAnOpenReserveIsSnakeCountryNotPicnicWoodland() {
        let alamo = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Alamo Mountain Area of Critical Environmental Concern",
            ],
            state: "TX",
            pack: "tx-west"
        )
        XCTAssertEqual(alamo.klass, "Open reserve")
        XCTAssertEqual(alamo.fieldRoute.first, Inspect.snakeTXCard)
        XCTAssertTrue(alamo.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertTrue(alamo.fieldRoute.contains(Inspect.mammalTXCard))
        XCTAssertEqual(InspectField.label(for: alamo.fieldRoute[0]), "FIELD · BITE")
        XCTAssertEqual(
            InspectField.bookLine(for: InspectField.presentRoute(
                alamo.fieldRoute,
                in: [
                    Inspect.snakeTXCard, Inspect.mammalTXCard, Inspect.cactusTXCard,
                    Inspect.treeUseTXCard, Inspect.plantTXCard, Inspect.gameTXCard,
                    Inspect.biteCard, Inspect.plantUseCard, Inspect.gameCard,
                    Inspect.heatCard,
                ]
            )),
            "BITE · ANIMAL · PLANT · FOOD · HEAT"
        )
        XCTAssertTrue(alamo.doLine.lowercased().contains("diamondback"), alamo.doLine)
        XCTAssertTrue(alamo.doLine.lowercased().contains("bite card"), alamo.doLine)
        XCTAssertTrue(alamo.doLine.lowercased().contains("no ice"), alamo.doLine)
        XCTAssertTrue(alamo.doLine.lowercased().contains("give it room"), alamo.doLine)
        XCTAssertFalse(alamo.doLine.lowercased().contains("live oak"), alamo.doLine)
        XCTAssertFalse(alamo.doLine.lowercased().contains("edible"), alamo.doLine)
        XCTAssertFalse(alamo.doLine.lowercased().contains("lives here"), alamo.doLine)

        let jones = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Jones Canyon Area of Critical Environmental Concern",
            ],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(jones.klass, "Open reserve")
        XCTAssertEqual(jones.fieldRoute.first, Inspect.snakeTXCard)
        XCTAssertTrue(jones.fieldRoute.contains(Inspect.snakeNMCard))
        let nmBook: Set<String> = [
            Inspect.snakeNMCard, Inspect.mammalNMCard, Inspect.cactusNMCard,
            Inspect.treeUseNMCard, Inspect.plantNMCard, Inspect.gameNMCard,
            Inspect.biteCard, Inspect.plantUseCard, Inspect.gameCard, Inspect.heatCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(jones.fieldRoute, in: nmBook).first,
            Inspect.snakeNMCard
        )
        XCTAssertTrue(jones.doLine.lowercased().contains("rattler") || jones.doLine.lowercased().contains("diamondback"), jones.doLine)
        XCTAssertTrue(jones.doLine.lowercased().contains("bite card"), jones.doLine)
        XCTAssertTrue(jones.doLine.lowercased().contains("no ice"), jones.doLine)
        XCTAssertTrue(jones.doLine.lowercased().contains("give it room"), jones.doLine)
        XCTAssertFalse(jones.doLine.lowercased().contains("cottonwood"), jones.doLine)

        let prairie = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "natural": "scrub",
                "name": "Decker Tallgrass Prairie Preserve",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(prairie.klass, "Open reserve")
        XCTAssertNotEqual(prairie.klass, "Desert scrub")
        XCTAssertEqual(prairie.fieldRoute.first, Inspect.snakeEastCard)
        XCTAssertTrue(prairie.doLine.lowercased().contains("cottonmouth"), prairie.doLine)

        let overlayPrairie = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Decker Tallgrass Prairie Preserve",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(overlayPrairie.klass, "Open reserve")
        XCTAssertEqual(overlayPrairie.fieldRoute.first, Inspect.snakeEastCard)

        let cave = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Pronoun Cave Area of Critical Environmental Concern",
            ],
            pack: "nm"
        )
        XCTAssertEqual(cave.klass, "Cave or hole")
        XCTAssertEqual(cave.fieldRoute, [Inspect.caveCard, Inspect.coldCard])
        XCTAssertNotEqual(cave.klass, "Open reserve")

        let hills = Inspect.read(
            tags: ["landuse": "residential", "name": "Prairie Hills Apartments"],
            pack: "nm"
        )
        XCTAssertEqual(hills.klass, "Built-up ground")
        XCTAssertNotEqual(hills.klass, "Open reserve")

        let street = Inspect.read(
            tags: ["highway": "residential", "name": "Gracecus Way"],
            pack: "tx-west"
        )
        XCTAssertEqual(street.klass, "Road")
        XCTAssertFalse(street.fieldRoute.contains(Inspect.snakeTXCard))

        let mesa = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Paseo de la Mesa Open Space",
            ],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(mesa.klass, "Open reserve")
        XCTAssertNotEqual(mesa.klass, "Protected land")
        XCTAssertEqual(mesa.fieldRoute.first, Inspect.snakeTXCard)
        XCTAssertTrue(mesa.fieldRoute.contains(Inspect.snakeNMCard))
        XCTAssertTrue(mesa.doLine.lowercased().contains("rattler") || mesa.doLine.lowercased().contains("diamondback"), mesa.doLine)
        XCTAssertTrue(mesa.doLine.lowercased().contains("sotol") || mesa.doLine.lowercased().contains("cholla"), mesa.doLine)
        XCTAssertTrue(mesa.doLine.lowercased().contains("give it room"), mesa.doLine)
        XCTAssertTrue(mesa.doLine.lowercased().contains("no ice"), mesa.doLine)
        XCTAssertFalse(mesa.doLine.lowercased().contains("cottonwood"), mesa.doLine)
        XCTAssertFalse(mesa.doLine.lowercased().contains("edible"), mesa.doLine)

        let unnamedReserve = Inspect.read(
            tags: ["leisure": "nature_reserve"],
            pack: "nm"
        )
        XCTAssertEqual(unnamedReserve.klass, "Protected land")
        XCTAssertNotEqual(unnamedReserve.klass, "Open reserve")

        let farmPreserve = Inspect.read(
            tags: ["leisure": "park", "name": "Candelaria Farm Preserve Open Space"],
            pack: "nm"
        )
        XCTAssertEqual(farmPreserve.klass, "Park")
        XCTAssertNotEqual(farmPreserve.klass, "Open reserve")

        let hueco = Inspect.read(
            tags: [
                "leisure": "park",
                "boundary": "protected_area",
                "name": "Hueco Tanks State Park and Historic Site",
            ],
            pack: "tx-west"
        )
        XCTAssertEqual(hueco.klass, "Open reserve")
        XCTAssertNotEqual(hueco.klass, "Park")
        XCTAssertEqual(hueco.fieldRoute.first, Inspect.snakeTXCard)
        XCTAssertTrue(hueco.doLine.lowercased().contains("diamondback"), hueco.doLine)
        XCTAssertTrue(hueco.doLine.lowercased().contains("javelina"), hueco.doLine)
        XCTAssertTrue(hueco.doLine.lowercased().contains("give it room"), hueco.doLine)
        XCTAssertTrue(hueco.doLine.lowercased().contains("no ice"), hueco.doLine)
        XCTAssertFalse(hueco.doLine.lowercased().contains("cottonwood"), hueco.doLine)
        XCTAssertFalse(hueco.doLine.lowercased().contains("mesquite"), hueco.doLine)
        XCTAssertFalse(hueco.doLine.lowercased().contains("edible"), hueco.doLine)

        let forest = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Cibola National Forest",
            ],
            pack: "nm"
        )
        XCTAssertEqual(forest.klass, "Protected land")
        XCTAssertNotEqual(forest.klass, "Open reserve")
        XCTAssertEqual(forest.fieldRoute.first, Inspect.treeUseTXCard)
        XCTAssertTrue(forest.fieldRoute.contains(Inspect.treeUseNMCard))
        let nmTimber: Set<String> = [
            Inspect.treeUseNMCard, Inspect.plantNMCard, Inspect.mammalNMCard,
            Inspect.gameNMCard, Inspect.plantUseCard, Inspect.biteCard,
            Inspect.shelterCard, Inspect.fungiCard, Inspect.gameCard, Inspect.plantCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(forest.fieldRoute, in: nmTimber).first,
            Inspect.treeUseNMCard
        )

        let lincoln = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Lincoln National Forest",
            ],
            pack: "nm"
        )
        XCTAssertEqual(lincoln.klass, "Protected land")
        XCTAssertNotEqual(lincoln.klass, "Open reserve")

        let franklin = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Franklin Mountains State Park",
            ],
            pack: "tx-west"
        )
        XCTAssertEqual(franklin.klass, "Open reserve")
        XCTAssertEqual(franklin.fieldRoute.first, Inspect.snakeTXCard)

        let huecoTown = Inspect.read(
            tags: ["leisure": "park", "name": "Hueco Mountain Park"],
            pack: "tx-west"
        )
        XCTAssertEqual(huecoTown.klass, "Park")
        XCTAssertNotEqual(huecoTown.klass, "Open reserve")

        let huecoRoad = Inspect.read(
            tags: ["highway": "tertiary", "name": "Hueco Tanks Road"],
            pack: "tx-west"
        )
        XCTAssertEqual(huecoRoad.klass, "Road")
        XCTAssertNotEqual(huecoRoad.klass, "Open reserve")

        let golden = Inspect.read(
            tags: ["leisure": "park", "name": "Golden Open Space"],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(golden.klass, "Open reserve")
        XCTAssertNotEqual(golden.klass, "Park")
        XCTAssertEqual(golden.fieldRoute.first, Inspect.snakeTXCard)
        XCTAssertTrue(golden.doLine.lowercased().contains("rattler") || golden.doLine.lowercased().contains("diamondback"), golden.doLine)
        XCTAssertTrue(golden.doLine.lowercased().contains("sotol") || golden.doLine.lowercased().contains("cholla"), golden.doLine)
        XCTAssertFalse(golden.doLine.lowercased().contains("cottonwood"), golden.doLine)
        XCTAssertFalse(golden.doLine.lowercased().contains("edible"), golden.doLine)

        let bearCanyon = Inspect.read(
            tags: ["leisure": "park", "name": "Bear Canyon Open Space West"],
            pack: "nm"
        )
        XCTAssertEqual(bearCanyon.klass, "Open reserve")
        XCTAssertNotEqual(bearCanyon.klass, "Park")

        let rioBosqueOpen = Inspect.read(
            tags: ["leisure": "park", "name": "Alameda/Rio Grande Open Space"],
            pack: "nm"
        )
        XCTAssertEqual(rioBosqueOpen.klass, "Park")
        XCTAssertNotEqual(rioBosqueOpen.klass, "Open reserve")

        let bachechi = Inspect.read(
            tags: ["leisure": "park", "name": "Bachechi Open Space"],
            pack: "nm"
        )
        XCTAssertEqual(bachechi.klass, "Park")
        XCTAssertNotEqual(bachechi.klass, "Open reserve")

        let trailhead = Inspect.read(
            tags: ["leisure": "park", "name": "Embudito Trailhead Open Space"],
            pack: "nm"
        )
        XCTAssertEqual(trailhead.klass, "Park")
        XCTAssertNotEqual(trailhead.klass, "Open reserve")

        let scenic = Inspect.read(
            tags: ["leisure": "park", "name": "Bear Canyon Scenic Easement"],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(scenic.klass, "Open reserve")
        XCTAssertNotEqual(scenic.klass, "Park")
        XCTAssertEqual(scenic.fieldRoute.first, Inspect.snakeTXCard)
        XCTAssertTrue(scenic.doLine.lowercased().contains("rattler") || scenic.doLine.lowercased().contains("diamondback"), scenic.doLine)
        XCTAssertTrue(scenic.doLine.lowercased().contains("sotol") || scenic.doLine.lowercased().contains("cholla"), scenic.doLine)
        XCTAssertFalse(scenic.doLine.lowercased().contains("cottonwood"), scenic.doLine)
        XCTAssertFalse(scenic.doLine.lowercased().contains("edible"), scenic.doLine)

        let riverside = Inspect.read(
            tags: [
                "leisure": "park",
                "name": "Ann and Roy Butler Hike and Bike 222 Riverside Easement",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(riverside.klass, "Park")
        XCTAssertNotEqual(riverside.klass, "Open reserve")

        let tierra = Inspect.read(
            tags: [
                "leisure": "park",
                "landuse": "recreation_ground",
                "name": "La Tierra Trails",
            ],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(tierra.klass, "Open reserve")
        XCTAssertNotEqual(tierra.klass, "Park")
        XCTAssertNotEqual(tierra.klass, "Irrigated ground")
        XCTAssertEqual(tierra.fieldRoute.first, Inspect.snakeTXCard)
        XCTAssertTrue(tierra.doLine.lowercased().contains("rattler") || tierra.doLine.lowercased().contains("diamondback"), tierra.doLine)
        XCTAssertTrue(tierra.doLine.lowercased().contains("sotol") || tierra.doLine.lowercased().contains("cholla"), tierra.doLine)
        XCTAssertFalse(tierra.doLine.lowercased().contains("cottonwood"), tierra.doLine)
        XCTAssertFalse(tierra.doLine.lowercased().contains("edible"), tierra.doLine)

        let blanca = Inspect.read(
            tags: ["leisure": "park", "name": "Tierra Blanca"],
            pack: "tx-west"
        )
        XCTAssertEqual(blanca.klass, "Park")
        XCTAssertNotEqual(blanca.klass, "Open reserve")

        let desertTrails = Inspect.read(
            tags: ["leisure": "park", "name": "Desert Trails Community Park"],
            pack: "tx-west"
        )
        XCTAssertEqual(desertTrails.klass, "Park")
        XCTAssertNotEqual(desertTrails.klass, "Open reserve")

        let sun = Inspect.read(
            tags: ["boundary": "protected_area", "name": "Sun Mountain"],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(sun.klass, "Open reserve")
        XCTAssertNotEqual(sun.klass, "Protected land")
        XCTAssertEqual(sun.fieldRoute.first, Inspect.snakeTXCard)
        XCTAssertTrue(sun.doLine.lowercased().contains("rattler") || sun.doLine.lowercased().contains("diamondback"), sun.doLine)
        XCTAssertTrue(sun.doLine.lowercased().contains("sotol") || sun.doLine.lowercased().contains("cholla"), sun.doLine)
        XCTAssertFalse(sun.doLine.lowercased().contains("cottonwood"), sun.doLine)
        XCTAssertFalse(sun.doLine.lowercased().contains("edible"), sun.doLine)

        let sunPeak = Inspect.read(
            tags: ["natural": "peak", "name": "Sun Mountain"],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(sunPeak.klass, "Peak")
        XCTAssertNotEqual(sunPeak.klass, "Open reserve")

        let sunEstates = Inspect.read(
            tags: [
                "landuse": "residential",
                "place": "neighbourhood",
                "name": "Sun Mountain Estates",
            ],
            pack: "nm"
        )
        XCTAssertEqual(sunEstates.klass, "Built-up ground")
        XCTAssertNotEqual(sunEstates.klass, "Open reserve")

        let sunRoad = Inspect.read(
            tags: ["highway": "residential", "name": "Sun Mountain Road"],
            pack: "nm"
        )
        XCTAssertEqual(sunRoad.klass, "Road")
        XCTAssertNotEqual(sunRoad.klass, "Open reserve")

        let hyde = Inspect.read(
            tags: ["boundary": "protected_area", "name": "Hyde Memorial State Park"],
            pack: "nm"
        )
        XCTAssertEqual(hyde.klass, "Protected land")
        XCTAssertNotEqual(hyde.klass, "Open reserve")
    }

    func testANamedTreeIsPlantGroundNotAMeal() {
        let tree = Inspect.read(tags: ["natural": "tree", "name": "El Paso Cottonwood"])
        XCTAssertEqual(tree.title, "El Paso Cottonwood")
        XCTAssertEqual(tree.klass, "Named tree")
        XCTAssertEqual(tree.fieldRoute.last, Inspect.plantCard)
        XCTAssertEqual(tree.fieldRoute.first, Inspect.treeUseTXCard)
        XCTAssertTrue(tree.fieldRoute.contains(Inspect.plantUseCard))
        XCTAssertFalse(tree.fieldRoute.contains(Inspect.mammalTXCard), "a named tree is not javelina country")
        XCTAssertFalse(tree.fieldRoute.contains(Inspect.gameTXCard))
        XCTAssertFalse(tree.doLine.lowercased().contains("edible"), tree.doLine)
        XCTAssertFalse(tree.doLine.lowercased().contains("javelina"), tree.doLine)
        XCTAssertFalse(tree.doLine.lowercased().contains("hog"), tree.doLine)
        XCTAssertFalse(tree.doLine.lowercased().contains("coyote"), tree.doLine)
        XCTAssertTrue(tree.doLine.lowercased().contains("not a meal"), tree.doLine)

        let westTree = Inspect.read(
            tags: ["natural": "tree", "name": "El Paso Cottonwood"],
            state: "TX",
            pack: "tx-west"
        )
        let westTreeDo = westTree.doLine.lowercased()
        XCTAssertTrue(westTreeDo.contains("mesquite"), westTree.doLine)
        XCTAssertTrue(westTreeDo.contains("cottonwood"), westTree.doLine)
        XCTAssertTrue(westTreeDo.contains("deadfall"), westTree.doLine)
        XCTAssertFalse(westTreeDo.contains("javelina"), westTree.doLine)
        XCTAssertFalse(westTreeDo.contains("hog"), westTree.doLine)
        XCTAssertFalse(westTreeDo.contains("bite card"), westTree.doLine)

        let nmTree = Inspect.read(
            tags: ["natural": "tree", "name": "Bosque Cottonwood"],
            state: "NM",
            pack: "nm"
        )
        let nmTreeDo = nmTree.doLine.lowercased()
        XCTAssertTrue(nmTreeDo.contains("cottonwood"), nmTree.doLine)
        XCTAssertFalse(nmTreeDo.contains("aspen"), nmTree.doLine)
        XCTAssertFalse(nmTreeDo.contains("bear"), nmTree.doLine)
        XCTAssertFalse(nmTreeDo.contains("elk"), nmTree.doLine)
        XCTAssertFalse(nmTreeDo.contains("javelina"), nmTree.doLine)

        let sorin = Inspect.read(
            tags: ["natural": "tree", "name": "Sorin Oak"],
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(sorin.klass, "Named tree")
        XCTAssertEqual(sorin.title, "Sorin Oak")
        XCTAssertEqual(sorin.fieldRoute.first, Inspect.treeUseEastCard)
        XCTAssertFalse(sorin.doLine.lowercased().contains("edible"), sorin.doLine)
        XCTAssertTrue(sorin.doLine.lowercased().contains("not a meal"), sorin.doLine)

        let sorinStreet = Inspect.read(
            tags: ["highway": "residential", "name": "Sorin Street"],
            pack: "tx-east"
        )
        XCTAssertEqual(sorinStreet.klass, "Road")
        XCTAssertNotEqual(sorinStreet.klass, "Named tree")

        let velvet = Inspect.read(
            tags: ["natural": "tree", "name": "Prosopis velutina / Velvet Mesquite"],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(velvet.klass, "Named tree")
        XCTAssertEqual(velvet.title, "Prosopis velutina / Velvet Mesquite")
        XCTAssertEqual(velvet.fieldRoute.first, Inspect.treeUseTXCard)
        XCTAssertTrue(velvet.fieldRoute.contains(Inspect.treeUseNMCard))
        XCTAssertFalse(velvet.doLine.lowercased().contains("edible"), velvet.doLine)
        XCTAssertTrue(velvet.doLine.lowercased().contains("not a meal"), velvet.doLine)

        let landry = Inspect.read(
            tags: ["highway": "residential", "name": "Landry Avenue Northwest"],
            pack: "nm"
        )
        XCTAssertEqual(landry.klass, "Road")
        XCTAssertNotEqual(landry.klass, "Named tree")

        let argus = Inspect.read(
            tags: ["natural": "tree", "name": "Argus"],
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(argus.klass, "Named tree")
        XCTAssertEqual(argus.title, "Argus")
        XCTAssertEqual(argus.fieldRoute.first, Inspect.treeUseEastCard)
        XCTAssertFalse(argus.doLine.lowercased().contains("edible"), argus.doLine)
        XCTAssertTrue(argus.doLine.lowercased().contains("not a meal"), argus.doLine)

        let arthurStiles = Inspect.read(
            tags: ["highway": "residential", "name": "Arthur Stiles Road"],
            pack: "tx-east"
        )
        XCTAssertEqual(arthurStiles.klass, "Road")
        XCTAssertNotEqual(arthurStiles.klass, "Named tree")

        let johnstonTerrace = Inspect.read(
            tags: ["landuse": "residential", "name": "Johnston Terrace"],
            pack: "tx-east"
        )
        XCTAssertEqual(johnstonTerrace.klass, "Built-up ground")
        XCTAssertNotEqual(johnstonTerrace.klass, "Named tree")

        let kimBird = Inspect.read(
            tags: ["natural": "tree", "name": "Kim Bird Gebert Memorial Tree"],
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(kimBird.klass, "Named tree")
        XCTAssertEqual(kimBird.title, "Kim Bird Gebert Memorial Tree")
        XCTAssertEqual(kimBird.fieldRoute.first, Inspect.treeUseEastCard)
        XCTAssertFalse(kimBird.doLine.lowercased().contains("edible"), kimBird.doLine)
        XCTAssertTrue(kimBird.doLine.lowercased().contains("not a meal"), kimBird.doLine)

        let silentHarbor = Inspect.read(
            tags: ["highway": "residential", "name": "Silent Harbor Loop"],
            pack: "tx-east"
        )
        XCTAssertEqual(silentHarbor.klass, "Road")
        XCTAssertNotEqual(silentHarbor.klass, "Named tree")

        let pflugervillePark = Inspect.read(
            tags: ["leisure": "park", "name": "Lake Pflugerville Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(pflugervillePark.klass, "Park")
        XCTAssertNotEqual(pflugervillePark.klass, "Named tree")
    }

    func testTheOpenPackNamesItsTreesAndAnimalsAsRangeNotPins() {
        // The hold names the Field book of the open pack. It does not pin a
        // javelina to a coordinate.
        let txWood = Inspect.read(tags: ["natural": "wood"], state: "TX")
        let txWoodDo = txWood.doLine.lowercased()
        XCTAssertTrue(txWoodDo.contains("mesquite"), txWood.doLine)
        XCTAssertTrue(txWoodDo.contains("cedar elm"), txWood.doLine)
        XCTAssertTrue(txWoodDo.contains("javelina"), txWood.doLine)
        XCTAssertTrue(txWoodDo.contains("coyote"), txWood.doLine)
        XCTAssertTrue(txWoodDo.contains("bite card"), txWood.doLine)
        XCTAssertTrue(txWoodDo.contains("deadfall"), txWood.doLine)
        XCTAssertTrue(txWoodDo.contains("south-side"), txWood.doLine)
        XCTAssertTrue(txWoodDo.contains("wind break"), txWood.doLine)
        XCTAssertTrue(txWoodDo.contains("not a meal"), txWood.doLine)
        XCTAssertTrue(txWoodDo.contains("give it the road"), txWood.doLine)
        XCTAssertFalse(txWoodDo.contains("food card"), txWood.doLine)
        XCTAssertFalse(txWoodDo.contains("edible"), txWood.doLine)
        XCTAssertFalse(txWoodDo.contains("lives here"), txWood.doLine)

        let nmWood = Inspect.read(tags: ["natural": "wood"], state: "NM")
        let nmWoodDo = nmWood.doLine.lowercased()
        XCTAssertTrue(
            nmWoodDo.contains("cottonwood") || nmWoodDo.contains("piñon") || nmWoodDo.contains("juniper"),
            nmWood.doLine
        )
        XCTAssertTrue(nmWoodDo.contains("rio grande"), nmWood.doLine)
        XCTAssertFalse(nmWoodDo.contains("aspen"), nmWood.doLine)
        XCTAssertTrue(nmWoodDo.contains("elk is high country"), nmWood.doLine)
        XCTAssertTrue(nmWoodDo.contains("mule deer"), nmWood.doLine)
        XCTAssertTrue(nmWoodDo.contains("bite card"), nmWood.doLine)
        XCTAssertTrue(nmWoodDo.contains("give it the road"), nmWood.doLine)
        XCTAssertFalse(nmWoodDo.contains("food card"), nmWood.doLine)

        let txScrub = Inspect.read(tags: ["natural": "scrub"], state: "TX")
        let txScrubDo = txScrub.doLine.lowercased()
        XCTAssertTrue(txScrubDo.contains("javelina") || txScrubDo.contains("diamondback"), txScrub.doLine)
        XCTAssertTrue(txScrubDo.contains("bite card"), txScrub.doLine)
        XCTAssertTrue(txScrubDo.contains("no ice"), txScrub.doLine)
        XCTAssertTrue(txScrubDo.contains("no cut"), txScrub.doLine)
        XCTAssertFalse(txScrubDo.contains("edible"), txScrub.doLine)
        XCTAssertFalse(txScrubDo.contains("lives here"), txScrub.doLine)
        XCTAssertFalse(txScrubDo.contains("standing here"), txScrub.doLine)
        XCTAssertTrue(txScrubDo.contains("yucca") || txScrubDo.contains("prickly"), txScrub.doLine)

        let nmPeak = Inspect.read(tags: ["natural": "peak", "name": "Wheeler"], state: "NM")
        XCTAssertTrue(nmPeak.doLine.lowercased().contains("bear"), nmPeak.doLine)
        XCTAssertTrue(nmPeak.doLine.lowercased().contains("elk"), nmPeak.doLine)
        XCTAssertFalse(nmPeak.doLine.lowercased().contains("bite card"), nmPeak.doLine)

        let txPeak = Inspect.read(tags: ["natural": "peak", "name": "North Franklin"], state: "TX")
        let txPeakDo = txPeak.doLine.lowercased()
        XCTAssertTrue(txPeakDo.contains("javelina"), txPeak.doLine)
        XCTAssertTrue(txPeakDo.contains("coyote") || txPeakDo.contains("deer"), txPeak.doLine)
        XCTAssertFalse(txPeakDo.contains("ice"), txPeak.doLine)
        XCTAssertFalse(txPeakDo.contains("bite card"), txPeak.doLine)
        XCTAssertFalse(txPeakDo.contains("food card"), txPeak.doLine)
        XCTAssertFalse(txPeakDo.contains("lives here"), txPeak.doLine)

        let txRock = Inspect.read(tags: ["natural": "bare_rock"], state: "TX")
        XCTAssertFalse(txRock.doLine.lowercased().contains("ice"), txRock.doLine)
        XCTAssertTrue(txRock.doLine.lowercased().contains("javelina"), txRock.doLine)
        XCTAssertTrue(
            txRock.doLine.lowercased().contains("coyote") || txRock.doLine.lowercased().contains("deer"),
            txRock.doLine
        )
        XCTAssertFalse(txRock.doLine.lowercased().contains("bite card"), txRock.doLine)

        let grass = Inspect.read(tags: ["natural": "grass"])
        XCTAssertEqual(grass.klass, "Grassland")
        XCTAssertEqual(grass.fieldRoute.first, Inspect.snakeTXCard)

        let westWood = Inspect.read(tags: ["natural": "wood"], state: "TX", pack: "tx-west")
        XCTAssertTrue(westWood.doLine.lowercased().contains("javelina"), westWood.doLine)
        XCTAssertTrue(westWood.doLine.lowercased().contains("deer"), westWood.doLine)
        XCTAssertTrue(westWood.doLine.lowercased().contains("mesquite"), westWood.doLine)
        XCTAssertTrue(westWood.doLine.lowercased().contains("cottonwood"), westWood.doLine)
        XCTAssertTrue(westWood.doLine.lowercased().contains("bite card"), westWood.doLine)
        XCTAssertTrue(westWood.doLine.lowercased().contains("give it the road"), westWood.doLine)
        XCTAssertFalse(westWood.doLine.lowercased().contains("food card"), westWood.doLine)

        let eastWood = Inspect.read(tags: ["natural": "wood"], state: "TX", pack: "tx-east")
        let eastWoodDo = eastWood.doLine.lowercased()
        XCTAssertTrue(eastWoodDo.contains("cedar elm") || eastWoodDo.contains("live oak"), eastWood.doLine)
        XCTAssertTrue(eastWoodDo.contains("pine"), eastWood.doLine)
        XCTAssertTrue(eastWoodDo.contains("cottonwood"), eastWood.doLine)
        XCTAssertTrue(eastWoodDo.contains("coyote") || eastWoodDo.contains("deer"), eastWood.doLine)
        XCTAssertTrue(eastWoodDo.contains("hog"), eastWood.doLine)
        XCTAssertTrue(eastWoodDo.contains("bite card"), eastWood.doLine)
        XCTAssertTrue(eastWoodDo.contains("give it the road"), eastWood.doLine)
        XCTAssertFalse(eastWoodDo.contains("food card"), eastWood.doLine)
        XCTAssertFalse(eastWoodDo.contains("javelina"), eastWood.doLine)
        XCTAssertFalse(eastWoodDo.contains("mesquite"), eastWood.doLine)
        XCTAssertFalse(eastWoodDo.contains("edible"), eastWood.doLine)
        XCTAssertFalse(eastWoodDo.contains("lives here"), eastWood.doLine)

        let nmScrub = Inspect.read(tags: ["natural": "scrub"], state: "NM", pack: "nm")
        let nmScrubDo = nmScrub.doLine.lowercased()
        XCTAssertTrue(nmScrubDo.contains("prairie") || nmScrubDo.contains("rattler"), nmScrub.doLine)
        XCTAssertTrue(nmScrubDo.contains("diamondback"), nmScrub.doLine)
        XCTAssertTrue(nmScrubDo.contains("sotol"), nmScrub.doLine)
        XCTAssertTrue(nmScrubDo.contains("no ice"), nmScrub.doLine)
        XCTAssertTrue(nmScrubDo.contains("give it room"), nmScrub.doLine)
        XCTAssertFalse(nmScrubDo.contains("cottonmouth"), nmScrub.doLine)
        XCTAssertFalse(nmScrubDo.contains("lives here"), nmScrub.doLine)
        XCTAssertFalse(nmScrubDo.contains("edible"), nmScrub.doLine)

        let nmRange = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "State Game Commission Land",
            ],
            state: "NM",
            pack: "nm"
        )
        let nmRangeDo = nmRange.doLine.lowercased()
        XCTAssertTrue(nmRangeDo.contains("mule deer"), nmRange.doLine)
        XCTAssertTrue(nmRangeDo.contains("elk is high country"), nmRange.doLine)
        XCTAssertTrue(nmRangeDo.contains("bear") || nmRangeDo.contains("elk"), nmRange.doLine)
        XCTAssertTrue(nmRangeDo.contains("bite card"), nmRange.doLine)
        XCTAssertTrue(nmRangeDo.contains("food card"), nmRange.doLine)
        XCTAssertTrue(nmRangeDo.contains("give it the road"), nmRange.doLine)
        XCTAssertTrue(nmRangeDo.contains("cook through"), nmRange.doLine)
        XCTAssertTrue(nmRangeDo.contains("no ice"), nmRange.doLine)
        XCTAssertTrue(nmRangeDo.contains("range") || nmRangeDo.contains("not a pin"), nmRange.doLine)
        XCTAssertFalse(nmRangeDo.contains("cottonwood"), nmRange.doLine)
        XCTAssertFalse(nmRangeDo.contains("lives here"), nmRange.doLine)
        XCTAssertFalse(nmRangeDo.contains("edible"), nmRange.doLine)

        let eastScrub = Inspect.read(tags: ["natural": "scrub"], state: "TX", pack: "tx-east")
        let eastScrubDo = eastScrub.doLine.lowercased()
        XCTAssertTrue(eastScrubDo.contains("cottonmouth") || eastScrubDo.contains("copperhead"), eastScrub.doLine)
        XCTAssertTrue(eastScrubDo.contains("hog"), eastScrub.doLine)
        XCTAssertTrue(eastScrubDo.contains("give it room"), eastScrub.doLine)
        XCTAssertFalse(eastScrubDo.contains("javelina"), eastScrub.doLine)
        XCTAssertFalse(eastScrubDo.contains("lives here"), eastScrub.doLine)

        let eastWet = Inspect.read(tags: ["natural": "wetland"], state: "TX", pack: "tx-east")
        XCTAssertTrue(eastWet.doLine.lowercased().contains("cottonmouth"), eastWet.doLine)
        XCTAssertTrue(eastWet.doLine.lowercased().contains("hog"), eastWet.doLine)
        XCTAssertTrue(eastWet.doLine.lowercased().contains("bite card"), eastWet.doLine)
        XCTAssertTrue(eastWet.doLine.lowercased().contains("south-side"), eastWet.doLine)
        XCTAssertTrue(eastWet.doLine.lowercased().contains("give it the road"), eastWet.doLine)
        XCTAssertTrue(eastWet.doLine.lowercased().contains("no ice"), eastWet.doLine)
        XCTAssertFalse(eastWet.doLine.lowercased().contains("food card"), eastWet.doLine)
        XCTAssertFalse(eastWet.doLine.lowercased().contains("javelina"), eastWet.doLine)
        XCTAssertEqual(eastWet.fieldRoute.first, Inspect.treeUseEastCard)
        XCTAssertEqual(InspectField.label(for: eastWet.fieldRoute[0]), "FIELD · PLANT")
        XCTAssertTrue(eastWet.fieldRoute.contains(Inspect.snakeEastCard))
        XCTAssertFalse(eastWet.fieldRoute.contains(Inspect.snakeTXCard))
        XCTAssertFalse(eastWet.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertFalse(eastWood.fieldRoute.contains(Inspect.snakeEastCard))
        let eastBook: Set<String> = [
            Inspect.treeUseEastCard, Inspect.plantTXCard, Inspect.cactusTXCard,
            Inspect.mammalEastCard, Inspect.gameEastCard, Inspect.snakeEastCard,
            Inspect.plantUseCard, Inspect.biteCard, Inspect.shelterCard,
            Inspect.fungiCard, Inspect.gameCard, Inspect.plantCard,
        ]
        XCTAssertEqual(
            InspectField.bookLine(for: InspectField.presentRoute(eastWet.fieldRoute, in: eastBook)),
            "PLANT · ANIMAL · FOOD · BITE · SHELTER · FUNGI"
        )

        // East Texas shares field.tx.json with the west pack. The hold still
        // walks this pack's chapter — not mesquite, not javelina.
        XCTAssertEqual(eastWood.fieldRoute.first, Inspect.treeUseEastCard)
        XCTAssertEqual(InspectField.label(for: eastWood.fieldRoute[0]), "FIELD · PLANT")
        XCTAssertTrue(eastWood.fieldRoute.contains(Inspect.mammalEastCard))
        XCTAssertTrue(eastWood.fieldRoute.contains(Inspect.gameEastCard))
        XCTAssertFalse(eastWood.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertFalse(eastWood.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertFalse(eastWood.fieldRoute.contains(Inspect.mammalTXCard))
        XCTAssertFalse(eastWood.fieldRoute.contains(Inspect.gameTXCard))

        XCTAssertEqual(eastScrub.fieldRoute.first, Inspect.snakeEastCard)
        XCTAssertEqual(InspectField.label(for: eastScrub.fieldRoute[0]), "FIELD · BITE")
        XCTAssertFalse(eastScrub.fieldRoute.contains(Inspect.snakeTXCard))
        XCTAssertFalse(eastScrub.fieldRoute.contains(Inspect.mammalTXCard))

        let eastPeak = Inspect.read(
            tags: ["natural": "peak", "name": "McKinney Falls"],
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertTrue(eastPeak.fieldRoute.contains(Inspect.mammalEastCard))
        XCTAssertTrue(eastPeak.fieldRoute.contains(Inspect.biteCard), "an east peak walk includes bite treatment")
        XCTAssertFalse(eastPeak.fieldRoute.contains(Inspect.mammalTXCard))
        XCTAssertTrue(eastPeak.doLine.lowercased().contains("hog"), eastPeak.doLine)
        XCTAssertFalse(eastPeak.doLine.lowercased().contains("javelina"), eastPeak.doLine)
        XCTAssertFalse(eastPeak.doLine.lowercased().contains("ice"), eastPeak.doLine)
        XCTAssertFalse(eastPeak.doLine.lowercased().contains("bite card"), eastPeak.doLine)

        let eastTree = Inspect.read(
            tags: ["natural": "tree", "name": "Treaty Oak"],
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(eastTree.fieldRoute.first, Inspect.treeUseEastCard)
        XCTAssertFalse(eastTree.fieldRoute.contains(Inspect.treeUseTXCard))
        let eastTreeDo = eastTree.doLine.lowercased()
        XCTAssertTrue(eastTreeDo.contains("loblolly") || eastTreeDo.contains("live oak"), eastTree.doLine)
        XCTAssertTrue(eastTreeDo.contains("deadfall"), eastTree.doLine)
        XCTAssertFalse(eastTreeDo.contains("mesquite"), eastTree.doLine)
        XCTAssertFalse(eastTreeDo.contains("hog"), eastTree.doLine)
        XCTAssertFalse(eastTreeDo.contains("javelina"), eastTree.doLine)
        XCTAssertFalse(eastTreeDo.contains("cottonmouth"), eastTree.doLine)
        XCTAssertFalse(eastTreeDo.contains("bite card"), eastTree.doLine)

        let glass = Inspect.read(
            tags: ["landuse": "greenhouse_horticulture", "name": "Vickery Wholesale Greenhouse"],
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(glass.klass, "Glasshouse")
        XCTAssertEqual(glass.title, "Vickery Wholesale Greenhouse")
        XCTAssertEqual(glass.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(glass.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(glass.fieldRoute.contains(Inspect.plantUseCard), "a glasshouse is not woodland tree-use")
        XCTAssertFalse(glass.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertFalse(glass.fieldRoute.contains(Inspect.mammalEastCard))
        XCTAssertFalse(glass.fieldRoute.contains(Inspect.gameEastCard))
        XCTAssertTrue(glass.why.contains("glasshouses"), glass.why)
        XCTAssertTrue(glass.doLine.lowercased().contains("oleander"), glass.doLine)
        XCTAssertTrue(glass.doLine.lowercased().contains("not food"), glass.doLine)
        XCTAssertTrue(glass.doLine.lowercased().contains("brush off"), glass.doLine)
        XCTAssertFalse(glass.doLine.lowercased().contains("datura"), glass.doLine)
        XCTAssertFalse(glass.doLine.lowercased().contains("live oak"), glass.doLine)
        XCTAssertFalse(glass.why.lowercased().contains("edible"), glass.why)
        XCTAssertFalse(glass.doLine.lowercased().contains("edible"), glass.doLine)
        XCTAssertFalse(glass.doLine.lowercased().contains("javelina"), glass.doLine)
        XCTAssertFalse(glass.doLine.lowercased().contains("lives here"), glass.doLine)
        XCTAssertEqual(InspectField.label(for: glass.fieldRoute[0]), "FIELD · PLANT")

        let bothTexasChapters: Set<String> = [
            Inspect.plantTXCard, Inspect.treeUseTXCard, Inspect.treeUseEastCard,
            Inspect.cactusTXCard, Inspect.mammalTXCard, Inspect.mammalEastCard,
            Inspect.gameTXCard, Inspect.gameEastCard, Inspect.snakeTXCard,
            Inspect.snakeEastCard, Inspect.plantUseCard, Inspect.biteCard,
            Inspect.shelterCard, Inspect.fungiCard, Inspect.gameCard,
            Inspect.plantCard, Inspect.heatCard,
        ]
        let eastPresent = InspectField.presentRoute(eastWood.fieldRoute, in: bothTexasChapters)
        XCTAssertEqual(eastPresent.first, Inspect.treeUseEastCard)
        XCTAssertFalse(eastPresent.contains(Inspect.treeUseTXCard))
        XCTAssertFalse(eastPresent.contains(Inspect.mammalTXCard))
    }

    func testAVisionGuessOpensTheKindOfFieldCardsThatKindUses() {
        // A still is a guess, not a pin. UNKNOWN and no model do not invent a
        // card. A javelina still opens the mammal trail, not the woodland dump.
        XCTAssertEqual(InspectField.fieldRoute(forVision: "no-model", state: "TX"), [])
        XCTAssertEqual(InspectField.fieldRoute(forVision: "unknown", state: "TX"), [])

        XCTAssertEqual(
            InspectField.fieldRoute(forVision: "kind:fungi", state: "TX"),
            [Inspect.fungiCard]
        )
        XCTAssertEqual(
            InspectField.fieldRoute(forVision: "kind:snake", state: "TX"),
            [Inspect.snakeTXCard, Inspect.biteCard]
        )
        XCTAssertEqual(
            InspectField.fieldRoute(forVision: "kind:snake", state: "NM"),
            [Inspect.snakeNMCard, Inspect.biteCard]
        )

        let javelina = InspectField.fieldRoute(forVision: "tx-javelina", state: "TX")
        XCTAssertEqual(javelina.first, Inspect.mammalTXCard)
        XCTAssertTrue(javelina.contains(Inspect.biteCard), "a mammal still includes bite treatment")
        XCTAssertTrue(javelina.contains(Inspect.gameTXCard))
        XCTAssertTrue(javelina.contains(Inspect.gameCard))
        XCTAssertEqual(InspectField.label(for: javelina[0]), "FIELD · ANIMAL")
        XCTAssertEqual(
            InspectField.bookLine(for: javelina),
            "ANIMAL · BITE · FOOD"
        )
        XCTAssertFalse(javelina.contains(Inspect.plantTXCard), "a mammal still is not woodland")

        let oak = InspectField.fieldRoute(forVision: "tx-live-oak", state: "TX")
        XCTAssertEqual(oak.first, Inspect.treeUseTXCard)
        XCTAssertEqual(InspectField.label(for: oak[0]), "FIELD · PLANT")

        let pear = InspectField.fieldRoute(forVision: "tx-prickly-pear", state: "TX")
        XCTAssertEqual(pear, [Inspect.cactusTXCard])
        XCTAssertFalse(pear.contains(Inspect.plantTXCard), "a cactus still is not oleander")
        XCTAssertEqual(InspectField.label(for: pear[0]), "FIELD · PLANT")

        let bear = InspectField.fieldRoute(forVision: "nm-black-bear", state: "NM")
        XCTAssertEqual(bear.first, Inspect.mammalNMCard)
        XCTAssertTrue(bear.contains(Inspect.biteCard), "a bear still includes bite treatment")
        XCTAssertEqual(InspectField.label(for: bear[0]), "FIELD · ANIMAL")

        let yucca = InspectField.fieldRoute(forVision: "kind:cacti_yucca", state: "NM")
        XCTAssertEqual(yucca, [Inspect.cactusNMCard])
        XCTAssertFalse(yucca.contains(Inspect.plantNMCard), "a yucca still is not datura")

        XCTAssertEqual(InspectField.label(for: Inspect.treeUseEastCard), "FIELD · PLANT")
        XCTAssertEqual(InspectField.label(for: Inspect.mammalEastCard), "FIELD · ANIMAL")
        XCTAssertEqual(InspectField.label(for: Inspect.gameEastCard), "FIELD · FOOD")
        XCTAssertEqual(InspectField.label(for: Inspect.snakeEastCard), "FIELD · BITE")

        XCTAssertEqual(
            InspectField.fieldRoute(forVision: "kind:snake", state: "TX", pack: "tx-east"),
            [Inspect.snakeEastCard, Inspect.biteCard]
        )
        let mammalKindEast = InspectField.fieldRoute(
            forVision: "kind:mammal",
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(mammalKindEast.first, Inspect.mammalEastCard)
        XCTAssertTrue(mammalKindEast.contains(Inspect.biteCard), "an east mammal still includes bite treatment")
        XCTAssertTrue(mammalKindEast.contains(Inspect.gameEastCard))
        XCTAssertFalse(mammalKindEast.contains(Inspect.mammalTXCard))

        let oakEast = InspectField.fieldRoute(
            forVision: "tx-live-oak",
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(oakEast.first, Inspect.treeUseEastCard)

        // Species wins: you photographed a javelina, even in East Texas.
        let javelinaEast = InspectField.fieldRoute(
            forVision: "tx-javelina",
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(javelinaEast.first, Inspect.mammalTXCard)
        XCTAssertFalse(javelinaEast.contains(Inspect.mammalEastCard))

        let mesquiteEast = InspectField.fieldRoute(
            forVision: "tx-mesquite",
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(mesquiteEast.first, Inspect.treeUseTXCard)

        let copperheadWest = InspectField.fieldRoute(
            forVision: "tx-copperhead",
            state: "TX",
            pack: "tx-west"
        )
        XCTAssertEqual(copperheadWest.first, Inspect.snakeEastCard)

        let diamondbackEast = InspectField.fieldRoute(
            forVision: "tx-western-diamondback",
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(diamondbackEast.first, Inspect.snakeTXCard)

        let hogWest = InspectField.fieldRoute(
            forVision: "tx-feral-hog",
            state: "TX",
            pack: "tx-west"
        )
        XCTAssertEqual(hogWest.first, Inspect.mammalEastCard)
        XCTAssertTrue(hogWest.contains(Inspect.biteCard), "a hog still includes bite treatment")
        XCTAssertFalse(hogWest.contains(Inspect.mammalTXCard))

        let pineWest = InspectField.fieldRoute(
            forVision: "tx-loblolly-pine",
            state: "TX",
            pack: "tx-west"
        )
        XCTAssertEqual(pineWest.first, Inspect.treeUseEastCard)
        XCTAssertFalse(pineWest.contains(Inspect.treeUseTXCard))
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
                Inspect.treeUseTXCard, Inspect.plantTXCard,
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

    func testTheHoldBookNamesTheProceduresThisPackShips() {
        // The button has to name the first card the loaded book actually has.
        // Texas has no ice-on-rock card, so a Franklin peak is ANIMAL then
        // BITE then COLD, not a COLD button that opens javelina. One
        // procedure is not a book.
        let texas: Set<String> = [
            Inspect.plantTXCard, Inspect.treeUseTXCard, Inspect.cactusTXCard,
            Inspect.mammalTXCard, Inspect.gameTXCard, Inspect.plantUseCard,
            Inspect.biteCard, Inspect.shelterCard, Inspect.fungiCard,
            Inspect.gameCard, Inspect.plantCard, Inspect.coldCard,
            Inspect.heatCard, Inspect.snakeTXCard,
        ]
        let wood = InspectField.presentRoute(
            Inspect.read(tags: ["natural": "wood"]).fieldRoute,
            in: texas
        )
        XCTAssertEqual(
            InspectField.bookLine(for: wood),
            "PLANT · ANIMAL · FOOD · BITE · SHELTER · FUNGI"
        )
        XCTAssertEqual(InspectField.label(for: wood[0]), "FIELD · PLANT")

        let wildlife = InspectField.presentRoute(
            Inspect.read(
                tags: [
                    "leisure": "nature_reserve",
                    "name": "Marquez Wildlife Management Area",
                ],
                pack: "tx-west"
            ).fieldRoute,
            in: texas
        )
        XCTAssertEqual(InspectField.label(for: wildlife[0]), "FIELD · ANIMAL")
        XCTAssertEqual(
            InspectField.bookLine(for: wildlife),
            "ANIMAL · BITE · FOOD · PLANT"
        )
        XCTAssertNotEqual(
            InspectField.bookLine(for: wildlife),
            InspectField.bookLine(for: wood),
            "range is not picnic woodland"
        )

        let east: Set<String> = [
            Inspect.plantTXCard, Inspect.treeUseEastCard, Inspect.cactusTXCard,
            Inspect.mammalEastCard, Inspect.gameEastCard, Inspect.plantUseCard,
            Inspect.biteCard, Inspect.shelterCard, Inspect.fungiCard,
            Inspect.gameCard, Inspect.plantCard, Inspect.coldCard,
            Inspect.heatCard, Inspect.snakeEastCard,
        ]
        let eastWildlife = InspectField.presentRoute(
            Inspect.read(
                tags: [
                    "leisure": "nature_reserve",
                    "name": "Colorado River Park Wildlife Sanctuary",
                ],
                pack: "tx-east"
            ).fieldRoute,
            in: east
        )
        XCTAssertEqual(InspectField.label(for: eastWildlife[0]), "FIELD · ANIMAL")
        XCTAssertEqual(
            InspectField.bookLine(for: eastWildlife),
            "ANIMAL · BITE · FOOD · PLANT"
        )

        let nmWildlifeBook: Set<String> = [
            Inspect.mammalNMCard, Inspect.snakeNMCard, Inspect.gameNMCard,
            Inspect.treeUseNMCard, Inspect.plantNMCard, Inspect.biteCard,
            Inspect.plantUseCard, Inspect.gameCard, Inspect.plantCard,
            Inspect.shelterCard, Inspect.fungiCard,
        ]
        let nmWildlife = InspectField.presentRoute(
            Inspect.read(
                tags: [
                    "leisure": "nature_reserve",
                    "name": "Marquez Wildlife Management Area",
                ],
                pack: "nm"
            ).fieldRoute,
            in: nmWildlifeBook
        )
        XCTAssertEqual(InspectField.label(for: nmWildlife[0]), "FIELD · ANIMAL")
        XCTAssertEqual(
            InspectField.bookLine(for: nmWildlife),
            "ANIMAL · BITE · FOOD · PLANT"
        )
        XCTAssertNotEqual(
            InspectField.bookLine(for: nmWildlife),
            InspectField.bookLine(
                for: InspectField.presentRoute(
                    Inspect.read(tags: ["natural": "wood"], pack: "nm").fieldRoute,
                    in: nmWildlifeBook
                )
            ),
            "range is not picnic woodland"
        )

        let scrub = InspectField.presentRoute(
            Inspect.read(tags: ["natural": "scrub"]).fieldRoute,
            in: texas
        )
        XCTAssertEqual(
            InspectField.bookLine(for: scrub),
            "BITE · ANIMAL · PLANT · FOOD · HEAT"
        )

        let peak = Inspect.read(tags: ["natural": "peak", "name": "North Franklin"]).fieldRoute
        let txPeak = InspectField.presentRoute(peak, in: texas)
        XCTAssertEqual(InspectField.label(for: txPeak[0]), "FIELD · ANIMAL")
        XCTAssertEqual(InspectField.bookLine(for: txPeak), "ANIMAL · BITE · COLD")
        XCTAssertNotEqual(InspectField.label(for: peak[0]), "FIELD · ANIMAL")

        let nm: Set<String> = [
            Inspect.iceRockCard, Inspect.mammalNMCard, Inspect.biteCard, Inspect.coldCard,
        ]
        let nmPeak = InspectField.presentRoute(peak, in: nm)
        XCTAssertEqual(InspectField.label(for: nmPeak[0]), "FIELD · COLD")
        XCTAssertEqual(InspectField.bookLine(for: nmPeak), "COLD · ANIMAL · BITE")

        XCTAssertEqual(
            InspectField.bookLine(for: Inspect.read(tags: ["natural": "sinkhole"]).fieldRoute),
            "CAVE · COLD"
        )
        XCTAssertNil(InspectField.bookLine(for: Inspect.read(tags: ["natural": "spring"]).fieldRoute))
        XCTAssertFalse(Inspect.read(tags: ["natural": "wood"], state: "TX").doLine.lowercased().contains("edible"))
        XCTAssertTrue(
            Inspect.read(tags: ["natural": "wood"], state: "TX").doLine.lowercased().contains("javelina"),
            Inspect.read(tags: ["natural": "wood"], state: "TX").doLine
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

        // Named bosque tagged forest is cottonwoods, not a silver sheet.
        // A named street through it still wins.
        XCTAssertEqual(
            Inspect.pick([
                ["landuse": "forest", "name": "Rio Grande Bosque"],
                ["highway": "residential", "name": "Bosque Road"],
            ])["highway"],
            "residential"
        )
        XCTAssertEqual(
            Inspect.pick([["landuse": "forest", "name": "Rio Grande Bosque"], ["highway": "track"]])["name"],
            "Rio Grande Bosque"
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
        // A spring still outranks a cave. Finding a source is what holding
        // is for. A drain in the thumb box is runoff, not a source — the
        // silver circle is the hole.
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "sinkhole"],
                ["natural": "spring"],
            ])["natural"],
            "spring"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "sinkhole"],
                ["waterway": "drain", "class": "drain"],
            ])["natural"],
            "sinkhole"
        )
        // A stream 28 m off Aztec Cave is still a channel. Rank 1 mouth
        // beats rank 2 water. Franklin Mountains overlay does not swallow it.
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "cave_entrance", "name": "Aztec Cave"],
                ["waterway": "stream"],
                [
                    "leisure": "nature_reserve",
                    "boundary": "protected_area",
                    "name": "Franklin Mountains State Park",
                ],
            ])["natural"],
            "cave_entrance"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "cave_entrance", "name": "Embudo Cave"],
                ["leisure": "park", "name": "Embudo Hills Park"],
            ])["natural"],
            "cave_entrance"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "cave_entrance", "name": "Bear Cave"],
                ["waterway": "stream", "name": "Rio En Medio"],
            ])["natural"],
            "cave_entrance"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "cave_entrance", "name": "Cueva la Ventana"],
                ["highway": "path", "name": "Cueva del Apache - La Ventana"],
            ])["natural"],
            "cave_entrance"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "cave_entrance", "name": "Pepper Rock Cave"],
                ["leisure": "park", "name": "Pepper Rock Park"],
                ["highway": "residential", "name": "Chatham Wood Drive"],
            ])["natural"],
            "cave_entrance"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "cave_entrance", "name": "Airmen's Cave"],
                ["waterway": "stream", "name": "Barton Creek"],
            ])["natural"],
            "cave_entrance"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "cave_entrance", "name": "Painted Cave"],
                ["leisure": "nature_reserve", "name": "Bandelier National Monument"],
                ["highway": "footway", "name": "Lower Capulin Trail"],
            ])["natural"],
            "cave_entrance"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "cave_entrance", "name": "Geronimo"],
                [
                    "leisure": "nature_reserve",
                    "boundary": "protected_area",
                    "name": "Organ Mountains-Desert Peaks National Monument",
                ],
                ["leisure": "nature_reserve", "name": "Robledo Mountains Wilderness"],
            ])["natural"],
            "cave_entrance"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "cave_entrance", "name": "Tree House Cave"],
                ["highway": "residential", "name": "Andrew Cove"],
                ["waterway": "river"],
            ])["natural"],
            "cave_entrance"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "cave_entrance", "name": "Hideaway"],
                ["leisure": "nature_reserve", "name": "Westside Preserve"],
                ["highway": "residential", "name": "Nelson Ranch Loop"],
            ])["natural"],
            "cave_entrance"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "cave_entrance", "name": "Buttercup Wind"],
                ["highway": "residential", "name": "Shea Drive"],
                ["highway": "residential", "name": "Lauren Trail"],
                ["leisure": "park", "name": "Godzilla Preserve"],
            ])["natural"],
            "cave_entrance"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "tree", "name": "Prosopis velutina / Velvet Mesquite"],
                ["highway": "residential", "name": "Landry Avenue Northwest"],
            ])["natural"],
            "tree"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "tree", "name": "Argus"],
                ["highway": "residential", "name": "Arthur Stiles Road"],
                ["landuse": "residential", "name": "Johnston Terrace"],
            ])["natural"],
            "tree"
        )
        XCTAssertEqual(
            Inspect.pick([
                ["natural": "tree", "name": "Kim Bird Gebert Memorial Tree"],
                ["highway": "residential", "name": "Silent Harbor Loop"],
                ["leisure": "park", "name": "Lake Pflugerville Park"],
            ])["natural"],
            "tree"
        )
    }

    func testAWildlifeSanctuaryBeatsWoodlandAndANamedStreet() {
        let wood: [String: String] = [
            "natural": "wood",
            "name": "Colorado River Park Wildlife Sanctuary",
            "class": "woodland",
        ]
        let sanctuary: [String: String] = [
            "leisure": "nature_reserve",
            "name": "Colorado River Park Wildlife Sanctuary",
        ]
        XCTAssertEqual(Inspect.pick([wood, sanctuary])["leisure"], "nature_reserve")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([wood, sanctuary]), pack: "tx-east").klass,
            "Wildlife range"
        )

        let road: [String: String] = ["highway": "residential", "name": "Grove Boulevard"]
        XCTAssertEqual(Inspect.pick([wood, sanctuary, road])["leisure"], "nature_reserve")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([wood, sanctuary, road]), pack: "tx-east").klass,
            "Wildlife range"
        )

        let dahlstrom: [String: String] = [
            "leisure": "nature_reserve",
            "name": "Gay Ruby Dahlstrom Nature Preserve",
        ]
        let dahlstromRoad: [String: String] = [
            "highway": "residential",
            "name": "Dahlstrom Road",
        ]
        XCTAssertEqual(Inspect.pick([dahlstrom, dahlstromRoad])["leisure"], "nature_reserve")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([dahlstrom, dahlstromRoad]), pack: "tx-east").klass,
            "Wildlife range"
        )

        let hawk: [String: String] = [
            "leisure": "park",
            "name": "Hawk Watch Open Space",
        ]
        let wilderness: [String: String] = [
            "leisure": "nature_reserve",
            "boundary": "protected_area",
            "name": "Sandia Mountain Wilderness",
        ]
        XCTAssertEqual(Inspect.pick([hawk, wilderness])["name"], "Hawk Watch Open Space")
        XCTAssertEqual(Inspect.pick([wilderness, hawk])["name"], "Hawk Watch Open Space")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([hawk, wilderness]), pack: "nm").klass,
            "Wildlife range"
        )
        XCTAssertNotEqual(
            Inspect.read(tags: Inspect.pick([hawk, wilderness]), pack: "nm").klass,
            "Open reserve"
        )

        let history: [String: String] = [
            "leisure": "nature_reserve",
            "name": "Sandia Mountain Natural History Center",
        ]
        XCTAssertEqual(
            Inspect.pick([history, wilderness])["name"],
            "Sandia Mountain Natural History Center"
        )
        XCTAssertEqual(
            Inspect.pick([wilderness, history])["name"],
            "Sandia Mountain Natural History Center"
        )
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([history, wilderness]), pack: "nm").klass,
            "Wildlife range"
        )

        let charlieSheet: [String: String] = [
            "leisure": "nature_reserve",
            "name": "Charlie Wakeem/Richard Teschner Nature Preserve of Resler Canyon",
        ]
        let cadizStreet: [String: String] = [
            "highway": "residential",
            "name": "Cadiz Street",
        ]
        XCTAssertEqual(Inspect.pick([charlieSheet, cadizStreet])["leisure"], "nature_reserve")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([charlieSheet, cadizStreet]), pack: "tx-west").klass,
            "Wildlife range"
        )

        let blunnSheet: [String: String] = [
            "leisure": "nature_reserve",
            "name": "Blunn Creek Nature Preserve",
        ]
        let oltorfStreet: [String: String] = [
            "highway": "secondary",
            "name": "East Oltorf Street",
        ]
        XCTAssertEqual(Inspect.pick([blunnSheet, oltorfStreet])["leisure"], "nature_reserve")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([blunnSheet, oltorfStreet]), pack: "tx-east").klass,
            "Wildlife range"
        )

        let sanAndresSheet: [String: String] = [
            "leisure": "nature_reserve",
            "name": "San Andres National Wildlife Refuge",
        ]
        let missileRoad: [String: String] = [
            "highway": "residential",
            "name": "White Sands Missile Range S Route 287",
        ]
        XCTAssertEqual(Inspect.pick([sanAndresSheet, missileRoad])["leisure"], "nature_reserve")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([sanAndresSheet, missileRoad]), pack: "tx-west").klass,
            "Wildlife range"
        )

        let sevilletaSheet: [String: String] = [
            "leisure": "nature_reserve",
            "name": "Sevilleta National Wildlife Refuge",
        ]
        let oldHighway: [String: String] = [
            "highway": "unclassified",
            "name": "Old Highway 85",
        ]
        XCTAssertEqual(Inspect.pick([sevilletaSheet, oldHighway])["leisure"], "nature_reserve")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([sevilletaSheet, oldHighway]), pack: "nm").klass,
            "Wildlife range"
        )
    }

    func testAnOpenReserveBeatsWoodlandAndANamedStreet() {
        let wood: [String: String] = [
            "natural": "wood",
            "name": "Alamo Mountain Area of Critical Environmental Concern",
            "class": "woodland",
        ]
        let reserve: [String: String] = [
            "leisure": "nature_reserve",
            "boundary": "protected_area",
            "name": "Alamo Mountain Area of Critical Environmental Concern",
        ]
        XCTAssertEqual(Inspect.pick([wood, reserve])["leisure"], "nature_reserve")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([wood, reserve]), pack: "tx-west").klass,
            "Open reserve"
        )

        let road: [String: String] = ["highway": "track", "name": "Alamo Mountain Road"]
        XCTAssertEqual(Inspect.pick([wood, reserve, road])["boundary"], "protected_area")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([wood, reserve, road]), pack: "tx-west").klass,
            "Open reserve"
        )

        let hueco: [String: String] = [
            "leisure": "park",
            "boundary": "protected_area",
            "name": "Hueco Tanks State Park and Historic Site",
        ]
        let huecoRoad: [String: String] = [
            "highway": "tertiary",
            "name": "Hueco Tanks Road",
        ]
        XCTAssertEqual(Inspect.pick([hueco, huecoRoad])["leisure"], "park")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([hueco, huecoRoad]), pack: "tx-west").klass,
            "Open reserve"
        )
        XCTAssertNotEqual(
            Inspect.read(tags: Inspect.pick([hueco, huecoRoad]), pack: "tx-west").klass,
            "Park"
        )

        let sunPeak: [String: String] = [
            "natural": "peak",
            "name": "Sun Mountain",
        ]
        let sunSlope: [String: String] = [
            "boundary": "protected_area",
            "name": "Sun Mountain",
        ]
        XCTAssertEqual(Inspect.pick([sunPeak, sunSlope])["natural"], "peak")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([sunPeak, sunSlope]), pack: "nm").klass,
            "Peak"
        )
        XCTAssertEqual(
            Inspect.read(tags: sunSlope, state: "NM", pack: "nm").klass,
            "Open reserve"
        )
        let sunRoad: [String: String] = [
            "highway": "residential",
            "name": "Sun Mountain Road",
        ]
        XCTAssertEqual(Inspect.pick([sunSlope, sunRoad])["boundary"], "protected_area")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([sunSlope, sunRoad]), pack: "nm").klass,
            "Open reserve"
        )
    }

    func testAnEastPrairiePreserveBeatsScrubFillAndANamedStreet() {
        let scrub: [String: String] = [
            "natural": "scrub",
            "name": "Decker Tallgrass Prairie Preserve",
            "class": "desert",
        ]
        let reserve: [String: String] = [
            "leisure": "nature_reserve",
            "name": "Decker Tallgrass Prairie Preserve",
        ]
        XCTAssertEqual(Inspect.pick([scrub, reserve])["leisure"], "nature_reserve")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([scrub, reserve]), pack: "tx-east").klass,
            "Open reserve"
        )
        XCTAssertNotEqual(
            Inspect.read(tags: Inspect.pick([scrub, reserve]), pack: "tx-east").klass,
            "Desert scrub"
        )

        let road: [String: String] = [
            "highway": "residential",
            "name": "Decker Lake Road",
        ]
        XCTAssertEqual(Inspect.pick([scrub, reserve, road])["leisure"], "nature_reserve")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([scrub, reserve, road]), pack: "tx-east").klass,
            "Open reserve"
        )
    }

    func testAGlasshouseBeatsFarmFillAndANamedStreet() {
        let farm: [String: String] = [
            "landuse": "farmland",
            "name": "Manor fields",
            "class": "farm",
        ]
        let glass: [String: String] = [
            "landuse": "greenhouse_horticulture",
            "name": "Vickery Wholesale Greenhouse",
        ]
        XCTAssertEqual(Inspect.pick([farm, glass])["landuse"], "greenhouse_horticulture")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([farm, glass]), pack: "tx-east").klass,
            "Glasshouse"
        )

        let unnamed: [String: String] = ["landuse": "greenhouse_horticulture"]
        XCTAssertEqual(Inspect.pick([farm, unnamed])["landuse"], "greenhouse_horticulture")

        let road: [String: String] = ["highway": "residential", "name": "Johnny Morris Road"]
        XCTAssertEqual(Inspect.pick([farm, glass, road])["landuse"], "greenhouse_horticulture")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([farm, glass, road]), pack: "tx-east").klass,
            "Glasshouse"
        )

        let daffan: [String: String] = ["highway": "tertiary", "name": "Daffan Lane"]
        XCTAssertEqual(Inspect.pick([farm, glass, daffan])["landuse"], "greenhouse_horticulture")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([farm, glass, daffan]), pack: "tx-east").klass,
            "Glasshouse"
        )
    }

    func testABotanicGardenIsWorkedGroundNotAMeal() {
        let garden = Inspect.read(
            tags: [
                "leisure": "park",
                "name": "Albuquerque BioPark Botanic Garden",
            ],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(garden.klass, "Botanic garden")
        XCTAssertEqual(garden.title, "Albuquerque BioPark Botanic Garden")
        XCTAssertEqual(garden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertTrue(garden.fieldRoute.contains(Inspect.plantNMCard))
        XCTAssertFalse(garden.fieldRoute.contains(Inspect.treeUseNMCard))
        XCTAssertFalse(garden.fieldRoute.contains(Inspect.plantUseCard), "a botanic garden is not woodland tree-use")
        XCTAssertFalse(garden.fieldRoute.contains(Inspect.cactusNMCard))
        XCTAssertFalse(garden.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertFalse(garden.fieldRoute.contains(Inspect.gameNMCard))
        XCTAssertTrue(garden.doLine.lowercased().contains("datura"), garden.doLine)
        XCTAssertTrue(garden.doLine.lowercased().contains("not food"), garden.doLine)
        XCTAssertTrue(garden.doLine.lowercased().contains("brush off"), garden.doLine)
        XCTAssertFalse(garden.doLine.lowercased().contains("oleander"), garden.doLine)
        XCTAssertFalse(garden.doLine.lowercased().contains("cholla"), garden.doLine)
        XCTAssertFalse(garden.doLine.lowercased().contains("live oak"), garden.doLine)
        XCTAssertFalse(garden.doLine.lowercased().contains("edible"), garden.doLine)
        XCTAssertFalse(garden.doLine.lowercased().contains("lives here"), garden.doLine)
        XCTAssertFalse(garden.why.lowercased().contains("edible"), garden.why)
        XCTAssertEqual(InspectField.label(for: garden.fieldRoute[0]), "FIELD · PLANT")
        let nmBook: Set<String> = [
            Inspect.plantNMCard, Inspect.treeUseNMCard, Inspect.mammalNMCard,
            Inspect.plantUseCard, Inspect.plantCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(garden.fieldRoute, in: nmBook).first,
            Inspect.plantNMCard
        )

        let conservatory = Inspect.read(
            tags: [
                "boundary": "protected_area",
                "name": "Chihuahuan Desert Conservatory",
            ],
            pack: "tx-west"
        )
        XCTAssertEqual(conservatory.klass, "Cactus garden")
        XCTAssertEqual(conservatory.fieldRoute.first, Inspect.cactusTXCard)
        XCTAssertEqual(conservatory.fieldRoute.last, Inspect.plantCard)
        XCTAssertFalse(conservatory.fieldRoute.contains(Inspect.plantTXCard), "a desert conservatory is not oleander")
        XCTAssertFalse(conservatory.fieldRoute.contains(Inspect.plantUseCard), "a desert conservatory is not woodland tree-use")
        XCTAssertFalse(conservatory.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertFalse(conservatory.fieldRoute.contains(Inspect.mammalTXCard))
        XCTAssertTrue(conservatory.doLine.lowercased().contains("prickly pear"), conservatory.doLine)
        XCTAssertTrue(conservatory.doLine.lowercased().contains("spines"), conservatory.doLine)
        XCTAssertTrue(conservatory.doLine.lowercased().contains("glochids"), conservatory.doLine)
        XCTAssertFalse(conservatory.doLine.lowercased().contains("oleander"), conservatory.doLine)

        let apartments = Inspect.read(
            tags: ["landuse": "residential", "name": "Conservatory At North Austin"],
            pack: "tx-east"
        )
        XCTAssertEqual(apartments.klass, "Built-up ground")
        XCTAssertFalse(apartments.doLine.lowercased().contains("not food"), apartments.doLine)

        let arboretum = Inspect.read(
            tags: ["landuse": "residential", "name": "Madison at the Arboretum"],
            pack: "tx-east"
        )
        XCTAssertEqual(arboretum.klass, "Built-up ground")

        let cactusGarden = Inspect.read(
            tags: ["leisure": "park", "name": "Three Crosses Cactus Garden"],
            pack: "tx-west"
        )
        XCTAssertEqual(cactusGarden.klass, "Cactus garden")
        XCTAssertEqual(cactusGarden.fieldRoute.first, Inspect.cactusTXCard)
        XCTAssertEqual(cactusGarden.fieldRoute.last, Inspect.plantCard)
        XCTAssertFalse(cactusGarden.fieldRoute.contains(Inspect.plantTXCard), "a cactus garden is not oleander")
        XCTAssertFalse(cactusGarden.fieldRoute.contains(Inspect.plantUseCard), "a cactus garden is not woodland tree-use")
        XCTAssertFalse(cactusGarden.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertEqual(InspectField.label(for: cactusGarden.fieldRoute[0]), "FIELD · PLANT")
        XCTAssertTrue(cactusGarden.doLine.lowercased().contains("spines"), cactusGarden.doLine)
        XCTAssertTrue(cactusGarden.doLine.lowercased().contains("prickly pear"), cactusGarden.doLine)
        XCTAssertTrue(cactusGarden.doLine.lowercased().contains("glochids"), cactusGarden.doLine)
        XCTAssertTrue(cactusGarden.doLine.lowercased().contains("give it room"), cactusGarden.doLine)
        XCTAssertTrue(cactusGarden.doLine.lowercased().contains("not a meal"), cactusGarden.doLine)
        XCTAssertFalse(cactusGarden.doLine.lowercased().contains("edible"), cactusGarden.doLine)
        XCTAssertFalse(cactusGarden.why.lowercased().contains("edible"), cactusGarden.why)

        let nmCactusGarden = Inspect.read(
            tags: ["leisure": "park", "name": "Three Crosses Cactus Garden"],
            pack: "nm"
        )
        XCTAssertEqual(nmCactusGarden.klass, "Cactus garden")
        XCTAssertTrue(nmCactusGarden.fieldRoute.contains(Inspect.cactusNMCard))
        XCTAssertFalse(nmCactusGarden.fieldRoute.contains(Inspect.plantNMCard), "a cactus garden is not datura")
        let nmCactusBook: Set<String> = [
            Inspect.cactusNMCard, Inspect.plantNMCard, Inspect.plantCard, Inspect.plantUseCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(nmCactusGarden.fieldRoute, in: nmCactusBook).first,
            Inspect.cactusNMCard
        )
        XCTAssertTrue(nmCactusGarden.doLine.lowercased().contains("cholla"), nmCactusGarden.doLine)
        XCTAssertTrue(nmCactusGarden.doLine.lowercased().contains("glochids"), nmCactusGarden.doLine)
        XCTAssertTrue(nmCactusGarden.doLine.lowercased().contains("give it room"), nmCactusGarden.doLine)
        XCTAssertFalse(nmCactusGarden.doLine.lowercased().contains("prickly pear"), nmCactusGarden.doLine)

        let cactusPark = Inspect.read(
            tags: ["leisure": "park", "name": "Cactus Point Park"],
            pack: "tx-west"
        )
        XCTAssertEqual(cactusPark.klass, "Park")
        XCTAssertEqual(cactusPark.fieldRoute.first, Inspect.treeUseTXCard)

        let sted = Inspect.read(
            tags: ["leisure": "park", "natural": "scrub", "name": "St. Edwards Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(sted.klass, "Park", "a city park tagged as scrub fill is kept ground")
        XCTAssertNotEqual(sted.klass, "Desert scrub")
        XCTAssertEqual(sted.fieldRoute.first, Inspect.treeUseEastCard)
        XCTAssertFalse(
            sted.fieldRoute.contains(Inspect.snakeEastCard),
            "a city park is not cottonmouth country"
        )
        XCTAssertTrue(sted.doLine.lowercased().contains("hog"), sted.doLine)
        XCTAssertTrue(sted.doLine.lowercased().contains("give it the road"), sted.doLine)
        XCTAssertFalse(sted.doLine.lowercased().contains("cottonmouth"), sted.doLine)
        XCTAssertFalse(sted.doLine.lowercased().contains("edible"), sted.doLine)

        let rio = Inspect.read(
            tags: [
                "leisure": "park",
                "natural": "wetland",
                "name": "Rio Bosque Wetlands Park",
            ],
            pack: "tx-west"
        )
        XCTAssertEqual(rio.klass, "Bosque or wetland", "a named bosque tagged as a park is still bosque")
        XCTAssertNotEqual(rio.klass, "Park")
        XCTAssertTrue(rio.doLine.lowercased().contains("cottonwood"), rio.doLine)
        XCTAssertFalse(rio.doLine.lowercased().contains("edible"), rio.doLine)

        let valle = Inspect.read(
            tags: ["leisure": "park", "name": "Valle del Bosque Park"],
            pack: "nm"
        )
        XCTAssertEqual(valle.klass, "Park")
        XCTAssertNotEqual(valle.klass, "Bosque or wetland")

        let andalucia = Inspect.read(
            tags: ["leisure": "park", "name": "Bosque de Andalucía"],
            pack: "tx-west"
        )
        XCTAssertEqual(andalucia.klass, "Park")

        let encantado = Inspect.read(
            tags: ["landuse": "residential", "name": "Bosque Encantado"],
            pack: "nm"
        )
        XCTAssertEqual(encantado.klass, "Built-up ground")
        XCTAssertNotEqual(encantado.klass, "Bosque or wetland")

        let desertGarden = Inspect.read(
            tags: ["leisure": "park", "name": "Desert Garden Park"],
            pack: "tx-west"
        )
        XCTAssertEqual(desertGarden.klass, "Cactus garden")
        XCTAssertEqual(desertGarden.fieldRoute.first, Inspect.cactusTXCard)
        XCTAssertFalse(desertGarden.fieldRoute.contains(Inspect.plantTXCard), "a desert garden is not oleander")
        XCTAssertTrue(desertGarden.doLine.lowercased().contains("prickly pear"), desertGarden.doLine)
        XCTAssertFalse(desertGarden.fieldRoute.contains(Inspect.treeUseTXCard))

        let desertGardens = Inspect.read(
            tags: ["leisure": "garden", "name": "Chihuahuan Desert Gardens"],
            pack: "tx-west"
        )
        XCTAssertEqual(desertGardens.klass, "Cactus garden")
        XCTAssertNotEqual(desertGardens.klass, "Botanic garden")
        XCTAssertEqual(desertGardens.fieldRoute.first, Inspect.cactusTXCard)
        XCTAssertFalse(desertGardens.fieldRoute.contains(Inspect.plantTXCard), "desert gardens are not oleander")
        XCTAssertTrue(desertGardens.doLine.lowercased().contains("prickly pear"), desertGardens.doLine)
        XCTAssertFalse(desertGardens.doLine.lowercased().contains("edible"), desertGardens.doLine)

        let rose = Inspect.read(
            tags: ["leisure": "park", "name": "Rose Garden"],
            pack: "tx-west"
        )
        XCTAssertEqual(rose.klass, "Botanic garden")
        XCTAssertEqual(rose.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(rose.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertFalse(rose.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertFalse(rose.fieldRoute.contains(Inspect.plantUseCard), "a rose garden is not woodland tree-use")

        let community = Inspect.read(
            tags: [
                "leisure": "park",
                "amenity": "community garden",
                "name": "Crestview Commons Neighborhood Park",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(community.klass, "Botanic garden")
        XCTAssertEqual(community.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(community.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertFalse(community.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(community.fieldRoute.contains(Inspect.plantUseCard), "a community garden is not woodland tree-use")

        let wildflower = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Wildflower Preserve",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(wildflower.klass, "Botanic garden")
        XCTAssertNotEqual(wildflower.klass, "Open reserve")
        XCTAssertNotEqual(wildflower.klass, "Wildlife range")
        XCTAssertEqual(wildflower.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(wildflower.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(wildflower.fieldRoute.contains(Inspect.mammalEastCard))
        XCTAssertFalse(wildflower.doLine.lowercased().contains("edible"), wildflower.doLine)

        let wildflowerPark = Inspect.read(
            tags: ["leisure": "park", "name": "Wildflower Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(wildflowerPark.klass, "Park")
        XCTAssertNotEqual(wildflowerPark.klass, "Botanic garden")

        let lush = Inspect.read(
            tags: ["leisure": "park", "name": "Lush n Lean Garden"],
            pack: "tx-west"
        )
        XCTAssertEqual(lush.klass, "Botanic garden")
        XCTAssertEqual(lush.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(lush.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertFalse(lush.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertFalse(lush.doLine.lowercased().contains("edible"), lush.doLine)

        let orchard = Inspect.read(
            tags: ["leisure": "park", "name": "Orchard Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(orchard.klass, "Botanic garden")
        XCTAssertNotEqual(orchard.klass, "Park")
        XCTAssertEqual(orchard.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(orchard.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(orchard.doLine.lowercased().contains("edible"), orchard.doLine)

        let orchardRoad = Inspect.read(
            tags: ["highway": "residential", "name": "Orchard Gardens Road Southwest"],
            pack: "nm"
        )
        XCTAssertEqual(orchardRoad.klass, "Road")
        XCTAssertNotEqual(orchardRoad.klass, "Botanic garden")

        let fiesta = Inspect.read(
            tags: ["leisure": "park", "name": "Fiesta Gardens"],
            pack: "tx-east"
        )
        XCTAssertEqual(fiesta.klass, "Park")
        XCTAssertNotEqual(fiesta.klass, "Botanic garden")

        let cornell = Inspect.read(
            tags: ["leisure": "park", "name": "Harvey Cornell Rose Park"],
            pack: "nm"
        )
        XCTAssertEqual(cornell.klass, "Botanic garden")
        XCTAssertEqual(cornell.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertTrue(cornell.fieldRoute.contains(Inspect.plantNMCard))
        XCTAssertFalse(cornell.fieldRoute.contains(Inspect.treeUseNMCard))
        XCTAssertFalse(cornell.doLine.lowercased().contains("edible"), cornell.doLine)

        let roseParkRoad = Inspect.read(
            tags: ["highway": "residential", "name": "Rose Park Avenue Northwest"],
            pack: "nm"
        )
        XCTAssertEqual(roseParkRoad.klass, "Road")
        XCTAssertNotEqual(roseParkRoad.klass, "Botanic garden")

        let wildrose = Inspect.read(
            tags: ["leisure": "park", "name": "Wildrose Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(wildrose.klass, "Park")
        XCTAssertNotEqual(wildrose.klass, "Botanic garden")

        let beer = Inspect.read(
            tags: ["leisure": "park", "name": "Moontower Saloon Beer Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(beer.klass, "Park")
        XCTAssertEqual(beer.fieldRoute.first, Inspect.treeUseEastCard)

        let ladybird = Inspect.read(
            tags: [
                "leisure": "garden",
                "name": "Ladybird Johnson Wildflower Center",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(ladybird.klass, "Botanic garden")
        XCTAssertNotEqual(ladybird.klass, "Park")
        XCTAssertNotEqual(ladybird.klass, "Open reserve")
        XCTAssertEqual(ladybird.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(ladybird.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(ladybird.fieldRoute.contains(Inspect.cactusTXCard), "a wildflower center is not spines")
        XCTAssertFalse(ladybird.fieldRoute.contains(Inspect.plantUseCard), "a wildflower center is not woodland tree-use")
        XCTAssertFalse(ladybird.doLine.lowercased().contains("edible"), ladybird.doLine)

        let zilker = Inspect.read(
            tags: ["leisure": "garden", "name": "Zilker Botanical Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(zilker.klass, "Botanic garden")
        XCTAssertEqual(zilker.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(zilker.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertFalse(zilker.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(zilker.doLine.lowercased().contains("edible"), zilker.doLine)

        let santaFeGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "Santa Fe Botanical Garden"],
            pack: "nm"
        )
        XCTAssertEqual(santaFeGarden.klass, "Botanic garden")
        XCTAssertEqual(santaFeGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertTrue(santaFeGarden.fieldRoute.contains(Inspect.plantNMCard))
        XCTAssertFalse(santaFeGarden.fieldRoute.contains(Inspect.treeUseNMCard))
        XCTAssertFalse(santaFeGarden.doLine.lowercased().contains("edible"), santaFeGarden.doLine)

        let japaneese = Inspect.read(
            tags: ["leisure": "garden", "name": "Japaneese Garden"],
            pack: "tx-west"
        )
        XCTAssertEqual(japaneese.klass, "Botanic garden")
        XCTAssertEqual(japaneese.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(japaneese.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertFalse(japaneese.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertFalse(japaneese.doLine.lowercased().contains("edible"), japaneese.doLine)

        let japaneseSpelled = Inspect.read(
            tags: ["leisure": "garden", "name": "Japanese Garden"],
            pack: "tx-west"
        )
        XCTAssertEqual(japaneseSpelled.klass, "Botanic garden")

        let capitolFlower = Inspect.read(
            tags: [
                "leisure": "garden",
                "name": "Lady Bird Johnson Texas Capitol Flower Gardens",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(capitolFlower.klass, "Botanic garden")
        XCTAssertEqual(capitolFlower.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(capitolFlower.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(capitolFlower.doLine.lowercased().contains("edible"), capitolFlower.doLine)

        let japaneseMemorial = Inspect.read(
            tags: ["leisure": "garden", "name": "Japanese Memorial Garden"],
            pack: "nm"
        )
        XCTAssertEqual(japaneseMemorial.klass, "Botanic garden")
        XCTAssertTrue(japaneseMemorial.fieldRoute.contains(Inspect.plantNMCard))
        XCTAssertFalse(japaneseMemorial.fieldRoute.contains(Inspect.treeUseNMCard))

        let demonstration = Inspect.read(
            tags: ["leisure": "garden", "name": "Water Wise Demonstration Garden"],
            pack: "nm"
        )
        XCTAssertEqual(demonstration.klass, "Botanic garden")
        XCTAssertTrue(demonstration.fieldRoute.contains(Inspect.plantNMCard))

        let prestonFoster = Inspect.read(
            tags: ["leisure": "garden", "name": "Preston Foster Native Garden"],
            pack: "tx-west"
        )
        XCTAssertEqual(prestonFoster.klass, "Botanic garden")
        XCTAssertEqual(prestonFoster.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(prestonFoster.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertFalse(prestonFoster.doLine.lowercased().contains("edible"), prestonFoster.doLine)

        let xeriscapeGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "Xeriscape Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(xeriscapeGarden.klass, "Botanic garden")
        XCTAssertEqual(xeriscapeGarden.fieldRoute.first, Inspect.plantTXCard)

        let xeriscapePark = Inspect.read(
            tags: ["leisure": "park", "name": "Xeriscape Park"],
            pack: "nm"
        )
        XCTAssertEqual(xeriscapePark.klass, "Park")
        XCTAssertNotEqual(xeriscapePark.klass, "Botanic garden")

        let teaching = Inspect.read(
            tags: ["leisure": "garden", "name": "SFC Teaching Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(teaching.klass, "Botanic garden")
        XCTAssertFalse(teaching.fieldRoute.contains(Inspect.treeUseEastCard))

        let fincher = Inspect.read(
            tags: ["leisure": "garden", "name": "E.R. Fincher III Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(fincher.klass, "Botanic garden")
        XCTAssertEqual(fincher.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(fincher.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(fincher.doLine.lowercased().contains("edible"), fincher.doLine)

        let brazosBluff = Inspect.read(
            tags: ["leisure": "garden", "name": "Brazos Bluff"],
            pack: "tx-east"
        )
        XCTAssertEqual(brazosBluff.klass, "Botanic garden")
        XCTAssertFalse(brazosBluff.fieldRoute.contains(Inspect.treeUseEastCard))

        let brazosStreet = Inspect.read(
            tags: ["highway": "residential", "name": "Brazos Street"],
            pack: "tx-east"
        )
        XCTAssertEqual(brazosStreet.klass, "Road")
        XCTAssertNotEqual(brazosStreet.klass, "Botanic garden")

        let explorers = Inspect.read(
            tags: ["leisure": "garden", "name": "Explorers Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(explorers.klass, "Botanic garden")
        XCTAssertFalse(explorers.doLine.lowercased().contains("edible"), explorers.doLine)

        let haozous = Inspect.read(
            tags: ["leisure": "garden", "name": "The Haozous Garden"],
            pack: "nm"
        )
        XCTAssertEqual(haozous.klass, "Botanic garden")
        XCTAssertTrue(haozous.fieldRoute.contains(Inspect.plantNMCard))
        XCTAssertFalse(haozous.fieldRoute.contains(Inspect.treeUseNMCard))
        XCTAssertFalse(haozous.doLine.lowercased().contains("edible"), haozous.doLine)

        let haozousRoad = Inspect.read(
            tags: ["highway": "residential", "name": "Haozous Road"],
            pack: "nm"
        )
        XCTAssertNotEqual(haozousRoad.klass, "Botanic garden")

        let esteGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "Este Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(esteGarden.klass, "Botanic garden")
        XCTAssertEqual(esteGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(esteGarden.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(esteGarden.doLine.lowercased().contains("edible"), esteGarden.doLine)

        let celesteDrive = Inspect.read(
            tags: ["highway": "residential", "name": "Celeste Drive"],
            pack: "tx-west"
        )
        XCTAssertEqual(celesteDrive.klass, "Road")
        XCTAssertNotEqual(celesteDrive.klass, "Botanic garden")

        let fourthStreetGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "4th Street Garden"],
            pack: "tx-west"
        )
        XCTAssertEqual(fourthStreetGarden.klass, "Botanic garden")
        XCTAssertEqual(fourthStreetGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(fourthStreetGarden.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertFalse(fourthStreetGarden.doLine.lowercased().contains("edible"), fourthStreetGarden.doLine)

        let westFourth = Inspect.read(
            tags: ["highway": "residential", "name": "West 4th Avenue"],
            pack: "tx-west"
        )
        XCTAssertEqual(westFourth.klass, "Road")
        XCTAssertNotEqual(westFourth.klass, "Botanic garden")

        let alamogordoGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "Alamogordo Community Garden"],
            pack: "tx-west"
        )
        XCTAssertEqual(alamogordoGarden.klass, "Botanic garden")
        XCTAssertEqual(alamogordoGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(alamogordoGarden.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertFalse(alamogordoGarden.doLine.lowercased().contains("edible"), alamogordoGarden.doLine)

        let alamogordoStreet = Inspect.read(
            tags: ["highway": "residential", "name": "Alamogordo"],
            pack: "tx-west"
        )
        XCTAssertEqual(alamogordoStreet.klass, "Road")
        XCTAssertNotEqual(alamogordoStreet.klass, "Botanic garden")

        let albuquerqueRose = Inspect.read(
            tags: ["leisure": "garden", "name": "Albuquerque Rose Garden"],
            pack: "nm"
        )
        XCTAssertEqual(albuquerqueRose.klass, "Botanic garden")
        XCTAssertEqual(albuquerqueRose.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertTrue(albuquerqueRose.fieldRoute.contains(Inspect.plantNMCard))
        XCTAssertFalse(albuquerqueRose.fieldRoute.contains(Inspect.treeUseNMCard))
        XCTAssertFalse(albuquerqueRose.doLine.lowercased().contains("edible"), albuquerqueRose.doLine)

        let laMesaGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "La Mesa Neighborhood Community Garden"],
            pack: "nm"
        )
        XCTAssertEqual(laMesaGarden.klass, "Botanic garden")
        XCTAssertNotEqual(laMesaGarden.klass, "Open reserve")
        XCTAssertEqual(laMesaGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertTrue(laMesaGarden.fieldRoute.contains(Inspect.plantNMCard))
        XCTAssertFalse(laMesaGarden.fieldRoute.contains(Inspect.treeUseNMCard))
        XCTAssertFalse(laMesaGarden.doLine.lowercased().contains("edible"), laMesaGarden.doLine)

        let internationalGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "International District Community Garden"],
            pack: "nm"
        )
        XCTAssertEqual(internationalGarden.klass, "Botanic garden")
        XCTAssertEqual(internationalGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertTrue(internationalGarden.fieldRoute.contains(Inspect.plantNMCard))
        XCTAssertFalse(internationalGarden.fieldRoute.contains(Inspect.treeUseNMCard))
        XCTAssertFalse(internationalGarden.doLine.lowercased().contains("edible"), internationalGarden.doLine)

        let laMesaCourt = Inspect.read(
            tags: ["highway": "residential", "name": "La Mesa Court Northwest"],
            pack: "nm"
        )
        XCTAssertEqual(laMesaCourt.klass, "Road")
        XCTAssertNotEqual(laMesaCourt.klass, "Botanic garden")

        let paseoMesa = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "boundary": "protected_area",
                "name": "Paseo de la Mesa Open Space",
            ],
            pack: "nm"
        )
        XCTAssertEqual(paseoMesa.klass, "Open reserve")
        XCTAssertNotEqual(paseoMesa.klass, "Botanic garden")

        let memorialRose = Inspect.read(
            tags: ["leisure": "garden", "name": "Memorial Rose Garden"],
            pack: "nm"
        )
        XCTAssertEqual(memorialRose.klass, "Botanic garden")
        XCTAssertNotEqual(memorialRose.klass, "Park")

        let bastropGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "Bastrop Community Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(bastropGarden.klass, "Botanic garden")
        XCTAssertNotEqual(bastropGarden.klass, "Park")
        XCTAssertEqual(bastropGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(bastropGarden.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(bastropGarden.doLine.lowercased().contains("edible"), bastropGarden.doLine)

        let bastropStreet = Inspect.read(
            tags: ["highway": "residential", "name": "Bastrop Street"],
            pack: "tx-east"
        )
        XCTAssertEqual(bastropStreet.klass, "Road")
        XCTAssertNotEqual(bastropStreet.klass, "Botanic garden")

        let bastropPark = Inspect.read(
            tags: ["leisure": "park", "name": "Bastrop State Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(bastropPark.klass, "Park")
        XCTAssertNotEqual(bastropPark.klass, "Botanic garden")

        let fortDessauGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "Fort Dessau Community Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(fortDessauGarden.klass, "Botanic garden")
        XCTAssertNotEqual(fortDessauGarden.klass, "Park")
        XCTAssertEqual(fortDessauGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(fortDessauGarden.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(fortDessauGarden.doLine.lowercased().contains("edible"), fortDessauGarden.doLine)

        let fortDessauRoad = Inspect.read(
            tags: ["highway": "residential", "name": "Fort Dessau Road"],
            pack: "tx-east"
        )
        XCTAssertEqual(fortDessauRoad.klass, "Road")
        XCTAssertNotEqual(fortDessauRoad.klass, "Botanic garden")

        let fortDessauAmenity = Inspect.read(
            tags: ["leisure": "park", "name": "Fort Dessau Amenity Center"],
            pack: "tx-east"
        )
        XCTAssertEqual(fortDessauAmenity.klass, "Park")
        XCTAssertNotEqual(fortDessauAmenity.klass, "Botanic garden")

        let windsorGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "Windsor Park Community Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(windsorGarden.klass, "Botanic garden")
        XCTAssertNotEqual(windsorGarden.klass, "Park")
        XCTAssertEqual(windsorGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(windsorGarden.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(windsorGarden.doLine.lowercased().contains("edible"), windsorGarden.doLine)

        let windsorPlace = Inspect.read(
            tags: ["place": "neighbourhood", "name": "Windsor Park"],
            pack: "tx-east"
        )
        XCTAssertNotEqual(windsorPlace.klass, "Botanic garden")

        let lamplightGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "Lamplight Community Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(lamplightGarden.klass, "Botanic garden")
        XCTAssertEqual(lamplightGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(lamplightGarden.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(lamplightGarden.doLine.lowercased().contains("edible"), lamplightGarden.doLine)

        let lamplightAve = Inspect.read(
            tags: ["highway": "tertiary", "name": "Lamplight Village Avenue"],
            pack: "tx-east"
        )
        XCTAssertEqual(lamplightAve.klass, "Road")
        XCTAssertNotEqual(lamplightAve.klass, "Botanic garden")

        let juanNavarroGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "Juan Navarro High School Community Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(juanNavarroGarden.klass, "Botanic garden")
        XCTAssertEqual(juanNavarroGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(juanNavarroGarden.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(juanNavarroGarden.doLine.lowercased().contains("edible"), juanNavarroGarden.doLine)

        let unityParkGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "Unity Park Community Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(unityParkGarden.klass, "Botanic garden")
        XCTAssertEqual(unityParkGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(unityParkGarden.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(unityParkGarden.doLine.lowercased().contains("edible"), unityParkGarden.doLine)

        let coloradoGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "Colorado Community Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(coloradoGarden.klass, "Botanic garden")
        XCTAssertNotEqual(coloradoGarden.klass, "Wildlife range")
        XCTAssertEqual(coloradoGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(coloradoGarden.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(coloradoGarden.doLine.lowercased().contains("edible"), coloradoGarden.doLine)

        let coloradoSanctuary = Inspect.read(
            tags: [
                "leisure": "nature_reserve",
                "name": "Colorado River Park Wildlife Sanctuary",
            ],
            pack: "tx-east"
        )
        XCTAssertEqual(coloradoSanctuary.klass, "Wildlife range")
        XCTAssertNotEqual(coloradoSanctuary.klass, "Botanic garden")

        let alamoGarden = Inspect.read(
            tags: ["leisure": "garden", "name": "Alamo Community Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(alamoGarden.klass, "Botanic garden")
        XCTAssertNotEqual(alamoGarden.klass, "Park")
        XCTAssertEqual(alamoGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(alamoGarden.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(alamoGarden.doLine.lowercased().contains("edible"), alamoGarden.doLine)

        let alamoStreet = Inspect.read(
            tags: ["highway": "residential", "name": "Alamo Street"],
            pack: "tx-east"
        )
        XCTAssertEqual(alamoStreet.klass, "Road")
        XCTAssertNotEqual(alamoStreet.klass, "Botanic garden")

        let alamoPocket = Inspect.read(
            tags: ["leisure": "park", "name": "Alamo Pocket Park"],
            pack: "tx-east"
        )
        XCTAssertEqual(alamoPocket.klass, "Park")
        XCTAssertNotEqual(alamoPocket.klass, "Botanic garden")

        let barelasGarden = Inspect.read(
            tags: ["leisure": "park", "name": "Barelas Community Garden"],
            state: "NM",
            pack: "nm"
        )
        XCTAssertEqual(barelasGarden.klass, "Botanic garden")
        XCTAssertNotEqual(barelasGarden.klass, "Park")
        XCTAssertEqual(barelasGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertTrue(barelasGarden.fieldRoute.contains(Inspect.plantNMCard))
        XCTAssertFalse(barelasGarden.fieldRoute.contains(Inspect.treeUseNMCard))
        XCTAssertFalse(barelasGarden.doLine.lowercased().contains("edible"), barelasGarden.doLine)

        let fourthStreetSW = Inspect.read(
            tags: ["highway": "tertiary", "name": "4th Street Southwest"],
            pack: "nm"
        )
        XCTAssertEqual(fourthStreetSW.klass, "Road")
        XCTAssertNotEqual(fourthStreetSW.klass, "Botanic garden")

        let prisma = Inspect.read(
            tags: [
                "leisure": "garden",
                "name": "Colonia Prisma Community Garden",
            ],
            pack: "nm"
        )
        XCTAssertEqual(prisma.klass, "Botanic garden")
        XCTAssertNotEqual(prisma.klass, "Park")
        XCTAssertEqual(prisma.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertTrue(prisma.fieldRoute.contains(Inspect.plantNMCard))
        XCTAssertFalse(prisma.fieldRoute.contains(Inspect.treeUseNMCard))
        XCTAssertFalse(prisma.doLine.lowercased().contains("edible"), prisma.doLine)

        let caminoRojo = Inspect.read(
            tags: ["highway": "residential", "name": "Camino Rojo"],
            pack: "nm"
        )
        XCTAssertEqual(caminoRojo.klass, "Road")
        XCTAssertNotEqual(caminoRojo.klass, "Botanic garden")

        let vueltaColorada = Inspect.read(
            tags: ["highway": "residential", "name": "Vuelta Colorada"],
            pack: "nm"
        )
        XCTAssertEqual(vueltaColorada.klass, "Road")
        XCTAssertNotEqual(vueltaColorada.klass, "Botanic garden")

        let winrock = Inspect.read(
            tags: ["leisure": "garden", "name": "Winrock Garden"],
            pack: "nm"
        )
        XCTAssertNotEqual(winrock.klass, "Botanic garden")

        let nestedNative = Inspect.read(
            tags: ["leisure": "garden", "name": "Native American Garden"],
            pack: "nm"
        )
        XCTAssertNotEqual(nestedNative.klass, "Botanic garden")

        let experimental = Inspect.read(
            tags: ["leisure": "garden", "name": "Experimental Gardens"],
            pack: "tx-east"
        )
        XCTAssertNotEqual(experimental.klass, "Botanic garden")

        let astronautMemorial = Inspect.read(
            tags: ["leisure": "garden", "name": "Astronaut Memorial Garden"],
            pack: "tx-west"
        )
        XCTAssertNotEqual(astronautMemorial.klass, "Botanic garden")

        let memorial = Inspect.read(
            tags: ["leisure": "garden", "name": "Memorial Garden"],
            pack: "tx-east"
        )
        XCTAssertNotEqual(memorial.klass, "Botanic garden")

        let wildflowerPath = Inspect.read(
            tags: [
                "highway": "footway",
                "name": "Ladybird Johnson Wildflower Center Foot Paths",
            ],
            pack: "tx-east"
        )
        XCTAssertNotEqual(wildflowerPath.klass, "Botanic garden")
        XCTAssertEqual(wildflowerPath.klass, "Trail")
    }

    func testABotanicGardenBeatsParkFillAndANamedStreet() {
        let park: [String: String] = [
            "class": "park",
            "name": "Albuquerque BioPark Botanic Garden",
        ]
        let botanic: [String: String] = [
            "leisure": "park",
            "name": "Albuquerque BioPark Botanic Garden",
        ]
        XCTAssertEqual(Inspect.pick([park, botanic])["leisure"], "park")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([park, botanic]), pack: "nm").klass,
            "Botanic garden"
        )

        let road: [String: String] = ["highway": "residential", "name": "Central Avenue"]
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([park, botanic, road]), pack: "nm").klass,
            "Botanic garden"
        )
        XCTAssertNil(Inspect.pick([park, botanic, road])["highway"])

        let rose: [String: String] = [
            "leisure": "garden",
            "name": "Albuquerque Rose Garden",
        ]
        let utah: [String: String] = [
            "highway": "residential",
            "name": "Utah Street Northeast",
        ]
        XCTAssertEqual(Inspect.pick([rose, utah])["leisure"], "garden")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([rose, utah]), pack: "nm").klass,
            "Botanic garden"
        )

        let prismaSheet: [String: String] = [
            "leisure": "garden",
            "name": "Colonia Prisma Community Garden",
        ]
        let caminoRojoStreet: [String: String] = [
            "highway": "residential",
            "name": "Camino Rojo",
        ]
        XCTAssertEqual(Inspect.pick([prismaSheet, caminoRojoStreet])["leisure"], "garden")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([prismaSheet, caminoRojoStreet]), pack: "nm").klass,
            "Botanic garden"
        )
    }

    func testACavePreserveBeatsParkFillAndANamedStreet() {
        let park: [String: String] = [
            "class": "park",
            "name": "Discovery Well Cave Preserve",
        ]
        let preserve: [String: String] = [
            "leisure": "park",
            "name": "Discovery Well Cave Preserve",
        ]
        XCTAssertEqual(Inspect.pick([park, preserve])["leisure"], "park")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([park, preserve]), pack: "tx-east").klass,
            "Cave or hole"
        )

        let road: [String: String] = ["highway": "residential", "name": "Great Oaks Drive"]
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([park, preserve, road]), pack: "tx-east").klass,
            "Cave or hole"
        )
        XCTAssertNil(Inspect.pick([park, preserve, road])["highway"])

        let russell: [String: String] = [
            "leisure": "nature_reserve",
            "name": "William H. Russell Karst Preserve",
        ]
        let karstLane: [String: String] = [
            "highway": "residential",
            "name": "Karst Lane",
        ]
        XCTAssertEqual(Inspect.pick([russell, karstLane])["leisure"], "nature_reserve")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([russell, karstLane]), pack: "tx-east").klass,
            "Cave or hole"
        )
    }

    func testANamedSinkBeatsBosqueFillAndANamedStreet() {
        // Blowing Sink is tagged wetland, so the land tiles paint bosque.
        // Phrase `blowing sink` on the overlay still has to name the hole.
        let bosque: [String: String] = [
            "natural": "wetland",
            "class": "bosque",
        ]
        let sink: [String: String] = [
            "name": "Blowing Sink",
        ]
        XCTAssertEqual(Inspect.pick([bosque, sink])["name"], "Blowing Sink")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([bosque, sink]), pack: "tx-east").klass,
            "Cave or hole"
        )
        XCTAssertNotEqual(
            Inspect.read(tags: Inspect.pick([bosque, sink]), pack: "tx-east").klass,
            "Bosque or wetland"
        )

        let road: [String: String] = [
            "highway": "residential",
            "name": "Blowing Sink Road",
        ]
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([bosque, sink, road]), pack: "tx-east").klass,
            "Cave or hole"
        )
        XCTAssertNil(Inspect.pick([bosque, sink, road])["highway"])
    }

    func testADesertConservatoryBeatsParkFillAndANamedStreet() {
        // Overlay kind is botanic. Phrase `desert conservatory` still has
        // to open cactus, not oleander, and still beat the street beside it.
        let park: [String: String] = [
            "class": "park",
        ]
        let sheet: [String: String] = [
            "boundary": "protected_area",
            "name": "Chihuahuan Desert Conservatory",
        ]
        XCTAssertEqual(Inspect.pick([park, sheet])["name"], "Chihuahuan Desert Conservatory")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([park, sheet]), pack: "tx-west").klass,
            "Cactus garden"
        )
        XCTAssertNotEqual(
            Inspect.read(tags: Inspect.pick([park, sheet]), pack: "tx-west").klass,
            "Botanic garden"
        )

        let road: [String: String] = [
            "highway": "tertiary",
            "name": "Smith Street",
        ]
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([park, sheet, road]), pack: "tx-west").klass,
            "Cactus garden"
        )
        XCTAssertNil(Inspect.pick([park, sheet, road])["highway"])
    }

    func testARoseGardenBeatsParkFillAndANamedStreet() {
        let park: [String: String] = [
            "class": "park",
        ]
        let sheet: [String: String] = [
            "leisure": "park",
            "name": "Rose Garden",
        ]
        XCTAssertEqual(Inspect.pick([park, sheet])["name"], "Rose Garden")
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([park, sheet]), pack: "tx-west").klass,
            "Botanic garden"
        )
        XCTAssertNotEqual(
            Inspect.read(tags: Inspect.pick([park, sheet]), pack: "tx-west").klass,
            "Cactus garden"
        )

        let road: [String: String] = [
            "highway": "footway",
            "name": "Garden Walk",
        ]
        XCTAssertEqual(
            Inspect.read(tags: Inspect.pick([park, sheet, road]), pack: "tx-west").klass,
            "Botanic garden"
        )
        XCTAssertNil(Inspect.pick([park, sheet, road])["highway"])
    }

    func testANamedStreetBeatsGenericParkFill() {
        let park: [String: String] = [
            "leisure": "park",
            "name": "Bee Cave Central Park",
        ]
        let road: [String: String] = ["highway": "residential", "name": "Bee Cave Road"]
        XCTAssertEqual(Inspect.pick([park, road])["highway"], "residential")
        XCTAssertEqual(Inspect.read(tags: Inspect.pick([park, road]), pack: "tx-east").klass, "Road")
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
        XCTAssertTrue(Inspect.overlayLayerIDs.contains(RouteLine.casingLayerID))
        XCTAssertTrue(Inspect.overlayLayerIDs.contains(RouteLine.coreLayerID))
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
        ["natural": "grass"],
        ["boundary": "protected_area"],
        ["boundary": "national_park"],
        ["leisure": "nature_reserve"],
        ["leisure": "park"],
        ["landuse": "forest"],
        ["landuse": "farmland"],
        ["landuse": "orchard"],
        ["landuse": "meadow"],
        ["landuse": "vineyard"],
        ["landuse": "greenhouse_horticulture"],
        ["landuse": "recreation_ground"],
        ["landuse": "grass"],
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
