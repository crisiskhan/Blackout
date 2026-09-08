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
        if isWater { return false }
        return isAmenity || Self.fieldCivilization.contains(kind)
    }

    public var isWater: Bool {
        Self.waterKinds.contains(kind)
    }

    public var isAmenity: Bool {
        Self.amenityKinds.contains(kind)
    }

    private static let amenityKinds: Set<String> = [
        "shop", "grocery", "supermarket", "convenience", "mall", "hardware", "clothes",
        "fuel", "pharmacy", "hospital", "clinic", "dentist", "dentists",
        "police", "fire_station", "post_office", "school", "bank", "atm",
        "cafe", "fast_food", "restaurant", "bar", "pub",
        "toilets", "parking", "charging_station",
        "hotel", "motel", "lodging", "camp_site", "information",
        "office", "craft"
    ]

    private static let fieldCivilization: Set<String> = [
        "city", "town", "ranger", "road", "rail", "mill"
    ]

    private static let waterKinds: Set<String> = [
        "spring", "tank", "water", "reservoir", "lake", "creek", "river", "pond"
    ]
}

public struct MapAddress: Hashable, Sendable, Identifiable {
    public var id: String
    public var house: String
    public var street: String
    public var latitude: Double
    public var longitude: Double

    public init(id: String, house: String, street: String, latitude: Double, longitude: Double) {
        self.id = id
        self.house = house
        self.street = street
        self.latitude = latitude
        self.longitude = longitude
    }

    public var title: String {
        "\(house) \(street)".trimmingCharacters(in: .whitespaces)
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
    public var addresses: [MapAddress]
    public var disclaimer: String
    public var tileCount: Int
    public var expectedTileCount: Int

    public init(
        rootURL: URL,
        region: MapRegion,
        pois: [MapPOI],
        addresses: [MapAddress] = [],
        disclaimer: String,
        tileCount: Int = 0,
        expectedTileCount: Int = 0
    ) {
        self.rootURL = rootURL
        self.region = region
        self.pois = pois
        self.addresses = addresses
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
    /// Field-pack manifest layout. Missing `schema` is this SHA's v1.
    public static let schema = 1
    public static let tooNewCopy = "Pack too new."

    public static func schema(from json: [String: Any]) -> Int {
        if let value = json["schema"] as? Int { return value }
        if let value = json["schema"] as? Double { return Int(value) }
        return schema
    }

    public static func isSupported(_ value: Int) -> Bool {
        value == schema
    }

    public static func isSupported(json: [String: Any]) -> Bool {
        isSupported(schema(from: json))
    }

    public static func readManifestJSON(root: URL) -> [String: Any]? {
        let url = root.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

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
        let tiles = root.appendingPathComponent("tiles", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: tiles.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        guard let enumerator = FileManager.default.enumerator(
            at: tiles,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "png" {
                return true
            }
        }
        return false
    }
}
