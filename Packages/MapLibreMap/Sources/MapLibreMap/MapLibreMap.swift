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
        if let data = try? JSONEncoder().encode(marks) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }

    public static func load(defaults: UserDefaults = .standard) -> [MapMark] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let loaded = (try? JSONDecoder().decode([MapMark].self, from: data)) ?? []
        return uniqued(loaded)
    }

    /// Drop marks that repeat a coordinate, keeping the one already on disk.
    ///
    /// `MarkDrop.merging` mints an id because it is dropping a brand new pin.
    /// Reusing it here renamed every mark on the way back off disk, so a pin
    /// survived a kill with different identity than it went in with.
    public static func uniqued(_ marks: [MapMark]) -> [MapMark] {
        marks.reduce(into: [MapMark]()) { kept, mark in
            let clash = kept.contains {
                MarkDrop.sameCoord(($0.lat, $0.lon), (mark.lat, mark.lon))
            }
            if !clash { kept.append(mark) }
        }
    }
}

public enum MarkDrop {
    public static let coordPlaces = 4

    public static func rounded(_ value: Double, places: Int = coordPlaces) -> Double {
        let scale = pow(10.0, Double(places))
        return (value * scale).rounded() / scale
    }

    public static func sameCoord(
        _ a: (lat: Double, lon: Double),
        _ b: (lat: Double, lon: Double)
    ) -> Bool {
        rounded(a.lat) == rounded(b.lat) && rounded(a.lon) == rounded(b.lon)
    }

    public static func merging(
        _ marks: [MapMark],
        lat: Double,
        lon: Double,
        label: String
    ) -> [MapMark] {
        if marks.contains(where: { sameCoord(($0.lat, $0.lon), (lat, lon)) }) {
            return marks
        }
        return marks + [MapMark(id: UUID().uuidString, lat: lat, lon: lon, label: label)]
    }
}

public enum PackChrome {
    public static let offPack = "OFF PACK"

    public static func banner(
        fix: (lat: Double, lon: Double)?,
        bbox: (south: Double, west: Double, north: Double, east: Double)?
    ) -> String {
        guard let fix, let bbox else { return "" }
        if UserPuck.contains(
            lat: fix.lat,
            lon: fix.lon,
            south: bbox.south,
            west: bbox.west,
            north: bbox.north,
            east: bbox.east
        ) {
            return ""
        }
        return offPack
    }

    public static func markLabel(
        lat: Double,
        lon: Double,
        packName: String,
        bbox: (south: Double, west: Double, north: Double, east: Double)?
    ) -> String {
        guard let bbox else { return packName }
        if UserPuck.contains(
            lat: lat,
            lon: lon,
            south: bbox.south,
            west: bbox.west,
            north: bbox.north,
            east: bbox.east
        ) {
            return packName
        }
        return offPack
    }
}

public enum PackOverlay {
    public static let fillsBBox = false
}

public enum OSMCredit {
    public static let line = "© OpenStreetMap contributors"
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

    /// Street names only render from `PackStyle` road-labels `minzoom` up. Fitting a
    /// whole 0.3° pack lands near z11, which is why TX WEST opened as nameless lines.
    /// The map therefore opens on YOU at walking zoom; FIT PACK still shows the region.
    public static let openZoom: Double = 15
    public static let streetNameMinZoom: Double = 12

    public static func opensOnStreetNames(openZoom: Double = openZoom, labelMinZoom: Double = streetNameMinZoom) -> Bool {
        openZoom >= labelMinZoom
    }

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

    public static func shouldRefit(
        fittedPack: (south: Double, west: Double, north: Double, east: Double)?,
        pack: (south: Double, west: Double, north: Double, east: Double),
        fittedSize: (width: Double, height: Double)?,
        size: (width: Double, height: Double)
    ) -> Bool {
        guard size.width > 1, size.height > 1 else { return false }
        guard let fittedPack, let fittedSize else { return true }
        if fittedPack != pack { return true }
        return abs(fittedSize.width - size.width) > 1 || abs(fittedSize.height - size.height) > 1
    }
}

public enum PackStyle {
    public static let wildSourceID = "wild"
    public static let wildRoadsLayerID = "wild-roads"
    public static let osmPointsLayerID = "osm-points"
    public static let roadLabelsLayerID = "road-labels"
    public static let roadRefsLayerID = "road-refs"
    public static let placeLabelsLayerID = "place-labels"
    public static let tracksLayerID = "tracks"

