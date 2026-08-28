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
