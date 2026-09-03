import Foundation
import TimerSync

public struct TripSheet: Equatable, Sendable {
    public var brief: String
    public var debrief: String
    public var outTime: Date
    public var dueBack: Date
    public func overdue(now: Date = Date()) -> Bool { now > dueBack }
}

public enum TripBrief {
    public static func make(brief: String, hours: Double, now: Date = Date()) -> TripSheet {
        TripSheet(brief: brief, debrief: "", outTime: now, dueBack: now.addingTimeInterval(hours * 3600))
    }
}
