import Foundation

/// Chrome contract. SOS is a RootView sibling so tab switches do not remount the 88pt disk.
public enum RootChromeLock {
    public static let tabCount = 4
    public static let sosOverlayIsInsideTabView = false
    public static let sosIsRootViewSibling = true
    public static let sosPlacement = "RootView.ZStack.sibling"
    /// Only flag that unmounts Map / Comms / Field / Expedition.
    public static let chromeCollapseFlag = "battery.isCritical"
    /// DS §10.1 first-run pack sheet is dead. Cold launch is Map.
    public static let autoPresentsFirstOpenPackSheet = false
    public static let coldLaunchDestination = "map"
}
