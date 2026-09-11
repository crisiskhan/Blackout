import Foundation

/// What kind of water a record is, in the words used on the ground in Texas and
/// New Mexico.
///
/// Raw values are the wire codes. They must stay in step with `CLASSES` in
/// `tools/v3/water.py`; the index refuses a code it does not know rather than
/// guessing, so a drift shows up as "no water here" and not as a wrong answer.
public enum WaterClass: UInt8, CaseIterable, Sendable {
    case spring = 0
    case tank = 1
    case acequia = 2
    case drain = 3
    case playa = 4
    case tinaja = 5
    case canal = 6
    case ditch = 7
    case stream = 8
    case river = 9
    case reservoir = 10
    /// Standing water the extract does not say the kind of.
    case water = 11
    case wetland = 12
    case dam = 13
    case tap = 14

    /// The seven the close zoom draws a class mark for. The rest already read
    /// as the line or the fill the vector tiles draw.
    public var isDetail: Bool {
        switch self {
        case .spring, .tank, .acequia, .drain, .playa, .tinaja, .canal:
            return true
        case .ditch, .stream, .river, .reservoir, .water, .wetland, .dam, .tap:
            return false
        }
    }

    public var title: String {
        switch self {
        case .spring: return "SPRING"
        case .tank: return "STOCK TANK"
        case .acequia: return "ACEQUIA"
        case .drain: return "DRAIN"
        case .playa: return "PLAYA"
        case .tinaja: return "TINAJA"
        case .canal: return "CANAL"
        case .ditch: return "DITCH"
        case .stream: return "STREAM"
        case .river: return "RIVER"
        case .reservoir: return "RESERVOIR"
        case .water: return "WATER"
        case .wetland: return "WETLAND"
        case .dam: return "DAM"
        case .tap: return "TAP"
        }
    }

    /// One line of what to do with this kind of water, in the field, now.
    ///
    /// None of it is a verdict on the water. Every line ends at the same place
    /// the `water-disinfect` card starts, because treating it is the answer
    /// whatever the class turned out to be.
    public var doLine: String {
        switch self {
        case .spring:
            return "Best odds of the lot. Take it at the source, above any hoofprints. Still boil it."
        case .tank:
            return "Stock tank: cattle stand in it. Dip clear of the churned edge, settle, filter cloth, boil."
        case .acequia:
            return "Live irrigation ditch — field runoff and whatever is upstream of you. Settle and boil."
        case .drain:
            return "Drain carries road and field wash. Last resort. Settle long, filter cloth, boil hard."
        case .playa:
            return "Playa fills after rain and goes alkaline as it dries. Taste-test nothing. Settle and boil."
        case .tinaja:
            return "Rock basin, no inflow — it is as old as the last storm. Skim, filter cloth, boil."
        case .canal:
            return "Canal moves and carries silt. Draw from the current, settle it out, then boil."
        case .ditch:
            return "Ditch: shallow, still, field-fed. Settle, filter cloth, boil."
        case .stream:
            return "Running water beats standing. Draw upstream of any crossing or camp, then boil."
        case .river:
            return "Draw from the current, not the slack. Silt settles out; what is dissolved does not. Boil."
        case .reservoir:
            return "Open water off the shoreline mud. Settle, filter cloth, boil."
        case .water:
            return "Kind unknown — treat it as the worst of the list. Settle, filter cloth, boil."
        case .wetland:
            return "Wetland water is stagnant and organic. Find moving water first. If not, settle and boil."
        case .dam:
            return "This is the structure, not the water. Take water off the pool above it, then boil."
        case .tap:
            return "A tap with no pressure and no report is surface water. Treat it exactly the same."
        }
    }
}

/// What a class was decided by. The card prints it, because "the tag says so"
/// and "the name says so" are not the same claim.
public enum WaterEvidence: UInt8, CaseIterable, Sendable {
    /// An OSM tag names the class outright.
    case tagged = 0
    /// The tag says water; the name says which kind.
    case named = 1
    /// The tag says water and nothing says which kind.
    case generic = 2
}

/// The closed tag table the wire indexes into. Mirrors `TAGS` in
/// `tools/v3/water.py` — change one, change both.
public enum WaterTag {
    public static let wire: [String] = [
        "waterway=canal",
        "waterway=drain",
        "waterway=ditch",
        "waterway=stream",
        "waterway=river",
        "waterway=dam",
        "waterway=weir",
        "waterway=lock_gate",
        "waterway=dam_crest",
        "waterway=fish_pass",
        "waterway=floating_barrier",
        "waterway=rapids",
        "waterway=waterfall",
        "natural=water",
        "natural=spring",
        "natural=wetland",
        "landuse=reservoir",
        "landuse=basin",
        "landuse=reservoir_watershed",
        "amenity=drinking_water",
    ]
}

