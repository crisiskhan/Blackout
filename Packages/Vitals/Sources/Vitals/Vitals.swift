import Foundation

public enum ConditionBand: String, Sendable { case green, yellow, red }

public struct PartyVitals: Equatable, Sendable {
    public var hunger: Double
    public var thirst: Double
    public var pain: Double
    public var water: Double
    public var fatigue: Double
    public var weatherExposure: Double
    public var flags: [String]
    public init(
        hunger: Double = 0.2,
        thirst: Double = 0.2,
        pain: Double = 0.2,
        water: Double,
        fatigue: Double,
        weatherExposure: Double,
        flags: [String] = []
    ) {
        self.hunger = hunger
        self.thirst = thirst
        self.pain = pain
        self.water = water
        self.fatigue = fatigue
        self.weatherExposure = weatherExposure
        self.flags = flags
    }

    public var band: ConditionBand {
        let worst = [hunger, thirst, pain, water, fatigue, weatherExposure].max() ?? 0
        if flags.contains("RED") || worst >= 0.8 { return .red }
        if worst >= 0.45 { return .yellow }
        return .green
    }
}
