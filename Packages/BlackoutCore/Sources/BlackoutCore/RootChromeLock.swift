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

/// First-open lock chrome. Real SwiftUI only — no full-screen lock/SOS bitmap.
public enum LaunchLock {
    public static let destination = "unlock"
    public static let usesBitmapLockUI = false
    public static let usesFullScreenLockImage = false
    public static let metalRingIsSwiftUI = true
    public static let sliderHasSOSTwin = true
    public static let sosTwinIsMapFAB = false
    public static let sosTwinHit: Double = 64
    public static let handleIsMetal = true
    public static let phrase = "SLIDE TO UNLOCK"
    public static let persistedSOSArmedStealsFirstOpen = false
    public static let coldLaunchShowsSplash = false
}
