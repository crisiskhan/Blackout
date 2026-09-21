import Foundation
import BlackBox

/// Typed TIME on EXPEDITION. Minutes unless the field ends in H / HR / HRS.
public enum TimerDuration {
    public static func parse(_ raw: String) -> TimeInterval? {
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .uppercased()
        guard !body.isEmpty else { return nil }
        let hours: Bool
        if body.hasSuffix("HRS") {
            body = String(body.dropLast(3))
            hours = true
        } else if body.hasSuffix("MINS") {
            body = String(body.dropLast(4))
            hours = false
        } else if body.hasSuffix("MIN") {
            body = String(body.dropLast(3))
            hours = false
        } else if body.hasSuffix("HR") {
            body = String(body.dropLast(2))
            hours = true
        } else if body.hasSuffix("H") {
            body = String(body.dropLast())
            hours = true
        } else if body.hasSuffix("M") {
            body = String(body.dropLast())
            hours = false
        } else {
            hours = false
        }
        guard let value = Double(body), value.isFinite, value > 0 else { return nil }
        return hours ? value * 3600 : value * 60
    }

    public static func label(_ duration: TimeInterval) -> String {
        let secs = Int(duration.rounded())
        if secs >= 3600, secs % 3600 == 0 {
            let hours = secs / 3600
            return hours == 1 ? "1 HR" : "\(hours) HR"
        }
        let minutes = max(1, Int((duration / 60.0).rounded()))
        return minutes == 1 ? "1 MIN" : "\(minutes) MIN"
    }
}

public struct PartyTimer: Equatable, Sendable, Identifiable, Codable {
    public var id: String
    public var who: String
    public var task: String
    public var duration: TimeInterval
    public var started: Date
    public var subjectAllTurnaround: Bool
    public var owner: String
    public var overdue: Bool { Date().timeIntervalSince(started) > duration }
    public var overdueRowID: String { "overdue:\(id)" }

    public init(
        id: String,
        who: String,
        task: String,
        duration: TimeInterval,
        started: Date,
        subjectAllTurnaround: Bool,
        owner: String = ""
    ) {
        self.id = id
        self.who = who
        self.task = task
        self.duration = duration
        self.started = started
        self.subjectAllTurnaround = subjectAllTurnaround
        self.owner = owner.isEmpty ? who : owner
    }

    public func remaining(now: Date = Date()) -> TimeInterval {
        max(0, duration - now.timeIntervalSince(started))
    }

    public func remainingFraction(now: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, remaining(now: now) / duration))
    }
}

public final class TimerBoard: @unchecked Sendable {
    public private(set) var timers: [PartyTimer] = []
    public private(set) var completed: [PartyTimer] = []
    private let box: EventLog
    public static let maxActive = 4
    public init(box: EventLog) { self.box = box }

    @discardableResult
    public func add(
        who: String,
        task: String,
        duration: TimeInterval,
        subjectAll: Bool,
        now: Date = Date(),
        owner: String = ""
    ) -> PartyTimer? {
        let who = who.isEmpty ? "ALL" : who
        if timers.contains(where: { $0.task == task && $0.who == who }) {
            return nil
        }
        guard timers.filter({ !$0.overdue || true }).count < Self.maxActive else { return nil }
        guard timers.count < Self.maxActive else { return nil }
        let t = PartyTimer(
            id: UUID().uuidString,
            who: who,
            task: task,
            duration: duration,
            started: now,
            subjectAllTurnaround: subjectAll,
            owner: owner
        )
        timers.append(t)
        box.log("timer", "\(who) \(task) \(duration)")
        return t
    }

    public func overduePlate(now: Date = Date()) -> [PartyTimer] {
        timers.filter { now.timeIntervalSince($0.started) > $0.duration }
    }

    public func onProfile(personID: String, name: String, isYou: Bool) -> [PartyTimer] {
        timers.filter { t in
            if t.who == personID || t.who == name { return true }
            if !t.owner.isEmpty && (t.owner == personID || t.owner == name) { return true }
            if isYou && (t.who == "ALL" || t.who == "YOU") { return true }
            return false
        }
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

    public static let persistKey = "you.timers"

    public func restore(timers: [PartyTimer], completed: [PartyTimer] = []) {
        self.timers = Array(timers.prefix(Self.maxActive))
        self.completed = completed
    }

    public func save(defaults: UserDefaults = .standard) {
        let blob = TimerBlob(timers: timers, completed: completed)
        if let data = try? JSONEncoder().encode(blob) {
            defaults.set(data, forKey: Self.persistKey)
        }
    }

    public func load(defaults: UserDefaults = .standard) {
        guard let data = defaults.data(forKey: Self.persistKey),
              let blob = try? JSONDecoder().decode(TimerBlob.self, from: data)
        else { return }
        restore(timers: blob.timers, completed: blob.completed)
    }
}

private struct TimerBlob: Codable {
    var timers: [PartyTimer]
    var completed: [PartyTimer]
}
