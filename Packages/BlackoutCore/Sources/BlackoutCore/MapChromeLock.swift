import Foundation

/// Signed-off Map chrome. Mocks are SoT. Device-32 slab stack is the fail.
public enum MapChromeLock {
    public static let surface = "ZStack.fullBleed"
    public static let tabCount = 3
    public static let mapIsCroppedPage = false

    public static let chipPaintedHeight: Double = 56
    public static let chipGlyphPoint: Double = 22
    public static let chipGap: Double = 8
    public static let chipHitSlop: Double = 64
    public static let chipHitSlopInset: Double = 4
    public static let chipHitIsPainted = false
    public static let chipHitIsLayoutMinHeight = false
    public static let chipTitles = ["Recenter", "Find civ", "Water", "Packs", "Satellite"]
    public static let showsFindCivWaterChips = true
    /// Walk heading-up lives on the tile canvas, not a Layers pile and not MapsRootView.
    public static let headingUpWhileWalk = true
    public static let walkOffCourseHaptic = true
    /// Return-to-start polyline on the canvas. Not Share/Return/Last MARK slabs.
    public static let paintsReturnBreadcrumbOnMap = true
    /// Pack-gap (50 recode, CPV stays 49): z16 town insets (TX/NM/FL) and statewide
    /// `routing/graph.bin` are not in this tree. Do not stall chrome+routing generating them.
    public static let packGapZ16TownInsetsInTree = false
    public static let packGapStatewideGraphsInTree = false

    public static func appliesHeadingUp(walkActive: Bool, headingUp: Bool) -> Bool {
        headingUpWhileWalk && walkActive && headingUp
    }

    public static func shouldFireOffCourseHaptic(wasOffRoute: Bool, nowOffRoute: Bool) -> Bool {
        walkOffCourseHaptic && nowOffRoute && !wasOffRoute
    }
    public static let layersChipOnMap = false
    public static let satelliteChipOnMap = true
    public static let hideStrangerBlips = true
    public static let strangerRadarDefaultOn = false
    public static let initsViewshedOnLaunch = false
    public static let initsLiDAROnLaunch = false
    public static let initsManDownOnLaunch = false
    public static let initsSlopeOnLaunch = false
    public static let killsDuskGradePipeline = true
    public static let actionButtonDefaultOn = false
    public static let backTapDefaultOn = false
    public static let controlCenterDefaultOn = false
    public static let flashlightDefaultOn = false
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

    public static let sosIsTabViewSibling = false
    public static let sosPaintsFAB = false
    public static let sosStackedInMapPanel = false
    public static let sosRecedesWithHUD = false
    public static let sosHidesForKeyboard = false
    public static let sosLiftsAboveKeyboard = false
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

    /// Crisis 2026-08-31 21:30: Mapbox Standard LOOK on pack vectors. No Mapbox SDK.
    public static let daylightStreetsAreBase = true
    public static let layersTitles: [String] = []
    public static let defaultPaintIsDuskAerial = false
    public static let aerialOverlayDefaultOn = false
    public static let defaultPaintsLabeledUSGS = false
    public static let defaultPaintsCountyNames = false
    public static let defaultPaintsHighwayShields = false
    public static let remapsLabeledPackTilesToDuskAerial = false
    public static let packTilesLayerDefaultOn = false
    public static let streetsLayerDefaultOn = true
    public static let contoursLayerDefaultOn = false
    public static let trailsLayerDefaultOn = false
    public static let topoLayerDefaultOn = false
    public static let recedesBasemapWhenRouteInPlay = true
    /// Paper fill under daylight streets. Not Surface.void dusk.
    public static let daylightLandRed: Double = 0.93
    public static let daylightLandGreen: Double = 0.94
    public static let daylightLandBlue: Double = 0.91

