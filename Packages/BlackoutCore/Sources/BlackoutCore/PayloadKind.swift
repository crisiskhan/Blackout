import Foundation

public enum PayloadKind: String, Codable, Sendable, CaseIterable {
    case message
    case sosAlert
    case pttClip
    case locationFix
    case breadcrumb
    /// Party lane. Not SOS-arm. Mesh transports blindly.
    case partyStatus
}