public struct WaterRecord: Equatable, Sendable {
    public var kind: WaterClass
    public var evidence: WaterEvidence
    /// The OSM tag the classification leaned on.
    public var tag: String
    /// Empty when the feature is unnamed, which most of them are.
    public var name: String

    public init(kind: WaterClass, evidence: WaterEvidence, tag: String, name: String) {
        self.kind = kind
        self.evidence = evidence
        self.tag = tag
        self.name = name
    }
}

public struct WaterHit: Equatable, Sendable {
    public var record: WaterRecord
    /// The sampled point that matched, not the feature's centre.
    public var lat: Double
    public var lon: Double
    public var distanceMeters: Double

    public init(record: WaterRecord, lat: Double, lon: Double, distanceMeters: Double) {
        self.record = record
        self.lat = lat
        self.lon = lon
        self.distanceMeters = distanceMeters
    }
}

/// How sure the app is about the **record**, in percent.
///
/// This is not a statement about the water. A tagged spring scores 95 because
/// OpenStreetMap says it is a spring, not because anything says it is safe; a
/// press that lands 100 m off scores lower because it is less likely to be
/// talking about the thing under the thumb. Nothing in here has ever seen the
/// water, and the card says so out loud.
public enum WaterSure {
    public static let disclaimer =
        "SURE is how sure of the record, not of the water. Nothing here says it is safe to drink."

    public static func classConfidence(_ evidence: WaterEvidence) -> Double {
        switch evidence {
        case .tagged: return 0.95
        case .named: return 0.78
        case .generic: return 0.55
        }
    }

    /// Falls from 1 under the thumb to 0.55 at the edge of what the press could
    /// have meant. Never below, because the record is still a real record.
    public static func matchConfidence(distanceMeters: Double, radiusMeters: Double) -> Double {
        guard radiusMeters > 0 else { return 1 }
        let reach = min(max(distanceMeters, 0) / radiusMeters, 1)
        return 1 - 0.45 * reach
    }

    public static func percent(
        evidence: WaterEvidence,
        distanceMeters: Double,
        radiusMeters: Double
    ) -> Int {
        let raw = classConfidence(evidence)
            * matchConfidence(distanceMeters: distanceMeters, radiusMeters: radiusMeters)
        return Int((raw * 100).rounded())
    }
}

/// Which water is drawn at which zoom, and how far a press reaches.
public enum WaterZoom {
    /// Fills draw from the bottom of the range: far out, the water is the shape
    /// of the ground and nothing else.
    public static let fillMinZoom: Double = 0
    /// The tiles carry no waterway below this, so a line layer drawn under it
    /// was promising geometry that is not in the archive.
    public static let lineMinZoom: Double = 11
    /// Class marks — spring, tank, acequia, drain, playa, tinaja, canal.
    public static let detailMinZoom: Double = 14
    /// Their names, one zoom later, so the marks land before the labels crowd.
    public static let labelMinZoom: Double = 15

    public enum Band: String, CaseIterable, Sendable {
        case fill, line, detail
    }

    public static func bands(atZoom zoom: Double) -> Set<Band> {
        var out: Set<Band> = []
        if zoom >= fillMinZoom { out.insert(.fill) }
        if zoom >= lineMinZoom { out.insert(.line) }
        if zoom >= detailMinZoom { out.insert(.detail) }
        return out
    }

    /// A thumb is about this wide on the glass, and that is the whole reason
    /// the press reach shrinks as the map zooms in: the same thumb covers less
    /// ground, so it should claim less ground.
    public static let pressRadiusPoints: Double = 28
    public static let minPressRadiusMeters: Double = 40
    public static let maxPressRadiusMeters: Double = 400

    /// Web-mercator ground resolution at 256-point tiles.
    public static func metersPerPoint(zoom: Double, latitude: Double) -> Double {
        let clamped = min(max(latitude, -85), 85)
        return 156_543.03392 * cos(clamped * .pi / 180) / pow(2, zoom)
    }

    public static func pressRadiusMeters(zoom: Double, latitude: Double) -> Double {
        let raw = metersPerPoint(zoom: zoom, latitude: latitude) * pressRadiusPoints
        return min(max(raw, minPressRadiusMeters), maxPressRadiusMeters)
    }
}

/// The water in one pack, as the arrays the wire holds.
///
/// Records keep their strings out of memory: 19,547 of them in tx-west would be
/// 39,094 `String`s built at load to answer one press. The name blob stays as
/// bytes and only the record that actually matched is ever turned into one.
public struct WaterIndex: Sendable {
    public static let magic: [UInt8] = Array("BLKTWTR".utf8) + [1]
    public static let version: UInt32 = 1
    public static let header = 24
    public static let recordStride = 16

    let kind: [UInt8]
    let evidence: [UInt8]
    let tag: [UInt8]
    let pointCount: [UInt8]
    let nameAt: [UInt32]
    let nameLength: [UInt16]
    let firstPoint: [UInt32]
    let latE7: [Int32]
    let lonE7: [Int32]
    let names: [UInt8]

