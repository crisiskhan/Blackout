import Foundation

public struct Banner: Equatable, Sendable, Identifiable {
    public var id: String
    public var states: [String]
    public var title: [String: String]
}

public enum RegionalPacks {
    public static let all: [Banner] = [
        Banner(id: "hurricane", states: ["TX", "FL"], title: ["en": "Hurricane procedure + paper", "es": "Huracán: procedimiento y papel"]),
        Banner(id: "monsoon", states: ["NM"], title: ["en": "Monsoon wash", "es": "Cárcava de monzón"]),
        Banner(id: "rip", states: ["FL"], title: ["en": "Rip current", "es": "Resaca"]),
        Banner(id: "heat-island", states: ["TX", "FL"], title: ["en": "Heat island", "es": "Isla de calor"]),
        Banner(id: "ice-rock", states: ["NM", "NY"], title: ["en": "Ice on rock", "es": "Hielo en la roca"]),
        Banner(id: "border-hospitals", states: ["TX", "NM"], title: ["en": "Border hospitals", "es": "Hospitales de la frontera"]),
        Banner(id: "keys-mm", states: ["FL"], title: ["en": "Keys mile marker", "es": "Milla de los Keys"]),
        Banner(id: "subway-north", states: ["NY"], title: ["en": "Subway walk to air", "es": "Metro al aire"]),
        Banner(id: "cattle-guard", states: ["TX", "NM"], title: ["en": "Cattle guard", "es": "Paso canadiense"]),
        Banner(id: "gator-dusk", states: ["FL"], title: ["en": "Gator at dusk", "es": "Caimán al anochecer"]),
    ]

    public static func visible(state: String) -> [Banner] {
        all.filter { $0.states.contains(state) }
    }

    public static func assertNoLeaks() -> Bool {
        let fl = visible(state: "FL").map(\.id)
        let ny = visible(state: "NY").map(\.id)
        return !fl.contains("ice-rock") && !ny.contains("gator-dusk")
    }
}
