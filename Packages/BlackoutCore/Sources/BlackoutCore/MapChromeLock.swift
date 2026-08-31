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

    /// Opacity 0 keeps the 56h slot so Layers / Packs do not jump.
    public static let recenterSlotReserved = true

    /// GPS lock (12 m) is on-center until the user pans. Pack-pin is not the signal.
    public static func cameraIsOnCenter(userMovedCamera: Bool, gpsLocked: Bool = false) -> Bool {
        _ = gpsLocked
        return !userMovedCamera
    }

    /// Compass / GPS accuracy. Tiny pill, not a 56h full-width bar.
    public static let lockHUDIsFullWidthBar = false
    public static let lockHUDPaintedHeight: Double = 28

    public static let layersTitles = ["Pack tiles", "Streets", "Topo"]
    public static let streetsLayerDefaultOn = false
    public static let topoLayerDefaultOn = false
    public static let duskGradesPackTiles = true
    public static let usesGoogleLogo = false
    public static let searchFieldSitsUnderHUD = true
    public static let pinsDestMarkSearch = true
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
    public static let vitalsIsRootSibling = true
    public static let vitalsSitsInSOSBand = true
    public static let vitalsCoversFieldCards = false

    public static func showsVitalsOverlay(tab: String) -> Bool {
        _ = tab
        return true
    }

    /// Field Injury / Guide cards sit above the dual chip + SOS band.
    public static func fieldContentBottomClearance(hasTabBar: Bool) -> Double {
        vitalsPaintedHeight + SOSChrome.gap + SOSChrome.fabBottomInset(hasTabBar: hasTabBar)
    }
}

/// Pack search. Type stays on the field; submit may sheet; pick starts Walk.
public enum MapPackSearchPolicy {
    public static let usesFocusState = true
    public static let contentShapesWholeBar = true
    public static let runsOnQueryChange = true
    public static let typingPresentsSheet = false
    public static let typingShowsDropdown = true
    public static let missOpensSheet = false
    public static let missShowsEmptyInList = true
    public static let submitStillRuns = true
    public static let submitPresentsSheet = false
    public static let submitPicksSingleHit = true
    public static let dropdownRowsStealMapTaps = true
    public static let pickStartsNavigate = true
    public static let pickIsCameraOnly = false
    public static let pickLocksDestWhenNoRoute = true
    public static let searchMissHoldsChrome = false
    public static let focusedHoldsChrome = true
    public static let recedeDisablesFocusedField = false

    public static func presentsSheet(
        query: String,
        hitCount: Int,
        empty: Bool,
        submitted: Bool = false
    ) -> Bool {
        _ = query
        _ = hitCount
        _ = empty
        _ = submitted
        return false
    }

    public static func presentsDropdown(
        query: String,
        hitCount: Int,
        empty: Bool,
        submitted: Bool = false
    ) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if submitted, hitCount == 1 { return false }
        return hitCount > 0 || empty
    }

    public static func shouldPickOnSubmit(hitCount: Int) -> Bool {
        hitCount == 1
    }

    public static func startsWalkPreview(hasOrigin: Bool, hasGraphRoute: Bool) -> Bool {
        hasOrigin && hasGraphRoute
    }

    public static func locksCompassWhenNoRoute(hasOrigin: Bool, hasGraphRoute: Bool) -> Bool {
        !startsWalkPreview(hasOrigin: hasOrigin, hasGraphRoute: hasGraphRoute)
    }

    public static func recedeAllowsHitTesting(
        isReceded: Bool,
        fieldFocused: Bool,
        reduceMotion: Bool
    ) -> Bool {
        if fieldFocused || reduceMotion { return true }
        return !isReceded
    }

    public static func holdChrome(
        existingHold: Bool,
        fieldFocused: Bool,
        searchMiss: Bool = false
    ) -> Bool {
        if searchMiss, !fieldFocused { return existingHold }
        return existingHold || fieldFocused
    }
}
