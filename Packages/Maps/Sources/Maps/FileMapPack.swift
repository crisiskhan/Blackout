import BlackoutCore
import Foundation
import MapsRouting
import Observation

@MainActor
@Observable
public final class FileMapPack: MapPackServing {
    public private(set) var pack: MapPackSnapshot?
    /// On-pack `routing/` graph. Nil when the mounted pack has no routing — honest empty.
    public private(set) var routing: RoutingPack?
    /// Covering pack is on disk but newer than this app.
    public private(set) var packTooNew = false
    /// Covering routing/ is present but newer than this app.
    public private(set) var routingTooNew = false
    /// Bundled DefaultPack region. Recenter pins a covering pack, not this by default.
    public var bundledRegion: MapRegion? { bundledEntry?.0.region }
    /// Recenter / paint never force Denver. `pinToBundled` stays false.
    public static let pinToBundled = false
    private var dem: DEMTable?
    private var bundledEntry: (MapPackSnapshot, DEMTable?)?
    private var bundledTooNewRegion: MapRegion?
    private var installedEntries: [(MapPackSnapshot, DEMTable?)] = []
    private var installedTooNewRegions: [MapRegion] = []
    private var routingRootPath: String?

    public init(rootURL: URL?) {
        if let rootURL {
            switch Self.inspect(root: rootURL) {
            case .ready(let snapshot):
                bundledEntry = snapshot
            case .tooNew(let region):
                bundledTooNewRegion = region
            case .unreadable:
                break
            }
        }
    }

    /// File roots under bundle FieldPacks/<id>/ or Application Support/FieldPacks/<id>/. Local files only.
    public func replaceInstalledRoots(_ roots: [URL]) {
        let normalized = roots.map { $0.standardizedFileURL }
        var next: [(MapPackSnapshot, DEMTable?)] = []
        var tooNew: [MapRegion] = []
        for root in normalized {
            switch Self.inspect(root: root) {
            case .ready(let snapshot):
                next.append(snapshot)
            case .tooNew(let region):
                tooNew.append(region)
            case .unreadable:
                continue
            }
        }
        let nextPaths = next.map { $0.0.rootURL.standardizedFileURL.path }
        let currentPaths = installedEntries.map { $0.0.rootURL.standardizedFileURL.path }
        if nextPaths == currentPaths, tooNew == installedTooNewRegions { return }
        installedEntries = next
        installedTooNewRegions = tooNew
        routingRootPath = nil
    }

    /// One covering pack. Tightest bbox. Recenter does not force DefaultPack.
    /// GPS / last-known outside every on-disk pack clears tiles (empty card).
    /// Routing loads from the mounted Field Pack whose `routing/` bbox covers the fix — never
    /// from Denver DefaultPack, and not from the painted tile root when that root has no graph.
    public func resolve(latitude: Double?, longitude: Double?) {
        let regions = allEntries.map(\.0.region)
        if let index = PackPaintPolicy.coveringIndex(
            regions: regions,
            latitude: latitude,
            longitude: longitude
        ) {
            packTooNew = false
            applyTiles(allEntries[index])
        } else if coveringTooNew(latitude: latitude, longitude: longitude) {
            packTooNew = true
            clearTiles()
        } else {
            packTooNew = false
            clearTiles()
        }
        reloadRouting(latitude: latitude, longitude: longitude)
    }

    private var allEntries: [(MapPackSnapshot, DEMTable?)] {
        (bundledEntry.map { [$0] } ?? []) + installedEntries
    }

    private var allTooNewRegions: [MapRegion] {
        (bundledTooNewRegion.map { [$0] } ?? []) + installedTooNewRegions
    }

    private func coveringTooNew(latitude: Double?, longitude: Double?) -> Bool {
        PackPaintPolicy.coveringIndex(
            regions: allTooNewRegions,
            latitude: latitude,
            longitude: longitude
        ) != nil
    }

    private func applyTiles(_ entry: (MapPackSnapshot, DEMTable?)) {
        let next = entry.0.rootURL.standardizedFileURL.path
        if pack?.rootURL.standardizedFileURL.path == next, !packTooNew { return }
        let hydrated = Self.hydrate(entry)
        pack = hydrated.0
        dem = hydrated.1
    }

    private static func hydrate(_ entry: (MapPackSnapshot, DEMTable?)) -> (MapPackSnapshot, DEMTable?) {
        let snap = entry.0
        let pois = snap.pois.isEmpty ? loadPOIs(root: snap.rootURL) : snap.pois
        let addresses = snap.addresses.isEmpty ? loadAddresses(root: snap.rootURL) : snap.addresses
        let dem = entry.1 ?? loadDEM(root: snap.rootURL)
        return (
            MapPackSnapshot(
                rootURL: snap.rootURL,
                region: snap.region,
                pois: pois,
                addresses: addresses,
                disclaimer: snap.disclaimer,
                tileCount: snap.tileCount,
                expectedTileCount: snap.expectedTileCount
            ),
            dem
        )
    }

