import Foundation
import MeshDTN
import CryptoParty
import PTTAudio
import RosterRoles

public enum Chip: String, CaseIterable, Sendable, Hashable {
    case ok, formUp, wait, water, lostKid, overdue, rally, down, sos
}

public struct CommsState: Sendable {
    public var channel: String
    public var chips: [Chip]
    public var whisperMeters: Double
    public var quietHours: Bool
    public var radioCheckOK: Bool
    public var leadBridge: Bool
    public var peer: String?

    public init() {
        channel = "ALL"
        chips = []
        whisperMeters = 9
        quietHours = false
        radioCheckOK = false
        leadBridge = false
        peer = nil
    }

    public mutating func setChannel(_ name: String) { channel = name }

    /// A radio check is a heard peer, not a boolean we invent.
    public mutating func radioCheck(heard: Bool = false) { radioCheckOK = heard }

    public var whisperOK: Bool { whisperMeters < 10 }

    public mutating func formUp() { push(.formUp) }
    public mutating func lostKid() { push(.lostKid) }
    public mutating func wait() { push(.wait) }
    public mutating func water() { push(.water) }
    public mutating func rally() { push(.rally) }
    public mutating func down() { push(.down) }
    public mutating func sos() { push(.sos) }

    public mutating func pickPeer(_ name: String) {
        peer = name
        channel = "1:1"
    }

    public func meshTo(nearby: [String]) -> String {
        guard channel == "1:1" else { return "*" }
        if let peer, nearby.contains(peer) { return peer }
        return nearby.first ?? "*"
    }

    public mutating func push(_ chip: Chip) {
        chips.append(chip)
        trim()
    }

    private mutating func trim() {
        if chips.count > 16 {
            chips.removeFirst(chips.count - 16)
        }
    }
}
