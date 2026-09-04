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

public enum PackStyle {
    public static func resolved(styleAt styleURL: URL, packRoot: URL) throws -> URL {
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: styleURL)) as? [String: Any] ?? [:]
        var sources = obj["sources"] as? [String: Any] ?? [:]
        for (key, raw) in sources {
            guard var src = raw as? [String: Any], src["type"] as? String == "geojson",
                  let rel = src["data"] as? String, !rel.hasPrefix("file:"), !rel.hasPrefix("{") else { continue }
            src["data"] = packRoot.appendingPathComponent(rel).absoluteString
            sources[key] = src
        }
        obj["sources"] = sources
        let out = packRoot.appendingPathComponent("style.resolved.json")
        try JSONSerialization.data(withJSONObject: obj).write(to: out)
        return out
    }
}
