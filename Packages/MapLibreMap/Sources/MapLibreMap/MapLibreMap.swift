import Foundation
import PackIO
import Search
import Router
import DeadReckoning
import Almanac
import BlackBox

public struct MapMark: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var lat: Double
    public var lon: Double
    public var label: String
    public init(id: String, lat: Double, lon: Double, label: String) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.label = label
    }
}

public enum MarkStore {
    public static let key = "map.marks"

    public static func save(_ marks: [MapMark], defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(marks), forKey: key)
    }

    public static func load(defaults: UserDefaults = .standard) -> [MapMark] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MapMark].self, from: data)) ?? []
    }
}

public enum LockOnChrome {
    public static func banner(hasGPS: Bool, hasGraph: Bool) -> String {
        if hasGPS || hasGraph { return "" }
        return "OFF GRAPH"
    }
}

public enum MapTool: String, CaseIterable, Sendable {
    case mark, walk, drive, ruler, usng, magTrue, almanac, elevProfile
    case avoidPolygon, shadePrefer, highLow, crossing, truckPin
    case walkBackGPX, paceCount, tailGap, strideCal
    case publicLand, flood, highContrast, paper
}

public struct MapSession: Sendable {
    public var pack: PackManifest
    public var lockOn: Bool
    public var lastPip: (lat: Double, lon: Double)?
    public var gnssDead: Bool
    public var tools: Set<MapTool>
    public init(pack: PackManifest) {
        self.pack = pack
        self.lockOn = false
        self.lastPip = (pack.center.lat, pack.center.lon)
        self.gnssDead = false
        self.tools = Set(MapTool.allCases)
    }

    public func styleRelativePath() -> String { "\(pack.id)/style.json" }

    public mutating func mark(lat: Double, lon: Double) { lastPip = (lat, lon); lockOn = true }

    public func navigate(graph: RouteGraph, from: Int, to: Int, mode: TravelMode) -> RouteResult {
        if let r = GraphRouter.route(graph: graph, from: from, to: to, mode: mode) { return r }
        let a = lastPip ?? (pack.center.lat, pack.center.lon)
        return GraphRouter.bearingFallback(fromLat: a.0, fromLon: a.1, toLat: pack.center.lat, toLon: pack.center.lon)
    }

    public func deadReckon(heading: Double, steps: Int, stride: Double) -> (Double, Double) {
        let start = lastPip ?? (pack.center.lat, pack.center.lon)
        return DeadReckoning.advance(DRFix(lat: start.0, lon: start.1, headingDeg: heading, strideMeters: stride, steps: steps))
    }
}

public enum USNG {
    public static func label(lat: Double, lon: Double) -> String {
        let zone = Int(floor((lon + 180) / 6) + 1)
        return String(format: "USNG %d / %.4f %.4f", zone, lat, lon)
    }
}

public enum PackGeometry {
    public static func bboxRing(south: Double, west: Double, north: Double, east: Double) -> [(lat: Double, lon: Double)] {
        [
            (south, west),
            (south, east),
            (north, east),
            (north, west),
            (south, west),
        ]
    }
}

/// Self marker when MapLibre `showsUserLocation` has no GPS fix yet.
public enum UserPuck {
    public static let title = "YOU"
    public static let haloRadiusMeters: Double = 80
    public static let haloSteps = 32

    public static func contains(
        lat: Double,
        lon: Double,
        south: Double,
        west: Double,
        north: Double,
        east: Double
    ) -> Bool {
        lat >= min(south, north)
            && lat <= max(south, north)
            && lon >= min(west, east)
            && lon <= max(west, east)
    }

    public static func coordinate(
        lastKnown: (lat: Double, lon: Double)?,
        packCenter: (lat: Double, lon: Double)
    ) -> (lat: Double, lon: Double) {
        lastKnown ?? packCenter
    }

    public static func coordinate(
        lastKnown: (lat: Double, lon: Double)?,
        packCenter: (lat: Double, lon: Double),
        packSouth: Double,
        packWest: Double,
        packNorth: Double,
        packEast: Double
    ) -> (lat: Double, lon: Double) {
        if let last = lastKnown,
           contains(
            lat: last.lat,
            lon: last.lon,
            south: packSouth,
            west: packWest,
            north: packNorth,
            east: packEast
           ) {
            return last
        }
        return packCenter
    }

