import Foundation

public enum ConditionBand: String, Sendable { case green, yellow, red }

public struct PartyVitals: Equatable, Sendable {
    public var water: Double
    public var fatigue: Double
    public var weatherExposure: Double
    public var flags: [String]
    public init(water: Double, fatigue: Double, weatherExposure: Double, flags: [String] = []) {
        self.water = water; self.fatigue = fatigue; self.weatherExposure = weatherExposure; self.flags = flags
    }

    public var band: ConditionBand {
        let worst = max(water, max(fatigue, weatherExposure))
        if flags.contains("RED") || worst >= 0.8 { return .red }
        if worst >= 0.45 { return .yellow }
        return .green
    }
}
