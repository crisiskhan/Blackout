import BlackoutCore
import Foundation
import LocalAuthentication
import Observation

@MainActor
@Observable
public final class AppLockService: AppLockServing {
    public var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    public private(set) var isUnlocked: Bool

    private static let enabledKey = "com.crisiskhan.blackout.lock.enabled"

    public init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isUnlocked = false
    }

    public func unlockSession() {
        isUnlocked = true
    }

    public func lock() {
        if isEnabled {
            isUnlocked = false
        }
    }

    public func unlock() async -> Bool {
        guard isEnabled else {
            isUnlocked = true
            return true
        }
        let context = LAContext()
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics
        guard context.canEvaluatePolicy(policy, error: &error) else {
            return false
        }
        do {
            let ok = try await context.evaluatePolicy(policy, localizedReason: "Unlock Blackout on this device.")
            isUnlocked = ok
            return ok
        } catch {
            return false
        }
    }
}
