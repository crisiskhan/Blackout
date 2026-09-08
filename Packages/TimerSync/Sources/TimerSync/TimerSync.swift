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
    public var overdueRowID: String { "overdue:\(id)" }
}

public final class TimerBoard: @unchecked Sendable {
    public private(set) var timers: [PartyTimer] = []
    public private(set) var completed: [PartyTimer] = []
    private let box: EventLog
    public static let maxActive = 4
    public init(box: EventLog) { self.box = box }

    @discardableResult
    public func add(who: String, task: String, duration: TimeInterval, subjectAll: Bool, now: Date = Date()) -> PartyTimer? {
        let who = who.isEmpty ? "ALL" : who
        if timers.contains(where: { $0.task == task && $0.who == who }) {
            return nil
        }
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

    public func markDone(_ id: String) {
        if let t = timers.first(where: { $0.id == id }) {
            timers.removeAll { $0.id == id }
            if !completed.contains(where: { $0.id == id }) {
                completed.append(t)
            }
            box.log("timer", "DONE \(id)")
        }
    }

    public func markDoneTask(_ task: String) {
        if let t = timers.first(where: { $0.task == task }) {
            markDone(t.id)
        }
    }

    public func doneLines(id: String? = nil) -> [String] {
        let rows = id == nil ? completed : completed.filter { $0.id == id }
        var seen: [String] = []
        var lines: [String] = []
        for t in rows {
            if seen.contains(t.id) { continue }
            seen.append(t.id)
            lines.append("\(t.task) \(t.who) DONE")
        }
        return lines
    }

    public func isSOS(_ t: PartyTimer) -> Bool { false }
}
