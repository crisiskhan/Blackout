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
    public static let startsLiveActivityBeforeUnlock = false
    public static let walksAllTilesOnBoot = false
}
