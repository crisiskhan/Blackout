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
    /// Water first: finding water is what holding a place is for, so holding
    /// where a wash crosses a road is a question about the wash.
    ///
    /// After that, a record the survey named beats one it did not, because a
    /// name means somebody stood at that exact thing. Between two named
    /// records take the smaller: a street is a line you aimed at, landcover is
    /// a sheet you cannot miss. `landuse=residential` is drawn under every
    /// street in Las Cruces, so without that a hold downtown answers with the
    /// subdivision instead of the road under the thumb. Between two unnamed
    /// records take the ground, because out there the biome is the answer and
    /// an unnamed ranch track is not.
    ///
    /// Sampling 4,000 points across the tx-west pack, a street and a piece of
    /// ground are both under the thumb 1.5% of the time, and that split is
    /// roughly even between the two rules — which is why it takes both.
    public static func pick(_ found: [[String: String]]) -> [String: String] {
        func rank(_ tags: [String: String]) -> Int {
            let named = !((tags["name"] ?? tags["ref"] ?? "").isEmpty)
            let notable = packGroundPointNaturals.contains(tags["natural"] ?? "")
            switch read(tags: tags).kind {
            case .water:
                return 0
            case .land where notable:
                return 1
            case .street where named:
                return 2
            case .land where named:
                return 3
            case .place where named:
                return 4
            case .land:
                return 5
            case .street:
                return 6
            case .place:
                return 7
            case .nothing:
                return 8
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
        DestinationPin.ringLayerID, DestinationPin.coreLayerID, RouteLine.layerID,
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
    public static let mammalTXCard = "tx-mammal"
    public static let mammalNMCard = "nm-mammal"
    public static let cactusTXCard = "tx-cactus"
    public static let cactusNMCard = "nm-cactus"
    public static let gameTXCard = "tx-game"
    public static let gameNMCard = "nm-game"

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
        state: String? = nil
    ) -> Card {
        let name = (tags["name"] ?? tags["ref"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let named = !name.isEmpty
        let reading = match(tags)
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
                state: state
            )
        )
    }

    // MARK: - The table

    private static func match(_ t: [String: String]) -> Reading {
        if let r = water(t) { return r }
        if let r = land(t) { return r }
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

    private static func land(_ t: [String: String]) -> Reading? {
        if t["natural"] == "peak" {
            return Reading(
                klass: "Peak",
                kind: .land,
                sure: 86,
                why: "a surveyed point, so the position is firm",
                advice: .field,
                field: coldCard,
                local: [iceRockCard, mammalNMCard, mammalTXCard],
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
            case "wood":
                return plantCover(
                    klass: "Woodland",
                    sure: 76,
                    why: "mapped as tree cover; the edge moves with the years",
                    unnamedPenalty: 4
                )
            case "scrub", "heath":
                return snakeCountry(
                    klass: "Desert scrub",
                    sure: 72,
                    why: "mapped as low brush, which is the open ground of this country",
                    unnamedPenalty: 2
                )
            case "sand", "dune":
                return snakeCountry(
                    klass: "Sand or playa floor",
                    sure: 70,
                    why: "mapped as bare sand; a playa floor reads the same way and floods after rain",
                    unnamedPenalty: 2
                )
            case "wetland":
                return plantCover(
                    klass: "Bosque or wetland",
                    sure: 74,
                    why: "mapped as wet ground, which is where the cottonwoods stand along the river",
                    unnamedPenalty: 4
                )
            case "bare_rock", "scree", "ridge", "cliff":
                return Reading(
                    klass: "Rock", kind: .land, sure: 74,
                    why: "mapped as bare rock, which holds no shade and no water",
                    advice: .field, field: coldCard,
                    local: [iceRockCard, mammalNMCard, mammalTXCard], unnamedPenalty: 2
                )
            case "grassland", "grass":
                return snakeCountry(
                    klass: "Grassland",
                    sure: 70,
                    why: "mapped as open grass",
                    unnamedPenalty: 2
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
                unnamedPenalty: 4
            )
        }
        if t["leisure"] == "park" {
            return plantCover(
                klass: "Park",
                sure: 80,
                why: "a drawn boundary around kept ground",
                unnamedPenalty: 6
            )
        }
        if let use = t["landuse"] {
            switch use {
            case "forest":
                return plantCover(
                    klass: "Woodland",
                    sure: 76,
                    why: "mapped as worked timber, so there is tree cover and usually a track in",
                    unnamedPenalty: 4
                )
            case "farmland", "orchard", "meadow", "vineyard", "recreation_ground":
                return plantCover(
                    klass: "Irrigated ground",
                    sure: 74,
                    why: "mapped as worked ground, which in this country means a ditch reaches it",
                    unnamedPenalty: 4
                )
            case "salt_pond":
                return snakeCountry(
                    klass: "Salt flat",
                    sure: 78,
                    why: "a drawn boundary around worked salt ground, so the outline is exact",
                    unnamedPenalty: 4
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

    /// Tree cover, parks, bosque: the trees this cover is, then don't chew,
    /// then cactus, animals, game. Unknown last so FIELD still lands with
    /// only the core book.
    private static func plantCover(
        klass: String,
        sure: Int,
        why: String,
        unnamedPenalty: Int,
        unnamedKlass: String? = nil,
        unnamedWhy: String? = nil
    ) -> Reading {
        Reading(
            klass: klass,
            kind: .land,
            sure: sure,
            why: why,
            advice: .field,
            field: plantCard,
            local: [
                treeUseTXCard, treeUseNMCard,
                plantTXCard, plantNMCard,
                cactusTXCard, cactusNMCard,
                mammalTXCard, mammalNMCard,
                gameTXCard, gameNMCard,
            ],
            extra: [plantUseCard, biteCard, shelterCard, fungiCard, gameCard],
            unnamedPenalty: unnamedPenalty,
            unnamedKlass: unnamedKlass,
            unnamedWhy: unnamedWhy
        )
    }

    /// Open country: the state's snakes, then bite, then heat.
    private static func snakeCountry(
        klass: String,
        sure: Int,
        why: String,
        unnamedPenalty: Int
    ) -> Reading {
        Reading(
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
