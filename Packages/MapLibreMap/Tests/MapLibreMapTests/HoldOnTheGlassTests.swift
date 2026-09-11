#if canImport(UIKit)
import CoreLocation
import MapLibre
import UIKit
import XCTest

@testable import MapLibreMap

/// A hold on the shipped Texas West archive, run on a real renderer.
///
/// `InspectTests` proves the reading is right for a given bag of tags, and the
/// Python guards prove those tags are in the pack. Neither proves the thing the
/// phone does: that putting a finger on a tank in El Paso and holding still
/// puts a card on the glass. Between the tags on disk and the card there is a
/// tile archive, a style, a 44pt query and a layer skip-list, and every one of
/// them can silently answer nothing.
///
/// So these boot the style the app boots, point the camera at coordinates taken
/// straight out of the extract, and call the app's own probe — the same
/// `record(under:on:)` the long-press handler calls. The coordinates are in the
/// test because they are evidence: each one is a real record in
/// `Resources/Packs/tx-west`, `tx-east`, or `nm` `osm.geojson` /
/// `layers/ground.geojson`. Texas West has no wildlife overlay in this fetch;
/// animals as range are held on an east sanctuary and on a west peak, not
/// invented as pins on the west pack. New Mexico botanic, wildlife,
/// cave-preserve, and open-reserve sheets are held on the NM archive.
/// East also holds a named sink tagged wetland (not bosque) and a prairie
/// preserve (east vipers, not west diamondback). A west desert conservatory
/// is cactus, not oleander. A named bosque holds tree use, not a pin.
/// Picnic woodland, irrigated ground, and a rose garden are the rest of
/// the plant book on west; east names hog on woodland and cottonmouth on
/// bosque; NM names cottonwood on woodland and bosque, and elk on a peak.
@MainActor
final class HoldOnTheGlassTests: XCTestCase {
    /// `representative_point` of a `content=water` storage tank 3.8 km west of
    /// home, taken from `osm.geojson` — the same point the tiler wrote into
    /// the archive. Do not reverse-project decoded tile pixels: the Python
    /// decoder flips Y and the first coordinates were 1.7 km off, which is
    /// why CI held empty ground and said the probe found nothing.
    private static let waterTank = CLLocationCoordinate2D(latitude: 31.792096, longitude: -106.497210)

    /// A storage tank 500 m from home with no `content` at all. Most tanks
    /// out here are this one, and the card has to say so.
    private static let silentTank = CLLocationCoordinate2D(latitude: 31.775803, longitude: -106.462400)

    /// Unnamed heath on the north-west edge of the pack. Nothing else is
    /// mapped within twice the probe box. This is ordinary cover, not a blank.
    private static let emptyDesert = CLLocationCoordinate2D(latitude: 31.94284, longitude: -106.75415)

    /// `Sierra de Ciudad Juárez` — ground the record does put a name to.
    private static let namedGround = CLLocationCoordinate2D(latitude: 31.71809, longitude: -106.61330)

    /// Interior of `Three Crosses Cactus Garden` in `layers/ground.geojson`.
    /// SOLO_QA 32.332056, −106.782048 is on the sheet; this point is inside it.
    private static let cactusGarden = CLLocationCoordinate2D(latitude: 32.332036, longitude: -106.782070)

    /// Interior of Chihuahuan Desert Conservatory. Overlay kind is botanic
    /// (`conservatory`); Inspect still reads cactus (`desert conservatory`).
    /// Farther from a stream and a way than the vertex-avg SOLO_QA point.
    private static let desertConservatory = CLLocationCoordinate2D(latitude: 33.157743, longitude: -107.242346)

    /// Interior of Rio Bosque Wetlands Park. Named wetland in the extract,
    /// not an overlay sheet. Tree use and animals as range, not a pin.
    private static let westBosque = CLLocationCoordinate2D(latitude: 31.638834, longitude: -106.308840)

    /// Interior of a west farmland sheet, far from a named way or a ditch.
    /// Irrigated tree-use, not javelina country.
    private static let irrigatedField = CLLocationCoordinate2D(latitude: 31.513892, longitude: -106.593002)

    /// Interior of unnamed west woodland, far from a named way or a tank.
    /// Picnic tree-use and javelina as range, not a bosque and not a hunt.
    private static let westWoodland = CLLocationCoordinate2D(latitude: 33.100215, longitude: -105.802406)

    /// Interior of Rose Garden. TX botanic oleander, not cactus, not datura.
    private static let roseGarden = CLLocationCoordinate2D(latitude: 32.911739, longitude: -105.959273)

    /// Unnamed `landuse=greenhouse_horticulture` sheet. SOLO_QA point,
    /// verified inside the overlay polygon.
    private static let glasshouse = CLLocationCoordinate2D(latitude: 32.502967, longitude: -106.933833)

    /// Interior of Alamo Mountain ACEC in `layers/ground.geojson`.
    private static let openReserve = CLLocationCoordinate2D(latitude: 32.032331, longitude: -105.633755)

