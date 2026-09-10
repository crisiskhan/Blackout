import Foundation

public enum ConditionBand: String, Sendable { case green, yellow, red }

public struct PartyVitals: Equatable, Sendable {
    /// Band edges and the ticks on the EXPEDITION rails. One source.
    public static let yellowAt: Double = 0.45
    public static let redAt: Double = 0.8
    public static let railSteps: [Double] = [0, 0.2, 0.45, 0.8, 1.0]

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
        Self.band(worst: [hunger, thirst, pain, water, fatigue, weatherExposure].max() ?? 0, flags: flags)
    }

    public static func band(worst: Double, flags: [String]) -> ConditionBand {
        if flags.contains("RED") || worst >= redAt { return .red }
        if worst >= yellowAt { return .yellow }
        return .green
    }

    /// Midpoint and above belongs to the worse tick, so CONDITION never sits between bands.
    public static func snap(_ raw: Double) -> Double {
        let clamped = min(1, max(0, raw))
        let steps = railSteps
        for i in 0..<(steps.count - 1) {
            let mid = (steps[i] + steps[i + 1]) / 2
            if clamped < mid {
                return steps[i]
            }
        }
        return steps[steps.count - 1]
    }

    public static func step(_ current: Double, _ delta: Int) -> Double {
        let steps = railSteps
        let snapped = snap(current)
        guard let i = steps.firstIndex(of: snapped) else { return snapped }
        let j = min(steps.count - 1, max(0, i + delta))
        return steps[j]
    }
}