    /// Streets arrive as vector tiles, which are addressed by layer. A layer on
    /// the `osm` source that does not name one draws nothing at all, silently,
    /// so the mapping lives here rather than being repeated at each call site.
    public static let roadSourceLayer = "road"
    public static let placeSourceLayer = "place"
    public static let voidInk = "#000000"
    public static let silverInk = "#B8BDC2"
    public static let accentInk = "#E10600"
    public static let glyphTokens = ["{fontstack}", "{range}"]
    /// Bump when the resolver changes: a phone that already cached a resolved style must
    /// not keep replaying it. v2 stopped percent-escaping the glyph tokens.
    public static let resolverVersion = 2

    private static var resolvedMemory: [String: URL] = [:]

    public static func needsResolve(styleModified: Date?, outputModified: Date?) -> Bool {
        guard let outputModified else { return true }
        guard let styleModified else { return false }
        return styleModified > outputModified
    }

    /// `URL.appendingPathComponent` percent-escapes `{` and `}`, which turned the local
    /// glyph template into `.../%7Bfontstack%7D/%7Brange%7D.pbf`. MapLibre substitutes
    /// only literal `{fontstack}` / `{range}`, so every glyph range 404'd and no street
    /// name could draw at any zoom. Build the file URL by string so the tokens survive.
    public static func localGlyphURL(template: String, packRoot: URL) -> String {
        guard !template.isEmpty, !template.hasPrefix("file:"), !template.contains("://") else {
            return template
        }
        var base = packRoot.absoluteString
        if !base.hasSuffix("/") { base += "/" }
        var relative = Substring(template)
        while relative.hasPrefix("/") { relative = relative.dropFirst() }
        return base + relative
    }

    public static func resolved(styleAt styleURL: URL, packRoot: URL, cacheDirectory: URL? = nil) throws -> URL {
        let memoryKey = packRoot.path
        if let cached = resolvedMemory[memoryKey] {
            return cached
        }
        let cache = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let out = cache.appendingPathComponent(
            "\(packRoot.lastPathComponent)-style.resolved.v\(resolverVersion).json"
        )
        let styleAttrs = try? FileManager.default.attributesOfItem(atPath: styleURL.path)
        let outAttrs = try? FileManager.default.attributesOfItem(atPath: out.path)
        let styleModified = styleAttrs?[.modificationDate] as? Date
        let outputModified = outAttrs?[.modificationDate] as? Date
        if !needsResolve(styleModified: styleModified, outputModified: outputModified) {
            resolvedMemory[memoryKey] = out
            return out
        }
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: styleURL)) as? [String: Any] ?? [:]
        if let glyphs = obj["glyphs"] as? String {
            obj["glyphs"] = localGlyphURL(template: glyphs, packRoot: packRoot)
        }
        var sources = obj["sources"] as? [String: Any] ?? [:]
        for (key, raw) in sources {
            guard var src = raw as? [String: Any] else { continue }
            let kind = src["type"] as? String
            if kind == "geojson", let rel = src["data"] as? String, !rel.hasPrefix("file:"), !rel.hasPrefix("{") {
                src["data"] = packRoot.appendingPathComponent(rel).absoluteString
                sources[key] = src
            } else if kind == "image", let rel = src["url"] as? String, !rel.hasPrefix("file:"), !rel.contains("://") {
                src["url"] = packRoot.appendingPathComponent(rel).absoluteString
                sources[key] = src
            } else if kind == "vector", let rel = src["url"] as? String, PMTilesURL.isRelative(rel) {
                src["url"] = PMTilesURL.resolve(rel, packRoot: packRoot)
                sources[key] = src
            }
        }
        obj["sources"] = sources
        attachOfflineVectorLayers(&obj, packRoot: packRoot)
        try JSONSerialization.data(withJSONObject: obj).write(to: out)
        resolvedMemory[memoryKey] = out
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
                        "line-color": silverInk,
                        "line-width": 2.6,
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
                "source-layer": placeSourceLayer,
                "layout": [
                    "visibility": "none",
                ],
                "paint": [
                    "circle-color": silverInk,
                    "circle-radius": 2.4,
                    "circle-stroke-color": voidInk,
                    "circle-stroke-width": 0.8,
                ],
            ])
        }
        if sources["osm"] != nil,
           !layers.contains(where: { $0["id"] as? String == tracksLayerID }) {
            layers.append([
                "id": tracksLayerID,
                "type": "line",
                "source": "osm",
                "source-layer": roadSourceLayer,
                "minzoom": 12,
                "filter": [
                    "in",
                    ["get", "highway"],
                    ["literal", ["track", "path", "footway", "bridleway", "cycleway", "steps"]],
                ],
                "paint": [
                    "line-color": silverInk,
                    "line-opacity": 0.72,
                    "line-width": 2.4,
                ],
            ])
        }
        if sources["osm"] != nil,
           !layers.contains(where: { $0["id"] as? String == roadLabelsLayerID }) {
            layers.append([
                "id": roadLabelsLayerID,
                "type": "symbol",
                "source": "osm",
                "source-layer": roadSourceLayer,
                "minzoom": 12,
                "filter": ["all", ["has", "highway"], ["has", "name"]],
                "layout": [
                    "text-field": ["get", "name"],
                    "symbol-placement": "line",
                    "symbol-spacing": 100,
                    "text-size": ["interpolate", ["linear"], ["zoom"], 12, 12, 14, 15, 16, 19, 18, 22],
                    "text-font": ["Open Sans Regular"],
                    "text-max-angle": 40,
                    "text-padding": 2,
                    "text-optional": true,
                    "text-keep-upright": true,
                ],
                "paint": [
                    "text-color": silverInk,
                    "text-halo-color": voidInk,
                    "text-halo-width": 2.2,
                ],
            ])
        }
        if sources["osm"] != nil,
           !layers.contains(where: { $0["id"] as? String == roadRefsLayerID }) {
            layers.append([
                "id": roadRefsLayerID,
                "type": "symbol",
                "source": "osm",
                "source-layer": roadSourceLayer,
                "minzoom": 11,
                "filter": ["all", ["has", "highway"], ["has", "ref"]],
                "layout": [
                    "text-field": ["get", "ref"],
                    "symbol-placement": "line",
                    "symbol-spacing": 300,
                    "text-size": ["interpolate", ["linear"], ["zoom"], 11, 15, 14, 18, 16, 21],
                    "text-font": ["Open Sans Regular"],
                    "text-optional": true,
                    "symbol-sort-key": 0,
                ],
                "paint": [
                    "text-color": accentInk,
                    "text-halo-color": silverInk,
                    "text-halo-width": 2.0,
                ],
            ])
        }
        if sources["osm"] != nil,
           !layers.contains(where: { $0["id"] as? String == placeLabelsLayerID }) {
            layers.append([
                "id": placeLabelsLayerID,
                "type": "symbol",
                "source": "osm",
                "source-layer": placeSourceLayer,
                "minzoom": 10,
                "maxzoom": 16,
                "filter": ["has", "place"],
                "layout": [
                    "text-field": ["get", "name"],
                    "text-size": ["interpolate", ["linear"], ["zoom"], 10, 13, 14, 18],
                    "text-font": ["Open Sans Regular"],
                ],
                "paint": [
                    "text-color": silverInk,
                    "text-halo-color": voidInk,
                    "text-halo-width": 2.0,
                ],
            ])
        }
        obj["sources"] = sources
        obj["layers"] = layers
    }
}

