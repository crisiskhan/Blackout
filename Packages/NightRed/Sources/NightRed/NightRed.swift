import Foundation
import Tokens

public struct NightRedState: Equatable, Sendable {
    public var enabled: Bool
    public init(enabled: Bool) { self.enabled = enabled }
    public var filter: BlackoutTokens.RGBA {
        enabled ? BlackoutTokens.Color.nightRed : BlackoutTokens.Color.void
    }
}
