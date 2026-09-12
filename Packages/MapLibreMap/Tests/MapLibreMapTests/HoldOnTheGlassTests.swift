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
/// `layers/ground.geojson`. West wildlife range is Lost Dog, San Andres,
/// and Feather Lake, not invented pins. Animals as range are also held on an east sanctuary
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

    /// Interior of Vickery Wholesale Greenhouse. Named glasshouse,
    /// not woodland tree-use. 137 m from OSM water. Daffan Lane 64 m
    /// is rank 7; glasshouse 5 still wins.
    private static let vickeryGlasshouse = CLLocationCoordinate2D(latitude: 30.313804, longitude: -97.617624)

    /// Interior of Alamo Mountain ACEC in `layers/ground.geojson`.
    private static let openReserve = CLLocationCoordinate2D(latitude: 32.032331, longitude: -105.633755)

    /// Interior of Franklin Mountains State Park. Named nature reserve, not
    /// picnic woodland. Peak pin still wins on Mount Franklin itself.
    private static let franklinReserve = CLLocationCoordinate2D(latitude: 31.97, longitude: -106.50)

    /// Interior of Castner Range National Monument. Named nature
    /// reserve, not picnic woodland. Unique versus Aztec Cave (4268 m),
    /// Lost Dog (7734 m), and the Franklin overlay Hold (8436 m).
    /// Castner Range peak is 205 m (rank 1) and stays a peak. Do not
    /// add matcher `castner`.
    private static let castnerRange = CLLocationCoordinate2D(latitude: 31.899542, longitude: -106.466848)

    /// Interior of Prehistoric Trackways National Monument. Named
    /// nature reserve, not picnic woodland. Robledo Loop 71 m is
    /// rank 7; open reserve 6 still wins. Unique versus Jornada
    /// (25878 m) and San Andres (52536 m). Nearest OSM water ~895 m.
    /// Organ Mountains nested wilderness leftovers stay unheld. Do
    /// not add matcher `trackways`.
    private static let trackways = CLLocationCoordinate2D(latitude: 32.370257, longitude: -106.899018)

    /// Dry interior of White Sands National Park. Unique overlay at
    /// the pip. Unique versus the San Andres overlay Hold (16639 m).
    /// White Sands Missile Range S Route 287 stays a road. Do not
    /// add matcher `white sands`.
    private static let whiteSands = CLLocationCoordinate2D(latitude: 32.764181, longitude: -106.331193)

    /// Interior of Knapp Land Conservation Easement. Named nature
    /// reserve, not picnic woodland. Unique versus Castner (3493 m)
    /// and Aztec Cave (6608 m). Nearest OSM stream ~200 m. No nearby
    /// name in 250 m. Nested Organ Mountains wilderness leftovers
    /// stay unheld. Do not add matcher `knapp`.
    private static let knappEasement = CLLocationCoordinate2D(latitude: 31.868514, longitude: -106.472646)

    /// Dry interior of Wind Mountain ACEC. Unique overlay at the
    /// pip. Unique versus Alamo Mountain ACEC (11384 m). Wind
    /// Mountain peak is 239 m (rank 1) and stays a peak. Overlay
    /// containment is the nearby name. Do not add matcher `wind`.
    private static let windMountainACEC = CLLocationCoordinate2D(latitude: 32.025028, longitude: -105.513302)

    /// Dry interior of Rincon ACEC. Unique overlay at the pip. Unique
    /// versus the west glasshouse Hold (24113 m) and Jornada
    /// (25095 m). Rincon Arroyo ~1830 m. No nearby name in 250 m.
    /// Do not add matcher `rincon`.
    private static let rinconACEC = CLLocationCoordinate2D(latitude: 32.688643, longitude: -107.066794)

    /// Dry interior of Sacramento Escarpment ACEC. Unique overlay
    /// at the pip. Unique versus Alamogordo Community Garden (24133 m).
    /// No nearby name in 250 m. Do not add matcher `sacramento`.
    private static let sacramentoEscarpment = CLLocationCoordinate2D(latitude: 32.699176, longitude: -105.881342)

    /// Dry interior of Uvas Valley ACEC. Unique overlay at the pip.
    /// Vertex-avg sat 104 m from a stream; this interior is 412 m
    /// from OSM water. Unique versus Trackways (48927 m). Nested
    /// Sierra de las Uvas Wilderness stays unheld. Do not add matcher
    /// `uvas`.
    private static let uvasValleyACEC = CLLocationCoordinate2D(latitude: 32.419455, longitude: -107.416855)

    /// Interior of Thunder Canyon Conservation Easement. Named
    /// nature reserve, not picnic woodland. Sharondale Drive 71 m
    /// is rank 7; open reserve 6 still wins. Unique versus Mount
    /// Franklin (1569 m) and Knapp (5126 m). Thunder Crest Lane
    /// stays a road. Do not add matcher `thunder`.
    private static let thunderCanyon = CLLocationCoordinate2D(latitude: 31.834020, longitude: -106.508651)

    /// Dry interior of Cornundas Mountain ACEC. Named nature reserve,
    /// not picnic woodland. County Road F022 51 m is rank 7; open
    /// reserve 6 still wins. Unique versus Wind Mountain ACEC (6450 m).
    /// Cornudas Mountain peak 1251 m stays a peak. OSM spelling
    /// Cornundas. Do not add matcher `cornundas` or `cornudas`.
    private static let cornundasACEC = CLLocationCoordinate2D(latitude: 32.082995, longitude: -105.510686)

    /// Dry interior of Florida Mountains Wilderness Study Area. Named
    /// nature reserve, not wildlife range. Unique overlay at the pip.
    /// Unique versus Uvas Valley ACEC (49903 m). Nearest OSM stream
    /// ~3977 m. No nearby name in 250 m. Nested Florida Mountains ACEC
    /// stays unheld. Do not add matcher `florida`.
    private static let floridaMountainsWSA = CLLocationCoordinate2D(latitude: 32.014948, longitude: -107.646608)

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

    /// `Cueva del Indio` on the west place slice. A cave mouth, 1.3 km
    /// from Cueva del Apache so the probe does not mix them. 76 m
    /// from OSM wash; rank 1 still beats water.
    private static let cuevaDelIndio = CLLocationCoordinate2D(latitude: 31.690888, longitude: -106.581974)

    /// `Cueva del Apache` on the west place slice. A cave mouth, not the
    /// path `Cueva del Apache - La Ventana`. 126 m from OSM stream.
    private static let cuevaDelApache = CLLocationCoordinate2D(latitude: 31.702715, longitude: -106.583114)

    /// `Cueva la Ventana` on the west place slice. A cave mouth, 216 m
    /// from Cueva del Apache so the probe does not mix them. 165 m
    /// from OSM stream; rank 1 still beats water. The path
    /// `Cueva del Apache - La Ventana` stays a trail.
    private static let cuevaLaVentana = CLLocationCoordinate2D(latitude: 31.702077, longitude: -106.585274)

    /// `Geronimo` on the west place slice. A cave mouth inside Organ
    /// Mountains-Desert Peaks — rank 1 still beats the overlay.
    /// 258 m from OSM stream. No other cave mouth in the probe.
    private static let geronimoCave = CLLocationCoordinate2D(latitude: 32.457274, longitude: -106.917562)

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
    /// Lime Creek Road Sink is 443 m off this pip. Under Three Oaks
    /// is 385 m off this pip. Jumbled Rocks is held 255 m off this
    /// pip — rank 1 still beats the overlay.
    private static let cavePreserve = CLLocationCoordinate2D(latitude: 30.490391, longitude: -97.855063)

    /// Interior of Buttercup Creek Cave Preserve. Phrase `cave
    /// preserve`. Listed centroid sits 71 m from Stone Well #1, a
    /// cave mouth — rank 1 beats cave overlay 3. This interior is
    /// unique, 277 m from OSM water. Good Friday is held 141 m off
    /// this pip — rank 1 still beats the overlay. Blowhole is 412 m
    /// off this pip. Cedar Elm Sink is 270 m off this pip. Nelson
    /// Ranch Road 24 m is rank 7; cave 3 still wins.
    private static let buttercupCave = CLLocationCoordinate2D(latitude: 30.498830, longitude: -97.841827)

    /// `Pepper Rock Cave` on the east place slice. A cave mouth,
    /// not Pepper Rock Park. 147 m from a tap; rank 1 still beats
    /// water. Chatham Wood Drive 56 m is rank 7.
    private static let pepperRockCave = CLLocationCoordinate2D(latitude: 30.496964, longitude: -97.740832)

    /// `Airmen's Cave` on the east place slice. A cave mouth.
    /// 24 m from Barton Creek; rank 1 still beats water. Unique
    /// versus Backdoor Cave.
    private static let airmenCave = CLLocationCoordinate2D(latitude: 30.241656, longitude: -97.791675)

    /// `Tree House Cave` on the east place slice. A cave mouth off
    /// the Buttercup overlay sheet. 46 m from the river; rank 1
    /// still beats water. Andrew Cove 94 m is rank 7. Unique versus
    /// the Buttercup overlay Hold. Warton Whirlpool is 326 m off
    /// this pip. Godzilla Cave stays unheld —
    /// Link's sits 84 m off that mouth and the probe would mix them.
    private static let treeHouseCave = CLLocationCoordinate2D(latitude: 30.498201, longitude: -97.837346)

    /// `Hideaway` on the east place slice. A cave mouth inside
    /// Westside Preserve — rank 1 still beats the overlay. Nelson
    /// Ranch Loop 73 m is rank 7. Unique versus the Buttercup overlay
    /// Hold. Off the cave-overlay sheet. No other mouth in 120 m.
    /// Buttercup Drain Cave is 392 m off this pip.
    private static let hideawayCave = CLLocationCoordinate2D(latitude: 30.494247, longitude: -97.84547)

    /// `Buttercup Wind` on the east place slice. A cave mouth off
    /// the Buttercup overlay sheet. Shea Drive and Lauren Trail are
    /// rank 7. Unique versus Discovery Well overlay Hold. Godzilla
    /// Cave stays unheld — Link's sits 84 m off that mouth.
    private static let buttercupWindCave = CLLocationCoordinate2D(latitude: 30.494273, longitude: -97.853218)

    /// `Buttercup Blowhole` on the east place slice. A cave mouth
    /// on the Buttercup overlay sheet — rank 1 still beats the
    /// overlay. Unique versus the Buttercup overlay Hold (412 m)
    /// and Tree House Cave (228 m). Stone Well #2 is 154 m off this
    /// pip. Buttercup Creek Boulevard 56 m is rank 7.
    private static let buttercupBlowhole = CLLocationCoordinate2D(latitude: 30.496429, longitude: -97.838549)

    /// `Lime Creek Road Sink` on the east place slice. A cave mouth
    /// on the Discovery Well overlay sheet — rank 1 still beats
    /// the overlay. Unique versus the Discovery Well overlay Hold
    /// (443 m) and Buttercup Wind (494 m). Persimmon Well is 277 m
    /// off this pip. Anderson Mill Road 93 m is rank 7. Blue Loop
    /// stays a trail. Lime Creek Road itself is 395 m off this pip.
    /// Under Three Oaks is 800 m off this pip.
    private static let limeCreekRoadSink = CLLocationCoordinate2D(latitude: 30.493286, longitude: -97.858242)

    /// `Cedar Elm Sink` on the east place slice. A cave mouth
    /// on the Buttercup overlay sheet — rank 1 still beats the
    /// overlay. Unique versus Buttercup Blowhole (189 m) and
    /// the Buttercup overlay Hold. Pat's Pit is 131 m off this
    /// pip. Good Friday is 165 m off this pip. Anna Court 93 m
    /// is rank 7. Cedar Elm Preserve Trail stays a trail. Brook
    /// Meadow Trail is residential, a road.
    private static let cedarElmSink = CLLocationCoordinate2D(latitude: 30.496675, longitude: -97.840497)

    /// `Under Three Oaks` on the east place slice. A cave mouth
    /// on the Discovery Well overlay sheet — rank 1 still beats
    /// the overlay. Unique versus the Discovery Well overlay Hold
    /// (385 m) and Lime Creek Road Sink. Anderson Mill Road 54 m
    /// is rank 7. Blue Loop (Three Oaks) stays a trail.
    private static let underThreeOaks = CLLocationCoordinate2D(latitude: 30.486996, longitude: -97.854268)

    /// `Buttercup Drain Cave` on the east place slice. A cave
    /// mouth inside Westside Preserve — rank 1 still beats the
    /// overlay. Off the Buttercup overlay sheet. Unique versus
    /// Hideaway. Kai Drive 94 m is rank 7. A 1 m drain is rank
    /// 2; the mouth still wins. No other mouth in 120 m.
    private static let buttercupDrainCave = CLLocationCoordinate2D(latitude: 30.491100, longitude: -97.847304)

    /// `Warton Whirlpool` on the east place slice. A cave mouth
    /// off the Buttercup overlay sheet. Unique versus Tree House
    /// Cave (326 m). Janet Bartles Park stays Park. Buttercup
    /// Creek Boulevard 28 m is rank 7. A 3 m stream is rank 2;
    /// the mouth still wins.
    private static let wartonWhirlpool = CLLocationCoordinate2D(latitude: 30.498651, longitude: -97.833984)

    /// `Pat's Pit` on the east place slice. A cave mouth on the
    /// Buttercup overlay sheet — rank 1 still beats the overlay.
    /// Unique versus Buttercup Blowhole (169 m) and Cedar Elm
    /// Sink (131 m). Anna Court 89 m is rank 7. Andrew Cove stays
    /// a road.
    private static let patsPitCave = CLLocationCoordinate2D(latitude: 30.497611, longitude: -97.839661)

    /// `Good Friday` on the east place slice. A cave mouth on the
    /// Buttercup overlay sheet — rank 1 still beats the overlay.
    /// Unique versus the Buttercup overlay Hold (141 m) and
    /// Cedar Elm Sink (165 m). Cedar Elm Preserve Trail 4 m is
    /// rank 7. Brook Meadow Trail is residential, a road. Anna
    /// Court stays a road. 405 m from OSM water.
    private static let goodFriday = CLLocationCoordinate2D(latitude: 30.497564, longitude: -97.841872)

    /// `Persimmon Well` on the east place slice. A cave mouth on
    /// the Discovery Well overlay sheet — rank 1 still beats the
    /// overlay. Unique versus Lime Creek Road Sink (277 m) and
    /// Jumbled Rocks (143 m) — Jumbled Rocks is held. Red Loop
    /// stays a trail. No named street in 110 m; overlay
    /// containment counts.
    private static let persimmonWell = CLLocationCoordinate2D(latitude: 30.490903, longitude: -97.859084)

    /// `Jumbled Rocks` on the east place slice. A cave mouth on the
    /// Discovery Well overlay sheet — rank 1 still beats the overlay.
    /// Unique versus Persimmon Well (143 m) and the Discovery Well
    /// overlay Hold (255 m). Mix Unmarked Cave 126 m is outside the
    /// probe. Red Loop stays a trail. Blue Loop stays a trail.
    /// Zig Zag stays unheld. 278 m from OSM water.
    private static let jumbledRocks = CLLocationCoordinate2D(latitude: 30.490379, longitude: -97.857723)

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

    /// Interior of Village of Western Oaks Karst Preserve and Watershed
    /// Management Area. Phrase `karst preserve`. Listed hunt sat on
    /// water. This interior is 140 m from Tiombe Branch. La Cresada
    /// Drive 12 m is rank 7; cave overlay 3 still wins. Davis Lane
    /// stays a road. No named mouth on the sheet.
    private static let westernOaksKarst = CLLocationCoordinate2D(latitude: 30.208365, longitude: -97.864477)

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
    /// Loma El Gato is held 11744 m off this pip — rank 1 still
    /// beats the overlay.
    private static let floraFauna = CLLocationCoordinate2D(latitude: 31.247021, longitude: -106.450970)

    /// Interior of Barton Creek Wilderness Park. Phrase `wilderness park`,
    /// not picnic woodland. 442 m from water.
    private static let bartonWilderness = CLLocationCoordinate2D(latitude: 30.243962, longitude: -97.815694)

    /// Interior of Balcones Canyonlands Preserve — Grandview Hills.
    /// Phrase `canyonlands preserve`, not Open reserve, not a trail park.
    private static let canyonlandsPreserve = CLLocationCoordinate2D(latitude: 30.416444, longitude: -97.864868)

    /// Interior of Balcones Canyonlands Preserve - Blackmore. Phrase
    /// `canyonlands preserve`. Unique title, not Grandview Hills.
    /// 193 m from OSM stream. Bullick Hollow Road 120 m is rank 7;
    /// wildlife 4 still wins.
    private static let blackmorePreserve = CLLocationCoordinate2D(latitude: 30.408712, longitude: -97.860602)

    /// Interior of Balcones Canyonlands Preserve - Lake Perspectives.
    /// Phrase `canyonlands preserve`. Unique title. 137 m from
    /// Bullick Hollow. Cuevas East is a separate sheet, 1.9 km
    /// off this pip.
    private static let lakePerspectives = CLLocationCoordinate2D(latitude: 30.420633, longitude: -97.872138)

    /// Interior of Valles Caldera National Preserve. Phrase `national
    /// preserve`. Elk country, not Open reserve. San Antonio
    /// Mountain is held 16092 m off this pip — rank 1 still
    /// beats the overlay.
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

    /// Interior of Stephenson Nature Preserve And Outdoor Education
    /// Center. Phrase `stephenson nature`, not the word
    /// `stephenson`. The `nature preserve` phrase already matches
    /// that sheet. Vertex-avg sits 87 m from wetland — water would
    /// win. This interior is 328 m from wetland. Bloomfield Drive
    /// 70 m is rank 7; wildlife 4 still wins.
    private static let stephensonPreserve = CLLocationCoordinate2D(latitude: 30.205991, longitude: -97.827853)

    /// Interior of Onion Creek Wildlife Sanctuary. Phrase `onion
    /// creek wildlife`, not the word `onion`. Onion Creek Drive
    /// stays a road. Onion Creek Management Unit is a separate
    /// sheet. 121 m from OSM water.
    private static let onionCreekSanctuary = CLLocationCoordinate2D(latitude: 30.200680, longitude: -97.615670)

    /// Interior of Mary Gay Maxwell Management Unit. Phrase `mary
    /// gay maxwell`. The `management unit` phrase already matches
    /// that sheet. 256 m from Slaughter Creek. Slaughter Creek Trail
    /// 133 m is rank 7; wildlife 4 still wins.
    private static let maryGayMaxwell = CLLocationCoordinate2D(latitude: 30.204777, longitude: -97.900751)

    /// Interior of Onion Creek Management Unit. Phrase `onion
    /// creek management`, not the word `onion`. 243 m from OSM
    /// stream.
    private static let onionCreekUnit = CLLocationCoordinate2D(latitude: 30.065560, longitude: -97.944464)

    /// Interior of Bull Creek Management Unit. Phrase `bull creek
    /// management`, not the word `bull`. Bull Creek West Loop 76 m
    /// is rank 7; wildlife 4 still wins. 192 m from Bull Creek.
    private static let bullCreekUnit = CLLocationCoordinate2D(latitude: 30.387998, longitude: -97.772249)

    /// Interior of Lower Barton Creek Management Unit. Phrase
    /// `lower barton creek`, not the word `barton`. Habitat
    /// Preserve and Wilderness Park stay their own. Listed hunt
    /// pip sits 13 m from an unnamed stream — water wins. This
    /// interior is unique, 361 m from OSM water. Circle Drive
    /// 72 m is rank 7; wildlife 4 still wins.
    private static let lowerBartonUnit = CLLocationCoordinate2D(latitude: 30.243478, longitude: -97.938144)

    /// Interior of Little Bear Creek Management Unit. Vertex-avg
    /// sits off the sheet. This interior is unique wildlife overlay,
    /// 844 m from OSM water. Phrase `little bear creek`. The
    /// `management unit` phrase already matches that sheet.
    private static let littleBearUnit = CLLocationCoordinate2D(latitude: 30.098137, longitude: -97.928628)

    /// Interior of Barrow Nature Preserve. Vertex-avg sits off the
    /// sheet. This interior is unique overlay, but an unnamed
    /// stream sits 24 m off the pip — water rank 2 beats wildlife
    /// 4. Every sampled interior is under 45 m from water. West
    /// Rim Cove stays a road. Phrase `nature preserve`.
    private static let barrowPreserve = CLLocationCoordinate2D(latitude: 30.371582, longitude: -97.767601)

    /// Interior of Wild Basin Wilderness Preserve. Phrase `wild
    /// basin wilderness`, not the word `basin`. The `wilderness
    /// preserve` phrase already matches that sheet. Listed
    /// centroid sits 20 m from water. This interior is unique,
    /// 110 m from OSM water. North Capital of Texas Highway 94 m
    /// is rank 7; wildlife 4 still wins.
    private static let wildBasin = CLLocationCoordinate2D(latitude: 30.318096, longitude: -97.820597)

    /// Interior of Stillhouse Hollow Nature Preserve. Phrase
    /// `stillhouse hollow`. The `nature preserve` phrase already
    /// matches that sheet. Listed centroid sits 22 m from water.
    /// This interior is unique, 297 m from OSM water. Sterling
    /// Drive 26 m is rank 7; wildlife 4 still wins.
    private static let stillhouseHollow = CLLocationCoordinate2D(latitude: 30.369023, longitude: -97.761957)

    /// Interior of Big Walnut Creek Nature Preserve. Phrase `big
    /// walnut creek`, not the word `walnut`. The `nature
    /// preserve` phrase already matches that sheet. Listed
    /// centroid sits 39 m from Walnut Creek. This interior is
    /// unique, 141 m from OSM water. Ferguson Cutoff 163 m is
    /// rank 7; wildlife 4 still wins.
    private static let bigWalnut = CLLocationCoordinate2D(latitude: 30.326237, longitude: -97.651732)

    /// Interior of Shady Hollow West Nature Preserve. Phrase
    /// `shady hollow west`, not the word `shady`. Lost Oasis
    /// Hollow stays a road. Bear Creek Management Unit is a
    /// separate sheet. Vertex-avg sits 88 m from water. This
    /// interior is unique, 113 m from OSM water. Lost Oasis Hollow
    /// 54 m is rank 7; wildlife 4 still wins.
    private static let shadyHollowWest = CLLocationCoordinate2D(latitude: 30.167029, longitude: -97.873372)

    /// Interior of Bright Leaf Natural Area. Phrase `natural area`.
    /// Listed centroid sits 90 m from OSM water. This interior is
    /// unique, 259 m from OSM water. Mount Lucas is held 197 m off
    /// this pip — rank 1 still beats the overlay. Mount Bonnell
    /// Road 77 m is rank 7; wildlife 4 still wins.
    private static let brightLeaf = CLLocationCoordinate2D(latitude: 30.328746, longitude: -97.774978)

    /// Interior of Red Bluff Nature Preserve. Phrase `nature
    /// preserve`, not the word `bluff`. Listed centroid sits 19 m
    /// from water. The neighborhood park sits on another interior.
    /// This interior is unique, 252 m from OSM water. DC Moore
    /// Addition 14 m is rank 8; wildlife 4 still wins. Prock Lane
    /// 62 m is rank 7.
    private static let redBluff = CLLocationCoordinate2D(latitude: 30.266661, longitude: -97.681788)

    /// Interior of Blunn Creek Nature Preserve. Phrase `nature
    /// preserve`, not the word `blunn`. Listed hunt sat on water.
    /// This interior is 248 m from OSM stream. East Oltorf Street
    /// 44 m is rank 7; wildlife 4 still wins.
    private static let blunnCreek = CLLocationCoordinate2D(latitude: 30.235167, longitude: -97.745515)

    /// Interior of Balcones Canyonlands Preserve - Austin Simon.
    /// Phrase `canyonlands preserve`. Unique title, not Grandview
    /// Hills, not Lime Creek.
    private static let austinSimonPreserve = CLLocationCoordinate2D(latitude: 30.495907, longitude: -97.877569)

    /// Interior of Balcones Canyonlands Preserve - Lime Creek.
    /// Phrase `canyonlands preserve`. Unique title. Austin Simon
    /// is 141 m off this pip, outside the z16 probe.
    private static let limeCreekPreserve = CLLocationCoordinate2D(latitude: 30.490657, longitude: -97.871229)

    /// Interior of Balcones Canyonlands Preserve - Romberg. Phrase
    /// `canyonlands preserve`. Unique title. Bob Wentz Park sits
    /// on the listed hunt pip. This interior is unique, 250 m
    /// from OSM water. McGregor is 144 m off this pip, outside the
    /// z16 probe. Comanche Trail 94 m is rank 7; wildlife 4 still
    /// wins.
    private static let rombergPreserve = CLLocationCoordinate2D(latitude: 30.420315, longitude: -97.894690)

    /// Interior of Balcones Canyonlands Preserve - McGregor. Phrase
    /// `canyonlands preserve`. Hippie Hollow Park sits on another
    /// interior. This interior is unique, 312 m from OSM stream.
    /// Romberg is 135 m off this pip, outside the z16 probe.
    /// Comanche Trail 81 m is rank 7; wildlife 4 still wins.
    private static let mcgregorPreserve = CLLocationCoordinate2D(latitude: 30.421875, longitude: -97.894955)

    /// Interior of Balcones Canyonlands Preserve - Cuevas East.
    /// Phrase `canyonlands preserve`. Unique title, not Cuevas,
    /// not Blackmore. SE interior is 200 m from the Cuevas sheet
    /// and 308 m from Blackmore, outside the z16 probe. 215 m from
    /// OSM water. Ranch Road 620 North 40 m is rank 7; wildlife
    /// 4 still wins. Four Points Drive 100 m is rank 7. Cuevas
    /// interiors sit on water. TSNL stays unheld — Grandview is
    /// in that probe.
    private static let cuevasEastPreserve = CLLocationCoordinate2D(latitude: 30.405959, longitude: -97.853307)

    /// Interior of Hawk Watch Open Space. Phrase `hawk watch`, not
    /// picnic open space. 449 m from water.
    private static let hawkWatch = CLLocationCoordinate2D(latitude: 35.069828, longitude: -106.424820)

    /// Interior of Jornada Experimental Range. Phrase `experimental
    /// range`, not Open reserve. Far from water.
    private static let jornadaRange = CLLocationCoordinate2D(latitude: 32.594082, longitude: -106.823441)

    /// Interior of Charlie Wakeem/Richard Teschner Nature Preserve of
    /// Resler Canyon. Phrase `nature preserve`, not the word `charlie`
    /// or `resler`. Listed hunt sat on water. This interior is 220 m
    /// from OSM stream. Cadiz Street 54 m is rank 7; wildlife 4 still
    /// wins. Fiesta Drive stays a road.
    private static let charlieWakeem = CLLocationCoordinate2D(latitude: 31.831091, longitude: -106.543456)

    /// Interior of Feather Lake Wildlife Refuge. Phrase `wildlife
    /// refuge`. Ditches sit on most of the sheet. This corner is 203 m
    /// from Bowman Lateral. Nottingham Drive 64 m is rank 7;
    /// wildlife 4 still wins. Envoy Way stays a road. Do not add
    /// matcher `feather`.
    private static let featherLakeRefuge = CLLocationCoordinate2D(latitude: 31.690659, longitude: -106.305767)

    /// Interior of San Andres National Wildlife Refuge. Phrase
    /// `national wildlife`, not the word `andres`. White Sands
    /// Missile Range S Route 287 stays a road. San Andres Peak is
    /// held 5032 m off this pip — rank 1 still beats the overlay.
    /// Bennett Mountain is held 14199 m off this pip — rank 1
    /// still beats the overlay. Big Brushy Mountain is held
    /// 10496 m off this pip — rank 1 still beats the overlay.
    /// Gardner Peak is held 16750 m off this pip — rank 1 still
    /// beats the overlay. Unique overlay.
    private static let sanAndres = CLLocationCoordinate2D(latitude: 32.688003, longitude: -106.484294)

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

    /// Interior of Bastrop Community Garden. Phrase `bastrop
    /// community`, not the word `bastrop`. The `community garden`
    /// phrase already matches that sheet. Bastrop Street stays a
    /// road. Bastrop State Park stays Park. Main Street 32 m is
    /// rank 7; botanic 5 still wins. 168 m from OSM tap.
    private static let bastropGarden = CLLocationCoordinate2D(latitude: 30.112298, longitude: -97.319724)

    /// Interior of Fort Dessau Community Garden. Phrase `fort
    /// dessau`, not the word `dessau`. Fort Dessau Road stays a
    /// road. Fort Dessau Amenity Center stays Park. 216 m from
    /// OSM water. Fort Dessau Road 61 m is rank 7; botanic 5 still
    /// wins.
    private static let fortDessauGarden = CLLocationCoordinate2D(latitude: 30.410049, longitude: -97.639508)

    /// Interior of Windsor Park Community Garden. Phrase `windsor
    /// park community`, not the word `windsor`. 228 m from OSM
    /// stream. Belmoor Drive 75 m is rank 7; botanic 5 still wins.
    private static let windsorParkGarden = CLLocationCoordinate2D(latitude: 30.312078, longitude: -97.689633)

    /// Interior of Lamplight Community Garden. Phrase `lamplight
    /// community`, not the word `lamplight`. Lamplight Village
    /// Avenue stays a road. 217 m from OSM water. Alderbrook Drive
    /// 22 m is rank 7; botanic 5 still wins.
    private static let lamplightGarden = CLLocationCoordinate2D(latitude: 30.415015, longitude: -97.697356)

    /// Interior of Juan Navarro High School Community Garden. Phrase
    /// `juan navarro`, not the word `navarro`. 211 m from OSM
    /// water. Fairfield Drive 36 m is rank 7; botanic 5 still wins.
    private static let juanNavarroGarden = CLLocationCoordinate2D(latitude: 30.358187, longitude: -97.706305)

    /// Interior of Unity Park Community Garden. Phrase `unity park
    /// community`, not the word `unity`. 126 m from OSM stream.
    /// Gattis School Road 62 m is rank 7; botanic 5 still wins.
    private static let unityParkGarden = CLLocationCoordinate2D(latitude: 30.496824, longitude: -97.644199)

    /// Interior of Colorado Community Garden. Phrase `colorado
    /// community`, not the word `colorado`. Colorado River Park
    /// Wildlife Sanctuary stays wildlife. Borger Street 15 m is
    /// rank 7; botanic 5 still wins. 217 m from OSM stream. 970 m
    /// from Zilker.
    private static let coloradoGarden = CLLocationCoordinate2D(latitude: 30.278396, longitude: -97.775309)

    /// Interior of Colorado River Park Wildlife Sanctuary. Phrase
    /// `colorado river park wildlife`. The `wildlife sanctuary`
    /// phrase already matches that sheet. Listed centroid sits
    /// 66 m from the Colorado River. This interior is unique,
    /// 185 m from the river. Levander Loop 28 m is rank 7;
    /// wildlife 4 still wins.
    private static let coloradoSanctuary = CLLocationCoordinate2D(latitude: 30.247020, longitude: -97.691879)

    /// Interior of Alamo Community Garden. Phrase `alamo
    /// community`, not the word `alamo`. Alamo Street stays a
    /// road. Alamo Pocket Park stays Park. 176 m from Este Garden
    /// so the probe does not mix them. Alamo Street 5 m is rank 7;
    /// botanic 5 still wins.
    private static let alamoGarden = CLLocationCoordinate2D(latitude: 30.282202, longitude: -97.719697)

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

    /// Interior of Memorial Rose Garden. Phrase `rose garden`.
    /// 245 m from Los Alamos Demonstration Garden so the probe does
    /// not mix them. 213 m from OSM drain. `Memorial Garden` stays out.
    private static let memorialRose = CLLocationCoordinate2D(latitude: 35.882522, longitude: -106.301719)

    /// Interior of La Mesa Neighborhood Community Garden. Phrase
    /// `la mesa neighborhood`, not `la mesa`. Paseo de la Mesa Open
    /// Space stays Open reserve. La Mesa Court stays a road. 512 m
    /// from OSM ditch.
    private static let laMesaGarden = CLLocationCoordinate2D(latitude: 35.080221, longitude: -106.563856)

    /// Interior of International District Community Garden. Phrase
    /// `international district`, not the word `international`. 301 m
    /// from OSM water.
    private static let internationalDistrictGarden = CLLocationCoordinate2D(latitude: 35.062299, longitude: -106.608226)

    /// Interior of Barelas Community Garden. Phrase `barelas
    /// community`, not the word `barelas`. 4th Street Southwest
    /// stays a road. The `community garden` phrase already matches
    /// that sheet. 528 m from OSM water. 4th Street Southwest
    /// 51 m is rank 7; botanic 5 still wins.
    private static let barelasGarden = CLLocationCoordinate2D(latitude: 35.078118, longitude: -106.653090)

    /// Interior of Colonia Prisma Community Garden. Phrase
    /// `community garden`, not the word `prisma` or `colonia`.
    /// Camino Rojo 28 m is rank 7; botanic 5 still wins. Vuelta
    /// Colorada stays a road. 145 m from OSM stream. Desert Garden
    /// Park stays unheld.
    private static let coloniaPrisma = CLLocationCoordinate2D(latitude: 35.627487, longitude: -106.047423)

    /// Interior of Sandia Mountain Natural History Center. Phrase
    /// `natural history`, not Open reserve. Far from water.
    private static let sandiaHistory = CLLocationCoordinate2D(latitude: 35.126801, longitude: -106.379801)

    /// `Treaty Oak` on the east place slice. A surveyed tree, shade and
    /// wood, not a meal.
    private static let treatyOak = CLLocationCoordinate2D(latitude: 30.271466, longitude: -97.755462)

    /// `Sorin Oak` on the east place slice. A surveyed tree, shade and
    /// wood, not a meal. Not Sorin Street. 267 m from OSM water.
    private static let sorinOak = CLLocationCoordinate2D(latitude: 30.229486, longitude: -97.75447)

    /// `Argus` on the east place slice. Named tree — shade and wood,
    /// not a meal. Arthur Stiles Road 48 m is rank 7. Johnston Terrace
    /// is built-up rank 8. 1035 m from a tap.
    private static let argusTree = CLLocationCoordinate2D(latitude: 30.258446, longitude: -97.680528)

    /// `Kim Bird Gebert Memorial Tree` on the east place slice. Named
    /// tree — shade and wood, not a meal. Silent Harbor Loop 90 m is
    /// rank 7. Lake Pflugerville Park is park rank 8. 276 m from a tap.
    private static let kimBirdTree = CLLocationCoordinate2D(latitude: 30.441822, longitude: -97.575189)

    /// Interior of Blowing Sink in east `layers/ground.geojson`. A wetland
    /// in the extract; phrase `blowing sink`, not a cave-preserve park.
    /// Vertex-avg covers the sheet. Streams and ways sit hundreds of metres off.
    private static let namedSink = CLLocationCoordinate2D(latitude: 30.193035, longitude: -97.850443)

    /// Interior of Decker Tallgrass Prairie Preserve. East open reserve —
    /// cottonmouth and hog, not west diamondback, not picnic woodland.
    /// Vertex-avg covers the sheet, far from Decker Creek and any named way.
    private static let eastOpenReserve = CLLocationCoordinate2D(latitude: 30.294331, longitude: -97.603942)

    /// Interior of Carrington's Prairie. East open reserve —
    /// cottonmouth and hog, not west diamondback. Trail West Drive
    /// 16 m is rank 7; open reserve 6 still wins. Unique versus
    /// Ladybird Wildflower Center (571 m) and Decker (22420 m).
    /// Sycamore Creek ~146 m. Do not add matcher `carrington`.
    private static let carringtonPrairie = CLLocationCoordinate2D(latitude: 30.247099, longitude: -97.830910)

    /// Interior of Indian Grass Prarie Preserve. East open reserve —
    /// cottonmouth and hog. OSM spelling `Prarie`. Violet Crown Trail
    /// 31 m is rank 7; open reserve 6 still wins. Unique versus Sunset
    /// Valley Nature Area (474 m) and Carrington's Prairie (2407 m).
    /// Williamson Creek ~219 m. Do not add matcher `indian grass` or
    /// `indian`.
    private static let indianGrassPrairie = CLLocationCoordinate2D(latitude: 30.225834, longitude: -97.826212)

    /// Interior of Albuquerque BioPark Botanic Garden in NM `layers/ground.geojson`.
    /// The listed centroid sits next to a pond; water outranks the sheet.
    /// This point is on the botanic polygon, away from water and named ways.
    private static let botanicGarden = CLLocationCoordinate2D(latitude: 35.093625, longitude: -106.680958)

    /// Interior of Harvey Cornell Rose Park. Phrase `harvey cornell`,
    /// botanic not picnic woodland, not Wildrose Park. Far from water.
    private static let cornellRose = CLLocationCoordinate2D(latitude: 35.670293, longitude: -105.946141)

    /// Interior of Marquez Wildlife Management Area in NM `layers/ground.geojson`.
    /// SOLO_QA 35.327562, −107.319389 is on the sheet and far from water or a way.
    /// Mesa Blanca is held 5246 m off this pip — rank 1 still
    /// beats the overlay. Cerritos de la Jolla de Santa Rosa is
    /// held 9111 m off this pip — rank 1 still beats the overlay.
    private static let nmWildlifeRange = CLLocationCoordinate2D(latitude: 35.327562, longitude: -107.319389)

    /// Interior of Bernardo Wildlife Management Area. Phrase `bernardo
    /// wildlife`, not the word `bernardo`. Bernardo Trails Park stays
    /// a park. Don Bernardo Road stays a road. 2316 m from OSM drain.
    private static let bernardoWMA = CLLocationCoordinate2D(latitude: 34.423426, longitude: -106.829413)

    /// Interior of Valle de Oro National Wildlife Refuge. Phrase
    /// `national wildlife`, not the word `valle`. Valle del Bosque
    /// Park stays Park. 159 m from OSM ditch.
    private static let valleDeOro = CLLocationCoordinate2D(latitude: 34.977244, longitude: -106.679397)

    /// Interior of La Joya Wildlife Management Area. Phrase `la
    /// joya wildlife`, not the word `joya`. Listed OSM centroid
    /// sits 26 m from a drain — water would win. This vertex-avg
    /// interior is unique overlay, 138 m from OSM ditch.
    private static let laJoyaWMA = CLLocationCoordinate2D(latitude: 34.334717, longitude: -106.861360)

    /// Interior of Rio Rancho Bosque Nature Preserve. Vertex-avg
    /// sits off the sheet. This interior is unique wildlife overlay,
    /// not bosque. Rio Rancho Bosque South Trail 42 m is rank 7;
    /// wildlife 4 still wins. Phrase `nature preserve`.
    private static let rioRanchoBosque = CLLocationCoordinate2D(latitude: 35.289327, longitude: -106.592122)

    /// Interior of Pecos River Complex Wildlife Management Areas.
    /// Phrase `wildlife management area`, not the word `pecos`.
    /// Listed river-adjacent hunt sits on water. This interior is
    /// unique, 587 m from the Pecos River. State Highway 63 76 m
    /// is rank 7; wildlife 4 still wins.
    private static let pecosComplex = CLLocationCoordinate2D(latitude: 35.701711, longitude: -105.688095)

    /// Interior of Rio Grande Nature Center State Park. Phrase
    /// `nature center`, not bosque. Listed centroid sits on the
    /// park ponds. This interior is unique, 323 m from the
    /// Riverside Drain. Calle del Bosque Northwest 74 m is rank
    /// 7; wildlife 4 still wins.
    private static let rioGrandeNature = CLLocationCoordinate2D(latitude: 35.124701, longitude: -106.683528)

    /// Interior of State Game Commission Land. Phrase `game
    /// commission`, not the word `game`. Listed pip sits 73 m
    /// from water. This interior is unique, 598 m from OSM drain.
    /// Rio Grande Stables Road 81 m is rank 7; wildlife 4 still
    /// wins. Other Game Commission sheets stay their own.
    private static let gameCommission = CLLocationCoordinate2D(latitude: 34.620499, longitude: -106.741123)

    /// Interior of Sevilleta National Wildlife Refuge. Phrase
    /// `national wildlife`, not the word `sevilleta`. Old Highway 85
    /// stays a road. Unique overlay. Dry interiors with no nearby name
    /// stay unheld; this pip sits on the named highway.
    private static let sevilleta = CLLocationCoordinate2D(latitude: 34.396837, longitude: -106.874225)

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

    /// `Cave of the Winds` on the NM place slice. A cave mouth, not the
    /// path `Cave of the Winds Trail`. 121 m from Los Alamos Canyon;
    /// rank 1 still beats water.
    private static let caveOfTheWinds = CLLocationCoordinate2D(latitude: 35.880941, longitude: -106.341764)

    /// `Painted Cave` on the NM place slice. A cave mouth, not
    /// Bandelier National Monument. 101 m from Capulin Creek; rank 1
    /// still beats water. Lower Capulin Trail 61 m is rank 7.
    private static let paintedCave = CLLocationCoordinate2D(latitude: 35.722425, longitude: -106.31994)

    /// `Hot Springs Cave` on the NM place slice. A cave mouth
    /// inside Jemez National Recreation Area — rank 1 still
    /// beats the overlay. 103 m from Jemez River; rank 1 still
    /// beats water. Soda Dam 107 m is rock, not the hole.
    /// Unique versus the Jemez overlay Hold on Cerro Pelado.
    /// Generic Cave and the two La Cueva stay unheld.
    private static let hotSpringsCave = CLLocationCoordinate2D(latitude: 35.791493, longitude: -106.687498)

    /// `Prosopis velutina / Velvet Mesquite` on the NM place slice.
    /// Named tree — shade and wood, not a meal. Landry Avenue
    /// Northwest 9 m is rank 7. 521 m from a well.
    private static let velvetMesquite = CLLocationCoordinate2D(latitude: 35.119023, longitude: -106.706073)

    /// `Prosopis torreyana / Western Honey Mesquite` on the NM
    /// place slice. Named tree — shade and wood, not a meal.
    /// Unique versus the Velvet Mesquite Hold (61 km). No
    /// nearby name in 200 m. 1045 m from OSM water. The other
    /// Western Honey Mesquite sits 69 m from Sandia Wash.
    /// Texas Honey Mesquite stays unheld — Pinus pinea sits
    /// 26 m off that tree. Do not add matcher `torreyana` or
    /// `honey mesquite`.
    private static let westernHoneyMesquite = CLLocationCoordinate2D(latitude: 35.511273, longitude: -106.234121)

    /// Interior of Randall Davey Audubon Center. NM wildlife range, not
    /// Open reserve.
    private static let randallDavey = CLLocationCoordinate2D(latitude: 35.688876, longitude: -105.884927)

    /// `Mount Franklin` on the west place slice. Peak pin still wins inside
    /// Franklin Mountains State Park. Animals as range are also Lost Dog.
    private static let westPeak = CLLocationCoordinate2D(latitude: 31.832051, longitude: -106.492210)

    /// `San Andres Peak` on the west place slice. A named peak on the
    /// San Andres overlay sheet — rank 1 still beats the overlay.
    /// Unique versus the San Andres overlay Hold (5032 m). Javelina
    /// as range, not hog.
    private static let sanAndresPeak = CLLocationCoordinate2D(latitude: 32.675918, longitude: -106.536111)

    /// `Bennett Mountain` on the west place slice. A named peak on the
    /// San Andres overlay sheet — rank 1 still beats the overlay.
    /// Unique versus the San Andres overlay Hold (14199 m) and
    /// San Andres Peak (13892 m). Overlay containment is the nearby
    /// name. Javelina as range, not hog. Goat Mountain stays unheld
    /// (two OSM peaks).
    private static let bennettMountain = CLLocationCoordinate2D(latitude: 32.560366, longitude: -106.479718)

    /// `Big Brushy Mountain` on the west place slice. A named
    /// peak on the San Andres overlay sheet — rank 1 still beats
    /// the overlay. Unique versus the San Andres overlay Hold
    /// (10496 m), Bennett Mountain (5561 m), and San Andres Peak
    /// (8802 m). Overlay containment is the nearby name. Unique
    /// title (one OSM peak). Nearest water ~1797 m. Javelina as
    /// range, not hog. Goat Mountain stays unheld (two OSM
    /// peaks). Do not add matcher `brushy` or `big brushy`.
    private static let bigBrushyMountain = CLLocationCoordinate2D(latitude: 32.598142, longitude: -106.518609)

    /// `Gardner Peak` on the west place slice. A named peak on
    /// the San Andres overlay sheet — rank 1 still beats the
    /// overlay. Unique versus the San Andres overlay Hold
    /// (16750 m), San Andres Peak (16632 m), Bennett Mountain
    /// (30292 m), and Big Brushy Mountain (25428 m). Overlay
    /// containment is the nearby name. Unique title (one OSM
    /// peak). Nearest water ~2253 m. Javelina as range, not hog.
    /// Goat Mountain stays unheld (two OSM peaks). Do not add
    /// matcher `gardner`.
    private static let gardnerPeak = CLLocationCoordinate2D(latitude: 32.823971, longitude: -106.561392)

    /// `Loma El Gato` on the west place slice. A named peak on the
    /// Samalayuca overlay sheet — rank 1 still beats the overlay.
    /// Unique versus the Samalayuca overlay Hold (11744 m).
    /// Javelina as range, not hog.
    private static let lomaElGato = CLLocationCoordinate2D(latitude: 31.235777, longitude: -106.573797)

    /// Interior of Jones Canyon ACEC in NM `layers/ground.geojson`. Open
    /// reserve, not Pronoun Cave — rattler and sotol, not a hole.
    private static let nmOpenReserve = CLLocationCoordinate2D(latitude: 35.846906, longitude: -107.025703)

    /// Interior of El Cerro de Los Lunas Preserve. Named nature reserve,
    /// not wildlife range. Sunrise Trail 125 m is rank 7; open reserve
    /// 6 still wins. Unique versus State Game Commission Land (20882 m).
    /// Do not add matcher `los lunas`.
    private static let elCerroLosLunas = CLLocationCoordinate2D(latitude: 34.803148, longitude: -106.794247)

    /// Dry interior of Galisteo Basin Preserve. Vertex-avg sits 24 m
    /// from water. This pip is 1364 m from OSM water. Unique versus
    /// Haozous Garden (15628 m). No nearby name in 250 m. Do not add
    /// matcher `galisteo`.
    private static let galisteoBasin = CLLocationCoordinate2D(latitude: 35.451490, longitude: -105.962032)

    /// Interior of Placitas Open Space. Named open-space cover, not
    /// picnic woodland. Pipeline Rd. Tr. 46 m is rank 7; open
    /// reserve 6 still wins. Unique versus Golden Open Space (14894 m).
    /// Do not add matcher `placitas`.
    private static let placitasOpenSpace = CLLocationCoordinate2D(latitude: 35.331544, longitude: -106.469276)

    /// Dry interior of Petroglyph National Monument. Unique overlay at
    /// the pip. Unique versus Paseo de la Mesa (2907 m). No nearby
    /// name in 250 m. Do not add matcher `petroglyph`.
    private static let petroglyphMonument = CLLocationCoordinate2D(latitude: 35.134837, longitude: -106.747963)

    /// Interior of Cerrillos Hills State Park. Named nature reserve.
    /// Coyote Trail 221 m is rank 7; open reserve 6 still wins.
    /// Unique versus Galisteo Basin (15335 m). Do not add matcher
    /// `cerrillos`.
    private static let cerrillosHills = CLLocationCoordinate2D(latitude: 35.454612, longitude: -106.131284)

    /// Dry interior of Ojito Wilderness. Named nature reserve, not
    /// wildlife range — phrase `wilderness preserve`, not the word
    /// `wilderness`. Unique overlay at the pip. Unique versus Cabezon
    /// WSA (16795 m). Do not add matcher `ojito`.
    private static let ojitoWilderness = CLLocationCoordinate2D(latitude: 35.517369, longitude: -106.915496)

    /// Dry interior of Cabezon Wilderness Study Area. Named nature
    /// reserve, not wildlife range. Unique overlay at the pip.
    /// Unique versus Ojito (16795 m) and Jones Canyon (28949 m). Do
    /// not add matcher `cabezon`.
    private static let cabezonWSA = CLLocationCoordinate2D(latitude: 35.590075, longitude: -107.078225)

    /// Dry interior of Kasha-Katuwe Tent Rocks National Monument.
    /// Unique overlay at the pip. Unique versus Valles Caldera
    /// (38477 m). Nearest OSM water ~460 m. Do not add matcher
    /// `tent rocks`.
    private static let tentRocks = CLLocationCoordinate2D(latitude: 35.655997, longitude: -106.419292)

    /// Dry interior of Pecos National Historical Park. Named nature
    /// reserve, not wildlife range. Representative pip sat 69 m from
    /// the Pecos River; this interior is 563 m from the river. Unique
    /// versus Pecos River Complex WMA (19532 m). No nearby name in
    /// 250 m. Do not add matcher `pecos`.
    private static let pecosHistorical = CLLocationCoordinate2D(latitude: 35.527945, longitude: -105.656464)

    /// Dry interior of Elk Springs ACEC. Named nature reserve, not
    /// wildlife range. Unique overlay at the pip. Unique versus Jones
    /// Canyon (8901 m). No nearby name in 250 m. Do not add matcher
    /// `elk springs` or `elk`.
    private static let elkSpringsACEC = CLLocationCoordinate2D(latitude: 35.859437, longitude: -106.928156)

    /// Dry interior of Chamisa Wilderness Study Area. Named nature
    /// reserve, not wildlife range. Unique overlay at the pip.
    /// Unique versus Cabezon WSA (16946 m). Cerro Chamisa Losa
    /// 4923 m stays a peak. No nearby name in 250 m. Do not add
    /// matcher `chamisa`.
    private static let chamisaWSA = CLLocationCoordinate2D(latitude: 35.536017, longitude: -107.253383)

    /// Dry interior of Tapia Canyon ACEC. Named nature reserve, not
    /// wildlife range. Griegos Road 193 m is rank 7; open reserve 6
    /// still wins. Unique versus Cabezon (14646 m) and Chamisa
    /// (6657 m). Cerro Salado 1263 m stays a peak. Do not add matcher
    /// `tapia`.
    private static let tapiaCanyonACEC = CLLocationCoordinate2D(latitude: 35.499193, longitude: -107.195388)

    /// Dry interior of Empedrado Wilderness Study Area. Named nature
    /// reserve, not wildlife range. San Luis Road 192 m is rank 7;
    /// open reserve 6 still wins. Unique versus Cabezon (10495 m).
    /// Arroyo Chico ~1230 m. Do not add matcher `empedrado`.
    private static let empedradoWSA = CLLocationCoordinate2D(latitude: 35.609314, longitude: -107.191865)

    /// Dry interior of Ignacio Chavez Wilderness Study Area. Named
    /// nature reserve, not wildlife range. Unique overlay at the pip.
    /// Unique versus Cabezon (25473 m). Mesa la Azabache 1158 m
    /// stays a peak. No nearby name in 250 m. Do not add matcher
    /// `ignacio` or `chavez`.
    private static let ignacioChavezWSA = CLLocationCoordinate2D(latitude: 35.609320, longitude: -107.358965)

    /// Dry interior of La Leña Wilderness Study Area. Named nature
    /// reserve, not wildlife range. Unique overlay at the pip.
    /// Unique versus Cabezon (16332 m). Nested San Luis Mesa ACEC
    /// stays unheld. No nearby name in 250 m. Do not add matcher
    /// `la leña` or `lena`.
    private static let laLenaWSA = CLLocationCoordinate2D(latitude: 35.679164, longitude: -107.221909)

    /// Dry interior of Sierra Ladrones Wilderness Study Area. Named
    /// nature reserve, not wildlife range. Unique overlay at the pip.
    /// Unique versus El Cerro de Los Lunas (52917 m). Ladrón Peak
    /// 5270 m and Cerro Colorado 8292 m stay peaks. Do not Hold
    /// Cerro Colorado. Do not add matcher `ladrones` or `ladron`.
    private static let sierraLadronesWSA = CLLocationCoordinate2D(latitude: 34.421613, longitude: -107.139863)

    /// Dry interior of Dome Wilderness. Named nature reserve, not
    /// wildlife range — phrase `wilderness preserve`, not the word
    /// `wilderness`. Unique overlay at the pip (not Jemez NRA, not
    /// Bandelier). Unique versus Painted Cave (4539 m) and Tent
    /// Rocks (11331 m). Saint Peter's Dome 1535 m stays a peak. No
    /// nearby name in 250 m. Do not add matcher `dome`.
    private static let domeWilderness = CLLocationCoordinate2D(latitude: 35.746173, longitude: -106.360843)

    /// Dry interior of Manzano Mountain Wilderness. Named nature
    /// reserve, not wildlife range. Unique overlay at the pip.
    /// Unique versus El Cerro de Los Lunas (37586 m). Osha Peak
    /// 1130 m stays a peak. Nested Manzano WSA stays unheld. No
    /// nearby name in 250 m. Do not add matcher `manzano`.
    private static let manzanoMountainWilderness = CLLocationCoordinate2D(latitude: 34.663796, longitude: -106.419519)

    /// Dry interior of Sandia Mountain Wilderness. Named nature
    /// reserve, not wildlife range, not Sandia Mountain Natural
    /// History Center. Unique overlay at the pip. Unique versus Hawk
    /// Watch Open Space (2202 m). Unnamed peaks 1309 m stay peaks.
    /// No nearby name in 250 m. Do not add matcher `sandia`.
    private static let sandiaMountainWilderness = CLLocationCoordinate2D(latitude: 35.088383, longitude: -106.416369)

    /// Interior of Isleta Rectangle. Named NM forest: cottonwood;
    /// elk is high country, not west javelina, not a wetland bosque.
    private static let nmWoodland = CLLocationCoordinate2D(latitude: 34.939900, longitude: -106.320316)

    /// Interior of an unnamed NM wetland. Cottonwood and mule deer, not elk
    /// (elk is high country), not cottonmouth (that is east).
    private static let nmBosque = CLLocationCoordinate2D(latitude: 34.628816, longitude: -105.915768)

    /// `La Cruz Peak` on the NM place slice. Bear and elk as range, not
    /// west javelina. Ice-on-rock is in this book, so FIELD names cold first.
    private static let nmPeak = CLLocationCoordinate2D(latitude: 34.392837, longitude: -107.420040)

    /// `Mesa Blanca` on the NM place slice. A named peak on the
    /// Marquez overlay sheet — rank 1 still beats the overlay.
    /// Unique versus the Marquez overlay Hold (5246 m). Bear
    /// and elk as range, not javelina. Ice-on-rock is in this
    /// book, so FIELD names cold first.
    private static let mesaBlanca = CLLocationCoordinate2D(latitude: 35.338369, longitude: -107.263101)

    /// `Cerritos de la Jolla de Santa Rosa` on the NM place
    /// slice. A named peak on the Marquez overlay sheet — rank 1
    /// still beats the overlay. Unique versus the Marquez
    /// overlay Hold (9111 m) and Mesa Blanca (9295 m). Bear and
    /// elk as range, not javelina. Ice-on-rock is in this book,
    /// so FIELD names cold first.
    private static let cerritosDeLaJolla = CLLocationCoordinate2D(latitude: 35.409477, longitude: -107.316992)

    /// `San Antonio Mountain` on the NM place slice. A named
    /// peak on the Valles Caldera overlay sheet — rank 1 still
    /// beats the overlay. Unique versus the Valles Caldera
    /// overlay Hold (16092 m) and Cerritos de la Jolla de Santa
    /// Rosa (86362 m). San Antonio Mountain Trail is 358 m
    /// (rank 7). Overlay containment is the nearby name. Bear
    /// and elk as range, not javelina. Ice-on-rock is in this
    /// book, so FIELD names cold first. Do not add matcher
    /// `san antonio`.
    private static let sanAntonioMountain = CLLocationCoordinate2D(latitude: 35.937521, longitude: -106.615869)

    /// `Barton Hill` on the east place slice. Hog as range, not west javelina.
    private static let eastPeak = CLLocationCoordinate2D(latitude: 30.065769, longitude: -97.882228)

    /// `Mount Lucas` on the east place slice. A named peak on the
    /// Bright Leaf overlay sheet — rank 1 still beats the overlay.
    /// Unique versus the Bright Leaf overlay Hold (197 m). Trail #3
    /// stays a trail. 107 m from OSM water. Hog as range, not javelina.
    private static let mountLucas = CLLocationCoordinate2D(latitude: 30.329372, longitude: -97.773062)

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

        let vickery = try hold(at: Self.vickeryGlasshouse, zoom: 16, packId: "tx-east")
        XCTAssertEqual(vickery.card?.klass, "Glasshouse", "\(vickery)")
        XCTAssertEqual(vickery.card?.title, "Vickery Wholesale Greenhouse", "\(vickery)")
        XCTAssertNotEqual(vickery.card?.klass, "Irrigated ground", "\(vickery)")
        XCTAssertNotEqual(vickery.card?.title, "Daffan Lane", "\(vickery)")
        XCTAssertEqual(vickery.card?.fieldRoute.first, Inspect.plantTXCard, "\(vickery)")
        XCTAssertFalse(
            vickery.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "a named glasshouse opened woodland tree-use: \(vickery)"
        )
        XCTAssertTrue((vickery.card?.doLine.lowercased() ?? "").contains("oleander"), vickery.card?.doLine ?? "")
        XCTAssertFalse((vickery.card?.doLine.lowercased() ?? "").contains("live oak"), vickery.card?.doLine ?? "")
        XCTAssertFalse((vickery.card?.doLine.lowercased() ?? "").contains("edible"), vickery.card?.doLine ?? "")
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

        let castner = try hold(at: Self.castnerRange, zoom: 16)
        XCTAssertEqual(castner.card?.klass, "Open reserve", "\(castner)")
        XCTAssertEqual(castner.card?.title, "Castner Range National Monument", "\(castner)")
        XCTAssertNotEqual(castner.card?.klass, "Peak", "\(castner)")
        XCTAssertNotEqual(castner.card?.title, "Castner Range", "\(castner)")
        XCTAssertNotEqual(castner.card?.title, "Franklin Mountains State Park", "\(castner)")
        XCTAssertEqual(castner.card?.fieldRoute.first, Inspect.snakeTXCard, "\(castner)")
        XCTAssertTrue((castner.card?.doLine.lowercased() ?? "").contains("diamondback"), castner.card?.doLine ?? "")
        XCTAssertTrue((castner.card?.doLine.lowercased() ?? "").contains("javelina"), castner.card?.doLine ?? "")
        XCTAssertFalse((castner.card?.doLine.lowercased() ?? "").contains("edible"), castner.card?.doLine ?? "")

        let trackways = try hold(at: Self.trackways, zoom: 16)
        XCTAssertEqual(trackways.card?.klass, "Open reserve", "\(trackways)")
        XCTAssertEqual(trackways.card?.title, "Prehistoric Trackways National Monument", "\(trackways)")
        XCTAssertNotEqual(trackways.card?.klass, "Wildlife range", "\(trackways)")
        XCTAssertNotEqual(trackways.card?.title, "Robledo Loop", "\(trackways)")
        XCTAssertEqual(trackways.card?.fieldRoute.first, Inspect.snakeTXCard, "\(trackways)")
        XCTAssertTrue((trackways.card?.doLine.lowercased() ?? "").contains("diamondback"), trackways.card?.doLine ?? "")
        XCTAssertTrue((trackways.card?.doLine.lowercased() ?? "").contains("javelina"), trackways.card?.doLine ?? "")
        XCTAssertFalse((trackways.card?.doLine.lowercased() ?? "").contains("edible"), trackways.card?.doLine ?? "")

        let whiteSands = try hold(at: Self.whiteSands, zoom: 16)
        XCTAssertEqual(whiteSands.card?.klass, "Open reserve", "\(whiteSands)")
        XCTAssertEqual(whiteSands.card?.title, "White Sands National Park", "\(whiteSands)")
        XCTAssertNotEqual(whiteSands.card?.klass, "Wildlife range", "\(whiteSands)")
        XCTAssertNotEqual(whiteSands.card?.title, "White Sands Missile Range S Route 287", "\(whiteSands)")
        XCTAssertNotEqual(whiteSands.card?.title, "San Andres National Wildlife Refuge", "\(whiteSands)")
        XCTAssertEqual(whiteSands.card?.fieldRoute.first, Inspect.snakeTXCard, "\(whiteSands)")
        XCTAssertTrue((whiteSands.card?.doLine.lowercased() ?? "").contains("diamondback"), whiteSands.card?.doLine ?? "")
        XCTAssertTrue((whiteSands.card?.doLine.lowercased() ?? "").contains("javelina"), whiteSands.card?.doLine ?? "")
        XCTAssertFalse((whiteSands.card?.doLine.lowercased() ?? "").contains("edible"), whiteSands.card?.doLine ?? "")

        let knapp = try hold(at: Self.knappEasement, zoom: 16)
        XCTAssertEqual(knapp.card?.klass, "Open reserve", "\(knapp)")
        XCTAssertEqual(knapp.card?.title, "Knapp Land Conservation Easement", "\(knapp)")
        XCTAssertNotEqual(knapp.card?.klass, "Wildlife range", "\(knapp)")
        XCTAssertNotEqual(knapp.card?.title, "Castner Range National Monument", "\(knapp)")
        XCTAssertEqual(knapp.card?.fieldRoute.first, Inspect.snakeTXCard, "\(knapp)")
        XCTAssertTrue((knapp.card?.doLine.lowercased() ?? "").contains("diamondback"), knapp.card?.doLine ?? "")
        XCTAssertTrue((knapp.card?.doLine.lowercased() ?? "").contains("javelina"), knapp.card?.doLine ?? "")
        XCTAssertFalse((knapp.card?.doLine.lowercased() ?? "").contains("edible"), knapp.card?.doLine ?? "")

        let windACEC = try hold(at: Self.windMountainACEC, zoom: 16)
        XCTAssertEqual(windACEC.card?.klass, "Open reserve", "\(windACEC)")
        XCTAssertEqual(windACEC.card?.title, "Wind Mountain Area of Critical Environmental Concern", "\(windACEC)")
        XCTAssertNotEqual(windACEC.card?.klass, "Peak", "\(windACEC)")
        XCTAssertNotEqual(windACEC.card?.title, "Wind Mountain", "\(windACEC)")
        XCTAssertNotEqual(windACEC.card?.title, "Alamo Mountain Area of Critical Environmental Concern", "\(windACEC)")
        XCTAssertEqual(windACEC.card?.fieldRoute.first, Inspect.snakeTXCard, "\(windACEC)")
        XCTAssertTrue((windACEC.card?.doLine.lowercased() ?? "").contains("diamondback"), windACEC.card?.doLine ?? "")
        XCTAssertTrue((windACEC.card?.doLine.lowercased() ?? "").contains("javelina"), windACEC.card?.doLine ?? "")
        XCTAssertFalse((windACEC.card?.doLine.lowercased() ?? "").contains("edible"), windACEC.card?.doLine ?? "")

        let rincon = try hold(at: Self.rinconACEC, zoom: 16)
        XCTAssertEqual(rincon.card?.klass, "Open reserve", "\(rincon)")
        XCTAssertEqual(rincon.card?.title, "Rincon Area of Critical Environmental Concern", "\(rincon)")
        XCTAssertNotEqual(rincon.card?.klass, "Wildlife range", "\(rincon)")
        XCTAssertNotEqual(rincon.card?.title, "Jornada Experimental Range", "\(rincon)")
        XCTAssertEqual(rincon.card?.fieldRoute.first, Inspect.snakeTXCard, "\(rincon)")
        XCTAssertTrue((rincon.card?.doLine.lowercased() ?? "").contains("diamondback"), rincon.card?.doLine ?? "")
        XCTAssertTrue((rincon.card?.doLine.lowercased() ?? "").contains("javelina"), rincon.card?.doLine ?? "")
        XCTAssertFalse((rincon.card?.doLine.lowercased() ?? "").contains("edible"), rincon.card?.doLine ?? "")

        let sacramento = try hold(at: Self.sacramentoEscarpment, zoom: 16)
        XCTAssertEqual(sacramento.card?.klass, "Open reserve", "\(sacramento)")
        XCTAssertEqual(sacramento.card?.title, "Sacramento Escarpment Area of Critical Environmental Concern", "\(sacramento)")
        XCTAssertNotEqual(sacramento.card?.klass, "Wildlife range", "\(sacramento)")
        XCTAssertNotEqual(sacramento.card?.title, "Alamogordo Community Garden", "\(sacramento)")
        XCTAssertEqual(sacramento.card?.fieldRoute.first, Inspect.snakeTXCard, "\(sacramento)")
        XCTAssertTrue((sacramento.card?.doLine.lowercased() ?? "").contains("diamondback"), sacramento.card?.doLine ?? "")
        XCTAssertTrue((sacramento.card?.doLine.lowercased() ?? "").contains("javelina"), sacramento.card?.doLine ?? "")
        XCTAssertFalse((sacramento.card?.doLine.lowercased() ?? "").contains("edible"), sacramento.card?.doLine ?? "")

        let uvas = try hold(at: Self.uvasValleyACEC, zoom: 16)
        XCTAssertEqual(uvas.card?.klass, "Open reserve", "\(uvas)")
        XCTAssertEqual(uvas.card?.title, "Uvas Valley Area of Critical Environmental Concern", "\(uvas)")
        XCTAssertNotEqual(uvas.card?.klass, "Wildlife range", "\(uvas)")
        XCTAssertNotEqual(uvas.card?.title, "Prehistoric Trackways National Monument", "\(uvas)")
        XCTAssertNotEqual(uvas.card?.title, "Sierra de las Uvas Wilderness", "\(uvas)")
        XCTAssertEqual(uvas.card?.fieldRoute.first, Inspect.snakeTXCard, "\(uvas)")
        XCTAssertTrue((uvas.card?.doLine.lowercased() ?? "").contains("diamondback"), uvas.card?.doLine ?? "")
        XCTAssertTrue((uvas.card?.doLine.lowercased() ?? "").contains("javelina"), uvas.card?.doLine ?? "")
        XCTAssertFalse((uvas.card?.doLine.lowercased() ?? "").contains("edible"), uvas.card?.doLine ?? "")

        let thunder = try hold(at: Self.thunderCanyon, zoom: 16)
        XCTAssertEqual(thunder.card?.klass, "Open reserve", "\(thunder)")
        XCTAssertEqual(thunder.card?.title, "Thunder Canyon Conservation Easement", "\(thunder)")
        XCTAssertNotEqual(thunder.card?.klass, "Park", "\(thunder)")
        XCTAssertNotEqual(thunder.card?.title, "Sharondale Drive", "\(thunder)")
        XCTAssertNotEqual(thunder.card?.title, "Mount Franklin", "\(thunder)")
        XCTAssertEqual(thunder.card?.fieldRoute.first, Inspect.snakeTXCard, "\(thunder)")
        XCTAssertTrue((thunder.card?.doLine.lowercased() ?? "").contains("diamondback"), thunder.card?.doLine ?? "")
        XCTAssertTrue((thunder.card?.doLine.lowercased() ?? "").contains("javelina"), thunder.card?.doLine ?? "")
        XCTAssertFalse((thunder.card?.doLine.lowercased() ?? "").contains("edible"), thunder.card?.doLine ?? "")

        let cornundas = try hold(at: Self.cornundasACEC, zoom: 16)
        XCTAssertEqual(cornundas.card?.klass, "Open reserve", "\(cornundas)")
        XCTAssertEqual(cornundas.card?.title, "Cornundas Mountain Area of Critical Environmental Concern", "\(cornundas)")
        XCTAssertNotEqual(cornundas.card?.klass, "Peak", "\(cornundas)")
        XCTAssertNotEqual(cornundas.card?.title, "Cornudas Mountain", "\(cornundas)")
        XCTAssertNotEqual(cornundas.card?.title, "County Road F022", "\(cornundas)")
        XCTAssertNotEqual(cornundas.card?.title, "Wind Mountain Area of Critical Environmental Concern", "\(cornundas)")
        XCTAssertEqual(cornundas.card?.fieldRoute.first, Inspect.snakeTXCard, "\(cornundas)")
        XCTAssertTrue((cornundas.card?.doLine.lowercased() ?? "").contains("diamondback"), cornundas.card?.doLine ?? "")
        XCTAssertTrue((cornundas.card?.doLine.lowercased() ?? "").contains("javelina"), cornundas.card?.doLine ?? "")
        XCTAssertFalse((cornundas.card?.doLine.lowercased() ?? "").contains("edible"), cornundas.card?.doLine ?? "")

        let florida = try hold(at: Self.floridaMountainsWSA, zoom: 16)
        XCTAssertEqual(florida.card?.klass, "Open reserve", "\(florida)")
        XCTAssertEqual(florida.card?.title, "Florida Mountains Wilderness Study Area", "\(florida)")
        XCTAssertNotEqual(florida.card?.klass, "Wildlife range", "\(florida)")
        XCTAssertNotEqual(florida.card?.title, "Florida Mountains Area of Critical Environmental Concern", "\(florida)")
        XCTAssertNotEqual(florida.card?.title, "Uvas Valley Area of Critical Environmental Concern", "\(florida)")
        XCTAssertEqual(florida.card?.fieldRoute.first, Inspect.snakeTXCard, "\(florida)")
        XCTAssertTrue((florida.card?.doLine.lowercased() ?? "").contains("diamondback"), florida.card?.doLine ?? "")
        XCTAssertTrue((florida.card?.doLine.lowercased() ?? "").contains("javelina"), florida.card?.doLine ?? "")
        XCTAssertFalse((florida.card?.doLine.lowercased() ?? "").contains("edible"), florida.card?.doLine ?? "")
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

        let indio = try hold(at: Self.cuevaDelIndio, zoom: 16)
        XCTAssertEqual(indio.card?.klass, "Cave or hole", "\(indio)")
        XCTAssertEqual(indio.card?.title, "Cueva del Indio", "\(indio)")
        XCTAssertNotEqual(indio.card?.title, "Cueva del Apache", "\(indio)")
        XCTAssertEqual(indio.card?.fieldRoute.first, Inspect.caveCard, "\(indio)")
        XCTAssertTrue((indio.card?.doLine.lowercased() ?? "").contains("stay in daylight"), indio.card?.doLine ?? "")
        XCTAssertFalse((indio.card?.doLine.lowercased() ?? "").contains("edible"), indio.card?.doLine ?? "")

        let aztec = try hold(at: Self.aztecCave, zoom: 16)
        XCTAssertEqual(aztec.card?.klass, "Cave or hole", "\(aztec)")
        XCTAssertEqual(aztec.card?.title, "Aztec Cave", "\(aztec)")
        XCTAssertNotEqual(aztec.card?.klass, "Open reserve", "\(aztec)")
        XCTAssertNotEqual(aztec.card?.title, "Franklin Mountains State Park", "\(aztec)")
        XCTAssertNotEqual(aztec.card?.title, "Aztec Caves Trail", "\(aztec)")
        XCTAssertEqual(aztec.card?.fieldRoute.first, Inspect.caveCard, "\(aztec)")
        XCTAssertTrue((aztec.card?.doLine.lowercased() ?? "").contains("stay in daylight"), aztec.card?.doLine ?? "")
        XCTAssertFalse((aztec.card?.doLine.lowercased() ?? "").contains("edible"), aztec.card?.doLine ?? "")

        let ventana = try hold(at: Self.cuevaLaVentana, zoom: 16)
        XCTAssertEqual(ventana.card?.klass, "Cave or hole", "\(ventana)")
        XCTAssertEqual(ventana.card?.title, "Cueva la Ventana", "\(ventana)")
        XCTAssertNotEqual(ventana.card?.title, "Cueva del Apache", "\(ventana)")
        XCTAssertNotEqual(ventana.card?.title, "Cueva del Apache - La Ventana", "\(ventana)")
        XCTAssertEqual(ventana.card?.fieldRoute.first, Inspect.caveCard, "\(ventana)")
        XCTAssertTrue((ventana.card?.doLine.lowercased() ?? "").contains("stay in daylight"), ventana.card?.doLine ?? "")
        XCTAssertFalse((ventana.card?.doLine.lowercased() ?? "").contains("edible"), ventana.card?.doLine ?? "")

        let geronimo = try hold(at: Self.geronimoCave, zoom: 16)
        XCTAssertEqual(geronimo.card?.klass, "Cave or hole", "\(geronimo)")
        XCTAssertEqual(geronimo.card?.title, "Geronimo", "\(geronimo)")
        XCTAssertNotEqual(geronimo.card?.klass, "Open reserve", "\(geronimo)")
        XCTAssertNotEqual(geronimo.card?.title, "Organ Mountains-Desert Peaks National Monument", "\(geronimo)")
        XCTAssertNotEqual(geronimo.card?.title, "Robledo Mountains Wilderness", "\(geronimo)")
        XCTAssertEqual(geronimo.card?.fieldRoute.first, Inspect.caveCard, "\(geronimo)")
        XCTAssertTrue((geronimo.card?.doLine.lowercased() ?? "").contains("stay in daylight"), geronimo.card?.doLine ?? "")
        XCTAssertFalse((geronimo.card?.doLine.lowercased() ?? "").contains("edible"), geronimo.card?.doLine ?? "")
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

        let charlie = try hold(at: Self.charlieWakeem, zoom: 16)
        XCTAssertEqual(charlie.card?.klass, "Wildlife range", "\(charlie)")
        XCTAssertEqual(
            charlie.card?.title,
            "Charlie Wakeem/Richard Teschner Nature Preserve of Resler Canyon",
            "\(charlie)"
        )
        XCTAssertNotEqual(charlie.card?.klass, "Open reserve", "\(charlie)")
        XCTAssertNotEqual(charlie.card?.klass, "Road", "\(charlie)")
        XCTAssertNotEqual(charlie.card?.title, "Cadiz Street", "\(charlie)")
        XCTAssertNotEqual(charlie.card?.title, "Fiesta Drive", "\(charlie)")
        XCTAssertEqual(charlie.card?.fieldRoute.first, Inspect.mammalTXCard, "\(charlie)")
        XCTAssertTrue((charlie.card?.doLine.lowercased() ?? "").contains("javelina"), charlie.card?.doLine ?? "")
        XCTAssertFalse((charlie.card?.doLine.lowercased() ?? "").contains("edible"), charlie.card?.doLine ?? "")

        let sanAndres = try hold(at: Self.sanAndres, zoom: 16)
        XCTAssertEqual(sanAndres.card?.klass, "Wildlife range", "\(sanAndres)")
        XCTAssertEqual(sanAndres.card?.title, "San Andres National Wildlife Refuge", "\(sanAndres)")
        XCTAssertNotEqual(sanAndres.card?.klass, "Open reserve", "\(sanAndres)")
        XCTAssertNotEqual(sanAndres.card?.klass, "Road", "\(sanAndres)")
        XCTAssertNotEqual(sanAndres.card?.title, "White Sands Missile Range S Route 287", "\(sanAndres)")
        XCTAssertNotEqual(sanAndres.card?.title, "San Andres Peak", "\(sanAndres)")
        XCTAssertNotEqual(sanAndres.card?.title, "Bennett Mountain", "\(sanAndres)")
        XCTAssertNotEqual(sanAndres.card?.title, "Big Brushy Mountain", "\(sanAndres)")
        XCTAssertNotEqual(sanAndres.card?.title, "Gardner Peak", "\(sanAndres)")
        XCTAssertEqual(sanAndres.card?.fieldRoute.first, Inspect.mammalTXCard, "\(sanAndres)")
        XCTAssertTrue((sanAndres.card?.doLine.lowercased() ?? "").contains("javelina"), sanAndres.card?.doLine ?? "")
        XCTAssertFalse((sanAndres.card?.doLine.lowercased() ?? "").contains("edible"), sanAndres.card?.doLine ?? "")

        let featherLake = try hold(at: Self.featherLakeRefuge, zoom: 16)
        XCTAssertEqual(featherLake.card?.klass, "Wildlife range", "\(featherLake)")
        XCTAssertEqual(featherLake.card?.title, "Feather Lake Wildlife Refuge", "\(featherLake)")
        XCTAssertNotEqual(featherLake.card?.klass, "Open reserve", "\(featherLake)")
        XCTAssertNotEqual(featherLake.card?.klass, "Road", "\(featherLake)")
        XCTAssertNotEqual(featherLake.card?.title, "Nottingham Drive", "\(featherLake)")
        XCTAssertNotEqual(featherLake.card?.title, "Envoy Way", "\(featherLake)")
        XCTAssertNotEqual(featherLake.card?.title, "Lost Dog Nature Preserve", "\(featherLake)")
        XCTAssertEqual(featherLake.card?.fieldRoute.first, Inspect.mammalTXCard, "\(featherLake)")
        XCTAssertTrue((featherLake.card?.doLine.lowercased() ?? "").contains("javelina"), featherLake.card?.doLine ?? "")
        XCTAssertFalse((featherLake.card?.doLine.lowercased() ?? "").contains("hog"), featherLake.card?.doLine ?? "")
        XCTAssertFalse((featherLake.card?.doLine.lowercased() ?? "").contains("edible"), featherLake.card?.doLine ?? "")

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
        XCTAssertNotEqual(flora.card?.title, "Loma El Gato", "\(flora)")
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

        let blackmore = try hold(at: Self.blackmorePreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(blackmore.card?.klass, "Wildlife range", "\(blackmore)")
        XCTAssertEqual(blackmore.card?.title, "Balcones Canyonlands Preserve - Blackmore", "\(blackmore)")
        XCTAssertNotEqual(blackmore.card?.title, "Balcones Canyonlands Preserve - Grandview Hills", "\(blackmore)")
        XCTAssertNotEqual(blackmore.card?.title, "Balcones Canyonlands Preserve - Cuevas East", "\(blackmore)")
        XCTAssertNotEqual(blackmore.card?.title, "Bullick Hollow Road", "\(blackmore)")
        XCTAssertEqual(blackmore.card?.fieldRoute.first, Inspect.mammalEastCard, "\(blackmore)")
        XCTAssertTrue((blackmore.card?.doLine.lowercased() ?? "").contains("hog"), blackmore.card?.doLine ?? "")
        XCTAssertFalse((blackmore.card?.doLine.lowercased() ?? "").contains("javelina"), blackmore.card?.doLine ?? "")
        XCTAssertFalse((blackmore.card?.doLine.lowercased() ?? "").contains("edible"), blackmore.card?.doLine ?? "")

        let lakePerspectives = try hold(at: Self.lakePerspectives, zoom: 16, packId: "tx-east")
        XCTAssertEqual(lakePerspectives.card?.klass, "Wildlife range", "\(lakePerspectives)")
        XCTAssertEqual(lakePerspectives.card?.title, "Balcones Canyonlands Preserve - Lake Perspectives", "\(lakePerspectives)")
        XCTAssertNotEqual(lakePerspectives.card?.title, "Balcones Canyonlands Preserve - Grandview Hills", "\(lakePerspectives)")
        XCTAssertNotEqual(lakePerspectives.card?.title, "Balcones Canyonlands Preserve - Cuevas East", "\(lakePerspectives)")
        XCTAssertEqual(lakePerspectives.card?.fieldRoute.first, Inspect.mammalEastCard, "\(lakePerspectives)")
        XCTAssertTrue((lakePerspectives.card?.doLine.lowercased() ?? "").contains("hog"), lakePerspectives.card?.doLine ?? "")
        XCTAssertFalse((lakePerspectives.card?.doLine.lowercased() ?? "").contains("javelina"), lakePerspectives.card?.doLine ?? "")
        XCTAssertFalse((lakePerspectives.card?.doLine.lowercased() ?? "").contains("edible"), lakePerspectives.card?.doLine ?? "")

        let austinSimon = try hold(at: Self.austinSimonPreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(austinSimon.card?.klass, "Wildlife range", "\(austinSimon)")
        XCTAssertEqual(austinSimon.card?.title, "Balcones Canyonlands Preserve - Austin Simon", "\(austinSimon)")
        XCTAssertNotEqual(austinSimon.card?.title, "Balcones Canyonlands Preserve - Grandview Hills", "\(austinSimon)")
        XCTAssertNotEqual(austinSimon.card?.title, "Balcones Canyonlands Preserve - Lime Creek", "\(austinSimon)")
        XCTAssertEqual(austinSimon.card?.fieldRoute.first, Inspect.mammalEastCard, "\(austinSimon)")
        XCTAssertTrue((austinSimon.card?.doLine.lowercased() ?? "").contains("hog"), austinSimon.card?.doLine ?? "")
        XCTAssertFalse((austinSimon.card?.doLine.lowercased() ?? "").contains("javelina"), austinSimon.card?.doLine ?? "")
        XCTAssertFalse((austinSimon.card?.doLine.lowercased() ?? "").contains("edible"), austinSimon.card?.doLine ?? "")

        let limeCreek = try hold(at: Self.limeCreekPreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(limeCreek.card?.klass, "Wildlife range", "\(limeCreek)")
        XCTAssertEqual(limeCreek.card?.title, "Balcones Canyonlands Preserve - Lime Creek", "\(limeCreek)")
        XCTAssertNotEqual(limeCreek.card?.title, "Balcones Canyonlands Preserve - Austin Simon", "\(limeCreek)")
        XCTAssertNotEqual(limeCreek.card?.title, "Balcones Canyonlands Preserve - Grandview Hills", "\(limeCreek)")
        XCTAssertEqual(limeCreek.card?.fieldRoute.first, Inspect.mammalEastCard, "\(limeCreek)")
        XCTAssertTrue((limeCreek.card?.doLine.lowercased() ?? "").contains("hog"), limeCreek.card?.doLine ?? "")
        XCTAssertFalse((limeCreek.card?.doLine.lowercased() ?? "").contains("javelina"), limeCreek.card?.doLine ?? "")
        XCTAssertFalse((limeCreek.card?.doLine.lowercased() ?? "").contains("edible"), limeCreek.card?.doLine ?? "")

        let romberg = try hold(at: Self.rombergPreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(romberg.card?.klass, "Wildlife range", "\(romberg)")
        XCTAssertEqual(romberg.card?.title, "Balcones Canyonlands Preserve - Romberg", "\(romberg)")
        XCTAssertNotEqual(romberg.card?.title, "Balcones Canyonlands Preserve - McGregor", "\(romberg)")
        XCTAssertNotEqual(romberg.card?.title, "Balcones Canyonlands Preserve - Grandview Hills", "\(romberg)")
        XCTAssertNotEqual(romberg.card?.title, "Bob Wentz Park", "\(romberg)")
        XCTAssertNotEqual(romberg.card?.title, "Comanche Trail", "\(romberg)")
        XCTAssertEqual(romberg.card?.fieldRoute.first, Inspect.mammalEastCard, "\(romberg)")
        XCTAssertTrue((romberg.card?.doLine.lowercased() ?? "").contains("hog"), romberg.card?.doLine ?? "")
        XCTAssertFalse((romberg.card?.doLine.lowercased() ?? "").contains("javelina"), romberg.card?.doLine ?? "")
        XCTAssertFalse((romberg.card?.doLine.lowercased() ?? "").contains("edible"), romberg.card?.doLine ?? "")

        let mcgregor = try hold(at: Self.mcgregorPreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(mcgregor.card?.klass, "Wildlife range", "\(mcgregor)")
        XCTAssertEqual(mcgregor.card?.title, "Balcones Canyonlands Preserve - McGregor", "\(mcgregor)")
        XCTAssertNotEqual(mcgregor.card?.title, "Balcones Canyonlands Preserve - Romberg", "\(mcgregor)")
        XCTAssertNotEqual(mcgregor.card?.title, "Balcones Canyonlands Preserve - Grandview Hills", "\(mcgregor)")
        XCTAssertNotEqual(mcgregor.card?.title, "Hippie Hollow Park", "\(mcgregor)")
        XCTAssertNotEqual(mcgregor.card?.title, "Bob Wentz Park", "\(mcgregor)")
        XCTAssertNotEqual(mcgregor.card?.title, "Comanche Trail", "\(mcgregor)")
        XCTAssertEqual(mcgregor.card?.fieldRoute.first, Inspect.mammalEastCard, "\(mcgregor)")
        XCTAssertTrue((mcgregor.card?.doLine.lowercased() ?? "").contains("hog"), mcgregor.card?.doLine ?? "")
        XCTAssertFalse((mcgregor.card?.doLine.lowercased() ?? "").contains("javelina"), mcgregor.card?.doLine ?? "")
        XCTAssertFalse((mcgregor.card?.doLine.lowercased() ?? "").contains("edible"), mcgregor.card?.doLine ?? "")

        let cuevasEast = try hold(at: Self.cuevasEastPreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(cuevasEast.card?.klass, "Wildlife range", "\(cuevasEast)")
        XCTAssertEqual(cuevasEast.card?.title, "Balcones Canyonlands Preserve - Cuevas East", "\(cuevasEast)")
        XCTAssertNotEqual(cuevasEast.card?.title, "Balcones Canyonlands Preserve - Cuevas", "\(cuevasEast)")
        XCTAssertNotEqual(cuevasEast.card?.title, "Balcones Canyonlands Preserve - Blackmore", "\(cuevasEast)")
        XCTAssertNotEqual(cuevasEast.card?.title, "Balcones Canyonlands Preserve - Grandview Hills", "\(cuevasEast)")
        XCTAssertNotEqual(cuevasEast.card?.title, "Ranch Road 620 North", "\(cuevasEast)")
        XCTAssertNotEqual(cuevasEast.card?.title, "Four Points Drive", "\(cuevasEast)")
        XCTAssertEqual(cuevasEast.card?.fieldRoute.first, Inspect.mammalEastCard, "\(cuevasEast)")
        XCTAssertTrue((cuevasEast.card?.doLine.lowercased() ?? "").contains("hog"), cuevasEast.card?.doLine ?? "")
        XCTAssertFalse((cuevasEast.card?.doLine.lowercased() ?? "").contains("javelina"), cuevasEast.card?.doLine ?? "")
        XCTAssertFalse((cuevasEast.card?.doLine.lowercased() ?? "").contains("edible"), cuevasEast.card?.doLine ?? "")

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

        let stephenson = try hold(at: Self.stephensonPreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(stephenson.card?.klass, "Wildlife range", "\(stephenson)")
        XCTAssertEqual(stephenson.card?.title, "Stephenson Nature Preserve And Outdoor Education Center", "\(stephenson)")
        XCTAssertNotEqual(stephenson.card?.klass, "Open reserve", "\(stephenson)")
        XCTAssertNotEqual(stephenson.card?.klass, "Park", "\(stephenson)")
        XCTAssertNotEqual(stephenson.card?.title, "Bloomfield Drive", "\(stephenson)")
        XCTAssertEqual(stephenson.card?.fieldRoute.first, Inspect.mammalEastCard, "\(stephenson)")
        XCTAssertTrue((stephenson.card?.doLine.lowercased() ?? "").contains("hog"), stephenson.card?.doLine ?? "")
        XCTAssertFalse((stephenson.card?.doLine.lowercased() ?? "").contains("javelina"), stephenson.card?.doLine ?? "")
        XCTAssertFalse((stephenson.card?.doLine.lowercased() ?? "").contains("edible"), stephenson.card?.doLine ?? "")

        let onionSanctuary = try hold(at: Self.onionCreekSanctuary, zoom: 16, packId: "tx-east")
        XCTAssertEqual(onionSanctuary.card?.klass, "Wildlife range", "\(onionSanctuary)")
        XCTAssertEqual(onionSanctuary.card?.title, "Onion Creek Wildlife Sanctuary", "\(onionSanctuary)")
        XCTAssertNotEqual(onionSanctuary.card?.title, "Onion Creek Management Unit", "\(onionSanctuary)")
        XCTAssertNotEqual(onionSanctuary.card?.title, "Onion Creek Drive", "\(onionSanctuary)")
        XCTAssertEqual(onionSanctuary.card?.fieldRoute.first, Inspect.mammalEastCard, "\(onionSanctuary)")
        XCTAssertTrue((onionSanctuary.card?.doLine.lowercased() ?? "").contains("hog"), onionSanctuary.card?.doLine ?? "")
        XCTAssertFalse((onionSanctuary.card?.doLine.lowercased() ?? "").contains("javelina"), onionSanctuary.card?.doLine ?? "")
        XCTAssertFalse((onionSanctuary.card?.doLine.lowercased() ?? "").contains("edible"), onionSanctuary.card?.doLine ?? "")

        let maryGay = try hold(at: Self.maryGayMaxwell, zoom: 16, packId: "tx-east")
        XCTAssertEqual(maryGay.card?.klass, "Wildlife range", "\(maryGay)")
        XCTAssertEqual(maryGay.card?.title, "Mary Gay Maxwell Management Unit", "\(maryGay)")
        XCTAssertNotEqual(maryGay.card?.klass, "Open reserve", "\(maryGay)")
        XCTAssertNotEqual(maryGay.card?.title, "Slaughter Creek Trail Main Loop", "\(maryGay)")
        XCTAssertEqual(maryGay.card?.fieldRoute.first, Inspect.mammalEastCard, "\(maryGay)")
        XCTAssertTrue((maryGay.card?.doLine.lowercased() ?? "").contains("hog"), maryGay.card?.doLine ?? "")
        XCTAssertFalse((maryGay.card?.doLine.lowercased() ?? "").contains("javelina"), maryGay.card?.doLine ?? "")
        XCTAssertFalse((maryGay.card?.doLine.lowercased() ?? "").contains("edible"), maryGay.card?.doLine ?? "")

        let onionUnit = try hold(at: Self.onionCreekUnit, zoom: 16, packId: "tx-east")
        XCTAssertEqual(onionUnit.card?.klass, "Wildlife range", "\(onionUnit)")
        XCTAssertEqual(onionUnit.card?.title, "Onion Creek Management Unit", "\(onionUnit)")
        XCTAssertNotEqual(onionUnit.card?.title, "Onion Creek Wildlife Sanctuary", "\(onionUnit)")
        XCTAssertEqual(onionUnit.card?.fieldRoute.first, Inspect.mammalEastCard, "\(onionUnit)")
        XCTAssertTrue((onionUnit.card?.doLine.lowercased() ?? "").contains("hog"), onionUnit.card?.doLine ?? "")
        XCTAssertFalse((onionUnit.card?.doLine.lowercased() ?? "").contains("javelina"), onionUnit.card?.doLine ?? "")
        XCTAssertFalse((onionUnit.card?.doLine.lowercased() ?? "").contains("edible"), onionUnit.card?.doLine ?? "")

        let bullCreek = try hold(at: Self.bullCreekUnit, zoom: 16, packId: "tx-east")
        XCTAssertEqual(bullCreek.card?.klass, "Wildlife range", "\(bullCreek)")
        XCTAssertEqual(bullCreek.card?.title, "Bull Creek Management Unit", "\(bullCreek)")
        XCTAssertNotEqual(bullCreek.card?.klass, "Open reserve", "\(bullCreek)")
        XCTAssertNotEqual(bullCreek.card?.title, "Bull Creek West Loop", "\(bullCreek)")
        XCTAssertEqual(bullCreek.card?.fieldRoute.first, Inspect.mammalEastCard, "\(bullCreek)")
        XCTAssertTrue((bullCreek.card?.doLine.lowercased() ?? "").contains("hog"), bullCreek.card?.doLine ?? "")
        XCTAssertFalse((bullCreek.card?.doLine.lowercased() ?? "").contains("javelina"), bullCreek.card?.doLine ?? "")
        XCTAssertFalse((bullCreek.card?.doLine.lowercased() ?? "").contains("edible"), bullCreek.card?.doLine ?? "")

        let lowerBarton = try hold(at: Self.lowerBartonUnit, zoom: 16, packId: "tx-east")
        XCTAssertEqual(lowerBarton.card?.klass, "Wildlife range", "\(lowerBarton)")
        XCTAssertEqual(lowerBarton.card?.title, "Lower Barton Creek Management Unit", "\(lowerBarton)")
        XCTAssertNotEqual(lowerBarton.card?.title, "Barton Creek Habitat Preserve", "\(lowerBarton)")
        XCTAssertNotEqual(lowerBarton.card?.title, "Barton Creek Wilderness Park", "\(lowerBarton)")
        XCTAssertNotEqual(lowerBarton.card?.title, "Circle Drive", "\(lowerBarton)")
        XCTAssertEqual(lowerBarton.card?.fieldRoute.first, Inspect.mammalEastCard, "\(lowerBarton)")
        XCTAssertTrue((lowerBarton.card?.doLine.lowercased() ?? "").contains("hog"), lowerBarton.card?.doLine ?? "")
        XCTAssertFalse((lowerBarton.card?.doLine.lowercased() ?? "").contains("javelina"), lowerBarton.card?.doLine ?? "")
        XCTAssertFalse((lowerBarton.card?.doLine.lowercased() ?? "").contains("edible"), lowerBarton.card?.doLine ?? "")

        let littleBear = try hold(at: Self.littleBearUnit, zoom: 16, packId: "tx-east")
        XCTAssertEqual(littleBear.card?.klass, "Wildlife range", "\(littleBear)")
        XCTAssertEqual(littleBear.card?.title, "Little Bear Creek Management Unit", "\(littleBear)")
        XCTAssertNotEqual(littleBear.card?.klass, "Open reserve", "\(littleBear)")
        XCTAssertEqual(littleBear.card?.fieldRoute.first, Inspect.mammalEastCard, "\(littleBear)")
        XCTAssertTrue((littleBear.card?.doLine.lowercased() ?? "").contains("hog"), littleBear.card?.doLine ?? "")
        XCTAssertFalse((littleBear.card?.doLine.lowercased() ?? "").contains("javelina"), littleBear.card?.doLine ?? "")
        XCTAssertFalse((littleBear.card?.doLine.lowercased() ?? "").contains("edible"), littleBear.card?.doLine ?? "")

        let barrow = try hold(at: Self.barrowPreserve, zoom: 16, packId: "tx-east")
        XCTAssertEqual(barrow.card?.kind, .water, "\(barrow)")
        XCTAssertNotEqual(barrow.card?.klass, "Wildlife range", "\(barrow)")
        XCTAssertNotEqual(barrow.card?.title, "Barrow Nature Preserve", "\(barrow)")
        XCTAssertEqual(barrow.card?.fieldRoute.first, Inspect.waterCard, "\(barrow)")

        let wildBasin = try hold(at: Self.wildBasin, zoom: 16, packId: "tx-east")
        XCTAssertEqual(wildBasin.card?.klass, "Wildlife range", "\(wildBasin)")
        XCTAssertEqual(wildBasin.card?.title, "Wild Basin Wilderness Preserve", "\(wildBasin)")
        XCTAssertNotEqual(wildBasin.card?.klass, "Open reserve", "\(wildBasin)")
        XCTAssertNotEqual(wildBasin.card?.klass, "Cactus garden", "\(wildBasin)")
        XCTAssertNotEqual(wildBasin.card?.title, "North Capital of Texas Highway", "\(wildBasin)")
        XCTAssertEqual(wildBasin.card?.fieldRoute.first, Inspect.mammalEastCard, "\(wildBasin)")
        XCTAssertTrue((wildBasin.card?.doLine.lowercased() ?? "").contains("hog"), wildBasin.card?.doLine ?? "")
        XCTAssertFalse((wildBasin.card?.doLine.lowercased() ?? "").contains("javelina"), wildBasin.card?.doLine ?? "")
        XCTAssertFalse((wildBasin.card?.doLine.lowercased() ?? "").contains("edible"), wildBasin.card?.doLine ?? "")

        let stillhouse = try hold(at: Self.stillhouseHollow, zoom: 16, packId: "tx-east")
        XCTAssertEqual(stillhouse.card?.klass, "Wildlife range", "\(stillhouse)")
        XCTAssertEqual(stillhouse.card?.title, "Stillhouse Hollow Nature Preserve", "\(stillhouse)")
        XCTAssertNotEqual(stillhouse.card?.klass, "Open reserve", "\(stillhouse)")
        XCTAssertNotEqual(stillhouse.card?.title, "Sterling Drive", "\(stillhouse)")
        XCTAssertEqual(stillhouse.card?.fieldRoute.first, Inspect.mammalEastCard, "\(stillhouse)")
        XCTAssertTrue((stillhouse.card?.doLine.lowercased() ?? "").contains("hog"), stillhouse.card?.doLine ?? "")
        XCTAssertFalse((stillhouse.card?.doLine.lowercased() ?? "").contains("javelina"), stillhouse.card?.doLine ?? "")
        XCTAssertFalse((stillhouse.card?.doLine.lowercased() ?? "").contains("edible"), stillhouse.card?.doLine ?? "")

        let bigWalnut = try hold(at: Self.bigWalnut, zoom: 16, packId: "tx-east")
        XCTAssertEqual(bigWalnut.card?.klass, "Wildlife range", "\(bigWalnut)")
        XCTAssertEqual(bigWalnut.card?.title, "Big Walnut Creek Nature Preserve", "\(bigWalnut)")
        XCTAssertNotEqual(bigWalnut.card?.klass, "Open reserve", "\(bigWalnut)")
        XCTAssertNotEqual(bigWalnut.card?.title, "Ferguson Cutoff", "\(bigWalnut)")
        XCTAssertEqual(bigWalnut.card?.fieldRoute.first, Inspect.mammalEastCard, "\(bigWalnut)")
        XCTAssertTrue((bigWalnut.card?.doLine.lowercased() ?? "").contains("hog"), bigWalnut.card?.doLine ?? "")
        XCTAssertFalse((bigWalnut.card?.doLine.lowercased() ?? "").contains("javelina"), bigWalnut.card?.doLine ?? "")
        XCTAssertFalse((bigWalnut.card?.doLine.lowercased() ?? "").contains("edible"), bigWalnut.card?.doLine ?? "")

        let coloradoSanctuary = try hold(at: Self.coloradoSanctuary, zoom: 16, packId: "tx-east")
        XCTAssertEqual(coloradoSanctuary.card?.klass, "Wildlife range", "\(coloradoSanctuary)")
        XCTAssertEqual(coloradoSanctuary.card?.title, "Colorado River Park Wildlife Sanctuary", "\(coloradoSanctuary)")
        XCTAssertNotEqual(coloradoSanctuary.card?.klass, "Botanic garden", "\(coloradoSanctuary)")
        XCTAssertNotEqual(coloradoSanctuary.card?.title, "Colorado Community Garden", "\(coloradoSanctuary)")
        XCTAssertNotEqual(coloradoSanctuary.card?.title, "Levander Loop", "\(coloradoSanctuary)")
        XCTAssertEqual(coloradoSanctuary.card?.fieldRoute.first, Inspect.mammalEastCard, "\(coloradoSanctuary)")
        XCTAssertTrue((coloradoSanctuary.card?.doLine.lowercased() ?? "").contains("hog"), coloradoSanctuary.card?.doLine ?? "")
        XCTAssertFalse((coloradoSanctuary.card?.doLine.lowercased() ?? "").contains("javelina"), coloradoSanctuary.card?.doLine ?? "")
        XCTAssertFalse((coloradoSanctuary.card?.doLine.lowercased() ?? "").contains("edible"), coloradoSanctuary.card?.doLine ?? "")

        let shadyHollow = try hold(at: Self.shadyHollowWest, zoom: 16, packId: "tx-east")
        XCTAssertEqual(shadyHollow.card?.klass, "Wildlife range", "\(shadyHollow)")
        XCTAssertEqual(shadyHollow.card?.title, "Shady Hollow West Nature Preserve", "\(shadyHollow)")
        XCTAssertNotEqual(shadyHollow.card?.klass, "Open reserve", "\(shadyHollow)")
        XCTAssertNotEqual(shadyHollow.card?.klass, "Cave or hole", "\(shadyHollow)")
        XCTAssertNotEqual(shadyHollow.card?.title, "Bear Creek Management Unit", "\(shadyHollow)")
        XCTAssertNotEqual(shadyHollow.card?.title, "Lost Oasis Hollow", "\(shadyHollow)")
        XCTAssertNotEqual(shadyHollow.card?.title, "Lost Oasis Cave Preserve", "\(shadyHollow)")
        XCTAssertEqual(shadyHollow.card?.fieldRoute.first, Inspect.mammalEastCard, "\(shadyHollow)")
        XCTAssertTrue((shadyHollow.card?.doLine.lowercased() ?? "").contains("hog"), shadyHollow.card?.doLine ?? "")
        XCTAssertFalse((shadyHollow.card?.doLine.lowercased() ?? "").contains("javelina"), shadyHollow.card?.doLine ?? "")
        XCTAssertFalse((shadyHollow.card?.doLine.lowercased() ?? "").contains("edible"), shadyHollow.card?.doLine ?? "")

        let brightLeaf = try hold(at: Self.brightLeaf, zoom: 16, packId: "tx-east")
        XCTAssertEqual(brightLeaf.card?.klass, "Wildlife range", "\(brightLeaf)")
        XCTAssertEqual(brightLeaf.card?.title, "Bright Leaf Natural Area", "\(brightLeaf)")
        XCTAssertNotEqual(brightLeaf.card?.klass, "Open reserve", "\(brightLeaf)")
        XCTAssertNotEqual(brightLeaf.card?.title, "Mount Bonnell Road", "\(brightLeaf)")
        XCTAssertNotEqual(brightLeaf.card?.title, "Waters Edge Drive", "\(brightLeaf)")
        XCTAssertNotEqual(brightLeaf.card?.title, "Mount Lucas", "\(brightLeaf)")
        XCTAssertEqual(brightLeaf.card?.fieldRoute.first, Inspect.mammalEastCard, "\(brightLeaf)")
        XCTAssertTrue((brightLeaf.card?.doLine.lowercased() ?? "").contains("hog"), brightLeaf.card?.doLine ?? "")
        XCTAssertFalse((brightLeaf.card?.doLine.lowercased() ?? "").contains("javelina"), brightLeaf.card?.doLine ?? "")
        XCTAssertFalse((brightLeaf.card?.doLine.lowercased() ?? "").contains("edible"), brightLeaf.card?.doLine ?? "")

        let redBluff = try hold(at: Self.redBluff, zoom: 16, packId: "tx-east")
        XCTAssertEqual(redBluff.card?.klass, "Wildlife range", "\(redBluff)")
        XCTAssertEqual(redBluff.card?.title, "Red Bluff Nature Preserve", "\(redBluff)")
        XCTAssertNotEqual(redBluff.card?.klass, "Open reserve", "\(redBluff)")
        XCTAssertNotEqual(redBluff.card?.title, "Red Bluff Neighborhood Park", "\(redBluff)")
        XCTAssertNotEqual(redBluff.card?.title, "DC Moore Addition", "\(redBluff)")
        XCTAssertNotEqual(redBluff.card?.title, "Prock Lane", "\(redBluff)")
        XCTAssertEqual(redBluff.card?.fieldRoute.first, Inspect.mammalEastCard, "\(redBluff)")
        XCTAssertTrue((redBluff.card?.doLine.lowercased() ?? "").contains("hog"), redBluff.card?.doLine ?? "")
        XCTAssertFalse((redBluff.card?.doLine.lowercased() ?? "").contains("javelina"), redBluff.card?.doLine ?? "")
        XCTAssertFalse((redBluff.card?.doLine.lowercased() ?? "").contains("edible"), redBluff.card?.doLine ?? "")

        let blunn = try hold(at: Self.blunnCreek, zoom: 16, packId: "tx-east")
        XCTAssertEqual(blunn.card?.klass, "Wildlife range", "\(blunn)")
        XCTAssertEqual(blunn.card?.title, "Blunn Creek Nature Preserve", "\(blunn)")
        XCTAssertNotEqual(blunn.card?.klass, "Open reserve", "\(blunn)")
        XCTAssertNotEqual(blunn.card?.klass, "Road", "\(blunn)")
        XCTAssertNotEqual(blunn.card?.title, "East Oltorf Street", "\(blunn)")
        XCTAssertEqual(blunn.card?.fieldRoute.first, Inspect.mammalEastCard, "\(blunn)")
        XCTAssertTrue((blunn.card?.doLine.lowercased() ?? "").contains("hog"), blunn.card?.doLine ?? "")
        XCTAssertFalse((blunn.card?.doLine.lowercased() ?? "").contains("javelina"), blunn.card?.doLine ?? "")
        XCTAssertFalse((blunn.card?.doLine.lowercased() ?? "").contains("edible"), blunn.card?.doLine ?? "")
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

        let argus = try hold(at: Self.argusTree, zoom: 16, packId: "tx-east")
        XCTAssertEqual(argus.card?.klass, "Named tree", "\(argus)")
        XCTAssertEqual(argus.card?.title, "Argus", "\(argus)")
        XCTAssertNotEqual(argus.card?.klass, "Road", "\(argus)")
        XCTAssertNotEqual(argus.card?.klass, "Built-up ground", "\(argus)")
        XCTAssertNotEqual(argus.card?.title, "Arthur Stiles Road", "\(argus)")
        XCTAssertNotEqual(argus.card?.title, "Johnston Terrace", "\(argus)")
        XCTAssertEqual(argus.card?.fieldRoute.first, Inspect.treeUseEastCard, "\(argus)")
        let argusDo = argus.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(argusDo.contains("not a meal"), argus.card?.doLine ?? "")
        XCTAssertFalse(argusDo.contains("edible"), argus.card?.doLine ?? "")
        XCTAssertFalse(argusDo.contains("hog"), argus.card?.doLine ?? "")
        XCTAssertFalse(argusDo.contains("javelina"), argus.card?.doLine ?? "")

        let kimBird = try hold(at: Self.kimBirdTree, zoom: 16, packId: "tx-east")
        XCTAssertEqual(kimBird.card?.klass, "Named tree", "\(kimBird)")
        XCTAssertEqual(kimBird.card?.title, "Kim Bird Gebert Memorial Tree", "\(kimBird)")
        XCTAssertNotEqual(kimBird.card?.klass, "Park", "\(kimBird)")
        XCTAssertNotEqual(kimBird.card?.klass, "Road", "\(kimBird)")
        XCTAssertNotEqual(kimBird.card?.title, "Lake Pflugerville Park", "\(kimBird)")
        XCTAssertNotEqual(kimBird.card?.title, "Silent Harbor Loop", "\(kimBird)")
        XCTAssertEqual(kimBird.card?.fieldRoute.first, Inspect.treeUseEastCard, "\(kimBird)")
        let kimBirdDo = kimBird.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(kimBirdDo.contains("not a meal"), kimBird.card?.doLine ?? "")
        XCTAssertFalse(kimBirdDo.contains("edible"), kimBird.card?.doLine ?? "")
        XCTAssertFalse(kimBirdDo.contains("hog"), kimBird.card?.doLine ?? "")
        XCTAssertFalse(kimBirdDo.contains("javelina"), kimBird.card?.doLine ?? "")
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
        XCTAssertNotEqual(held.card?.title, "Lime Creek Road Sink", "\(held)")
        XCTAssertNotEqual(held.card?.title, "Under Three Oaks", "\(held)")
        XCTAssertNotEqual(held.card?.title, "Persimmon Well", "\(held)")
        XCTAssertNotEqual(held.card?.title, "Jumbled Rocks", "\(held)")
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

        let westernOaks = try hold(at: Self.westernOaksKarst, zoom: 16, packId: "tx-east")
        XCTAssertEqual(westernOaks.card?.klass, "Cave or hole", "\(westernOaks)")
        XCTAssertNotEqual(westernOaks.card?.klass, "Wildlife range", "\(westernOaks)")
        XCTAssertEqual(
            westernOaks.card?.title,
            "Village of Western Oaks Karst Preserve and Watershed Management Area",
            "\(westernOaks)"
        )
        XCTAssertNotEqual(westernOaks.card?.title, "La Cresada Drive", "\(westernOaks)")
        XCTAssertNotEqual(westernOaks.card?.title, "Davis Lane", "\(westernOaks)")
        XCTAssertNotEqual(westernOaks.card?.title, "William H. Russell Karst Preserve", "\(westernOaks)")
        XCTAssertNotEqual(westernOaks.card?.title, "Goat Cave Karst Nature Preserve", "\(westernOaks)")
        XCTAssertEqual(westernOaks.card?.fieldRoute.first, Inspect.caveCard, "\(westernOaks)")
        XCTAssertTrue((westernOaks.card?.doLine.lowercased() ?? "").contains("stay in daylight"), westernOaks.card?.doLine ?? "")
        XCTAssertFalse((westernOaks.card?.doLine.lowercased() ?? "").contains("edible"), westernOaks.card?.doLine ?? "")

        let buttercup = try hold(at: Self.buttercupCave, zoom: 16, packId: "tx-east")
        XCTAssertEqual(buttercup.card?.klass, "Cave or hole", "\(buttercup)")
        XCTAssertNotEqual(buttercup.card?.klass, "Wildlife range", "\(buttercup)")
        XCTAssertEqual(buttercup.card?.title, "Buttercup Creek Cave Preserve", "\(buttercup)")
        XCTAssertNotEqual(buttercup.card?.title, "Stone Well #1", "\(buttercup)")
        XCTAssertNotEqual(buttercup.card?.title, "Good Friday", "\(buttercup)")
        XCTAssertNotEqual(buttercup.card?.title, "Buttercup Blowhole", "\(buttercup)")
        XCTAssertNotEqual(buttercup.card?.title, "Cedar Elm Sink", "\(buttercup)")
        XCTAssertNotEqual(buttercup.card?.title, "Pat's Pit", "\(buttercup)")
        XCTAssertNotEqual(buttercup.card?.title, "Nelson Ranch Road", "\(buttercup)")
        XCTAssertNotEqual(buttercup.card?.title, "Discovery Well Cave Preserve", "\(buttercup)")
        XCTAssertEqual(buttercup.card?.fieldRoute.first, Inspect.caveCard, "\(buttercup)")
        XCTAssertTrue((buttercup.card?.doLine.lowercased() ?? "").contains("stay in daylight"), buttercup.card?.doLine ?? "")
        XCTAssertFalse((buttercup.card?.doLine.lowercased() ?? "").contains("edible"), buttercup.card?.doLine ?? "")

        let pepperRock = try hold(at: Self.pepperRockCave, zoom: 16, packId: "tx-east")
        XCTAssertEqual(pepperRock.card?.klass, "Cave or hole", "\(pepperRock)")
        XCTAssertEqual(pepperRock.card?.title, "Pepper Rock Cave", "\(pepperRock)")
        XCTAssertNotEqual(pepperRock.card?.klass, "Park", "\(pepperRock)")
        XCTAssertNotEqual(pepperRock.card?.title, "Pepper Rock Park", "\(pepperRock)")
        XCTAssertNotEqual(pepperRock.card?.title, "Chatham Wood Drive", "\(pepperRock)")
        XCTAssertEqual(pepperRock.card?.fieldRoute.first, Inspect.caveCard, "\(pepperRock)")
        XCTAssertTrue((pepperRock.card?.doLine.lowercased() ?? "").contains("stay in daylight"), pepperRock.card?.doLine ?? "")
        XCTAssertFalse((pepperRock.card?.doLine.lowercased() ?? "").contains("edible"), pepperRock.card?.doLine ?? "")

        let airmen = try hold(at: Self.airmenCave, zoom: 16, packId: "tx-east")
        XCTAssertEqual(airmen.card?.klass, "Cave or hole", "\(airmen)")
        XCTAssertEqual(airmen.card?.title, "Airmen's Cave", "\(airmen)")
        XCTAssertNotEqual(airmen.card?.title, "Barton Creek Greenbelt", "\(airmen)")
        XCTAssertEqual(airmen.card?.fieldRoute.first, Inspect.caveCard, "\(airmen)")
        XCTAssertTrue((airmen.card?.doLine.lowercased() ?? "").contains("stay in daylight"), airmen.card?.doLine ?? "")
        XCTAssertFalse((airmen.card?.doLine.lowercased() ?? "").contains("edible"), airmen.card?.doLine ?? "")

        let treeHouse = try hold(at: Self.treeHouseCave, zoom: 16, packId: "tx-east")
        XCTAssertEqual(treeHouse.card?.klass, "Cave or hole", "\(treeHouse)")
        XCTAssertEqual(treeHouse.card?.title, "Tree House Cave", "\(treeHouse)")
        XCTAssertNotEqual(treeHouse.card?.title, "Buttercup Creek Cave Preserve", "\(treeHouse)")
        XCTAssertNotEqual(treeHouse.card?.title, "Andrew Cove", "\(treeHouse)")
        XCTAssertNotEqual(treeHouse.card?.title, "Godzilla Cave", "\(treeHouse)")
        XCTAssertNotEqual(treeHouse.card?.title, "Warton Whirlpool", "\(treeHouse)")
        XCTAssertEqual(treeHouse.card?.fieldRoute.first, Inspect.caveCard, "\(treeHouse)")
        XCTAssertTrue((treeHouse.card?.doLine.lowercased() ?? "").contains("stay in daylight"), treeHouse.card?.doLine ?? "")
        XCTAssertFalse((treeHouse.card?.doLine.lowercased() ?? "").contains("edible"), treeHouse.card?.doLine ?? "")

        let hideaway = try hold(at: Self.hideawayCave, zoom: 16, packId: "tx-east")
        XCTAssertEqual(hideaway.card?.klass, "Cave or hole", "\(hideaway)")
        XCTAssertEqual(hideaway.card?.title, "Hideaway", "\(hideaway)")
        XCTAssertNotEqual(hideaway.card?.klass, "Open reserve", "\(hideaway)")
        XCTAssertNotEqual(hideaway.card?.title, "Westside Preserve", "\(hideaway)")
        XCTAssertNotEqual(hideaway.card?.title, "Nelson Ranch Loop", "\(hideaway)")
        XCTAssertNotEqual(hideaway.card?.title, "Buttercup Creek Cave Preserve", "\(hideaway)")
        XCTAssertNotEqual(hideaway.card?.title, "Buttercup Drain Cave", "\(hideaway)")
        XCTAssertEqual(hideaway.card?.fieldRoute.first, Inspect.caveCard, "\(hideaway)")
        XCTAssertTrue((hideaway.card?.doLine.lowercased() ?? "").contains("stay in daylight"), hideaway.card?.doLine ?? "")
        XCTAssertFalse((hideaway.card?.doLine.lowercased() ?? "").contains("edible"), hideaway.card?.doLine ?? "")

        let buttercupWind = try hold(at: Self.buttercupWindCave, zoom: 16, packId: "tx-east")
        XCTAssertEqual(buttercupWind.card?.klass, "Cave or hole", "\(buttercupWind)")
        XCTAssertEqual(buttercupWind.card?.title, "Buttercup Wind", "\(buttercupWind)")
        XCTAssertNotEqual(buttercupWind.card?.title, "Shea Drive", "\(buttercupWind)")
        XCTAssertNotEqual(buttercupWind.card?.title, "Lauren Trail", "\(buttercupWind)")
        XCTAssertNotEqual(buttercupWind.card?.title, "Godzilla Preserve", "\(buttercupWind)")
        XCTAssertNotEqual(buttercupWind.card?.title, "Godzilla Cave", "\(buttercupWind)")
        XCTAssertNotEqual(buttercupWind.card?.title, "Discovery Well Cave Preserve", "\(buttercupWind)")
        XCTAssertEqual(buttercupWind.card?.fieldRoute.first, Inspect.caveCard, "\(buttercupWind)")
        XCTAssertTrue((buttercupWind.card?.doLine.lowercased() ?? "").contains("stay in daylight"), buttercupWind.card?.doLine ?? "")
        XCTAssertFalse((buttercupWind.card?.doLine.lowercased() ?? "").contains("edible"), buttercupWind.card?.doLine ?? "")

        let blowhole = try hold(at: Self.buttercupBlowhole, zoom: 16, packId: "tx-east")
        XCTAssertEqual(blowhole.card?.klass, "Cave or hole", "\(blowhole)")
        XCTAssertEqual(blowhole.card?.title, "Buttercup Blowhole", "\(blowhole)")
        XCTAssertNotEqual(blowhole.card?.title, "Buttercup Creek Cave Preserve", "\(blowhole)")
        XCTAssertNotEqual(blowhole.card?.title, "Buttercup Creek Boulevard", "\(blowhole)")
        XCTAssertNotEqual(blowhole.card?.title, "Stone Well #2", "\(blowhole)")
        XCTAssertNotEqual(blowhole.card?.title, "Tree House Cave", "\(blowhole)")
        XCTAssertNotEqual(blowhole.card?.title, "Cedar Elm Sink", "\(blowhole)")
        XCTAssertNotEqual(blowhole.card?.title, "Pat's Pit", "\(blowhole)")
        XCTAssertEqual(blowhole.card?.fieldRoute.first, Inspect.caveCard, "\(blowhole)")
        XCTAssertTrue((blowhole.card?.doLine.lowercased() ?? "").contains("stay in daylight"), blowhole.card?.doLine ?? "")
        XCTAssertFalse((blowhole.card?.doLine.lowercased() ?? "").contains("edible"), blowhole.card?.doLine ?? "")

        let limeSink = try hold(at: Self.limeCreekRoadSink, zoom: 16, packId: "tx-east")
        XCTAssertEqual(limeSink.card?.klass, "Cave or hole", "\(limeSink)")
        XCTAssertEqual(limeSink.card?.title, "Lime Creek Road Sink", "\(limeSink)")
        XCTAssertNotEqual(limeSink.card?.title, "Discovery Well Cave Preserve", "\(limeSink)")
        XCTAssertNotEqual(limeSink.card?.title, "Anderson Mill Road", "\(limeSink)")
        XCTAssertNotEqual(limeSink.card?.title, "Blue Loop", "\(limeSink)")
        XCTAssertNotEqual(limeSink.card?.title, "Lime Creek Road", "\(limeSink)")
        XCTAssertNotEqual(limeSink.card?.title, "Balcones Canyonlands Preserve - Lime Creek", "\(limeSink)")
        XCTAssertNotEqual(limeSink.card?.title, "Under Three Oaks", "\(limeSink)")
        XCTAssertNotEqual(limeSink.card?.title, "Persimmon Well", "\(limeSink)")
        XCTAssertEqual(limeSink.card?.fieldRoute.first, Inspect.caveCard, "\(limeSink)")
        XCTAssertTrue((limeSink.card?.doLine.lowercased() ?? "").contains("stay in daylight"), limeSink.card?.doLine ?? "")
        XCTAssertFalse((limeSink.card?.doLine.lowercased() ?? "").contains("edible"), limeSink.card?.doLine ?? "")

        let cedarElm = try hold(at: Self.cedarElmSink, zoom: 16, packId: "tx-east")
        XCTAssertEqual(cedarElm.card?.klass, "Cave or hole", "\(cedarElm)")
        XCTAssertEqual(cedarElm.card?.title, "Cedar Elm Sink", "\(cedarElm)")
        XCTAssertNotEqual(cedarElm.card?.title, "Buttercup Creek Cave Preserve", "\(cedarElm)")
        XCTAssertNotEqual(cedarElm.card?.title, "Buttercup Blowhole", "\(cedarElm)")
        XCTAssertNotEqual(cedarElm.card?.title, "Anna Court", "\(cedarElm)")
        XCTAssertNotEqual(cedarElm.card?.title, "Cedar Elm Preserve Trail", "\(cedarElm)")
        XCTAssertNotEqual(cedarElm.card?.title, "Brook Meadow Trail", "\(cedarElm)")
        XCTAssertNotEqual(cedarElm.card?.title, "Pat's Pit", "\(cedarElm)")
        XCTAssertNotEqual(cedarElm.card?.title, "Good Friday", "\(cedarElm)")
        XCTAssertEqual(cedarElm.card?.fieldRoute.first, Inspect.caveCard, "\(cedarElm)")
        XCTAssertTrue((cedarElm.card?.doLine.lowercased() ?? "").contains("stay in daylight"), cedarElm.card?.doLine ?? "")
        XCTAssertFalse((cedarElm.card?.doLine.lowercased() ?? "").contains("edible"), cedarElm.card?.doLine ?? "")

        let threeOaks = try hold(at: Self.underThreeOaks, zoom: 16, packId: "tx-east")
        XCTAssertEqual(threeOaks.card?.klass, "Cave or hole", "\(threeOaks)")
        XCTAssertEqual(threeOaks.card?.title, "Under Three Oaks", "\(threeOaks)")
        XCTAssertNotEqual(threeOaks.card?.title, "Discovery Well Cave Preserve", "\(threeOaks)")
        XCTAssertNotEqual(threeOaks.card?.title, "Lime Creek Road Sink", "\(threeOaks)")
        XCTAssertNotEqual(threeOaks.card?.title, "Anderson Mill Road", "\(threeOaks)")
        XCTAssertNotEqual(threeOaks.card?.title, "Blue Loop", "\(threeOaks)")
        XCTAssertNotEqual(threeOaks.card?.title, "Blue Loop (Three Oaks)", "\(threeOaks)")
        XCTAssertNotEqual(threeOaks.card?.title, "Persimmon Well", "\(threeOaks)")
        XCTAssertEqual(threeOaks.card?.fieldRoute.first, Inspect.caveCard, "\(threeOaks)")
        XCTAssertTrue((threeOaks.card?.doLine.lowercased() ?? "").contains("stay in daylight"), threeOaks.card?.doLine ?? "")
        XCTAssertFalse((threeOaks.card?.doLine.lowercased() ?? "").contains("edible"), threeOaks.card?.doLine ?? "")

        let drainCave = try hold(at: Self.buttercupDrainCave, zoom: 16, packId: "tx-east")
        XCTAssertEqual(drainCave.card?.klass, "Cave or hole", "\(drainCave)")
        XCTAssertEqual(drainCave.card?.title, "Buttercup Drain Cave", "\(drainCave)")
        XCTAssertNotEqual(drainCave.card?.klass, "Open reserve", "\(drainCave)")
        XCTAssertNotEqual(drainCave.card?.title, "Westside Preserve", "\(drainCave)")
        XCTAssertNotEqual(drainCave.card?.title, "Hideaway", "\(drainCave)")
        XCTAssertNotEqual(drainCave.card?.title, "Kai Drive", "\(drainCave)")
        XCTAssertNotEqual(drainCave.card?.title, "Burnie Bishop Place", "\(drainCave)")
        XCTAssertEqual(drainCave.card?.fieldRoute.first, Inspect.caveCard, "\(drainCave)")
        XCTAssertTrue((drainCave.card?.doLine.lowercased() ?? "").contains("stay in daylight"), drainCave.card?.doLine ?? "")
        XCTAssertFalse((drainCave.card?.doLine.lowercased() ?? "").contains("edible"), drainCave.card?.doLine ?? "")

        let warton = try hold(at: Self.wartonWhirlpool, zoom: 16, packId: "tx-east")
        XCTAssertEqual(warton.card?.klass, "Cave or hole", "\(warton)")
        XCTAssertEqual(warton.card?.title, "Warton Whirlpool", "\(warton)")
        XCTAssertNotEqual(warton.card?.title, "Tree House Cave", "\(warton)")
        XCTAssertNotEqual(warton.card?.title, "Janet Bartles Park", "\(warton)")
        XCTAssertNotEqual(warton.card?.title, "Buttercup Creek Boulevard", "\(warton)")
        XCTAssertNotEqual(warton.card?.title, "Buttercup Creek Cave Preserve", "\(warton)")
        XCTAssertEqual(warton.card?.fieldRoute.first, Inspect.caveCard, "\(warton)")
        XCTAssertTrue((warton.card?.doLine.lowercased() ?? "").contains("stay in daylight"), warton.card?.doLine ?? "")
        XCTAssertFalse((warton.card?.doLine.lowercased() ?? "").contains("edible"), warton.card?.doLine ?? "")

        let patsPit = try hold(at: Self.patsPitCave, zoom: 16, packId: "tx-east")
        XCTAssertEqual(patsPit.card?.klass, "Cave or hole", "\(patsPit)")
        XCTAssertEqual(patsPit.card?.title, "Pat's Pit", "\(patsPit)")
        XCTAssertNotEqual(patsPit.card?.title, "Buttercup Creek Cave Preserve", "\(patsPit)")
        XCTAssertNotEqual(patsPit.card?.title, "Buttercup Blowhole", "\(patsPit)")
        XCTAssertNotEqual(patsPit.card?.title, "Cedar Elm Sink", "\(patsPit)")
        XCTAssertNotEqual(patsPit.card?.title, "Anna Court", "\(patsPit)")
        XCTAssertNotEqual(patsPit.card?.title, "Andrew Cove", "\(patsPit)")
        XCTAssertEqual(patsPit.card?.fieldRoute.first, Inspect.caveCard, "\(patsPit)")
        XCTAssertTrue((patsPit.card?.doLine.lowercased() ?? "").contains("stay in daylight"), patsPit.card?.doLine ?? "")
        XCTAssertFalse((patsPit.card?.doLine.lowercased() ?? "").contains("edible"), patsPit.card?.doLine ?? "")

        let goodFriday = try hold(at: Self.goodFriday, zoom: 16, packId: "tx-east")
        XCTAssertEqual(goodFriday.card?.klass, "Cave or hole", "\(goodFriday)")
        XCTAssertEqual(goodFriday.card?.title, "Good Friday", "\(goodFriday)")
        XCTAssertNotEqual(goodFriday.card?.title, "Buttercup Creek Cave Preserve", "\(goodFriday)")
        XCTAssertNotEqual(goodFriday.card?.title, "Brook Meadow Trail", "\(goodFriday)")
        XCTAssertNotEqual(goodFriday.card?.title, "Anna Court", "\(goodFriday)")
        XCTAssertNotEqual(goodFriday.card?.title, "Cedar Elm Sink", "\(goodFriday)")
        XCTAssertNotEqual(goodFriday.card?.title, "Cedar Elm Preserve Trail", "\(goodFriday)")
        XCTAssertNotEqual(goodFriday.card?.title, "Pat's Pit", "\(goodFriday)")
        XCTAssertEqual(goodFriday.card?.fieldRoute.first, Inspect.caveCard, "\(goodFriday)")
        XCTAssertTrue((goodFriday.card?.doLine.lowercased() ?? "").contains("stay in daylight"), goodFriday.card?.doLine ?? "")
        XCTAssertFalse((goodFriday.card?.doLine.lowercased() ?? "").contains("edible"), goodFriday.card?.doLine ?? "")

        let persimmon = try hold(at: Self.persimmonWell, zoom: 16, packId: "tx-east")
        XCTAssertEqual(persimmon.card?.klass, "Cave or hole", "\(persimmon)")
        XCTAssertEqual(persimmon.card?.title, "Persimmon Well", "\(persimmon)")
        XCTAssertNotEqual(persimmon.card?.title, "Discovery Well Cave Preserve", "\(persimmon)")
        XCTAssertNotEqual(persimmon.card?.title, "Lime Creek Road Sink", "\(persimmon)")
        XCTAssertNotEqual(persimmon.card?.title, "Jumbled Rocks", "\(persimmon)")
        XCTAssertNotEqual(persimmon.card?.title, "Red Loop", "\(persimmon)")
        XCTAssertNotEqual(persimmon.card?.title, "Blue Loop", "\(persimmon)")
        XCTAssertEqual(persimmon.card?.fieldRoute.first, Inspect.caveCard, "\(persimmon)")
        XCTAssertTrue((persimmon.card?.doLine.lowercased() ?? "").contains("stay in daylight"), persimmon.card?.doLine ?? "")
        XCTAssertFalse((persimmon.card?.doLine.lowercased() ?? "").contains("edible"), persimmon.card?.doLine ?? "")

        let jumbled = try hold(at: Self.jumbledRocks, zoom: 16, packId: "tx-east")
        XCTAssertEqual(jumbled.card?.klass, "Cave or hole", "\(jumbled)")
        XCTAssertEqual(jumbled.card?.title, "Jumbled Rocks", "\(jumbled)")
        XCTAssertNotEqual(jumbled.card?.title, "Discovery Well Cave Preserve", "\(jumbled)")
        XCTAssertNotEqual(jumbled.card?.title, "Persimmon Well", "\(jumbled)")
        XCTAssertNotEqual(jumbled.card?.title, "Red Loop", "\(jumbled)")
        XCTAssertNotEqual(jumbled.card?.title, "Blue Loop", "\(jumbled)")
        XCTAssertNotEqual(jumbled.card?.title, "Unmarked Cave", "\(jumbled)")
        XCTAssertNotEqual(jumbled.card?.title, "Zig Zag", "\(jumbled)")
        XCTAssertEqual(jumbled.card?.fieldRoute.first, Inspect.caveCard, "\(jumbled)")
        XCTAssertTrue((jumbled.card?.doLine.lowercased() ?? "").contains("stay in daylight"), jumbled.card?.doLine ?? "")
        XCTAssertFalse((jumbled.card?.doLine.lowercased() ?? "").contains("edible"), jumbled.card?.doLine ?? "")
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

        let bastrop = try hold(at: Self.bastropGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(bastrop.card?.klass, "Botanic garden", "\(bastrop)")
        XCTAssertEqual(bastrop.card?.title, "Bastrop Community Garden", "\(bastrop)")
        XCTAssertNotEqual(bastrop.card?.klass, "Park", "\(bastrop)")
        XCTAssertNotEqual(bastrop.card?.title, "Main Street", "\(bastrop)")
        XCTAssertEqual(bastrop.card?.fieldRoute.first, Inspect.plantTXCard, "\(bastrop)")
        XCTAssertFalse(
            bastrop.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Bastrop Community Garden opened woodland tree-use: \(bastrop)"
        )
        XCTAssertFalse((bastrop.card?.doLine.lowercased() ?? "").contains("edible"), bastrop.card?.doLine ?? "")

        let fortDessau = try hold(at: Self.fortDessauGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(fortDessau.card?.klass, "Botanic garden", "\(fortDessau)")
        XCTAssertEqual(fortDessau.card?.title, "Fort Dessau Community Garden", "\(fortDessau)")
        XCTAssertNotEqual(fortDessau.card?.klass, "Park", "\(fortDessau)")
        XCTAssertNotEqual(fortDessau.card?.title, "Fort Dessau Road", "\(fortDessau)")
        XCTAssertNotEqual(fortDessau.card?.title, "Fort Dessau Amenity Center", "\(fortDessau)")
        XCTAssertEqual(fortDessau.card?.fieldRoute.first, Inspect.plantTXCard, "\(fortDessau)")
        XCTAssertFalse(
            fortDessau.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Fort Dessau Community Garden opened woodland tree-use: \(fortDessau)"
        )
        XCTAssertFalse((fortDessau.card?.doLine.lowercased() ?? "").contains("edible"), fortDessau.card?.doLine ?? "")

        let windsor = try hold(at: Self.windsorParkGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(windsor.card?.klass, "Botanic garden", "\(windsor)")
        XCTAssertEqual(windsor.card?.title, "Windsor Park Community Garden", "\(windsor)")
        XCTAssertNotEqual(windsor.card?.klass, "Park", "\(windsor)")
        XCTAssertNotEqual(windsor.card?.title, "Belmoor Drive", "\(windsor)")
        XCTAssertEqual(windsor.card?.fieldRoute.first, Inspect.plantTXCard, "\(windsor)")
        XCTAssertFalse(
            windsor.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Windsor Park Community Garden opened woodland tree-use: \(windsor)"
        )
        XCTAssertFalse((windsor.card?.doLine.lowercased() ?? "").contains("edible"), windsor.card?.doLine ?? "")

        let lamplight = try hold(at: Self.lamplightGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(lamplight.card?.klass, "Botanic garden", "\(lamplight)")
        XCTAssertEqual(lamplight.card?.title, "Lamplight Community Garden", "\(lamplight)")
        XCTAssertNotEqual(lamplight.card?.title, "Lamplight Village Avenue", "\(lamplight)")
        XCTAssertEqual(lamplight.card?.fieldRoute.first, Inspect.plantTXCard, "\(lamplight)")
        XCTAssertFalse(
            lamplight.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Lamplight Community Garden opened woodland tree-use: \(lamplight)"
        )
        XCTAssertFalse((lamplight.card?.doLine.lowercased() ?? "").contains("edible"), lamplight.card?.doLine ?? "")

        let juanNavarro = try hold(at: Self.juanNavarroGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(juanNavarro.card?.klass, "Botanic garden", "\(juanNavarro)")
        XCTAssertEqual(juanNavarro.card?.title, "Juan Navarro High School Community Garden", "\(juanNavarro)")
        XCTAssertNotEqual(juanNavarro.card?.title, "Fairfield Drive", "\(juanNavarro)")
        XCTAssertEqual(juanNavarro.card?.fieldRoute.first, Inspect.plantTXCard, "\(juanNavarro)")
        XCTAssertFalse(
            juanNavarro.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Juan Navarro High School Community Garden opened woodland tree-use: \(juanNavarro)"
        )
        XCTAssertFalse((juanNavarro.card?.doLine.lowercased() ?? "").contains("edible"), juanNavarro.card?.doLine ?? "")

        let unityPark = try hold(at: Self.unityParkGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(unityPark.card?.klass, "Botanic garden", "\(unityPark)")
        XCTAssertEqual(unityPark.card?.title, "Unity Park Community Garden", "\(unityPark)")
        XCTAssertNotEqual(unityPark.card?.title, "Gattis School Road", "\(unityPark)")
        XCTAssertEqual(unityPark.card?.fieldRoute.first, Inspect.plantTXCard, "\(unityPark)")
        XCTAssertFalse(
            unityPark.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Unity Park Community Garden opened woodland tree-use: \(unityPark)"
        )
        XCTAssertFalse((unityPark.card?.doLine.lowercased() ?? "").contains("edible"), unityPark.card?.doLine ?? "")

        let colorado = try hold(at: Self.coloradoGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(colorado.card?.klass, "Botanic garden", "\(colorado)")
        XCTAssertEqual(colorado.card?.title, "Colorado Community Garden", "\(colorado)")
        XCTAssertNotEqual(colorado.card?.klass, "Wildlife range", "\(colorado)")
        XCTAssertNotEqual(colorado.card?.title, "Colorado River Park Wildlife Sanctuary", "\(colorado)")
        XCTAssertNotEqual(colorado.card?.title, "Borger Street", "\(colorado)")
        XCTAssertEqual(colorado.card?.fieldRoute.first, Inspect.plantTXCard, "\(colorado)")
        XCTAssertFalse(
            colorado.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Colorado Community Garden opened woodland tree-use: \(colorado)"
        )
        XCTAssertFalse((colorado.card?.doLine.lowercased() ?? "").contains("edible"), colorado.card?.doLine ?? "")

        let alamo = try hold(at: Self.alamoGarden, zoom: 16, packId: "tx-east")
        XCTAssertEqual(alamo.card?.klass, "Botanic garden", "\(alamo)")
        XCTAssertEqual(alamo.card?.title, "Alamo Community Garden", "\(alamo)")
        XCTAssertNotEqual(alamo.card?.title, "Este Garden", "\(alamo)")
        XCTAssertNotEqual(alamo.card?.title, "Alamo Street", "\(alamo)")
        XCTAssertNotEqual(alamo.card?.title, "Alamo Pocket Park", "\(alamo)")
        XCTAssertEqual(alamo.card?.fieldRoute.first, Inspect.plantTXCard, "\(alamo)")
        XCTAssertFalse(
            alamo.card?.fieldRoute.contains(Inspect.treeUseEastCard) ?? true,
            "Alamo Community Garden opened woodland tree-use: \(alamo)"
        )
        XCTAssertFalse((alamo.card?.doLine.lowercased() ?? "").contains("edible"), alamo.card?.doLine ?? "")

        let barelas = try hold(at: Self.barelasGarden, zoom: 16, packId: "nm")
        XCTAssertEqual(barelas.card?.klass, "Botanic garden", "\(barelas)")
        XCTAssertEqual(barelas.card?.title, "Barelas Community Garden", "\(barelas)")
        XCTAssertNotEqual(barelas.card?.klass, "Park", "\(barelas)")
        XCTAssertNotEqual(barelas.card?.title, "4th Street Southwest", "\(barelas)")
        XCTAssertEqual(barelas.card?.fieldRoute.first, Inspect.plantTXCard, "\(barelas)")
        XCTAssertTrue(
            barelas.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "Barelas Community Garden dropped the NM plant-danger card: \(barelas)"
        )
        XCTAssertFalse(
            barelas.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? true,
            "Barelas Community Garden opened woodland tree-use: \(barelas)"
        )
        XCTAssertFalse((barelas.card?.doLine.lowercased() ?? "").contains("edible"), barelas.card?.doLine ?? "")

        let prisma = try hold(at: Self.coloniaPrisma, zoom: 16, packId: "nm")
        XCTAssertEqual(prisma.card?.klass, "Botanic garden", "\(prisma)")
        XCTAssertEqual(prisma.card?.title, "Colonia Prisma Community Garden", "\(prisma)")
        XCTAssertNotEqual(prisma.card?.klass, "Park", "\(prisma)")
        XCTAssertNotEqual(prisma.card?.klass, "Road", "\(prisma)")
        XCTAssertNotEqual(prisma.card?.title, "Camino Rojo", "\(prisma)")
        XCTAssertNotEqual(prisma.card?.title, "Vuelta Colorada", "\(prisma)")
        XCTAssertEqual(prisma.card?.fieldRoute.first, Inspect.plantTXCard, "\(prisma)")
        XCTAssertTrue(
            prisma.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "Colonia Prisma dropped the NM plant-danger card: \(prisma)"
        )
        XCTAssertFalse(
            prisma.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? true,
            "Colonia Prisma opened woodland tree-use: \(prisma)"
        )
        XCTAssertFalse(
            prisma.card?.fieldRoute.contains(Inspect.cactusNMCard) ?? true,
            "Colonia Prisma opened cactus: \(prisma)"
        )
        XCTAssertFalse((prisma.card?.doLine.lowercased() ?? "").contains("edible"), prisma.card?.doLine ?? "")

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

        let memorialRose = try hold(at: Self.memorialRose, zoom: 16, packId: "nm")
        XCTAssertEqual(memorialRose.card?.klass, "Botanic garden", "\(memorialRose)")
        XCTAssertEqual(memorialRose.card?.title, "Memorial Rose Garden", "\(memorialRose)")
        XCTAssertNotEqual(memorialRose.card?.title, "Albuquerque Rose Garden", "\(memorialRose)")
        XCTAssertNotEqual(memorialRose.card?.title, "Los Alamos Demonstration Garden", "\(memorialRose)")
        XCTAssertEqual(memorialRose.card?.fieldRoute.first, Inspect.plantTXCard, "\(memorialRose)")
        XCTAssertTrue(
            memorialRose.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "Memorial Rose Garden dropped the NM plant-danger card: \(memorialRose)"
        )
        XCTAssertFalse(
            memorialRose.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? true,
            "Memorial Rose Garden opened woodland tree-use: \(memorialRose)"
        )
        XCTAssertFalse((memorialRose.card?.doLine.lowercased() ?? "").contains("edible"), memorialRose.card?.doLine ?? "")

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

        let international = try hold(at: Self.internationalDistrictGarden, zoom: 16, packId: "nm")
        XCTAssertEqual(international.card?.klass, "Botanic garden", "\(international)")
        XCTAssertEqual(international.card?.title, "International District Community Garden", "\(international)")
        XCTAssertEqual(international.card?.fieldRoute.first, Inspect.plantTXCard, "\(international)")
        XCTAssertTrue(
            international.card?.fieldRoute.contains(Inspect.plantNMCard) ?? false,
            "International District Community Garden dropped the NM plant-danger card: \(international)"
        )
        XCTAssertFalse(
            international.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? true,
            "International District Community Garden opened woodland tree-use: \(international)"
        )
        XCTAssertFalse((international.card?.doLine.lowercased() ?? "").contains("edible"), international.card?.doLine ?? "")
    }

    func testHoldingAWildlifeManagementAreaOpensAnimalsNotPicnicWoodland() throws {
        let held = try hold(at: Self.nmWildlifeRange, zoom: 16, packId: "nm")
        XCTAssertEqual(held.card?.klass, "Wildlife range", "\(held)")
        XCTAssertEqual(held.card?.title, "Marquez Wildlife Management Area", "\(held)")
        XCTAssertNotEqual(held.card?.title, "Mesa Blanca", "\(held)")
        XCTAssertNotEqual(held.card?.title, "Cerritos de la Jolla de Santa Rosa", "\(held)")
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
        XCTAssertNotEqual(caldera.card?.title, "San Antonio Mountain", "\(caldera)")
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

        let valle = try hold(at: Self.valleDeOro, zoom: 16, packId: "nm")
        XCTAssertEqual(valle.card?.klass, "Wildlife range", "\(valle)")
        XCTAssertEqual(valle.card?.title, "Valle de Oro National Wildlife Refuge", "\(valle)")
        XCTAssertNotEqual(valle.card?.klass, "Park", "\(valle)")
        XCTAssertNotEqual(valle.card?.title, "Valle del Bosque Park", "\(valle)")
        XCTAssertEqual(valle.card?.fieldRoute.first, Inspect.mammalTXCard, "\(valle)")
        XCTAssertTrue(
            valle.card?.fieldRoute.contains(Inspect.mammalNMCard) ?? false,
            "Valle de Oro dropped the NM mammal card: \(valle)"
        )
        XCTAssertTrue((valle.card?.doLine.lowercased() ?? "").contains("elk is high country"), valle.card?.doLine ?? "")
        XCTAssertFalse((valle.card?.doLine.lowercased() ?? "").contains("javelina"), valle.card?.doLine ?? "")
        XCTAssertFalse((valle.card?.doLine.lowercased() ?? "").contains("edible"), valle.card?.doLine ?? "")

        let laJoya = try hold(at: Self.laJoyaWMA, zoom: 16, packId: "nm")
        XCTAssertEqual(laJoya.card?.klass, "Wildlife range", "\(laJoya)")
        XCTAssertEqual(laJoya.card?.title, "La Joya Wildlife Management Area", "\(laJoya)")
        XCTAssertNotEqual(laJoya.card?.klass, "Park", "\(laJoya)")
        XCTAssertEqual(laJoya.card?.fieldRoute.first, Inspect.mammalTXCard, "\(laJoya)")
        XCTAssertTrue(
            laJoya.card?.fieldRoute.contains(Inspect.mammalNMCard) ?? false,
            "La Joya WMA dropped the NM mammal card: \(laJoya)"
        )
        XCTAssertTrue((laJoya.card?.doLine.lowercased() ?? "").contains("elk is high country"), laJoya.card?.doLine ?? "")
        XCTAssertFalse((laJoya.card?.doLine.lowercased() ?? "").contains("javelina"), laJoya.card?.doLine ?? "")
        XCTAssertFalse((laJoya.card?.doLine.lowercased() ?? "").contains("edible"), laJoya.card?.doLine ?? "")

        let rioRancho = try hold(at: Self.rioRanchoBosque, zoom: 16, packId: "nm")
        XCTAssertEqual(rioRancho.card?.klass, "Wildlife range", "\(rioRancho)")
        XCTAssertEqual(rioRancho.card?.title, "Rio Rancho Bosque Nature Preserve", "\(rioRancho)")
        XCTAssertNotEqual(rioRancho.card?.klass, "Bosque or wetland", "\(rioRancho)")
        XCTAssertNotEqual(rioRancho.card?.klass, "Open reserve", "\(rioRancho)")
        XCTAssertNotEqual(rioRancho.card?.title, "Rio Rancho Bosque South Trail", "\(rioRancho)")
        XCTAssertEqual(rioRancho.card?.fieldRoute.first, Inspect.mammalTXCard, "\(rioRancho)")
        XCTAssertTrue(
            rioRancho.card?.fieldRoute.contains(Inspect.mammalNMCard) ?? false,
            "Rio Rancho Bosque dropped the NM mammal card: \(rioRancho)"
        )
        XCTAssertFalse((rioRancho.card?.doLine.lowercased() ?? "").contains("cottonwood"), rioRancho.card?.doLine ?? "")
        XCTAssertFalse((rioRancho.card?.doLine.lowercased() ?? "").contains("edible"), rioRancho.card?.doLine ?? "")

        let pecos = try hold(at: Self.pecosComplex, zoom: 16, packId: "nm")
        XCTAssertEqual(pecos.card?.klass, "Wildlife range", "\(pecos)")
        XCTAssertEqual(pecos.card?.title, "Pecos River Complex Wildlife Management Areas", "\(pecos)")
        XCTAssertNotEqual(pecos.card?.klass, "Open reserve", "\(pecos)")
        XCTAssertNotEqual(pecos.card?.title, "State Highway 63", "\(pecos)")
        XCTAssertEqual(pecos.card?.fieldRoute.first, Inspect.mammalTXCard, "\(pecos)")
        XCTAssertTrue(
            pecos.card?.fieldRoute.contains(Inspect.mammalNMCard) ?? false,
            "Pecos River Complex dropped the NM mammal card: \(pecos)"
        )
        XCTAssertTrue((pecos.card?.doLine.lowercased() ?? "").contains("elk is high country"), pecos.card?.doLine ?? "")
        XCTAssertFalse((pecos.card?.doLine.lowercased() ?? "").contains("javelina"), pecos.card?.doLine ?? "")
        XCTAssertFalse((pecos.card?.doLine.lowercased() ?? "").contains("edible"), pecos.card?.doLine ?? "")

        let natureCenter = try hold(at: Self.rioGrandeNature, zoom: 16, packId: "nm")
        XCTAssertEqual(natureCenter.card?.klass, "Wildlife range", "\(natureCenter)")
        XCTAssertEqual(natureCenter.card?.title, "Rio Grande Nature Center State Park", "\(natureCenter)")
        XCTAssertNotEqual(natureCenter.card?.klass, "Bosque or wetland", "\(natureCenter)")
        XCTAssertNotEqual(natureCenter.card?.klass, "Park", "\(natureCenter)")
        XCTAssertNotEqual(natureCenter.card?.title, "Calle del Bosque Northwest", "\(natureCenter)")
        XCTAssertNotEqual(natureCenter.card?.title, "Calle Grande Northwest", "\(natureCenter)")
        XCTAssertEqual(natureCenter.card?.fieldRoute.first, Inspect.mammalTXCard, "\(natureCenter)")
        XCTAssertTrue(
            natureCenter.card?.fieldRoute.contains(Inspect.mammalNMCard) ?? false,
            "Rio Grande Nature Center dropped the NM mammal card: \(natureCenter)"
        )
        XCTAssertTrue((natureCenter.card?.doLine.lowercased() ?? "").contains("elk is high country"), natureCenter.card?.doLine ?? "")
        XCTAssertFalse((natureCenter.card?.doLine.lowercased() ?? "").contains("cottonwood"), natureCenter.card?.doLine ?? "")
        XCTAssertFalse((natureCenter.card?.doLine.lowercased() ?? "").contains("edible"), natureCenter.card?.doLine ?? "")

        let gameLand = try hold(at: Self.gameCommission, zoom: 16, packId: "nm")
        XCTAssertEqual(gameLand.card?.klass, "Wildlife range", "\(gameLand)")
        XCTAssertEqual(gameLand.card?.title, "State Game Commission Land", "\(gameLand)")
        XCTAssertNotEqual(gameLand.card?.klass, "Open reserve", "\(gameLand)")
        XCTAssertNotEqual(gameLand.card?.title, "Rio Grande Stables Road", "\(gameLand)")
        XCTAssertEqual(gameLand.card?.fieldRoute.first, Inspect.mammalTXCard, "\(gameLand)")
        XCTAssertTrue(
            gameLand.card?.fieldRoute.contains(Inspect.mammalNMCard) ?? false,
            "State Game Commission Land dropped the NM mammal card: \(gameLand)"
        )
        XCTAssertTrue((gameLand.card?.doLine.lowercased() ?? "").contains("elk is high country"), gameLand.card?.doLine ?? "")
        XCTAssertFalse((gameLand.card?.doLine.lowercased() ?? "").contains("javelina"), gameLand.card?.doLine ?? "")
        XCTAssertFalse((gameLand.card?.doLine.lowercased() ?? "").contains("edible"), gameLand.card?.doLine ?? "")

        let sevilleta = try hold(at: Self.sevilleta, zoom: 16, packId: "nm")
        XCTAssertEqual(sevilleta.card?.klass, "Wildlife range", "\(sevilleta)")
        XCTAssertEqual(sevilleta.card?.title, "Sevilleta National Wildlife Refuge", "\(sevilleta)")
        XCTAssertNotEqual(sevilleta.card?.klass, "Open reserve", "\(sevilleta)")
        XCTAssertNotEqual(sevilleta.card?.klass, "Road", "\(sevilleta)")
        XCTAssertNotEqual(sevilleta.card?.title, "Old Highway 85", "\(sevilleta)")
        XCTAssertEqual(sevilleta.card?.fieldRoute.first, Inspect.mammalTXCard, "\(sevilleta)")
        XCTAssertTrue(
            sevilleta.card?.fieldRoute.contains(Inspect.mammalNMCard) ?? false,
            "Sevilleta dropped the NM mammal card: \(sevilleta)"
        )
        XCTAssertTrue((sevilleta.card?.doLine.lowercased() ?? "").contains("elk is high country"), sevilleta.card?.doLine ?? "")
        XCTAssertFalse((sevilleta.card?.doLine.lowercased() ?? "").contains("javelina"), sevilleta.card?.doLine ?? "")
        XCTAssertFalse((sevilleta.card?.doLine.lowercased() ?? "").contains("edible"), sevilleta.card?.doLine ?? "")
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

        let winds = try hold(at: Self.caveOfTheWinds, zoom: 16, packId: "nm")
        XCTAssertEqual(winds.card?.klass, "Cave or hole", "\(winds)")
        XCTAssertEqual(winds.card?.title, "Cave of the Winds", "\(winds)")
        XCTAssertNotEqual(winds.card?.title, "Cave of the Winds Trail", "\(winds)")
        XCTAssertEqual(winds.card?.fieldRoute.first, Inspect.caveCard, "\(winds)")
        XCTAssertTrue((winds.card?.doLine.lowercased() ?? "").contains("stay in daylight"), winds.card?.doLine ?? "")
        XCTAssertFalse((winds.card?.doLine.lowercased() ?? "").contains("edible"), winds.card?.doLine ?? "")

        let painted = try hold(at: Self.paintedCave, zoom: 16, packId: "nm")
        XCTAssertEqual(painted.card?.klass, "Cave or hole", "\(painted)")
        XCTAssertEqual(painted.card?.title, "Painted Cave", "\(painted)")
        XCTAssertNotEqual(painted.card?.klass, "Open reserve", "\(painted)")
        XCTAssertNotEqual(painted.card?.title, "Bandelier National Monument", "\(painted)")
        XCTAssertNotEqual(painted.card?.title, "Lower Capulin Trail", "\(painted)")
        XCTAssertEqual(painted.card?.fieldRoute.first, Inspect.caveCard, "\(painted)")
        XCTAssertTrue((painted.card?.doLine.lowercased() ?? "").contains("stay in daylight"), painted.card?.doLine ?? "")
        XCTAssertFalse((painted.card?.doLine.lowercased() ?? "").contains("edible"), painted.card?.doLine ?? "")

        let hotSprings = try hold(at: Self.hotSpringsCave, zoom: 16, packId: "nm")
        XCTAssertEqual(hotSprings.card?.klass, "Cave or hole", "\(hotSprings)")
        XCTAssertEqual(hotSprings.card?.title, "Hot Springs Cave", "\(hotSprings)")
        XCTAssertNotEqual(hotSprings.card?.klass, "Open reserve", "\(hotSprings)")
        XCTAssertNotEqual(hotSprings.card?.klass, "Rock", "\(hotSprings)")
        XCTAssertNotEqual(hotSprings.card?.title, "Jemez National Recreation Area", "\(hotSprings)")
        XCTAssertNotEqual(hotSprings.card?.title, "Soda Dam", "\(hotSprings)")
        XCTAssertNotEqual(hotSprings.card?.title, "Painted Cave", "\(hotSprings)")
        XCTAssertEqual(hotSprings.card?.fieldRoute.first, Inspect.caveCard, "\(hotSprings)")
        XCTAssertTrue((hotSprings.card?.doLine.lowercased() ?? "").contains("stay in daylight"), hotSprings.card?.doLine ?? "")
        XCTAssertFalse((hotSprings.card?.doLine.lowercased() ?? "").contains("edible"), hotSprings.card?.doLine ?? "")
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

        let andres = try hold(at: Self.sanAndresPeak, zoom: 16)
        XCTAssertEqual(andres.card?.klass, "Peak", "\(andres)")
        XCTAssertEqual(andres.card?.title, "San Andres Peak", "\(andres)")
        XCTAssertNotEqual(andres.card?.klass, "Wildlife range", "\(andres)")
        XCTAssertNotEqual(andres.card?.title, "San Andres National Wildlife Refuge", "\(andres)")
        XCTAssertNotEqual(andres.card?.title, "Mount Franklin", "\(andres)")
        XCTAssertNotEqual(andres.card?.title, "Big Brushy Mountain", "\(andres)")
        XCTAssertNotEqual(andres.card?.title, "Gardner Peak", "\(andres)")
        let andresDo = andres.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(andresDo.contains("javelina"), andres.card?.doLine ?? "")
        XCTAssertTrue(andresDo.contains("give it the road"), andres.card?.doLine ?? "")
        XCTAssertFalse(andresDo.contains("hog"), andres.card?.doLine ?? "")
        XCTAssertFalse(andresDo.contains("edible"), andres.card?.doLine ?? "")
        let andresPresent = InspectField.presentRoute(andres.card?.fieldRoute ?? [], in: texas)
        XCTAssertEqual(andresPresent.first, Inspect.mammalTXCard, "\(andres)")
        XCTAssertEqual(InspectField.label(for: andresPresent.first ?? ""), "FIELD · ANIMAL")
        XCTAssertEqual(InspectField.bookLine(for: andresPresent), "ANIMAL · BITE · COLD")

        let gato = try hold(at: Self.lomaElGato, zoom: 16)
        XCTAssertEqual(gato.card?.klass, "Peak", "\(gato)")
        XCTAssertEqual(gato.card?.title, "Loma El Gato", "\(gato)")
        XCTAssertNotEqual(gato.card?.klass, "Wildlife range", "\(gato)")
        XCTAssertNotEqual(
            gato.card?.title,
            "Área de Protección de Flora y Fauna Médanos de Samalayuca",
            "\(gato)"
        )
        XCTAssertNotEqual(gato.card?.title, "San Andres Peak", "\(gato)")
        XCTAssertNotEqual(gato.card?.title, "Mount Franklin", "\(gato)")
        let gatoDo = gato.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(gatoDo.contains("javelina"), gato.card?.doLine ?? "")
        XCTAssertTrue(gatoDo.contains("give it the road"), gato.card?.doLine ?? "")
        XCTAssertFalse(gatoDo.contains("hog"), gato.card?.doLine ?? "")
        XCTAssertFalse(gatoDo.contains("edible"), gato.card?.doLine ?? "")
        let gatoPresent = InspectField.presentRoute(gato.card?.fieldRoute ?? [], in: texas)
        XCTAssertEqual(gatoPresent.first, Inspect.mammalTXCard, "\(gato)")
        XCTAssertEqual(InspectField.label(for: gatoPresent.first ?? ""), "FIELD · ANIMAL")
        XCTAssertEqual(InspectField.bookLine(for: gatoPresent), "ANIMAL · BITE · COLD")

        let bennett = try hold(at: Self.bennettMountain, zoom: 16)
        XCTAssertEqual(bennett.card?.klass, "Peak", "\(bennett)")
        XCTAssertEqual(bennett.card?.title, "Bennett Mountain", "\(bennett)")
        XCTAssertNotEqual(bennett.card?.klass, "Wildlife range", "\(bennett)")
        XCTAssertNotEqual(bennett.card?.title, "San Andres National Wildlife Refuge", "\(bennett)")
        XCTAssertNotEqual(bennett.card?.title, "San Andres Peak", "\(bennett)")
        XCTAssertNotEqual(bennett.card?.title, "Mount Franklin", "\(bennett)")
        XCTAssertNotEqual(bennett.card?.title, "Goat Mountain", "\(bennett)")
        XCTAssertNotEqual(bennett.card?.title, "Big Brushy Mountain", "\(bennett)")
        XCTAssertNotEqual(bennett.card?.title, "Gardner Peak", "\(bennett)")
        let bennettDo = bennett.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(bennettDo.contains("javelina"), bennett.card?.doLine ?? "")
        XCTAssertTrue(bennettDo.contains("give it the road"), bennett.card?.doLine ?? "")
        XCTAssertFalse(bennettDo.contains("hog"), bennett.card?.doLine ?? "")
        XCTAssertFalse(bennettDo.contains("edible"), bennett.card?.doLine ?? "")
        let bennettPresent = InspectField.presentRoute(bennett.card?.fieldRoute ?? [], in: texas)
        XCTAssertEqual(bennettPresent.first, Inspect.mammalTXCard, "\(bennett)")
        XCTAssertEqual(InspectField.label(for: bennettPresent.first ?? ""), "FIELD · ANIMAL")
        XCTAssertEqual(InspectField.bookLine(for: bennettPresent), "ANIMAL · BITE · COLD")

        let brushy = try hold(at: Self.bigBrushyMountain, zoom: 16)
        XCTAssertEqual(brushy.card?.klass, "Peak", "\(brushy)")
        XCTAssertEqual(brushy.card?.title, "Big Brushy Mountain", "\(brushy)")
        XCTAssertNotEqual(brushy.card?.klass, "Wildlife range", "\(brushy)")
        XCTAssertNotEqual(brushy.card?.title, "San Andres National Wildlife Refuge", "\(brushy)")
        XCTAssertNotEqual(brushy.card?.title, "San Andres Peak", "\(brushy)")
        XCTAssertNotEqual(brushy.card?.title, "Bennett Mountain", "\(brushy)")
        XCTAssertNotEqual(brushy.card?.title, "Mount Franklin", "\(brushy)")
        XCTAssertNotEqual(brushy.card?.title, "Goat Mountain", "\(brushy)")
        XCTAssertNotEqual(brushy.card?.title, "Gardner Peak", "\(brushy)")
        let brushyDo = brushy.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(brushyDo.contains("javelina"), brushy.card?.doLine ?? "")
        XCTAssertTrue(brushyDo.contains("give it the road"), brushy.card?.doLine ?? "")
        XCTAssertFalse(brushyDo.contains("hog"), brushy.card?.doLine ?? "")
        XCTAssertFalse(brushyDo.contains("edible"), brushy.card?.doLine ?? "")
        let brushyPresent = InspectField.presentRoute(brushy.card?.fieldRoute ?? [], in: texas)
        XCTAssertEqual(brushyPresent.first, Inspect.mammalTXCard, "\(brushy)")
        XCTAssertEqual(InspectField.label(for: brushyPresent.first ?? ""), "FIELD · ANIMAL")
        XCTAssertEqual(InspectField.bookLine(for: brushyPresent), "ANIMAL · BITE · COLD")

        let gardner = try hold(at: Self.gardnerPeak, zoom: 16)
        XCTAssertEqual(gardner.card?.klass, "Peak", "\(gardner)")
        XCTAssertEqual(gardner.card?.title, "Gardner Peak", "\(gardner)")
        XCTAssertNotEqual(gardner.card?.klass, "Wildlife range", "\(gardner)")
        XCTAssertNotEqual(gardner.card?.title, "San Andres National Wildlife Refuge", "\(gardner)")
        XCTAssertNotEqual(gardner.card?.title, "San Andres Peak", "\(gardner)")
        XCTAssertNotEqual(gardner.card?.title, "Bennett Mountain", "\(gardner)")
        XCTAssertNotEqual(gardner.card?.title, "Big Brushy Mountain", "\(gardner)")
        XCTAssertNotEqual(gardner.card?.title, "Mount Franklin", "\(gardner)")
        XCTAssertNotEqual(gardner.card?.title, "Goat Mountain", "\(gardner)")
        XCTAssertNotEqual(gardner.card?.title, "Block Mountain", "\(gardner)")
        let gardnerDo = gardner.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(gardnerDo.contains("javelina"), gardner.card?.doLine ?? "")
        XCTAssertTrue(gardnerDo.contains("give it the road"), gardner.card?.doLine ?? "")
        XCTAssertFalse(gardnerDo.contains("hog"), gardner.card?.doLine ?? "")
        XCTAssertFalse(gardnerDo.contains("edible"), gardner.card?.doLine ?? "")
        let gardnerPresent = InspectField.presentRoute(gardner.card?.fieldRoute ?? [], in: texas)
        XCTAssertEqual(gardnerPresent.first, Inspect.mammalTXCard, "\(gardner)")
        XCTAssertEqual(InspectField.label(for: gardnerPresent.first ?? ""), "FIELD · ANIMAL")
        XCTAssertEqual(InspectField.bookLine(for: gardnerPresent), "ANIMAL · BITE · COLD")
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

        let lucas = try hold(at: Self.mountLucas, zoom: 16, packId: "tx-east")
        XCTAssertEqual(lucas.card?.klass, "Peak", "\(lucas)")
        XCTAssertEqual(lucas.card?.title, "Mount Lucas", "\(lucas)")
        XCTAssertNotEqual(lucas.card?.klass, "Wildlife range", "\(lucas)")
        XCTAssertNotEqual(lucas.card?.title, "Bright Leaf Natural Area", "\(lucas)")
        XCTAssertNotEqual(lucas.card?.title, "Trail #3", "\(lucas)")
        XCTAssertNotEqual(lucas.card?.title, "Mount Bonnell Road", "\(lucas)")
        XCTAssertNotEqual(lucas.card?.title, "Barton Hill", "\(lucas)")
        let lucasDo = lucas.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(lucasDo.contains("hog"), lucas.card?.doLine ?? "")
        XCTAssertTrue(lucasDo.contains("give it the road"), lucas.card?.doLine ?? "")
        XCTAssertFalse(lucasDo.contains("javelina"), lucas.card?.doLine ?? "")
        XCTAssertFalse(lucasDo.contains("edible"), lucas.card?.doLine ?? "")
        let lucasPresent = InspectField.presentRoute(lucas.card?.fieldRoute ?? [], in: east)
        XCTAssertEqual(lucasPresent.first, Inspect.mammalEastCard, "\(lucas)")
        XCTAssertEqual(InspectField.label(for: lucasPresent.first ?? ""), "FIELD · ANIMAL")
        XCTAssertEqual(InspectField.bookLine(for: lucasPresent), "ANIMAL · BITE · COLD")
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

        let losLunas = try hold(at: Self.elCerroLosLunas, zoom: 16, packId: "nm")
        XCTAssertEqual(losLunas.card?.klass, "Open reserve", "\(losLunas)")
        XCTAssertEqual(losLunas.card?.title, "El Cerro de Los Lunas Preserve", "\(losLunas)")
        XCTAssertNotEqual(losLunas.card?.klass, "Wildlife range", "\(losLunas)")
        XCTAssertNotEqual(losLunas.card?.title, "Sunrise Trail", "\(losLunas)")
        XCTAssertEqual(losLunas.card?.fieldRoute.first, Inspect.snakeTXCard, "\(losLunas)")
        XCTAssertTrue(
            losLunas.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "El Cerro de Los Lunas dropped the NM snake card: \(losLunas)"
        )
        let losDo = losLunas.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(losDo.contains("rattler") || losDo.contains("diamondback"), losLunas.card?.doLine ?? "")
        XCTAssertTrue(losDo.contains("sotol") || losDo.contains("cholla"), losLunas.card?.doLine ?? "")
        XCTAssertFalse(losDo.contains("javelina"), losLunas.card?.doLine ?? "")
        XCTAssertFalse(losDo.contains("edible"), losLunas.card?.doLine ?? "")

        let galisteo = try hold(at: Self.galisteoBasin, zoom: 16, packId: "nm")
        XCTAssertEqual(galisteo.card?.klass, "Open reserve", "\(galisteo)")
        XCTAssertEqual(galisteo.card?.title, "Galisteo Basin Preserve", "\(galisteo)")
        XCTAssertNotEqual(galisteo.card?.klass, "Wildlife range", "\(galisteo)")
        XCTAssertNotEqual(galisteo.card?.title, "The Haozous Garden", "\(galisteo)")
        XCTAssertEqual(galisteo.card?.fieldRoute.first, Inspect.snakeTXCard, "\(galisteo)")
        XCTAssertTrue(
            galisteo.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Galisteo Basin dropped the NM snake card: \(galisteo)"
        )
        let galDo = galisteo.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(galDo.contains("rattler") || galDo.contains("diamondback"), galisteo.card?.doLine ?? "")
        XCTAssertTrue(galDo.contains("sotol") || galDo.contains("cholla"), galisteo.card?.doLine ?? "")
        XCTAssertFalse(galDo.contains("javelina"), galisteo.card?.doLine ?? "")
        XCTAssertFalse(galDo.contains("edible"), galisteo.card?.doLine ?? "")

        let placitas = try hold(at: Self.placitasOpenSpace, zoom: 16, packId: "nm")
        XCTAssertEqual(placitas.card?.klass, "Open reserve", "\(placitas)")
        XCTAssertEqual(placitas.card?.title, "Placitas Open Space", "\(placitas)")
        XCTAssertNotEqual(placitas.card?.klass, "Park", "\(placitas)")
        XCTAssertNotEqual(placitas.card?.title, "Pipeline Rd. Tr.", "\(placitas)")
        XCTAssertEqual(placitas.card?.fieldRoute.first, Inspect.snakeTXCard, "\(placitas)")
        XCTAssertTrue(
            placitas.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Placitas Open Space dropped the NM snake card: \(placitas)"
        )
        let placitasDo = placitas.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(placitasDo.contains("rattler") || placitasDo.contains("diamondback"), placitas.card?.doLine ?? "")
        XCTAssertTrue(placitasDo.contains("sotol") || placitasDo.contains("cholla"), placitas.card?.doLine ?? "")
        XCTAssertFalse(placitasDo.contains("javelina"), placitas.card?.doLine ?? "")
        XCTAssertFalse(placitasDo.contains("edible"), placitas.card?.doLine ?? "")

        let petroglyph = try hold(at: Self.petroglyphMonument, zoom: 16, packId: "nm")
        XCTAssertEqual(petroglyph.card?.klass, "Open reserve", "\(petroglyph)")
        XCTAssertEqual(petroglyph.card?.title, "Petroglyph National Monument", "\(petroglyph)")
        XCTAssertNotEqual(petroglyph.card?.klass, "Wildlife range", "\(petroglyph)")
        XCTAssertNotEqual(petroglyph.card?.title, "Paseo de la Mesa Open Space", "\(petroglyph)")
        XCTAssertEqual(petroglyph.card?.fieldRoute.first, Inspect.snakeTXCard, "\(petroglyph)")
        XCTAssertTrue(
            petroglyph.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Petroglyph National Monument dropped the NM snake card: \(petroglyph)"
        )
        let petroDo = petroglyph.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(petroDo.contains("rattler") || petroDo.contains("diamondback"), petroglyph.card?.doLine ?? "")
        XCTAssertTrue(petroDo.contains("sotol") || petroDo.contains("cholla"), petroglyph.card?.doLine ?? "")
        XCTAssertFalse(petroDo.contains("javelina"), petroglyph.card?.doLine ?? "")
        XCTAssertFalse(petroDo.contains("edible"), petroglyph.card?.doLine ?? "")

        let cerrillos = try hold(at: Self.cerrillosHills, zoom: 16, packId: "nm")
        XCTAssertEqual(cerrillos.card?.klass, "Open reserve", "\(cerrillos)")
        XCTAssertEqual(cerrillos.card?.title, "Cerrillos Hills State Park", "\(cerrillos)")
        XCTAssertNotEqual(cerrillos.card?.klass, "Park", "\(cerrillos)")
        XCTAssertNotEqual(cerrillos.card?.title, "Galisteo Basin Preserve", "\(cerrillos)")
        XCTAssertEqual(cerrillos.card?.fieldRoute.first, Inspect.snakeTXCard, "\(cerrillos)")
        XCTAssertTrue(
            cerrillos.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Cerrillos Hills dropped the NM snake card: \(cerrillos)"
        )
        let cerrillosDo = cerrillos.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(cerrillosDo.contains("rattler") || cerrillosDo.contains("diamondback"), cerrillos.card?.doLine ?? "")
        XCTAssertTrue(cerrillosDo.contains("sotol") || cerrillosDo.contains("cholla"), cerrillos.card?.doLine ?? "")
        XCTAssertFalse(cerrillosDo.contains("javelina"), cerrillos.card?.doLine ?? "")
        XCTAssertFalse(cerrillosDo.contains("edible"), cerrillos.card?.doLine ?? "")

        let ojito = try hold(at: Self.ojitoWilderness, zoom: 16, packId: "nm")
        XCTAssertEqual(ojito.card?.klass, "Open reserve", "\(ojito)")
        XCTAssertEqual(ojito.card?.title, "Ojito Wilderness", "\(ojito)")
        XCTAssertNotEqual(ojito.card?.klass, "Wildlife range", "\(ojito)")
        XCTAssertEqual(ojito.card?.fieldRoute.first, Inspect.snakeTXCard, "\(ojito)")
        XCTAssertTrue(
            ojito.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Ojito Wilderness dropped the NM snake card: \(ojito)"
        )
        let ojitoDo = ojito.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(ojitoDo.contains("rattler") || ojitoDo.contains("diamondback"), ojito.card?.doLine ?? "")
        XCTAssertTrue(ojitoDo.contains("sotol") || ojitoDo.contains("cholla"), ojito.card?.doLine ?? "")
        XCTAssertFalse(ojitoDo.contains("javelina"), ojito.card?.doLine ?? "")
        XCTAssertFalse(ojitoDo.contains("edible"), ojito.card?.doLine ?? "")

        let cabezon = try hold(at: Self.cabezonWSA, zoom: 16, packId: "nm")
        XCTAssertEqual(cabezon.card?.klass, "Open reserve", "\(cabezon)")
        XCTAssertEqual(cabezon.card?.title, "Cabezon Wilderness Study Area", "\(cabezon)")
        XCTAssertNotEqual(cabezon.card?.klass, "Wildlife range", "\(cabezon)")
        XCTAssertNotEqual(cabezon.card?.title, "Ojito Wilderness", "\(cabezon)")
        XCTAssertEqual(cabezon.card?.fieldRoute.first, Inspect.snakeTXCard, "\(cabezon)")
        XCTAssertTrue(
            cabezon.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Cabezon WSA dropped the NM snake card: \(cabezon)"
        )
        let cabezonDo = cabezon.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(cabezonDo.contains("rattler") || cabezonDo.contains("diamondback"), cabezon.card?.doLine ?? "")
        XCTAssertTrue(cabezonDo.contains("sotol") || cabezonDo.contains("cholla"), cabezon.card?.doLine ?? "")
        XCTAssertFalse(cabezonDo.contains("javelina"), cabezon.card?.doLine ?? "")
        XCTAssertFalse(cabezonDo.contains("edible"), cabezon.card?.doLine ?? "")

        let tentRocks = try hold(at: Self.tentRocks, zoom: 16, packId: "nm")
        XCTAssertEqual(tentRocks.card?.klass, "Open reserve", "\(tentRocks)")
        XCTAssertEqual(tentRocks.card?.title, "Kasha-Katuwe Tent Rocks National Monument", "\(tentRocks)")
        XCTAssertNotEqual(tentRocks.card?.klass, "Wildlife range", "\(tentRocks)")
        XCTAssertNotEqual(tentRocks.card?.title, "Valles Caldera National Preserve", "\(tentRocks)")
        XCTAssertEqual(tentRocks.card?.fieldRoute.first, Inspect.snakeTXCard, "\(tentRocks)")
        XCTAssertTrue(
            tentRocks.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Tent Rocks dropped the NM snake card: \(tentRocks)"
        )
        let tentDo = tentRocks.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(tentDo.contains("rattler") || tentDo.contains("diamondback"), tentRocks.card?.doLine ?? "")
        XCTAssertTrue(tentDo.contains("sotol") || tentDo.contains("cholla"), tentRocks.card?.doLine ?? "")
        XCTAssertFalse(tentDo.contains("javelina"), tentRocks.card?.doLine ?? "")
        XCTAssertFalse(tentDo.contains("edible"), tentRocks.card?.doLine ?? "")

        let pecos = try hold(at: Self.pecosHistorical, zoom: 16, packId: "nm")
        XCTAssertEqual(pecos.card?.klass, "Open reserve", "\(pecos)")
        XCTAssertEqual(pecos.card?.title, "Pecos National Historical Park", "\(pecos)")
        XCTAssertNotEqual(pecos.card?.klass, "Wildlife range", "\(pecos)")
        XCTAssertNotEqual(pecos.card?.title, "Pecos River Complex Wildlife Management Areas", "\(pecos)")
        XCTAssertEqual(pecos.card?.fieldRoute.first, Inspect.snakeTXCard, "\(pecos)")
        XCTAssertTrue(
            pecos.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Pecos National Historical Park dropped the NM snake card: \(pecos)"
        )
        let pecosDo = pecos.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(pecosDo.contains("rattler") || pecosDo.contains("diamondback"), pecos.card?.doLine ?? "")
        XCTAssertTrue(pecosDo.contains("sotol") || pecosDo.contains("cholla"), pecos.card?.doLine ?? "")
        XCTAssertFalse(pecosDo.contains("javelina"), pecos.card?.doLine ?? "")
        XCTAssertFalse(pecosDo.contains("edible"), pecos.card?.doLine ?? "")

        let elkSprings = try hold(at: Self.elkSpringsACEC, zoom: 16, packId: "nm")
        XCTAssertEqual(elkSprings.card?.klass, "Open reserve", "\(elkSprings)")
        XCTAssertEqual(elkSprings.card?.title, "Elk Springs Area of Critical Environmental Concern", "\(elkSprings)")
        XCTAssertNotEqual(elkSprings.card?.klass, "Wildlife range", "\(elkSprings)")
        XCTAssertNotEqual(elkSprings.card?.title, "Jones Canyon Area of Critical Environmental Concern", "\(elkSprings)")
        XCTAssertEqual(elkSprings.card?.fieldRoute.first, Inspect.snakeTXCard, "\(elkSprings)")
        XCTAssertTrue(
            elkSprings.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Elk Springs ACEC dropped the NM snake card: \(elkSprings)"
        )
        let elkDo = elkSprings.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(elkDo.contains("rattler") || elkDo.contains("diamondback"), elkSprings.card?.doLine ?? "")
        XCTAssertTrue(elkDo.contains("sotol") || elkDo.contains("cholla"), elkSprings.card?.doLine ?? "")
        XCTAssertFalse(elkDo.contains("javelina"), elkSprings.card?.doLine ?? "")
        XCTAssertFalse(elkDo.contains("edible"), elkSprings.card?.doLine ?? "")

        let chamisa = try hold(at: Self.chamisaWSA, zoom: 16, packId: "nm")
        XCTAssertEqual(chamisa.card?.klass, "Open reserve", "\(chamisa)")
        XCTAssertEqual(chamisa.card?.title, "Chamisa Wilderness Study Area", "\(chamisa)")
        XCTAssertNotEqual(chamisa.card?.klass, "Wildlife range", "\(chamisa)")
        XCTAssertNotEqual(chamisa.card?.title, "Cabezon Wilderness Study Area", "\(chamisa)")
        XCTAssertNotEqual(chamisa.card?.title, "Cerro Chamisa Losa", "\(chamisa)")
        XCTAssertEqual(chamisa.card?.fieldRoute.first, Inspect.snakeTXCard, "\(chamisa)")
        XCTAssertTrue(
            chamisa.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Chamisa WSA dropped the NM snake card: \(chamisa)"
        )
        let chamisaDo = chamisa.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(chamisaDo.contains("rattler") || chamisaDo.contains("diamondback"), chamisa.card?.doLine ?? "")
        XCTAssertTrue(chamisaDo.contains("sotol") || chamisaDo.contains("cholla"), chamisa.card?.doLine ?? "")
        XCTAssertFalse(chamisaDo.contains("javelina"), chamisa.card?.doLine ?? "")
        XCTAssertFalse(chamisaDo.contains("edible"), chamisa.card?.doLine ?? "")

        let tapia = try hold(at: Self.tapiaCanyonACEC, zoom: 16, packId: "nm")
        XCTAssertEqual(tapia.card?.klass, "Open reserve", "\(tapia)")
        XCTAssertEqual(tapia.card?.title, "Tapia Canyon Area of Critical Environmental Concern", "\(tapia)")
        XCTAssertNotEqual(tapia.card?.klass, "Wildlife range", "\(tapia)")
        XCTAssertNotEqual(tapia.card?.title, "Griegos Road", "\(tapia)")
        XCTAssertNotEqual(tapia.card?.title, "Chamisa Wilderness Study Area", "\(tapia)")
        XCTAssertEqual(tapia.card?.fieldRoute.first, Inspect.snakeTXCard, "\(tapia)")
        XCTAssertTrue(
            tapia.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Tapia Canyon ACEC dropped the NM snake card: \(tapia)"
        )
        let tapiaDo = tapia.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(tapiaDo.contains("rattler") || tapiaDo.contains("diamondback"), tapia.card?.doLine ?? "")
        XCTAssertTrue(tapiaDo.contains("sotol") || tapiaDo.contains("cholla"), tapia.card?.doLine ?? "")
        XCTAssertFalse(tapiaDo.contains("javelina"), tapia.card?.doLine ?? "")
        XCTAssertFalse(tapiaDo.contains("edible"), tapia.card?.doLine ?? "")

        let empedrado = try hold(at: Self.empedradoWSA, zoom: 16, packId: "nm")
        XCTAssertEqual(empedrado.card?.klass, "Open reserve", "\(empedrado)")
        XCTAssertEqual(empedrado.card?.title, "Empedrado Wilderness Study Area", "\(empedrado)")
        XCTAssertNotEqual(empedrado.card?.klass, "Wildlife range", "\(empedrado)")
        XCTAssertNotEqual(empedrado.card?.title, "San Luis Road", "\(empedrado)")
        XCTAssertNotEqual(empedrado.card?.title, "Cabezon Wilderness Study Area", "\(empedrado)")
        XCTAssertEqual(empedrado.card?.fieldRoute.first, Inspect.snakeTXCard, "\(empedrado)")
        XCTAssertTrue(
            empedrado.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Empedrado WSA dropped the NM snake card: \(empedrado)"
        )
        let empedradoDo = empedrado.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(empedradoDo.contains("rattler") || empedradoDo.contains("diamondback"), empedrado.card?.doLine ?? "")
        XCTAssertTrue(empedradoDo.contains("sotol") || empedradoDo.contains("cholla"), empedrado.card?.doLine ?? "")
        XCTAssertFalse(empedradoDo.contains("javelina"), empedrado.card?.doLine ?? "")
        XCTAssertFalse(empedradoDo.contains("edible"), empedrado.card?.doLine ?? "")

        let ignacio = try hold(at: Self.ignacioChavezWSA, zoom: 16, packId: "nm")
        XCTAssertEqual(ignacio.card?.klass, "Open reserve", "\(ignacio)")
        XCTAssertEqual(ignacio.card?.title, "Ignacio Chavez Wilderness Study Area", "\(ignacio)")
        XCTAssertNotEqual(ignacio.card?.klass, "Wildlife range", "\(ignacio)")
        XCTAssertNotEqual(ignacio.card?.title, "Cabezon Wilderness Study Area", "\(ignacio)")
        XCTAssertNotEqual(ignacio.card?.title, "Mesa la Azabache", "\(ignacio)")
        XCTAssertEqual(ignacio.card?.fieldRoute.first, Inspect.snakeTXCard, "\(ignacio)")
        XCTAssertTrue(
            ignacio.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Ignacio Chavez WSA dropped the NM snake card: \(ignacio)"
        )
        let ignacioDo = ignacio.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(ignacioDo.contains("rattler") || ignacioDo.contains("diamondback"), ignacio.card?.doLine ?? "")
        XCTAssertTrue(ignacioDo.contains("sotol") || ignacioDo.contains("cholla"), ignacio.card?.doLine ?? "")
        XCTAssertFalse(ignacioDo.contains("javelina"), ignacio.card?.doLine ?? "")
        XCTAssertFalse(ignacioDo.contains("edible"), ignacio.card?.doLine ?? "")

        let laLena = try hold(at: Self.laLenaWSA, zoom: 16, packId: "nm")
        XCTAssertEqual(laLena.card?.klass, "Open reserve", "\(laLena)")
        XCTAssertEqual(laLena.card?.title, "La Leña Wilderness Study Area", "\(laLena)")
        XCTAssertNotEqual(laLena.card?.klass, "Wildlife range", "\(laLena)")
        XCTAssertNotEqual(laLena.card?.title, "San Luis Mesa Area of Critical Environmental Concern", "\(laLena)")
        XCTAssertNotEqual(laLena.card?.title, "Cabezon Wilderness Study Area", "\(laLena)")
        XCTAssertEqual(laLena.card?.fieldRoute.first, Inspect.snakeTXCard, "\(laLena)")
        XCTAssertTrue(
            laLena.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "La Leña WSA dropped the NM snake card: \(laLena)"
        )
        let laLenaDo = laLena.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(laLenaDo.contains("rattler") || laLenaDo.contains("diamondback"), laLena.card?.doLine ?? "")
        XCTAssertTrue(laLenaDo.contains("sotol") || laLenaDo.contains("cholla"), laLena.card?.doLine ?? "")
        XCTAssertFalse(laLenaDo.contains("javelina"), laLena.card?.doLine ?? "")
        XCTAssertFalse(laLenaDo.contains("edible"), laLena.card?.doLine ?? "")

        let ladrones = try hold(at: Self.sierraLadronesWSA, zoom: 16, packId: "nm")
        XCTAssertEqual(ladrones.card?.klass, "Open reserve", "\(ladrones)")
        XCTAssertEqual(ladrones.card?.title, "Sierra Ladrones Wilderness Study Area", "\(ladrones)")
        XCTAssertNotEqual(ladrones.card?.klass, "Wildlife range", "\(ladrones)")
        XCTAssertNotEqual(ladrones.card?.klass, "Peak", "\(ladrones)")
        XCTAssertNotEqual(ladrones.card?.title, "Ladrón Peak", "\(ladrones)")
        XCTAssertNotEqual(ladrones.card?.title, "Cerro Colorado", "\(ladrones)")
        XCTAssertNotEqual(ladrones.card?.title, "El Cerro de Los Lunas Preserve", "\(ladrones)")
        XCTAssertEqual(ladrones.card?.fieldRoute.first, Inspect.snakeTXCard, "\(ladrones)")
        XCTAssertTrue(
            ladrones.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Sierra Ladrones WSA dropped the NM snake card: \(ladrones)"
        )
        let ladronesDo = ladrones.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(ladronesDo.contains("rattler") || ladronesDo.contains("diamondback"), ladrones.card?.doLine ?? "")
        XCTAssertTrue(ladronesDo.contains("sotol") || ladronesDo.contains("cholla"), ladrones.card?.doLine ?? "")
        XCTAssertFalse(ladronesDo.contains("javelina"), ladrones.card?.doLine ?? "")
        XCTAssertFalse(ladronesDo.contains("edible"), ladrones.card?.doLine ?? "")

        let dome = try hold(at: Self.domeWilderness, zoom: 16, packId: "nm")
        XCTAssertEqual(dome.card?.klass, "Open reserve", "\(dome)")
        XCTAssertEqual(dome.card?.title, "Dome Wilderness", "\(dome)")
        XCTAssertNotEqual(dome.card?.klass, "Wildlife range", "\(dome)")
        XCTAssertNotEqual(dome.card?.klass, "Peak", "\(dome)")
        XCTAssertNotEqual(dome.card?.title, "Saint Peter's Dome", "\(dome)")
        XCTAssertNotEqual(dome.card?.title, "Jemez National Recreation Area", "\(dome)")
        XCTAssertNotEqual(dome.card?.title, "Bandelier National Monument", "\(dome)")
        XCTAssertNotEqual(dome.card?.title, "Kasha-Katuwe Tent Rocks National Monument", "\(dome)")
        XCTAssertEqual(dome.card?.fieldRoute.first, Inspect.snakeTXCard, "\(dome)")
        XCTAssertTrue(
            dome.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Dome Wilderness dropped the NM snake card: \(dome)"
        )
        let domeDo = dome.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(domeDo.contains("rattler") || domeDo.contains("diamondback"), dome.card?.doLine ?? "")
        XCTAssertTrue(domeDo.contains("sotol") || domeDo.contains("cholla"), dome.card?.doLine ?? "")
        XCTAssertFalse(domeDo.contains("javelina"), dome.card?.doLine ?? "")
        XCTAssertFalse(domeDo.contains("edible"), dome.card?.doLine ?? "")

        let manzano = try hold(at: Self.manzanoMountainWilderness, zoom: 16, packId: "nm")
        XCTAssertEqual(manzano.card?.klass, "Open reserve", "\(manzano)")
        XCTAssertEqual(manzano.card?.title, "Manzano Mountain Wilderness", "\(manzano)")
        XCTAssertNotEqual(manzano.card?.klass, "Wildlife range", "\(manzano)")
        XCTAssertNotEqual(manzano.card?.klass, "Peak", "\(manzano)")
        XCTAssertNotEqual(manzano.card?.title, "Osha Peak", "\(manzano)")
        XCTAssertNotEqual(manzano.card?.title, "Manzano Wilderness Study Area", "\(manzano)")
        XCTAssertNotEqual(manzano.card?.title, "El Cerro de Los Lunas Preserve", "\(manzano)")
        XCTAssertEqual(manzano.card?.fieldRoute.first, Inspect.snakeTXCard, "\(manzano)")
        XCTAssertTrue(
            manzano.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Manzano Mountain Wilderness dropped the NM snake card: \(manzano)"
        )
        let manzanoDo = manzano.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(manzanoDo.contains("rattler") || manzanoDo.contains("diamondback"), manzano.card?.doLine ?? "")
        XCTAssertTrue(manzanoDo.contains("sotol") || manzanoDo.contains("cholla"), manzano.card?.doLine ?? "")
        XCTAssertFalse(manzanoDo.contains("javelina"), manzano.card?.doLine ?? "")
        XCTAssertFalse(manzanoDo.contains("edible"), manzano.card?.doLine ?? "")

        let sandia = try hold(at: Self.sandiaMountainWilderness, zoom: 16, packId: "nm")
        XCTAssertEqual(sandia.card?.klass, "Open reserve", "\(sandia)")
        XCTAssertEqual(sandia.card?.title, "Sandia Mountain Wilderness", "\(sandia)")
        XCTAssertNotEqual(sandia.card?.klass, "Wildlife range", "\(sandia)")
        XCTAssertNotEqual(sandia.card?.title, "Hawk Watch Open Space", "\(sandia)")
        XCTAssertNotEqual(sandia.card?.title, "Sandia Mountain Natural History Center", "\(sandia)")
        XCTAssertNotEqual(sandia.card?.title, "Sandia Foothills Open Space", "\(sandia)")
        XCTAssertEqual(sandia.card?.fieldRoute.first, Inspect.snakeTXCard, "\(sandia)")
        XCTAssertTrue(
            sandia.card?.fieldRoute.contains(Inspect.snakeNMCard) ?? false,
            "Sandia Mountain Wilderness dropped the NM snake card: \(sandia)"
        )
        let sandiaDo = sandia.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(sandiaDo.contains("rattler") || sandiaDo.contains("diamondback"), sandia.card?.doLine ?? "")
        XCTAssertTrue(sandiaDo.contains("sotol") || sandiaDo.contains("cholla"), sandia.card?.doLine ?? "")
        XCTAssertFalse(sandiaDo.contains("javelina"), sandia.card?.doLine ?? "")
        XCTAssertFalse(sandiaDo.contains("edible"), sandia.card?.doLine ?? "")
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

        let velvet = try hold(at: Self.velvetMesquite, zoom: 16, packId: "nm")
        XCTAssertEqual(velvet.card?.klass, "Named tree", "\(velvet)")
        XCTAssertEqual(velvet.card?.title, "Prosopis velutina / Velvet Mesquite", "\(velvet)")
        XCTAssertNotEqual(velvet.card?.klass, "Road", "\(velvet)")
        XCTAssertNotEqual(velvet.card?.title, "Landry Avenue Northwest", "\(velvet)")
        XCTAssertEqual(velvet.card?.fieldRoute.first, Inspect.treeUseTXCard, "\(velvet)")
        XCTAssertTrue(
            velvet.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? false,
            "a named NM tree dropped the NM tree-use card: \(velvet)"
        )
        let velvetDo = velvet.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(velvetDo.contains("not a meal"), velvet.card?.doLine ?? "")
        XCTAssertFalse(velvetDo.contains("edible"), velvet.card?.doLine ?? "")
        XCTAssertFalse(velvetDo.contains("javelina"), velvet.card?.doLine ?? "")

        let honey = try hold(at: Self.westernHoneyMesquite, zoom: 16, packId: "nm")
        XCTAssertEqual(honey.card?.klass, "Named tree", "\(honey)")
        XCTAssertEqual(honey.card?.title, "Prosopis torreyana / Western Honey Mesquite", "\(honey)")
        XCTAssertNotEqual(honey.card?.title, "Prosopis velutina / Velvet Mesquite", "\(honey)")
        XCTAssertNotEqual(honey.card?.title, "Prosopis glandulosa / Texas Honey Mesquite", "\(honey)")
        XCTAssertNotEqual(honey.card?.title, "Pinus pinea / Italian Stone Pine", "\(honey)")
        XCTAssertEqual(honey.card?.fieldRoute.first, Inspect.treeUseTXCard, "\(honey)")
        XCTAssertTrue(
            honey.card?.fieldRoute.contains(Inspect.treeUseNMCard) ?? false,
            "a named NM tree dropped the NM tree-use card: \(honey)"
        )
        let honeyDo = honey.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(honeyDo.contains("not a meal"), honey.card?.doLine ?? "")
        XCTAssertFalse(honeyDo.contains("edible"), honey.card?.doLine ?? "")
        XCTAssertFalse(honeyDo.contains("javelina"), honey.card?.doLine ?? "")
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

        let blanca = try hold(at: Self.mesaBlanca, zoom: 16, packId: "nm")
        XCTAssertEqual(blanca.card?.klass, "Peak", "\(blanca)")
        XCTAssertEqual(blanca.card?.title, "Mesa Blanca", "\(blanca)")
        XCTAssertNotEqual(blanca.card?.klass, "Wildlife range", "\(blanca)")
        XCTAssertNotEqual(blanca.card?.title, "Marquez Wildlife Management Area", "\(blanca)")
        XCTAssertNotEqual(blanca.card?.title, "La Cruz Peak", "\(blanca)")
        let blancaDo = blanca.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(blancaDo.contains("black bear and elk range"), blanca.card?.doLine ?? "")
        XCTAssertTrue(blancaDo.contains("give it the road"), blanca.card?.doLine ?? "")
        XCTAssertFalse(blancaDo.contains("javelina"), blanca.card?.doLine ?? "")
        XCTAssertFalse(blancaDo.contains("hog"), blanca.card?.doLine ?? "")
        XCTAssertFalse(blancaDo.contains("edible"), blanca.card?.doLine ?? "")
        let blancaPresent = InspectField.presentRoute(blanca.card?.fieldRoute ?? [], in: nmBook)
        XCTAssertEqual(blancaPresent.first, Inspect.iceRockCard, "\(blanca)")
        XCTAssertEqual(InspectField.label(for: blancaPresent.first ?? ""), "FIELD · COLD")
        XCTAssertEqual(InspectField.bookLine(for: blancaPresent), "COLD · ANIMAL · BITE")

        let cerritos = try hold(at: Self.cerritosDeLaJolla, zoom: 16, packId: "nm")
        XCTAssertEqual(cerritos.card?.klass, "Peak", "\(cerritos)")
        XCTAssertEqual(cerritos.card?.title, "Cerritos de la Jolla de Santa Rosa", "\(cerritos)")
        XCTAssertNotEqual(cerritos.card?.klass, "Wildlife range", "\(cerritos)")
        XCTAssertNotEqual(cerritos.card?.title, "Marquez Wildlife Management Area", "\(cerritos)")
        XCTAssertNotEqual(cerritos.card?.title, "Mesa Blanca", "\(cerritos)")
        XCTAssertNotEqual(cerritos.card?.title, "La Cruz Peak", "\(cerritos)")
        XCTAssertNotEqual(cerritos.card?.title, "San Antonio Mountain", "\(cerritos)")
        let cerritosDo = cerritos.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(cerritosDo.contains("black bear and elk range"), cerritos.card?.doLine ?? "")
        XCTAssertTrue(cerritosDo.contains("give it the road"), cerritos.card?.doLine ?? "")
        XCTAssertFalse(cerritosDo.contains("javelina"), cerritos.card?.doLine ?? "")
        XCTAssertFalse(cerritosDo.contains("hog"), cerritos.card?.doLine ?? "")
        XCTAssertFalse(cerritosDo.contains("edible"), cerritos.card?.doLine ?? "")
        let cerritosPresent = InspectField.presentRoute(cerritos.card?.fieldRoute ?? [], in: nmBook)
        XCTAssertEqual(cerritosPresent.first, Inspect.iceRockCard, "\(cerritos)")
        XCTAssertEqual(InspectField.label(for: cerritosPresent.first ?? ""), "FIELD · COLD")
        XCTAssertEqual(InspectField.bookLine(for: cerritosPresent), "COLD · ANIMAL · BITE")

        let antonio = try hold(at: Self.sanAntonioMountain, zoom: 16, packId: "nm")
        XCTAssertEqual(antonio.card?.klass, "Peak", "\(antonio)")
        XCTAssertEqual(antonio.card?.title, "San Antonio Mountain", "\(antonio)")
        XCTAssertNotEqual(antonio.card?.klass, "Wildlife range", "\(antonio)")
        XCTAssertNotEqual(antonio.card?.title, "Valles Caldera National Preserve", "\(antonio)")
        XCTAssertNotEqual(antonio.card?.title, "San Antonio Mountain Trail", "\(antonio)")
        XCTAssertNotEqual(antonio.card?.title, "Cerritos de la Jolla de Santa Rosa", "\(antonio)")
        XCTAssertNotEqual(antonio.card?.title, "Mesa Blanca", "\(antonio)")
        XCTAssertNotEqual(antonio.card?.title, "La Cruz Peak", "\(antonio)")
        let antonioDo = antonio.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(antonioDo.contains("black bear and elk range"), antonio.card?.doLine ?? "")
        XCTAssertTrue(antonioDo.contains("give it the road"), antonio.card?.doLine ?? "")
        XCTAssertFalse(antonioDo.contains("javelina"), antonio.card?.doLine ?? "")
        XCTAssertFalse(antonioDo.contains("hog"), antonio.card?.doLine ?? "")
        XCTAssertFalse(antonioDo.contains("edible"), antonio.card?.doLine ?? "")
        let antonioPresent = InspectField.presentRoute(antonio.card?.fieldRoute ?? [], in: nmBook)
        XCTAssertEqual(antonioPresent.first, Inspect.iceRockCard, "\(antonio)")
        XCTAssertEqual(InspectField.label(for: antonioPresent.first ?? ""), "FIELD · COLD")
        XCTAssertEqual(InspectField.bookLine(for: antonioPresent), "COLD · ANIMAL · BITE")
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

        let carrington = try hold(at: Self.carringtonPrairie, zoom: 16, packId: "tx-east")
        XCTAssertEqual(carrington.card?.klass, "Open reserve", "\(carrington)")
        XCTAssertEqual(carrington.card?.title, "Carrington's Prairie", "\(carrington)")
        XCTAssertNotEqual(carrington.card?.title, "Decker Tallgrass Prairie Preserve", "\(carrington)")
        XCTAssertNotEqual(carrington.card?.title, "Trail West Drive", "\(carrington)")
        XCTAssertEqual(carrington.card?.fieldRoute.first, Inspect.snakeEastCard, "\(carrington)")
        XCTAssertNotEqual(
            carrington.card?.fieldRoute.first,
            Inspect.treeUseEastCard,
            "Carrington's Prairie opened picnic woodland: \(carrington)"
        )
        let carringtonDo = carrington.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(carringtonDo.contains("cottonmouth"), carrington.card?.doLine ?? "")
        XCTAssertTrue(carringtonDo.contains("hog"), carrington.card?.doLine ?? "")
        XCTAssertTrue(carringtonDo.contains("give it room"), carrington.card?.doLine ?? "")
        XCTAssertTrue(carringtonDo.contains("no ice"), carrington.card?.doLine ?? "")
        XCTAssertFalse(carringtonDo.contains("javelina"), carrington.card?.doLine ?? "")
        XCTAssertFalse(carringtonDo.contains("edible"), carrington.card?.doLine ?? "")

        let indianGrass = try hold(at: Self.indianGrassPrairie, zoom: 16, packId: "tx-east")
        XCTAssertEqual(indianGrass.card?.klass, "Open reserve", "\(indianGrass)")
        XCTAssertEqual(indianGrass.card?.title, "Indian Grass Prarie Preserve", "\(indianGrass)")
        XCTAssertNotEqual(indianGrass.card?.klass, "Wildlife range", "\(indianGrass)")
        XCTAssertNotEqual(indianGrass.card?.title, "Violet Crown Trail", "\(indianGrass)")
        XCTAssertNotEqual(indianGrass.card?.title, "Sunset Valley Nature Area", "\(indianGrass)")
        XCTAssertNotEqual(indianGrass.card?.title, "Carrington's Prairie", "\(indianGrass)")
        XCTAssertEqual(indianGrass.card?.fieldRoute.first, Inspect.snakeEastCard, "\(indianGrass)")
        XCTAssertNotEqual(
            indianGrass.card?.fieldRoute.first,
            Inspect.treeUseEastCard,
            "Indian Grass Prarie Preserve opened picnic woodland: \(indianGrass)"
        )
        let indianDo = indianGrass.card?.doLine.lowercased() ?? ""
        XCTAssertTrue(indianDo.contains("cottonmouth"), indianGrass.card?.doLine ?? "")
        XCTAssertTrue(indianDo.contains("hog"), indianGrass.card?.doLine ?? "")
        XCTAssertTrue(indianDo.contains("give it room"), indianGrass.card?.doLine ?? "")
        XCTAssertTrue(indianDo.contains("no ice"), indianGrass.card?.doLine ?? "")
        XCTAssertFalse(indianDo.contains("javelina"), indianGrass.card?.doLine ?? "")
        XCTAssertFalse(indianDo.contains("edible"), indianGrass.card?.doLine ?? "")
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
            ("castner range", Self.castnerRange, 16.0),
            ("prehistoric trackways", Self.trackways, 16.0),
            ("white sands", Self.whiteSands, 16.0),
            ("knapp easement", Self.knappEasement, 16.0),
            ("wind mountain acec", Self.windMountainACEC, 16.0),
            ("rincon acec", Self.rinconACEC, 16.0),
            ("sacramento escarpment", Self.sacramentoEscarpment, 16.0),
            ("uvas valley acec", Self.uvasValleyACEC, 16.0),
            ("thunder canyon", Self.thunderCanyon, 16.0),
            ("cornundas acec", Self.cornundasACEC, 16.0),
            ("florida mountains wsa", Self.floridaMountainsWSA, 16.0),
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