    public static func haloRing(
        lat: Double,
        lon: Double,
        radiusMeters: Double = haloRadiusMeters,
        steps: Int = haloSteps
    ) -> [(lat: Double, lon: Double)] {
        let latRad = lat * .pi / 180
        let metersPerDegLat = 111_320.0
        let dLat = radiusMeters / metersPerDegLat
        let dLon = radiusMeters / (metersPerDegLat * max(cos(latRad), 1e-6))
        var ring: [(lat: Double, lon: Double)] = []
        ring.reserveCapacity(steps + 1)
        for i in 0..<steps {
            let theta = (Double(i) / Double(steps)) * 2 * .pi
            ring.append((lat + dLat * sin(theta), lon + dLon * cos(theta)))
        }
        if let first = ring.first {
            ring.append(first)
        }
        return ring
    }

    public static func needsReapply(
        storedPack: (south: Double, west: Double, north: Double, east: Double)?,
        storedPuck: (lat: Double, lon: Double)?,
        pack: (south: Double, west: Double, north: Double, east: Double),
        puck: (lat: Double, lon: Double),
        mapHasPuck: Bool
    ) -> Bool {
        guard mapHasPuck, let storedPack, let storedPuck else { return true }
        return storedPack != pack || storedPuck != puck
    }
}

public enum PackCamera {
    public static let edgePaddingPoints: Double = 28

    public static func bounds(
        south: Double,
        west: Double,
        north: Double,
        east: Double
    ) -> (south: Double, west: Double, north: Double, east: Double) {
        (
            min(south, north),
            min(west, east),
            max(south, north),
            max(west, east)
        )
    }
}

public enum PackStyle {
    public static let wildSourceID = "wild"
    public static let wildRoadsLayerID = "wild-roads"
    public static let osmPointsLayerID = "osm-points"

    public static func resolved(styleAt styleURL: URL, packRoot: URL, cacheDirectory: URL? = nil) throws -> URL {
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: styleURL)) as? [String: Any] ?? [:]
        var sources = obj["sources"] as? [String: Any] ?? [:]
        for (key, raw) in sources {
            guard var src = raw as? [String: Any], src["type"] as? String == "geojson",
                  let rel = src["data"] as? String, !rel.hasPrefix("file:"), !rel.hasPrefix("{") else { continue }
            src["data"] = packRoot.appendingPathComponent(rel).absoluteString
            sources[key] = src
        }
        obj["sources"] = sources
        attachOfflineVectorLayers(&obj, packRoot: packRoot)
        let cache = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let out = cache.appendingPathComponent("\(packRoot.lastPathComponent)-style.resolved.json")
        try JSONSerialization.data(withJSONObject: obj).write(to: out)
        return out
    }

    public static func attachOfflineVectorLayers(_ obj: inout [String: Any], packRoot: URL) {
        var sources = obj["sources"] as? [String: Any] ?? [:]
        var layers = obj["layers"] as? [[String: Any]] ?? []
        let wildFile = packRoot.appendingPathComponent("wild.geojson")
        if FileManager.default.fileExists(atPath: wildFile.path) {
            if var existing = sources[wildSourceID] as? [String: Any] {
                if let rel = existing["data"] as? String, !rel.hasPrefix("file:"), !rel.hasPrefix("{") {
                    existing["data"] = packRoot.appendingPathComponent(rel).absoluteString
                    sources[wildSourceID] = existing
                }
            } else {
                sources[wildSourceID] = [
                    "type": "geojson",
                    "data": wildFile.absoluteString,
                ]
            }
            if !layers.contains(where: { $0["id"] as? String == wildRoadsLayerID }) {
                layers.append([
                    "id": wildRoadsLayerID,
                    "type": "line",
                    "source": wildSourceID,
                    "filter": ["has", "highway"],
                    "paint": [
                        "line-color": "#e8eef4",
                        "line-width": 2.4,
                    ],
                ])
            }
        }
        if sources["osm"] != nil,
           !layers.contains(where: { $0["id"] as? String == osmPointsLayerID }) {
            layers.append([
                "id": osmPointsLayerID,
                "type": "circle",
                "source": "osm",
                "paint": [
                    "circle-color": "#c5cdd6",
                    "circle-radius": 2.2,
                    "circle-stroke-color": "#0c0e10",
                    "circle-stroke-width": 0.6,
                ],
            ])
        }
        obj["sources"] = sources
        obj["layers"] = layers
    }
}
