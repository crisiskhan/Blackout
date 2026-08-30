import Foundation

/// `blackout-routing-v1` on-disk contract. Reader only — packs supply the bytes.
public enum RoutingLayout {
    public static let format = "blackout-routing-v1"
    public static let graphMagic = "BLRG0001"
    public static let namesMagic = "BLNM0001"
    public static let geometryMagic = "BLGM0001"
    public static let headerBytes = 16
    public static let nodeStride = 8
    public static let edgeStride = 26
    public static let defaultManifestKey = "routing/routing.json"

    public static let walkFlag: UInt16 = 1 << 0
    public static let driveFlag: UInt16 = 1 << 1
    public static let onewayFlag: UInt16 = 1 << 2

    public static func graphByteCount(nodes: Int, edges: Int) -> Int {
        headerBytes + nodes * nodeStride + edges * edgeStride
    }

    /// El Paso Field Pack facts. Not a bundled graph.
    public enum ElPaso {
        public static let packId = "us-tx-el-paso"
        public static let west = -106.885
        public static let south = 31.3619
        public static let east = -106.085
        public static let north = 32.1619
        public static let centerLat = 31.7619
        public static let centerLon = -106.485
        public static let nodeCount = 237_279
        public static let edgeCount = 335_665
        public static let walkEdgeCount = 333_626
        public static let driveEdgeCount = 289_072
        public static let onewayEdgeCount = 52_285
        public static let nameCount = 23_772
        public static let graphBytes = 10_625_538
        public static let namesBytes = 446_213
        public static let geometryBytes = 9_605_206
        public static let graphSHA256 = "2ac6f58c09d5d83f5a9f8ac791d37e81777922db4445a1672f4ecaeef6561917"
        public static let namesSHA256 = "21309ce4559fe2e6b7fc3af7798e3a91e387222bab79959e1fabf0ac023a2ffc"
        public static let geometrySHA256 = "7b2edbfebdc165634a4cb6e6104f4b7bdea30c2ffef92725eadc6bc2bcb97097"
    }
}

public enum NavigateProfile: String, Sendable, CaseIterable {
    case walk
    case drive

    public var allowsWalk: Bool {
        switch self {
        case .walk: return true
        case .drive: return false
        }
    }

    public func allows(_ flags: UInt16) -> Bool {
        switch self {
        case .walk: return flags & RoutingLayout.walkFlag != 0
        case .drive: return flags & RoutingLayout.driveFlag != 0
        }
    }

    public func costMs(_ edge: RoutingEdge) -> Int {
        switch self {
        case .walk: return Int(edge.walkMs)
        case .drive: return Int(edge.driveMs)
        }
    }

    public var snapMeters: Double {
        switch self {
        case .walk: return 75
        case .drive: return 150
        }
    }
}

public enum NavigateCopy {
    public static let noGraphTitle = "No turns in this pack."
    public static let noGraphBody = "El Paso pack has routing; this pack does not."
    public static let offGraph = "Off pack. Bearing to destination."
    public static let searchMiss = "No matches in this pack."
    public static let noGPS = "No GPS."
    public static let bearingOnly = "Bearing only"
    public static let packManager = "Pack manager"
}

public enum MapEmptyCopy {
    public static let eyebrow = "MAP"
    public static let noPack = "No pack for this area"
    public static let noTurns = "No turns for this area"
    public static let noCivilization = "No civilization in this pack"
    public static let noWater = "No water mapped here"
}

public enum MapEmptyKind: Equatable, Sendable {
    case noPack
    case noTurns
    case noCivilization
    case noWater

    public var title: String {
        switch self {
        case .noPack: return MapEmptyCopy.noPack
        case .noTurns: return MapEmptyCopy.noTurns
        case .noCivilization: return MapEmptyCopy.noCivilization
        case .noWater: return MapEmptyCopy.noWater
        }
    }
}

public enum NavigateEmpty: Equatable, Sendable {
    case noGraph
    case offGraph
    case searchMiss
    case noGPS
    case noCivilization
    case noWater

    public var title: String {
        switch self {
        case .noGraph: return NavigateCopy.noGraphTitle
        case .offGraph: return NavigateCopy.offGraph
        case .searchMiss: return NavigateCopy.searchMiss
        case .noGPS: return NavigateCopy.noGPS
        case .noCivilization: return MapEmptyCopy.noCivilization
        case .noWater: return MapEmptyCopy.noWater
        }
    }

    public var body: String? {
        switch self {
        case .noGraph: return NavigateCopy.noGraphBody
        case .offGraph, .searchMiss, .noGPS, .noCivilization, .noWater: return nil
        }
    }

    public var mapKind: MapEmptyKind? {
        switch self {
        case .noGraph: return .noTurns
        case .noCivilization: return .noCivilization
        case .noWater: return .noWater
        case .offGraph, .searchMiss, .noGPS: return nil
        }
    }
}

