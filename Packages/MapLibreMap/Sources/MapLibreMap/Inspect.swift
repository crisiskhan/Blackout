import Foundation

/// What one held point on the map turns out to be.
///
/// Everything here reads the pack's own record and says what it found. It never
/// says a thing is safe to drink, safe to eat, or safe to touch — those are
/// judgements no offline record can make, and a number next to them would be
/// read as permission. `sure` is confidence that the feature is really there
/// and really is what it claims, nothing more, and `why` says so in a line.
public enum Inspect {
    public enum Kind: String, Sendable, Equatable {
        case water
        case land
        case street
        case place
        case nothing
    }

    /// What to do with the thing, in the only three shapes that are honest:
    /// run the water tree over it, leave it alone, or read the ground's card.
    public enum Advice: String, Sendable, Equatable {
        case treat
        case leave
        case field

        public var line: String {
            switch self {
            case .treat: return "Treat it. Field has the steps."
            case .leave: return "Leave it. Runoff, not a source."
            case .field: return "Field has the card for this ground."
            }
        }
    }

    public struct Card: Sendable, Equatable {
        /// The record's name, or `Unnamed` — never a guess at one.
        public var title: String
        public var klass: String
        public var kind: Kind
        /// Confidence the record is right about what this is. Not drinkability.
        public var sure: Int
        public var why: String
        public var advice: Advice
        /// Field card this opens. Core cards only, so it is there in every state.
        public var fieldCardID: String
        /// State cards that answer this ground better than the core one, best
        /// first. A state book may not be loaded, so these are only preferences.
        public var localCardIDs: [String]
        /// Core cards that sit between the state's book and the last fallback.
        /// Woodland wants plant-use and shelter after Texas plant-danger; they
        /// cannot live in `localCardIDs` because those must be state-only.
        public var extraCoreIDs: [String]
        /// When the pack's OSM was pulled, as the manifest recorded it.
        public var packDate: String?
        /// Class-specific field voice when we have it. Generic treat/leave otherwise.
        public var doDetail: String?

        public init(
            title: String,
            klass: String,
            kind: Kind,
            sure: Int,
            why: String,
            advice: Advice,
            fieldCardID: String,
            localCardIDs: [String] = [],
            extraCoreIDs: [String] = [],
            packDate: String? = nil,
            doDetail: String? = nil
        ) {
            self.title = title
            self.klass = klass
            self.kind = kind
            self.sure = sure
            self.why = why
            self.advice = advice
            self.fieldCardID = fieldCardID
            self.localCardIDs = localCardIDs
            self.extraCoreIDs = extraCoreIDs
            self.packDate = packDate
            self.doDetail = doDetail
        }

        public var sureLine: String { "SURE \(sure)% — \(why)" }
        public var doLine: String { doDetail ?? advice.line }

        /// Cards to try in order when FIELD is pressed. The state's own card
        /// answers the ground better than the core one — holding a subdivision
        /// in El Paso wants the heat island, not "stop and locate" — but only
        /// the state that wrote it ships it. Extra core cards sit next, then
        /// the last core card, so FIELD lands somewhere no matter which book is
        /// open.
        public var fieldRoute: [String] {
            var seen = Set<String>()
            var out: [String] = []
            for id in localCardIDs + extraCoreIDs + [fieldCardID] {
                if seen.insert(id).inserted { out.append(id) }
            }
            return out
        }
    }

    public static let unnamed = "Unnamed"

    /// How long a thumb has to stay put before the card comes up, and how far
    /// it may drift first. Past that drift the map pans and no card appears,
    /// because a hold that moves was a pan all along.
    public static let holdSeconds = 0.4
    public static let holdDriftPoints = 12.0
    /// A thumb covers more than a pixel, so the probe reads a box this wide.
    public static let holdProbePoints = 44.0
    /// A thumb landing below this much of the canvas would be behind the card,
    /// so the map slides to put the held place this far down from the top.
    public static let holdLiftBelow = 0.45
    public static let holdLiftTo = 0.3

    /// Everything the map drew under the thumb, and which of it the card is
    /// about.
    ///
    /// A spring, well, tank or tap is what holding a place is for, so those
    /// point records beat everything else. A wash that crosses a road is still
    /// the wash. A drain in the thumb box is not: a silver hole, peak or tree
    /// is the thing aimed at, and the Field book of that mark is the question.
    ///
    /// After that, a record the survey named beats one it did not, because a
    /// name means somebody stood at that exact thing. A cave preserve, a
    /// wildlife sanctuary, a botanic garden, an open reserve, or a glasshouse
    /// is a named (or tagged) sheet that is the question — it beats woodland
    /// and farm fill, and it beats a named street. Among those sheets the card
    /// order holds: a hole, then wildlife, then botanic or glasshouse, then
    /// open reserve. A raptor site or natural-history center inside a
    /// wilderness is range, not the mountain — more tags on the wilderness
    /// sheet must not swallow it. The silver outline is the hold; the trail
    /// that runs through the preserve is not. A street still beats generic
    /// park and town fill: `landuse=residential` is drawn under every street
    /// in Las Cruces, so without that a hold downtown answers with the
    /// subdivision instead of the road under the thumb. Between two unnamed
    /// records take the ground, because out there the biome is the answer
    /// and an unnamed ranch track is not.
    ///
    /// Sampling 4,000 points across the tx-west pack, a street and a piece of
    /// ground are both under the thumb 1.5% of the time, and that split is
    /// roughly even between the two rules — which is why it takes both.
    public static func pick(_ found: [[String: String]]) -> [String: String] {
        func rank(_ tags: [String: String]) -> Int {
            let named = !((tags["name"] ?? tags["ref"] ?? "").isEmpty)
            let notablePoint = packGroundPointNaturals.contains(tags["natural"] ?? "")
            let glasshouse = tags["landuse"] == "greenhouse_horticulture"
            let pointWater = packPointClasses.contains(tags["class"] ?? "")
                || ["storage_tank", "water_tank", "water_well", "cistern", "reservoir_covered"]
                    .contains(tags["man_made"] ?? "")
                || ["spring", "hot_spring", "geyser"].contains(tags["natural"] ?? "")
            switch read(tags: tags).kind {
            case .water where pointWater:
                return 0
            case .land where notablePoint:
                return 1
            case .water:
                return 2
            case .land where isCavePreserve(tags):
                return 3
            case .land where isWildlifeRange(tags):
                return 4
            case .land where isBotanicGarden(tags) || glasshouse:
                return 5
            case .land where isOpenReserve(tags):
                return 6
            case .street where named:
                return 7
            case .land where named:
                return 8
            case .place where named:
                return 9
            case .land:
                return 10
            case .street:
                return 11
            case .place:
                return 12
            case .nothing:
                return 13
            }
        }
        return found
            .filter { !$0.isEmpty }
            .min { a, b in
                let (ra, rb) = (rank(a), rank(b))
                if ra != rb { return ra < rb }
                return a.count > b.count
            } ?? [:]
    }

