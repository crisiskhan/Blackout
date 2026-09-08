import Foundation

/// Idle clock for Map chrome. Recedes GPS + chips (incl. §10.4 56h vitals) +
/// scale bar after 2s without pan / zoom / tap. Hold (sheets, dest, deny, live
/// Rec, SOS) and Reduce Motion keep chrome static. SOS FAB is not part of this flag.
public struct MapChromeRecede: Equatable, Sendable {
    public static let idleInterval: TimeInterval = 2
    /// DS §10.3 motion.move
    public static let fadeDuration: TimeInterval = 0.220
    /// DS §10.3 motion.snap
    public static let restoreDuration: TimeInterval = 0.120

    public var reduceMotion: Bool
    public var hold: Bool
    public private(set) var isReceded: Bool
    /// I’m-OK chip and HUD stay when Reduce Motion is on, even if idle already receded.
    public var shouldHide: Bool { isReceded && !reduceMotion }
    private var lastActivity: TimeInterval

    public init(
        reduceMotion: Bool = false,
        hold: Bool = false,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) {
        self.reduceMotion = reduceMotion
        self.hold = hold
        self.isReceded = false
        self.lastActivity = now
    }

    public mutating func noteActivity(at now: TimeInterval) {
        lastActivity = now
        isReceded = false
    }

    public mutating func tick(at now: TimeInterval) {
        if reduceMotion || hold {
            isReceded = false
            if hold {
                lastActivity = now
            }
            return
        }
        isReceded = (now - lastActivity) >= Self.idleInterval
    }
}

/// Honest round numbers for the receding scale bar. Not painted on tiles.
public enum MapScaleBarMath {
    public static let steps: [Double] = [
        5, 10, 20, 50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000, 50_000
    ]

    public static func niceMeters(metersPerPoint: Double, targetPoints: Double = 80) -> Double {
        let raw = max(metersPerPoint, 0.001) * targetPoints
        return steps.last(where: { $0 <= raw }) ?? steps.first!
    }

    public static func metersPerPoint(latitude: Double, zoom: Double) -> Double {
        156_543.03392 * cos(latitude * .pi / 180) / pow(2.0, zoom)
    }
}
