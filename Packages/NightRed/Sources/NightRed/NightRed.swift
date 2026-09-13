import Foundation
import Tokens

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
