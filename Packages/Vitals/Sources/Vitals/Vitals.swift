import Foundation

public enum ConditionBand: String, CaseIterable, Sendable {
    case green, yellow, orange, red
}

public struct PartyVitals: Equatable, Sendable {
    /// Band edges and the ticks on the EXPEDITION rails. One source.
    public static let yellowAt: Double = 0.45
    public static let orangeAt: Double = 0.65
    public static let redAt: Double = 0.8
    /// Two YELLOW rails is CONDITION ORANGE, not a yellow average.
    public static let stackYellowToOrange: Int = 2
    /// Three YELLOW rails is a compounding body.
    public static let stackYellowToRed: Int = 3
    /// Two ORANGE rails is CONDITION RED.
    public static let stackOrangeToRed: Int = 2
    public static let yellowLoad: Int = 1
    public static let orangeLoad: Int = 2
    public static let redLoad: Int = 3
    public static let railSteps: [Double] = [0, 0.2, 0.45, 0.65, 0.8, 1.0]

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

    public var rails: [Double] {
        [hunger, thirst, pain, water, fatigue, weatherExposure]
    }

    public var band: ConditionBand {
        Self.band(rails: rails, flags: flags)
    }

    public static func band(of value: Double) -> ConditionBand {
        if value >= redAt { return .red }
        if value >= orangeAt { return .orange }
        if value >= yellowAt { return .yellow }
        return .green
    }

    /// YELLOW is 1, ORANGE is 2, RED is 3. Load 2 is ORANGE. Load 3 is RED.
    public static func load(of value: Double) -> Int {
        switch band(of: value) {
        case .green:
            return 0
        case .yellow:
            return yellowLoad
        case .orange:
            return orangeLoad
        case .red:
            return redLoad
        }
    }

    public static func band(rails: [Double], flags: [String] = []) -> ConditionBand {
        if flags.contains("RED") { return .red }
        var total = 0
        for value in rails {
            let piece = load(of: value)
            if piece >= redLoad { return .red }
            total += piece
        }
        if total >= stackYellowToRed { return .red }
        if total >= stackYellowToOrange { return .orange }
        if total > 0 { return .yellow }
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

    /// POS carries six snapped ticks. Old peers with no rails parse as nil.
    public static func fromPOS(_ rails: [Double]?) -> PartyVitals? {
        guard let rails, rails.count == 6 else { return nil }
        return PartyVitals(
            hunger: snap(rails[0]),
            thirst: snap(rails[1]),
            pain: snap(rails[2]),
            water: snap(rails[3]),
            fatigue: snap(rails[4]),
            weatherExposure: snap(rails[5])
        )
    }

    public var posRails: [Double] {
        rails.map { Self.snap($0) }
    }
}
