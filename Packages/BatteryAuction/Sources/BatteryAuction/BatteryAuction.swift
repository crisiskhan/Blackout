import Foundation
import BlackBox

public enum PowerMode: String, CaseIterable, Sendable { case quiet, normal, search }

public struct PowerState: Equatable, Sendable {
    public var mode: PowerMode
    public var pocket: Bool
    public var powerBankWh: Double
    public var screenBuffer: Bool
}

public final class BatteryAuction: @unchecked Sendable {
    public private(set) var state: PowerState
    private let box: BlackBox
    public init(box: BlackBox) {
        self.box = box
        self.state = PowerState(mode: .normal, pocket: false, powerBankWh: 0, screenBuffer: false)
    }

    public func set(_ mode: PowerMode) {
        state.mode = mode
        box.log("power", mode.rawValue)
    }

    public func setPocket(_ on: Bool) { state.pocket = on }
    public func setBank(wh: Double) { state.powerBankWh = wh }
    public func hotSparePayload() -> String { "blackout-hotspare:\(state.powerBankWh)" }
}