public enum OverlaySync: Sendable {
    public static func needsStyleMutation(
        force: Bool,
        puckNeedsReapply: Bool,
        routeNeedsReapply: Bool,
        destinationNeedsReapply: Bool = false
    ) -> Bool {
        force || puckNeedsReapply || routeNeedsReapply || destinationNeedsReapply
    }
}

public enum MapKeepAwake: Sendable {
    public static func idleTimerDisabled(mapInstrumentActive: Bool) -> Bool {
        mapInstrumentActive
    }
}

/// UIKit `MLNMapView` ignores SwiftUI `allowsHitTesting`. The Metal view has
/// to take this itself, and a hold card owns the canvas while it is up.
public enum MapCanvasHit: Sendable {
    public static func enabled(onMap: Bool, holding: Bool) -> Bool {
        onMap && !holding
    }
}

public enum FixPublish: Sendable {
    public static let minInterval: TimeInterval = 0.25
    public static let minHeadingDelta = 2.0
    public static let minMoveMeters = 4.0

    public static func headingDelta(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }

    public static func shouldPublish(
        now: TimeInterval,
        lastPublished: TimeInterval?,
        heading: Double?,
        lastHeading: Double?,
        coord: (lat: Double, lon: Double)?,
        lastCoord: (lat: Double, lon: Double)?
    ) -> Bool {
        guard let lastPublished else { return true }
        if now - lastPublished < minInterval { return false }
        if let heading, let lastHeading, headingDelta(heading, lastHeading) >= minHeadingDelta {
            return true
        }
        if heading != nil && lastHeading == nil { return true }
        if let coord, let lastCoord {
            return GraphRouter.haversine(coord.lat, coord.lon, lastCoord.lat, lastCoord.lon) >= minMoveMeters
        }
        return coord != nil && lastCoord == nil
    }
}
