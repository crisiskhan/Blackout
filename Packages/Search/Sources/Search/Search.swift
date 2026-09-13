import Foundation
import Tokens

public struct SearchHit: Equatable, Hashable, Sendable {
    public var name: String
    public var kind: String
    public var lat: Double
    public var lon: Double
    public var score: Double
    public var meters: Double?
    public var city: String
    public var post: String
    public var what: String
    public var sure: Int
    public var why: String

    public init(
        name: String,
        kind: String,
        lat: Double,
        lon: Double,
        score: Double,
        meters: Double? = nil,
        city: String = "",
        post: String = "",
        what: String = "",
        sure: Int = 0,
        why: String = ""
    ) {
        self.name = name
        self.kind = kind
        self.lat = lat
        self.lon = lon
        self.score = score
        self.meters = meters
        self.city = city
        self.post = post
        self.what = what
        self.sure = sure
        self.why = why
    }
}

public struct AddrRange: Equatable, Sendable {
    public var street: Int
    public var from: Int
    public var to: Int
    public var zip: Int
    public var lat0: Double
    public var lon0: Double
    public var lat1: Double
    public var lon1: Double
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
    case address

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
        case .address: return "ADDRESS"
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
        case "address":
            return .address
        default:
            return .place
        }
    }
}

public struct SearchExtra: Sendable, Equatable {
    public var name: String
    public var kind: String
    public var lat: Double
    public var lon: Double

    public init(name: String, kind: String, lat: Double, lon: Double) {
        self.name = name
        self.kind = kind
        self.lat = lat
        self.lon = lon
    }
}

public struct SearchIndex: Sendable {
    private let docs: [Doc]
    private let foldedOrder: [Int]
    private let tokenIndex: [String: [Int]]
    private let kindIndex: [String: [Int]]
    private let tokenKeys: [String]
    private let addrStreets: [String]
    private let addrZips: [String]
    private let addrRanges: [AddrRange]
    private let rangesByStreet: [Int: [AddrRange]]
    private let streetTokenIndex: [String: [Int]]
    private let streetTokenKeys: [String]
    private let streetCenters: [(lat: Double, lon: Double)]
    private let streetFreq: [Int]
    private let streetCell: [Int64: [Int]]
    private let rangeCell: [Int64: [Int]]

    private static let nameCellDegrees = 0.01
    private static let nameReachMeters = 55.0
    private static let cellStride: Int64 = 100_000

    private struct Doc: Sendable {
        var name: String
        var kind: String
        var lat: Double
        var lon: Double
        var folded: String
        var tokens: [String]
    }

    public init(pois: [[String: Any]]) {
        self.init(docs: pois.compactMap(Self.doc(from:)))
    }

