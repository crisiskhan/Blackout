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
    public static let speakLocation = "SPEAK LOCATION"
    public static let speakCoords = "SPEAK COORDS"
    public static let sharePosition = "SHARE"
    public static let copyCoords = "COPY"
    public static let call911 = "CALL 911"
    public static let visualStrobe = "STROBE"
    public static let stop = "STOP"
    public static let slideToConfirm = "SLIDE TO CONFIRM"
    public static let cancel = "CANCEL"
}

/// Crisis-lock confirm cover controls. Not the Map 88pt FAB. CALL 911 is tap-only.
public enum SOSCrisisLockControl: String, CaseIterable, Sendable, Hashable {
    case cancel
    case strobe
    case speakCoords
    case share
    case call911

    public var title: String {
        switch self {
        case .cancel: return SOSConfirmCopy.cancel
        case .strobe: return SOSConfirmCopy.visualStrobe
        case .speakCoords: return SOSConfirmCopy.speakCoords
        case .share: return SOSConfirmCopy.sharePosition
        case .call911: return SOSConfirmCopy.call911
        }
    }

    public var symbol: String {
        switch self {
        case .cancel: return "xmark"
        case .strobe: return "sun.max.fill"
        case .speakCoords: return "plus.viewfinder"
        case .share: return "square.and.arrow.up"
        case .call911: return "phone.fill"
        }
    }

    public var confirmAction: SOSConfirmAction? {
        switch self {
        case .cancel: return nil
        case .strobe: return .visualStrobe
        case .speakCoords: return .speakLocation
        case .share: return .sharePosition
        case .call911: return .call911
        }
    }
}

/// FAB + I’m-OK chip geometry. SOS never recedes with Map HUD.
public enum SOSChrome {
    public static let fab: Double = 88
    public static let chip: Double = 56
    public static let gap: Double = 8
    public static let trailing: Double = 16
    public static let tabBar: Double = 49
    public static let homeIndicator: Double = 34
    public static let holdSeconds: Double = 1.5
    /// Confirm-cover SOS only. Map FAB stays `fab` (88). Never 88 on the lock cover.
    public static let confirmHit: Double = 64
    /// Bottom fraction of the SOS confirm cover. Thumb reaches slide + SOS.
    public static let confirmThumbZone: Double = 0.34
    public static let confirmPhrase = SOSConfirmCopy.slideToConfirm
    public static let confirmKnobIsSOS = true

    /// Never hide the 88pt disk to clear Field or the keyboard. Lift it instead.
    public static let hidesForKeyboard = false
    public static let liftsAboveKeyboard = true

    /// Overlay stays in the bottom safe area so the tab bar is not padded off-screen.
    /// Compact 4-tab: 8pt above the tab bar. Critical / iPad: 8pt above the home indicator.
    /// Keyboard up: 8pt above the keys. Tab bar is covered, so it is not added again.
    public static func fabBottomInset(hasTabBar: Bool, keyboardHeight: Double = 0) -> Double {
        if keyboardHeight > 0 {
            return gap + keyboardHeight
        }
        return gap + (hasTabBar ? tabBar : 0)
    }

    /// Keyboard frame overlap with the screen. Hidden / off-screen frames are 0.
    public static func keyboardOverlap(keyboardMinY: Double, screenHeight: Double) -> Double {
        max(0, screenHeight - keyboardMinY)
    }

    /// Trailing spacer so the 56h chip stays ≥8pt clear of the 88pt disk.
    public static var chipDiskClearance: Double { fab + gap }

    /// Chip and SOS share 16pt trailing. Spacer is disk + gap, so the gap is exactly 8.
    public static var horizontalGap: Double { chipDiskClearance - fab }
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

    public static func meshEnvelope(
        sender: BlackoutID,
        recipient: BlackoutID,
        callsign: String = Callsign.defaultValue
    ) -> Envelope {
        Envelope(
            kind: meshKind,
            ciphertext: SOSMeshBody.encode(callsign: callsign),
            sender: sender,
            recipient: recipient
        )
    }
}

/// Persisted-armed restore. Closing the panel does not disarm. A new binary
/// must not trap the first launch on that overlay.
public enum SOSArmedRestore {
    public static let dismissDisarms = false
    public static let autoPresentOnColdLaunch = false
    public static let appearStartsSpeech = false
    public static let appearStartsStrobe = false
    public static let appearRequiresPeers = false
    public static let appearRequiresLocation = false

    public static func currentBuild(from bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
    }

    public static func isNewBinaryLaunch(currentBuild: String, lastSeenBuild: String?) -> Bool {
        currentBuild.isEmpty || currentBuild != lastSeenBuild
    }

    public static func shouldAutoPresentArmedOverlay(
        persistedArmed: Bool,
        presentRequested: Bool,
        newBinaryLaunch: Bool
    ) -> Bool {
        // First open is the unlock gate. Armed overlay is never the launch screen.
        _ = persistedArmed
        _ = presentRequested
        _ = newBinaryLaunch
        return false
    }

    public static func shouldRequestConfirmAfterMissedCheckIn(
        persistedArmed: Bool,
        newBinaryLaunch: Bool
    ) -> Bool {
        _ = newBinaryLaunch
        return !persistedArmed
    }
}

/// SOS mesh body. Sender callsign lives here so the pipe stays opaque.
public enum SOSMeshBody {
    public static func encode(callsign: String) -> Data {
        let wire = Wire(v: 1, callsign: Callsign.commit(callsign))
        return (try? JSONEncoder().encode(wire)) ?? Data("sos".utf8)
    }

    public static func callsign(in ciphertext: Data) -> String {
        if let wire = try? JSONDecoder().decode(Wire.self, from: ciphertext),
           !wire.callsign.isEmpty {
            return Callsign.commit(wire.callsign)
        }
        return Callsign.defaultValue
    }

    private struct Wire: Codable {
        var v: Int
        var callsign: String
    }
}
