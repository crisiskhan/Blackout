import Foundation

/// Chat status copy. Never delivery ticks.
public enum MessageStatus: String, Codable, Sendable, CaseIterable {
    case sealed = "Sealed"
    case queued = "Queued"
    case onMesh = "On mesh"
}