    /// Unnamed `natural=sinkhole` on the place slice. SOLO_QA 31.694905, −106.441133.
    private static let sinkhole = CLLocationCoordinate2D(latitude: 31.694905, longitude: -106.441133)

    /// Interior of Indiangrass Wildlife Sanctuary in east `layers/ground.geojson`.
    /// Scrub fill does not win. Range, not a pin.
    private static let wildlifeRange = CLLocationCoordinate2D(latitude: 30.315667, longitude: -97.591821)

    /// Interior of Beaukiss Woods. East woodland tree-use: loblolly and hog,
    /// not west javelina, not cottonmouth (that is bosque).
    private static let eastWoodland = CLLocationCoordinate2D(latitude: 30.423083, longitude: -97.227224)

    /// Interior of an unnamed east wetland. Cottonmouth on bosque, not a park.
    /// Water sits just outside the 44pt box at walking zoom.
    private static let eastBosque = CLLocationCoordinate2D(latitude: 30.194954, longitude: -97.688346)

    /// Interior of Discovery Well Cave Preserve in east `layers/ground.geojson`.
    private static let cavePreserve = CLLocationCoordinate2D(latitude: 30.490391, longitude: -97.855063)

    /// Interior of Blowing Sink in east `layers/ground.geojson`. A wetland
    /// in the extract; phrase `blowing sink`, not a cave-preserve park.
    /// Vertex-avg covers the sheet. Streams and ways sit hundreds of metres off.
    private static let namedSink = CLLocationCoordinate2D(latitude: 30.193035, longitude: -97.850443)

    /// Interior of Decker Tallgrass Prairie Preserve. East open reserve —
    /// cottonmouth and hog, not west diamondback, not picnic woodland.
    /// Vertex-avg covers the sheet, far from Decker Creek and any named way.
    private static let eastOpenReserve = CLLocationCoordinate2D(latitude: 30.294331, longitude: -97.603942)

    /// Interior of Albuquerque BioPark Botanic Garden in NM `layers/ground.geojson`.
    /// SOLO_QA 35.094694, −106.682101 sits next to a pond; water outranks the
    /// sheet. This point is on the botanic polygon, away from water and named ways.
    private static let botanicGarden = CLLocationCoordinate2D(latitude: 35.093625, longitude: -106.680958)

    /// Interior of Marquez Wildlife Management Area in NM `layers/ground.geojson`.
    /// SOLO_QA 35.327562, −107.319389 is on the sheet and far from water or a way.
    private static let nmWildlifeRange = CLLocationCoordinate2D(latitude: 35.327562, longitude: -107.319389)

    /// Interior of Pronoun Cave ACEC in NM `layers/ground.geojson`. A cave
    /// phrase, not open reserve, even though the name also says ACEC.
    private static let nmCavePreserve = CLLocationCoordinate2D(latitude: 34.750796, longitude: -107.344750)

    /// `Mount Franklin` on the west place slice. Texas West has no wildlife
    /// overlay; animals as range on this pack are this silver circle, not a pin.
    /// Farther from a named way than North Franklin Mountain.
    private static let westPeak = CLLocationCoordinate2D(latitude: 31.832051, longitude: -106.492210)

    /// Interior of Jones Canyon ACEC in NM `layers/ground.geojson`. Open
    /// reserve, not Pronoun Cave — rattler and sotol, not a hole.
    private static let nmOpenReserve = CLLocationCoordinate2D(latitude: 35.846906, longitude: -107.025703)

    /// Interior of Isleta Rectangle. Named NM forest: cottonwood and elk
    /// as range, not west javelina, not a wetland bosque.
    private static let nmWoodland = CLLocationCoordinate2D(latitude: 34.939900, longitude: -106.320316)

    /// Interior of an unnamed NM wetland. Cottonwood and mule deer, not elk
    /// (that is woodland), not cottonmouth (that is east).
    private static let nmBosque = CLLocationCoordinate2D(latitude: 34.628816, longitude: -105.915768)

    /// `La Cruz Peak` on the NM place slice. Bear and elk as range, not
    /// west javelina. Ice-on-rock is in this book, so FIELD names cold first.
    private static let nmPeak = CLLocationCoordinate2D(latitude: 34.392837, longitude: -107.420040)

    /// `Barton Hill` on the east place slice. Hog as range, not west javelina.
    private static let eastPeak = CLLocationCoordinate2D(latitude: 30.065769, longitude: -97.882228)

    // MARK: - The two holds the build is gated on

    func testHoldingAWaterTankSaysWater() throws {
        let held = try hold(at: Self.waterTank, zoom: 16)
        XCTAssertEqual(held.card?.klass, "Water tank", "a content=water tank did not read as water: \(held)")
        XCTAssertEqual(held.card?.kind, .water, "\(held)")
        XCTAssertEqual(held.card?.advice, .treat, "water still has to be treated: \(held)")
        // The record is unnamed, so the 8-point unnamed penalty lands on 74
        // and the card reads 66. A silent tank is 42. The gap is the point.
        XCTAssertGreaterThanOrEqual(
            held.card?.sure ?? 0,
            60,
            "content=water still has to outrank a silent tank: \(held)"
        )
    }

