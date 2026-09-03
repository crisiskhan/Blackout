import Foundation

public struct SearchHit: Equatable, Sendable {
    public var name: String
    public var kind: String
    public var lat: Double
    public var lon: Double
    public var score: Double

    public init(name: String, kind: String, lat: Double, lon: Double, score: Double) {
        self.name = name
        self.kind = kind
        self.lat = lat
        self.lon = lon
        self.score = score
    }
}

public struct SearchIndex: Sendable {
    private let docs: [(name: String, kind: String, lat: Double, lon: Double, tokens: Set<String>)]

    public init(pois: [[String: Any]]) {
        docs = pois.map { p in
            let name = (p["name"] as? String) ?? ""
            let kind = (p["kind"] as? String) ?? (p["amenity"] as? String) ?? ""
            let lat = p["lat"] as? Double ?? 0
            let lon = p["lon"] as? Double ?? 0
            let tokens = Set((name + " " + kind).lowercased().split(separator: " ").map(String.init))
            return (name, kind, lat, lon, tokens)
        }
    }

    public func fts(_ query: String) -> [SearchHit] {
        let q = Set(query.lowercased().split(separator: " ").map(String.init))
        return docs.compactMap { d in
            let overlap = Double(q.intersection(d.tokens).count)
            guard overlap > 0 else { return nil }
            return SearchHit(name: d.name, kind: d.kind, lat: d.lat, lon: d.lon, score: overlap)
        }.sorted { $0.score > $1.score }
    }

    public func semantic(_ intent: String) -> [SearchHit] {
        let map: [String: [String]] = [
            "hospital": ["hospital", "clinic", "doctors"],
            "water": ["drinking_water", "water", "spring"],
            "shelter": ["shelter", "ranger"],
            "peak": ["peak", "summit"],
        ]
        let kinds = map[intent.lowercased()] ?? [intent.lowercased()]
        return docs.filter { kinds.contains($0.kind.lowercased()) }.map {
            SearchHit(name: $0.name, kind: $0.kind, lat: $0.lat, lon: $0.lon, score: 1)
        }
    }
}
