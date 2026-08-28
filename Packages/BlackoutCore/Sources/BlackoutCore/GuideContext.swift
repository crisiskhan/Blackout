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

public struct GuideQueryContext: Sendable {
    public var hour: Int
    public var elevationMeters: Double?
    public var batteryLevel: Float
    public var sosArmed: Bool
    public var partySize: Int
    public var isNight: Bool
    public var extremeSaver: Bool

    public init(
        hour: Int,
        elevationMeters: Double?,
        batteryLevel: Float,
        sosArmed: Bool,
        partySize: Int = 1,
        extremeSaver: Bool = false
    ) {
        self.hour = hour
        self.elevationMeters = elevationMeters
        self.batteryLevel = batteryLevel
        self.sosArmed = sosArmed
        self.partySize = partySize
        self.isNight = hour < 6 || hour >= 20
        self.extremeSaver = extremeSaver
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
