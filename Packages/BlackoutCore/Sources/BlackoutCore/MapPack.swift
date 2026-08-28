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
        case "city", "town", "hospital", "ranger":
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
}

public struct MapPackSnapshot: Sendable {
    public var rootURL: URL
    public var region: MapRegion
    public var pois: [MapPOI]
    public var disclaimer: String

    public init(rootURL: URL, region: MapRegion, pois: [MapPOI], disclaimer: String) {
        self.rootURL = rootURL
        self.region = region
        self.pois = pois
        self.disclaimer = disclaimer
    }
}