    public var recordCount: Int { kind.count }
    public var pointTotal: Int { latE7.count }
    public var isEmpty: Bool { kind.isEmpty }

    public static func load(from url: URL?) -> WaterIndex? {
        // Mapped rather than read: the layout is what the reader wants, so its
        // pages fault in as they are touched instead of all at once.
        guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return load(data)
    }

    public static func load(_ data: Data) -> WaterIndex? {
        data.withUnsafeBytes { raw -> WaterIndex? in
            guard raw.count >= header else { return nil }
            for (i, byte) in magic.enumerated() where raw[i] != byte { return nil }
            guard u32(raw, 8) == version else { return nil }

            let records = Int(u32(raw, 12))
            let points = Int(u32(raw, 16))
            let nameBytes = Int(u32(raw, 20))
            // Every offset below comes out of these three counts, so one length
            // check here means nothing after it can read past the end.
            let want = header + recordStride * records + 8 * points + nameBytes
            guard records > 0, points > 0, raw.count == want else { return nil }

            var kind = [UInt8](repeating: 0, count: records)
            var evidence = [UInt8](repeating: 0, count: records)
            var tag = [UInt8](repeating: 0, count: records)
            var pointCount = [UInt8](repeating: 0, count: records)
            var nameAt = [UInt32](repeating: 0, count: records)
            var nameLength = [UInt16](repeating: 0, count: records)
            var firstPoint = [UInt32](repeating: 0, count: records)

            let tagCount = UInt8(clamping: WaterTag.wire.count)
            for i in 0..<records {
                let at = header + recordStride * i
                let k = raw[at]
                let e = raw[at + 1]
                let t = raw[at + 2]
                let n = raw[at + 3]
                // A code this build does not know is a pack from a later tool.
                // Refusing the file beats answering a press with a class the
                // app would have to invent a name for.
                guard WaterClass(rawValue: k) != nil,
                      WaterEvidence(rawValue: e) != nil,
                      t < tagCount,
                      n > 0
                else { return nil }
                let nameOffset = u32(raw, at + 4)
                let nameLen = u16(raw, at + 8)
                let first = u32(raw, at + 12)
                guard Int(nameOffset) + Int(nameLen) <= nameBytes,
                      Int(first) + Int(n) <= points
                else { return nil }
                kind[i] = k
                evidence[i] = e
                tag[i] = t
                pointCount[i] = n
                nameAt[i] = nameOffset
                nameLength[i] = nameLen
                firstPoint[i] = first
            }

            var latE7 = [Int32](repeating: 0, count: points)
            var lonE7 = [Int32](repeating: 0, count: points)
            let coordsAt = header + recordStride * records
            for p in 0..<points {
                latE7[p] = Int32(bitPattern: u32(raw, coordsAt + 8 * p))
                lonE7[p] = Int32(bitPattern: u32(raw, coordsAt + 8 * p + 4))
            }

            let namesAt = coordsAt + 8 * points
            var names = [UInt8](repeating: 0, count: nameBytes)
            for i in 0..<nameBytes { names[i] = raw[namesAt + i] }

            return WaterIndex(
                kind: kind,
                evidence: evidence,
                tag: tag,
                pointCount: pointCount,
                nameAt: nameAt,
                nameLength: nameLength,
                firstPoint: firstPoint,
                latE7: latE7,
                lonE7: lonE7,
                names: names
            )
        }
    }

    public func record(at index: Int) -> WaterRecord? {
        guard index >= 0, index < recordCount,
              let kindValue = WaterClass(rawValue: kind[index]),
              let evidenceValue = WaterEvidence(rawValue: evidence[index]),
              Int(tag[index]) < WaterTag.wire.count
        else { return nil }
        let at = Int(nameAt[index])
        let length = Int(nameLength[index])
        let name = length > 0 ? String(decoding: names[at..<(at + length)], as: UTF8.self) : ""
        return WaterRecord(
            kind: kindValue,
            evidence: evidenceValue,
            tag: WaterTag.wire[Int(tag[index])],
            name: name
        )
    }

