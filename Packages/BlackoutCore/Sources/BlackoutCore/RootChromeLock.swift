import Foundation

/// Chrome contract. SOS is a RootView sibling so tab switches do not remount the 88pt disk.
public enum RootChromeLock {
    public static let tabCount = 3
    public static let sosOverlayIsInsideTabView = false
    public static let sosIsRootViewSibling = true
    public static let sosPlacement = "RootView.ZStack.sibling"
    /// Device 42: gear on Guide/Threads was a Root overlay at top-leading.
    public static let settingsIsTopLeadingOverlay = false
    public static let settingsSitsInSegmentRow = true
    /// PTT disc must sit in the bottom safe area, not under the tab bar.
    public static let pttIgnoresBottomSafeArea = false
    /// Only flag that unmounts Map / Comms / Field / Expedition.
    public static let chromeCollapseFlag = "battery.isCritical"
    /// DS §10.1 first-run pack sheet is dead. Cold launch is live Map.
    public static let autoPresentsFirstOpenPackSheet = false
    public static let coldLaunchDestination = LaunchLock.destination
    public static let expeditionIsTab = false
    /// 2% SOS-only shell stays in the tree for later. Do not collapse on cold launch.
    public static let sosOnlyCollapseOnColdLaunch = false
    public static let liveActivitySOSEnabled = false

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
    public static let destination = "map"
    public static let usesBitmapLockUI = false
    public static let usesFullScreenLockImage = false
    public static let usesLockupImage = false
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
    public static let remountsLockGateOnInactive = false
    public static let parksHardwareOnBackground = true
    /// Never call lock() while backgrounded. MetalRingLockup remount there is the 9:08 class.
    public static let locksOnBackground = false
    /// PHPicker / share / fileImporter / photo library is not a true leave.
    public static let locksOnPickerBackground = false
    public static let parksLiveActivityOnBackground = true
    public static let startsHardwareWhenSceneInactive = false
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
        _ = isUnlocked
        _ = sceneActive
        return false
    }
}

/// Scene-phase lock / park contract. Lock UI never remounts off an active scene.
public enum SceneLockPolicy {
    public enum Phase: Equatable, Sendable {
        case active
        case inactive
        case background
    }

    public static let requiresActiveSceneForHardware = true

    /// Lock Image / Metal / SOS cover paint only on a live, locked scene.
    public static func showsLockGate(isUnlocked: Bool, phase: Phase) -> Bool {
        _ = isUnlocked
        _ = phase
        return false
    }

    /// lock() is never applied in the phase handler itself.
    public static func shouldLockNow(phase: Phase) -> Bool {
        _ = phase
        return false
    }

    public static func shouldPark(phase: Phase) -> Bool {
        phase != .active
    }

    /// Home / other-app leave. A presented system picker is not a true leave.
    public static func pendingTrueLeave(phase: Phase, systemCoverPresented: Bool) -> Bool {
        phase == .background && !systemCoverPresented
    }

    /// Relock mounts MetalRingLockup on the next live scene only.
    public static func shouldRelockOnActive(pendingTrueLeave: Bool, systemCoverPresented: Bool) -> Bool {
        _ = pendingTrueLeave
        _ = systemCoverPresented
        return false
    }

    public static func isSystemCover(_ name: String) -> Bool {
        let needles = [
            "UIImagePickerController",
            "PHPickerViewController",
            "UIActivityViewController",
            "UIDocumentPickerViewController",
            "UIDocumentBrowserViewController",
            "PUPhotoPicker"
        ]
        return needles.contains { name.contains($0) }
    }
}