    func testHoldingEmptyDesertSaysGround() throws {
        let held = try hold(at: Self.emptyDesert, zoom: 15)
        XCTAssertNotNil(held.card, "holding empty desert put nothing on the glass")
        XCTAssertEqual(held.card?.kind, .land, "empty desert did not read as ground: \(held)")
        XCTAssertEqual(held.card?.title, "Unnamed", "the record has no name for it and the card invented one: \(held)")
        XCTAssertEqual(held.card?.klass, "Desert scrub", "ordinary cover is viper country, not a blank: \(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.snakeTXCard, "\(held)")
        XCTAssertEqual(held.card?.advice, .field, "empty ground sends you to Field: \(held)")
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("diamondback"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it room"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · BITE"
        )
        let texas: Set<String> = [
            Inspect.plantTXCard, Inspect.treeUseTXCard, Inspect.cactusTXCard,
            Inspect.mammalTXCard, Inspect.gameTXCard, Inspect.plantUseCard,
            Inspect.biteCard, Inspect.shelterCard, Inspect.fungiCard,
            Inspect.gameCard, Inspect.plantCard, Inspect.coldCard,
            Inspect.heatCard, Inspect.snakeTXCard,
        ]
        XCTAssertEqual(
            InspectField.bookLine(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: texas
            )),
            "BITE · ANIMAL · PLANT · FOOD · HEAT"
        )
    }

    // MARK: - The ones that keep it honest

    /// The failure that would matter most: a bare tank reading as water because
    /// `man_made=storage_tank` sounds like it holds some. Around El Paso only
    /// 110 of 585 storage tanks carry `content=water`.
    func testHoldingATankWithNoContentDoesNotPromiseWater() throws {
        let held = try hold(at: Self.silentTank, zoom: 16)
        XCTAssertNotNil(held.card, "holding a mapped tank put nothing on the glass")
        XCTAssertNotEqual(held.card?.klass, "Water tank", "a tank with no content was read as water: \(held)")
        XCTAssertEqual(held.card?.advice, .leave, "an unknown tank is a leave-it: \(held)")
        XCTAssertLessThan(held.card?.sure ?? 100, 60, "nobody wrote down what is in it, so do not sound sure: \(held)")
    }