    /// The vector source the packs put the record in. A hold reads this, not
    /// only the pixels the style chose to paint: a tank is a five-point circle
    /// and `visibleFeatures` will not give it back.
    public static let packSourceID = "osm"

    /// Source layers a hold will take a point from. Springs, wells, tanks and
    /// taps live in `water` as points; the rest of the record is a fill or a
    /// line and the painted query already finds those.
    public static let packPointSourceLayers: Set<String> = ["water", "place"]

    /// `class` values the tiler emits as a point so the style can draw a ring.
    public static let packPointClasses: Set<String> = [
        "spring", "well", "tank", "tank_other", "tap",
    ]

    /// Point records on the pack's `place` slice that a hold has to name even
    /// when the style drew them too small to hit. Peaks, holes and named
    /// trees. Never an animal — range is the Field book, not a GPS pin.
    public static let packGroundPointNaturals: Set<String> = [
        "peak", "sinkhole", "cave", "cave_entrance", "tree",
    ]

    /// Style layers the app draws itself. They carry no record worth reading,
    /// so a hold looks straight through them.
    public static let overlayLayerIDs: Set<String> = [
        "pack-bbox-line", "you-puck-halo", "you-puck-core",
        DestinationPin.ringLayerID, DestinationPin.coreLayerID,
        RouteLine.casingLayerID, RouteLine.layerID, RouteLine.coreLayerID,
        HoldPin.ringLayerID, HoldPin.coreLayerID,
        PartyPips.haloLayerID, PartyPips.coreLayerID,
    ]

    // Core Field cards, which every state ships, so a hold can never open a
    // card that is not in the book.
    public static let waterCard = "water-disinfect"
    public static let plantCard = "plant-unknown"
    public static let plantUseCard = "plant-use"
    public static let heatCard = "env-heat-collapse"
    public static let coldCard = "env-cold"
    public static let lostCard = "nav-lost"
    public static let caveCard = "cave-dark"
    public static let biteCard = "animal-bite"
    public static let shelterCard = "shelter-tarp"
    public static let fungiCard = "fungi-leave"
    public static let gameCard = "food-game"

    // State cards that describe one kind of ground exactly. Each is only in
    // the book of the state that wrote it, so each is a preference over a core
    // card and never a replacement for one.
    public static let heatIslandCard = "tx-heat-island"
    public static let iceRockCard = "nm-ice-rock"
    public static let ranchRoadCard = "tx-cattle-guard"
    public static let snakeTXCard = "tx-snake"
    public static let snakeNMCard = "nm-snake"
    public static let plantTXCard = "tx-plant-danger"
    public static let plantNMCard = "nm-plant-danger"
    public static let treeUseTXCard = "tx-tree-use"
    public static let treeUseNMCard = "nm-tree-use"
    public static let treeUseEastCard = "tx-east-tree-use"
    public static let mammalTXCard = "tx-mammal"
    public static let mammalNMCard = "nm-mammal"
    public static let mammalEastCard = "tx-east-mammal"
    public static let cactusTXCard = "tx-cactus"
    public static let cactusNMCard = "nm-cactus"
    public static let gameTXCard = "tx-game"
    public static let gameNMCard = "nm-game"
    public static let gameEastCard = "tx-east-game"
    public static let snakeEastCard = "tx-east-snake"

    /// One row of the reading table: how a feature is recognised, and what the
    /// card says once it has been.
    private struct Reading {
        var klass: String
        var kind: Kind
        var sure: Int
        var why: String
        var advice: Advice
        var field: String
        var local: [String] = []
        var extra: [String] = []
        /// Applied when the record carries no name, because an unnamed feature
        /// is one nobody surveyed closely.
        var unnamedPenalty: Int = 8
        var unnamedKlass: String?
        var unnamedWhy: String?
    }

