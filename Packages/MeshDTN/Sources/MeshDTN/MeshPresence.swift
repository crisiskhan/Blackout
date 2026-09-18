import Foundation

/// A heard radio. Discovery is not a peer. Hop is a Blackout carry.
public struct MeshHear: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: Kind
    public var rssi: Int
    public var manufacturer: UInt16?
    public var services: [String]
    public var txPower: Int?
    public var connectable: Bool?
    public var lat: Double?
    public var lon: Double?
    public var heardAt: Date

    public enum Kind: String, Sendable {
        case apple, samsung, hop, device
    }

    public init(
        id: String,
        name: String = "",
        kind: Kind,
        rssi: Int = 0,
        manufacturer: UInt16? = nil,
        services: [String] = [],
        txPower: Int? = nil,
        connectable: Bool? = nil,
        lat: Double? = nil,
        lon: Double? = nil,
        heardAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.rssi = rssi
        self.manufacturer = manufacturer
        self.services = services
        self.txPower = txPower
        self.connectable = connectable
        self.lat = lat
        self.lon = lon
        self.heardAt = heardAt
    }
}

/// One heard radio on the hold glass. Empty strings are omitted, never guessed.
public struct NearRadio: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var rssi: String
    public var reach: String
    public var radio: String
    public var maker: String
    public var link: String
    public var tx: String
    public var hop: Bool

    public init(
        id: String,
        name: String,
        kind: String,
        rssi: String = "",
        reach: String = "",
        radio: String = "",
        maker: String = "",
        link: String = "",
        tx: String = "",
        hop: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.rssi = rssi
        self.reach = reach
        self.radio = radio
        self.maker = maker
        self.link = link
        self.tx = tx
        self.hop = hop
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
    public var radios: [NearRadio]

    public init(
        id: String,
        lat: Double,
        lon: Double,
        count: Int,
        kinds: [String],
        placed: Bool = true,
        last: Bool = false,
        signal: String = "",
        radios: [NearRadio] = []
    ) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.count = count
        self.kinds = kinds
        self.placed = placed
        self.last = last
        self.signal = signal
        self.radios = radios
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
        public var radios: [NearRadio]

        public init(
            id: String,
            lat: Double,
            lon: Double,
            count: Int,
            kinds: [String],
            placed: Bool = true,
            radios: [NearRadio] = []
        ) {
            self.id = id
            self.lat = lat
            self.lon = lon
            self.count = count
            self.kinds = kinds
            self.placed = placed
            self.radios = radios
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

    public static func radioToken(_ id: String) -> String {
        let compact = id.uppercased().filter { $0.isLetter || $0.isNumber }
        if compact.count >= 4 {
            return String(compact.suffix(4))
        }
        return compact.isEmpty ? "—" : compact
    }

    public static func makerWord(_ manufacturer: UInt16?) -> String {
        guard let manufacturer else { return "" }
        switch manufacturer {
        case 0x004C:
            return "APPLE"
        case 0x0075:
            return "SAMSUNG"
        default:
            return String(format: "%04X", manufacturer)
        }
    }

    public static func kindWord(name: String, kind: MeshHear.Kind, services: [String]) -> String {
        if accessory(name: name, services: services) {
            return "ACCESSORY"
        }
        switch kind {
        case .apple:
            return "IPHONE"
        case .samsung:
            return "SAMSUNG"
        case .hop:
            return "HOP"
        case .device:
            return "DEVICE"
        }
    }

    public static func rssiWord(_ rssi: Int) -> String {
        guard rssi > -120, rssi < 0 else { return "" }
        return "−\(abs(rssi))"
    }

    public static func radio(from hear: MeshHear) -> NearRadio {
        let name = MeshPOS.nameToken(hear.name)
        let rssi = rssiWord(hear.rssi)
        let hop = hear.kind == .hop || hear.services.contains(where: { $0.lowercased() == "hop" })
        var link = ""
        if let connectable = hear.connectable {
            link = connectable ? "CONNECTABLE" : "CLOSED"
        }
        var tx = ""
        if let power = hear.txPower {
            tx = power < 0 ? "−\(abs(power))" : "\(power)"
        }
        return NearRadio(
            id: hear.id,
            name: name.isEmpty ? "UNNAMED" : name,
            kind: kindWord(name: hear.name, kind: hear.kind, services: hear.services),
            rssi: rssi,
            reach: rssi.isEmpty ? "" : "\(Int(reachMeters(rssi: hear.rssi).rounded())) M",
            radio: radioToken(hear.id),
            maker: makerWord(hear.manufacturer),
            link: link,
            tx: tx,
            hop: hop
        )
    }

    public static func cluster(
        _ points: [(id: String, lat: Double, lon: Double, kind: String)],
        radiusMeters: Double = houseMeters
    ) -> [Mark] {
        cluster(
            points.map {
                (
                    MeshHear(id: $0.id, kind: MeshHear.Kind(rawValue: $0.kind) ?? .device),
                    lat: $0.lat,
                    lon: $0.lon,
                    placed: true
                )
            },
            radiusMeters: radiusMeters
        )
    }

    public static func cluster(
        _ points: [(id: String, lat: Double, lon: Double, kind: String, placed: Bool)],
        radiusMeters: Double = houseMeters
    ) -> [Mark] {
        cluster(
            points.map {
                (
                    MeshHear(id: $0.id, kind: MeshHear.Kind(rawValue: $0.kind) ?? .device),
                    lat: $0.lat,
                    lon: $0.lon,
                    placed: $0.placed
                )
            },
            radiusMeters: radiusMeters
        )
    }

    public static func cluster(
        _ points: [(MeshHear, lat: Double, lon: Double, placed: Bool)],
        radiusMeters: Double = houseMeters
    ) -> [Mark] {
        var leftover = points.sorted { $0.0.id < $1.0.id }
        var out: [Mark] = []
        while !leftover.isEmpty {
            let seed = leftover.removeFirst()
            var bunch = [seed]
            var kept: [(MeshHear, lat: Double, lon: Double, placed: Bool)] = []
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
            for point in bunch {
                let kind = point.0.kind.rawValue
                if !kind.isEmpty && !kinds.contains(kind) {
                    kinds.append(kind)
                }
            }
            out.append(
                Mark(
                    id: NearMark.canvasID(lat: lat, lon: lon),
                    lat: lat,
                    lon: lon,
                    count: bunch.count,
                    kinds: kinds,
                    placed: bunch.allSatisfy(\.placed),
                    radios: bunch.map { radio(from: $0.0) }
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
        var placed: [(MeshHear, lat: Double, lon: Double, placed: Bool)] = []
        for hear in hears {
            if let lat = hear.lat, let lon = hear.lon, lat.isFinite, lon.isFinite {
                placed.append((hear, lat, lon, true))
                continue
            }
            if place, let you, you.lat.isFinite, you.lon.isFinite {
                let dest = offset(
                    lat: you.lat,
                    lon: you.lon,
                    meters: reachMeters(rssi: hear.rssi),
                    bearingDegrees: bearingDegrees(id: hear.id)
                )
                placed.append((hear, dest.lat, dest.lon, false))
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
