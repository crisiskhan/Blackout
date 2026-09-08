import AVFoundation
import BlackoutCore
import Foundation
import Observation

/// Rear torch on/off. Independent of SOS strobe. Last writer wins at the OS torch.
@MainActor
@Observable
public final class MapTorchController {
    public private(set) var isOn = false
    public let hasHardware: Bool

    public init(hasHardware: Bool? = nil) {
        self.hasHardware = hasHardware ?? Self.detectHardware()
    }

    public static func detectHardware() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video) else { return false }
        return device.hasTorch
    }

    public func toggle() {
        setOn(!isOn)
    }

    public func turnOff() {
        setOn(false)
    }

    public func setOn(_ on: Bool) {
        guard hasHardware else { return }
        guard MapTorchPolicy.showsControl(hasTorch: hasHardware) else { return }
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            isOn = false
            return
        }
        do {
            try device.lockForConfiguration()
            if on, device.isTorchModeSupported(.on) {
                device.torchMode = .on
                isOn = true
            } else {
                device.torchMode = .off
                isOn = false
            }
            device.unlockForConfiguration()
        } catch {
            isOn = false
        }
    }
}
