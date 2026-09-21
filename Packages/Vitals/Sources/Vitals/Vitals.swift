import Foundation

public enum ConditionBand: String, CaseIterable, Sendable {
    case green, yellow, orange, red, black
}

public struct PartyVitals: Equatable, Sendable {
    /// Band edges and the ticks on the EXPEDITION rails. One source.
    public static let yellowAt: Double = 0.45
    public static let orangeAt: Double = 0.65
    public static let redAt: Double = 0.8
    /// The fifth CONDITION color. Past RED. Mesh SOS, not a phone dial.
    public static let blackAt: Double = 1.0
    /// Three YELLOW rails is CONDITION ORANGE. Two stay YELLOW.
    public static let stackYellowToOrange: Int = 3
    /// Every rail YELLOW is CONDITION RED.
    public static let stackYellowToRed: Int = 5
    /// Two ORANGE rails is CONDITION RED.
    public static let stackOrangeToRed: Int = 2
    /// One ORANGE plus two YELLOW is CONDITION RED. One plus one stays ORANGE.
    public static let stackOrangeAndYellowToRed: Int = 2
    public static let yellowLoad: Int = 1
    public static let orangeLoad: Int = 2
    public static let redLoad: Int = 3
    public static let blackLoad: Int = 4
    public static let railSteps: [Double] = [0, 0.2, 0.45, 0.65, 0.8, 1.0]
    /// Five color cells on the CONDITION menu. 0 stays a step below GREEN.
    public static let colorSteps: [Double] = [0.2, 0.45, 0.65, 0.8, 1.0]
    public static let railTitles: [String] = [
        "HUNGER", "THIRST", "PAIN", "FATIGUE", "EXPOSURE",
    ]

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
        [hunger, thirst, pain, fatigue, weatherExposure]
    }

    public var band: ConditionBand {
        Self.band(rails: rails, flags: flags)
    }

    public static func band(of value: Double) -> ConditionBand {
        if value >= blackAt { return .black }
        if value >= redAt { return .red }
        if value >= orangeAt { return .orange }
        if value >= yellowAt { return .yellow }
        return .green
    }

    /// YELLOW is 1, ORANGE is 2, RED is 3, BLACK is 4. Load 2 is ORANGE. Load 3 is RED.
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
        case .black:
            return blackLoad
        }
    }

    public static func band(rails: [Double], flags: [String] = []) -> ConditionBand {
        if rails.contains(where: { band(of: $0) == .black }) { return .black }
        if flags.contains("RED") { return .red }
        var yellow = 0
        var orange = 0
        var red = 0
        for value in rails {
            switch band(of: value) {
            case .black:
                return .black
            case .red:
                red += 1
            case .orange:
                orange += 1
            case .yellow:
                yellow += 1
            case .green:
                break
            }
        }
        if red >= 1 { return .red }
        if orange >= stackOrangeToRed { return .red }
        if orange >= 1 && yellow >= stackOrangeAndYellowToRed { return .red }
        if orange >= 1 { return .orange }
        if yellow >= stackYellowToRed { return .red }
        if yellow >= stackYellowToOrange { return .orange }
        if yellow >= 1 { return .yellow }
        return .green
    }

    public var blackTitles: [String] {
        zip(Self.railTitles, rails).compactMap { title, value in
            PartyVitals.band(of: value) == .black ? title : nil
        }
    }

    /// Party-wide SOS line: condition, coordinates, bearing. Mesh note, not a phone call.
    public func partyAlertLine(coordinates: String, bearing: String) -> String {
        let titles = blackTitles
        let condition: String
        if titles.count == 1 {
            condition = "\(titles[0]) BLACK"
        } else {
            condition = "CONDITION BLACK"
        }
        return "SOS \(condition) \(coordinates) \(bearing)"
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
        [hunger, thirst, pain, water, fatigue, weatherExposure].map { Self.snap($0) }
    }
}
