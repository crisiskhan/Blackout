import Foundation

/// Catalog copy matches disk. Designated bundled ≠ Ready on this SHA.
public enum FieldPackHonesty {
    public static func claimsBundledReady(isInstalled: Bool) -> Bool {
        isInstalled
    }

    public static func showsCatalogSummary(isReady: Bool) -> Bool {
        isReady
    }

    public static func rowState(
        isInstalled: Bool,
        downloading: Bool,
        isRemote: Bool,
        assetReady: Bool,
        pathSatisfied: Bool,
        onWiFi: Bool
    ) -> FieldPackRowState? {
        if downloading { return .downloading }
        if isInstalled { return .ready }
        if isRemote {
            if !pathSatisfied || !onWiFi { return .noWifi }
            if !assetReady { return .failed }
        }
        return nil
    }

    public static func message(
        isInstalled: Bool,
        isBundled: Bool,
        isRemote: Bool,
        assetReady: Bool,
        pathSatisfied: Bool,
        onWiFi: Bool
    ) -> String {
        if isInstalled {
            return isBundled ? "Bundled. Ready. Works airplane." : "Ready. Works airplane."
        }
        if isRemote {
            if !pathSatisfied {
                return "No network. Airplane uses packs already on disk."
            }
            if !onWiFi {
                return "Prefers Wi-Fi. Tap Download to try anyway from this screen."
            }
            if !assetReady {
                return "Not on GitHub Releases yet. Denver stays the fallback."
            }
            return "Tap Download. Then airplane."
        }
        return "Available. Not installed on this device."
    }
}
