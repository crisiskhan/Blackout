import Foundation

public struct SearchHit: Equatable, Hashable, Sendable {
    public var name: String
    public var kind: String
    public var lat: Double
    public var lon: Double
    public var score: Double
    public var meters: Double?

    public init(
        name: String,
        kind: String,
        lat: Double,
        lon: Double,
        score: Double,
        meters: Double? = nil
    ) {
        self.name = name
        self.kind = kind
        self.lat = lat
        self.lon = lon
        self.score = score
        self.meters = meters
    }
}

public enum SearchHUDWord: Sendable {
    case water
    case peak
    case street
    case hospital
    case clinic
    case care
    case pharmacy
    case fire
    case shelter
    case police
    case cave
    case tree
    case place
    case coordinates
    case mark

    public var title: String {
        switch self {
        case .water: return "WATER"
        case .peak: return "PEAK"
        case .street: return "STREET"
        case .hospital: return "HOSPITAL"
        case .clinic: return "CLINIC"
        case .care: return "CARE"
        case .pharmacy: return "PHARMACY"
        case .fire: return "FIRE"
        case .shelter: return "SHELTER"
        case .police: return "POLICE"
        case .cave: return "CAVE"
        case .tree: return "TREE"
        case .place: return "PLACE"
        case .coordinates: return "COORDINATES"
        case .mark: return "MARK"
        }
    }

    public static func from(packed: String) -> SearchHUDWord {
        switch packed {
        case "drinking_water", "water", "spring", "canal", "stream", "river", "tank":
            return .water
        case "peak", "summit":
            return .peak
        case "street", "residential", "primary", "secondary", "tertiary",
             "motorway", "trunk", "unclassified", "service", "track", "path",
             "footway", "cycleway", "living_street", "pedestrian", "road":
            return .street
        case "hospital":
            return .hospital
        case "clinic":
            return .clinic
        case "doctors":
            return .care
        case "pharmacy":
            return .pharmacy
        case "fire_station":
            return .fire
        case "shelter", "ranger":
            return .shelter
        case "police":
            return .police
        case "cave_entrance":
            return .cave
        case "tree":
            return .tree
        case "coordinates":
            return .coordinates
        case "mark":
            return .mark
        default:
            return .place
        }
    }
}

public struct SearchIndex: Sendable {
    private let docs: [Doc]

    private struct Doc: Sendable {
        var name: String
        var kind: String
        var lat: Double
        var lon: Double
        var folded: String
        var tokens: [String]
    }

    public init(pois: [[String: Any]]) {
        docs = pois.compactMap(Self.doc(from:))
    }

