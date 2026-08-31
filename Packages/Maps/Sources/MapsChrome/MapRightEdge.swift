import Foundation

/// One right-edge stack at a time. Nav mock vs radar mock. Never both.
public enum MapRightEdge: String, Equatable, Sendable {
    case chips
    case nav

    public static func stack(routeInPlay: Bool) -> MapRightEdge {
        routeInPlay ? .nav : .chips
    }

    public static func showsBoth(routeInPlay: Bool) -> Bool {
        false
    }
}
