import Foundation
import BlackBox

public struct PackManifest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var state: String
    public var bytes: Int
    public var banners: [String]
    public var center: Coord
    public var bbox: BBox
    /// Where the canvas opens with no GPS fix. The bbox midpoint is often bare
    /// terrain; `home` is the metro slice, where the street grid is.
    public var home: Coord?
    /// The day this pack's OpenStreetMap extract was pulled, `YYYY-MM-DD`. The
    /// inspect card prints it so nobody reads a record as current when it is a
    /// year old. Optional because packs built before it existed have no honest
    /// answer, and a made-up date is worse than none.
    public var osmFetched: String?
    /// Street graph and yard NAIP. STATES is the one catalog pack that is not.
    public var walkable: Bool
    /// Flat TX+NM chart. Pinch stays on the packed outlines; WALK stays off graph.
    public var overview: Bool

    /// A struct's memberwise init is internal, so every other module could read
    /// a manifest off disk but not build one. That quietly made the map tests
    /// uncompilable, which is why they had never run.
    public init(
        id: String,
        name: String,
        state: String,
        bytes: Int,
        banners: [String],
        center: Coord,
        bbox: BBox,
        home: Coord? = nil,
        osmFetched: String? = nil,
        walkable: Bool = true,
        overview: Bool = false
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.bytes = bytes
        self.banners = banners
        self.center = center
        self.bbox = bbox
        self.home = home
        self.osmFetched = osmFetched
        self.walkable = walkable
        self.overview = overview
    }

    enum CodingKeys: String, CodingKey {
        case id, name, state, bytes, banners, center, bbox, home, osmFetched, walkable, overview
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        state = try c.decode(String.self, forKey: .state)
        bytes = try c.decode(Int.self, forKey: .bytes)
        banners = try c.decode([String].self, forKey: .banners)
        center = try c.decode(Coord.self, forKey: .center)
        bbox = try c.decode(BBox.self, forKey: .bbox)
        home = try c.decodeIfPresent(Coord.self, forKey: .home)
        osmFetched = try c.decodeIfPresent(String.self, forKey: .osmFetched)
        walkable = try c.decodeIfPresent(Bool.self, forKey: .walkable) ?? true
        overview = try c.decodeIfPresent(Bool.self, forKey: .overview) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(state, forKey: .state)
        try c.encode(bytes, forKey: .bytes)
        try c.encode(banners, forKey: .banners)
        try c.encode(center, forKey: .center)
        try c.encode(bbox, forKey: .bbox)
        try c.encodeIfPresent(home, forKey: .home)
        try c.encodeIfPresent(osmFetched, forKey: .osmFetched)
        try c.encode(walkable, forKey: .walkable)
        try c.encode(overview, forKey: .overview)
    }

    public struct Coord: Codable, Equatable, Sendable {
        public var lat: Double
        public var lon: Double
        public init(lat: Double, lon: Double) {
            self.lat = lat
            self.lon = lon
        }
    }

    public struct BBox: Codable, Equatable, Sendable {
        public var south: Double
        public var west: Double
        public var north: Double
        public var east: Double
        public init(south: Double, west: Double, north: Double, east: Double) {
            self.south = south
            self.west = west
            self.north = north
            self.east = east
        }

        public func contains(lat: Double, lon: Double) -> Bool {
            lat >= south && lat <= north && lon >= west && lon <= east
        }
    }
}

public struct PackCatalog: Codable, Equatable, Sendable {
    /// States the bundle actually carries map packs for. Absent in hand-built
    /// catalogs; the shipped one always names them.
    public var states: [String]? = nil
    public var packs: [PackManifest]

    public init(states: [String]? = nil, packs: [PackManifest]) {
        self.states = states
        self.packs = packs
    }
}

public final class PackStore: @unchecked Sendable {
    public static let defaultPackID = "tx-west"
    public static let osmAttribution = "© OpenStreetMap contributors"

    public private(set) var active: PackManifest?
    public private(set) var catalog: PackCatalog
    private let box: EventLog
    private let root: URL

    public init(root: URL, box: EventLog) throws {
        self.root = root
        self.box = box
        let data = try Data(contentsOf: root.appendingPathComponent("catalog.json"))
        let decoded = try JSONDecoder().decode(PackCatalog.self, from: data)
        // Reordering the packs must not lose the list of states we ship. It did,
        // which left `switchTo`'s region-leak check reading a nil list and
        // waving through every pack in the catalog.
        self.catalog = PackCatalog(states: decoded.states, packs: Self.preferPrimary(decoded.packs))
        self.active = catalog.packs.first(where: { $0.id == Self.defaultPackID }) ?? catalog.packs.first
    }

    public static func preferPrimary(_ packs: [PackManifest]) -> [PackManifest] {
        let primary = packs.filter { $0.id == defaultPackID }
        let rest = packs.filter { $0.id != defaultPackID }
        return primary + rest
    }

    public func switchTo(_ id: String) throws {
        guard let pack = catalog.packs.first(where: { $0.id == id }) else {
            throw PackError.missing(id)
        }
        if let shipped = catalog.states, !shipped.contains(pack.state) {
            throw PackError.regionLeak
        }
        active = pack
        box.log("pack", "switched \(id) bytes=\(pack.bytes)")
    }

    public func packRoot(id: String) -> URL {
        root.appendingPathComponent(id)
    }

    public func packURL(_ file: String) -> URL? {
        guard let active else { return nil }
        return packRoot(id: active.id).appendingPathComponent(file)
    }

    public func homeCoordinate() -> (lat: Double, lon: Double)? {
        guard let active else { return nil }
        let point = active.home ?? active.center
        return (point.lat, point.lon)
    }

    /// Where the active pack keeps its routing graph. `graph.bin` is what the
    /// packs ship; the JSON name is only still looked for so an older pack
    /// sitting on a phone keeps routing.
    public func graphURL() -> URL? {
        guard let id = active?.id else { return nil }
        return graphURL(for: id)
    }

    public func graphURL(for packID: String) -> URL? {
        let binary = packRoot(id: packID).appendingPathComponent("graph.bin")
        let fm = FileManager.default
        if fm.fileExists(atPath: binary.path) { return binary }
        let legacy = packRoot(id: packID).appendingPathComponent("graph.json")
        guard fm.fileExists(atPath: legacy.path) else { return binary }
        return legacy
    }

    public func hasUsableGraph() -> Bool {
        guard let url = graphURL() else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return false }
        return GraphProbe.isUsable(byteCount: size.intValue)
    }

    public func realSize(of id: String) -> Int? {
        catalog.packs.first(where: { $0.id == id })?.bytes
    }

    /// Metro under a STATES tap or SEARCH pin. Overview itself never wins.
    public func walkablePack(at lat: Double, lon: Double) -> PackManifest? {
        catalog.packs.first { pack in
            pack.walkable && !pack.overview && pack.bbox.contains(lat: lat, lon: lon)
        }
    }
}

public enum GraphProbe: Sendable {
    /// `{"edges":[]}` is 12 bytes. One test edge is ~57. Shipped TX WEST is ~4.5MB.
    public static let emptyMaxBytes = 32

    public static func isUsable(byteCount: Int) -> Bool {
        byteCount > emptyMaxBytes
    }
}

public enum PackError: Error, Equatable { case missing(String); case regionLeak }