public struct RoutingCoordinate: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(latE7: Int32, lonE7: Int32) {
        self.latitude = Double(latE7) / 10_000_000
        self.longitude = Double(lonE7) / 10_000_000
    }

    public var latE7: Int32 { Int32((latitude * 10_000_000).rounded()) }
    public var lonE7: Int32 { Int32((longitude * 10_000_000).rounded()) }
}

public struct RoutingBBox: Hashable, Sendable {
    public var west: Double
    public var south: Double
    public var east: Double
    public var north: Double

    public init(west: Double, south: Double, east: Double, north: Double) {
        self.west = west
        self.south = south
        self.east = east
        self.north = north
    }

    public func contains(_ coordinate: RoutingCoordinate) -> Bool {
        coordinate.longitude >= west && coordinate.longitude <= east
            && coordinate.latitude >= south && coordinate.latitude <= north
    }

    public var area: Double {
        max(east - west, 0) * max(north - south, 0)
    }
}

public struct RoutingManifest: Hashable, Sendable {
    public var format: String
    public var profiles: [NavigateProfile]
    public var bbox: RoutingBBox
    public var nodeCount: Int
    public var edgeCount: Int
    public var walkEdgeCount: Int?
    public var driveEdgeCount: Int?
    public var onewayEdgeCount: Int?
    public var nameCount: Int?
    public var bidirectionalIfNotOneway: Bool
    public var attribution: String?
    public var packId: String?
    public var checksums: [String: String]

    public init(
        format: String,
        profiles: [NavigateProfile],
        bbox: RoutingBBox,
        nodeCount: Int,
        edgeCount: Int,
        walkEdgeCount: Int? = nil,
        driveEdgeCount: Int? = nil,
        onewayEdgeCount: Int? = nil,
        nameCount: Int? = nil,
        bidirectionalIfNotOneway: Bool = true,
        attribution: String? = nil,
        packId: String? = nil,
        checksums: [String: String] = [:]
    ) {
        self.format = format
        self.profiles = profiles
        self.bbox = bbox
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.walkEdgeCount = walkEdgeCount
        self.driveEdgeCount = driveEdgeCount
        self.onewayEdgeCount = onewayEdgeCount
        self.nameCount = nameCount
        self.bidirectionalIfNotOneway = bidirectionalIfNotOneway
        self.attribution = attribution
        self.packId = packId
        self.checksums = checksums
    }
}

public struct RoutingNode: Hashable, Sendable {
    public var lonE7: Int32
    public var latE7: Int32

    public var coordinate: RoutingCoordinate {
        RoutingCoordinate(latE7: latE7, lonE7: lonE7)
    }
}

public struct RoutingEdge: Hashable, Sendable {
    public var from: UInt32
    public var to: UInt32
    public var nameId: UInt32
    public var flags: UInt16
    public var lengthCm: UInt32
    public var walkMs: UInt32
    public var driveMs: UInt32

    public var allowsWalk: Bool { flags & RoutingLayout.walkFlag != 0 }
    public var allowsDrive: Bool { flags & RoutingLayout.driveFlag != 0 }
    public var isOneway: Bool { flags & RoutingLayout.onewayFlag != 0 }
}

public struct RoutingArc: Hashable, Sendable {
    public var edgeIndex: Int
    public var toward: UInt32
    public var reverse: Bool
}

public struct RoutingPOI: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var coordinate: RoutingCoordinate

    public init(id: String, name: String, kind: String, coordinate: RoutingCoordinate) {
        self.id = id
        self.name = name
        self.kind = kind
        self.coordinate = coordinate
    }
}

public struct PackSearchHit: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var kind: String
    public var coordinate: RoutingCoordinate
    public var meters: Double?

    public init(
        id: String,
        title: String,
        kind: String,
        coordinate: RoutingCoordinate,
        meters: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.coordinate = coordinate
        self.meters = meters
    }
}

public enum ManeuverKind: String, Sendable {
    case depart
    case arrive
    case left
    case right
    case slightLeft
    case slightRight
    case uTurn
    case straight
}

public struct Maneuver: Hashable, Sendable {
    public var kind: ManeuverKind
    public var streetName: String?
    public var distanceMeters: Double
    public var coordinate: RoutingCoordinate
}

public struct Route: Hashable, Sendable {
    public var profile: NavigateProfile
    public var distanceMeters: Double
    public var etaSeconds: Double
    public var nodeIds: [UInt32]
    public var edgeIndexes: [Int]
    public var reversed: [Bool]
    public var polyline: [RoutingCoordinate]
    public var maneuvers: [Maneuver]
}

public enum RouteOutcome: Equatable, Hashable, Sendable {
    case noGraph
    case offGraph
    case routed(Route)

    public var route: Route? {
        if case .routed(let route) = self { return route }
        return nil
    }
}

public struct GuidanceTick: Hashable, Sendable {
    public var remainingMeters: Double
    public var etaSeconds: Double
    public var nextManeuver: Maneuver?
    public var distanceToTurnMeters: Double
    public var offRoute: Bool
    public var reroute: RouteOutcome?
}