    func testHoldingNamedGroundUsesTheNameTheRecordGaveIt() throws {
        let held = try hold(at: Self.namedGround, zoom: 15)
        XCTAssertNotNil(held.card, "holding the Sierra de Ciudad Juárez put nothing on the glass")
        XCTAssertEqual(held.card?.kind, .land, "\(held)")
        XCTAssertTrue(
            held.card?.title.contains("Sierra de Ciudad Juárez") ?? false,
            "the ground is named in the record and the card dropped it: \(held)"
        )
        // Painted heath, not an overlay sheet. Vipers use this cover.
        XCTAssertEqual(held.card?.klass, "Desert scrub", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.snakeTXCard, "\(held)")
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("diamondback"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it room"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("live oak"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("food card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · BITE"
        )
        let texas: Set<String> = [
            Inspect.plantTXCard, Inspect.treeUseTXCard, Inspect.cactusTXCard,
            Inspect.mammalTXCard, Inspect.gameTXCard, Inspect.plantUseCard,
            Inspect.biteCard, Inspect.shelterCard, Inspect.fungiCard,
            Inspect.gameCard, Inspect.plantCard, Inspect.coldCard,
            Inspect.heatCard, Inspect.snakeTXCard,
        ]
        XCTAssertEqual(
            InspectField.bookLine(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: texas
            )),
            "BITE · ANIMAL · PLANT · FOOD · HEAT"
        )
    }

    /// Overlay fill is one percent and walking-zoom. The hold still has to
    /// name the record and open the Field book of that sheet — cactus, not
    /// oleander; bite, not picnic woodland; cave, not bosque.
    func testHoldingACactusGardenOpensTheCactusCardNotOleander() throws {
        let held = try hold(at: Self.cactusGarden, zoom: 16)
        XCTAssertEqual(held.card?.klass, "Cactus garden", "\(held)")
        XCTAssertEqual(held.card?.title, "Three Crosses Cactus Garden", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.cactusTXCard, "\(held)")
        XCTAssertFalse(
            held.card?.fieldRoute.contains(Inspect.plantTXCard) ?? true,
            "a cactus garden opened oleander: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("prickly pear"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it room"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("glochids"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("oleander"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · PLANT"
        )
    }

    func testHoldingADesertConservatoryOpensCactusNotOleander() throws {
        let held = try hold(at: Self.desertConservatory, zoom: 16)
        XCTAssertEqual(held.card?.klass, "Cactus garden", "\(held)")
        XCTAssertNotEqual(held.card?.klass, "Botanic garden", "\(held)")
        XCTAssertEqual(held.card?.title, "Chihuahuan Desert Conservatory", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.cactusTXCard, "\(held)")
        XCTAssertFalse(
            held.card?.fieldRoute.contains(Inspect.plantTXCard) ?? true,
            "a desert conservatory opened oleander: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("prickly pear"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it room"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("glochids"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("oleander"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("live oak"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · PLANT"
        )
    }

    func testHoldingARoseGardenOpensPlantDangerNotCactus() throws {
        let held = try hold(at: Self.roseGarden, zoom: 16)
        XCTAssertEqual(held.card?.klass, "Botanic garden", "\(held)")
        XCTAssertNotEqual(held.card?.klass, "Cactus garden", "\(held)")
        XCTAssertEqual(held.card?.title, "Rose Garden", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.plantTXCard, "\(held)")
        XCTAssertFalse(
            held.card?.fieldRoute.contains(Inspect.cactusTXCard) ?? true,
            "a rose garden opened cactus: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("oleander"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("brush off"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("datura"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cholla"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("glochids"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("live oak"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · PLANT"
        )
    }

    func testHoldingANamedBosqueOpensTreeUseNotAPin() throws {
        let held = try hold(at: Self.westBosque, zoom: 16)
        XCTAssertEqual(held.card?.klass, "Bosque or wetland", "\(held)")
        XCTAssertEqual(held.card?.title, "Rio Bosque Wetlands Park", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.treeUseTXCard, "\(held)")
        XCTAssertFalse(
            held.card?.fieldRoute.contains(Inspect.cactusTXCard) ?? true,
            "a bosque opened cactus: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("south-side"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("wind break"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("deadfall"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("food card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("give it room"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · PLANT"
        )
        let texas: Set<String> = [
            Inspect.plantTXCard, Inspect.treeUseTXCard, Inspect.cactusTXCard,
            Inspect.mammalTXCard, Inspect.gameTXCard, Inspect.plantUseCard,
            Inspect.biteCard, Inspect.shelterCard, Inspect.fungiCard,
            Inspect.gameCard, Inspect.plantCard,
        ]
        XCTAssertEqual(
            InspectField.bookLine(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: texas
            )),
            "PLANT · ANIMAL · FOOD · BITE · SHELTER · FUNGI"
        )
    }

    func testHoldingIrrigatedGroundOpensTreeUseNotJavelina() throws {
        let held = try hold(at: Self.irrigatedField, zoom: 16)
        XCTAssertEqual(held.card?.klass, "Irrigated ground", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.treeUseTXCard, "\(held)")
        XCTAssertFalse(
            held.card?.fieldRoute.contains(Inspect.mammalTXCard) ?? true,
            "a field opened javelina country: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("mesquite") || doLine.contains("live oak"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("south-side"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("wind break"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("deadfall"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · PLANT"
        )
    }

    func testHoldingWestWoodlandOpensTreeUseNotAHunt() throws {
        let held = try hold(at: Self.westWoodland, zoom: 16)
        XCTAssertEqual(held.card?.klass, "Woodland", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.treeUseTXCard, "\(held)")
        XCTAssertFalse(
            held.card?.fieldRoute.contains(Inspect.snakeTXCard) ?? true,
            "picnic woodland opened diamondback: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("mesquite") || doLine.contains("live oak"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("south-side"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("wind break"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("deadfall"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("food card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("hog"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · PLANT"
        )
        let texas: Set<String> = [
            Inspect.plantTXCard, Inspect.treeUseTXCard, Inspect.cactusTXCard,
            Inspect.mammalTXCard, Inspect.gameTXCard, Inspect.plantUseCard,
            Inspect.biteCard, Inspect.shelterCard, Inspect.fungiCard,
            Inspect.gameCard, Inspect.plantCard,
        ]
        XCTAssertEqual(
            InspectField.bookLine(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: texas
            )),
            "PLANT · ANIMAL · FOOD · BITE · SHELTER · FUNGI"
        )
    }

    func testHoldingAGlasshouseOpensPlantDangerNotTreeUse() throws {
        let held = try hold(at: Self.glasshouse, zoom: 16)
        XCTAssertEqual(held.card?.klass, "Glasshouse", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.plantTXCard, "\(held)")
        XCTAssertFalse(
            held.card?.fieldRoute.contains(Inspect.treeUseTXCard) ?? true,
            "a glasshouse opened woodland tree-use: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("oleander"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("brush off"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("live oak"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · PLANT"
        )
    }

    func testHoldingAnOpenReserveOpensBiteNotPicnicWoodland() throws {
        let held = try hold(at: Self.openReserve, zoom: 16)
        XCTAssertEqual(held.card?.klass, "Open reserve", "\(held)")
        XCTAssertEqual(held.card?.title, "Alamo Mountain Area of Critical Environmental Concern", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.snakeTXCard, "\(held)")
        XCTAssertNotEqual(
            held.card?.fieldRoute.first,
            Inspect.treeUseTXCard,
            "an ACEC opened picnic woodland: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("diamondback"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it room"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("live oak"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · BITE"
        )
    }

    func testHoldingASinkholeOpensTheCaveCard() throws {
        let held = try hold(at: Self.sinkhole, zoom: 16)
        XCTAssertEqual(held.card?.klass, "Cave or hole", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.caveCard, "\(held)")
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("stay in daylight"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · CAVE"
        )
    }

    func testHoldingAWildlifeSanctuaryOpensAnimalsNotPicnicWoodland() throws {
        let held = try hold(at: Self.wildlifeRange, zoom: 16, packId: "tx-east")
        XCTAssertEqual(held.card?.klass, "Wildlife range", "\(held)")
        XCTAssertEqual(held.card?.title, "Indiangrass Wildlife Sanctuary", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.mammalEastCard, "\(held)")
        XCTAssertNotEqual(
            held.card?.fieldRoute.first,
            Inspect.treeUseEastCard,
            "a wildlife sanctuary opened picnic woodland: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("hog"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("cook through"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("food card"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · ANIMAL"
        )
        XCTAssertEqual(
            InspectField.bookLine(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: [
                    Inspect.mammalEastCard, Inspect.snakeEastCard, Inspect.gameEastCard,
                    Inspect.treeUseEastCard, Inspect.plantTXCard, Inspect.biteCard,
                    Inspect.plantUseCard, Inspect.gameCard, Inspect.plantCard,
                ]
            )),
            "ANIMAL · BITE · FOOD · PLANT"
        )
    }

    func testHoldingEastWoodlandOpensTreeUseNotCottonmouth() throws {
        let held = try hold(at: Self.eastWoodland, zoom: 16, packId: "tx-east")
        XCTAssertEqual(held.card?.klass, "Woodland", "\(held)")
        XCTAssertEqual(held.card?.title, "Beaukiss Woods", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.treeUseEastCard, "\(held)")
        XCTAssertFalse(
            held.card?.fieldRoute.contains(Inspect.snakeEastCard) ?? true,
            "picnic woodland opened cottonmouth: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("loblolly"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("hog"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("south-side"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("wind break"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("food card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · PLANT"
        )
    }

    func testHoldingAnEastBosqueNamesCottonmouthNotAPark() throws {
        let held = try hold(at: Self.eastBosque, zoom: 16, packId: "tx-east")
        XCTAssertEqual(held.card?.klass, "Bosque or wetland", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.treeUseEastCard, "\(held)")
        XCTAssertTrue(
            held.card?.fieldRoute.contains(Inspect.snakeEastCard) ?? false,
            "east bosque dropped cottonmouth treatment: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("hog"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("south-side"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("wind break"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("food card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · PLANT"
        )
    }

    func testHoldingACavePreserveOpensTheCaveCardNotBosque() throws {
        let held = try hold(at: Self.cavePreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(held.card?.klass, "Cave or hole", "\(held)")
        XCTAssertEqual(held.card?.title, "Discovery Well Cave Preserve", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.caveCard, "\(held)")
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("stay in daylight"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · CAVE"
        )
    }

    func testHoldingANamedSinkOpensTheCaveCardNotBosque() throws {
        let held = try hold(at: Self.namedSink, zoom: 16, packId: "tx-east")
        XCTAssertEqual(held.card?.klass, "Cave or hole", "\(held)")
        XCTAssertNotEqual(held.card?.klass, "Bosque or wetland", "\(held)")
        XCTAssertEqual(held.card?.title, "Blowing Sink", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.caveCard, "\(held)")
        XCTAssertTrue(
            held.card?.why.contains("named sink") ?? false,
            held.card?.why ?? ""
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("stay in daylight"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · CAVE"
        )
    }

    func testHoldingABotanicGardenOpensPlantDangerNotTreeUse() throws {
        let held = try hold(at: Self.botanicGarden, zoom: 16, packId: "nm")
        XCTAssertEqual(held.card?.klass, "Botanic garden", "\(held)")
        XCTAssertEqual(held.card?.title, "Albuquerque BioPark Botanic Garden", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.plantTXCard, "\(held)")
        XCTAssertTrue(
            held.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "a botanic garden dropped the NM plant-danger card: \(held)"
        )
        XCTAssertFalse(
            held.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? true,
            "a botanic garden opened woodland tree-use: \(held)"
        )
        XCTAssertFalse(
            held.card?.fieldRoute.contains(Inspect.cactusNMCard) ?? true,
            "a botanic garden opened cactus: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("datura"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("brush off"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("oleander"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cholla"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        let nmBook: Set<String> = [
            Inspect.plantNMCard, Inspect.treeUseNMCard, Inspect.mammalNMCard,
            Inspect.plantUseCard, Inspect.plantCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(held.card?.fieldRoute ?? [], in: nmBook).first,
            Inspect.plantNMCard
        )
        XCTAssertEqual(
            InspectField.label(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: nmBook
            ).first ?? ""),
            "FIELD · PLANT"
        )
    }

    func testHoldingAWildlifeManagementAreaOpensAnimalsNotPicnicWoodland() throws {
        let held = try hold(at: Self.nmWildlifeRange, zoom: 16, packId: "nm")
        XCTAssertEqual(held.card?.klass, "Wildlife range", "\(held)")
        XCTAssertEqual(held.card?.title, "Marquez Wildlife Management Area", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.mammalTXCard, "\(held)")
        XCTAssertTrue(
            held.card?.fieldRoute.contains(Inspect.mammalNMCard) ?? false,
            "a WMA dropped the NM mammal card: \(held)"
        )
        XCTAssertNotEqual(
            held.card?.fieldRoute.first,
            Inspect.treeUseNMCard,
            "a wildlife range opened picnic woodland: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("bear"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("elk"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("mule deer"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("rattler") || doLine.contains("diamondback"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("cook through"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("food card"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        let nmBook: Set<String> = [
            Inspect.mammalNMCard, Inspect.snakeNMCard, Inspect.gameNMCard,
            Inspect.treeUseNMCard, Inspect.plantNMCard, Inspect.biteCard,
            Inspect.plantUseCard, Inspect.gameCard, Inspect.plantCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(held.card?.fieldRoute ?? [], in: nmBook).first,
            Inspect.mammalNMCard
        )
        XCTAssertEqual(
            InspectField.label(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: nmBook
            ).first ?? ""),
            "FIELD · ANIMAL"
        )
        XCTAssertEqual(
            InspectField.bookLine(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: nmBook
            )),
            "ANIMAL · BITE · FOOD · PLANT"
        )
    }

    func testHoldingACaveACECOpensTheCaveCardNotOpenReserve() throws {
        let held = try hold(at: Self.nmCavePreserve, zoom: 16, packId: "nm")
        XCTAssertEqual(held.card?.klass, "Cave or hole", "\(held)")
        XCTAssertNotEqual(held.card?.klass, "Open reserve", "\(held)")
        XCTAssertEqual(
            held.card?.title,
            "Pronoun Cave Area of Critical Environmental Concern",
            "\(held)"
        )
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.caveCard, "\(held)")
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("stay in daylight"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("rattler"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · CAVE"
        )
    }

    func testHoldingAWestPeakOpensAnimalsNotIce() throws {
        let held = try hold(at: Self.westPeak, zoom: 16)
        XCTAssertEqual(held.card?.klass, "Peak", "\(held)")
        XCTAssertEqual(held.card?.title, "Mount Franklin", "\(held)")
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("coyote and deer range"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("ice"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("hog"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        let texas: Set<String> = [
            Inspect.plantTXCard, Inspect.treeUseTXCard, Inspect.cactusTXCard,
            Inspect.mammalTXCard, Inspect.gameTXCard, Inspect.plantUseCard,
            Inspect.biteCard, Inspect.shelterCard, Inspect.fungiCard,
            Inspect.gameCard, Inspect.plantCard, Inspect.coldCard,
            Inspect.heatCard, Inspect.snakeTXCard,
        ]
        let present = InspectField.presentRoute(held.card?.fieldRoute ?? [], in: texas)
        XCTAssertEqual(present.first, Inspect.mammalTXCard, "\(held)")
        XCTAssertEqual(InspectField.label(for: present.first ?? ""), "FIELD · ANIMAL")
        XCTAssertEqual(InspectField.bookLine(for: present), "ANIMAL · BITE · COLD")
    }

    func testHoldingAnEastPeakOpensHogNotJavelina() throws {
        let held = try hold(at: Self.eastPeak, zoom: 16, packId: "tx-east")
        XCTAssertEqual(held.card?.klass, "Peak", "\(held)")
        XCTAssertEqual(held.card?.title, "Barton Hill", "\(held)")
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("hog"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("ice"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("elk"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        let east: Set<String> = [
            Inspect.plantTXCard, Inspect.treeUseEastCard, Inspect.cactusTXCard,
            Inspect.mammalEastCard, Inspect.gameEastCard, Inspect.plantUseCard,
            Inspect.biteCard, Inspect.shelterCard, Inspect.fungiCard,
            Inspect.gameCard, Inspect.plantCard, Inspect.coldCard,
            Inspect.heatCard, Inspect.snakeEastCard,
        ]
        let present = InspectField.presentRoute(held.card?.fieldRoute ?? [], in: east)
        XCTAssertEqual(present.first, Inspect.mammalEastCard, "\(held)")
        XCTAssertEqual(InspectField.label(for: present.first ?? ""), "FIELD · ANIMAL")
        XCTAssertEqual(InspectField.bookLine(for: present), "ANIMAL · BITE · COLD")
    }

    func testHoldingANewMexicoOpenReserveOpensBiteNotPicnicWoodland() throws {
        let held = try hold(at: Self.nmOpenReserve, zoom: 16, packId: "nm")
        XCTAssertEqual(held.card?.klass, "Open reserve", "\(held)")
        XCTAssertEqual(
            held.card?.title,
            "Jones Canyon Area of Critical Environmental Concern",
            "\(held)"
        )
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.snakeTXCard, "\(held)")
        XCTAssertTrue(
            held.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "an NM ACEC dropped the NM snake card: \(held)"
        )
        XCTAssertNotEqual(
            held.card?.fieldRoute.first,
            Inspect.treeUseNMCard,
            "an ACEC opened picnic woodland: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("rattler") || doLine.contains("diamondback"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("sotol") || doLine.contains("cholla"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it room"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        let nmBook: Set<String> = [
            Inspect.snakeNMCard, Inspect.mammalNMCard, Inspect.cactusNMCard,
            Inspect.treeUseNMCard, Inspect.plantNMCard, Inspect.gameNMCard,
            Inspect.biteCard, Inspect.plantUseCard, Inspect.gameCard, Inspect.heatCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(held.card?.fieldRoute ?? [], in: nmBook).first,
            Inspect.snakeNMCard
        )
        XCTAssertEqual(
            InspectField.label(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: nmBook
            ).first ?? ""),
            "FIELD · BITE"
        )
    }

    func testHoldingNewMexicoWoodlandOpensCottonwoodNotJavelina() throws {
        let held = try hold(at: Self.nmWoodland, zoom: 16, packId: "nm")
        XCTAssertEqual(held.card?.klass, "Woodland", "\(held)")
        XCTAssertEqual(held.card?.title, "Isleta Rectangle", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.treeUseTXCard, "\(held)")
        XCTAssertTrue(
            held.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? false,
            "NM woodland dropped the NM tree-use card: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("juniper") || doLine.contains("piñon") || doLine.contains("pinon"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("elk"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("south-side"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("wind break"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("food card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        let nmBook: Set<String> = [
            Inspect.treeUseNMCard, Inspect.plantNMCard, Inspect.mammalNMCard,
            Inspect.gameNMCard, Inspect.plantUseCard, Inspect.biteCard,
            Inspect.shelterCard, Inspect.fungiCard, Inspect.gameCard, Inspect.plantCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(held.card?.fieldRoute ?? [], in: nmBook).first,
            Inspect.treeUseNMCard
        )
        XCTAssertEqual(
            InspectField.label(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: nmBook
            ).first ?? ""),
            "FIELD · PLANT"
        )
        XCTAssertEqual(
            InspectField.bookLine(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: nmBook
            )),
            "PLANT · ANIMAL · FOOD · BITE · SHELTER · FUNGI"
        )
    }

    func testHoldingANewMexicoBosqueOpensCottonwoodNotElkCountry() throws {
        let held = try hold(at: Self.nmBosque, zoom: 16, packId: "nm")
        XCTAssertEqual(held.card?.klass, "Bosque or wetland", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.treeUseTXCard, "\(held)")
        XCTAssertFalse(
            held.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? true,
            "NM bosque opened rattler country: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("mule deer"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bear"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("south-side"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("wind break"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("elk"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("food card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        XCTAssertEqual(
            InspectField.label(for: held.card?.fieldRoute.first ?? ""),
            "FIELD · PLANT"
        )
    }

    func testHoldingANewMexicoPeakOpensColdThenAnimals() throws {
        let held = try hold(at: Self.nmPeak, zoom: 16, packId: "nm")
        XCTAssertEqual(held.card?.klass, "Peak", "\(held)")
        XCTAssertEqual(held.card?.title, "La Cruz Peak", "\(held)")
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("black bear and elk range"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("hog"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        let nmBook: Set<String> = [
            Inspect.iceRockCard, Inspect.mammalNMCard, Inspect.biteCard, Inspect.coldCard,
        ]
        let present = InspectField.presentRoute(held.card?.fieldRoute ?? [], in: nmBook)
        XCTAssertEqual(present.first, Inspect.iceRockCard, "\(held)")
        XCTAssertEqual(InspectField.label(for: present.first ?? ""), "FIELD · COLD")
        XCTAssertEqual(InspectField.bookLine(for: present), "COLD · ANIMAL · BITE")
    }

    func testHoldingAnEastPrairiePreserveOpensBiteNotPicnicWoodland() throws {
        let held = try hold(at: Self.eastOpenReserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(held.card?.klass, "Open reserve", "\(held)")
        XCTAssertEqual(held.card?.title, "Decker Tallgrass Prairie Preserve", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.snakeEastCard, "\(held)")
        XCTAssertNotEqual(
            held.card?.fieldRoute.first,
            Inspect.treeUseEastCard,
            "a prairie preserve opened picnic woodland: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("hog"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it room"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("sotol"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cook through"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("give it the road"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("edible"), held.card?.doLine ?? "")
        let eastBook: Set<String> = [
            Inspect.snakeEastCard, Inspect.mammalEastCard, Inspect.cactusTXCard,
            Inspect.treeUseEastCard, Inspect.plantTXCard, Inspect.gameEastCard,
            Inspect.biteCard, Inspect.plantUseCard, Inspect.gameCard, Inspect.heatCard,
        ]
        XCTAssertEqual(
            InspectField.presentRoute(held.card?.fieldRoute ?? [], in: eastBook).first,
            Inspect.snakeEastCard
        )
        XCTAssertEqual(
            InspectField.label(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: eastBook
            ).first ?? ""),
            "FIELD · BITE"
        )
        XCTAssertEqual(
            InspectField.bookLine(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: eastBook
            )),
            "BITE · ANIMAL · PLANT · FOOD · HEAT"
        )
    }

    /// Whatever came back, it has to carry the four lines the card shows and a
    /// Field card to open. A reading with an empty `why` renders as `SURE 68% —`
    /// and looks broken.
    func testEveryHoldOnTheGlassFillsInTheWholeCard() throws {
        let pulled = try Self.packDate()
        for (place, coordinate, zoom) in [
            ("water tank", Self.waterTank, 16.0),
            ("silent tank", Self.silentTank, 16.0),
            ("empty desert", Self.emptyDesert, 15.0),
            ("named ground", Self.namedGround, 15.0),
            ("cactus garden", Self.cactusGarden, 16.0),
            ("desert conservatory", Self.desertConservatory, 16.0),
            ("named bosque", Self.westBosque, 16.0),
            ("irrigated field", Self.irrigatedField, 16.0),
            ("west woodland", Self.westWoodland, 16.0),
            ("rose garden", Self.roseGarden, 16.0),
            ("glasshouse", Self.glasshouse, 16.0),
            ("open reserve", Self.openReserve, 16.0),
            ("sinkhole", Self.sinkhole, 16.0),
        ] {
            let held = try hold(at: coordinate, zoom: zoom)
            guard let card = held.card else {
                XCTFail("\(place) put nothing on the glass")
                continue
            }
            XCTAssertFalse(card.title.isEmpty, "\(place) has no title: \(held)")
            XCTAssertFalse(card.klass.isEmpty, "\(place) has no class: \(held)")
            XCTAssertFalse(card.why.isEmpty, "\(place) has no reason, so SURE reads as a bare number: \(held)")
            XCTAssertFalse(card.fieldCardID.isEmpty, "\(place) opens no Field card: \(held)")
            XCTAssertEqual(card.packDate, pulled, "\(place) lost the pack date: \(held)")
            XCTAssertTrue((1...100).contains(card.sure), "\(place) SURE out of range: \(held)")
        }
    }

    // MARK: - Harness

    /// When the pack's OSM was pulled, as the manifest recorded it — the same
    /// string `AppRuntime` hands the card.
    private static func packDate(packId: String = "tx-west") throws -> String {
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: RenderHarness.packRoot(packId).appendingPathComponent("manifest.json"))
        ) as? [String: Any]
        return try XCTUnwrap(manifest?["osmFetched"] as? String, "the pack does not say when it was pulled")
    }

    /// Hold in the middle of the viewport, through the app's own probe. The
    /// tags come back alongside the card so a red assertion can say whether
    /// the tile was wrong or the reading of it was.
    private func hold(
        at centre: CLLocationCoordinate2D,
        zoom: Double,
        packId: String = "tx-west"
    ) throws -> Held {
        let pack = RenderHarness.packRoot(packId)
        _ = try RenderHarness.requireArchive(in: pack)
        let style = try RenderHarness.shippedStyle(pack: pack)
        // `fallback: [:]` on its own is `[AnyHashable: Any]`, and that type
        // then becomes T — the probe already returns `[String: String]`.
        let tags: [String: String] = try RenderHarness.withRenderedMap(
            style: style,
            at: centre,
            zoom: zoom,
            read: { view in
                let tags = OfflineMapView.Coordinator().record(
                    under: CGPoint(x: view.bounds.midX, y: view.bounds.midY),
                    on: view
                )
                if tags.isEmpty {
                    let source = view.style?.source(withIdentifier: Inspect.packSourceID) as? MLNVectorTileSource
                    let loaded = source?.features(
                        sourceLayerIdentifiers: Inspect.packPointSourceLayers,
                        predicate: nil
                    ).count ?? -1
                    print("HOLD-EMPTY \(centre.latitude),\(centre.longitude) sourcePoints=\(loaded)")
                }
                return tags
            },
            fallback: [:]
        )
        guard !tags.isEmpty else { return Held(tags: [:], card: nil) }
        let state = packId == "nm" ? "NM" : "TX"
        return Held(
            tags: tags,
            card: Inspect.read(
                tags: tags,
                packDate: try Self.packDate(packId: packId),
                state: state,
                pack: packId
            )
        )
    }

    private struct Held: CustomStringConvertible {
        var tags: [String: String]
        var card: Inspect.Card?

        var description: String {
            let probed = tags.isEmpty
                ? "the probe found nothing"
                : tags.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            guard let card else { return probed }
            return "\(card.title) / \(card.klass) / \(card.kind) / \(card.sureLine)  [\(probed)]"
        }
    }
}
#endif
