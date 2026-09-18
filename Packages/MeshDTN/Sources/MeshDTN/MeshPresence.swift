import Foundation

/// A heard radio. Discovery is not a peer. Hop is a Blackout carry.
public struct MeshHear: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: Kind
    public var rssi: Int
    public var lat: Double?
    public var lon: Double?
    public var heardAt: Date

    public enum Kind: String, Sendable {
        case apple, samsung, hop, device
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
    public static let lastPrefix = "LAST·"

    public static func canvasID(lat: Double, lon: Double) -> String {
        String(format: "NEAR·%.5f,%.5f", lat, lon)
    }

    public static func lastID(lat: Double, lon: Double) -> String {
        String(format: "LAST·%.5f,%.5f", lat, lon)
    }

    public static func parse(_ raw: String) -> (lat: Double, lon: Double, last: Bool)? {
        let last = raw.hasPrefix(lastPrefix)
        guard raw.hasPrefix(idPrefix) || last else { return nil }
        let rest = String(raw.dropFirst(last ? lastPrefix.count : idPrefix.count))
        let parts = rest.split(separator: ",")
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else {
            return nil
        }
        return (lat, lon, last)
    }
}

public struct NearHold: Equatable, Sendable {
    public var id: String
    public var lat: Double
    public var lon: Double
    public var count: Int
    public var kinds: [String]
    public var placed: Bool
    public var last: Bool
    public var signal: String

    public init(
        id: String,
        lat: Double,
        lon: Double,
        count: Int,
        kinds: [String],
        placed: Bool = true,
        last: Bool = false,
        signal: String = ""
    ) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.count = count
        self.kinds = kinds
        self.placed = placed
        self.last = last
        self.signal = signal
    }
}

/// House-sized clusters of heard radios. Green/black on the field.
public enum MeshPresence {
    public static let houseMeters = 45.0
    public static let hearSeconds: TimeInterval = 25
    public static let lastSeconds: TimeInterval = 1800
    public static let probeCap = 6

    public struct Mark: Equatable, Sendable, Identifiable {
        public var id: String
        public var lat: Double
        public var lon: Double
        public var count: Int
        public var kinds: [String]
        public var placed: Bool

        public init(
            id: String,
            lat: Double,
            lon: Double,
            count: Int,
            kinds: [String],
            placed: Bool = true
        ) {
            self.id = id
            self.lat = lat
            self.lon = lon
            self.count = count
            self.kinds = kinds
            self.placed = placed
        }
    }

    public static func classify(
        name: String,
        manufacturer: UInt16?,
        services: [String]
    ) -> MeshHear.Kind {
        let n = name.lowercased()
        let svc = Set(services.map { $0.lowercased() })
        if svc.contains("hop") {
            return .hop
        }
        if n.contains("iphone") || n.contains("ipad") {
            return .apple
        }
        if n.contains("galaxy") || n.contains("samsung") || n.hasPrefix("sm-") {
            return .samsung
        }
        if manufacturer == 0x004C && !accessory(name: name, services: services) {
            return .apple
        }
        if manufacturer == 0x0075 && !accessory(name: name, services: services) {
            return .samsung
        }
        return .device
    }

    /// Closed accessories still paint. They cannot carry hop, so they are not probed.
    public static func shouldProbe(name: String, services: [String]) -> Bool {
        if services.contains(where: { $0.lowercased() == "hop" }) {
            return true
        }
        return !accessory(name: name, services: services)
    }

    public static func accessory(name: String, services: [String]) -> Bool {
        let n = name.lowercased()
        let phones = ["iphone", "ipad", "galaxy", "samsung", "pixel", "motorola"]
        if phones.contains(where: { n.contains($0) }) {
            return false
        }
        let accessories = ["airpods", "watch", "pencil", "keyboard", "mouse", "buds"]
        if accessories.contains(where: { n.contains($0) }) {
            return true
        }
        return services.contains(where: { $0.lowercased() == "1812" })
    }

    public static func manufacturerID(_ data: Data?) -> UInt16? {
        guard let data, data.count >= 2 else { return nil }
        return UInt16(data[0]) | (UInt16(data[1]) << 8)
    }

