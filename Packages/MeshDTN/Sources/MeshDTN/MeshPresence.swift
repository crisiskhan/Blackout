import Foundation

/// A heard phone. Discovery is not a peer. Hop is a Blackout carry.
public struct MeshHear: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: Kind
    public var rssi: Int
    public var lat: Double?
    public var lon: Double?
    public var heardAt: Date

    public enum Kind: String, Sendable {
        case apple, samsung, hop
    }

    public init(
        id: String,
        kind: Kind,
        rssi: Int = 0,
        lat: Double? = nil,
        lon: Double? = nil,
        heardAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.rssi = rssi
        self.lat = lat
        self.lon = lon
        self.heardAt = heardAt
    }
}

/// Canvas id for a clustered NEAR mark.
public enum NearMark {
    public static let idPrefix = "NEAR·"

    public static func canvasID(lat: Double, lon: Double) -> String {
        String(format: "NEAR·%.5f,%.5f", lat, lon)
    }

    public static func parse(_ raw: String) -> (lat: Double, lon: Double)? {
        guard raw.hasPrefix(idPrefix) else { return nil }
        let rest = String(raw.dropFirst(idPrefix.count))
        let parts = rest.split(separator: ",")
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else {
            return nil
        }
        return (lat, lon)
    }
}

public struct NearHold: Equatable, Sendable {
    public var id: String
    public var lat: Double
    public var lon: Double
    public var count: Int
    public var kinds: [String]

    public init(id: String, lat: Double, lon: Double, count: Int, kinds: [String]) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.count = count
        self.kinds = kinds
    }
}

/// House-sized clusters of heard phones. Green/black on the field.
public enum MeshPresence {
    public static let houseMeters = 45.0
    public static let hearSeconds: TimeInterval = 25

    public struct Mark: Equatable, Sendable, Identifiable {
        public var id: String
        public var lat: Double
        public var lon: Double
        public var count: Int
        public var kinds: [String]

        public init(id: String, lat: Double, lon: Double, count: Int, kinds: [String]) {
            self.id = id
            self.lat = lat
            self.lon = lon
            self.count = count
            self.kinds = kinds
        }
    }

    public static func classify(
        name: String,
        manufacturer: UInt16?,
        services: [String]
    ) -> MeshHear.Kind? {
        let n = name.lowercased()
        let accessories = ["airpods", "watch", "pencil", "keyboard", "mouse", "buds"]
        let phones = ["iphone", "ipad", "galaxy", "samsung"]
        if accessories.contains(where: { n.contains($0) }) && !phones.contains(where: { n.contains($0) }) {
            return nil
        }
        let svc = Set(services.map { $0.lowercased() })
        if svc.contains("1812") && !phones.contains(where: { n.contains($0) }) {
            return nil
        }
        if svc.contains("hop") {
            return .hop
        }
        if n.contains("iphone") || n.contains("ipad") {
            return .apple
        }
        if n.contains("galaxy") || n.contains("samsung") || n.hasPrefix("sm-") {
            return .samsung
        }
        if manufacturer == 0x004C { return .apple }
        if manufacturer == 0x0075 { return .samsung }
        return nil
    }

    public static func manufacturerID(_ data: Data?) -> UInt16? {
        guard let data, data.count >= 2 else { return nil }
        return UInt16(data[0]) | (UInt16(data[1]) << 8)
    }

    public static func cluster(
        _ points: [(id: String, lat: Double, lon: Double, kind: String)],
        radiusMeters: Double = houseMeters
    ) -> [Mark] {
        var leftover = points.sorted { $0.id < $1.id }
        var out: [Mark] = []
        while !leftover.isEmpty {
            let seed = leftover.removeFirst()
            var bunch = [seed]
            var kept: [(id: String, lat: Double, lon: Double, kind: String)] = []
            for point in leftover {
                if meters(seed.lat, seed.lon, point.lat, point.lon) <= radiusMeters {
                    bunch.append(point)
                } else {
                    kept.append(point)
                }
            }
            leftover = kept
            let lat = bunch.map(\.lat).reduce(0, +) / Double(bunch.count)
            let lon = bunch.map(\.lon).reduce(0, +) / Double(bunch.count)
            var kinds: [String] = []
            for point in bunch where !point.kind.isEmpty && !kinds.contains(point.kind) {
                kinds.append(point.kind)
            }
            out.append(
                Mark(
                    id: NearMark.canvasID(lat: lat, lon: lon),
                    lat: lat,
                    lon: lon,
                    count: bunch.count,
                    kinds: kinds
                )
            )
        }
        return out
    }

    public static func marks(
        hears: [MeshHear],
        you: (lat: Double, lon: Double)?
    ) -> [Mark] {
        var placed: [(id: String, lat: Double, lon: Double, kind: String)] = []
        for hear in hears {
            let lat: Double
            let lon: Double
            if let hLat = hear.lat, let hLon = hear.lon, hLat.isFinite, hLon.isFinite {
                lat = hLat
                lon = hLon
            } else if let you {
                lat = you.lat
                lon = you.lon
            } else {
                continue
            }
            placed.append((hear.id, lat, lon, hear.kind.rawValue))
        }
        return cluster(placed)
    }

    public static func chrome(count: Int) -> String {
        guard count > 0 else { return "" }
        return "NEAR · \(count)"
    }

    public static func meters(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let r = 6_371_000.0
        let p1 = aLat * .pi / 180
        let p2 = bLat * .pi / 180
        let dphi = (bLat - aLat) * .pi / 180
        let dl = (bLon - aLon) * .pi / 180
        let h = sin(dphi / 2) * sin(dphi / 2)
            + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}