    public static func load(data: Data) -> SearchIndex {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            return SearchIndex(pois: [])
        }
        if let root = obj as? [String: Any] {
            if let rows = root["docs"] as? [Any] {
                return SearchIndex(docs: rows.compactMap(Self.doc(fromJSON:)))
            }
            if let feats = root["features"] as? [[String: Any]] {
                return SearchIndex(pois: feats.compactMap(Self.poi(fromFeature:)))
            }
        }
        if let rows = obj as? [Any] {
            return SearchIndex(docs: rows.compactMap(Self.doc(fromJSON:)))
        }
        return SearchIndex(pois: [])
    }

    public static func asking(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func coordinates(in query: String) -> (lat: Double, lon: Double)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { String($0) }
            .filter { !$0.isEmpty }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]),
              lat >= -90, lat <= 90,
              lon >= -180, lon <= 180
        else { return nil }
        return (lat, lon)
    }

    public static func rangeLabel(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f M", meters)
        }
        return String(format: "%.1f KM", meters / 1000)
    }

    public func fts(_ query: String) -> [SearchHit] {
        lookup(query, cap: 50)
    }

    public func semantic(_ intent: String) -> [SearchHit] {
        let kinds = Self.expand([Self.fold(intent)])
        return docs.filter { kinds.contains($0.kind.lowercased()) }.map {
            SearchHit(name: $0.name, kind: $0.kind, lat: $0.lat, lon: $0.lon, score: 1)
        }
    }

    public func lookup(
        _ query: String,
        you: (lat: Double, lon: Double)? = nil,
        extra: [[String: Any]] = [],
        cap: Int = 5
    ) -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.asking(trimmed) else { return [] }
        if let coord = Self.coordinates(in: trimmed) {
            let meters = you.map { haversine($0.lat, $0.lon, coord.lat, coord.lon) }
            return [
                SearchHit(
                    name: String(format: "%.5f, %.5f", coord.lat, coord.lon),
                    kind: "coordinates",
                    lat: coord.lat,
                    lon: coord.lon,
                    score: 100,
                    meters: meters
                )
            ]
        }
        let pool = extra.isEmpty ? docs : docs + extra.compactMap(Self.doc(from:))
        let foldedQuery = Self.fold(trimmed)
        let qTokens = Self.tokens(trimmed)
        var hits: [SearchHit] = []
        hits.reserveCapacity(min(64, pool.count))
        for d in pool {
            guard let score = matchScore(foldedQuery: foldedQuery, qTokens: qTokens, doc: d) else {
                continue
            }
            let meters = you.map { haversine($0.lat, $0.lon, d.lat, d.lon) }
            hits.append(
                SearchHit(
                    name: d.name,
                    kind: d.kind,
                    lat: d.lat,
                    lon: d.lon,
                    score: score,
                    meters: meters
                )
            )
        }
        hits.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            let am = a.meters ?? .greatestFiniteMagnitude
            let bm = b.meters ?? .greatestFiniteMagnitude
            if am != bm { return am < bm }
            return a.name < b.name
        }
        if hits.count > cap {
            hits = Array(hits.prefix(cap))
        }
        return hits
    }

    private init(docs: [Doc]) {
        self.docs = docs
    }

    private static func poi(fromFeature f: [String: Any]) -> [String: Any]? {
        guard let props = f["properties"] as? [String: Any],
              let geom = f["geometry"] as? [String: Any],
              let coords = geom["coordinates"] as? [Double], coords.count >= 2
        else { return nil }
        let name = (props["name"] as? String)
            ?? (props["amenity"] as? String)
            ?? "poi"
        let kind = (props["amenity"] as? String)
            ?? (props["natural"] as? String)
            ?? (props["highway"] as? String)
            ?? "poi"
        return ["name": name, "kind": kind, "lat": coords[1], "lon": coords[0]]
    }

    private static func doc(from poi: [String: Any]) -> Doc? {
        let name = (poi["name"] as? String) ?? ""
        guard !name.isEmpty else { return nil }
        let kind = (poi["kind"] as? String) ?? (poi["amenity"] as? String) ?? ""
        let lat = number(poi["lat"]) ?? 0
        let lon = number(poi["lon"]) ?? 0
        return makeDoc(name: name, kind: kind, lat: lat, lon: lon)
    }

    private static func doc(fromJSON item: Any) -> Doc? {
        if let row = item as? [Any], row.count >= 4,
           let name = row[0] as? String,
           let kind = row[1] as? String,
           let lat = number(row[2]),
           let lon = number(row[3])
        {
            return makeDoc(name: name, kind: kind, lat: lat, lon: lon)
        }
        if let poi = item as? [String: Any] {
            return doc(from: poi)
        }
        return nil
    }

    private static func makeDoc(name: String, kind: String, lat: Double, lon: Double) -> Doc {
        let folded = fold(name)
        var toks = tokens(name)
        toks.append(contentsOf: tokens(kind))
        return Doc(name: name, kind: kind, lat: lat, lon: lon, folded: folded, tokens: toks)
    }

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func fold(_ s: String) -> String {
        s.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func tokens(_ s: String) -> [String] {
        let folded = fold(s)
        var words: [String] = []
        var current = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func expand(_ qTokens: [String]) -> Set<String> {
        var out = Set(qTokens)
        for word in qTokens {
            switch word {
            case "hospital":
                out.formUnion(["hospital", "clinic", "doctors"])
            case "water":
                out.formUnion(["drinking_water", "water", "spring", "canal", "stream", "river"])
            case "shelter":
                out.formUnion(["shelter", "ranger"])
            case "peak", "summit", "mtn", "mount", "mountain":
                out.formUnion(["peak", "summit"])
            default:
                break
            }
        }
        return out
    }

    private static func aliases(of token: String) -> Set<String> {
        switch token {
        case "ave", "avenue", "av":
            return ["ave", "avenue", "av", "avenida"]
        case "avenida":
            return ["avenida", "av", "ave", "avenue"]
        case "st", "street":
            return ["st", "street"]
        case "rd", "road":
            return ["rd", "road"]
        case "blvd", "boulevard":
            return ["blvd", "boulevard"]
        case "dr", "drive":
            return ["dr", "drive"]
        case "ln", "lane":
            return ["ln", "lane"]
        case "hwy", "highway":
            return ["hwy", "highway"]
        case "pkwy", "parkway":
            return ["pkwy", "parkway"]
        case "ct", "court":
            return ["ct", "court"]
        case "cir", "circle":
            return ["cir", "circle"]
        case "pl", "place":
            return ["pl", "place"]
        case "mt", "mtn", "mount", "mountain":
            return ["mt", "mtn", "mount", "mountain"]
        case "pk", "peak", "summit":
            return ["pk", "peak", "summit"]
        default:
            return [token]
        }
    }

    private static func exactOrAlias(_ q: String, in docTokens: [String]) -> Bool {
        let want = aliases(of: q)
        for d in docTokens where want.contains(d) {
            return true
        }
        return false
    }

    private static func tokenHits(_ q: String, in docTokens: [String]) -> Bool {
        if exactOrAlias(q, in: docTokens) { return true }
        if q.count >= 3 {
            for d in docTokens where d.hasPrefix(q) {
                return true
            }
        }
        if q.count >= 4 {
            for d in docTokens where editDistanceOne(q, d) {
                return true
            }
        }
        return false
    }

    private static func editDistanceOne(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let ac = Array(a)
        let bc = Array(b)
        if abs(ac.count - bc.count) > 1 { return false }
        if ac.count == bc.count {
            var i = 0
            var diffs = 0
            while i < ac.count {
                if ac[i] == bc[i] {
                    i += 1
                    continue
                }
                if i + 1 < ac.count, ac[i] == bc[i + 1], ac[i + 1] == bc[i] {
                    diffs += 1
                    if diffs > 1 { return false }
                    i += 2
                    continue
                }
                diffs += 1
                if diffs > 1 { return false }
                i += 1
            }
            return diffs == 1
        }
        let longer = ac.count > bc.count ? ac : bc
        let shorter = ac.count > bc.count ? bc : ac
        var i = 0
        var j = 0
        var skipped = false
        while i < longer.count && j < shorter.count {
            if longer[i] == shorter[j] {
                i += 1
                j += 1
            } else if !skipped {
                skipped = true
                i += 1
            } else {
                return false
            }
        }
        return true
    }

    private func matchScore(foldedQuery: String, qTokens: [String], doc: Doc) -> Double? {
        if doc.folded == foldedQuery { return 100 }
        if !foldedQuery.isEmpty, doc.folded.hasPrefix(foldedQuery) {
            return 90
        }
        if !qTokens.isEmpty, qTokens.allSatisfy({ Self.exactOrAlias($0, in: doc.tokens) }) {
            return 80
        }
        if !qTokens.isEmpty, qTokens.allSatisfy({ Self.tokenHits($0, in: doc.tokens) }) {
            return 50 + Double(qTokens.map(\.count).max() ?? 0)
        }
        if foldedQuery.count >= 3, doc.folded.contains(foldedQuery) {
            return 40
        }
        let expanded = Self.expand(qTokens)
        if expanded.contains(doc.kind.lowercased()) {
            return 15
        }
        return nil
    }

    private func haversine(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let r = 6_371_000.0
        let p1 = aLat * .pi / 180
        let p2 = bLat * .pi / 180
        let dp = (bLat - aLat) * .pi / 180
        let dl = (bLon - aLon) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2)
            + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}
