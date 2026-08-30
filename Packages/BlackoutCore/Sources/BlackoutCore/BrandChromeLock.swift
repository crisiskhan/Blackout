import Foundation

/// Logo-as-chrome contract. Locked wordmark + red-eye O crop only. No lockup. No SF Symbol O.
public enum BrandChromeLock {
    public static let wordmarkAsset = "Wordmark"
    public static let redEyeOAsset = "RedEyeO"
    public static let redEyeOIsTemplate = false
    public static let usesLockupInApp = false
    public static let typesetsBlackoutInSFPro = false
    public static let substitutesSFSymbolForO = false

    public static let splashWordmarkMaxWidth: Double = 280
    public static let splashHoldSeconds: Double = 1.2
    public static let splashHasEmblem = false
    public static let splashHasLockup = false
    public static let splashUsesStandaloneRedEyeO = false

    public static let aboutWordmarkMaxWidth: Double = 240
    public static let aboutTitle = "About"

    public static let sosConfirmRedEye: Double = 48
    public static let noPackRedEye: Double = 24
    public static let fabShowsRedEyeO = false

    public static let markSurfaces = ["splash-wordmark", "about-wordmark", "sos-confirm", "map-empty-no-pack"]
    public static let forbiddenMarkSurfaces = [
        "tab-bar",
        "sos-fab-disk",
        "map-hud",
        "map-chips",
        "map-puck",
        "map-tiles",
        "guide-cards",
        "packs-plate",
        "comms-bubbles",
        "map-empty-no-turns",
        "map-empty-no-civ",
        "map-empty-no-water"
    ]

    public static func splashPulsesO(reduceMotion: Bool) -> Bool {
        switch reduceMotion {
        case true:
            return false
        case false:
            return false
        }
    }
}
