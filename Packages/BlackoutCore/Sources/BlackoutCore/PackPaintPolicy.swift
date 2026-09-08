import Foundation

/// One covering pack. Tightest bbox wins. No mosaic. No DefaultPack fallback.
public enum PackPaintPolicy {
    /// Recenter pins the camera to coverage. It does not select Denver.
    public static let recenterForcesDefaultPack = false
    /// GPS outside every installed/bundled bbox is the empty card.
    public static let paintsDefaultWhenUncovered = false

    public static func coveringIndex(
        regions: [MapRegion],
        latitude: Double?,
        longitude: Double?
    ) -> Int? {
        guard let latitude, let longitude else { return nil }
        let hits = regions.enumerated().filter { _, region in
            region.contains(latitude: latitude, longitude: longitude)
        }
        return hits.min { lhs, rhs in
            area(lhs.element) < area(rhs.element)
        }?.offset
    }

    private static func area(_ region: MapRegion) -> Double {
        region.spanLatitude * region.spanLongitude
    }
}