    public static func read(
        tags: [String: String],
        packDate: String? = nil,
        state: String? = nil,
        pack: String? = nil
    ) -> Card {
        let name = (tags["name"] ?? tags["ref"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let named = !name.isEmpty
        let reading = match(tags, pack: pack)
        let klass = named ? reading.klass : (reading.unnamedKlass ?? reading.klass)
        let why = named ? reading.why : (reading.unnamedWhy ?? reading.why)
        let sure = max(5, min(97, named ? reading.sure : reading.sure - reading.unnamedPenalty))
        return Card(
            title: named ? name : unnamed,
            klass: klass,
            kind: reading.kind,
            sure: sure,
            why: why,
            advice: reading.advice,
            fieldCardID: reading.field,
            localCardIDs: reading.local,
            extraCoreIDs: reading.extra,
            packDate: packDate,
            doDetail: fieldDoLine(
                klass: klass,
                kind: reading.kind,
                advice: reading.advice,
                state: state,
                pack: pack
            )
        )
    }

    // MARK: - The table

    static func isEastPack(_ pack: String?) -> Bool {
        (pack ?? "").lowercased() == "tx-east"
    }

    /// A park named Bee Cave is a town park. A park named Cave Preserve is
    /// the hole. Phrase `karst preserve`. William H. Russell Karst
    /// Preserve is a hole, not wildlife range. Karst Lane stays a
    /// road. A nature reserve named for a
    /// cave is the hole. Not the word cave as a bare contains — Bee Cave,
    /// Coyote Cave Park, and Cave Drive stay parks. Phrase `blowing sink`,
    /// not the word `sink` — a highway named Blowing Sink Road is a road,
    /// and Kitchen Sink is not a hole.
    static func isCavePreserve(_ t: [String: String]) -> Bool {
        let n = (t["name"] ?? "").lowercased()
        if n.contains("blowing sink") {
            let highway = t["highway"] ?? ""
            return highway.isEmpty
        }
        let park = t["leisure"] == "park"
            || t["leisure"] == "nature_reserve"
            || t["boundary"] == "protected_area"
            || t["boundary"] == "national_park"
        guard park else { return false }
        if n.contains("bee cave") { return false }
        if n.contains("cave park") { return false }
        if n.contains("cave drive") { return false }
        if n.contains("cave preserve") { return true }
        if n.contains("cave area of critical") { return true }
        if n.contains("karst preserve") { return true }
        if n.range(of: "cave") != nil { return true }
        return false
    }

    /// A park named Wildlife Drive is a street park. A wildlife
    /// management area is range. Phrase match, not the word `wildlife`.
    /// Game Commission land is range. Phrase `game commission`, not the
    /// word `game` — Department of Game & Fish is an office. Phrase
    /// `wilderness preserve`, not the word `wilderness` — Wilderness
    /// Gate is apartments. Phrase `nature preserve` / `nature center` /
    /// `natural area` / `nature area`, not the word `preserve` — Godzilla
    /// Preserve is a park. Phrase `wildlife preserve`, not the word
    /// `wildlife` — Wildlife Drive stays a park. Phrase `audubon`, not
    /// a street. Phrase `habitat preserve`, not the word `habitat`.
    /// Phrase `flora y fauna`, not a street. Phrase `national
    /// preserve`, not the word `preserve`. Phrase `wilderness park`,
    /// not the word `wilderness`. Phrase `canyonlands preserve`, not
    /// the word `canyonlands` — Canyonlands Trail Park stays a park.
    /// Phrase `wetland preserve`, not the word `wetland` — Rio Bosque
    /// Wetlands Park stays bosque. Phrase `canyon preserve`, not the
    /// word `canyon` — Santa Fe Canyon Preserve is range; Canyon
    /// Preserve Interpretive Loop Trail stays a path; El Cerro de Los
    /// Lunas Preserve and Galisteo Basin Preserve stay Open reserve.
    /// Phrase `management unit`, not `wildlife management area` — a
    /// Balcones management unit is range; Waste Management Wildlife
    /// Park stays Open reserve. Phrase `ecological research`, not the
    /// word `research`. Phrase `hawk watch`, not the word `hawk` —
    /// Hawk Watch Trail stays a trail. Phrase `experimental range`, not
    /// the word `experimental`. Phrase `natural history`, not the word
    /// `history` — Sandia Mountain Natural History Center is range, like
    /// a nature center. Phrase `baker sanctuary`, not the word
    /// `baker`. Phrase `blair woods sanctuary`, not the word `blair` or
    /// `woods`. Phrase `beck preserve`, not the word `beck`. Beck
    /// Preserve is Travis Audubon bird sanctuary. Phrase `brodie
    /// wild`, not the word `brodie`. Brodie Lane stays a road.
    /// Brodie and Oakdale Properties stay Open reserve. Phrase
    /// `dahlstrom nature`, not the word `dahlstrom`. Dahlstrom
    /// Road stays a road. The `nature preserve` phrase already
    /// matches that sheet. Phrase `bernardo wildlife`, not the
    /// word `bernardo`. Bernardo Trails Park stays a park. Don
    /// Bernardo Road stays a road. The `wildlife management area`
    /// phrase already matches that sheet. Phrase `national
    /// wildlife`, not the word `valle`. Valle de Oro National
    /// Wildlife Refuge is range. Valle del Bosque Park stays a
    /// park. Phrase `stephenson nature`, not the word
    /// `stephenson`. The `nature preserve` phrase already
    /// matches that sheet. Phrase `onion creek wildlife`, not the
    /// word `onion`. Onion Creek Drive stays a road. Onion Creek
    /// Management Unit is a separate sheet. Phrase `onion creek
    /// management`, not the word `onion`. The `wildlife sanctuary`
    /// and `management unit` phrases already match those sheets.
    /// Phrase `mary gay maxwell`. The `management unit` phrase
    /// already matches that sheet. Phrase `bull creek management`,
    /// not the word `bull`. Bull Creek West Loop stays a trail. The
    /// `management unit` phrase already matches that sheet. Phrase
    /// `lower barton creek`, not the word `barton`. Barton Creek
    /// Habitat Preserve and Barton Creek Wilderness Park stay their
    /// own sheets. Phrase `little bear creek`. The `management
    /// unit` phrase already matches that sheet. Phrase `la joya
    /// wildlife`, not the word `joya`. The `wildlife management
    /// area` phrase already matches that sheet. Phrase `canyonlands
    /// preserve` already matches Grandview Hills, Blackmore, Lake
    /// Perspectives, Austin Simon, and Lime Creek as unique titles.
    /// Cuevas East sits next to Cuevas and stays unheld. Barrow
    /// Nature Preserve vertex-avg sits off the sheet; the listed
    /// interior is on it. The `nature preserve` phrase already
    /// matches that sheet. Rio Rancho Bosque Nature Preserve is
    /// range, not bosque overlay. The `nature preserve` phrase
    /// already matches that sheet. Phrase `wild basin
    /// wilderness`, not the word `basin`. The `wilderness
    /// preserve` phrase already matches that sheet. Listed
    /// centroid sits on water. Phrase `stillhouse hollow`. The
    /// `nature preserve` phrase already matches that sheet. Listed
    /// centroid sits on water. Phrase `big walnut creek`, not the
    /// word `walnut`. The `nature preserve` phrase already matches
    /// that sheet. Listed centroid sits on Walnut Creek. Phrase
    /// `colorado river park wildlife`. The `wildlife sanctuary`
    /// phrase already matches that sheet. Listed centroid sits
    /// on the Colorado River. Phrase `shady hollow west`, not
    /// the word `shady`. Lost Oasis Hollow stays a road. Bear
    /// Creek Management Unit is a separate sheet. The `nature
    /// preserve` phrase already matches that sheet. Austin
    /// wildland, animals as range, not a pin. Phrase `nature
    /// preserve` already matches Charlie Wakeem/Richard Teschner
    /// Nature Preserve of Resler Canyon and Blunn Creek Nature
    /// Preserve. Cadiz Street and East Oltorf Street stay roads.
    /// Do not add matcher `charlie`, `resler`, or `blunn`. Phrase
    /// `national wildlife` already matches San Andres National
    /// Wildlife Refuge and Sevilleta National Wildlife Refuge.
    /// Do not add matcher `san andres` or `sevilleta`. White
    /// Sands Missile Range S Route 287 and Old Highway 85 stay
    /// roads. Whitfield dry interiors have no nearby name that is
    /// not Acequia Madre and stay unheld. `preserve` alone is
    /// still forbidden.
    static func isWildlifeRange(_ t: [String: String]) -> Bool {
        let park = t["leisure"] == "park"
            || t["leisure"] == "nature_reserve"
            || t["boundary"] == "protected_area"
            || t["boundary"] == "national_park"
        guard park else { return false }
        let n = (t["name"] ?? "").lowercased()
        if n.contains("wildlife refuge") { return true }
        if n.contains("wildlife management area") { return true }
        if n.contains("national wildlife") { return true }
        if n.contains("wildlife sanctuary") { return true }
        if n.contains("wildlife conservation area") { return true }
        if n.contains("game commission") { return true }
        if n.contains("wilderness preserve") { return true }
        if n.contains("nature preserve") { return true }
        if n.contains("nature center") { return true }
        if n.contains("natural area") { return true }
        if n.contains("nature area") { return true }
        if n.contains("wildlife preserve") { return true }
        if n.contains("audubon") { return true }
        if n.contains("habitat preserve") { return true }
        if n.contains("flora y fauna") { return true }
        if n.contains("national preserve") { return true }
        if n.contains("wilderness park") { return true }
        if n.contains("canyonlands preserve") { return true }
        if n.contains("wetland preserve") { return true }
        if n.contains("canyon preserve") { return true }
        if n.contains("management unit") { return true }
        if n.contains("ecological research") { return true }
        if n.contains("hawk watch") { return true }
        if n.contains("experimental range") { return true }
        if n.contains("natural history") { return true }
        if n.contains("baker sanctuary") { return true }
        if n.contains("blair woods sanctuary") { return true }
        if n.contains("beck preserve") { return true }
        if n.contains("brodie wild") { return true }
        return false
    }

    /// Phrase `cactus garden`, `desert garden`, or `desert conservatory`,
    /// not the word `cactus`. Cactus Point Park and Parque Cactus del
    /// Desierto stay parks. A rose garden is botanic, not spines.
    /// `leisure=garden` is cactus-eligible with a desert/cactus phrase;
    /// Chihuahuan Desert Gardens is spines, not oleander.
    static func isCactusGarden(_ t: [String: String]) -> Bool {
        let n = (t["name"] ?? "").lowercased()
        let phrase = n.contains("cactus garden")
            || n.contains("desert garden")
            || n.contains("desert conservatory")
        guard phrase else { return false }
        if t["leisure"] == "garden" { return true }
        let park = t["leisure"] == "park"
            || t["leisure"] == "nature_reserve"
            || t["boundary"] == "protected_area"
            || t["boundary"] == "national_park"
        return park
    }

    /// A park named Conservatory At North Austin is apartments. A botanic
    /// garden is worked plant ground. Phrase match, not the word `garden`
    /// and not `arboretum`. A cactus garden opens the cactus card; Cactus
    /// Point Park is not. A beer garden is a patio. Phrase `wildflower
    /// preserve`, not the word `wildflower` — Wildflower Park stays a park.
    /// Phrase `wildflower center`, not the word `wildflower` — Ladybird
    /// Johnson Wildflower Center is a garden relation, not a ring faked
    /// from foot paths. Those paths stay paths. Phrase `lush n lean`,
    /// not the word `lush`. Phrase `orchard garden`, not the word
    /// `orchard` — Orchard Gardens Road stays a road. Fiesta Gardens is
    /// an event park and stays a park. Phrase `harvey cornell`, not
    /// `rose park` — Wildrose Park stays a park. Phrase `japaneese
    /// garden` is OSM's El Paso spelling; phrase `japanese garden` is
    /// the correctly spelled sheet. Phrase `japanese memorial`, not
    /// Memorial Garden. Phrase `capitol flower`, not `flower
    /// gardens`. Mayfield Gardens stays out. Phrase `demonstration
    /// garden`, not the word `demonstration`. Phrase `preston
    /// foster`, not `native garden` — Native American Garden inside
    /// Santa Fe Botanical Garden stays nested. Phrase `xeriscape
    /// garden`, not the word `xeriscape` — Xeriscape Park stays a
    /// park. Phrase `teaching garden`, not the word `teaching`.
    /// Phrase `fincher iii garden`, not the word `fincher` — E.R.
    /// Fincher III Garden is a community garden without the amenity
    /// tag. Phrase `brazos bluff`, not the word `brazos` — Brazos
    /// Street stays a road. Phrase `explorers garden`. Both are
    /// educational gardens, not a meal. Phrase `haozous garden`,
    /// not the word `haozous` — Haozous Road stays a road. Phrase
    /// `este garden`, not the word `este`. Celeste Drive stays a
    /// road. Alamo Community Garden is a separate sheet. Phrase
    /// `4th street garden`, not the word `4th`. West 4th Avenue
    /// stays a road. Phrase `alamogordo community garden`, not the
    /// word `alamogordo`. The Alamogordo street stays a road. The
    /// `community garden` phrase already matches that sheet. Phrase
    /// `albuquerque rose garden`, not the word `albuquerque`.
    /// Memorial Rose Garden is a separate sheet. The `rose garden`
    /// phrase already matches both. Phrase `la mesa neighborhood`,
    /// not `la mesa`. Paseo de la Mesa Open Space stays Open reserve.
    /// La Mesa Court stays a road. The `community garden` phrase
    /// already matches that sheet. Phrase `international district`,
    /// not the word `international`. The `community garden` phrase
    /// already matches that sheet. Phrase `bastrop community`,
    /// not the word `bastrop`. Bastrop Street stays a road.
    /// Bastrop State Park stays a park. The `community garden`
    /// phrase already matches that sheet. Phrase `fort dessau`,
    /// not the word `dessau`. Fort Dessau Road stays a road. Fort
    /// Dessau Amenity Center stays a park. The `community garden`
    /// phrase already matches that sheet. Phrase `windsor park
    /// community`, not the word `windsor`. Phrase `lamplight
    /// community`, not the word `lamplight`. Lamplight Village
    /// Avenue stays a road. Phrase `juan navarro`, not the word
    /// `navarro`. Phrase `unity park community`, not the word
    /// `unity`. Phrase `colorado community`, not the word
    /// `colorado`. Colorado River Park Wildlife Sanctuary stays
    /// wildlife. Phrase `alamo community`, not the word `alamo`.
    /// Alamo Street stays a road. Alamo Pocket Park stays a park. Phrase
    /// `barelas community`, not the word `barelas`. 4th Street
    /// Southwest stays a road. The `community garden` phrase
    /// already matches those
    /// sheets. Winrock Garden is a mall bed and stays out.
    /// Experimental Gardens
    /// overlap glasshouses and stay out. `leisure=garden` is
    /// botanic-eligible with a phrase; it is not a cave, wildlife,
    /// or open-reserve key. Memorial Garden stays out.
    static func isBotanicGarden(_ t: [String: String]) -> Bool {
        let amenity = (t["amenity"] ?? "").lowercased()
        if amenity == "community_garden" || amenity == "community garden" { return true }
        let n = (t["name"] ?? "").lowercased()
        let phrase = n.contains("botanic garden")
            || n.contains("botanical garden")
            || n.contains("conservatory")
            || n.contains("cactus garden")
            || n.contains("desert garden")
            || n.contains("rose garden")
            || n.contains("community garden")
            || n.contains("wildflower preserve")
            || n.contains("wildflower center")
            || n.contains("lush n lean")
            || n.contains("orchard garden")
            || n.contains("harvey cornell")
            || n.contains("japaneese garden")
            || n.contains("japanese garden")
            || n.contains("capitol flower")
            || n.contains("japanese memorial")
            || n.contains("demonstration garden")
            || n.contains("preston foster")
            || n.contains("xeriscape garden")
            || n.contains("teaching garden")
            || n.contains("fincher iii garden")
            || n.contains("brazos bluff")
            || n.contains("explorers garden")
            || n.contains("haozous garden")
            || n.contains("este garden")
            || n.contains("4th street garden")
        guard phrase else { return false }
        if t["leisure"] == "garden" { return true }
        let park = t["leisure"] == "park"
            || t["leisure"] == "nature_reserve"
            || t["boundary"] == "protected_area"
            || t["boundary"] == "national_park"
        return park
    }

    /// A mountain ACEC is not picnic woodland. Phrase `area of critical
    /// environmental concern`, not the word `critical` — Gracecus Way
    /// is a street. Phrase `prairie preserve`, not the word `prairie`
    /// — Prairie Hills is apartments. Pronoun Cave is a hole and is
    /// matched first. A wilderness preserve is range (animals first,
    /// trees), not this walk — cactus does not live on Wild Basin.
    /// A named nature reserve that is not already a hole, wildlife
    /// range, or garden is this walk — vipers use that cover. An
    /// unnamed reserve falls through to the landcover. Phrase `open
    /// space` is not a bare `contains` — Open Space Visitor Center, a
    /// farm open space, Alameda/Rio Grande Open Space, and a trailhead
    /// stay parks. Named open-space cover is this walk. Phrase `hueco
    /// tanks`, not the word `hueco` — Hueco Mountain Park is a town
    /// park, and Hueco Tanks Road is a road. Phrase `scenic easement`,
    /// not the word `easement` — a riverside hike-and-bike easement
    /// stays a park. Phrase `la tierra trails`, not the word `tierra`
    /// or `trails` — Tierra Blanca and a trails neighborhood park stay
    /// parks. Phrase `sun mountain`, not the word `sun` or `mountain`
    /// — Hyde Memorial and Manzano stay protected picnic land. The
    /// peak pin stays a peak. Sun Mountain Estates is built-up. Sun
    /// Mountain Road is a road. Phrase `national forest`, not the
    /// word `forest`. Cibola and Santa Fe National Forest are timber.
    /// Lincoln National Forest stays picnic.
    static func isOpenReserve(_ t: [String: String]) -> Bool {
        let n = (t["name"] ?? "").lowercased()
        if n.contains("national forest") { return false }
        let named = !(t["name"] ?? "").isEmpty
        if t["leisure"] == "nature_reserve", named { return true }
        let park = t["leisure"] == "park"
            || t["leisure"] == "nature_reserve"
            || t["boundary"] == "protected_area"
            || t["boundary"] == "national_park"
        guard park else { return false }
        if n.contains("area of critical environmental concern") { return true }
        if n.contains("prairie preserve") { return true }
        if n.contains("hueco tanks") { return true }
        if n.contains("scenic easement") { return true }
        if n.contains("la tierra trails") { return true }
        if n.contains("sun mountain") { return true }
        if n.range(of: "open space") != nil {
            if !n.contains("visitor"),
               !n.contains("farm"),
               !n.contains("rio grande"),
               !n.contains("bachechi"),
               !n.contains("trail") {
                return true
            }
        }
        return false
    }

    /// Named bosque tagged wood or forest is cottonwoods along the
    /// river, not picnic timber. Phrase `bosque`, not a park name and
    /// not apartments. Unnamed wood stays woodland. Isleta Rectangle
    /// is forest without the word and stays woodland. Valle del
    /// Bosque Park stays a park. Bosque Encantado stays built-up.
    /// A named tree still reads as a tree. Streets through the
    /// bosque still win — this is cover, not a silver sheet.
    static func isNamedBosqueCover(_ t: [String: String]) -> Bool {
        let n = (t["name"] ?? "").lowercased()
        if !n.contains("bosque") { return false }
        if t["landuse"] == "residential" { return false }
        if t["leisure"] == "park" { return false }
        return t["natural"] == "wood" || t["landuse"] == "forest"
    }

    private static func match(_ t: [String: String], pack: String? = nil) -> Reading {
        if let r = water(t) { return r }
        if let r = land(t, pack: pack) { return r }
        if let r = builtUp(t) { return r }
        return Reading(
            klass: "Open ground",
            kind: .nothing,
            sure: 20,
            why: "nothing is mapped at this point, so this is the ground around it",
            advice: .field,
            field: lostCard,
            unnamedPenalty: 0
        )
    }

    private static func water(_ t: [String: String]) -> Reading? {
        if t["natural"] == "spring" {
            return Reading(
                klass: "Spring",
                kind: .water,
                sure: 78,
                why: "mapped as a spring; whether it runs today is not in the record",
                advice: .treat,
                field: waterCard
            )
        }
        if let made = t["man_made"] {
            switch made {
            case "water_well":
                return Reading(
                    klass: "Well",
                    kind: .water,
                    sure: 75,
                    why: "mapped as a well; the record does not say if it still draws",
                    advice: .treat,
                    field: waterCard
                )
            case "water_tank":
                return Reading(
                    klass: "Water tank",
                    kind: .water,
                    sure: 74,
                    why: "mapped as a water tank; how full it is now is not recorded",
                    advice: .treat,
                    field: waterCard
                )
            case "cistern":
                return Reading(
                    klass: "Cistern",
                    kind: .water,
                    sure: 70,
                    why: "mapped as a cistern; the record says nothing about its state",
                    advice: .treat,
                    field: waterCard
                )
            case "storage_tank", "reservoir_covered":
                return tank(t)
            default:
                break
            }
        }
        if t["amenity"] == "drinking_water" {
            return Reading(
                klass: "Tap",
                kind: .water,
                sure: 80,
                why: "mapped as a public tap, which means someone plumbed it, not that it flows",
                advice: .treat,
                field: waterCard
            )
        }
        if let way = t["waterway"] {
            switch way {
            case "river":
                return Reading(
                    klass: "River",
                    kind: .water,
                    sure: 88,
                    why: "a river is mapped from its channel, so the line is where the water runs",
                    advice: .treat,
                    field: waterCard,
                    unnamedPenalty: 6
                )
            case "stream":
                return Reading(
                    klass: "Creek",
                    kind: .water,
                    sure: 70,
                    why: "named in the record as a stream",
                    advice: .treat,
                    field: waterCard,
                    unnamedPenalty: 18,
                    unnamedKlass: "Wash or stream",
                    unnamedWhy: "the record says stream and no more; out here that is usually dry between rains"
                )
            case "canal":
                return Reading(
                    klass: "Canal",
                    kind: .water,
                    sure: 82,
                    why: "a dug channel, so it is where the record puts it; whether it is charged is seasonal",
                    advice: .treat,
                    field: waterCard,
                    unnamedPenalty: 6
                )
            case "ditch":
                return Reading(
                    klass: "Acequia or ditch",
                    kind: .water,
                    sure: 68,
                    why: "a dug channel; the record does not separate an acequia from field drainage",
                    advice: .treat,
                    field: waterCard,
                    unnamedPenalty: 8
                )
            case "drain":
                return Reading(
                    klass: "Drain",
                    kind: .water,
                    sure: 74,
                    why: "mapped as a drain, which carries what runs off the ground above it",
                    advice: .leave,
                    field: waterCard,
                    unnamedPenalty: 4
                )
            case "dam", "dam_crest":
                return Reading(
                    klass: "Dam",
                    kind: .water,
                    sure: 80,
                    why: "a structure, so it is mapped where it stands",
                    advice: .treat,
                    field: waterCard,
                    unnamedPenalty: 6
                )
            case "weir", "lock_gate", "fish_pass":
                return Reading(
                    klass: "Weir",
                    kind: .water,
                    sure: 74,
                    why: "a structure in the channel, mapped where it stands",
                    advice: .treat,
                    field: waterCard,
                    unnamedPenalty: 6
                )
            case "wadi":
                return Reading(
                    klass: "Wash",
                    kind: .water,
                    sure: 62,
                    why: "mapped as a dry channel that carries water only after rain",
                    advice: .treat,
                    field: waterCard,
                    unnamedPenalty: 6
                )
            default:
                return Reading(
                    klass: "Channel",
                    kind: .water,
                    sure: 58,
                    why: "the record calls this \(way) and gives nothing further",
                    advice: .treat,
                    field: waterCard
                )
            }
        }
        if t["landuse"] == "reservoir" || t["landuse"] == "basin" || t["water"] == "reservoir" {
            return Reading(
                klass: "Reservoir or tank",
                kind: .water,
                sure: 76,
                why: "mapped as held water; the level is not in the record",
                advice: .treat,
                field: waterCard
            )
        }
        if t["natural"] == "water" {
            return Reading(
                klass: "Water body",
                kind: .water,
                sure: 82,
                why: "mapped as standing water, from its edge",
                advice: .treat,
                field: waterCard,
                unnamedPenalty: 14,
                unnamedWhy: unnamedWaterWhy(t)
            )
        }
        return nil
    }

    /// Water is a rock pool at this size and a reservoir at that one, and a
    /// bare `natural=water` says neither. The outline does, so the tiler
    /// measures it and the card passes the measurement on and stops there. A
    /// tinaja is not a class anyone can hold, because nothing in the record is
    /// tagged as one — but a hold on nine metres of unnamed water in a canyon
    /// can at least say it is nine metres, and let the reader draw their own
    /// conclusion. It is a fact about the outline, never about the water.
    static let smallWaterSpanMetres = 15

    private static func unnamedWaterWhy(_ t: [String: String]) -> String {
        guard let raw = t["span_m"], let across = Int(raw), across > 0 else {
            return "mapped as standing water with no name, which often means a stock tank or a seasonal pool"
        }
        if across <= smallWaterSpanMetres {
            return "mapped as standing water with no name, and the outline is only about \(across)m across — a rock pool, a trough and a dugout all read this way"
        }
        return "mapped as standing water with no name and about \(across)m across, which out here usually means a stock tank or a pool that fills after rain"
    }

    /// A plain storage tank, which is only water if the record says so.
    ///
    /// Around El Paso only 110 of 585 storage tanks carry `content=water`. 470
    /// say nothing at all and a few say fuel. Calling the silent ones water
    /// would invent a supply that is as likely to be diesel, so they are read
    /// as what they are — a tank nobody wrote the contents of — and the card
    /// says leave it rather than treat it.
    private static func tank(_ t: [String: String]) -> Reading {
        switch t["content"] {
        case "water", "drinking_water", "rainwater":
            return Reading(
                klass: "Water tank",
                kind: .water,
                sure: 74,
                why: "the record says this tank holds water; how full it is now is not recorded",
                advice: .treat,
                field: waterCard
            )
        case "wastewater", "sewage", "slurry":
            return Reading(
                klass: "Waste tank",
                kind: .water,
                sure: 76,
                why: "the record says this tank holds waste",
                advice: .leave,
                field: waterCard
            )
        case .some(let content) where content != "unknown":
            return Reading(
                klass: "Tank, holds \(content)",
                kind: .water,
                sure: 74,
                why: "the record names the contents, and they are not water",
                advice: .leave,
                field: waterCard
            )
        default:
            return Reading(
                klass: "Tank, contents unrecorded",
                kind: .water,
                sure: 42,
                why: "a tank is mapped here and nobody wrote down what is in it; out here that is as often fuel as water",
                advice: .leave,
                field: waterCard,
                unnamedPenalty: 2
            )
        }
    }

    private static func land(_ t: [String: String], pack: String? = nil) -> Reading? {
        if t["natural"] == "peak" {
            // Hold names animals as range. Mammal SPEAK names the bite
            // card. Not a hunt, not snake country — cold stays last.
            if isEastPack(pack) {
                return Reading(
                    klass: "Peak",
                    kind: .land,
                    sure: 86,
                    why: "a surveyed point, so the position is firm",
                    advice: .field,
                    field: coldCard,
                    local: [iceRockCard, mammalNMCard, mammalEastCard],
                    extra: [biteCard],
                    unnamedPenalty: 10
                )
            }
            return Reading(
                klass: "Peak",
                kind: .land,
                sure: 86,
                why: "a surveyed point, so the position is firm",
                advice: .field,
                field: coldCard,
                local: [iceRockCard, mammalNMCard, mammalTXCard],
                extra: [biteCard],
                unnamedPenalty: 10
            )
        }
        if let natural = t["natural"] {
            switch natural {
            case "cave", "cave_entrance", "sinkhole":
                return Reading(
                    klass: "Cave or hole",
                    kind: .land,
                    sure: 80,
                    why: "a hole in the record; air, dark and cold are the facts, not a tourist guide",
                    advice: .field,
                    field: coldCard,
                    extra: [caveCard],
                    unnamedPenalty: 6,
                    unnamedWhy: "a hole is mapped here with no name; whether it goes anywhere is not in the record"
                )
            case "tree":
                if isEastPack(pack) {
                    return Reading(
                        klass: "Named tree",
                        kind: .land,
                        sure: 78,
                        why: "a surveyed tree; shade and wood, not a meal",
                        advice: .field,
                        field: plantCard,
                        local: [treeUseEastCard, treeUseNMCard],
                        extra: [plantUseCard],
                        unnamedPenalty: 8,
                        unnamedKlass: "Tree",
                        unnamedWhy: "a tree is mapped here with no name"
                    )
                }
                return Reading(
                    klass: "Named tree",
                    kind: .land,
                    sure: 78,
                    why: "a surveyed tree; shade and wood, not a meal",
                    advice: .field,
                    field: plantCard,
                    local: [treeUseTXCard, treeUseNMCard],
                    extra: [plantUseCard],
                    unnamedPenalty: 8,
                    unnamedKlass: "Tree",
                    unnamedWhy: "a tree is mapped here with no name"
                )
            default:
                break
            }
        }
        if isCavePreserve(t) {
            let namedSink = (t["name"] ?? "").lowercased().contains("blowing sink")
            return Reading(
                klass: "Cave or hole",
                kind: .land,
                sure: 80,
                why: namedSink
                    ? "mapped as a named sink; air, dark and cold are the facts, not a tourist guide"
                    : "mapped as a cave preserve; air, dark and cold are the facts, not a tourist guide",
                advice: .field,
                field: coldCard,
                extra: [caveCard],
                unnamedPenalty: 6,
                unnamedWhy: "a hole is mapped here with no name; whether it goes anywhere is not in the record"
            )
        }
        if isWildlifeRange(t) {
            return wildlifeRange(
                klass: "Wildlife range",
                sure: 84,
                why: "mapped as wildlife range; this is the Field book, not a pin",
                unnamedPenalty: 4,
                pack: pack
            )
        }
        if isCactusGarden(t) {
            return cactusGardenCover(
                klass: "Cactus garden",
                sure: 82,
                why: "mapped as a cactus or desert garden; spines, not a meal, not wild cover"
            )
        }
        if isBotanicGarden(t) {
            return workedCover(
                klass: "Botanic garden",
                sure: 82,
                why: "mapped as a botanic garden; pretty is not food, not wild cover",
                unnamedPenalty: 4
            )
        }
        if isOpenReserve(t) {
            return snakeCountry(
                klass: "Open reserve",
                sure: 84,
                why: "mapped as open reserve; vipers use this cover, not picnic woodland",
                unnamedPenalty: 4,
                pack: pack
            )
        }
        // Named wetland is cottonwoods, even when OSM also tags leisure=park.
        if t["natural"] == "wetland" {
            return wetlandCover(
                klass: "Bosque or wetland",
                sure: 74,
                why: "mapped as wet ground, which is where the cottonwoods stand along the river",
                unnamedPenalty: 4,
                pack: pack
            )
        }
        // Named bosque tagged wood or forest is the same walk. A park
        // named bosque stays a park. Apartments named bosque stay built-up.
        if isNamedBosqueCover(t) {
            return wetlandCover(
                klass: "Bosque or wetland",
                sure: 74,
                why: "mapped as bosque; cottonwoods along the river, not picnic timber",
                unnamedPenalty: 4,
                pack: pack
            )
        }
        // A city park tagged with scrub or wood fill is still kept ground.
        // Tiles may paint the landcover colour first; the hold reads leisure.
        if t["leisure"] == "park" {
            return plantCover(
                klass: "Park",
                sure: 80,
                why: "a drawn boundary around kept ground",
                unnamedPenalty: 6,
                pack: pack
            )
        }
        if let natural = t["natural"] {
            switch natural {
            case "wood":
                return plantCover(
                    klass: "Woodland",
                    sure: 76,
                    why: "mapped as tree cover; the edge moves with the years",
                    unnamedPenalty: 4,
                    pack: pack
                )
            case "scrub", "heath":
                return snakeCountry(
                    klass: "Desert scrub",
                    sure: 72,
                    why: "mapped as low brush, which is the open ground of this country",
                    unnamedPenalty: 2,
                    pack: pack
                )
            case "sand", "dune":
                return snakeCountry(
                    klass: "Sand or playa floor",
                    sure: 70,
                    why: "mapped as bare sand; a playa floor reads the same way and floods after rain",
                    unnamedPenalty: 2,
                    pack: pack
                )
            case "bare_rock", "scree", "ridge", "cliff":
                if isEastPack(pack) {
                    return Reading(
                        klass: "Rock", kind: .land, sure: 74,
                        why: "mapped as bare rock, which holds no shade and no water",
                        advice: .field, field: coldCard,
                        local: [iceRockCard, mammalNMCard, mammalEastCard],
                        extra: [biteCard], unnamedPenalty: 2
                    )
                }
                return Reading(
                    klass: "Rock", kind: .land, sure: 74,
                    why: "mapped as bare rock, which holds no shade and no water",
                    advice: .field, field: coldCard,
                    local: [iceRockCard, mammalNMCard, mammalTXCard],
                    extra: [biteCard], unnamedPenalty: 2
                )
            case "grassland", "grass":
                return snakeCountry(
                    klass: "Grassland",
                    sure: 70,
                    why: "mapped as open grass",
                    unnamedPenalty: 2,
                    pack: pack
                )
            default:
                break
            }
        }
        if t["boundary"] == "protected_area" || t["boundary"] == "national_park" || t["leisure"] == "nature_reserve" {
            return plantCover(
                klass: "Protected land",
                sure: 84,
                why: "a drawn boundary, so the line is exact even where the ground is not",
                unnamedPenalty: 4,
                pack: pack
            )
        }
        if let use = t["landuse"] {
            switch use {
            case "forest":
                return plantCover(
                    klass: "Woodland",
                    sure: 76,
                    why: "mapped as worked timber, so there is tree cover and usually a track in",
                    unnamedPenalty: 4,
                    pack: pack
                )
            case "farmland", "orchard", "meadow", "vineyard", "recreation_ground":
                return irrigatedCover(
                    klass: "Irrigated ground",
                    sure: 74,
                    why: "mapped as worked ground, which in this country means a ditch reaches it",
                    unnamedPenalty: 4,
                    pack: pack
                )
            case "greenhouse_horticulture":
                return workedCover(
                    klass: "Glasshouse",
                    sure: 78,
                    why: "mapped as glasshouses; worked ground a ditch reaches, not wild cover",
                    unnamedPenalty: 4
                )
            case "grass":
                return snakeCountry(
                    klass: "Grassland",
                    sure: 70,
                    why: "mapped as open grass",
                    unnamedPenalty: 2,
                    pack: pack
                )
            case "salt_pond":
                return snakeCountry(
                    klass: "Salt flat",
                    sure: 78,
                    why: "a drawn boundary around worked salt ground, so the outline is exact",
                    unnamedPenalty: 4,
                    pack: pack
                )
            case "residential":
                return Reading(
                    klass: "Built-up ground", kind: .land, sure: 70,
                    why: "a boundary somebody drew round houses and streets, so the edge is firmer than the middle",
                    advice: .field, field: lostCard, local: [heatIslandCard], unnamedPenalty: 4
                )
            default:
                break
            }
        }
        return nil
    }

    /// East bosque names cottonmouth on the hold. The Field walk has to
    /// open that pack's snake card so treatment matches the speech. Parks
    /// stay picnic woodland — Barton Hills is not cottonmouth country.
    /// Snake sits after game so BOOK stays `PLANT · ANIMAL · FOOD · BITE`.
    private static func wetlandCover(
        klass: String,
        sure: Int,
        why: String,
        unnamedPenalty: Int,
        pack: String? = nil
    ) -> Reading {
        if !isEastPack(pack) {
            return plantCover(
                klass: klass,
                sure: sure,
                why: why,
                unnamedPenalty: unnamedPenalty,
                pack: pack
            )
        }
        return Reading(
            klass: klass,
            kind: .land,
            sure: sure,
            why: why,
            advice: .field,
            field: plantCard,
            local: [
                treeUseEastCard, treeUseNMCard,
                plantTXCard, plantNMCard,
                mammalEastCard, mammalNMCard,
                gameEastCard, gameNMCard,
                snakeEastCard, snakeNMCard,
            ],
            extra: [plantUseCard, biteCard, shelterCard, fungiCard, gameCard],
            unnamedPenalty: unnamedPenalty
        )
    }

    /// Tree cover, parks: the trees this cover is, then don't chew,
    /// then animals, game. Unknown last so FIELD still lands with
    /// only the core book. East bosque is `wetlandCover`, not this.
    /// Cactus lives on scrub and cactus gardens, not picnic woodland.
    ///
    /// West `local:` is written first so the source contract can see
    /// `treeUseTXCard` before the first `plantTXCard`. East is the same
    /// shape with this pack's ids.
    private static func plantCover(
        klass: String,
        sure: Int,
        why: String,
        unnamedPenalty: Int,
        unnamedKlass: String? = nil,
        unnamedWhy: String? = nil,
        pack: String? = nil
    ) -> Reading {
        if !isEastPack(pack) {
            return Reading(
                klass: klass,
                kind: .land,
                sure: sure,
                why: why,
                advice: .field,
                field: plantCard,
                local: [
                    treeUseTXCard, treeUseNMCard,
                    plantTXCard, plantNMCard,
                    mammalTXCard, mammalNMCard,
                    gameTXCard, gameNMCard,
                ],
                extra: [plantUseCard, biteCard, shelterCard, fungiCard, gameCard],
                unnamedPenalty: unnamedPenalty,
                unnamedKlass: unnamedKlass,
                unnamedWhy: unnamedWhy
            )
        }
        return Reading(
            klass: klass,
            kind: .land,
            sure: sure,
            why: why,
            advice: .field,
            field: plantCard,
            local: [
                treeUseEastCard, treeUseNMCard,
                plantTXCard, plantNMCard,
                mammalEastCard, mammalNMCard,
                gameEastCard, gameNMCard,
            ],
            extra: [plantUseCard, biteCard, shelterCard, fungiCard, gameCard],
            unnamedPenalty: unnamedPenalty,
            unnamedKlass: unnamedKlass,
            unnamedWhy: unnamedWhy
        )
    }

    /// A ditch reaches it. Pack trees and don't chew. Not a hunt, not
    /// javelina country, not a cactus garden. Parks stay `plantCover`.
    private static func irrigatedCover(
        klass: String,
        sure: Int,
        why: String,
        unnamedPenalty: Int,
        pack: String? = nil
    ) -> Reading {
        if !isEastPack(pack) {
            return Reading(
                klass: klass,
                kind: .land,
                sure: sure,
                why: why,
                advice: .field,
                field: plantCard,
                local: [
                    treeUseTXCard, treeUseNMCard,
                    plantTXCard, plantNMCard,
                ],
                extra: [plantUseCard],
                unnamedPenalty: unnamedPenalty
            )
        }
        return Reading(
            klass: klass,
            kind: .land,
            sure: sure,
            why: why,
            advice: .field,
            field: plantCard,
            local: [
                treeUseEastCard, treeUseNMCard,
                plantTXCard, plantNMCard,
            ],
            extra: [plantUseCard],
            unnamedPenalty: unnamedPenalty
        )
    }

    /// Open country: the state's snakes, then bite, then heat.
    private static func snakeCountry(
        klass: String,
        sure: Int,
        why: String,
        unnamedPenalty: Int,
        pack: String? = nil
    ) -> Reading {
        if !isEastPack(pack) {
            return Reading(
                klass: klass,
                kind: .land,
                sure: sure,
                why: why,
                advice: .field,
                field: heatCard,
                local: [
                    snakeTXCard, snakeNMCard,
                    mammalTXCard, mammalNMCard,
                    cactusTXCard, cactusNMCard,
                    treeUseTXCard, treeUseNMCard,
                    plantTXCard, plantNMCard,
                    gameTXCard, gameNMCard,
                ],
                extra: [biteCard, plantUseCard, gameCard],
                unnamedPenalty: unnamedPenalty
            )
        }
        return Reading(
            klass: klass,
            kind: .land,
            sure: sure,
            why: why,
            advice: .field,
            field: heatCard,
            local: [
                snakeEastCard, snakeNMCard,
                mammalEastCard, mammalNMCard,
                cactusTXCard, cactusNMCard,
                treeUseEastCard, treeUseNMCard,
                plantTXCard, plantNMCard,
                gameEastCard, gameNMCard,
            ],
            extra: [biteCard, plantUseCard, gameCard],
            unnamedPenalty: unnamedPenalty
        )
    }

    /// A cactus garden: spines, not oleander, not woodland tree-use.
    private static func cactusGardenCover(
        klass: String,
        sure: Int,
        why: String,
        unnamedPenalty: Int = 4
    ) -> Reading {
        return Reading(
            klass: klass,
            kind: .land,
            sure: sure,
            why: why,
            advice: .field,
            field: plantCard,
            local: [
                cactusTXCard, cactusNMCard,
            ],
            unnamedPenalty: unnamedPenalty
        )
    }

    /// Glasshouses and botanic gardens: don't chew. Not woodland
    /// tree-use, not plant-use, not a hunt, not a cactus garden.
    private static func workedCover(
        klass: String,
        sure: Int,
        why: String,
        unnamedPenalty: Int
    ) -> Reading {
        return Reading(
            klass: klass,
            kind: .land,
            sure: sure,
            why: why,
            advice: .field,
            field: plantCard,
            local: [
                plantTXCard, plantNMCard,
            ],
            unnamedPenalty: unnamedPenalty
        )
    }

    /// A wildlife refuge or WMA: this pack's animals first. Range, not a pin.
    private static func wildlifeRange(
        klass: String,
        sure: Int,
        why: String,
        unnamedPenalty: Int,
        pack: String? = nil
    ) -> Reading {
        if !isEastPack(pack) {
            return Reading(
                klass: klass,
                kind: .land,
                sure: sure,
                why: why,
                advice: .field,
                field: plantCard,
                local: [
                    mammalTXCard, mammalNMCard,
                    snakeTXCard, snakeNMCard,
                    gameTXCard, gameNMCard,
                    treeUseTXCard, treeUseNMCard,
                    plantTXCard, plantNMCard,
                ],
                extra: [biteCard, plantUseCard, gameCard],
                unnamedPenalty: unnamedPenalty
            )
        }
        return Reading(
            klass: klass,
            kind: .land,
            sure: sure,
            why: why,
            advice: .field,
            field: plantCard,
            local: [
                mammalEastCard, mammalNMCard,
                snakeEastCard, snakeNMCard,
                gameEastCard, gameNMCard,
                treeUseEastCard, treeUseNMCard,
                plantTXCard, plantNMCard,
            ],
            extra: [biteCard, plantUseCard, gameCard],
            unnamedPenalty: unnamedPenalty
        )
    }

    private static func builtUp(_ t: [String: String]) -> Reading? {
        if let place = t["place"] {
            let klass: String
            switch place {
            case "city": klass = "City"
            case "town": klass = "Town"
            case "village": klass = "Village"
            case "hamlet": klass = "Hamlet"
            case "suburb", "neighbourhood", "quarter": klass = "Neighbourhood"
            default: klass = "Settlement"
            }
            return Reading(
                klass: klass, kind: .place, sure: 84,
                why: "a named place in the record, put at its centre rather than its edge",
                advice: .field, field: lostCard, unnamedPenalty: 20
            )
        }
        if let highway = t["highway"] {
            let paved = ["motorway", "trunk", "primary", "secondary", "tertiary", "residential", "unclassified", "living_street"]
            let foot = ["path", "footway", "steps", "bridleway", "cycleway", "pedestrian"]
            let klass: String
            var sure = 84
            var local: [String] = []
            if paved.contains(highway) {
                klass = "Road"
            } else if foot.contains(highway) {
                klass = "Trail"
                sure = 74
            } else if highway == "track" {
                klass = "Track"
                sure = 72
                // A track out here is a ranch road, and a ranch road is where
                // the grate across it takes an ankle.
                local = [ranchRoadCard]
            } else if highway == "service" {
                klass = "Service road"
                sure = 78
            } else {
                klass = "Road"
            }
            return Reading(
                klass: klass, kind: .street, sure: sure,
                why: "drawn from its centreline, so the line is the way itself",
                advice: .field, field: lostCard, local: local, unnamedPenalty: 6
            )
        }
        return nil
    }
}
