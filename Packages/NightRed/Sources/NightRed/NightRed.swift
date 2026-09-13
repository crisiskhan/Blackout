import Foundation
import Tokens

public enum HUDLamp: String, Sendable, Equatable, CaseIterable {
    case off
    case night
    case sun

    public static func toggling(current: HUDLamp, tap: HUDLamp) -> HUDLamp {
        switch tap {
        case .off:
            return .off
        case .night, .sun:
            return current == tap ? .off : tap
        }
    }

    public var nightOn: Bool {
        switch self {
        case .night: return true
        case .off, .sun: return false
        }
    }

    public var sunOn: Bool {
        switch self {
        case .sun: return true
        case .off, .night: return false
        }
    }
}

public struct NightRedState: Equatable, Sendable {
    public var enabled: Bool
    public init(enabled: Bool) { self.enabled = enabled }

    /// Multiply ink. White when the lamp is off so the modifier can stay
    /// on the tree (MapLibre stays mounted).
    public var filter: BlackoutTokens.RGBA { multiply }

    public var multiply: BlackoutTokens.RGBA {
        enabled ? BlackoutTokens.Color.nightRed : Self.identity
    }

    public static let identity = BlackoutTokens.RGBA(r: 1, g: 1, b: 1, a: 1)

    /// Pull brightness down so rods stay adapted. Void stays void.
    public static let dim: Double = -0.04
}
