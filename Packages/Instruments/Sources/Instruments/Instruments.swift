import Foundation
import BlackBox

public struct InstrumentState: Equatable, Sendable {
    public var torchClicks: Int
    public var compassCalibrated: Bool
    public var usbCPTT: Bool
    public var externalGNSS: Bool
    public var magNorth: Bool
}

public final class Instruments: @unchecked Sendable {
    public private(set) var state = InstrumentState(torchClicks: 0, compassCalibrated: false, usbCPTT: false, externalGNSS: false, magNorth: true)
    private let box: BlackBox
    public init(box: BlackBox) { self.box = box }
    public func torchTap() {
        state.torchClicks = (state.torchClicks + 1) % 4
        box.log("torch", "\(state.torchClicks)")
    }
    public func calibrateCompass() { state.compassCalibrated = true }
    public func attachUSB_C_PTT(_ present: Bool) { state.usbCPTT = present }
    public func attachGNSSPuck(_ present: Bool) { state.externalGNSS = present }
    public func setTrueNorth() { state.magNorth = false }
}
