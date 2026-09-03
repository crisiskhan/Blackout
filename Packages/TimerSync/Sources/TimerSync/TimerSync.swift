import Foundation
import BlackBox

public struct PartyTimer: Equatable, Sendable, Identifiable {
    public var id: String
    public var who: String
    public var task: String
    public var duration: TimeInterval
    public var started: Date
    public var subjectAllTurnaround: Bool
    public var overdue: Bool { Date().timeIntervalSince(started) > duration }
}

public final class TimerBoard: @unchecked Sendable {
    public private(set) var timers: [PartyTimer] = []
    private let box: BlackBox
    public static let maxActive = 4
    public init(box: BlackBox) { self.box = box }

    @discardableResult
    public func add(who: String, task: String, duration: TimeInterval, subjectAll: Bool, now: Date = Date()) -> PartyTimer? {
        guard timers.filter({ !$0.overdue || true }).count < Self.maxActive else { return nil }
        guard timers.count < Self.maxActive else { return nil }
        let t = PartyTimer(id: UUID().uuidString, who: who, task: task, duration: duration, started: now, subjectAllTurnaround: subjectAll)
        timers.append(t)
        box.log("timer", "\(who) \(task) \(duration)")
        return t
    }

    public func overduePlate(now: Date = Date()) -> [PartyTimer] {
        timers.filter { now.timeIntervalSince($0.started) > $0.duration }
    }

    public func isSOS(_ t: PartyTimer) -> Bool { false }
}