    public static func basemapAlpha(routeInPlay: Bool) -> Double {
        if recedesBasemapWhenRouteInPlay, routeInPlay { return 0.42 }
        return 1
    }
    public static let pinsDefaultOn = true
    /// Last-launch UserDefaults must not turn streets/topo on. Session toggle only.
    public static let streetsTopoReadPersistedOnLaunch = false
    /// Pack rasters already print county/street names. Do not add a second label pass.
    public static let paintsPackLabelOverlayWhenTopoOff = false
    public static let duskGradesPackTiles = false
    /// Device 39 FAIL: multiply + 0.42 void crushed pack rasters to a black well.
    /// Overlay-only wash (38 path) keeps USGS/terrain visible under dusk.
    public static let duskUsesMultiply = false
    /// Paper + ink both flatten so county / I-10 type does not survive the invert.
    public static let duskCrushesCountyLabels = true
    /// Per-pixel dusk remap in `draw` is the Map crawl. Cache + off-main fill-in.
    public static let duskRemapBlocksDraw = false
    public static let duskRemapCachesTiles = true
    public static let canvasRedrawsVisibleRectOnly = true
    /// Overlay-only wash. 0.42 × multiply was the killer; 0.22 grades dusk without zeroing luminance.
    public static let duskGradeAlpha: Double = 0.22
    public static let duskGradeColorName = "Surface.void"

    /// Overlay blend: `tile * (1 - alpha) + void * alpha`. Mid-gray pack tiles must stay terrain, not void.
    public static func duskResultLuminance(tileLuminance: Double) -> Double {
        let voidLuminance = 7.0 / 255.0
        let a = duskGradeAlpha
        return tileLuminance * (1.0 - a) + voidLuminance * a
    }

    /// USGS paper is near-white with black type. Paper and ink both flatten to dusk
    /// ground so county / highway words do not survive as glowing labels.
    public static func duskAerialRGB(tileLuminance: Double) -> (Double, Double, Double) {
        let t = min(1, max(0, tileLuminance))
        let dusk: Double
        if duskCrushesCountyLabels, t > 0.82 || t < 0.28 {
            dusk = 0.18
        } else {
            dusk = 0.16 + (1.0 - t) * 0.38
        }
        return (
            12.0 / 255.0 + dusk * 0.55,
            16.0 / 255.0 + dusk * 0.50,
            22.0 / 255.0 + dusk * 0.58
        )
    }

    public static func duskAerialLuminance(tileLuminance: Double) -> Double {
        let rgb = duskAerialRGB(tileLuminance: tileLuminance)
        return 0.2126 * rgb.0 + 0.7152 * rgb.1 + 0.0722 * rgb.2
    }
    public static let usesGoogleLogo = false

    /// OfflineMapView fills the ZStack. Letterbox fit is the device-38 black well.
    public static let canvasIgnoresSafeArea = true
    public static let canvasMaxFrameInfinity = true
    public static let canvasUIViewAutoresizes = true
    public static let canvasCoverNotLetterbox = true

    public static func coverZoomScale(
        viewWidth: Double,
        viewHeight: Double,
        canvasWidth: Double,
        canvasHeight: Double
    ) -> Double {
        let width = max(viewWidth, 1)
        let height = max(viewHeight, 1)
        let canvasW = max(canvasWidth, 1)
        let canvasH = max(canvasHeight, 1)
        return max(width / canvasW, height / canvasH)
    }

    public static func letterboxZoomScale(
        viewWidth: Double,
        viewHeight: Double,
        canvasWidth: Double,
        canvasHeight: Double
    ) -> Double {
        let width = max(viewWidth, 1)
        let height = max(viewHeight, 1)
        let canvasW = max(canvasWidth, 1)
        let canvasH = max(canvasHeight, 1)
        return min(width / canvasW, height / canvasH)
    }

    /// Per-frame `setNeedsDisplay` on pan is why the map feels unusable.
    public static let redrawCanvasOnPan = false
    public static let reportsScaleOnEveryScroll = false
    public static let headingRedrawStepDegrees: Double = 8

    public static func shouldRedrawAfterScroll(zoomIntegerChanged: Bool) -> Bool {
        zoomIntegerChanged
    }