    /// The closest sampled water point within `radius`, or nil.
    ///
    /// A flat sweep with a latitude-band reject. The alternative is a grid that
    /// costs memory at load to save a fraction of a millisecond once per press,
    /// which is the wrong trade for something a thumb starts.
    public func nearest(lat: Double, lon: Double, withinMeters radius: Double) -> WaterHit? {
        guard radius > 0, !isEmpty else { return nil }
        let metresPerDegLat = 111_320.0
        let metresPerDegLon = metresPerDegLat * max(cos(lat * .pi / 180), 1e-6)
        let latBandE7 = Int32(clamping: Int((radius / metresPerDegLat) * 1e7) + 1)
        let latTargetE7 = Int32(clamping: Int((lat * 1e7).rounded()))

        var bestSquared = radius * radius
        var bestRecord = -1
        var bestPoint = -1

        for r in 0..<recordCount {
            let start = Int(firstPoint[r])
            let end = start + Int(pointCount[r])
            for p in start..<end {
                let dLatE7 = latE7[p] &- latTargetE7
                if dLatE7 > latBandE7 || dLatE7 < -latBandE7 { continue }
                let dLat = (Double(latE7[p]) / 1e7 - lat) * metresPerDegLat
                let dLon = (Double(lonE7[p]) / 1e7 - lon) * metresPerDegLon
                let squared = dLat * dLat + dLon * dLon
                if squared < bestSquared {
                    bestSquared = squared
                    bestRecord = r
                    bestPoint = p
                }
            }
        }

        guard bestRecord >= 0, let found = record(at: bestRecord) else { return nil }
        return WaterHit(
            record: found,
            lat: Double(latE7[bestPoint]) / 1e7,
            lon: Double(lonE7[bestPoint]) / 1e7,
            distanceMeters: bestSquared.squareRoot()
        )
    }

    private static func u32(_ raw: UnsafeRawBufferPointer, _ at: Int) -> UInt32 {
        UInt32(raw[at]) | UInt32(raw[at + 1]) << 8 | UInt32(raw[at + 2]) << 16 | UInt32(raw[at + 3]) << 24
    }

    private static func u16(_ raw: UnsafeRawBufferPointer, _ at: Int) -> UInt16 {
        UInt16(raw[at]) | UInt16(raw[at + 1]) << 8
    }
}

public enum InspectSubject: Equatable, Sendable {
    case water(WaterHit)
    /// Ground, with whatever water is close enough to be worth pointing at.
    case land(nearest: WaterHit?)
}

/// Which Field card a press hands off to.
public enum InspectField {
    public static let water = "water-disinfect"
    public static let land = "nav-lost"

    public enum Procedure: Sendable, Equatable {
        case water
        case plant
        case bite
        case cave
        case shelter
        case lost
        case heat
        case cold
        case fungi
        case food
        case animal
        case field
    }

    public static func cardID(for subject: InspectSubject) -> String {
        switch subject {
        case .water: return water
        case .land: return land
        }
    }

    public static func procedure(for cardID: String) -> Procedure {
        switch cardID {
        case water:
            return .water
        case Inspect.plantCard, Inspect.plantTXCard, Inspect.plantNMCard, Inspect.plantUseCard,
             Inspect.treeUseTXCard, Inspect.treeUseNMCard, Inspect.treeUseEastCard,
             Inspect.cactusTXCard, Inspect.cactusNMCard:
            return .plant
        case Inspect.snakeTXCard, Inspect.snakeNMCard, Inspect.snakeEastCard, Inspect.biteCard:
            return .bite
        case Inspect.mammalTXCard, Inspect.mammalNMCard, Inspect.mammalEastCard:
            return .animal
        case Inspect.caveCard:
            return .cave
        case Inspect.shelterCard:
            return .shelter
        case land:
            return .lost
        case Inspect.heatCard, Inspect.heatIslandCard:
            return .heat
        case Inspect.coldCard, Inspect.iceRockCard:
            return .cold
        case Inspect.fungiCard:
            return .fungi
        case Inspect.gameCard, Inspect.gameTXCard, Inspect.gameNMCard, Inspect.gameEastCard, "food-cook":
            return .food
        default:
            return .field
        }
    }

    /// What the button says. Naming the procedure means the handoff is visible
    /// before it is taken rather than after.
    public static func label(for cardID: String) -> String {
        switch procedure(for: cardID) {
        case .water: return "FIELD · WATER"
        case .plant: return "FIELD · PLANT"
        case .bite: return "FIELD · BITE"
        case .cave: return "FIELD · CAVE"
        case .shelter: return "FIELD · SHELTER"
        case .lost: return "FIELD · LOST"
        case .heat: return "FIELD · HEAT"
        case .cold: return "FIELD · COLD"
        case .fungi: return "FIELD · FUNGI"
        case .food: return "FIELD · FOOD"
        case .animal: return "FIELD · ANIMAL"
        case .field: return "FIELD"
        }
    }

    /// What the last step of a jumped card becomes when another card on the
    /// hold's route is still waiting. Naming the next procedure is the same
    /// honesty as the hold button: you see the handoff before you take it.
    public static func nextAction(for cardID: String) -> String {
        switch procedure(for: cardID) {
        case .water: return "NEXT · WATER"
        case .plant: return "NEXT · PLANT"
        case .bite: return "NEXT · BITE"
        case .cave: return "NEXT · CAVE"
        case .shelter: return "NEXT · SHELTER"
        case .lost: return "NEXT · LOST"
        case .heat: return "NEXT · HEAT"
        case .cold: return "NEXT · COLD"
        case .fungi: return "NEXT · FUNGI"
        case .food: return "NEXT · FOOD"
        case .animal: return "NEXT · ANIMAL"
        case .field: return "NEXT"
        }
    }

