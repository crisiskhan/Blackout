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

    public var isCritical: Bool {
        level >= 0 && level <= 0.02 && !isCharging
    }

    public var tightensToSOSNavRadar: Bool {
        policy == .extremeSaver || isCritical
    }

    public var pausesCameraAndPTT: Bool {
        tightensToSOSNavRadar
    }

    private static let policyKey = "com.crisiskhan.blackout.battery.policy"
    private var userPickedPolicy = true

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
        applyCriticalIfNeeded()
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.level = UIDevice.current.batteryLevel
                self?.applyCriticalIfNeeded()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isCharging = Self.isPlugged(UIDevice.current.batteryState)
                self?.applyCriticalIfNeeded()
            }
        }
    }

    private func applyCriticalIfNeeded() {
        if isCritical, policy != .extremeSaver {
            policy = .extremeSaver
        }
    }

    private static func isPlugged(_ state: UIDevice.BatteryState) -> Bool {
        state == .charging || state == .full
    }
}
