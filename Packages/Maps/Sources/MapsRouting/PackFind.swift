import Foundation

public enum PackFindMode: String, Sendable {
    case civilization
    case water
}

public enum PackFindAction: Equatable, Sendable {
    case route
    case lockOn
}

public enum PackFindCopy {
    public static let civilization = "Find civilization"
    public static let water = "Find water"
    public static let empty = NavigateCopy.searchMiss
    public static let subtitle = "Pack points only. No geocoder, no network."
}

/// On-device Find civilization / Find water. Pack `poi.json` only. No WAN, no geocoder.
public enum PackFind {
    public static func matches(kind: String, mode: PackFindMode) -> Bool {
        switch mode {
        case .civilization:
            let key = normalize(kind)
            if PackAmenityPolicy.amenityKinds.contains(key) { return true }
            switch key {
            case "road", "rail", "town", "mill", "city", "ranger":
                return true
            default:
                return false
            }
        case .water:
            switch normalize(kind) {
            case "spring", "tank", "water", "reservoir", "lake", "creek", "river", "pond":
                return true
            default:
                return false
            }
        }
    }

    public static func query(
        mode: PackFindMode,
        origin: RoutingCoordinate?,
        packBounds: RoutingBBox?,
        pois: [RoutingPOI],
        limit: Int = 12
    ) -> (hits: [PackSearchHit], empty: NavigateEmpty?) {
        if let origin, let packBounds, !packBounds.contains(origin) {
            return ([], empty(for: mode))
        }

        var ranked: [(hit: PackSearchHit, score: Double)] = []
        for poi in pois where matches(kind: poi.kind, mode: mode) {
            let meters = origin.map { Geo.haversine($0, poi.coordinate) }
            let score = Double(weight(kind: poi.kind, mode: mode)) * 100_000 - (meters ?? 0)
            ranked.append(
                (
                    PackSearchHit(
                        id: "poi:\(poi.id)",
                        title: poi.name,
                        kind: poi.kind,
                        coordinate: poi.coordinate,
                        meters: meters
                    ),
                    score
                )
            )
        }
        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.hit.title < rhs.hit.title
        }
        let hits = Array(ranked.prefix(limit).map(\.hit))
        if hits.isEmpty { return ([], empty(for: mode)) }
        return (hits, nil)
    }

    private static func empty(for mode: PackFindMode) -> NavigateEmpty {
        switch mode {
        case .civilization:
            return .noCivilization
        case .water:
            return .noWater
        }
    }

    public static func action(
        destination: RoutingCoordinate,
        origin: RoutingCoordinate?,
        pack: RoutingPack?,
        profile: NavigateProfile
    ) -> PackFindAction {
        guard let pack, let origin, pack.manifest.bbox.contains(destination) else {
            return .lockOn
        }
        if case .routed = PackRouter.route(from: origin, to: destination, profile: profile, pack: pack) {
            return .route
        }
        return .lockOn
    }

    private static func weight(kind: String, mode: PackFindMode) -> Int {
        let key = normalize(kind)
        switch mode {
        case .civilization:
            switch key {
            case "town", "city":
                return 100
            case "mill":
                return 80
            case "hospital", "clinic", "pharmacy", "police", "fire_station", "ranger":
                return 70
            case let key where PackAmenityPolicy.amenityKinds.contains(key):
                return 65
            case "rail":
                return 50
            case "road":
                return 40
            default:
                return 10
            }
        case .water:
            switch key {
            case "spring":
                return 100
            case "tank":
                return 80
            case "water", "reservoir", "lake", "creek", "river", "pond":
                return 60
            default:
                return 10
            }
        }
    }

    private static func normalize(_ kind: String) -> String {
        kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