    public static func bookWord(for procedure: Procedure) -> String {
        switch procedure {
        case .water: return "WATER"
        case .plant: return "PLANT"
        case .bite: return "BITE"
        case .cave: return "CAVE"
        case .shelter: return "SHELTER"
        case .lost: return "LOST"
        case .heat: return "HEAT"
        case .cold: return "COLD"
        case .fungi: return "FUNGI"
        case .food: return "FOOD"
        case .animal: return "ANIMAL"
        case .field: return "FIELD"
        }
    }

    /// Unique procedures on the route, in order. One card is not a book —
    /// a spring is WATER, a hole is CAVE, and the hold should not pretend
    /// there is a trail behind them.
    public static func bookLine(for route: [String]) -> String? {
        var seen = Set<Procedure>()
        var words: [String] = []
        for id in route {
            let next = procedure(for: id)
            if seen.insert(next).inserted {
                words.append(bookWord(for: next))
            }
        }
        guard words.count > 1 else { return nil }
        return words.joined(separator: " · ")
    }

    /// The hold's route, minus cards this book's load does not have.
    /// Texas has no ice-on-rock card; New Mexico has no heat-island. The
    /// state's own card is first when it is present, and the core cards
    /// behind it still run.
    public static func presentRoute(_ route: [String], in book: Set<String>) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in route {
            guard book.contains(id), seen.insert(id).inserted else { continue }
            out.append(id)
        }
        return out
    }

    /// What a FIELD still is, when the matcher named a kind. Not a species ID.
    public enum VisionGround: Sendable, Equatable {
        case tree
        case cactus
        case snake
        case mammal
        case fungi
    }

    /// UNKNOWN and no model stay empty — a missing guess is not a card.
    public static func visionGround(labelId: String) -> VisionGround? {
        let id = labelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch id {
        case "", "no-model", "unknown":
            return nil
        case "kind:fungi":
            return .fungi
        case "kind:snake":
            return .snake
        case "kind:mammal":
            return .mammal
        case "kind:tree":
            return .tree
        case "kind:cactus", "kind:cacti_yucca":
            return .cactus
        default:
            return visionGroundFromSpecies(id)
        }
    }

    private static func visionGroundFromSpecies(_ id: String) -> VisionGround? {
        if id.contains("fungi") || id.contains("amanita") || id.contains("galerina")
            || id.contains("morel") || id.hasSuffix("jack")
        {
            return .fungi
        }
        if id.contains("snake") || id.contains("diamondback") || id.contains("copperhead")
            || id.contains("cottonmouth") || id.contains("rattler")
        {
            return .snake
        }
        if id.contains("coyote") || id.contains("javelina") || id.contains("whitetail")
            || id.contains("elk") || id.contains("deer") || id.contains("bear")
            || id.contains("hog")
        {
            return .mammal
        }
        if id.contains("prickly") || id.contains("cholla") || id.contains("yucca") || id.contains("sotol") {
            return .cactus
        }
        if id.contains("oak") || id.contains("mesquite") || id.contains("elm") || id.contains("pecan")
            || id.contains("pinon") || id.contains("juniper") || id.contains("aspen")
            || id.contains("cottonwood") || id.contains("pine") || id.contains("loblolly")
        {
            return .tree
        }
        return nil
    }

    /// The still named a kind. Open that kind's cards — not the whole biome.
    /// A javelina is the mammal trail, not woodland plant-danger. East Texas
    /// opens this pack's chapter unless the still named a west-only species.
    public static func fieldRoute(forVision labelId: String, state: String?, pack: String? = nil) -> [String] {
        guard let ground = visionGround(labelId: labelId) else { return [] }
        let id = labelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nm = (state ?? "").uppercased() == "NM"
        let east = Inspect.isEastPack(pack)
        switch ground {
        case .fungi:
            return [Inspect.fungiCard]
        case .snake:
            if nm {
                return [Inspect.snakeNMCard, Inspect.biteCard]
            }
            if id.contains("diamondback") {
                return [Inspect.snakeTXCard, Inspect.biteCard]
            }
            if east || id.contains("copperhead") || id.contains("cottonmouth") {
                return [Inspect.snakeEastCard, Inspect.biteCard]
            }
            return [Inspect.snakeTXCard, Inspect.biteCard]
        case .mammal:
            if id.contains("javelina") {
                return [Inspect.mammalTXCard, Inspect.gameTXCard, Inspect.gameCard]
            }
            if id.contains("hog") {
                return [Inspect.mammalEastCard, Inspect.gameEastCard, Inspect.gameCard]
            }
            if nm {
                return [Inspect.mammalNMCard, Inspect.gameNMCard, Inspect.gameCard]
            }
            if east {
                return [Inspect.mammalEastCard, Inspect.gameEastCard, Inspect.gameCard]
            }
            return [Inspect.mammalTXCard, Inspect.gameTXCard, Inspect.gameCard]
        case .tree:
            if id.contains("mesquite") {
                return [Inspect.treeUseTXCard, Inspect.plantUseCard]
            }
            if id.contains("pine") || id.contains("loblolly") {
                return [Inspect.treeUseEastCard, Inspect.plantUseCard]
            }
            if nm {
                return [Inspect.treeUseNMCard, Inspect.plantUseCard]
            }
            return [
                east ? Inspect.treeUseEastCard : Inspect.treeUseTXCard,
                Inspect.plantUseCard,
            ]
        case .cactus:
            return [
                nm ? Inspect.cactusNMCard : Inspect.cactusTXCard,
                nm ? Inspect.plantNMCard : Inspect.plantTXCard,
            ]
        }
    }
}