    private func clearTiles() {
        guard pack != nil || dem != nil else { return }
        pack = nil
        dem = nil
    }

    private func reloadRouting(latitude: Double?, longitude: Double?) {
        guard let latitude, let longitude else {
            if routing != nil || routingTooNew {
                routing = nil
                routingTooNew = false
                routingRootPath = nil
            }
            return
        }
        let coordinate = RoutingCoordinate(latitude: latitude, longitude: longitude)
        let roots = allEntries.map { $0.0.rootURL }
        if let hit = RoutingPackLoader.coveringInspect(
            among: roots,
            latitude: latitude,
            longitude: longitude
        ) {
            switch hit.status {
            case .tooNew:
                routing = nil
                routingTooNew = true
                routingRootPath = nil
                return
            case .compatible:
                if let routing,
                   let routingRootPath,
                   routing.manifest.bbox.contains(coordinate),
                   hit.url.standardizedFileURL.path == routingRootPath {
                    routingTooNew = false
                    return
                }
                routing = RoutingPackLoader.load(packRoot: hit.url)
                routingTooNew = false
                routingRootPath = routing == nil ? nil : hit.url.standardizedFileURL.path
                return
            case .missing, .unreadable:
                break
            }
        }
        if let root = RoutingPackLoader.coveringRoot(
            among: roots,
            latitude: latitude,
            longitude: longitude
        ) {
            routing = RoutingPackLoader.load(packRoot: root)
            routingTooNew = false
            routingRootPath = routing == nil ? nil : root.standardizedFileURL.path
            return
        }
        if routing != nil || routingTooNew {
            routing = nil
            routingTooNew = false
            routingRootPath = nil
        }
    }

    public func elevationMeters(latitude: Double, longitude: Double) -> Double? {
        dem?.sample(latitude: latitude, longitude: longitude)
    }

    public func slopeDegrees(latitude: Double, longitude: Double) -> Double? {
        dem?.slopeDegrees(latitude: latitude, longitude: longitude)
    }

    public func viewshed(fromLatitude: Double, fromLongitude: Double, observerHeightMeters: Double) -> [ViewshedRay] {
        dem?.viewshed(fromLatitude: fromLatitude, fromLongitude: fromLongitude, observerHeightMeters: observerHeightMeters) ?? []
    }

    public var hasDEM: Bool { dem != nil }

    public func slopeSamples() -> [SlopeSample] {
        dem?.slopeGrid() ?? []
    }

    private enum PackInspect {
        case ready((MapPackSnapshot, DEMTable?))
        case tooNew(MapRegion)
        case unreadable
    }

    private static func inspect(root: URL) -> PackInspect {
        guard let json = MapPackLayout.readManifestJSON(root: root) else { return .unreadable }
        let center = json["center"] as? [String: Any]
        let span = json["span"] as? [String: Any]
        let region = MapRegion(
            name: json["name"] as? String ?? "Sample pack",
            centerLatitude: (center?["lat"] as? Double) ?? 39.74,
            centerLongitude: (center?["lon"] as? Double) ?? -105.25,
            spanLatitude: (span?["lat"] as? Double) ?? 0.55,
            spanLongitude: (span?["lon"] as? Double) ?? 0.85,
            minZoom: json["minZoom"] as? Int ?? 10,
            maxZoom: json["maxZoom"] as? Int ?? 12
        )
        if !MapPackLayout.isSupported(json: json) {
            return .tooNew(region)
        }
        let disclaimer = json["disclaimer"] as? String ?? "Generated sample pack."
        guard MapPackLayout.containsTilePNGs(root: root) else {
            return .unreadable
        }
        let expectedTileCount = json["tileCount"] as? Int ?? 0
        let tileCount = expectedTileCount > 0 ? expectedTileCount : 1
        return .ready((
            MapPackSnapshot(
                rootURL: root,
                region: region,
                pois: [],
                addresses: [],
                disclaimer: disclaimer,
                tileCount: tileCount,
                expectedTileCount: tileCount
            ),
            nil
        ))
    }

    public var paintDiagnostic: String {
        pack?.paintDiagnostic ?? "no pack · 0 tiles — DefaultPack did not copy"
    }

