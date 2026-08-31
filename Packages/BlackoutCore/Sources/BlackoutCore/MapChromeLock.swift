import Foundation

/// Signed-off Map chrome. Mocks are SoT. Device-32 slab stack is the fail.
public enum MapChromeLock {
    public static let surface = "ZStack.fullBleed"
    public static let tabCount = 4
    public static let mapIsCroppedPage = false

    public static let chipPaintedHeight: Double = 56
    public static let chipGlyphPoint: Double = 22
    public static let chipHitSlop: Double = 64
    public static let chipHitIsPainted = false
    public static let chipTitles = ["Recenter", "Layers", "Packs"]
    public static let chipRowIncludesLight = false

    public static let showsShareReturnLastMarkOnMap = false
    public static let showsSearchPatternsOnMap = false
    public static let showsExpeditionBannerOnMap = false
    public static let showsGearOnMap = false
    public static let showsFieldVisionOnMap = false
    public static let showsExpeditionPanelsOnMap = false

    public static let compassLockIsRightEdgeStack = true
    public static let compassLockIsMidMapSlabs = false
    public static let drawsBothRightEdgeStacks = false

    public static let vitalsIsFatBottomToggle = false
    public static let vitalsIs56LeadingOverlay = true
    public static let vitalsPaintedHeight: Double = 56

    public static let sosIsTabViewSibling = true
    public static let sosStackedInMapPanel = false
    public static let sosRecedesWithHUD = false
    public static let sosDiameter: Double = 88

    public static let puckDiameter: Double = 36
    public static let puckIsMapKitBlue = false
    public static let overlayIgnoresBottomSafeArea = false

    public static let mapTabSymbol = "map"
    public static let mapTabSymbolRendering = "monochrome"

    /// Dest/route in play shows the nav stack. Otherwise chips. Never both.
    public static func rightEdgeShowsNav(routeInPlay: Bool) -> Bool {
        routeInPlay
    }

    public static func rightEdgeShowsChips(routeInPlay: Bool) -> Bool {
        !routeInPlay
    }
}
