import Foundation

public enum PermissionKind: String, Sendable, CaseIterable, Identifiable {
    case location
    case camera
    case microphone
    case bluetooth
    case motion
    case localAuthentication

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .location: return "Location"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .bluetooth: return "Bluetooth"
        case .motion: return "Motion / compass"
        case .localAuthentication: return "Device lock"
        }
    }
}
