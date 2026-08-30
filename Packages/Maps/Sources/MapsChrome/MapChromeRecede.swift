import Foundation

/// Idle clock for Map chrome. Recedes GPS + chip row after 2s without
/// pan / zoom / tap. Reduce Motion never recedes. SOS is not part of this flag.
public struct MapChromeRecede: Equatable, Sendable {
    public static let idleInterval: TimeInterval = 2

    public var reduceMotion: Bool
    public private(set) var isReceded: Bool
    private var lastActivity: TimeInterval

    public init(reduceMotion: Bool = false, now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        self.reduceMotion = reduceMotion
        self.isReceded = false
        self.lastActivity = now
    }

    public mutating func noteActivity(at now: TimeInterval) {
        lastActivity = now
        isReceded = false
    }

    public mutating func tick(at now: TimeInterval) {
        if reduceMotion {
            isReceded = false
            return
        }
        isReceded = (now - lastActivity) >= Self.idleInterval
    }
}
