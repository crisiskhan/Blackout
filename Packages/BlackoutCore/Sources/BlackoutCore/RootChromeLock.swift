import Foundation

/// Chrome contract. SOS is a RootView sibling so tab switches do not remount the 88pt disk.
public enum RootChromeLock {
    public static let tabCount = 4
    public static let sosOverlayIsInsideTabView = false
    public static let sosIsRootViewSibling = true
    public static let sosPlacement = "RootView.ZStack.sibling"
    /// Only flag that unmounts Map / Comms / Field / Expedition.
    public static let chromeCollapseFlag = "battery.isCritical"
    /// DS §10.1 first-run pack sheet is dead. Cold launch is the in-app unlock gate.
    public static let autoPresentsFirstOpenPackSheet = false
    public static let coldLaunchDestination = LaunchLock.destination

    /// Hold-twin cover may mount SOSFab. The idle lock frame must not.
    public static func sosOverlayMounts(isUnlocked: Bool, coverRequested: Bool) -> Bool {
        LaunchLock.sosOverlayMounts(isUnlocked: isUnlocked, coverRequested: coverRequested)
    }

    /// Lock gate stays off while backgrounded so Field camera / photo leave
    /// does not tear down UIImagePickerController under the lock remount.
    public static func showsLockGate(isUnlocked: Bool, sceneActive: Bool) -> Bool {
        LaunchLock.showsLockGate(isUnlocked: isUnlocked, sceneActive: sceneActive)
    }
}

/// First-open lock chrome. SwiftUI slider + lockup Image emblem. Not a full-screen still.
public enum LaunchLock {
    public static let destination = "unlock"
    public static let usesBitmapLockUI = false
    public static let usesFullScreenLockImage = false
    public static let usesLockupImage = true
    public static let metalRingIsSwiftUI = false
    public static let sliderHasSOSTwin = true
    public static let sosTwinIsMapFAB = false
    public static let trackHit: Double = 56
    public static let handleHit: Double = 56
    public static let sosTwinHit: Double = 56
    public static let handleIsMetal = true
    public static let phrase = "SLIDE TO UNLOCK"
    public static let slideArmsSOS = false
    public static let twinHoldPresentsUnarmedCover = true
    public static let twinHoldArmsSOS = false
    public static let twinHoldSeconds: Double = 1.5
    public static let persistedSOSArmedStealsFirstOpen = false
    public static let coldLaunchShowsSplash = false
    public static let startsSensorsBeforeUnlock = false
    /// CLLocationManager / CMPedometer / CMMotionManager stay off AppContainer.init.
    public static let constructsLocationHardwareInInit = false
    public static let startsPackPathMonitorInInit = false
    public static let startsHardwareSynchronouslyOnUnlock = false
    public static let remountsLockGateOnBackground = false
    public static let parksHardwareOnBackground = true
    public static let startsLiveActivityBeforeUnlock = false
    /// 33 lock-frame crash class. Covers stay off the lock tree until the twin asks.
    public static let sosFabMountsOnLockFrame = false
    /// CBCentralManager + NWPathMonitor must not start during AppContainer.init.
    public static let startsRadioProbeBeforeUnlock = false
    /// Leftover 32 ActivityKit rows must not be read on the first 33 process.
    public static let touchesLiveActivityOnNewBinary = false
    public static let walksAllTilesOnBoot = false

    /// Hold-twin cover may mount SOSFab. The idle lock frame must not.
    public static func sosOverlayMounts(isUnlocked: Bool, coverRequested: Bool) -> Bool {
        isUnlocked || coverRequested
    }

    public static func showsLockGate(isUnlocked: Bool, sceneActive: Bool) -> Bool {
        !isUnlocked && sceneActive
    }
}
