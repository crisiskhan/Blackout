import Foundation

/// Confirm-panel actions. Hold 1.5s presents the unarmed cover; tap never fires.
public enum SOSConfirmAction: String, CaseIterable, Sendable, Hashable {
    case speakSOS
    case speakLocation
    case sharePosition
    case copyCoords
    case call911
    case visualStrobe

    public var title: String {
        switch self {
        case .speakSOS: return SOSConfirmCopy.speakSOS
        case .speakLocation: return SOSConfirmCopy.speakLocation
        case .sharePosition: return SOSConfirmCopy.sharePosition
        case .copyCoords: return SOSConfirmCopy.copyCoords
        case .call911: return SOSConfirmCopy.call911
        case .visualStrobe: return SOSConfirmCopy.visualStrobe
        }
    }

    public var stopTitle: String { SOSConfirmCopy.stop }
}

public enum SOSConfirmCopy {
    public static let speakSOS = "SPEAK SOS"
    public static let speakLocation = "SPEAK MY LOCATION"
    public static let sharePosition = "SHARE POSITION"
    public static let copyCoords = "COPY COORDS"
    public static let call911 = "CALL 911"
    public static let visualStrobe = "VISUAL SOS STROBE"
    public static let stop = "STOP"
}

/// FAB + I’m-OK chip geometry. SOS never recedes with Map HUD.
public enum SOSChrome {
    public static let fab: Double = 88
    public static let chip: Double = 56
    public static let gap: Double = 8
    public static let tabBar: Double = 49
    public static let homeIndicator: Double = 34
    public static let holdSeconds: Double = 1.5

    /// Overlay ignores the bottom safe area. Compact 4-tab: gap above the tab bar.
    /// Critical SOS-only and iPad split have no tab bar: gap above the home indicator.
    public static func fabBottomInset(hasTabBar: Bool) -> Double {
        gap + (hasTabBar ? tabBar : 0) + homeIndicator
    }

    /// Trailing spacer so the 56h chip stays 8pt clear of the 88pt disk.
    public static var chipDiskClearance: Double { fab + gap }
}

/// Unarmed-cover helpers. Never auto-dials 911. Never auto-invokes OS Emergency SOS.
public enum SOSConfirm {
    public static let speakSOS = "SOS"
    public static let noFix = "NO FIX"
    public static let emergencyTel = "tel:911"
    public static let autoDials911 = false
    public static let autoInvokesSystemEmergencySOS = false
    public static let strobePeriodMs = 330
    public static var strobeInterval: TimeInterval { Double(strobePeriodMs) / 1000 }
    public static let reduceMotionOpacity = 0.55
    public static let holdSeconds = SOSChrome.holdSeconds
    public static let meshKind = PayloadKind.sosAlert

    public static func coordsLine(_ fix: LocationFix?) -> String {
        guard let fix, let lat = fix.latitude, let lon = fix.longitude else {
            return noFix
        }
        return String(format: "%.5f, %.5f", lat, lon)
    }

    public static func shareMessage(fix: LocationFix?) -> String {
        "BLACKOUT \(coordsLine(fix))"
    }

    public static func speakLocation(_ fix: LocationFix?) -> String {
        coordsLine(fix)
    }

    public static func shouldSendMesh(peerCount: Int) -> Bool {
        peerCount > 0
    }

    public static func meshEnvelope(sender: BlackoutID, recipient: BlackoutID) -> Envelope {
        Envelope(
            kind: meshKind,
            ciphertext: Data("sos".utf8),
            sender: sender,
            recipient: recipient
        )
    }
}
