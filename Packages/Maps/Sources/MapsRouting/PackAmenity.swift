import Foundation

/// Shop / civic / field amenity layer. Pack files only. No live search.
public enum PackAmenityPolicy {
    public static let pinZoom = 11
    public static let densityCap = 48

    public static let amenityKinds: Set<String> = [
        "shop", "grocery", "supermarket", "convenience", "mall", "hardware", "clothes",
        "fuel", "pharmacy", "hospital", "clinic", "dentist", "dentists",
        "police", "fire_station", "post_office", "school", "bank", "atm",
        "cafe", "fast_food", "restaurant", "bar", "pub",
        "toilets", "parking", "charging_station",
        "hotel", "motel", "lodging", "camp_site", "information",
        "office", "craft"
    ]

    public static let fieldKinds: Set<String> = [
        "town", "city", "ranger", "road", "rail", "mill",
        "spring", "tank", "water", "reservoir", "lake", "creek", "river", "pond"
    ]

    public static func isAmenity(_ kind: String) -> Bool {
        amenityKinds.contains(normalize(kind))
    }

    /// Addresses stay searchable. They do not paint a statewide dot field.
    public static func paintsOnMap(_ kind: String) -> Bool {
        let key = normalize(kind)
        if key == "address" || key == "house" { return false }
        return isAmenity(key) || fieldKinds.contains(key)
    }

    public static func showsPins(zoom: Int) -> Bool {
        zoom >= pinZoom
    }

    public static func cap(_ pins: [RoutingPOI], limit: Int = densityCap) -> [RoutingPOI] {
        Array(pins.prefix(limit))
    }

    public static func visiblePins(pois: [RoutingPOI], zoom: Int, limit: Int = densityCap) -> [RoutingPOI] {
        guard showsPins(zoom: zoom) else { return [] }
        return cap(pois.filter { paintsOnMap($0.kind) }, limit: limit)
    }

    public static let tapRadiusMeters: Double = 48

    /// Nearest painted pin within `radiusMeters`. Empty tap / far zoom is a miss.
    public static func pinHit(
        latitude: Double,
        longitude: Double,
        pins: [RoutingPOI],
        zoom: Int,
        radiusMeters: Double = tapRadiusMeters
    ) -> RoutingPOI? {
        let visible = visiblePins(pois: pins, zoom: zoom)
        let tap = RoutingCoordinate(latitude: latitude, longitude: longitude)
        return visible.min(by: {
            Geo.haversine(tap, $0.coordinate) < Geo.haversine(tap, $1.coordinate)
        }).flatMap { pin in
            Geo.haversine(tap, pin.coordinate) <= radiusMeters ? pin : nil
        }
    }

    private static func normalize(_ kind: String) -> String {
        kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct RoutingAddress: Hashable, Sendable, Identifiable {
    public var id: String
    public var house: String
    public var street: String
    public var coordinate: RoutingCoordinate

    public init(id: String, house: String, street: String, coordinate: RoutingCoordinate) {
        self.id = id
        self.house = house
        self.street = street
        self.coordinate = coordinate
    }

    public var title: String {
        "\(house) \(street)".trimmingCharacters(in: .whitespaces)
    }
}

/// `poi.json` / `address.json` inside a Field Pack. Missing schema is v1. Newer fails closed.
public enum PackPOIFile {
    public static let schema = 1

    public static func places(from data: Data) -> [RoutingPOI]? {
        guard let json = object(data) else { return [] }
        guard schemaOK(json) else { return nil }
        let rows = json["pois"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let name = row["name"] as? String,
                  let kind = row["kind"] as? String,
                  let lat = number(row["lat"]),
                  let lon = number(row["lon"]) else { return nil }
            return RoutingPOI(
                id: id,
                name: name,
                kind: kind,
                coordinate: RoutingCoordinate(latitude: lat, longitude: lon)
            )
        }
    }

    public static func addresses(from data: Data) -> [RoutingAddress]? {
        guard let json = object(data) else { return [] }
        guard schemaOK(json) else { return nil }
        let rows = json["addresses"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let house = row["house"] as? String,
                  let street = row["street"] as? String,
                  let lat = number(row["lat"]),
                  let lon = number(row["lon"]) else { return nil }
            return RoutingAddress(
                id: id,
                house: house,
                street: street,
                coordinate: RoutingCoordinate(latitude: lat, longitude: lon)
            )
        }
    }

    private static func schemaOK(_ json: [String: Any]) -> Bool {
        if let value = json["schema"] as? Int { return value == schema }
        if let value = json["schema"] as? Double { return Int(value) == schema }
        return true
    }

    private static func object(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}
