import Foundation

/// Glove-size field pings. CoS-locked copy and hues. Not SOS.
public enum FieldPingID: String, Codable, Sendable, CaseIterable {
    case rally
    case escort
    case danger
    case down
}

public enum FieldReplyID: String, Codable, Sendable, CaseIterable {
    case copy
    case coming
    case hold
    case cant
}

public enum FieldPingHue: String, Sendable, CaseIterable {
    case ok
    case warn
    case red
}

public enum FieldPingHaptic: String, Sendable {
    case light
    case medium
    case heavy
}

public enum FieldPing {
    public static let envelopeKind = PayloadKind.message
    public static let armsSOS = false
    public static let autoDials911 = false
    public static let downSetsInjury = false
    public static let chipHeight: Double = 56
    public static let cardHeight: Double = 64
    public static let pip: Double = 8
    public static let openWindow: TimeInterval = 15 * 60
    /// Same band as NAV lock (`CompassLockMath.speechRate`).
    public static let speechRate: Float = 0.50
    public static let speechRateMin: Float = 0.47
    public static let speechRateMax: Float = 0.52

    public static func label(_ id: FieldPingID) -> String {
        switch id {
        case .rally: return "Rally here"
        case .escort: return "Need escort"
        case .danger: return "Danger here"
        case .down: return "I'm down"
        }
    }

    public static func hue(_ id: FieldPingID) -> FieldPingHue {
        switch id {
        case .rally: return .ok
        case .escort: return .warn
        case .danger, .down: return .red
        }
    }

    public static func label(_ id: FieldReplyID) -> String {
        switch id {
        case .copy: return "Copy"
        case .coming: return "Coming"
        case .hold: return "Hold"
        case .cant: return "Can't"
        }
    }

    public static func hue(_ id: FieldReplyID) -> FieldPingHue {
        switch id {
        case .copy, .coming: return .ok
        case .hold: return .warn
        case .cant: return .red
        }
    }

    public static func haptic(_ hue: FieldPingHue) -> FieldPingHaptic {
        switch hue {
        case .ok: return .light
        case .warn: return .medium
        case .red: return .heavy
        }
    }

    /// I'm down double-taps so it is not identical to Danger here (both red / heavy).
    public static func hapticRepeats(_ id: FieldPingID) -> Int {
        switch id {
        case .down: return 2
        case .rally, .escort, .danger: return 1
        }
    }

    public static func holdsMapChrome(_ id: FieldPingID) -> Bool {
        switch id {
        case .danger, .down: return true
        case .rally, .escort: return false
        }
    }

    public static func announcePhrase(callsign: String, id: FieldPingID) -> String {
        "\(Callsign.commit(callsign)). \(label(id))."
    }

    public static func shouldSpeak(isOutbound: Bool) -> Bool {
        !isOutbound
    }

    public static func shouldPlayHaptic(supportsHaptics: Bool) -> Bool {
        supportsHaptics
    }

    public static func requiresSenderPin(_ id: FieldReplyID) -> Bool {
        switch id {
        case .coming: return true
        case .copy, .hold, .cant: return false
        }
    }

    public static func requiresLocationPayload(_ id: FieldPingID) -> Bool {
        switch id {
        case .rally, .escort, .danger, .down:
            return true
        }
    }
}

public struct FieldPingNav: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var label: String

    public init(latitude: Double, longitude: Double, label: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
    }
}
