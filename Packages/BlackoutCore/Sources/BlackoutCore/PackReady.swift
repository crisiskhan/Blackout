import Foundation

/// One Ready query. Map, Field, and Navigate ask this — not a second catalog.
public struct PackReadySnapshot: Equatable, Sendable {
    public var readyIDs: [String]

    public init(readyIDs: [String] = []) {
        self.readyIDs = readyIDs
    }

    public func isReady(_ id: String) -> Bool {
        readyIDs.contains(id)
    }

    public static let empty = PackReadySnapshot()
}
