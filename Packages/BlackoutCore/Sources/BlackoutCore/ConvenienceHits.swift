import Foundation

/// Latest inbound field ping from someone else. Map pip + strip + idle + Live Activity.
public struct LatestInboundPing: Hashable, Sendable, Identifiable {
    public var id: BlackoutID
    public var ping: FieldPingID
    public var callsign: String
    public var createdAt: Date
    public var latitude: Double?
    public var longitude: Double?
    public var thread: ChatThreadRef
    public var acknowledged: Bool

    public init(
        id: BlackoutID,
        ping: FieldPingID,
        callsign: String,
        createdAt: Date,
        latitude: Double? = nil,
        longitude: Double? = nil,
        thread: ChatThreadRef,
        acknowledged: Bool = false
    ) {
        self.id = id
        self.ping = ping
        self.callsign = callsign
        self.createdAt = createdAt
        self.latitude = latitude
        self.longitude = longitude
        self.thread = thread
        self.acknowledged = acknowledged
    }

    public var hue: FieldPingHue { FieldPing.hue(ping) }
    public var label: String { FieldPing.label(ping) }
    public var hasCoordinate: Bool { latitude != nil && longitude != nil }

    public func isOpen(at now: Date = Date()) -> Bool {
        !acknowledged && now.timeIntervalSince(createdAt) < FieldPing.openWindow
    }

    public func showsMapStrip(at now: Date = Date()) -> Bool {
        isOpen(at: now)
    }

    public func holdsMapChrome(at now: Date = Date()) -> Bool {
        isOpen(at: now) && FieldPing.holdsMapChrome(ping)
    }

    public func keepsScreenAwake(at now: Date = Date()) -> Bool {
        isOpen(at: now) && ping == .down
    }

    public var navigation: FieldPingNav? {
        guard let latitude, let longitude else { return nil }
        return FieldPingNav(latitude: latitude, longitude: longitude, label: "\(callsign) · \(label)")
    }

    public var announcePhrase: String {
        FieldPing.announcePhrase(callsign: callsign, id: ping)
    }
}

public enum IdleTimerPolicy {
    public static let pttHeardWindow: TimeInterval = 5

    public static func shouldDisable(
        navLockOn: Bool,
        pttTransmitting: Bool,
        pttLastHeard: Date?,
        sosCoverPresented: Bool,
        inboundImDownOpen: Bool,
        leaveBehindRelay: Bool = false,
        now: Date = Date()
    ) -> Bool {
        if leaveBehindRelay { return true }
        if navLockOn { return true }
        if pttTransmitting { return true }
        if sosCoverPresented { return true }
        if inboundImDownOpen { return true }
        if let heard = pttLastHeard, now.timeIntervalSince(heard) < pttHeardWindow {
            return true
        }
        return false
    }
}

/// One-time radios banner. Dismiss persists until radios recover, then fail again.
public struct MeshRadioBannerPolicy: Equatable, Sendable {
    public var dismissed: Bool
    public var lastCannotRun: Bool

    public init(dismissed: Bool = false, lastCannotRun: Bool = false) {
        self.dismissed = dismissed
        self.lastCannotRun = lastCannotRun
    }

    public var title: String { "Mesh off." }
    public var body: String {
        "Keep Bluetooth and Wi-Fi on in Airplane Mode. Text will queue. PTT unavailable."
    }

    public static func cannotRun(
        bluetoothOff: Bool,
        wifiOff: Bool,
        localNetworkDenied: Bool
    ) -> Bool {
        bluetoothOff || wifiOff || localNetworkDenied
    }

    public func shouldShow(cannotRun: Bool) -> Bool {
        cannotRun && !dismissed
    }

    public mutating func applyRadios(cannotRun: Bool) {
        if lastCannotRun && !cannotRun {
            dismissed = false
        }
        lastCannotRun = cannotRun
    }

    public mutating func dismiss() {
        dismissed = true
    }
}

/// Airplane + Wi-Fi on (no SSID / no WAN) is not wifi-off. Mesh is local radio.
public enum MeshRadioPathHonesty {
    public static func wifiRadioOff(wifiDenied: Bool) -> Bool {
        wifiDenied
    }
}

public enum MapQuickNav {
    public static let disabledOpacity: Double = 0.38

    public static func returnEnabled(hasStart: Bool) -> Bool { hasStart }

    public static func lastMarkEnabled(hasMark: Bool) -> Bool { hasMark }

    public static func returnDisabledReason(hasStart: Bool) -> String? {
        hasStart ? nil : "No start fix this outing."
    }

    public static func lastMarkDisabledReason(hasMark: Bool) -> String? {
        hasMark ? nil : "No MARK yet."
    }

    public static func outingStart(
        crumbs: [(latitude: Double?, longitude: Double?)],
        startLatitude: Double?,
        startLongitude: Double?
    ) -> (latitude: Double, longitude: Double)? {
        if let crumb = crumbs.first(where: { $0.latitude != nil && $0.longitude != nil }),
           let lat = crumb.latitude, let lon = crumb.longitude {
            return (lat, lon)
        }
        if let lat = startLatitude, let lon = startLongitude {
            return (lat, lon)
        }
        return nil
    }
}

