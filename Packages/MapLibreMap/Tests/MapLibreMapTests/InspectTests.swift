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
            Inspect.iceRockCard, Inspect.mammalNMCard, Inspect.mammalTXCard, Inspect.coldCard,
        ])
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
        XCTAssertFalse(coyote.fieldRoute.contains(Inspect.caveCard))
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
        let doLine = marquez.doLine.lowercased()
        XCTAssertTrue(doLine.contains("bear") || doLine.contains("elk"), marquez.doLine)
        XCTAssertTrue(doLine.contains("range") || doLine.contains("not a pin"), marquez.doLine)
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
        XCTAssertFalse(refuge.doLine.lowercased().contains("javelina"), refuge.doLine)
        XCTAssertFalse(refuge.doLine.lowercased().contains("lives here"), refuge.doLine)

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
        XCTAssertTrue(txWoodDo.contains("not a meal"), txWood.doLine)
        XCTAssertFalse(txWoodDo.contains("edible"), txWood.doLine)
        XCTAssertFalse(txWoodDo.contains("lives here"), txWood.doLine)

        let nmWood = Inspect.read(tags: ["natural": "wood"], state: "NM")
        let nmWoodDo = nmWood.doLine.lowercased()
        XCTAssertTrue(
            nmWoodDo.contains("cottonwood") || nmWoodDo.contains("piñon") || nmWoodDo.contains("juniper"),
            nmWood.doLine
        )
        XCTAssertTrue(nmWoodDo.contains("bear") || nmWoodDo.contains("elk"), nmWood.doLine)

        let txScrub = Inspect.read(tags: ["natural": "scrub"], state: "TX")
        let txScrubDo = txScrub.doLine.lowercased()
        XCTAssertTrue(txScrubDo.contains("javelina") || txScrubDo.contains("diamondback"), txScrub.doLine)
        XCTAssertFalse(txScrubDo.contains("edible"), txScrub.doLine)
        XCTAssertFalse(txScrubDo.contains("lives here"), txScrub.doLine)
        XCTAssertFalse(txScrubDo.contains("standing here"), txScrub.doLine)
        XCTAssertTrue(txScrubDo.contains("yucca") || txScrubDo.contains("prickly"), txScrub.doLine)

        let nmPeak = Inspect.read(tags: ["natural": "peak", "name": "Wheeler"], state: "NM")
        XCTAssertTrue(nmPeak.doLine.lowercased().contains("bear"), nmPeak.doLine)
        XCTAssertEqual(InspectField.label(for: Inspect.mammalNMCard), "FIELD · ANIMAL")

        let txPeak = Inspect.read(tags: ["natural": "peak", "name": "North Franklin"], state: "TX")
        let txPeakDo = txPeak.doLine.lowercased()
        XCTAssertTrue(txPeakDo.contains("coyote") || txPeakDo.contains("deer"), txPeak.doLine)
        XCTAssertFalse(txPeakDo.contains("ice"), txPeak.doLine)
        XCTAssertFalse(txPeakDo.contains("lives here"), txPeak.doLine)

        let txRock = Inspect.read(tags: ["natural": "bare_rock"], state: "TX")
        XCTAssertFalse(txRock.doLine.lowercased().contains("ice"), txRock.doLine)
        XCTAssertTrue(
            txRock.doLine.lowercased().contains("coyote") || txRock.doLine.lowercased().contains("deer"),
            txRock.doLine
        )

        let grass = Inspect.read(tags: ["natural": "grass"])
        XCTAssertEqual(grass.klass, "Grassland")
        XCTAssertEqual(grass.fieldRoute.first, Inspect.snakeTXCard)

        let westWood = Inspect.read(tags: ["natural": "wood"], state: "TX", pack: "tx-west")
        XCTAssertTrue(westWood.doLine.lowercased().contains("javelina"), westWood.doLine)
        XCTAssertTrue(westWood.doLine.lowercased().contains("mesquite"), westWood.doLine)

        let eastWood = Inspect.read(tags: ["natural": "wood"], state: "TX", pack: "tx-east")
        let eastWoodDo = eastWood.doLine.lowercased()
        XCTAssertTrue(eastWoodDo.contains("cedar elm") || eastWoodDo.contains("live oak"), eastWood.doLine)
        XCTAssertTrue(eastWoodDo.contains("pine"), eastWood.doLine)
        XCTAssertTrue(eastWoodDo.contains("coyote") || eastWoodDo.contains("deer"), eastWood.doLine)
        XCTAssertTrue(eastWoodDo.contains("hog"), eastWood.doLine)
        XCTAssertFalse(eastWoodDo.contains("javelina"), eastWood.doLine)
        XCTAssertFalse(eastWoodDo.contains("mesquite"), eastWood.doLine)
        XCTAssertFalse(eastWoodDo.contains("edible"), eastWood.doLine)
        XCTAssertFalse(eastWoodDo.contains("lives here"), eastWood.doLine)

        let eastScrub = Inspect.read(tags: ["natural": "scrub"], state: "TX", pack: "tx-east")
        let eastScrubDo = eastScrub.doLine.lowercased()
        XCTAssertTrue(eastScrubDo.contains("cottonmouth") || eastScrubDo.contains("copperhead"), eastScrub.doLine)
        XCTAssertFalse(eastScrubDo.contains("javelina"), eastScrub.doLine)
        XCTAssertFalse(eastScrubDo.contains("lives here"), eastScrub.doLine)

        let eastWet = Inspect.read(tags: ["natural": "wetland"], state: "TX", pack: "tx-east")
        XCTAssertTrue(eastWet.doLine.lowercased().contains("cottonmouth"), eastWet.doLine)
        XCTAssertFalse(eastWet.doLine.lowercased().contains("javelina"), eastWet.doLine)

        // East Texas shares field.tx.json with the west pack. The hold still
        // walks this pack's chapter — not mesquite, not javelina.
        XCTAssertEqual(eastWood.fieldRoute.first, Inspect.treeUseEastCard)
        XCTAssertEqual(InspectField.label(for: eastWood.fieldRoute[0]), "FIELD · PLANT")
        XCTAssertTrue(eastWood.fieldRoute.contains(Inspect.mammalEastCard))
        XCTAssertTrue(eastWood.fieldRoute.contains(Inspect.gameEastCard))
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
        XCTAssertFalse(eastPeak.fieldRoute.contains(Inspect.mammalTXCard))
        XCTAssertTrue(eastPeak.doLine.lowercased().contains("hog"), eastPeak.doLine)
        XCTAssertFalse(eastPeak.doLine.lowercased().contains("javelina"), eastPeak.doLine)
        XCTAssertFalse(eastPeak.doLine.lowercased().contains("ice"), eastPeak.doLine)

        let eastTree = Inspect.read(
            tags: ["natural": "tree", "name": "Treaty Oak"],
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(eastTree.fieldRoute.first, Inspect.treeUseEastCard)
        XCTAssertFalse(eastTree.fieldRoute.contains(Inspect.treeUseTXCard))

        let glass = Inspect.read(
            tags: ["landuse": "greenhouse_horticulture", "name": "Vickery Wholesale Greenhouse"],
            state: "TX",
            pack: "tx-east"
        )
        XCTAssertEqual(glass.klass, "Glasshouse")
        XCTAssertEqual(glass.title, "Vickery Wholesale Greenhouse")
        XCTAssertEqual(glass.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(glass.fieldRoute.contains(Inspect.treeUseEastCard))
        XCTAssertFalse(glass.fieldRoute.contains(Inspect.mammalEastCard))
        XCTAssertFalse(glass.fieldRoute.contains(Inspect.gameEastCard))
        XCTAssertTrue(glass.why.contains("glasshouses"), glass.why)
        XCTAssertTrue(glass.doLine.lowercased().contains("not food"), glass.doLine)
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
        XCTAssertTrue(javelina.contains(Inspect.gameTXCard))
        XCTAssertTrue(javelina.contains(Inspect.gameCard))
        XCTAssertEqual(InspectField.label(for: javelina[0]), "FIELD · ANIMAL")
        XCTAssertFalse(javelina.contains(Inspect.plantTXCard), "a mammal still is not woodland")

        let oak = InspectField.fieldRoute(forVision: "tx-live-oak", state: "TX")
        XCTAssertEqual(oak.first, Inspect.treeUseTXCard)
        XCTAssertEqual(InspectField.label(for: oak[0]), "FIELD · PLANT")

        let pear = InspectField.fieldRoute(forVision: "tx-prickly-pear", state: "TX")
        XCTAssertEqual(pear.first, Inspect.cactusTXCard)
        XCTAssertTrue(pear.contains(Inspect.plantTXCard))

        let bear = InspectField.fieldRoute(forVision: "nm-black-bear", state: "NM")
        XCTAssertEqual(bear.first, Inspect.mammalNMCard)
        XCTAssertEqual(InspectField.label(for: bear[0]), "FIELD · ANIMAL")

        let yucca = InspectField.fieldRoute(forVision: "kind:cacti_yucca", state: "NM")
        XCTAssertEqual(yucca.first, Inspect.cactusNMCard)

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
                Inspect.treeUseTXCard, Inspect.plantTXCard, Inspect.cactusTXCard,
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
        // Texas has no ice-on-rock card, so a Franklin peak is ANIMAL then COLD,
        // not a COLD button that opens javelina. One procedure is not a book.
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
        XCTAssertEqual(InspectField.bookLine(for: txPeak), "ANIMAL · COLD")
        XCTAssertNotEqual(InspectField.label(for: peak[0]), "FIELD · ANIMAL")

        let nm: Set<String> = [
            Inspect.iceRockCard, Inspect.mammalNMCard, Inspect.coldCard,
        ]
        let nmPeak = InspectField.presentRoute(peak, in: nm)
        XCTAssertEqual(InspectField.label(for: nmPeak[0]), "FIELD · COLD")
        XCTAssertEqual(InspectField.bookLine(for: nmPeak), "COLD · ANIMAL")

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

    func testAWildlifeSanctuaryBeatsWoodlandAndLosesToANamedStreet() {
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
        XCTAssertEqual(Inspect.pick([wood, sanctuary, road])["highway"], "residential")
    }

    func testAGlasshouseBeatsFarmFillAndLosesToANamedStreet() {
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
        XCTAssertEqual(Inspect.pick([farm, glass, road])["highway"], "residential")
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
        XCTAssertFalse(garden.fieldRoute.contains(Inspect.mammalNMCard))
        XCTAssertFalse(garden.fieldRoute.contains(Inspect.gameNMCard))
        XCTAssertTrue(garden.doLine.lowercased().contains("not food"), garden.doLine)
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
        XCTAssertEqual(conservatory.klass, "Botanic garden")
        XCTAssertEqual(conservatory.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertFalse(conservatory.fieldRoute.contains(Inspect.treeUseTXCard))
        XCTAssertFalse(conservatory.fieldRoute.contains(Inspect.mammalTXCard))
        XCTAssertTrue(conservatory.doLine.lowercased().contains("not food"), conservatory.doLine)

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
        XCTAssertEqual(cactusGarden.klass, "Botanic garden")
        XCTAssertEqual(cactusGarden.fieldRoute.first, Inspect.plantTXCard)
        XCTAssertTrue(cactusGarden.fieldRoute.contains(Inspect.cactusTXCard))
        XCTAssertFalse(cactusGarden.fieldRoute.contains(Inspect.treeUseTXCard))

        let cactusPark = Inspect.read(
            tags: ["leisure": "park", "name": "Cactus Point Park"],
            pack: "tx-west"
        )
        XCTAssertEqual(cactusPark.klass, "Park")
        XCTAssertEqual(cactusPark.fieldRoute.first, Inspect.treeUseTXCard)

        let desertGarden = Inspect.read(
            tags: ["leisure": "park", "name": "Desert Garden Park"],
            pack: "tx-west"
        )
        XCTAssertEqual(desertGarden.klass, "Botanic garden")
        XCTAssertEqual(desertGarden.fieldRoute.first, Inspect.plantTXCard)

        let rose = Inspect.read(
            tags: ["leisure": "park", "name": "Rose Garden"],
            pack: "tx-west"
        )
        XCTAssertEqual(rose.klass, "Botanic garden")
        XCTAssertFalse(rose.fieldRoute.contains(Inspect.treeUseTXCard))

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
        XCTAssertFalse(community.fieldRoute.contains(Inspect.treeUseEastCard))

        let beer = Inspect.read(
            tags: ["leisure": "park", "name": "Moontower Saloon Beer Garden"],
            pack: "tx-east"
        )
        XCTAssertEqual(beer.klass, "Park")
        XCTAssertEqual(beer.fieldRoute.first, Inspect.treeUseEastCard)
    }

    func testABotanicGardenBeatsParkFillAndLosesToANamedStreet() {
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
        XCTAssertEqual(Inspect.pick([park, botanic, road])["highway"], "residential")
    }

    func testACavePreserveBeatsParkFillAndLosesToANamedStreet() {
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
        XCTAssertEqual(Inspect.pick([park, preserve, road])["highway"], "residential")
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