public struct InspectFinding: Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    public var subject: InspectSubject
    public var title: String
    /// Absent on land: there is no record to be sure about.
    public var sure: Int?
    public var why: String
    public var doLine: String
    public var fieldCardID: String
    public var markLabel: String

    public var isWater: Bool {
        switch subject {
        case .water: return true
        case .land: return false
        }
    }
}

public enum MapInspect {
    /// How far past the press it is still worth naming the nearest water. Two
    /// kilometres is a walk you would plan; ten is a different day.
    public static let landReachMeters: Double = 2_000

    public static func resolve(
        lat: Double,
        lon: Double,
        zoom: Double,
        index: WaterIndex?
    ) -> InspectFinding {
        let radius = WaterZoom.pressRadiusMeters(zoom: zoom, latitude: lat)
        if let index, let hit = index.nearest(lat: lat, lon: lon, withinMeters: radius) {
            return water(hit, at: (lat, lon), radius: radius)
        }
        let nearby = index?.nearest(lat: lat, lon: lon, withinMeters: landReachMeters)
        return land(at: (lat, lon), radius: radius, nearest: nearby)
    }

    static func water(
        _ hit: WaterHit,
        at press: (lat: Double, lon: Double),
        radius: Double
    ) -> InspectFinding {
        let name = hit.record.name
        let title = name.isEmpty ? hit.record.kind.title : "\(hit.record.kind.title) · \(name)"
        return InspectFinding(
            lat: press.lat,
            lon: press.lon,
            subject: .water(hit),
            title: title,
            sure: WaterSure.percent(
                evidence: hit.record.evidence,
                distanceMeters: hit.distanceMeters,
                radiusMeters: radius
            ),
            why: why(hit),
            doLine: hit.record.kind.doLine,
            fieldCardID: InspectField.cardID(for: .water(hit)),
            markLabel: title
        )
    }

    static func land(
        at press: (lat: Double, lon: Double),
        radius: Double,
        nearest: WaterHit?
    ) -> InspectFinding {
        var why = "No water record within \(Int(radius.rounded())) m of this press."
        if let nearest {
            let name = nearest.record.name.isEmpty ? nearest.record.kind.title : nearest.record.name
            why += " Nearest is \(name), \(distance(nearest.distanceMeters)) "
            why += compass(from: press, to: (nearest.lat, nearest.lon)) + "."
        } else {
            why += " Nothing else within \(Int(landReachMeters / 1000)) km either."
        }
        return InspectFinding(
            lat: press.lat,
            lon: press.lon,
            subject: .land(nearest: nearest),
            title: "LAND",
            sure: nil,
            why: why,
            doLine: "Ground, not water. Fix where you are off what you can see before you walk.",
            fieldCardID: InspectField.cardID(for: .land(nearest: nearest)),
            markLabel: "LAND"
        )
    }

    static func why(_ hit: WaterHit) -> String {
        let tag = hit.record.tag
        switch hit.record.evidence {
        case .tagged:
            return "OpenStreetMap tags this \(tag)."
        case .named:
            let name = hit.record.name.isEmpty ? "its name" : "the name \(hit.record.name)"
            return "Tagged \(tag); \(name) says \(hit.record.kind.title.lowercased())."
        case .generic:
            return "Tagged \(tag), with nothing saying which kind."
        }
    }

    static func distance(_ metres: Double) -> String {
        metres >= 1000
            ? String(format: "%.1f km", metres / 1000)
            : "\(Int(metres.rounded())) m"
    }

    static func compass(from: (lat: Double, lon: Double), to: (lat: Double, lon: Double)) -> String {
        let dLat = to.lat - from.lat
        let dLon = (to.lon - from.lon) * cos(from.lat * .pi / 180)
        guard dLat != 0 || dLon != 0 else { return "here" }
        var degrees = atan2(dLon, dLat) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return points[Int((degrees / 45).rounded()) % 8]
    }
}