    private static func loadPOIs(root: URL) -> [MapPOI] {
        let url = root.appendingPathComponent("poi.json")
        guard let data = try? Data(contentsOf: url),
              let places = PackPOIFile.places(from: data) else { return [] }
        return places.map {
            MapPOI(
                id: $0.id,
                name: $0.name,
                kind: $0.kind,
                latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude
            )
        }
    }

    private static func loadAddresses(root: URL) -> [MapAddress] {
        let url = root.appendingPathComponent("address.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let rows = PackPOIFile.addresses(from: data) else { return [] }
        return rows.map {
            MapAddress(
                id: $0.id,
                house: $0.house,
                street: $0.street,
                latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude
            )
        }
    }

    private static func loadDEM(root: URL) -> DEMTable? {
        let url = root.appendingPathComponent("dem.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lons = json["lons"] as? [Double],
              let lats = json["lats"] as? [Double],
              let grid = json["grid"] as? [[Double]],
              !lons.isEmpty, !lats.isEmpty else { return nil }
        return DEMTable(lons: lons, lats: lats, grid: grid)
    }
}

public struct SlopeSample: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var degrees: Double

    public init(latitude: Double, longitude: Double, degrees: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.degrees = degrees
    }
}

struct DEMTable {
    let lons: [Double]
    let lats: [Double]
    let grid: [[Double]]

    func sample(latitude: Double, longitude: Double) -> Double? {
        DEMGrid.sample(latitude: latitude, longitude: longitude, lons: lons, lats: lats, grid: grid)
    }

    func slopeDegrees(latitude: Double, longitude: Double) -> Double? {
        guard lons.count > 1, lats.count > 1,
              let firstLat = lats.first, let lastLat = lats.last,
              let firstLon = lons.first, let lastLon = lons.last else { return nil }
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(latitude * .pi / 180)
        let dLat = (lastLat - firstLat) / Double(lats.count - 1)
        let dLon = (lastLon - firstLon) / Double(lons.count - 1)
        guard let e = sample(latitude: latitude, longitude: longitude),
              let n = sample(latitude: latitude + dLat, longitude: longitude),
              let s = sample(latitude: latitude - dLat, longitude: longitude),
              let east = sample(latitude: latitude, longitude: longitude + dLon),
              let w = sample(latitude: latitude, longitude: longitude - dLon) else { return nil }
        let dzdy = (n - s) / max(2 * dLat * metersPerDegLat, 1)
        let dzdx = (east - w) / max(2 * dLon * metersPerDegLon, 1)
        let slope = atan(sqrt(dzdx * dzdx + dzdy * dzdy)) * 180 / .pi
        return slope
    }

    func slopeGrid() -> [SlopeSample] {
        var samples: [SlopeSample] = []
        for (iy, lat) in lats.enumerated() {
            for (ix, lon) in lons.enumerated() {
                if let slope = slopeDegrees(latitude: lat, longitude: lon) {
                    samples.append(SlopeSample(latitude: lat, longitude: lon, degrees: slope))
                } else if iy < grid.count, ix < grid[iy].count {
                    samples.append(SlopeSample(latitude: lat, longitude: lon, degrees: 0))
                }
            }
        }
        return samples
    }

    func viewshed(fromLatitude: Double, fromLongitude: Double, observerHeightMeters: Double) -> [ViewshedRay] {
        guard let eye = sample(latitude: fromLatitude, longitude: fromLongitude) else { return [] }
        let observer = eye + observerHeightMeters
        var rays: [ViewshedRay] = []
        let steps = 18
        let maxRange = 8_000.0
        for i in 0..<72 {
            let bearing = Double(i) * 5.0
            var maxVisible = 0.0
            var maxAngle = -Double.greatestFiniteMagnitude
            for s in 1...steps {
                let meters = Double(s) / Double(steps) * maxRange
                let dest = offset(latitude: fromLatitude, longitude: fromLongitude, meters: meters, bearing: bearing)
                guard let ground = sample(latitude: dest.0, longitude: dest.1) else { break }
                let angle = atan2(ground - observer, meters)
                if angle >= maxAngle {
                    maxAngle = angle
                    maxVisible = meters
                }
            }
            rays.append(ViewshedRay(bearingDegrees: bearing, visibleMeters: maxVisible))
        }
        return rays
    }

    private func offset(latitude: Double, longitude: Double, meters: Double, bearing: Double) -> (Double, Double) {
        let r = 6_371_000.0
        let brng = bearing * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(meters / r) + cos(lat1) * sin(meters / r) * cos(brng))
        let lon2 = lon1 + atan2(
            sin(brng) * sin(meters / r) * cos(lat1),
            cos(meters / r) - sin(lat1) * sin(lat2)
        )
        return (lat2 * 180 / .pi, lon2 * 180 / .pi)
    }
}
