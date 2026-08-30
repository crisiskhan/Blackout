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
    public static let aboutUsesSameWordmarkPNG = true
    public static let aboutPlateRadius: Double = 12
    public static let aboutPlateEdge: Double = 1
    public static let aboutPlateSunEdge: Double = 2
    public static let aboutPlateHasDropShadow = false

    public static func aboutPlateEdgeWidth(sun: Bool) -> Double {
        switch sun {
        case true:
            return aboutPlateSunEdge
        case false:
            return aboutPlateEdge
        }
    }

    /// Full red-eye O hero on the Crisis lock confirm cover. Not the old 48pt crop.
    public static let sosConfirmRedEye: Double = 200
    public static let sosConfirmShowsSOSWordUnderEye = false
    public static let sosConfirmStacksSOSDiskUnderEye = false
    public static let sosConfirmUsesLockup = false
    public static let sosConfirmUsesEmblem = false
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
