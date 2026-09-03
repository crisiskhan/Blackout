import Foundation
import MeshDTN
import CryptoParty
import PTTAudio
import RosterRoles

public enum Chip: String, CaseIterable, Sendable {
    case ok, formUp, wait, water, lostKid, overdue
}

public struct CommsState: Sendable {
    public var channel: String
    public var chips: [Chip]
    public var whisperMeters: Double
    public var quietHours: Bool
    public var radioCheckOK: Bool
    public var leadBridge: Bool
    public init() {
        channel = "ALL"
        chips = []
        whisperMeters = 9
        quietHours = false
        radioCheckOK = false
        leadBridge = false
    }

    public mutating func setChannel(_ name: String) { channel = name }
    public mutating func radioCheck() { radioCheckOK = true }
    public var whisperOK: Bool { whisperMeters < 10 }
    public mutating func formUp() { chips.append(.formUp) }
    public mutating func lostKid() { chips.append(.lostKid) }
}
