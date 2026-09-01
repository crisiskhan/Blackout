import Foundation

/// Offline DEM sample. Empty or jagged tables fail closed — never first! / last!.
public enum DEMGrid {
    public static func sample(
        latitude: Double,
        longitude: Double,
        lons: [Double],
        lats: [Double],
        grid: [[Double]]
    ) -> Double? {
        guard let firstLat = lats.first, let lastLat = lats.last,
              let firstLon = lons.first, let lastLon = lons.last,
              lats.count > 1 || latitude == firstLat,
              lons.count > 1 || longitude == firstLon,
              latitude >= firstLat, latitude <= lastLat,
              longitude >= firstLon, longitude <= lastLon
        else { return nil }

        let x = interpIndex(longitude, in: lons)
        let y = interpIndex(latitude, in: lats)
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = min(x0 + 1, lons.count - 1)
        let y1 = min(y0 + 1, lats.count - 1)
        guard y0 >= 0, x0 >= 0,
              y0 < grid.count, y1 < grid.count,
              x0 < grid[y0].count, x1 < grid[y0].count,
              x0 < grid[y1].count, x1 < grid[y1].count
        else { return nil }

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

    private static func interpIndex(_ value: Double, in axis: [Double]) -> Double {
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
