import Foundation

/// Chat status copy. Never delivery ticks. Never “Delivered to server.”
public enum MessageStatus: String, Codable, Sendable, CaseIterable {
    case sealed = "Sealed"
    case queued = "Queued"
    case onMesh = "On mesh"
    case failed = "Failed"
}
