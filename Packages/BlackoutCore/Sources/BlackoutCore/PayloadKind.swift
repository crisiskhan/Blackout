import Foundation

public enum PayloadKind: String, Codable, Sendable, CaseIterable {
    case message
    case sosAlert
    case pttClip
    case locationFix
    case breadcrumb
}
