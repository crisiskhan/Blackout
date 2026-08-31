import Foundation

/// Signed-off Map chrome. Mocks are SoT. Device-32 slab stack is the fail.
public enum MapChromeLock {
    public static let surface = "ZStack.fullBleed"
    public static let tabCount = 4
    public static let mapIsCroppedPage = false

    public static let chipPaintedHeight: Double = 56
    public static let chipGlyphPoint: Double = 22
    public static let chipGap: Double = 8
    public static let chipHitSlop: Double = 64
    public static let chipHitSlopInset: Double = 4
    public static let chipHitIsPainted = false
    public static let chipHitIsLayoutMinHeight = false
    public static let chipTitles = ["Recenter", "Layers", "Packs"]
    public static let chipRowIncludesLight = false
    public static let showsAddressSearchOnMap = true
    public static let showsSearchHitsOnMap = false
    public static let showsSearchHitsInSheet = true
    public static let searchRecedesWithChrome = true
    public static let showsSearchHitsAsSlabsOnMap = false
    public static let showsRadarOnMap = false
    /// Product wanted DBZ polar HUD on Map when Radar is on. Crisis override: never.
    public static let showsRadarOverlayWhenRadarOn = false
    public static let radarIsFifthTab = false
    public static let radarDefaultOn = false
    public static let radarSelfPoint: Double = 260

    /// Layers → Radar is its own screen. The Map tab never paints sweep/rings/wedge.
    public static func paintsRadarOnMap(radarOn: Bool) -> Bool {
        _ = radarOn
        return false
    }

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
    public static let vitalsPlateIsRaised = true
    public static let vitalsPlateIsBtnMetal = false

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

    /// Recenter is not painted when the camera is already on-center.
    public static func recenterOpacity(onCenter: Bool) -> Double {
        onCenter ? 0 : 1
    }

    /// Compass / GPS accuracy. Tiny pill, not a 56h full-width bar.
    public static let lockHUDIsFullWidthBar = false
    public static let lockHUDPaintedHeight: Double = 28

    public static let layersTitles = ["Pack tiles", "Trail"]
    public static let layersIncludeRadar = false
    public static let layersIncludeSlope = false
    public static let layersIncludeViewshed = false
    public static let layersIncludeNightRed = false
    public static let layersIncludeSearch = false
    public static let layersIncludeLiDAR = false
    public static let layersIncludeNavigate = false
    public static let layersIncludeFind = false
    public static let layersIncludeHeadingUp = false
    public static let layersIncludeSweepAudio = false

    public static let tapPinShowsNameSheet = true
    public static let tapPinStartsRoute = false
    public static let prefersPackImagery = true
    public static let usesNetworkSatellite = false
    public static let paintsFieldModePlateOnIdleMap = false
    public static let paintsDeadReckoningChipOnMap = false
    public static let paintsScaleBarOnMap = false
    public static let pinSheetIsMetalSlab = false

    /// I AM OK sits in the SOS band. Field cards must stay clear.
    public static func showsVitalsOverlay(tab: String) -> Bool {
        tab != "field"
    }
}
