import Foundation
import Observation
import BlackBox

/// Five on-device Speak voices. Compact identifiers so airplane mode never
/// waits on a download. Rate and pause are the quality, not a slogan.
public enum NavVoice: String, CaseIterable, Equatable, Sendable {
    case steel
    case night
    case range
    case mesh
    case desert

    public var title: String {
        switch self {
        case .steel:
            return "STEEL"
        case .night:
            return "NIGHT"
        case .range:
            return "RANGE"
        case .mesh:
            return "MESH"
        case .desert:
            return "DESERT"
        }
    }

    public static func parse(_ raw: String?) -> NavVoice {
        guard let raw, let voice = NavVoice(rawValue: raw) else { return .steel }
        return voice
    }

    public func identifier(locale: String) -> String {
        let spanish = locale == "es"
        switch self {
        case .steel:
            return spanish
                ? "com.apple.voice.compact.es-MX.Paulina"
                : "com.apple.voice.compact.en-US.Samantha"
        case .night:
            return spanish
                ? "com.apple.voice.compact.es-ES.Monica"
                : "com.apple.voice.compact.en-GB.Daniel"
        case .range:
            return spanish
                ? "com.apple.voice.compact.es-ES.Jorge"
                : "com.apple.voice.compact.en-AU.Karen"
        case .mesh:
            return spanish
                ? "com.apple.voice.compact.es-MX.Paulina"
                : "com.apple.voice.compact.en-IE.Moira"
        case .desert:
            return spanish
                ? "com.apple.voice.compact.es-US.Isabela"
                : "com.apple.voice.compact.en-ZA.Tessa"
        }
    }

    public var rate: Float {
        switch self {
        case .steel:
            return 0.44
        case .night:
            return 0.40
        case .range:
            return 0.47
        case .mesh:
            return 0.46
        case .desert:
            return 0.42
        }
    }

    public var pitch: Float {
        switch self {
        case .steel:
            return 0.96
        case .night:
            return 0.86
        case .range:
            return 1.06
        case .mesh:
            return 1.00
        case .desert:
            return 0.90
        }
    }

    public var preDelay: TimeInterval {
        switch self {
        case .steel:
            return 0.10
        case .night:
            return 0.14
        case .range:
            return 0.08
        case .mesh:
            return 0.10
        case .desert:
            return 0.16
        }
    }

    public var postDelay: TimeInterval {
        switch self {
        case .steel:
            return 0.32
        case .night:
            return 0.40
        case .range:
            return 0.28
        case .mesh:
            return 0.34
        case .desert:
            return 0.42
        }
    }
}

public struct InstrumentState: Equatable, Sendable {
    public var torchClicks: Int
    public var compassCalibrated: Bool
    public var usbCPTT: Bool
    public var externalGNSS: Bool
    public var magNorth: Bool
    public var voice: NavVoice

    public init(
        torchClicks: Int = 0,
        compassCalibrated: Bool = false,
        usbCPTT: Bool = false,
        externalGNSS: Bool = false,
        magNorth: Bool = true,
        voice: NavVoice = .steel
    ) {
        self.torchClicks = torchClicks
        self.compassCalibrated = compassCalibrated
        self.usbCPTT = usbCPTT
        self.externalGNSS = externalGNSS
        self.magNorth = magNorth
        self.voice = voice
    }
}

@Observable
public final class InstrumentBoard: @unchecked Sendable {
    public private(set) var state = InstrumentState()
    private let box: EventLog
    public init(box: EventLog) { self.box = box }
    public func torchTap() {
        state.torchClicks = (state.torchClicks + 1) % 4
        box.log("torch", "\(state.torchClicks)")
    }
    public func calibrateCompass() { state.compassCalibrated = true }
    public func attachUSB_C_PTT(_ present: Bool) { state.usbCPTT = present }
    public func attachGNSSPuck(_ present: Bool) { state.externalGNSS = present }
    public func setTrueNorth() { state.magNorth = false }
    public func toggleMagTrue() { state.magNorth.toggle() }
    public func setVoice(_ voice: NavVoice) {
        state.voice = voice
        box.log("voice", voice.rawValue)
    }
}
