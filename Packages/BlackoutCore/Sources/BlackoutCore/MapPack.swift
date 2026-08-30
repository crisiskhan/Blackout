import Foundation

public struct MapPOI: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var latitude: Double
    public var longitude: Double

    public init(id: String, name: String, kind: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.kind = kind
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isCivilization: Bool {
        switch kind {
        case "city", "town", "hospital", "ranger", "road", "rail", "mill":
            return true
        default:
            return false
        }
    }

    public var isWater: Bool {
        switch kind {
        case "spring", "tank", "water", "reservoir", "lake", "creek", "river", "pond":
            return true
        default:
            return false
        }
    }
}

public struct MapRegion: Hashable, Sendable {
    public var name: String
    public var centerLatitude: Double
    public var centerLongitude: Double
    public var spanLatitude: Double
    public var spanLongitude: Double
    public var minZoom: Int
    public var maxZoom: Int

    public init(
        name: String,
        centerLatitude: Double,
        centerLongitude: Double,
        spanLatitude: Double,
        spanLongitude: Double,
        minZoom: Int,
        maxZoom: Int
    ) {
        self.name = name
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.spanLatitude = spanLatitude
        self.spanLongitude = spanLongitude
        self.minZoom = minZoom
        self.maxZoom = maxZoom
    }

    public var west: Double { centerLongitude - spanLongitude / 2 }
    public var east: Double { centerLongitude + spanLongitude / 2 }
    public var south: Double { centerLatitude - spanLatitude / 2 }
    public var north: Double { centerLatitude + spanLatitude / 2 }

    /// Manifest center, e.g. DefaultPack Denver / Front Range. Not GPS.
    public var centerLabel: String {
        String(format: "%.2f,%.2f", centerLatitude, centerLongitude)
    }

    public func contains(latitude: Double, longitude: Double, padFraction: Double = 0) -> Bool {
        let padLon = spanLongitude * padFraction
        let padLat = spanLatitude * padFraction
        return longitude >= west - padLon && longitude <= east + padLon
            && latitude >= south - padLat && latitude <= north + padLat
    }
}

public struct MapPackSnapshot: Sendable {
    public var rootURL: URL
    public var region: MapRegion
    public var pois: [MapPOI]
    public var disclaimer: String
    public var tileCount: Int
    public var expectedTileCount: Int

    public init(
        rootURL: URL,
        region: MapRegion,
        pois: [MapPOI],
        disclaimer: String,
        tileCount: Int = 0,
        expectedTileCount: Int = 0
    ) {
        self.rootURL = rootURL
        self.region = region
        self.pois = pois
        self.disclaimer = disclaimer
        self.tileCount = tileCount
        self.expectedTileCount = expectedTileCount
    }

    /// Recenter / HUD line. Testers have no Mac Console; this is the runtime log.
    public var paintDiagnostic: String {
        if tileCount == 0 {
            return "\(region.name) · pack \(region.centerLabel) · 0 tiles — pack did not copy"
        }
        if expectedTileCount > 0, tileCount < expectedTileCount {
            return "\(region.name) · pack \(region.centerLabel) · \(tileCount)/\(expectedTileCount) tiles — short copy"
        }
        return "\(region.name) · pack \(region.centerLabel) · \(tileCount) tiles"
    }
}

/// Layout under DefaultPack / downloaded packs: `tiles/{z}/{x}/{y}.png`.
public enum MapPackLayout {
    public static func tilePNGCount(root: URL) -> Int {
        let tiles = root.appendingPathComponent("tiles", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: tiles.path, isDirectory: &isDir), isDir.boolValue else {
            return 0
        }
        guard let enumerator = FileManager.default.enumerator(
            at: tiles,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "png" {
                count += 1
            }
        }
        return count
    }

    public static func containsTilePNGs(root: URL) -> Bool {
        tilePNGCount(root: root) > 0
    }
}