    public static func load(data: Data) -> SearchIndex {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            return SearchIndex(pois: [])
        }
        if let root = obj as? [String: Any] {
            if let rows = root["docs"] as? [Any] {
                let packed = Self.packedAddr(root["addr"])
                return SearchIndex(
                    docs: rows.compactMap(Self.doc(fromJSON:)),
                    addrStreets: packed.streets,
                    addrZips: packed.zips,
                    addrRanges: packed.ranges
                )
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
        BlackoutTokens.Distance.hud(meters)
    }

    /// Nearest packed street name. Nil when nothing named sits in reach —
    /// SPEAK must not invent a road.
    public func streetName(near lat: Double, lon: Double, withinMeters: Double = 55) -> String? {
        guard lat.isFinite, lon.isFinite else { return nil }
        let reach = min(withinMeters, Self.nameReachMeters)
        var best: (name: String, metres: Double)?
        let cy = Int64((lat / Self.nameCellDegrees).rounded(.down))
        let cx = Int64((lon / Self.nameCellDegrees).rounded(.down))
        for dy in Int64(-1)...1 {
            for dx in Int64(-1)...1 {
                let key = Self.nameCell(y: cy + dy, x: cx + dx)
                for i in streetCell[key] ?? [] {
                    let d = docs[i]
                    let metres = haversine(lat, lon, d.lat, d.lon)
                    if metres <= reach, best == nil || metres < best!.metres {
                        best = (d.name, metres)
                    }
                }
                for i in rangeCell[key] ?? [] {
                    let range = addrRanges[i]
                    guard addrStreets.indices.contains(range.street) else { continue }
                    let metres = metresToSegment(
                        lat: lat,
                        lon: lon,
                        aLat: range.lat0,
                        aLon: range.lon0,
                        bLat: range.lat1,
                        bLon: range.lon1
                    )
                    if metres <= reach, best == nil || metres < best!.metres {
                        best = (addrStreets[range.street], metres)
                    }
                }
            }
        }
        let name = best?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    /// One name per route segment, mid-point lookup. Missing names stay nil.
    public func streetNames(along: [(lat: Double, lon: Double)]) -> [String?] {
        guard along.count >= 2 else { return [] }
        return zip(along, along.dropFirst()).map { a, b in
            streetName(near: (a.lat + b.lat) / 2, lon: (a.lon + b.lon) / 2)
        }
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
        extra: [SearchExtra] = [],
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
        if let house = Self.houseQuery(trimmed) {
            var hits: [SearchHit] = []
            considerAddresses(
                hn: house.0,
                streetTokens: house.1,
                you: you,
                into: &hits,
                cap: cap
            )
            let rest = house.1.joined(separator: " ")
            let restFolded = Self.fold(rest)
            for i in candidateIndices(foldedQuery: restFolded, qTokens: house.1) {
                consider(
                    docs[i],
                    foldedQuery: restFolded,
                    qTokens: house.1,
                    you: you,
                    into: &hits,
                    cap: cap
                )
            }
            for row in extra {
                consider(
                    Self.makeDoc(name: row.name, kind: row.kind, lat: row.lat, lon: row.lon),
                    foldedQuery: restFolded,
                    qTokens: house.1,
                    you: you,
                    into: &hits,
                    cap: cap
                )
            }
            return hits
        }
        let foldedQuery = Self.fold(trimmed)
        let qTokens = Self.tokens(trimmed)
        var hits: [SearchHit] = []
        for i in candidateIndices(foldedQuery: foldedQuery, qTokens: qTokens) {
            consider(
                docs[i],
                foldedQuery: foldedQuery,
                qTokens: qTokens,
                you: you,
                into: &hits,
                cap: cap
            )
        }
        for row in extra {
            consider(
                Self.makeDoc(name: row.name, kind: row.kind, lat: row.lat, lon: row.lon),
                foldedQuery: foldedQuery,
                qTokens: qTokens,
                you: you,
                into: &hits,
                cap: cap
            )
        }
        return hits
    }

    private init(
        docs: [Doc],
        addrStreets: [String] = [],
        addrZips: [String] = [],
        addrRanges: [AddrRange] = []
    ) {
        self.docs = docs
        self.addrStreets = addrStreets
        self.addrZips = addrZips
        self.addrRanges = addrRanges
        var order = Array(docs.indices)
        order.sort { docs[$0].folded < docs[$1].folded }
        foldedOrder = order
        var tokens: [String: [Int]] = [:]
        var kinds: [String: [Int]] = [:]
        for (i, d) in docs.enumerated() {
            var seen = Set<String>()
            for t in d.tokens where seen.insert(t).inserted {
                tokens[t, default: []].append(i)
            }
            let kind = d.kind.lowercased()
            if !kind.isEmpty {
                kinds[kind, default: []].append(i)
            }
        }
        tokenIndex = tokens
        kindIndex = kinds
        tokenKeys = tokens.keys.sorted()
        var streetTokens: [String: [Int]] = [:]
        for (i, street) in addrStreets.enumerated() {
            var seen = Set<String>()
            for t in Self.tokens(street) {
                for alias in Self.aliases(of: t) where seen.insert(alias).inserted {
                    streetTokens[alias, default: []].append(i)
                }
            }
        }
        streetTokenIndex = streetTokens
        streetTokenKeys = streetTokens.keys.sorted()
        var latSum = Array(repeating: 0.0, count: addrStreets.count)
        var lonSum = Array(repeating: 0.0, count: addrStreets.count)
        var counts = Array(repeating: 0, count: addrStreets.count)
        var buckets: [Int: [AddrRange]] = [:]
        for range in addrRanges {
            guard range.street >= 0, range.street < addrStreets.count else { continue }
            latSum[range.street] += (range.lat0 + range.lat1) / 2
            lonSum[range.street] += (range.lon0 + range.lon1) / 2
            counts[range.street] += 1
            buckets[range.street, default: []].append(range)
        }
        rangesByStreet = buckets
        var centers: [(lat: Double, lon: Double)] = []
        centers.reserveCapacity(addrStreets.count)
        for i in addrStreets.indices {
            let n = Double(max(1, counts[i]))
            centers.append((latSum[i] / n, lonSum[i] / n))
        }
        streetCenters = centers
        streetFreq = counts
        var streetCell: [Int64: [Int]] = [:]
        for (i, d) in docs.enumerated() where SearchHUDWord.from(packed: d.kind) == .street {
            streetCell[Self.nameCell(lat: d.lat, lon: d.lon), default: []].append(i)
        }
        self.streetCell = streetCell
        var rangeCell: [Int64: [Int]] = [:]
        for (i, range) in addrRanges.enumerated() {
            let lat = (range.lat0 + range.lat1) / 2
            let lon = (range.lon0 + range.lon1) / 2
            rangeCell[Self.nameCell(lat: lat, lon: lon), default: []].append(i)
        }
        self.rangeCell = rangeCell
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
        case "n", "north":
            return ["n", "north"]
        case "s", "south":
            return ["s", "south"]
        case "e", "east":
            return ["e", "east"]
        case "w", "west":
            return ["w", "west"]
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

    private func candidateIndices(foldedQuery: String, qTokens: [String]) -> [Int] {
        var found = Set<Int>()
        if !foldedQuery.isEmpty {
            found.formUnion(foldedPrefixHits(foldedQuery))
        }
        for q in qTokens {
            for alias in Self.aliases(of: q) {
                if let ids = tokenIndex[alias] {
                    found.formUnion(ids)
                }
            }
            if q.count >= 3 {
                for key in tokensPrefixed(by: q) {
                    if let ids = tokenIndex[key] {
                        found.formUnion(ids)
                    }
                }
            }
            if (4...16).contains(q.count) {
                for edit in Self.editsOne(q) {
                    if let ids = tokenIndex[edit] {
                        found.formUnion(ids)
                    }
                }
            }
        }
        for kind in Self.expand(qTokens) {
            if let ids = kindIndex[kind] {
                found.formUnion(ids)
            }
        }
        if found.isEmpty, foldedQuery.count >= 3 {
            for (i, d) in docs.enumerated() where d.folded.contains(foldedQuery) {
                found.insert(i)
            }
        }
        return Array(found)
    }

    private func foldedPrefixHits(_ prefix: String) -> [Int] {
        var lo = 0
        var hi = foldedOrder.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if docs[foldedOrder[mid]].folded < prefix {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        var out: [Int] = []
        var i = lo
        while i < foldedOrder.count {
            let idx = foldedOrder[i]
            if docs[idx].folded.hasPrefix(prefix) {
                out.append(idx)
                i += 1
            } else {
                break
            }
        }
        return out
    }

    private func tokensPrefixed(by prefix: String) -> [String] {
        var lo = 0
        var hi = tokenKeys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if tokenKeys[mid] < prefix {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        var out: [String] = []
        var i = lo
        while i < tokenKeys.count {
            let key = tokenKeys[i]
            if key.hasPrefix(prefix) {
                out.append(key)
                i += 1
            } else {
                break
            }
        }
        return out
    }

    private static func editsOne(_ word: String) -> [String] {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let chars = Array(word)
        var out: [String] = []
        out.reserveCapacity(chars.count * 28)
        for i in chars.indices {
            var copy = chars
            copy.remove(at: i)
            out.append(String(copy))
        }
        if chars.count >= 2 {
            for i in 0..<(chars.count - 1) {
                var copy = chars
                copy.swapAt(i, i + 1)
                out.append(String(copy))
            }
        }
        for i in chars.indices {
            for letter in letters where letter != chars[i] {
                var copy = chars
                copy[i] = letter
                out.append(String(copy))
            }
        }
        for i in 0...chars.count {
            for letter in letters {
                var copy = chars
                copy.insert(letter, at: i)
                out.append(String(copy))
            }
        }
        return out
    }

    private func consider(
        _ doc: Doc,
        foldedQuery: String,
        qTokens: [String],
        you: (lat: Double, lon: Double)?,
        into hits: inout [SearchHit],
        cap: Int
    ) {
        guard cap > 0, let score = matchScore(foldedQuery: foldedQuery, qTokens: qTokens, doc: doc) else {
            return
        }
        let hit = SearchHit(
            name: doc.name,
            kind: doc.kind,
            lat: doc.lat,
            lon: doc.lon,
            score: score,
            meters: you.map { haversine($0.lat, $0.lon, doc.lat, doc.lon) }
        )
        if hits.count < cap {
            hits.append(hit)
            hits.sort(by: Self.better)
            return
        }
        if Self.better(hit, hits[hits.count - 1]) {
            hits[hits.count - 1] = hit
            hits.sort(by: Self.better)
        }
    }

    private static func better(_ a: SearchHit, _ b: SearchHit) -> Bool {
        if a.score != b.score { return a.score > b.score }
        let am = a.meters ?? .greatestFiniteMagnitude
        let bm = b.meters ?? .greatestFiniteMagnitude
        if am != bm { return am < bm }
        return a.name < b.name
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

    public static func houseQuery(_ raw: String) -> (Int, [String])? {
        let toks = tokens(raw)
        guard let first = toks.first else { return nil }
        var i = first.startIndex
        while i < first.endIndex, first[i].isNumber {
            i = first.index(after: i)
        }
        let digitPart = String(first[..<i])
        guard !digitPart.isEmpty, let hn = Int(digitPart) else { return nil }
        let rest = String(first[i...])
        switch rest {
        case "th", "st", "nd", "rd":
            return nil
        default:
            break
        }
        if !rest.isEmpty, rest.contains(where: { !$0.isLetter }) {
            return nil
        }
        let street = Array(toks.dropFirst())
        guard !street.isEmpty else { return nil }
        return (hn, street)
    }

    private static func packedAddr(_ any: Any?) -> (streets: [String], zips: [String], ranges: [AddrRange]) {
        guard let obj = any as? [String: Any] else { return ([], [], []) }
        let streets = (obj["streets"] as? [String]) ?? []
        let zips = (obj["zips"] as? [String]) ?? []
        var ranges: [AddrRange] = []
        for row in (obj["ranges"] as? [Any]) ?? [] {
            guard let vals = row as? [Any], vals.count >= 8,
                  let street = intNumber(vals[0]),
                  let from = intNumber(vals[1]),
                  let to = intNumber(vals[2]),
                  let zip = intNumber(vals[3])
            else { continue }
            ranges.append(
                AddrRange(
                    street: street,
                    from: from,
                    to: to,
                    zip: zip,
                    lat0: coord(vals[4]),
                    lon0: coord(vals[5]),
                    lat1: coord(vals[6]),
                    lon1: coord(vals[7])
                )
            )
        }
        return (streets, zips, ranges)
    }

    private static func intNumber(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private static func coord(_ any: Any?) -> Double {
        let value = number(any) ?? 0
        if abs(value) > 1000 { return value / 100_000 }
        return value
    }

    private static func hnOnRange(_ hn: Int, _ from: Int, _ to: Int) -> Bool {
        let lo = min(from, to)
        let hi = max(from, to)
        if hn < lo || hn > hi { return false }
        if from % 2 == to % 2 {
            return hn % 2 == from % 2
        }
        return true
    }

    private static func interpolate(
        _ hn: Int,
        _ from: Int,
        _ to: Int,
        _ lat0: Double,
        _ lon0: Double,
        _ lat1: Double,
        _ lon1: Double
    ) -> (Double, Double) {
        let span = to - from
        if span == 0 { return (lat0, lon0) }
        let frac = Double(hn - from) / Double(span)
        return (lat0 + frac * (lat1 - lat0), lon0 + frac * (lon1 - lon0))
    }

    private static func cityForZip(_ zip: String) -> String {
        let digits = zip.filter(\.isNumber)
        guard digits.count >= 3 else { return "" }
        switch String(digits.prefix(3)) {
        case "765": return "Temple"
        case "786", "787": return "Austin"
        case "789": return "Giddings"
        case "798": return "Sierra Blanca"
        case "799": return "El Paso"
        case "870": return "Bernalillo"
        case "871": return "Albuquerque"
        case "873": return "Gallup"
        case "875": return "Santa Fe"
        case "877": return "Las Vegas"
        case "878": return "Socorro"
        case "879": return "Truth or Consequences"
        case "880": return "Las Cruces"
        case "881": return "Clovis"
        case "883": return "Alamogordo"
        default:
            return ""
        }
    }

    private static let typeTokens: Set<String> = [
        "ave", "avenue", "av", "avenida",
        "st", "street",
        "rd", "road",
        "blvd", "boulevard",
        "dr", "drive",
        "ln", "lane",
        "hwy", "highway",
        "pkwy", "parkway",
        "ct", "court",
        "cir", "circle",
        "pl", "place",
        "n", "north", "s", "south", "e", "east", "w", "west",
    ]

    private static func contentPenalty(street: String, query: [String]) -> Int {
        var leftover = 0
        for tok in tokens(street) {
            if typeTokens.contains(tok) { continue }
            if query.contains(where: { exactOrAlias($0, in: [tok]) || tokenHits($0, in: [tok]) }) {
                continue
            }
            leftover += 1
        }
        return leftover
    }

    private func considerAddresses(
        hn: Int,
        streetTokens: [String],
        you: (lat: Double, lon: Double)?,
        into hits: inout [SearchHit],
        cap: Int
    ) {
        guard streetTokens.contains(where: { !Self.typeTokens.contains($0) }) else { return }
        let streets = matchingStreets(streetTokens)
        guard !streets.isEmpty, cap > 0 else { return }
        let liveYou: (lat: Double, lon: Double)?
        if let you, you.lat.isFinite, you.lon.isFinite {
            liveYou = you
        } else {
            liveYou = nil
        }
        var found: [(hit: SearchHit, penalty: Int, freq: Int, centerMeters: Double, span: Int)] = []
        for streetId in streets {
            guard let bucket = rangesByStreet[streetId],
                  streetId >= 0, streetId < addrStreets.count
            else { continue }
            var best: (hit: SearchHit, penalty: Int, freq: Int, centerMeters: Double, span: Int)?
            for range in bucket {
                guard Self.hnOnRange(hn, range.from, range.to) else { continue }
                let (lat, lon) = Self.interpolate(
                    hn,
                    range.from,
                    range.to,
                    range.lat0,
                    range.lon0,
                    range.lat1,
                    range.lon1
                )
                guard lat.isFinite, lon.isFinite else { continue }
                let street = addrStreets[streetId]
                let zip = (range.zip >= 0 && range.zip < addrZips.count) ? addrZips[range.zip] : ""
                let penalty = Self.contentPenalty(street: street, query: streetTokens)
                let center: (lat: Double, lon: Double)
                if streetCenters.indices.contains(streetId) {
                    center = streetCenters[streetId]
                } else {
                    center = (lat: lat, lon: lon)
                }
                let youMeters = liveYou.map { haversine($0.lat, $0.lon, lat, lon) }
                let hit = SearchHit(
                    name: "\(hn) \(street)",
                    kind: "address",
                    lat: lat,
                    lon: lon,
                    score: 95 - Double(penalty),
                    meters: youMeters,
                    city: Self.cityForZip(zip),
                    post: zip,
                    what: "door on \(street)",
                    sure: 72,
                    why: "census range \(range.from)–\(range.to)"
                )
                let span = abs(range.to - range.from)
                let item = (
                    hit,
                    penalty,
                    streetFreq.indices.contains(streetId) ? streetFreq[streetId] : 0,
                    haversine(center.lat, center.lon, lat, lon),
                    span
                )
                if let current = best {
                    if span < current.span || (span == current.span && hit.name < current.hit.name) {
                        best = item
                    }
                } else {
                    best = item
                }
            }
            if let best {
                found.append(best)
            }
        }
        if liveYou != nil {
            found.sort { a, b in
                let am = a.hit.meters ?? .greatestFiniteMagnitude
                let bm = b.hit.meters ?? .greatestFiniteMagnitude
                if am != bm { return am < bm }
                if a.penalty != b.penalty { return a.penalty < b.penalty }
                return a.hit.name < b.hit.name
            }
        } else {
            found.sort { a, b in
                if a.penalty != b.penalty { return a.penalty < b.penalty }
                if a.freq != b.freq { return a.freq > b.freq }
                if a.centerMeters != b.centerMeters { return a.centerMeters < b.centerMeters }
                return a.hit.name < b.hit.name
            }
        }
        for item in found.prefix(cap) {
            hits.append(item.hit)
        }
        hits.sort(by: Self.better)
    }

    private func matchingStreets(_ qTokens: [String]) -> Set<Int> {
        var result: Set<Int>?
        for q in qTokens {
            var found = Set<Int>()
            for alias in Self.aliases(of: q) {
                if let ids = streetTokenIndex[alias] {
                    found.formUnion(ids)
                }
            }
            if q.count >= 3 {
                for key in streetTokensPrefixed(by: q) {
                    if let ids = streetTokenIndex[key] {
                        found.formUnion(ids)
                    }
                }
            }
            if let current = result {
                result = current.intersection(found)
            } else {
                result = found
            }
            if result?.isEmpty == true {
                return []
            }
        }
        return result ?? []
    }

    private func streetTokensPrefixed(by prefix: String) -> [String] {
        var lo = 0
        var hi = streetTokenKeys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if streetTokenKeys[mid] < prefix {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        var out: [String] = []
        var i = lo
        while i < streetTokenKeys.count {
            let key = streetTokenKeys[i]
            if key.hasPrefix(prefix) {
                out.append(key)
                i += 1
            } else {
                break
            }
        }
        return out
    }

    private func haversine(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        guard aLat.isFinite, aLon.isFinite, bLat.isFinite, bLon.isFinite else {
            return .greatestFiniteMagnitude
        }
        let r = 6_371_000.0
        let p1 = aLat * .pi / 180
        let p2 = bLat * .pi / 180
        let dp = (bLat - aLat) * .pi / 180
        let dl = (bLon - aLon) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2)
            + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        let clamped = max(0, min(1, h))
        return 2 * r * asin(sqrt(clamped))
    }

    private func metresToSegment(
        lat: Double,
        lon: Double,
        aLat: Double,
        aLon: Double,
        bLat: Double,
        bLon: Double
    ) -> Double {
        let metresLon = 111_320.0 * cos(lat * .pi / 180)
        let ax = (aLon - lon) * metresLon
        let ay = (aLat - lat) * 110_540.0
        let bx = (bLon - lon) * metresLon
        let by = (bLat - lat) * 110_540.0
        let dx = bx - ax
        let dy = by - ay
        let len2 = dx * dx + dy * dy
        if len2 < 1 {
            return haversine(lat, lon, aLat, aLon)
        }
        var t = (-ax * dx - ay * dy) / len2
        t = min(1, max(0, t))
        let px = ax + t * dx
        let py = ay + t * dy
        return (px * px + py * py).squareRoot()
    }

    private static func nameCell(lat: Double, lon: Double) -> Int64 {
        nameCell(
            y: Int64((lat / nameCellDegrees).rounded(.down)),
            x: Int64((lon / nameCellDegrees).rounded(.down))
        )
    }

    private static func nameCell(y: Int64, x: Int64) -> Int64 {
        y &* cellStride &+ x
    }
}