/// Map SHARE uses the same string as SOS SHARE. Never a manual pin.
public enum BlackoutCoordShare {
    public static func shareFix(live: LocationFix?, lastKnown: LocationFix?) -> LocationFix? {
        if let live, live.hasCoordinate, live.source == .gps || live.source == .deadReckoning {
            return live
        }
        if let lastKnown, lastKnown.hasCoordinate, lastKnown.source != .manualPin {
            return lastKnown
        }
        return nil
    }

    public static func message(live: LocationFix?, lastKnown: LocationFix?) -> String {
        SOSConfirm.shareMessage(fix: shareFix(live: live, lastKnown: lastKnown))
    }
}

public enum PartyQR {
    public static let showTitle = "Show QR"
    public static let scanTitle = "Scan QR"
    public static let cameraDenied = "Camera denied. Type the 4–8 code."

    public static func payload(code: String) -> String {
        PartyCode.normalize(code)
    }

    public static func parse(_ raw: String) -> String? {
        let code = PartyCode.normalize(raw)
        return PartyCode.isValid(code) ? code : nil
    }
}

/// NFC join uses the same 4–8 code as QR / type-in. Hide controls when hardware is missing.
public enum PartyNFC {
    public static let holdToShare = "Hold to share"
    public static let tapToJoin = "Tap to join"
    public static let sessionFailed = "NFC failed. Type the 4–8 code."
    public static let denied = "NFC denied. Type the 4–8 code."

    public static func showsControls(readingAvailable: Bool) -> Bool {
        readingAvailable
    }

    public static func payload(code: String) -> String {
        PartyQR.payload(code: code)
    }

    public static func parse(_ raw: String) -> String? {
        if let code = PartyQR.parse(raw) { return code }
        return parseEmbedded(raw)
    }

    public static func parseMessagePayloads(_ payloads: [String]) -> String? {
        for raw in payloads {
            if let code = parse(raw) { return code }
        }
        return nil
    }

    private static func parseEmbedded(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("blackout://join/") {
            return PartyQR.parse(String(trimmed.dropFirst("blackout://join/".count)))
        }
        if let last = trimmed.split(separator: "/").last {
            return PartyQR.parse(String(last))
        }
        return nil
    }
}

/// Rear torch on Map. Not SOS, not the SOS strobe, not on the 2% shell.
public enum MapTorchPolicy {
    public static let emitsSOS = false
    public static let armsSOS = false
    public static let startsSOSStrobe = false
    public static let allowedInExtremeSaver = true
    public static let showsOnCriticalShell = false
    public static let envelopeKind: PayloadKind? = nil

    public static func showsControl(hasTorch: Bool) -> Bool {
        hasTorch
    }
}

/// Action Button / Camera Control / App Shortcut use the same PTT decision as the 72 disk.
public enum PTTIntentPolicy {
    public static let startTitle = "Start PTT"
    public static let stopTitle = "Stop PTT"
    public static let toggleTitle = "Toggle PTT"
    public static let actionHint = "Set Action Button to PTT in Settings"
    public static let firesSOS = false
    public static let sendsImDown = false

    public static func evaluate(
        nearbyPeerCount: Int,
        partyCode: String?,
        meshRunning: Bool,
        microphoneAllowed: Bool
    ) -> PTTDecision {
        PTTDecision.evaluate(
            nearbyPeerCount: nearbyPeerCount,
            partyCode: partyCode,
            meshRunning: meshRunning,
            microphoneAllowed: microphoneAllowed
        )
    }
}

public struct ActionButtonHintPolicy: Equatable, Sendable {
    public var dismissed: Bool

    public init(dismissed: Bool = false) {
        self.dismissed = dismissed
    }

    public func shouldShow() -> Bool { !dismissed }

    public mutating func dismiss() {
        dismissed = true
    }
}

public enum LiveActivityPolicy {
    public static func shouldBeActive(
        partyCode: String?,
        inboundPing: LatestInboundPing?,
        now: Date = Date()
    ) -> Bool {
        if PartyCode.isValid(partyCode) { return true }
        guard let inboundPing else { return false }
        return inboundPing.isOpen(at: now) && FieldPing.holdsMapChrome(inboundPing.ping)
    }
}

public enum ConvenienceCopy {
    public static let shareCoords = "Share"
    public static let returnToStart = "Return"
    public static let lastMark = "Last MARK"
    public static let coming = "Coming"
    public static let hold = "Hold"
    public static let navigate = "Navigate"
    public static let dictation = "Dictate"
    public static let dictationDenied = "Mic denied. Type instead. Open Settings to dictate."
    public static let noFixShare = "NO FIX. Nothing to share."
    public static let flashlight = "Light"
}