    public static func shouldRedrawForHeading(previous: Double?, next: Double?) -> Bool {
        switch (previous, next) {
        case (nil, nil):
            return false
        case (nil, _?), (_?, nil):
            return true
        case let (last?, incoming?):
            let delta = abs(incoming - last)
            let wrapped = min(delta, 360 - delta)
            return wrapped >= headingRedrawStepDegrees
        }
    }

    public static func shouldRedrawForFix(
        previousLat: Double?,
        previousLon: Double?,
        nextLat: Double?,
        nextLon: Double?
    ) -> Bool {
        switch (previousLat, previousLon, nextLat, nextLon) {
        case (nil, nil, nil, nil):
            return false
        case (nil, _, _?, _), (_, nil, _, _?), (_?, _, nil, _), (_, _?, _, nil):
            return true
        case let (plat?, plon?, nlat?, nlon?):
            return abs(nlat - plat) >= 0.0004 || abs(nlon - plon) >= 0.0004
        default:
            return previousLat != nextLat || previousLon != nextLon
        }
    }

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
    /// Walk chrome (Crisis 2026-08-31 20:30). Idle map stays clean.
    public static let paintsWalkTurnPlate = true
    public static let walkTurnPlateShowsMuteEnd = false
    public static let paintsWalkLockOnBanner = true
    public static let walkLockOnBannerHeight: Double = 56
    public static let paintsWalkScaleAndCompass = true
    public static let hidesSearchDuringWalk = true
    public static let walkShowsEndUnderTurnPlate = true
    public static let pinSheetIsMetalSlab = false

    /// Crisis 2026-08-31 15:57: dual I AM OK chrome is deleted. Roster two-tap stays.
    public static let paintsVitalsChrome = false
    public static let vitalsIsRootSibling = false
    public static let vitalsSitsInSOSBand = false
    public static let vitalsCoversFieldCards = false
    public static let vitalsNeverOnField = true
    public static let fieldPlateUsesSafeArea = true
    public static let fieldContentFitsSafeWidth = true
    public static let fieldContentHorizontalInset: Double = 20

    public static func hasParty(
        nearbyPeerCount: Int,
        partyPeerCount: Int = 0,
        expeditionOpen: Bool
    ) -> Bool {
        nearbyPeerCount > 0 || partyPeerCount > 0 || expeditionOpen
    }

    /// Dead. Dual is not chrome. Expedition roster two-tap is PartyVitalsPlate.
    public static func showsVitalsOverlay(
        tab: String,
        nearbyPeerCount: Int = 0,
        partyPeerCount: Int = 0,
        expeditionOpen: Bool = false
    ) -> Bool {
        _ = tab
        _ = nearbyPeerCount
        _ = partyPeerCount
        _ = expeditionOpen
        return paintsVitalsChrome
    }

    /// Recenter / Layers / Packs recede when Map search is focused so they do not sit on the keyboard.
    public static func showsRightEdgeChips(searchFocused: Bool) -> Bool {
        !searchFocused
    }

    /// Field Guide / Ask / Next sit above the 88pt SOS disk, not the 56pt chip.
    public static func fieldContentBottomClearance(hasTabBar: Bool) -> Double {
        max(vitalsPaintedHeight, SOSChrome.fab) + SOSChrome.gap + SOSChrome.fabBottomInset(hasTabBar: hasTabBar)
    }
}

/// Pack search. Type stays on the field; submit may sheet; pick starts Walk.
public enum MapPackSearchPolicy {
    public static let usesFocusState = true
    public static let contentShapesWholeBar = true
    public static let runsOnQueryChange = true
    public static let searchDebounceMilliseconds: Double = 180

    public static func shouldRunQuerySearch(elapsedMs: Double) -> Bool {
        elapsedMs >= searchDebounceMilliseconds
    }
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
    public static let pickAutoStartsGuidance = true
    public static let pickLocksDestWhenNoRoute = true
    public static let pickDismissesHits = true
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
        submitted: Bool = false,
        picked: Bool = false
    ) -> Bool {
        if pickDismissesHits, picked { return false }
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
