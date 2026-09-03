import Foundation

public struct BlackBoxEvent: Codable, Equatable, Sendable {
    public var at: Date
    public var kind: String
    public var detail: String
    public init(at: Date = Date(), kind: String, detail: String) {
        self.at = at; self.kind = kind; self.detail = detail
    }
}

public final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [BlackBoxEvent] = []
    public init() {}

    public func log(_ kind: String, _ detail: String) {
        lock.lock(); defer { lock.unlock() }
        events.append(BlackBoxEvent(kind: kind, detail: detail))
    }

    public func all() -> [BlackBoxEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }

    public func jsonl() throws -> String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return try all().map { String(data: try enc.encode($0), encoding: .utf8)! }.joined(separator: "\n")
    }
}
