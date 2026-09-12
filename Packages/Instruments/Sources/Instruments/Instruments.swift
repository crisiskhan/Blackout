import Foundation
import BlackBox

public struct InstrumentState: Equatable, Sendable {
    public var torchClicks: Int
    public var compassCalibrated: Bool
    public var usbCPTT: Bool
    public var externalGNSS: Bool
    public var magNorth: Bool

    public init(
        torchClicks: Int = 0,
        compassCalibrated: Bool = false,
        usbCPTT: Bool = false,
        externalGNSS: Bool = false,
        magNorth: Bool = true
    ) {
        self.torchClicks = torchClicks
        self.compassCalibrated = compassCalibrated
        self.usbCPTT = usbCPTT
        self.externalGNSS = externalGNSS
        self.magNorth = magNorth
    }
}

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
}