    public static func cluster(
        _ points: [(id: String, lat: Double, lon: Double, kind: String)],
        radiusMeters: Double = houseMeters
    ) -> [Mark] {
        cluster(
            points.map { ($0.id, $0.lat, $0.lon, $0.kind, true) },
            radiusMeters: radiusMeters
        )
    }

    public static func cluster(
        _ points: [(id: String, lat: Double, lon: Double, kind: String, placed: Bool)],
        radiusMeters: Double = houseMeters
    ) -> [Mark] {
        var leftover = points.sorted { $0.id < $1.id }
        var out: [Mark] = []
        while !leftover.isEmpty {
            let seed = leftover.removeFirst()
            var bunch = [seed]
            var kept: [(id: String, lat: Double, lon: Double, kind: String, placed: Bool)] = []
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
                    kinds: kinds,
                    placed: bunch.allSatisfy(\.placed)
                )
            )
        }
        return out
    }

    public static func reachMeters(rssi: Int) -> Double {
        let clamped = max(-100, min(-35, rssi))
        return 50.0 + Double((-35 - clamped) * 2)
    }

    public static func bearingDegrees(id: String) -> Double {
        var hash: UInt32 = 2_166_132_261
        for byte in id.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Double(hash % 36_000) / 100.0
    }

    public static func offset(
        lat: Double,
        lon: Double,
        meters: Double,
        bearingDegrees: Double
    ) -> (lat: Double, lon: Double) {
        let r = 6_371_000.0
        let br = bearingDegrees * .pi / 180
        let p1 = lat * .pi / 180
        let ang = meters / r
        let p2 = asin(sin(p1) * cos(ang) + cos(p1) * sin(ang) * cos(br))
        let l2 = lon * .pi / 180 + atan2(
            sin(br) * sin(ang) * cos(p1),
            cos(ang) - sin(p1) * sin(p2)
        )
        return (p2 * 180 / .pi, l2 * 180 / .pi)
    }

    public static func placeHear(
        _ hear: MeshHear,
        you: (lat: Double, lon: Double)
    ) -> (id: String, lat: Double, lon: Double, kind: String, placed: Bool) {
        let dest = offset(
            lat: you.lat,
            lon: you.lon,
            meters: reachMeters(rssi: hear.rssi),
            bearingDegrees: bearingDegrees(id: hear.id)
        )
        return (hear.id, dest.lat, dest.lon, hear.kind.rawValue, false)
    }

    public static func marks(
        hears: [MeshHear],
        you: (lat: Double, lon: Double)?,
        place: Bool = false
    ) -> [Mark] {
        var placed: [(id: String, lat: Double, lon: Double, kind: String, placed: Bool)] = []
        for hear in hears {
            if let lat = hear.lat, let lon = hear.lon, lat.isFinite, lon.isFinite {
                placed.append((hear.id, lat, lon, hear.kind.rawValue, true))
                continue
            }
            if place, let you, you.lat.isFinite, you.lon.isFinite {
                placed.append(placeHear(hear, you: you))
            }
        }
        return cluster(placed)
    }

    public static func signal(was: Int?, now: Int?) -> String {
        guard let now else { return "" }
        guard let was else { return "NEAR · LIVE" }
        if now - was >= 6 { return "NEAR · LOUDER" }
        if was - now >= 6 { return "NEAR · QUIETER" }
        return ""
    }

    public struct LastFix: Equatable, Sendable {
        public var lat: Double
        public var lon: Double
        public var count: Int
        public var kinds: [String]
        public var at: Date

        public init(lat: Double, lon: Double, count: Int, kinds: [String], at: Date = Date()) {
            self.lat = lat
            self.lon = lon
            self.count = count
            self.kinds = kinds
            self.at = at
        }
    }

    public static func lasts(
        remembered: [LastFix],
        live: [Mark],
        now: Date = Date(),
        keep: TimeInterval = lastSeconds
    ) -> [Mark] {
        remembered.compactMap { point in
            if now.timeIntervalSince(point.at) > keep { return nil }
            if live.contains(where: { meters(point.lat, point.lon, $0.lat, $0.lon) <= houseMeters }) {
                return nil
            }
            return Mark(
                id: NearMark.lastID(lat: point.lat, lon: point.lon),
                lat: point.lat,
                lon: point.lon,
                count: point.count,
                kinds: point.kinds,
                placed: true
            )
        }
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