extension WaterClass {
    /// HUD `Inspect` titles, plus the classifier's own display titles.
    public static func fromHUDKlass(_ klass: String) -> WaterClass? {
        switch klass {
        case "Spring": return .spring
        case "Water tank", "STOCK TANK": return .tank
        case "Acequia or ditch", "ACEQUIA": return .acequia
        case "Drain", "DRAIN": return .drain
        case "PLAYA": return .playa
        case "TINAJA": return .tinaja
        case "Canal", "CANAL": return .canal
        case "Ditch", "DITCH": return .ditch
        case "Creek", "Wash or stream", "STREAM": return .stream
        case "River", "RIVER": return .river
        case "Reservoir or tank", "RESERVOIR": return .reservoir
        case "Water body", "WATER": return .water
        case "WETLAND": return .wetland
        case "Dam", "DAM": return .dam
        case "Tap", "TAP": return .tap
        default: return nil
        }
    }
}

extension Inspect {
    /// A wash under a road is the question. A canal 40 m off downtown is not.
    public static let streetWaterOverrideMeters = 15.0

    public static func fieldDoLine(
        klass: String,
        kind: Kind,
        advice: Advice,
        state: String? = nil,
        pack: String? = nil
    ) -> String? {
        switch kind {
        case .water:
            if advice == .leave { return nil }
            if let mapped = WaterClass.fromHUDKlass(klass) {
                return mapped.doLine
            }
            switch klass {
            case "Well":
                return "A well is a hole. If it draws, take it. Settle, filter cloth, boil."
            case "Cistern":
                return "Covered storage. Dip, settle, filter cloth, boil."
            case "Weir":
                return WaterClass.dam.doLine
            case "Channel":
                return WaterClass.water.doLine
            default:
                return WaterClass.water.doLine
            }
        case .land:
            return landDoLine(klass, state: state, pack: pack)
        case .street:
            if klass == "Track" {
                return "A ranch road is where the grate takes an ankle. Field has the card."
            }
            return "A way is mapped here. Field has stop-and-locate."
        case .place:
            return "A named place. Stop. Field has stop-and-locate."
        case .nothing:
            return "Nothing is mapped here. Stop and locate before you walk."
        }
    }

    /// The open pack, not a blended Texas. East and West share a Field book
    /// and a Vision book; the hold still names the country under the glass.
    private enum PackRange: Sendable {
        case txWest
        case txEast
        case nm
        case unknown

        static func of(state: String?, pack: String?) -> PackRange {
            switch (pack ?? "").lowercased() {
            case "tx-east":
                return .txEast
            case "tx-west":
                return .txWest
            case "nm":
                return .nm
            default:
                break
            }
            switch (state ?? "").uppercased() {
            case "NM":
                return .nm
            case "TX":
                return .txWest
            default:
                return .unknown
            }
        }
    }

    private static func treeRangeLine(state: String?, pack: String?) -> String {
        switch PackRange.of(state: state, pack: pack) {
        case .txWest:
            return "Live oak, pecan, mesquite, cedar elm. Javelina and coyote range. Shade and thorns, not a meal."
        case .txEast:
            return "Live oak, pecan, cedar elm, loblolly pine. Coyote and deer range. Hog country. Shade, not a meal."
        case .nm:
            return "Cottonwood, juniper, piñon. Black bear and elk range. Shade and wind, not a meal."
        case .unknown:
            return "Shade, wind, deadfall. Not a meal. Field has the plant and animal cards."
        }
    }

    private static func animalRangeLine(state: String?, pack: String?) -> String {
        switch PackRange.of(state: state, pack: pack) {
        case .txWest:
            return "Diamondback and javelina country. Yucca and prickly pear. Spines, not a meal."
        case .txEast:
            return "Copperhead and cottonmouth country. Yucca and prickly pear. Spines, not a meal."
        case .nm:
            return "Prairie rattler or diamondback country. Cholla and yucca. Spines, not a meal."
        case .unknown:
            return "Open country. Vipers use this cover. Field has the bite card."
        }
    }

