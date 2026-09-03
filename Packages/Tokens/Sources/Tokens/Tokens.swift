import Foundation

public enum BlackoutTokens: Sendable {
    public enum Chrome {
        public static let sosDiameter: Double = 56
        public static let sosHoldMs: Int = 800
        public static let tabCount: Int = 4
        public static let dynamicTypeCap: String = "xxxLarge"
        public static let oneThumbGutter: Double = 16
    }

    public enum Color {
        public static let void = RGBA(r: 0.05, g: 0.06, b: 0.07, a: 1)
        public static let raised = RGBA(r: 0.09, g: 0.10, b: 0.12, a: 1)
        public static let metal = RGBA(r: 0.77, g: 0.80, b: 0.84, a: 1)
        public static let silverEdge = RGBA(r: 0.55, g: 0.58, b: 0.62, a: 1)
        public static let sos = RGBA(r: 0.86, g: 0.14, b: 0.14, a: 1)
        public static let nightRed = RGBA(r: 0.55, g: 0.05, b: 0.05, a: 1)
    }

    public struct RGBA: Equatable, Sendable {
        public var r, g, b, a: Double
        public init(r: Double, g: Double, b: Double, a: Double) {
            self.r = r; self.g = g; self.b = b; self.a = a
        }
    }

    public enum Tab: String, CaseIterable, Sendable {
        case map, comms, field, expedition
    }

    public static func conditionOnPipOnly(_ raw: String) -> Bool {
        raw == "pip"
    }
}
