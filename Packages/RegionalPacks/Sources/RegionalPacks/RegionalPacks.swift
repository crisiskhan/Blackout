import Foundation

public struct Banner: Equatable, Sendable, Identifiable {
    public var id: String
    public var states: [String]
    public var title: [String: String]

    public init(id: String, states: [String], title: [String: String]) {
        self.id = id
        self.states = states
        self.title = title
    }
}

public enum RegionalPacks {
    /// Ground the vessel carries a map pack for. A banner anywhere else is
    /// advice with no map behind it.
    public static let shippedStates = ["TX", "NM"]

    public static let all: [Banner] = [
        Banner(id: "hurricane", states: ["TX"], title: ["en": "Hurricane procedure + paper", "es": "Huracán: procedimiento y papel"]),
        Banner(id: "monsoon", states: ["NM"], title: ["en": "Monsoon wash", "es": "Cárcava de monzón"]),
        Banner(id: "heat-island", states: ["TX"], title: ["en": "Heat island", "es": "Isla de calor"]),
        Banner(id: "ice-rock", states: ["NM"], title: ["en": "Ice on rock", "es": "Hielo en la roca"]),
        Banner(id: "border-hospitals", states: ["TX", "NM"], title: ["en": "Border hospitals", "es": "Hospitales de la frontera"]),
        Banner(id: "cattle-guard", states: ["TX", "NM"], title: ["en": "Cattle guard", "es": "Paso canadiense"]),
    ]

    public static func visible(state: String) -> [Banner] {
        all.filter { $0.states.contains(state) }
    }

    /// No banner may claim ground we ship no pack for, and no shipped state may
    /// come up empty.
    public static func assertNoLeaks() -> Bool {
        let shipped = Set(shippedStates)
        let scoped = all.allSatisfy { !$0.states.isEmpty && Set($0.states).isSubset(of: shipped) }
        return scoped && shippedStates.allSatisfy { !visible(state: $0).isEmpty }
    }
}
