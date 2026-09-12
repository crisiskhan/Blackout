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
/// `layers/ground.geojson`. West wildlife range is Lost Dog and San Andres,
/// not invented pins. Animals as range are also held on an east sanctuary
/// and on a west peak. New Mexico botanic, wildlife,
/// cave-preserve, and open-reserve sheets are held on the NM archive.
/// East also holds a named sink tagged wetland (not bosque) and a prairie
/// preserve (east vipers, not west diamondback). A west desert conservatory
/// is cactus, not oleander. A named bosque holds tree use, not a pin.
/// Picnic woodland, irrigated ground, and a rose garden are the rest of
/// the plant book on west; east names hog on woodland and cottonmouth on
/// bosque; NM names cottonwood on woodland and bosque, and elk on a peak.
/// Painted heath and scrub are viper country on every pack, not only ACEC
/// overlays. A city park tagged as scrub fill is still a park.
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

    /// Interior of Lush n Lean Garden. Phrase `lush n lean`, botanic
    /// not picnic woodland. 259 m from water.
    private static let lushNLean = CLLocationCoordinate2D(latitude: 32.316751, longitude: -106.777347)

    /// Unnamed `landuse=greenhouse_horticulture` sheet. SOLO_QA point,
    /// verified inside the overlay polygon.
    private static let glasshouse = CLLocationCoordinate2D(latitude: 32.502967, longitude: -106.933833)

    /// Interior of Alamo Mountain ACEC in `layers/ground.geojson`.
    private static let openReserve = CLLocationCoordinate2D(latitude: 32.032331, longitude: -105.633755)

    /// Interior of Franklin Mountains State Park. Named nature reserve, not
    /// picnic woodland. Peak pin still wins on Mount Franklin itself.
    private static let franklinReserve = CLLocationCoordinate2D(latitude: 31.97, longitude: -106.50)

    /// Interior of Lost Dog Nature Preserve. The listed centroid sits on a
    /// wash; this pip is on the wildlife sheet, 441 m from a path.
    private static let westWildlife = CLLocationCoordinate2D(latitude: 31.913286, longitude: -106.547160)

    /// Unnamed `natural=sinkhole` on the place slice. SOLO_QA 31.694905, −106.441133.
    private static let sinkhole = CLLocationCoordinate2D(latitude: 31.694905, longitude: -106.441133)

    /// `Anthony Gap Cave` on the west place slice. A cave mouth, not the
    /// Franklin Mountains overlay that contains it.
    private static let anthonyGapCave = CLLocationCoordinate2D(latitude: 31.998167, longitude: -106.51017)

    /// `Bat Cave` on the west place slice. A cave mouth, not Bee Cave,
    /// not Coyote Cave Park. 2.5 km from OSM water.
    private static let batCave = CLLocationCoordinate2D(latitude: 32.932316, longitude: -107.234781)

    /// `Manilla Thrilla Cave` on the west place slice. A cave mouth,
    /// 232 m from Bat Cave so the probe does not mix them. 2.3 km
    /// from OSM water.
    private static let manillaThrilla = CLLocationCoordinate2D(latitude: 32.930831, longitude: -107.233037)

    /// `Cueva del Apache` on the west place slice. A cave mouth, not the
    /// path `Cueva del Apache - La Ventana`. 126 m from OSM stream.
    private static let cuevaDelApache = CLLocationCoordinate2D(latitude: 31.702715, longitude: -106.583114)

    /// `Aztec Cave` on the west place slice. A cave mouth inside Franklin
    /// Mountains State Park, not `Aztec Caves Trail`. 28 m from OSM stream;
    /// rank 1 still beats water.
    private static let aztecCave = CLLocationCoordinate2D(latitude: 31.921771, longitude: -106.503704)

    /// Interior of Indiangrass Wildlife Sanctuary in east `layers/ground.geojson`.
    /// Scrub fill does not win. Range, not a pin.
    private static let wildlifeRange = CLLocationCoordinate2D(latitude: 30.315667, longitude: -97.591821)

    /// Interior of Beaukiss Woods. East woodland tree-use: loblolly and hog,
    /// not west javelina, not cottonmouth (that is bosque).
    private static let eastWoodland = CLLocationCoordinate2D(latitude: 30.423083, longitude: -97.227224)

    /// Interior of an unnamed east wetland. Cottonmouth on bosque, not a park.
    /// Chosen from `osm.pmtiles` land `class=bosque` / `natural=wetland`, not
    /// a geojson ring whose centroid tiles as meadow.
    private static let eastBosque = CLLocationCoordinate2D(latitude: 30.346188, longitude: -97.795410)

    /// Interior of Discovery Well Cave Preserve in east `layers/ground.geojson`.
    private static let cavePreserve = CLLocationCoordinate2D(latitude: 30.490391, longitude: -97.855063)

    /// Interior of Lost Oasis Cave Preserve. Named nature-reserve cave
    /// phrase, not a picnic park.
    private static let lostOasisCave = CLLocationCoordinate2D(latitude: 30.163187, longitude: -97.873678)

    /// Interior of Whirlpool Cave nature reserve. A hole, not picnic
    /// woodland. The cave mouth sits 125 m off this pip.
    private static let whirlpoolCave = CLLocationCoordinate2D(latitude: 30.215509, longitude: -97.845277)

    /// Interior of Goat Cave Karst Nature Preserve. A hole, not wildlife
    /// range. Phrase `karst preserve`.
    private static let goatCaveKarst = CLLocationCoordinate2D(latitude: 30.199538, longitude: -97.846758)

    /// Interior of William H. Russell Karst Preserve. A hole, not
    /// wildlife range. Phrase `karst preserve`. Karst Lane stays a
    /// road. 396 m from OSM water.
    private static let russellKarst = CLLocationCoordinate2D(latitude: 30.197158, longitude: -97.851485)

    /// Interior of Nalle Bunny Run Wildlife Preserve. East wildlife range,
    /// not Open reserve.
    private static let nalleWildlife = CLLocationCoordinate2D(latitude: 30.349686, longitude: -97.803982)

    /// Interior of Sunset Valley Nature Area. Phrase `nature area`, not
    /// only `natural area`. Williamson Creek is 102 m off this pip.
    private static let sunsetNatureArea = CLLocationCoordinate2D(latitude: 30.222831, longitude: -97.822707)

    /// Interior of Barton Creek Habitat Preserve (west sheet). Phrase
    /// `habitat preserve`. Barton Creek is kilometres off this pip.
    private static let bartonHabitat = CLLocationCoordinate2D(latitude: 30.269882, longitude: -97.916386)

    /// Interior of Área de Protección de Flora y Fauna Médanos de
    /// Samalayuca. Phrase `flora y fauna`, not Open reserve.
    private static let floraFauna = CLLocationCoordinate2D(latitude: 31.247021, longitude: -106.450970)

    /// Interior of Barton Creek Wilderness Park. Phrase `wilderness park`,
    /// not picnic woodland. 442 m from water.
    private static let bartonWilderness = CLLocationCoordinate2D(latitude: 30.243962, longitude: -97.815694)

    /// Interior of Balcones Canyonlands Preserve — Grandview Hills.
    /// Phrase `canyonlands preserve`, not Open reserve, not a trail park.
    private static let canyonlandsPreserve = CLLocationCoordinate2D(latitude: 30.416444, longitude: -97.864868)

    /// Interior of Valles Caldera National Preserve. Phrase `national
    /// preserve`. Elk country, not Open reserve.
    private static let vallesCaldera = CLLocationCoordinate2D(latitude: 36.000815, longitude: -106.455062)

    /// Interior of Leonora Curtin Wetland Preserve. Phrase `wetland
    /// preserve`, animals first, not bosque overlay. 417 m from water.
    private static let curtinWetland = CLLocationCoordinate2D(latitude: 35.569230, longitude: -106.101626)

    /// Interior of Santa Fe Canyon Preserve. Phrase `canyon preserve`,
    /// not Open reserve, not the interpretive loop. 678 m from water.
    private static let santaFeCanyon = CLLocationCoordinate2D(latitude: 35.680636, longitude: -105.887799)

    /// Interior of Bear Creek Management Unit. Phrase `management unit`,
    /// not Open reserve. 777 m from water.
    private static let bearCreekUnit = CLLocationCoordinate2D(latitude: 30.160921, longitude: -97.877106)

    /// Interior of Hornsby Bend Ecological Research Area. Phrase
    /// `ecological research`, not Open reserve. 516 m from water.
    private static let hornsbyBend = CLLocationCoordinate2D(latitude: 30.231564, longitude: -97.646392)
    private static let bakerSanctuary = CLLocationCoordinate2D(latitude: 30.483183, longitude: -97.865747)
    private static let blairWoods = CLLocationCoordinate2D(latitude: 30.286405, longitude: -97.675658)
    /// Interior of Beck Preserve (Travis Audubon). Phrase `beck preserve`,
    /// not the word `beck`. Vertex-avg, 488 m from water.
    private static let beckPreserve = CLLocationCoordinate2D(latitude: 30.493184, longitude: -97.730214)

    /// Interior of Brodie Wild. Phrase `brodie wild`, not the word
    /// `brodie`. Brodie Lane stays a road. Brodie and Oakdale
    /// Properties stay Open reserve. 128 m from OSM water.
    private static let brodieWild = CLLocationCoordinate2D(latitude: 30.183433, longitude: -97.850150)

    /// Interior of Gay Ruby Dahlstrom Nature Preserve. Phrase
    /// `dahlstrom nature`, not the word `dahlstrom`. Dahlstrom Road
    /// stays a road. 646 m from OSM stream.
    private static let dahlstromPreserve = CLLocationCoordinate2D(latitude: 30.085079, longitude: -97.898228)

    /// Interior of Hawk Watch Open Space. Phrase `hawk watch`, not
    /// picnic open space. 449 m from water.
    private static let hawkWatch = CLLocationCoordinate2D(latitude: 35.069828, longitude: -106.424820)

    /// Interior of Jornada Experimental Range. Phrase `experimental
    /// range`, not Open reserve. Far from water.
    private static let jornadaRange = CLLocationCoordinate2D(latitude: 32.594082, longitude: -106.823441)

    /// Interior of Chihuahuan Desert Gardens. Phrase `desert garden` on a
    /// garden sheet; spines, not oleander. 314 m from water.
    private static let desertGardens = CLLocationCoordinate2D(latitude: 31.769382, longitude: -106.506453)

    /// Interior of Wildflower Preserve. Phrase `wildflower preserve`,
    /// botanic not Open reserve, not a wildflower park. 194 m from water.
    private static let wildflowerPreserve = CLLocationCoordinate2D(latitude: 30.242251, longitude: -97.828949)

    /// Interior of Orchard Garden. Phrase `orchard garden`, botanic
    /// not a meal, not Orchard Gardens Road. Far from water.
    private static let orchardGarden = CLLocationCoordinate2D(latitude: 30.290271, longitude: -97.696468)

    /// Interior of Ladybird Johnson Wildflower Center. OSM garden
    /// relation, not a ring faked from foot paths. Phrase `wildflower
    /// center`. 1067 m from water.
    private static let ladybirdCenter = CLLocationCoordinate2D(latitude: 30.178036, longitude: -97.867541)

    /// Interior of Zilker Botanical Garden. Phrase `botanical garden`.
    /// 780 m from Barton Creek.
    private static let zilkerBotanic = CLLocationCoordinate2D(latitude: 30.269689, longitude: -97.774680)

    /// Interior of Santa Fe Botanical Garden. Phrase `botanical garden`.
    /// Far from water.
    private static let santaFeBotanic = CLLocationCoordinate2D(latitude: 35.666135, longitude: -105.925544)

    /// Interior of Japaneese Garden. OSM spelling, phrase `japaneese
    /// garden`. 344 m from water.
    private static let japaneeseGarden = CLLocationCoordinate2D(latitude: 31.803975, longitude: -106.436233)

    /// Interior of Lady Bird Johnson Texas Capitol Flower Gardens.
    /// Phrase `capitol flower`, not `flower gardens`. 537 m from water.
    private static let capitolFlower = CLLocationCoordinate2D(latitude: 30.275837, longitude: -97.739917)

    /// Interior of Japanese Memorial Garden. Phrase `japanese memorial`,
    /// not Memorial Garden. 151 m from water.
    private static let japaneseMemorial = CLLocationCoordinate2D(latitude: 35.153338, longitude: -106.555074)

    /// Interior of Water Wise Demonstration Garden. Phrase
    /// `demonstration garden`. Far from water.
    private static let waterWiseGarden = CLLocationCoordinate2D(latitude: 35.243410, longitude: -106.665821)

    /// Interior of Los Alamos Demonstration Garden. Phrase
    /// `demonstration garden`. 125 m from water.
    private static let losAlamosDemo = CLLocationCoordinate2D(latitude: 35.881885, longitude: -106.304329)

    /// Interior of Preston Foster Native Garden. Phrase `preston
    /// foster`, not `native garden`. 195 m from water.
    private static let prestonFoster = CLLocationCoordinate2D(latitude: 31.759280, longitude: -106.490443)

    /// Interior of Xeriscape Garden. Phrase `xeriscape garden`, not
    /// Xeriscape Park. Far from water.
    private static let xeriscapeGarden = CLLocationCoordinate2D(latitude: 30.496225, longitude: -97.734943)

    /// Interior of SFC Teaching Garden. Phrase `teaching garden`.
    /// 934 m from water.
    private static let sfcTeaching = CLLocationCoordinate2D(latitude: 30.278584, longitude: -97.709046)

    /// Interior of Desert Oasis Teaching Garden. Phrase `teaching
    /// garden`. 121 m from water.
    private static let desertOasisTeaching = CLLocationCoordinate2D(latitude: 35.151445, longitude: -106.556576)

    /// E.R. Fincher III Garden overlay (phrase `fincher iii garden`).
    /// Community garden without the amenity tag. The listed centroid sits
    /// on Boggy Creek — water still outranks overlay.
    private static let fincherGarden = CLLocationCoordinate2D(latitude: 30.260460, longitude: -97.699293)

    /// Interior of Brazos Bluff. Phrase `brazos bluff`, not the word
    /// `brazos`. Educational garden. 290 m from water.
    private static let brazosBluff = CLLocationCoordinate2D(latitude: 30.261206, longitude: -97.742801)

    /// Explorers Garden overlay (phrase `explorers garden`). Educational
    /// garden. The listed centroid sits on water / a tap — water still
    /// outranks overlay.
    private static let explorersGarden = CLLocationCoordinate2D(latitude: 30.260564, longitude: -97.740969)

    /// Interior of The Haozous Garden. Phrase `haozous garden`, not
    /// Haozous Road. 1064 m from water.
    private static let haozousGarden = CLLocationCoordinate2D(latitude: 35.586438, longitude: -106.010271)

    /// Interior of Este Garden. Phrase `este garden`, not the word
    /// `este`. Celeste Drive stays a road. 203 m from OSM water.
    private static let esteGarden = CLLocationCoordinate2D(latitude: 30.283704, longitude: -97.719118)

    /// Interior of 4th Street Garden. Phrase `4th street garden`,
    /// not the word `4th`. West 4th Avenue stays a road. 91 m from
    /// OSM drain.
    private static let fourthStreetGarden = CLLocationCoordinate2D(latitude: 33.134037, longitude: -107.252761)

    /// Interior of Alamogordo Community Garden. Phrase `alamogordo
    /// community garden`, not the word `alamogordo`. The Alamogordo
    /// street stays a road. 419 m from OSM ditch.
    private static let alamogordoGarden = CLLocationCoordinate2D(latitude: 32.908810, longitude: -105.948195)

    /// Interior of Albuquerque Rose Garden. Phrase `albuquerque rose
    /// garden`, not the word `albuquerque`. Memorial Rose Garden is a
    /// separate sheet. 975 m from Embudo Arroyo.
    private static let albuquerqueRose = CLLocationCoordinate2D(latitude: 35.107927, longitude: -106.552812)

    /// Interior of La Mesa Neighborhood Community Garden. Phrase
    /// `la mesa neighborhood`, not `la mesa`. Paseo de la Mesa Open
    /// Space stays Open reserve. La Mesa Court stays a road. 512 m
    /// from OSM ditch.
    private static let laMesaGarden = CLLocationCoordinate2D(latitude: 35.080221, longitude: -106.563856)

    /// Interior of Sandia Mountain Natural History Center. Phrase
    /// `natural history`, not Open reserve. Far from water.
    private static let sandiaHistory = CLLocationCoordinate2D(latitude: 35.126801, longitude: -106.379801)

    /// `Treaty Oak` on the east place slice. A surveyed tree, shade and
    /// wood, not a meal.
    private static let treatyOak = CLLocationCoordinate2D(latitude: 30.271466, longitude: -97.755462)

    /// `Sorin Oak` on the east place slice. A surveyed tree, shade and
    /// wood, not a meal. Not Sorin Street. 267 m from OSM water.
    private static let sorinOak = CLLocationCoordinate2D(latitude: 30.229486, longitude: -97.75447)

    /// Interior of Blowing Sink in east `layers/ground.geojson`. A wetland
    /// in the extract; phrase `blowing sink`, not a cave-preserve park.
    /// Vertex-avg covers the sheet. Streams and ways sit hundreds of metres off.
    private static let namedSink = CLLocationCoordinate2D(latitude: 30.193035, longitude: -97.850443)

    /// Interior of Decker Tallgrass Prairie Preserve. East open reserve —
    /// cottonmouth and hog, not west diamondback, not picnic woodland.
    /// Vertex-avg covers the sheet, far from Decker Creek and any named way.
    private static let eastOpenReserve = CLLocationCoordinate2D(latitude: 30.294331, longitude: -97.603942)

    /// Interior of Albuquerque BioPark Botanic Garden in NM `layers/ground.geojson`.
    /// The listed centroid sits next to a pond; water outranks the sheet.
    /// This point is on the botanic polygon, away from water and named ways.
    private static let botanicGarden = CLLocationCoordinate2D(latitude: 35.093625, longitude: -106.680958)

    /// Interior of Harvey Cornell Rose Park. Phrase `harvey cornell`,
    /// botanic not picnic woodland, not Wildrose Park. Far from water.
    private static let cornellRose = CLLocationCoordinate2D(latitude: 35.670293, longitude: -105.946141)

    /// Interior of Marquez Wildlife Management Area in NM `layers/ground.geojson`.
    /// SOLO_QA 35.327562, −107.319389 is on the sheet and far from water or a way.
    private static let nmWildlifeRange = CLLocationCoordinate2D(latitude: 35.327562, longitude: -107.319389)

    /// Interior of Bernardo Wildlife Management Area. Phrase `bernardo
    /// wildlife`, not the word `bernardo`. Bernardo Trails Park stays
    /// a park. Don Bernardo Road stays a road. 2316 m from OSM drain.
    private static let bernardoWMA = CLLocationCoordinate2D(latitude: 34.423426, longitude: -106.829413)

    /// Interior of Pronoun Cave ACEC in NM `layers/ground.geojson`. A cave
    /// phrase, not open reserve, even though the name also says ACEC.
    private static let nmCavePreserve = CLLocationCoordinate2D(latitude: 34.750796, longitude: -107.344750)

    /// `Sandia Man Cave` on the NM place slice. A cave mouth, not a pin
    /// and not picnic woodland.
    private static let sandiaManCave = CLLocationCoordinate2D(latitude: 35.254746, longitude: -106.405585)

    /// `Embudo Cave` on the NM place slice. A cave mouth, not Embudo Hills
    /// Park, not Embudo Trail. 300 m from OSM water.
    private static let embudoCave = CLLocationCoordinate2D(latitude: 35.204126, longitude: -106.414502)

    /// `Bear Cave` on the NM place slice. A cave mouth. 206 m from
    /// Rio En Medio; rank 1 still beats water.
    private static let bearCave = CLLocationCoordinate2D(latitude: 35.791534, longitude: -105.799885)

    /// Interior of Randall Davey Audubon Center. NM wildlife range, not
    /// Open reserve.
    private static let randallDavey = CLLocationCoordinate2D(latitude: 35.688876, longitude: -105.884927)

    /// `Mount Franklin` on the west place slice. Peak pin still wins inside
    /// Franklin Mountains State Park. Animals as range are also Lost Dog.
    private static let westPeak = CLLocationCoordinate2D(latitude: 31.832051, longitude: -106.492210)

    /// Interior of Jones Canyon ACEC in NM `layers/ground.geojson`. Open
    /// reserve, not Pronoun Cave — rattler and sotol, not a hole.
    private static let nmOpenReserve = CLLocationCoordinate2D(latitude: 35.846906, longitude: -107.025703)

    /// Interior of Isleta Rectangle. Named NM forest: cottonwood;
    /// elk is high country, not west javelina, not a wetland bosque.
    private static let nmWoodland = CLLocationCoordinate2D(latitude: 34.939900, longitude: -106.320316)

    /// Interior of an unnamed NM wetland. Cottonwood and mule deer, not elk
    /// (elk is high country), not cottonmouth (that is east).
    private static let nmBosque = CLLocationCoordinate2D(latitude: 34.628816, longitude: -105.915768)

    /// `La Cruz Peak` on the NM place slice. Bear and elk as range, not
    /// west javelina. Ice-on-rock is in this book, so FIELD names cold first.
    private static let nmPeak = CLLocationCoordinate2D(latitude: 34.392837, longitude: -107.420040)

    /// `Barton Hill` on the east place slice. Hog as range, not west javelina.
    private static let eastPeak = CLLocationCoordinate2D(latitude: 30.065769, longitude: -97.882228)

    /// Interior of unnamed east scrub. Ordinary cover: cottonmouth and hog,
    /// not west diamondback, not an overlay prairie.
    private static let eastScrub = CLLocationCoordinate2D(latitude: 30.048502, longitude: -97.745559)

    /// Interior of Cerro Pelado Burn Scar, inside Jemez National Recreation
    /// Area. The burn scar is still painted scrub; the hold names the
    /// recreation area. Not Jones Canyon. Not picnic woodland.
    private static let nmScrub = CLLocationCoordinate2D(latitude: 35.785371, longitude: -106.573932)

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

        let gardens = try hold(at: Self.desertGardens, zoom: 16)
        XCTAssertEqual(gardens.card?.klass, "Cactus garden", "\(gardens)")
        XCTAssertNotEqual(gardens.card?.klass, "Botanic garden", "\(gardens)")
        XCTAssertEqual(gardens.card?.title, "Chihuahuan Desert Gardens", "\(gardens)")
        XCTAssertEqual(gardens.card?.fieldRoute.first, Inspect.cactusTXCard, "\(gardens)")
        XCTAssertFalse(
            gardens.card?.fieldRoute.contains(Inspect.plantTXCard) ?? true,
            "desert gardens opened oleander: \(gardens)"
        )
        let gardensDo = gardens.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(gardensDo.contains("prickly pear"), gardens.card?.doLine ?? "")
        XCTAssertFalse(gardensDo.contains("oleander"), gardens.card?.doLine ?? "")
        XCTAssertFalse(gardensDo.contains("edible"), gardens.card?.doLine ?? "")
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

        let lush = try hold(at: Self.lushNLean, zoom: 16)
        XCTAssertEqual(lush.card?.klass, "Botanic garden", "\(lush)")
        XCTAssertEqual(lush.card?.title, "Lush n Lean Garden", "\(lush)")
        XCTAssertEqual(lush.card?.fieldRoute.first, Inspect.plantTXCard, "\(lush)")
        XCTAssertFalse(
            lush.card?.fieldRoute.contains(Inspect.treeUseTXCard) ?? true,
            "a lush n lean garden opened woodland tree-use: \(lush)"
        )
        XCTAssertFalse(
            lush.card?.fieldRoute.contains(Inspect.cactusTXCard) ?? true,
            "a lush n lean garden opened cactus: \(lush)"
        )
        XCTAssertFalse((lush.card?.doLine.lowercased() ?? "").contains("edible"), lush.card?.doLine ?? "")
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

        let franklin = try hold(at: Self.franklinReserve, zoom: 16)
        XCTAssertEqual(franklin.card?.klass, "Open reserve", "\(franklin)")
        XCTAssertEqual(franklin.card?.title, "Franklin Mountains State Park", "\(franklin)")
        XCTAssertEqual(franklin.card?.fieldRoute.first, Inspect.snakeTXCard, "\(franklin)")
        XCTAssertFalse((franklin.card?.doLine.lowercased() ?? "").contains("edible"), franklin.card?.doLine ?? "")
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

        let cave = try hold(at: Self.anthonyGapCave, zoom: 16)
        XCTAssertEqual(cave.card?.klass, "Cave or hole", "\(cave)")
        XCTAssertEqual(cave.card?.title, "Anthony Gap Cave", "\(cave)")
        XCTAssertEqual(cave.card?.fieldRoute.first, Inspect.caveCard, "\(cave)")
        XCTAssertFalse((cave.card?.doLine.lowercased() ?? "").contains("edible"), cave.card?.doLine ?? "")

        let bat = try hold(at: Self.batCave, zoom: 16)
        XCTAssertEqual(bat.card?.klass, "Cave or hole", "\(bat)")
        XCTAssertEqual(bat.card?.title, "Bat Cave", "\(bat)")
        XCTAssertNotEqual(bat.card?.klass, "Park", "\(bat)")
        XCTAssertEqual(bat.card?.fieldRoute.first, Inspect.caveCard, "\(bat)")
        XCTAssertTrue((bat.card?.doLine.lowercased() ?? "").contains("stay in daylight"), bat.card?.doLine ?? "")
        XCTAssertFalse((bat.card?.doLine.lowercased() ?? "").contains("edible"), bat.card?.doLine ?? "")

        let manilla = try hold(at: Self.manillaThrilla, zoom: 16)
        XCTAssertEqual(manilla.card?.klass, "Cave or hole", "\(manilla)")
        XCTAssertEqual(manilla.card?.title, "Manilla Thrilla Cave", "\(manilla)")
        XCTAssertNotEqual(manilla.card?.title, "Bat Cave", "\(manilla)")
        XCTAssertEqual(manilla.card?.fieldRoute.first, Inspect.caveCard, "\(manilla)")
        XCTAssertTrue((manilla.card?.doLine.lowercased() ?? "").contains("stay in daylight"), manilla.card?.doLine ?? "")
        XCTAssertFalse((manilla.card?.doLine.lowercased() ?? "").contains("edible"), manilla.card?.doLine ?? "")

        let apache = try hold(at: Self.cuevaDelApache, zoom: 16)
        XCTAssertEqual(apache.card?.klass, "Cave or hole", "\(apache)")
        XCTAssertEqual(apache.card?.title, "Cueva del Apache", "\(apache)")
        XCTAssertNotEqual(apache.card?.title, "Cueva del Apache - La Ventana", "\(apache)")
        XCTAssertEqual(apache.card?.fieldRoute.first, Inspect.caveCard, "\(apache)")
        XCTAssertTrue((apache.card?.doLine.lowercased() ?? "").contains("stay in daylight"), apache.card?.doLine ?? "")
        XCTAssertFalse((apache.card?.doLine.lowercased() ?? "").contains("edible"), apache.card?.doLine ?? "")

        let aztec = try hold(at: Self.aztecCave, zoom: 16)
        XCTAssertEqual(aztec.card?.klass, "Cave or hole", "\(aztec)")
        XCTAssertEqual(aztec.card?.title, "Aztec Cave", "\(aztec)")
        XCTAssertNotEqual(aztec.card?.klass, "Open reserve", "\(aztec)")
        XCTAssertNotEqual(aztec.card?.title, "Franklin Mountains State Park", "\(aztec)")
        XCTAssertNotEqual(aztec.card?.title, "Aztec Caves Trail", "\(aztec)")
        XCTAssertEqual(aztec.card?.fieldRoute.first, Inspect.caveCard, "\(aztec)")
        XCTAssertTrue((aztec.card?.doLine.lowercased() ?? "").contains("stay in daylight"), aztec.card?.doLine ?? "")
        XCTAssertFalse((aztec.card?.doLine.lowercased() ?? "").contains("edible"), aztec.card?.doLine ?? "")
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

        let west = try hold(at: Self.westWildlife, zoom: 16)
        XCTAssertEqual(west.card?.klass, "Wildlife range", "\(west)")
        XCTAssertEqual(west.card?.title, "Lost Dog Nature Preserve", "\(west)")
        XCTAssertEqual(west.card?.fieldRoute.first, Inspect.mammalTXCard, "\(west)")
        let westDo = west.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(westDo.contains("javelina"), west.card?.doLine ?? "")
        XCTAssertFalse(westDo.contains("edible"), west.card?.doLine ?? "")

        let jornada = try hold(at: Self.jornadaRange, zoom: 16)
        XCTAssertEqual(jornada.card?.klass, "Wildlife range", "\(jornada)")
        XCTAssertEqual(jornada.card?.title, "Jornada Experimental Range", "\(jornada)")
        XCTAssertNotEqual(jornada.card?.klass, "Open reserve", "\(jornada)")
        XCTAssertEqual(jornada.card?.fieldRoute.first, Inspect.mammalTXCard, "\(jornada)")
        XCTAssertTrue((jornada.card?.doLine.lowercased() ?? "").contains("javelina"), jornada.card?.doLine ?? "")
        XCTAssertFalse((jornada.card?.doLine.lowercased() ?? "").contains("edible"), jornada.card?.doLine ?? "")

        let nalle = try hold(at: Self.nalleWildlife, zoom: 16, packId: "tx-east")
        XCTAssertEqual(nalle.card?.klass, "Wildlife range", "\(nalle)")
        XCTAssertEqual(nalle.card?.title, "Nalle Bunny Run Wildlife Preserve", "\(nalle)")
        XCTAssertEqual(nalle.card?.fieldRoute.first, Inspect.mammalEastCard, "\(nalle)")
        XCTAssertFalse((nalle.card?.doLine.lowercased() ?? "").contains("edible"), nalle.card?.doLine ?? "")

        let natureArea = try hold(at: Self.sunsetNatureArea, zoom: 16, packId: "tx-east")
        XCTAssertEqual(natureArea.card?.klass, "Wildlife range", "\(natureArea)")
        XCTAssertEqual(natureArea.card?.title, "Sunset Valley Nature Area", "\(natureArea)")
        XCTAssertNotEqual(natureArea.card?.klass, "Open reserve", "\(natureArea)")
        XCTAssertEqual(natureArea.card?.fieldRoute.first, Inspect.mammalEastCard, "\(natureArea)")
        XCTAssertFalse((natureArea.card?.doLine.lowercased() ?? "").contains("edible"), natureArea.card?.doLine ?? "")

        let habitat = try hold(at: Self.bartonHabitat, zoom: 16, packId: "tx-east")
        XCTAssertEqual(habitat.card?.klass, "Wildlife range", "\(habitat)")
        XCTAssertEqual(habitat.card?.title, "Barton Creek Habitat Preserve", "\(habitat)")
        XCTAssertNotEqual(habitat.card?.klass, "Open reserve", "\(habitat)")
        XCTAssertEqual(habitat.card?.fieldRoute.first, Inspect.mammalEastCard, "\(habitat)")
        XCTAssertFalse((habitat.card?.doLine.lowercased() ?? "").contains("edible"), habitat.card?.doLine ?? "")

        let flora = try hold(at: Self.floraFauna, zoom: 16)
        XCTAssertEqual(flora.card?.klass, "Wildlife range", "\(flora)")
        XCTAssertEqual(
            flora.card?.title,
            "Área de Protección de Flora y Fauna Médanos de Samalayuca",
            "\(flora)"
        )
        XCTAssertNotEqual(flora.card?.klass, "Open reserve", "\(flora)")
        XCTAssertEqual(flora.card?.fieldRoute.first, Inspect.mammalTXCard, "\(flora)")
        XCTAssertFalse((flora.card?.doLine.lowercased() ?? "").contains("edible"), flora.card?.doLine ?? "")

        let wildernessPark = try hold(at: Self.bartonWilderness, zoom: 16, packId: "tx-east")
        XCTAssertEqual(wildernessPark.card?.klass, "Wildlife range", "\(wildernessPark)")
        XCTAssertEqual(wildernessPark.card?.title, "Barton Creek Wilderness Park", "\(wildernessPark)")
        XCTAssertNotEqual(wildernessPark.card?.klass, "Open reserve", "\(wildernessPark)")
        XCTAssertEqual(wildernessPark.card?.fieldRoute.first, Inspect.mammalEastCard, "\(wildernessPark)")
        XCTAssertFalse((wildernessPark.card?.doLine.lowercased() ?? "").contains("edible"), wildernessPark.card?.doLine ?? "")

        let canyonlands = try hold(at: Self.canyonlandsPreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(canyonlands.card?.klass, "Wildlife range", "\(canyonlands)")
        XCTAssertEqual(
            canyonlands.card?.title,
            "Balcones Canyonlands Preserve - Grandview Hills",
            "\(canyonlands)"
        )
        XCTAssertNotEqual(canyonlands.card?.klass, "Open reserve", "\(canyonlands)")
        XCTAssertEqual(canyonlands.card?.fieldRoute.first, Inspect.mammalEastCard, "\(canyonlands)")
        XCTAssertTrue((canyonlands.card?.doLine.lowercased() ?? "").contains("hog"), canyonlands.card?.doLine ?? "")
        XCTAssertFalse((canyonlands.card?.doLine.lowercased() ?? "").contains("cottonwood"), canyonlands.card?.doLine ?? "")
        XCTAssertFalse((canyonlands.card?.doLine.lowercased() ?? "").contains("edible"), canyonlands.card?.doLine ?? "")

        let management = try hold(at: Self.bearCreekUnit, zoom: 16, packId: "tx-east")
        XCTAssertEqual(management.card?.klass, "Wildlife range", "\(management)")
        XCTAssertEqual(management.card?.title, "Bear Creek Management Unit", "\(management)")
        XCTAssertNotEqual(management.card?.klass, "Open reserve", "\(management)")
        XCTAssertEqual(management.card?.fieldRoute.first, Inspect.mammalEastCard, "\(management)")
        XCTAssertTrue((management.card?.doLine.lowercased() ?? "").contains("hog"), management.card?.doLine ?? "")
        XCTAssertFalse((management.card?.doLine.lowercased() ?? "").contains("edible"), management.card?.doLine ?? "")

        let hornsby = try hold(at: Self.hornsbyBend, zoom: 16, packId: "tx-east")
        XCTAssertEqual(hornsby.card?.klass, "Wildlife range", "\(hornsby)")
        XCTAssertEqual(hornsby.card?.title, "Hornsby Bend Ecological Research Area", "\(hornsby)")
        XCTAssertNotEqual(hornsby.card?.klass, "Open reserve", "\(hornsby)")
        XCTAssertEqual(hornsby.card?.fieldRoute.first, Inspect.mammalEastCard, "\(hornsby)")
        XCTAssertFalse((hornsby.card?.doLine.lowercased() ?? "").contains("edible"), hornsby.card?.doLine ?? "")

        let baker = try hold(at: Self.bakerSanctuary, zoom: 16, packId: "tx-east")
        XCTAssertEqual(baker.card?.klass, "Wildlife range", "\(baker)")
        XCTAssertEqual(baker.card?.title, "Baker Sanctuary", "\(baker)")
        XCTAssertNotEqual(baker.card?.klass, "Open reserve", "\(baker)")
        XCTAssertEqual(baker.card?.fieldRoute.first, Inspect.mammalEastCard, "\(baker)")
        XCTAssertTrue((baker.card?.doLine.lowercased() ?? "").contains("hog"), baker.card?.doLine ?? "")
        XCTAssertFalse((baker.card?.doLine.lowercased() ?? "").contains("javelina"), baker.card?.doLine ?? "")
        XCTAssertFalse((baker.card?.doLine.lowercased() ?? "").contains("edible"), baker.card?.doLine ?? "")

        let blair = try hold(at: Self.blairWoods, zoom: 16, packId: "tx-east")
        XCTAssertEqual(blair.card?.klass, "Wildlife range", "\(blair)")
        XCTAssertEqual(blair.card?.title, "Blair Woods Sanctuary", "\(blair)")
        XCTAssertNotEqual(blair.card?.klass, "Open reserve", "\(blair)")
        XCTAssertEqual(blair.card?.fieldRoute.first, Inspect.mammalEastCard, "\(blair)")
        XCTAssertTrue((blair.card?.doLine.lowercased() ?? "").contains("hog"), blair.card?.doLine ?? "")
        XCTAssertFalse((blair.card?.doLine.lowercased() ?? "").contains("edible"), blair.card?.doLine ?? "")

        let beck = try hold(at: Self.beckPreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(beck.card?.klass, "Wildlife range", "\(beck)")
        XCTAssertEqual(beck.card?.title, "Beck Preserve", "\(beck)")
        XCTAssertNotEqual(beck.card?.klass, "Open reserve", "\(beck)")
        XCTAssertEqual(beck.card?.fieldRoute.first, Inspect.mammalEastCard, "\(beck)")
        XCTAssertTrue((beck.card?.doLine.lowercased() ?? "").contains("hog"), beck.card?.doLine ?? "")
        XCTAssertFalse((beck.card?.doLine.lowercased() ?? "").contains("edible"), beck.card?.doLine ?? "")

        let brodie = try hold(at: Self.brodieWild, zoom: 16, packId: "tx-east")
        XCTAssertEqual(brodie.card?.klass, "Wildlife range", "\(brodie)")
        XCTAssertEqual(brodie.card?.title, "Brodie Wild", "\(brodie)")
        XCTAssertNotEqual(brodie.card?.klass, "Open reserve", "\(brodie)")
        XCTAssertEqual(brodie.card?.fieldRoute.first, Inspect.mammalEastCard, "\(brodie)")
        XCTAssertTrue((brodie.card?.doLine.lowercased() ?? "").contains("hog"), brodie.card?.doLine ?? "")
        XCTAssertFalse((brodie.card?.doLine.lowercased() ?? "").contains("javelina"), brodie.card?.doLine ?? "")
        XCTAssertFalse((brodie.card?.doLine.lowercased() ?? "").contains("edible"), brodie.card?.doLine ?? "")

        let dahlstrom = try hold(at: Self.dahlstromPreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(dahlstrom.card?.klass, "Wildlife range", "\(dahlstrom)")
        XCTAssertEqual(dahlstrom.card?.title, "Gay Ruby Dahlstrom Nature Preserve", "\(dahlstrom)")
        XCTAssertNotEqual(dahlstrom.card?.klass, "Open reserve", "\(dahlstrom)")
        XCTAssertNotEqual(dahlstrom.card?.title, "Dahlstrom Road", "\(dahlstrom)")
        XCTAssertEqual(dahlstrom.card?.fieldRoute.first, Inspect.mammalEastCard, "\(dahlstrom)")
        XCTAssertTrue((dahlstrom.card?.doLine.lowercased() ?? "").contains("hog"), dahlstrom.card?.doLine ?? "")
        XCTAssertFalse((dahlstrom.card?.doLine.lowercased() ?? "").contains("javelina"), dahlstrom.card?.doLine ?? "")
        XCTAssertFalse((dahlstrom.card?.doLine.lowercased() ?? "").contains("edible"), dahlstrom.card?.doLine ?? "")
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

        let oak = try hold(at: Self.treatyOak, zoom: 16, packId: "tx-east")
        XCTAssertEqual(oak.card?.klass, "Named tree", "\(oak)")
        XCTAssertEqual(oak.card?.title, "Treaty Oak", "\(oak)")
        XCTAssertEqual(oak.card?.fieldRoute.first, Inspect.treeUseEastCard, "\(oak)")
        let oakDo = oak.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(oakDo.contains("not a meal"), oak.card?.doLine ?? "")
        XCTAssertFalse(oakDo.contains("edible"), oak.card?.doLine ?? "")
        XCTAssertFalse(oakDo.contains("hog"), oak.card?.doLine ?? "")

        let sorin = try hold(at: Self.sorinOak, zoom: 16, packId: "tx-east")
        XCTAssertEqual(sorin.card?.klass, "Named tree", "\(sorin)")
        XCTAssertEqual(sorin.card?.title, "Sorin Oak", "\(sorin)")
        XCTAssertEqual(sorin.card?.fieldRoute.first, Inspect.treeUseEastCard, "\(sorin)")
        let sorinDo = sorin.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(sorinDo.contains("not a meal"), sorin.card?.doLine ?? "")
        XCTAssertFalse(sorinDo.contains("edible"), sorin.card?.doLine ?? "")
        XCTAssertFalse(sorinDo.contains("hog"), sorin.card?.doLine ?? "")
        XCTAssertFalse(sorinDo.contains("javelina"), sorin.card?.doLine ?? "")
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

        let oasis = try hold(at: Self.lostOasisCave, zoom: 16, packId: "tx-east")
        XCTAssertEqual(oasis.card?.klass, "Cave or hole", "\(oasis)")
        XCTAssertEqual(oasis.card?.title, "Lost Oasis Cave Preserve", "\(oasis)")
        XCTAssertEqual(oasis.card?.fieldRoute.first, Inspect.caveCard, "\(oasis)")
        XCTAssertFalse((oasis.card?.doLine.lowercased() ?? "").contains("edible"), oasis.card?.doLine ?? "")

        let whirl = try hold(at: Self.whirlpoolCave, zoom: 16, packId: "tx-east")
        XCTAssertEqual(whirl.card?.klass, "Cave or hole", "\(whirl)")
        XCTAssertEqual(whirl.card?.title, "Whirlpool Cave", "\(whirl)")
        XCTAssertEqual(whirl.card?.fieldRoute.first, Inspect.caveCard, "\(whirl)")
        XCTAssertFalse((whirl.card?.doLine.lowercased() ?? "").contains("edible"), whirl.card?.doLine ?? "")

        let goat = try hold(at: Self.goatCaveKarst, zoom: 16, packId: "tx-east")
        XCTAssertEqual(goat.card?.klass, "Cave or hole", "\(goat)")
        XCTAssertNotEqual(goat.card?.klass, "Wildlife range", "\(goat)")
        XCTAssertEqual(goat.card?.title, "Goat Cave Karst Nature Preserve", "\(goat)")
        XCTAssertEqual(goat.card?.fieldRoute.first, Inspect.caveCard, "\(goat)")

        let russell = try hold(at: Self.russellKarst, zoom: 16, packId: "tx-east")
        XCTAssertEqual(russell.card?.klass, "Cave or hole", "\(russell)")
        XCTAssertNotEqual(russell.card?.klass, "Wildlife range", "\(russell)")
        XCTAssertEqual(russell.card?.title, "William H. Russell Karst Preserve", "\(russell)")
        XCTAssertNotEqual(russell.card?.title, "Karst Lane", "\(russell)")
        XCTAssertEqual(russell.card?.fieldRoute.first, Inspect.caveCard, "\(russell)")
        XCTAssertTrue((russell.card?.doLine.lowercased() ?? "").contains("stay in daylight"), russell.card?.doLine ?? "")
        XCTAssertFalse((russell.card?.doLine.lowercased() ?? "").contains("edible"), russell.card?.doLine ?? "")
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

        let wildflower = try hold(at: Self.wildflowerPreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(wildflower.card?.klass, "Botanic garden", "\(wildflower)")
        XCTAssertEqual(wildflower.card?.title, "Wildflower Preserve", "\(wildflower)")
        XCTAssertNotEqual(wildflower.card?.klass, "Open reserve", "\(wildflower)")
        XCTAssertNotEqual(wildflower.card?.klass, "Wildlife range", "\(wildflower)")
        XCTAssertEqual(wildflower.card?.fieldRoute.first, Inspect.plantTXCard, "\(wildflower)")
        XCTAssertFalse(
            wildflower.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "a wildflower preserve opened woodland tree-use: \(wildflower)"
        )
        XCTAssertFalse((wildflower.card?.doLine.lowercased() ?? "").contains("edible"), wildflower.card?.doLine ?? "")

        let orchard = try hold(at: Self.orchardGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(orchard.card?.klass, "Botanic garden", "\(orchard)")
        XCTAssertEqual(orchard.card?.title, "Orchard Garden", "\(orchard)")
        XCTAssertNotEqual(orchard.card?.klass, "Park", "\(orchard)")
        XCTAssertEqual(orchard.card?.fieldRoute.first, Inspect.plantTXCard, "\(orchard)")
        XCTAssertFalse(
            orchard.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "an orchard garden opened woodland tree-use: \(orchard)"
        )
        XCTAssertFalse((orchard.card?.doLine.lowercased() ?? "").contains("edible"), orchard.card?.doLine ?? "")

        let ladybird = try hold(at: Self.ladybirdCenter, zoom: 16, packId: "tx-east")
        XCTAssertEqual(ladybird.card?.klass, "Botanic garden", "\(ladybird)")
        XCTAssertEqual(ladybird.card?.title, "Ladybird Johnson Wildflower Center", "\(ladybird)")
        XCTAssertNotEqual(ladybird.card?.klass, "Park", "\(ladybird)")
        XCTAssertEqual(ladybird.card?.fieldRoute.first, Inspect.plantTXCard, "\(ladybird)")
        XCTAssertFalse(
            ladybird.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "a wildflower center opened woodland tree-use: \(ladybird)"
        )
        XCTAssertFalse(
            ladybird.card?.fieldRoute.contains(Inspect.cactusTXCard) ?? true,
            "a wildflower center opened cactus: \(ladybird)"
        )
        XCTAssertFalse((ladybird.card?.doLine.lowercased() ?? "").contains("edible"), ladybird.card?.doLine ?? "")

        let zilker = try hold(at: Self.zilkerBotanic, zoom: 16, packId: "tx-east")
        XCTAssertEqual(zilker.card?.klass, "Botanic garden", "\(zilker)")
        XCTAssertEqual(zilker.card?.title, "Zilker Botanical Garden", "\(zilker)")
        XCTAssertEqual(zilker.card?.fieldRoute.first, Inspect.plantTXCard, "\(zilker)")
        XCTAssertFalse(
            zilker.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Zilker Botanical Garden opened woodland tree-use: \(zilker)"
        )
        XCTAssertFalse((zilker.card?.doLine.lowercased() ?? "").contains("edible"), zilker.card?.doLine ?? "")

        let santaFe = try hold(at: Self.santaFeBotanic, zoom: 16, packId: "nm")
        XCTAssertEqual(santaFe.card?.klass, "Botanic garden", "\(santaFe)")
        XCTAssertEqual(santaFe.card?.title, "Santa Fe Botanical Garden", "\(santaFe)")
        XCTAssertEqual(santaFe.card?.fieldRoute.first, Inspect.plantTXCard, "\(santaFe)")
        XCTAssertTrue(
            santaFe.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "Santa Fe Botanical Garden dropped the NM plant-danger card: \(santaFe)"
        )
        XCTAssertFalse(
            santaFe.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? true,
            "Santa Fe Botanical Garden opened woodland tree-use: \(santaFe)"
        )
        XCTAssertFalse((santaFe.card?.doLine.lowercased() ?? "").contains("edible"), santaFe.card?.doLine ?? "")

        let japaneese = try hold(at: Self.japaneeseGarden, zoom: 16)
        XCTAssertEqual(japaneese.card?.klass, "Botanic garden", "\(japaneese)")
        XCTAssertEqual(japaneese.card?.title, "Japaneese Garden", "\(japaneese)")
        XCTAssertEqual(japaneese.card?.fieldRoute.first, Inspect.plantTXCard, "\(japaneese)")
        XCTAssertFalse(
            japaneese.card?.fieldRoute.contains(Inspect.treeUseTXCard) ?? true,
            "Japaneese Garden opened woodland tree-use: \(japaneese)"
        )
        XCTAssertFalse((japaneese.card?.doLine.lowercased() ?? "").contains("edible"), japaneese.card?.doLine ?? "")

        let capitol = try hold(at: Self.capitolFlower, zoom: 16, packId: "tx-east")
        XCTAssertEqual(capitol.card?.klass, "Botanic garden", "\(capitol)")
        XCTAssertEqual(capitol.card?.title, "Lady Bird Johnson Texas Capitol Flower Gardens", "\(capitol)")
        XCTAssertEqual(capitol.card?.fieldRoute.first, Inspect.plantTXCard, "\(capitol)")
        XCTAssertFalse(
            capitol.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Capitol Flower Gardens opened woodland tree-use: \(capitol)"
        )
        XCTAssertFalse((capitol.card?.doLine.lowercased() ?? "").contains("edible"), capitol.card?.doLine ?? "")

        let japaneseMemorial = try hold(at: Self.japaneseMemorial, zoom: 16, packId: "nm")
        XCTAssertEqual(japaneseMemorial.card?.klass, "Botanic garden", "\(japaneseMemorial)")
        XCTAssertEqual(japaneseMemorial.card?.title, "Japanese Memorial Garden", "\(japaneseMemorial)")
        XCTAssertEqual(japaneseMemorial.card?.fieldRoute.first, Inspect.plantTXCard, "\(japaneseMemorial)")
        XCTAssertTrue(
            japaneseMemorial.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "Japanese Memorial Garden dropped the NM plant-danger card: \(japaneseMemorial)"
        )
        XCTAssertFalse(
            japaneseMemorial.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? true,
            "Japanese Memorial Garden opened woodland tree-use: \(japaneseMemorial)"
        )
        XCTAssertFalse((japaneseMemorial.card?.doLine.lowercased() ?? "").contains("edible"), japaneseMemorial.card?.doLine ?? "")

        let waterWise = try hold(at: Self.waterWiseGarden, zoom: 16, packId: "nm")
        XCTAssertEqual(waterWise.card?.klass, "Botanic garden", "\(waterWise)")
        XCTAssertEqual(waterWise.card?.title, "Water Wise Demonstration Garden", "\(waterWise)")
        XCTAssertTrue(
            waterWise.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "Water Wise Demonstration Garden dropped the NM plant-danger card: \(waterWise)"
        )
        XCTAssertFalse((waterWise.card?.doLine.lowercased() ?? "").contains("edible"), waterWise.card?.doLine ?? "")

        let losAlamos = try hold(at: Self.losAlamosDemo, zoom: 16, packId: "nm")
        XCTAssertEqual(losAlamos.card?.klass, "Botanic garden", "\(losAlamos)")
        XCTAssertEqual(losAlamos.card?.title, "Los Alamos Demonstration Garden", "\(losAlamos)")
        XCTAssertTrue(
            losAlamos.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "Los Alamos Demonstration Garden dropped the NM plant-danger card: \(losAlamos)"
        )
        XCTAssertFalse((losAlamos.card?.doLine.lowercased() ?? "").contains("edible"), losAlamos.card?.doLine ?? "")

        let preston = try hold(at: Self.prestonFoster, zoom: 16)
        XCTAssertEqual(preston.card?.klass, "Botanic garden", "\(preston)")
        XCTAssertEqual(preston.card?.title, "Preston Foster Native Garden", "\(preston)")
        XCTAssertEqual(preston.card?.fieldRoute.first, Inspect.plantTXCard, "\(preston)")
        XCTAssertFalse(
            preston.card?.fieldRoute.contains(Inspect.treeUseTXCard) ?? true,
            "Preston Foster Native Garden opened woodland tree-use: \(preston)"
        )
        XCTAssertFalse((preston.card?.doLine.lowercased() ?? "").contains("edible"), preston.card?.doLine ?? "")

        let xeriscape = try hold(at: Self.xeriscapeGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(xeriscape.card?.klass, "Botanic garden", "\(xeriscape)")
        XCTAssertEqual(xeriscape.card?.title, "Xeriscape Garden", "\(xeriscape)")
        XCTAssertEqual(xeriscape.card?.fieldRoute.first, Inspect.plantTXCard, "\(xeriscape)")
        XCTAssertFalse(
            xeriscape.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Xeriscape Garden opened woodland tree-use: \(xeriscape)"
        )
        XCTAssertFalse((xeriscape.card?.doLine.lowercased() ?? "").contains("edible"), xeriscape.card?.doLine ?? "")

        let sfc = try hold(at: Self.sfcTeaching, zoom: 16, packId: "tx-east")
        XCTAssertEqual(sfc.card?.klass, "Botanic garden", "\(sfc)")
        XCTAssertEqual(sfc.card?.title, "SFC Teaching Garden", "\(sfc)")
        XCTAssertEqual(sfc.card?.fieldRoute.first, Inspect.plantTXCard, "\(sfc)")
        XCTAssertFalse((sfc.card?.doLine.lowercased() ?? "").contains("edible"), sfc.card?.doLine ?? "")

        let desertOasis = try hold(at: Self.desertOasisTeaching, zoom: 16, packId: "nm")
        XCTAssertEqual(desertOasis.card?.klass, "Botanic garden", "\(desertOasis)")
        XCTAssertEqual(desertOasis.card?.title, "Desert Oasis Teaching Garden", "\(desertOasis)")
        XCTAssertTrue(
            desertOasis.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "Desert Oasis Teaching Garden dropped the NM plant-danger card: \(desertOasis)"
        )
        XCTAssertFalse((desertOasis.card?.doLine.lowercased() ?? "").contains("edible"), desertOasis.card?.doLine ?? "")

        let fincher = try hold(at: Self.fincherGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(fincher.card?.kind, .water, "\(fincher)")
        XCTAssertNotEqual(fincher.card?.klass, "Botanic garden", "\(fincher)")
        XCTAssertEqual(fincher.card?.fieldRoute.first, "water-disinfect", "\(fincher)")

        let brazosBluff = try hold(at: Self.brazosBluff, zoom: 16, packId: "tx-east")
        XCTAssertEqual(brazosBluff.card?.klass, "Botanic garden", "\(brazosBluff)")
        XCTAssertEqual(brazosBluff.card?.title, "Brazos Bluff", "\(brazosBluff)")
        XCTAssertEqual(brazosBluff.card?.fieldRoute.first, Inspect.plantTXCard, "\(brazosBluff)")
        XCTAssertFalse(
            brazosBluff.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Brazos Bluff opened woodland tree-use: \(brazosBluff)"
        )
        XCTAssertFalse((brazosBluff.card?.doLine.lowercased() ?? "").contains("edible"), brazosBluff.card?.doLine ?? "")

        let explorers = try hold(at: Self.explorersGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(explorers.card?.kind, .water, "\(explorers)")
        XCTAssertNotEqual(explorers.card?.klass, "Botanic garden", "\(explorers)")
        XCTAssertEqual(explorers.card?.fieldRoute.first, "water-disinfect", "\(explorers)")

        let haozous = try hold(at: Self.haozousGarden, zoom: 16, packId: "nm")
        XCTAssertEqual(haozous.card?.klass, "Botanic garden", "\(haozous)")
        XCTAssertEqual(haozous.card?.title, "The Haozous Garden", "\(haozous)")
        XCTAssertEqual(haozous.card?.fieldRoute.first, Inspect.plantTXCard, "\(haozous)")
        XCTAssertTrue(
            haozous.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "The Haozous Garden dropped the NM plant-danger card: \(haozous)"
        )
        XCTAssertFalse(
            haozous.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? true,
            "The Haozous Garden opened woodland tree-use: \(haozous)"
        )
        XCTAssertFalse((haozous.card?.doLine.lowercased() ?? "").contains("edible"), haozous.card?.doLine ?? "")

        let este = try hold(at: Self.esteGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(este.card?.klass, "Botanic garden", "\(este)")
        XCTAssertEqual(este.card?.title, "Este Garden", "\(este)")
        XCTAssertEqual(este.card?.fieldRoute.first, Inspect.plantTXCard, "\(este)")
        XCTAssertFalse(
            este.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Este Garden opened woodland tree-use: \(este)"
        )
        XCTAssertFalse((este.card?.doLine.lowercased() ?? "").contains("edible"), este.card?.doLine ?? "")

        let fourthStreet = try hold(at: Self.fourthStreetGarden, zoom: 16)
        XCTAssertEqual(fourthStreet.card?.klass, "Botanic garden", "\(fourthStreet)")
        XCTAssertEqual(fourthStreet.card?.title, "4th Street Garden", "\(fourthStreet)")
        XCTAssertEqual(fourthStreet.card?.fieldRoute.first, Inspect.plantTXCard, "\(fourthStreet)")
        XCTAssertFalse(
            fourthStreet.card?.fieldRoute.contains(Inspect.treeUseTXCard) ?? true,
            "4th Street Garden opened woodland tree-use: \(fourthStreet)"
        )
        XCTAssertFalse((fourthStreet.card?.doLine.lowercased() ?? "").contains("edible"), fourthStreet.card?.doLine ?? "")

        let alamogordo = try hold(at: Self.alamogordoGarden, zoom: 16)
        XCTAssertEqual(alamogordo.card?.klass, "Botanic garden", "\(alamogordo)")
        XCTAssertEqual(alamogordo.card?.title, "Alamogordo Community Garden", "\(alamogordo)")
        XCTAssertEqual(alamogordo.card?.fieldRoute.first, Inspect.plantTXCard, "\(alamogordo)")
        XCTAssertFalse(
            alamogordo.card?.fieldRoute.contains(Inspect.treeUseTXCard) ?? true,
            "Alamogordo Community Garden opened woodland tree-use: \(alamogordo)"
        )
        XCTAssertFalse((alamogordo.card?.doLine.lowercased() ?? "").contains("edible"), alamogordo.card?.doLine ?? "")

        let cornell = try hold(at: Self.cornellRose, zoom: 16, packId: "nm")
        XCTAssertEqual(cornell.card?.klass, "Botanic garden", "\(cornell)")
        XCTAssertEqual(cornell.card?.title, "Harvey Cornell Rose Park", "\(cornell)")
        XCTAssertEqual(cornell.card?.fieldRoute.first, Inspect.plantTXCard, "\(cornell)")
        XCTAssertTrue(
            cornell.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "a harvey cornell rose park dropped the NM plant-danger card: \(cornell)"
        )
        XCTAssertFalse(
            cornell.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? true,
            "a harvey cornell rose park opened woodland tree-use: \(cornell)"
        )
        let cornellDo = cornell.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(cornellDo.contains("datura"), cornell.card?.doLine ?? "")
        XCTAssertFalse(cornellDo.contains("edible"), cornell.card?.doLine ?? "")

        let albuquerqueRose = try hold(at: Self.albuquerqueRose, zoom: 16, packId: "nm")
        XCTAssertEqual(albuquerqueRose.card?.klass, "Botanic garden", "\(albuquerqueRose)")
        XCTAssertEqual(albuquerqueRose.card?.title, "Albuquerque Rose Garden", "\(albuquerqueRose)")
        XCTAssertNotEqual(albuquerqueRose.card?.title, "Memorial Rose Garden", "\(albuquerqueRose)")
        XCTAssertEqual(albuquerqueRose.card?.fieldRoute.first, Inspect.plantTXCard, "\(albuquerqueRose)")
        XCTAssertTrue(
            albuquerqueRose.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "Albuquerque Rose Garden dropped the NM plant-danger card: \(albuquerqueRose)"
        )
        XCTAssertFalse(
            albuquerqueRose.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? true,
            "Albuquerque Rose Garden opened woodland tree-use: \(albuquerqueRose)"
        )
        XCTAssertFalse((albuquerqueRose.card?.doLine.lowercased() ?? "").contains("edible"), albuquerqueRose.card?.doLine ?? "")

        let laMesa = try hold(at: Self.laMesaGarden, zoom: 16, packId: "nm")
        XCTAssertEqual(laMesa.card?.klass, "Botanic garden", "\(laMesa)")
        XCTAssertEqual(laMesa.card?.title, "La Mesa Neighborhood Community Garden", "\(laMesa)")
        XCTAssertNotEqual(laMesa.card?.klass, "Open reserve", "\(laMesa)")
        XCTAssertNotEqual(laMesa.card?.title, "Paseo de la Mesa Open Space", "\(laMesa)")
        XCTAssertEqual(laMesa.card?.fieldRoute.first, Inspect.plantTXCard, "\(laMesa)")
        XCTAssertTrue(
            laMesa.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "La Mesa Neighborhood Community Garden dropped the NM plant-danger card: \(laMesa)"
        )
        XCTAssertFalse(
            laMesa.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? true,
            "La Mesa Neighborhood Community Garden opened woodland tree-use: \(laMesa)"
        )
        XCTAssertFalse((laMesa.card?.doLine.lowercased() ?? "").contains("edible"), laMesa.card?.doLine ?? "")
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
        XCTAssertTrue(doLine.contains("elk is high country"), held.card?.doLine ?? "")
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

        let audubon = try hold(at: Self.randallDavey, zoom: 16, packId: "nm")
        XCTAssertEqual(audubon.card?.klass, "Wildlife range", "\(audubon)")
        XCTAssertEqual(audubon.card?.title, "Randall Davey Audubon Center & Sanctuary", "\(audubon)")
        XCTAssertEqual(audubon.card?.fieldRoute.first, Inspect.mammalTXCard, "\(audubon)")
        XCTAssertTrue(
            (audubon.card?.doLine.lowercased() ?? "").contains("elk is high country"),
            audubon.card?.doLine ?? ""
        )
        XCTAssertFalse((audubon.card?.doLine.lowercased() ?? "").contains("edible"), audubon.card?.doLine ?? "")

        let caldera = try hold(at: Self.vallesCaldera, zoom: 16, packId: "nm")
        XCTAssertEqual(caldera.card?.klass, "Wildlife range", "\(caldera)")
        XCTAssertEqual(caldera.card?.title, "Valles Caldera National Preserve", "\(caldera)")
        XCTAssertNotEqual(caldera.card?.klass, "Open reserve", "\(caldera)")
        XCTAssertEqual(caldera.card?.fieldRoute.first, Inspect.mammalTXCard, "\(caldera)")
        XCTAssertTrue(
            (caldera.card?.doLine.lowercased() ?? "").contains("elk is high country"),
            caldera.card?.doLine ?? ""
        )
        XCTAssertFalse((caldera.card?.doLine.lowercased() ?? "").contains("edible"), caldera.card?.doLine ?? "")

        let curtin = try hold(at: Self.curtinWetland, zoom: 16, packId: "nm")
        XCTAssertEqual(curtin.card?.klass, "Wildlife range", "\(curtin)")
        XCTAssertEqual(curtin.card?.title, "Leonora Curtin Wetland Preserve", "\(curtin)")
        XCTAssertNotEqual(curtin.card?.klass, "Bosque or wetland", "\(curtin)")
        XCTAssertNotEqual(curtin.card?.klass, "Open reserve", "\(curtin)")
        XCTAssertEqual(curtin.card?.fieldRoute.first, Inspect.mammalTXCard, "\(curtin)")
        XCTAssertFalse((curtin.card?.doLine.lowercased() ?? "").contains("cottonwood"), curtin.card?.doLine ?? "")
        XCTAssertFalse((curtin.card?.doLine.lowercased() ?? "").contains("edible"), curtin.card?.doLine ?? "")

        let canyon = try hold(at: Self.santaFeCanyon, zoom: 16, packId: "nm")
        XCTAssertEqual(canyon.card?.klass, "Wildlife range", "\(canyon)")
        XCTAssertEqual(canyon.card?.title, "Santa Fe Canyon Preserve", "\(canyon)")
        XCTAssertNotEqual(canyon.card?.klass, "Open reserve", "\(canyon)")
        XCTAssertEqual(canyon.card?.fieldRoute.first, Inspect.mammalTXCard, "\(canyon)")
        XCTAssertFalse((canyon.card?.doLine.lowercased() ?? "").contains("edible"), canyon.card?.doLine ?? "")

        let hawk = try hold(at: Self.hawkWatch, zoom: 16, packId: "nm")
        XCTAssertEqual(hawk.card?.klass, "Wildlife range", "\(hawk)")
        XCTAssertEqual(hawk.card?.title, "Hawk Watch Open Space", "\(hawk)")
        XCTAssertNotEqual(hawk.card?.klass, "Open reserve", "\(hawk)")
        XCTAssertEqual(hawk.card?.fieldRoute.first, Inspect.mammalTXCard, "\(hawk)")
        XCTAssertFalse((hawk.card?.doLine.lowercased() ?? "").contains("edible"), hawk.card?.doLine ?? "")

        let history = try hold(at: Self.sandiaHistory, zoom: 16, packId: "nm")
        XCTAssertEqual(history.card?.klass, "Wildlife range", "\(history)")
        XCTAssertEqual(history.card?.title, "Sandia Mountain Natural History Center", "\(history)")
        XCTAssertNotEqual(history.card?.klass, "Open reserve", "\(history)")
        XCTAssertEqual(history.card?.fieldRoute.first, Inspect.mammalTXCard, "\(history)")
        XCTAssertFalse((history.card?.doLine.lowercased() ?? "").contains("edible"), history.card?.doLine ?? "")

        let bernardo = try hold(at: Self.bernardoWMA, zoom: 16, packId: "nm")
        XCTAssertEqual(bernardo.card?.klass, "Wildlife range", "\(bernardo)")
        XCTAssertEqual(bernardo.card?.title, "Bernardo Wildlife Management Area", "\(bernardo)")
        XCTAssertNotEqual(bernardo.card?.klass, "Park", "\(bernardo)")
        XCTAssertNotEqual(bernardo.card?.title, "Bernardo Trails Park", "\(bernardo)")
        XCTAssertEqual(bernardo.card?.fieldRoute.first, Inspect.mammalTXCard, "\(bernardo)")
        XCTAssertTrue(
            bernardo.card?.fieldRoute.contains(Inspect.mammalNMCard) ?? false,
            "Bernardo WMA dropped the NM mammal card: \(bernardo)"
        )
        XCTAssertTrue((bernardo.card?.doLine.lowercased() ?? "").contains("elk is high country"), bernardo.card?.doLine ?? "")
        XCTAssertFalse((bernardo.card?.doLine.lowercased() ?? "").contains("javelina"), bernardo.card?.doLine ?? "")
        XCTAssertFalse((bernardo.card?.doLine.lowercased() ?? "").contains("edible"), bernardo.card?.doLine ?? "")
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

        let mouth = try hold(at: Self.sandiaManCave, zoom: 16, packId: "nm")
        XCTAssertEqual(mouth.card?.klass, "Cave or hole", "\(mouth)")
        XCTAssertEqual(mouth.card?.title, "Sandia Man Cave", "\(mouth)")
        XCTAssertEqual(mouth.card?.fieldRoute.first, Inspect.caveCard, "\(mouth)")
        XCTAssertFalse((mouth.card?.doLine.lowercased() ?? "").contains("edible"), mouth.card?.doLine ?? "")

        let embudo = try hold(at: Self.embudoCave, zoom: 16, packId: "nm")
        XCTAssertEqual(embudo.card?.klass, "Cave or hole", "\(embudo)")
        XCTAssertEqual(embudo.card?.title, "Embudo Cave", "\(embudo)")
        XCTAssertNotEqual(embudo.card?.klass, "Park", "\(embudo)")
        XCTAssertNotEqual(embudo.card?.title, "Embudo Hills Park", "\(embudo)")
        XCTAssertEqual(embudo.card?.fieldRoute.first, Inspect.caveCard, "\(embudo)")
        XCTAssertTrue((embudo.card?.doLine.lowercased() ?? "").contains("stay in daylight"), embudo.card?.doLine ?? "")
        XCTAssertFalse((embudo.card?.doLine.lowercased() ?? "").contains("edible"), embudo.card?.doLine ?? "")

        let bear = try hold(at: Self.bearCave, zoom: 16, packId: "nm")
        XCTAssertEqual(bear.card?.klass, "Cave or hole", "\(bear)")
        XCTAssertEqual(bear.card?.title, "Bear Cave", "\(bear)")
        XCTAssertEqual(bear.card?.fieldRoute.first, Inspect.caveCard, "\(bear)")
        XCTAssertTrue((bear.card?.doLine.lowercased() ?? "").contains("stay in daylight"), bear.card?.doLine ?? "")
        XCTAssertFalse((bear.card?.doLine.lowercased() ?? "").contains("edible"), bear.card?.doLine ?? "")
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
        XCTAssertTrue(doLine.contains("elk is high country"), held.card?.doLine ?? "")
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

    func testHoldingEastScrubOpensBiteNotPicnicWoodland() throws {
        let held = try hold(at: Self.eastScrub, zoom: 16, packId: "tx-east")
        XCTAssertEqual(held.card?.klass, "Desert scrub", "ordinary east cover is viper country: \(held)")
        XCTAssertEqual(held.card?.title, "Unnamed", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.snakeEastCard, "\(held)")
        XCTAssertNotEqual(
            held.card?.fieldRoute.first,
            Inspect.treeUseEastCard,
            "east scrub opened picnic woodland: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("hog"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it room"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("sotol"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("live oak"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("food card"), held.card?.doLine ?? "")
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

    func testHoldingNewMexicoScrubOpensRattlerNotPicnicWoodland() throws {
        let held = try hold(at: Self.nmScrub, zoom: 16, packId: "nm")
        XCTAssertEqual(held.card?.klass, "Open reserve", "ordinary NM cover is viper country: \(held)")
        XCTAssertEqual(held.card?.title, "Jemez National Recreation Area", "\(held)")
        XCTAssertEqual(held.card?.fieldRoute.first, Inspect.snakeTXCard, "\(held)")
        XCTAssertTrue(
            held.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "NM scrub dropped the NM snake card: \(held)"
        )
        XCTAssertNotEqual(
            held.card?.fieldRoute.first,
            Inspect.treeUseNMCard,
            "NM scrub opened picnic woodland: \(held)"
        )
        let doLine = held.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(doLine.contains("rattler") || doLine.contains("diamondback"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("sotol") || doLine.contains("cholla"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("give it room"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("no ice"), held.card?.doLine ?? "")
        XCTAssertTrue(doLine.contains("bite card"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("javelina"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonmouth"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("cottonwood"), held.card?.doLine ?? "")
        XCTAssertFalse(doLine.contains("food card"), held.card?.doLine ?? "")
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
        XCTAssertEqual(
            InspectField.bookLine(for: InspectField.presentRoute(
                held.card?.fieldRoute ?? [],
                in: nmBook
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
            ("lush n lean garden", Self.lushNLean, 16.0),
            ("desert gardens", Self.desertGardens, 16.0),
            ("japaneese garden", Self.japaneeseGarden, 16.0),
            ("preston foster", Self.prestonFoster, 16.0),
            ("4th street garden", Self.fourthStreetGarden, 16.0),
            ("alamogordo community garden", Self.alamogordoGarden, 16.0),
            ("glasshouse", Self.glasshouse, 16.0),
            ("open reserve", Self.openReserve, 16.0),
            ("franklin reserve", Self.franklinReserve, 16.0),
            ("west wildlife", Self.westWildlife, 16.0),
            ("jornada range", Self.jornadaRange, 16.0),
            ("sinkhole", Self.sinkhole, 16.0),
            ("anthony gap cave", Self.anthonyGapCave, 16.0),
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