    private static func landDoLine(_ klass: String, state: String?, pack: String?) -> String {
        switch klass {
        case "Woodland", "Named tree", "Tree", "Park", "Protected land", "Irrigated ground":
            return treeRangeLine(state: state, pack: pack)
        case "Glasshouse", "Botanic garden":
            return "Worked ground a ditch reaches. Pretty is not food. Field has the plant cards."
        case "Cactus garden":
            return "Cactus and yucca. Spines, not a meal. Pretty is not food."
        case "Wildlife range":
            switch PackRange.of(state: state, pack: pack) {
            case .txWest:
                return "Javelina, coyote, and deer range. This is range, not a pin."
            case .txEast:
                return "Coyote and deer range. Hog country. Not a pin."
            case .nm:
                return "Black bear, elk, and mule deer range. This is range, not a pin."
            case .unknown:
                return "This is range, not a pin. Field has the animal cards."
            }
        case "Bosque or wetland":
            switch PackRange.of(state: state, pack: pack) {
            case .txWest:
                return "Cottonwoods and pecan along the water. Javelina and coyote range. Shade, not a meal."
            case .txEast:
                return "Cottonwoods and pecan along the water. Cottonmouth country. Shade, not a meal."
            case .nm:
                return "Rio Grande cottonwood. Black bear range. Shade, not a meal."
            case .unknown:
                return "Cottonwoods and wet ground. Shade, not a meal. Field has the plant and animal cards."
            }
        case "Desert scrub", "Grassland", "Sand or playa floor", "Salt flat":
            return animalRangeLine(state: state, pack: pack)
        case "Cave or hole":
            return "A hole in the record. Dark, still air, cold. Do not go in alone."
        case "Peak":
            switch PackRange.of(state: state, pack: pack) {
            case .nm:
                return "High ground. Wind, cold, black bear range. Field has ice and cold."
            case .txWest:
                return "High ground. Wind, coyote and deer range. Field has animal and cold."
            case .txEast:
                return "High ground. Wind, coyote, deer, and hog range. Field has animal and cold."
            case .unknown:
                return "High ground. Wind and cold. Field has animal and cold."
            }
        case "Rock":
            switch PackRange.of(state: state, pack: pack) {
            case .nm:
                return "Bare rock. Ice films over. Black bear range. Field has ice and cold."
            case .txWest:
                return "Bare rock. Coyote and deer range. Field has animal and cold."
            case .txEast:
                return "Bare rock. Coyote, deer, and hog range. Field has animal and cold."
            case .unknown:
                return "Bare rock. No shade. Field has the cold card."
            }
        case "Built-up ground":
            return "Pavement and little shade. Field has the heat island card."
        default:
            return Advice.field.line
        }
    }

    /// Painted tags first (streets, tanks, land). The water index fills in
    /// what paint missed: a class, a mid-channel hit, or the nearest water.
    public static func resolve(
        tags: [String: String],
        lat: Double,
        lon: Double,
        zoom: Double,
        index: WaterIndex?,
        packDate: String? = nil,
        state: String? = nil,
        pack: String? = nil
    ) -> Card {
        let painted = read(tags: tags, packDate: packDate, state: state, pack: pack)
        let radius = WaterZoom.pressRadiusMeters(zoom: zoom, latitude: lat)
        let under = index?.nearest(lat: lat, lon: lon, withinMeters: radius)

        // A silent or fuel tank under the thumb is the answer. A drain that
        // also says leave still wants the class line from the index.
        if painted.kind == .water, painted.advice == .leave,
           painted.klass.lowercased().contains("tank") {
            return painted
        }
        if painted.kind == .street || painted.kind == .place {
            if let hit = under, hit.distanceMeters <= streetWaterOverrideMeters {
                return card(from: hit, press: (lat, lon), radius: radius, packDate: packDate)
            }
            return painted
        }
        if let hit = under {
            return card(from: hit, press: (lat, lon), radius: radius, packDate: packDate)
        }
        if painted.kind == .land || painted.kind == .nothing {
            let nearby = index?.nearest(lat: lat, lon: lon, withinMeters: MapInspect.landReachMeters)
            return pointing(at: painted, from: (lat, lon), nearest: nearby)
        }
        return painted
    }

    static func card(
        from hit: WaterHit,
        press: (lat: Double, lon: Double),
        radius: Double,
        packDate: String?
    ) -> Card {
        let finding = MapInspect.water(hit, at: press, radius: radius)
        let named = !hit.record.name.isEmpty
        return Card(
            title: named ? hit.record.name : unnamed,
            klass: hit.record.kind.title,
            kind: .water,
            sure: finding.sure ?? 55,
            why: finding.why,
            advice: hit.record.kind == .drain ? .leave : .treat,
            fieldCardID: waterCard,
            packDate: packDate,
            doDetail: hit.record.kind.doLine
        )
    }

    static func pointing(
        at painted: Card,
        from press: (lat: Double, lon: Double),
        nearest: WaterHit?
    ) -> Card {
        guard let nearest else { return painted }
        let name = nearest.record.name.isEmpty ? nearest.record.kind.title : nearest.record.name
        let extra = "Nearest water is \(name), \(MapInspect.distance(nearest.distanceMeters)) \(MapInspect.compass(from: press, to: (nearest.lat, nearest.lon)))."
        return Card(
            title: painted.title,
            klass: painted.klass,
            kind: painted.kind,
            sure: painted.sure,
            why: painted.why + " " + extra,
            advice: painted.advice,
            fieldCardID: painted.fieldCardID,
            localCardIDs: painted.localCardIDs,
            extraCoreIDs: painted.extraCoreIDs,
            packDate: painted.packDate,
            doDetail: painted.doDetail
        )
    }
}
