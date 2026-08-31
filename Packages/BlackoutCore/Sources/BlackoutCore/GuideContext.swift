import Foundation

public enum GuideTopic: String, CaseIterable, Sendable, Identifiable {
    case water
    case fire
    case shelter
    case firstAid = "first-aid"
    case signaling
    case navigation
    case weather
    case foodPlants = "food-plants"
    case animals
    case tools
    case bushcraft

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .water: return "Water"
        case .fire: return "Fire"
        case .shelter: return "Shelter"
        case .firstAid: return "First aid"
        case .signaling: return "Signaling"
        case .navigation: return "Navigation"
        case .weather: return "Weather"
        case .foodPlants: return "Food / plants"
        case .animals: return "Animals"
        case .tools: return "Tools"
        case .bushcraft: return "Bushcraft"
        }
    }
}

public enum GuideBiome: String, Sendable, CaseIterable {
    case florida
    case texas
    case newMexico
    case newYork
    case southernRockies
    case unknown

    public var rankTokens: [String] {
        switch self {
        case .florida: return ["fl", "florida"]
        case .texas: return ["tx", "texas", "el-paso", "chih"]
        case .newMexico: return ["nm", "new-mexico", "chih"]
        case .newYork: return ["ny", "new-york"]
        case .southernRockies: return ["rockies", "denver", "front-range", "14er"]
        case .unknown: return []
        }
    }

    public static func infer(latitude: Double?, longitude: Double?) -> GuideBiome {
        guard let latitude, let longitude else { return .unknown }
        if latitude >= 24.4, latitude <= 31.05, longitude >= -87.65, longitude <= -79.8 {
            return .florida
        }
        if latitude >= 40.45, latitude <= 45.05, longitude >= -79.8, longitude <= -71.75 {
            return .newYork
        }
        if latitude >= 32.0, latitude <= 37.0, longitude >= -109.1, longitude <= -103.0 {
            return .newMexico
        }
        if latitude >= 31.3, latitude < 32.0, longitude >= -109.1, longitude <= -106.6 {
            return .newMexico
        }
        if latitude >= 25.8, latitude <= 36.55, longitude >= -106.65, longitude <= -93.45 {
            return .texas
        }
        if latitude >= 36.9, latitude <= 41.1, longitude >= -109.1, longitude <= -102.0 {
            return .southernRockies
        }
        return .unknown
    }
}

public struct GuideQueryContext: Sendable {
    public var hour: Int
    public var elevationMeters: Double?
    public var batteryLevel: Float
    public var sosArmed: Bool
    public var partySize: Int
    public var isNight: Bool
    public var extremeSaver: Bool
    public var month: Int
    public var latitude: Double?
    public var longitude: Double?
    public var biome: GuideBiome

    public var gpsKnown: Bool { latitude != nil && longitude != nil }

    public init(
        hour: Int,
        elevationMeters: Double?,
        batteryLevel: Float,
        sosArmed: Bool,
        partySize: Int = 1,
        extremeSaver: Bool = false,
        month: Int = 0,
        latitude: Double? = nil,
        longitude: Double? = nil,
        biome: GuideBiome? = nil
    ) {
        self.hour = hour
        self.elevationMeters = elevationMeters
        self.batteryLevel = batteryLevel
        self.sosArmed = sosArmed
        self.partySize = partySize
        self.isNight = hour < 6 || hour >= 20
        self.extremeSaver = extremeSaver
        self.month = month
        self.latitude = latitude
        self.longitude = longitude
        self.biome = biome ?? GuideBiome.infer(latitude: latitude, longitude: longitude)
    }
}

/// Field Guide home is Ask + kid chips + one step card. Not an encyclopedia wall.
public enum FieldAskHomeLock {
    public static let homeIsAskPlusChips = true
    public static let paintsEncyclopediaOnHome = false
    public static let paintsMedicalLostWallOnHome = false
    public static let paintsPackCountEssayOnHome = false
    public static let stacksAnswerCards = false
    public static let oneCardAtATime = true
    public static let stopReturnsToAsk = true
    public static let askPlaceholder = "What do you need?"
    public static let browseLabel = "Browse"
    public static let unknownCopy = "Unknown is valid. Try a chip or ask again."
    public static let homeChipTitles = [
        "Fire", "Water", "Shelter", "First aid", "Injury", "Lost", "Signaling"
    ]
    public static let skillsIsCurriculumList = true
    public static let skillsDumpsAllPlates = false

    public static func homeChipArticleID(_ title: String) -> String? {
        switch title {
        case "Fire": return "fire-when"
        case "Water": return "situation-water"
        case "Shelter": return "shelter-emergency"
        case "First aid": return "aid-scene"
        case "Injury": return "situation-injury"
        case "Lost": return "situation-lost"
        case "Signaling": return "signal-whistle"
        default: return nil
        }
    }

    public static func showsHome(hasActiveArticle: Bool, browsing: Bool) -> Bool {
        !hasActiveArticle && !browsing
    }

    public static func presentsStepPager(hitCount: Int) -> Bool {
        hitCount == 1
    }

    public static func presentsBrowse(hitCount: Int) -> Bool {
        hitCount > 1
    }

    public static func presentsUnknown(hitCount: Int) -> Bool {
        hitCount == 0
    }
}

public struct ViewshedRay: Hashable, Sendable {
    public var bearingDegrees: Double
    public var visibleMeters: Double

    public init(bearingDegrees: Double, visibleMeters: Double) {
        self.bearingDegrees = bearingDegrees
        self.visibleMeters = visibleMeters
    }
}
