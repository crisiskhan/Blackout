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

    public var west: Double { centerLongitude - spanLongitude / 2 }
    public var east: Double { centerLongitude + spanLongitude / 2 }
    public var south: Double { centerLatitude - spanLatitude / 2 }
    public var north: Double { centerLatitude + spanLatitude / 2 }

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

    public init(rootURL: URL, region: MapRegion, pois: [MapPOI], disclaimer: String) {
        self.rootURL = rootURL
        self.region = region
        self.pois = pois
        self.disclaimer = disclaimer
    }
}
