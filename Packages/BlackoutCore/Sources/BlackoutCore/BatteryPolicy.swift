import Foundation

public enum BatteryPolicy: String, Codable, Sendable, CaseIterable, Identifiable {
    case balanced
    case saver
    case extremeSaver

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .saver: return "Saver"
        case .extremeSaver: return "Extreme Saver"
        }
    }

    public var detail: String {
        switch self {
        case .balanced:
            return "Full local sensors. SOS and coarse Navigate always available."
        case .saver:
            return "Slower location cadence. SOS stays visible."
        case .extremeSaver:
            return "SOS + coarse Navigate + radar HUD. Camera / PTT / Vision pause. SOS stays visible. Auto-selected at ~2% battery."
        }
    }
}
