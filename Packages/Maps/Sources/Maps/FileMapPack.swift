import BlackoutCore
import Foundation
import Observation

@MainActor
@Observable
public final class FileMapPack: MapPackServing {
    public private(set) var pack: MapPackSnapshot?
    private var dem: DEMTable?

    public init(rootURL: URL?) {
        if let rootURL, let snapshot = Self.load(root: rootURL) {
            pack = snapshot.0
            dem = snapshot.1
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

    public func slopeSamples() -> [SlopeSample] {
        dem?.slopeGrid() ?? []
    }

    private static func load(root: URL) -> (MapPackSnapshot, DEMTable?)? {
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
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
        let disclaimer = json["disclaimer"] as? String ?? "Generated sample pack."
        let tilesDir = root.appendingPathComponent("tiles", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: tilesDir.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        let pois = loadPOIs(root: root)
        let dem = loadDEM(root: root)
        return (MapPackSnapshot(rootURL: root, region: region, pois: pois, disclaimer: disclaimer), dem)
    }

    private static func loadPOIs(root: URL) -> [MapPOI] {
        let url = root.appendingPathComponent("poi.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["pois"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let name = row["name"] as? String,
                  let kind = row["kind"] as? String,
                  let lat = row["lat"] as? Double,
                  let lon = row["lon"] as? Double else { return nil }
            return MapPOI(id: id, name: name, kind: kind, latitude: lat, longitude: lon)
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
        guard latitude >= lats.first! && latitude <= lats.last!,
              longitude >= lons.first! && longitude <= lons.last! else { return nil }
        let x = interpIndex(longitude, in: lons)
        let y = interpIndex(latitude, in: lats)
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = min(x0 + 1, lons.count - 1)
        let y1 = min(y0 + 1, lats.count - 1)
        let tx = x - Double(x0)
        let ty = y - Double(y0)
        let v00 = grid[y0][x0]
        let v10 = grid[y0][x1]
        let v01 = grid[y1][x0]
        let v11 = grid[y1][x1]
        let a = v00 * (1 - tx) + v10 * tx
        let b = v01 * (1 - tx) + v11 * tx
        return a * (1 - ty) + b * ty
    }

    func slopeDegrees(latitude: Double, longitude: Double) -> Double? {
        guard lons.count > 1, lats.count > 1 else { return nil }
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(latitude * .pi / 180)
        let dLat = (lats.last! - lats.first!) / Double(lats.count - 1)
        let dLon = (lons.last! - lons.first!) / Double(lons.count - 1)
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

    private func interpIndex(_ value: Double, in axis: [Double]) -> Double {
        guard axis.count > 1 else { return 0 }
        for i in 0..<(axis.count - 1) {
            if value >= axis[i] && value <= axis[i + 1] {
                let span = axis[i + 1] - axis[i]
                guard span != 0 else { return Double(i) }
                return Double(i) + (value - axis[i]) / span
            }
        }
        return Double(axis.count - 1)
    }
}
