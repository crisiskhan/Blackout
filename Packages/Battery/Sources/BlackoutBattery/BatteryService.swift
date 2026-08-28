import BlackoutCore
import Foundation
import Observation
import UIKit

@MainActor
@Observable
public final class BatteryService: BatteryServing {
    public var policy: BatteryPolicy {
        didSet { UserDefaults.standard.set(policy.rawValue, forKey: Self.policyKey) }
    }
    public private(set) var level: Float
    public private(set) var isCharging: Bool

    public var hidesSOS: Bool { false }

    public var coarseNavigateEnabled: Bool { true }

    public var pausesCameraAndPTT: Bool {
        policy == .extremeSaver
    }

    private static let policyKey = "com.crisiskhan.blackout.battery.policy"

    public init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        if let raw = UserDefaults.standard.string(forKey: Self.policyKey),
           let stored = BatteryPolicy(rawValue: raw) {
            policy = stored
        } else {
            policy = .balanced
        }
        level = UIDevice.current.batteryLevel
        isCharging = Self.isPlugged(UIDevice.current.batteryState)
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.level = UIDevice.current.batteryLevel
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isCharging = Self.isPlugged(UIDevice.current.batteryState)
            }
        }
    }

    private static func isPlugged(_ state: UIDevice.BatteryState) -> Bool {
        state == .charging || state == .full
    }
}
