import Foundation

public struct BlackoutID: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID { rawValue }
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
