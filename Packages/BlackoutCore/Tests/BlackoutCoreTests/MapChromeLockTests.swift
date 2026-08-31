import XCTest
@testable import BlackoutCore

final class MapChromeLockTests: XCTestCase {
    func testMapIsFullBleedZStackNotACroppedPage() {
        XCTAssertEqual(MapChromeLock.surface, "ZStack.fullBleed")
        XCTAssertFalse(MapChromeLock.mapIsCroppedPage)
        XCTAssertEqual(MapChromeLock.tabCount, 4)
        XCTAssertEqual(RootChromeLock.tabCount, 4)
    }

    func testChipsAre56PaintedWithInvisible64SlopNoLight() {
        XCTAssertEqual(MapChromeLock.chipPaintedHeight, 56)
        XCTAssertEqual(MapChromeLock.chipGlyphPoint, 22)
        XCTAssertEqual(MapChromeLock.chipGap, 8)
        XCTAssertEqual(MapChromeLock.chipHitSlop, 64)
        XCTAssertEqual(MapChromeLock.chipHitSlopInset, 4)
        XCTAssertFalse(MapChromeLock.chipHitIsPainted)
        XCTAssertFalse(MapChromeLock.chipHitIsLayoutMinHeight)
        XCTAssertEqual(MapChromeLock.chipTitles, ["Recenter", "Layers", "Packs"])
        XCTAssertFalse(MapChromeLock.chipRowIncludesLight)
        XCTAssertLessThan(MapChromeLock.chipPaintedHeight, MapChromeLock.chipHitSlop)
        XCTAssertLessThan(MapChromeLock.chipPaintedHeight, MapChromeLock.sosDiameter)
        XCTAssertEqual(MapChromeLock.chipPaintedHeight + MapChromeLock.chipGap, 64)
        XCTAssertEqual(
            MapChromeLock.chipPaintedHeight + MapChromeLock.chipHitSlopInset * 2,
            MapChromeLock.chipHitSlop
        )
    }

    func testRecenterOpacityZeroWhenOnCenter() {
        XCTAssertEqual(MapChromeLock.recenterOpacity(onCenter: true), 0)
        XCTAssertEqual(MapChromeLock.recenterOpacity(onCenter: false), 1)
        XCTAssertTrue(MapChromeLock.recenterSlotReserved)
        XCTAssertTrue(MapChromeLock.cameraIsOnCenter(userMovedCamera: false))
        XCTAssertFalse(MapChromeLock.cameraIsOnCenter(userMovedCamera: true))
        XCTAssertTrue(MapChromeLock.cameraIsOnCenter(userMovedCamera: false, gpsLocked: true))
        XCTAssertFalse(MapChromeLock.cameraIsOnCenter(userMovedCamera: true, gpsLocked: true))
    }

    func testSearchHitsDoNotLandOnMap() {
        XCTAssertTrue(MapChromeLock.showsAddressSearchOnMap)
        XCTAssertFalse(MapChromeLock.showsSearchHitsOnMap)
        XCTAssertTrue(MapChromeLock.showsSearchHitsInSheet)
        XCTAssertTrue(MapChromeLock.searchRecedesWithChrome)
        XCTAssertFalse(MapChromeLock.showsSearchHitsAsSlabsOnMap)
        XCTAssertFalse(MapChromeLock.showsRadarOnMap)
        XCTAssertFalse(MapChromeLock.showsRadarOverlayWhenRadarOn)
        XCTAssertFalse(MapChromeLock.radarIsFifthTab)
        XCTAssertFalse(MapChromeLock.paintsRadarOnMap(radarOn: false))
        XCTAssertFalse(MapChromeLock.paintsRadarOnMap(radarOn: true))
        XCTAssertFalse(MapChromeLock.radarDefaultOn)
        XCTAssertEqual(MapChromeLock.radarSelfPoint, 260)
    }

    func testKillsDevice32PermanentSlabStack() {
        XCTAssertFalse(MapChromeLock.showsShareReturnLastMarkOnMap)
        XCTAssertFalse(MapChromeLock.showsSearchPatternsOnMap)
        XCTAssertFalse(MapChromeLock.showsExpeditionBannerOnMap)
        XCTAssertFalse(MapChromeLock.showsGearOnMap)
        XCTAssertFalse(MapChromeLock.showsFieldVisionOnMap)
        XCTAssertFalse(MapChromeLock.showsExpeditionPanelsOnMap)
        XCTAssertFalse(MapChromeLock.compassLockIsMidMapSlabs)
        XCTAssertTrue(MapChromeLock.compassLockIsRightEdgeStack)
        XCTAssertFalse(MapChromeLock.vitalsIsFatBottomToggle)
        XCTAssertTrue(MapChromeLock.vitalsIs56LeadingOverlay)
        XCTAssertEqual(MapChromeLock.vitalsPaintedHeight, 56)
        XCTAssertTrue(MapChromeLock.vitalsPlateIsRaised)
        XCTAssertFalse(MapChromeLock.vitalsPlateIsBtnMetal)
        XCTAssertEqual(PartyVitalsCopy.chipHeight, 56)
    }

    func testSOSIs88SiblingAndDoesNotRecede() {
        XCTAssertTrue(MapChromeLock.sosIsTabViewSibling)
        XCTAssertTrue(RootChromeLock.sosIsRootViewSibling)
        XCTAssertFalse(MapChromeLock.sosStackedInMapPanel)
        XCTAssertFalse(MapChromeLock.sosRecedesWithHUD)
        XCTAssertEqual(MapChromeLock.sosDiameter, 88)
        XCTAssertEqual(SOSChrome.fab, 88)
        XCTAssertFalse(MapChromeLock.overlayIgnoresBottomSafeArea)
        XCTAssertEqual(SOSChrome.fabBottomInset(hasTabBar: true), 8 + 49)
        XCTAssertEqual(SOSChrome.fabBottomInset(hasTabBar: false), 8)
    }

    func testFollowPuckIs36RedNotMapKitBlue() {
        XCTAssertEqual(MapChromeLock.puckDiameter, 36)
        XCTAssertFalse(MapChromeLock.puckIsMapKitBlue)
        XCTAssertEqual(MapChromeLock.mapTabSymbol, "map")
        XCTAssertEqual(MapChromeLock.mapTabSymbolRendering, "monochrome")
    }

    func testRightEdgeNeverDrawsBothStacks() {
        XCTAssertFalse(MapChromeLock.drawsBothRightEdgeStacks)
        XCTAssertTrue(MapChromeLock.rightEdgeShowsNav(routeInPlay: true))
        XCTAssertFalse(MapChromeLock.rightEdgeShowsChips(routeInPlay: true))
        XCTAssertFalse(MapChromeLock.rightEdgeShowsNav(routeInPlay: false))
        XCTAssertTrue(MapChromeLock.rightEdgeShowsChips(routeInPlay: false))
    }

    func testIdleMapIsPackTilesPinsSearchNotARadarHUD() {
        XCTAssertFalse(MapChromeLock.lockHUDIsFullWidthBar)
        XCTAssertEqual(MapChromeLock.lockHUDPaintedHeight, 28)
        XCTAssertLessThan(MapChromeLock.lockHUDPaintedHeight, MapChromeLock.chipPaintedHeight)
        XCTAssertEqual(MapChromeLock.layersTitles, ["Streets", "Contours", "Trails"])
        XCTAssertFalse(MapChromeLock.streetsLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.contoursLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.trailsLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.topoLayerDefaultOn)
        XCTAssertTrue(MapChromeLock.duskGradesPackTiles)
        XCTAssertTrue(MapChromeLock.defaultPaintIsDuskAerial)
        XCTAssertFalse(MapChromeLock.defaultPaintsLabeledUSGS)
        XCTAssertFalse(MapChromeLock.defaultPaintsCountyNames)
        XCTAssertFalse(MapChromeLock.defaultPaintsHighwayShields)
        XCTAssertTrue(MapChromeLock.pinsDefaultOn)
        XCTAssertFalse(MapChromeLock.usesGoogleLogo)
        XCTAssertTrue(MapChromeLock.searchFieldSitsUnderHUD)
        XCTAssertTrue(MapChromeLock.pinsDestMarkSearch)
        XCTAssertFalse(MapChromeLock.layersIncludeRadar)
        XCTAssertFalse(MapChromeLock.layersIncludeSlope)
        XCTAssertFalse(MapChromeLock.layersIncludeViewshed)
        XCTAssertFalse(MapChromeLock.layersIncludeNightRed)
        XCTAssertFalse(MapChromeLock.layersIncludeSearch)
        XCTAssertFalse(MapChromeLock.layersIncludeLiDAR)
        XCTAssertFalse(MapChromeLock.layersIncludeNavigate)
        XCTAssertFalse(MapChromeLock.layersIncludeFind)
        XCTAssertFalse(MapChromeLock.layersIncludeHeadingUp)
        XCTAssertFalse(MapChromeLock.layersIncludeSweepAudio)
        XCTAssertTrue(MapChromeLock.tapPinShowsNameSheet)
        XCTAssertFalse(MapChromeLock.tapPinStartsRoute)
        XCTAssertTrue(MapChromeLock.prefersPackImagery)
        XCTAssertFalse(MapChromeLock.usesNetworkSatellite)
        XCTAssertFalse(MapChromeLock.paintsFieldModePlateOnIdleMap)
        XCTAssertFalse(MapChromeLock.paintsDeadReckoningChipOnMap)
        XCTAssertFalse(MapChromeLock.paintsScaleBarOnMap)
        XCTAssertFalse(MapChromeLock.pinSheetIsMetalSlab)
        XCTAssertTrue(MapChromeLock.showsVitalsOverlay(tab: "map"))
        XCTAssertTrue(MapChromeLock.showsVitalsOverlay(tab: "comms"))
        XCTAssertTrue(MapChromeLock.showsVitalsOverlay(tab: "field"))
        XCTAssertTrue(MapChromeLock.showsVitalsOverlay(tab: "expedition"))
        XCTAssertTrue(MapChromeLock.vitalsIsRootSibling)
        XCTAssertTrue(MapChromeLock.vitalsSitsInSOSBand)
        XCTAssertFalse(MapChromeLock.vitalsCoversFieldCards)
        XCTAssertEqual(
            MapChromeLock.fieldContentBottomClearance(hasTabBar: true),
            MapChromeLock.vitalsPaintedHeight + SOSChrome.gap + SOSChrome.fabBottomInset(hasTabBar: true)
        )
        XCTAssertGreaterThan(
            MapChromeLock.fieldContentBottomClearance(hasTabBar: true),
            MapChromeLock.vitalsPaintedHeight
        )
    }

    func testPackSearchTapFocusesFieldAndMapDoesNotSteal() {
        XCTAssertTrue(MapPackSearchPolicy.usesFocusState)
        XCTAssertTrue(MapPackSearchPolicy.contentShapesWholeBar)
        XCTAssertTrue(MapPackSearchPolicy.focusedHoldsChrome)
        XCTAssertTrue(MapPackSearchPolicy.holdChrome(existingHold: false, fieldFocused: true))
        XCTAssertFalse(MapPackSearchPolicy.holdChrome(existingHold: false, fieldFocused: false))
    }

    func testPackSearchQueryMatchAndMissPresentSheet() {
        XCTAssertTrue(MapPackSearchPolicy.runsOnQueryChange)
        XCTAssertFalse(MapPackSearchPolicy.typingPresentsSheet)
        XCTAssertTrue(MapPackSearchPolicy.typingShowsDropdown)
        XCTAssertFalse(MapPackSearchPolicy.missOpensSheet)
        XCTAssertTrue(MapPackSearchPolicy.missShowsEmptyInList)
        XCTAssertTrue(MapPackSearchPolicy.submitStillRuns)
        XCTAssertFalse(MapPackSearchPolicy.submitPresentsSheet)
        XCTAssertTrue(MapPackSearchPolicy.submitPicksSingleHit)
        XCTAssertTrue(MapPackSearchPolicy.dropdownRowsStealMapTaps)
        XCTAssertFalse(MapPackSearchPolicy.presentsSheet(query: "h", hitCount: 5, empty: false, submitted: false))
        XCTAssertFalse(MapPackSearchPolicy.presentsSheet(query: "Walmart Pharmacy", hitCount: 1, empty: false, submitted: true))
        XCTAssertFalse(MapPackSearchPolicy.presentsSheet(query: "zzzz", hitCount: 0, empty: true, submitted: true))
        XCTAssertTrue(MapPackSearchPolicy.presentsDropdown(query: "h", hitCount: 5, empty: false, submitted: false))
        XCTAssertTrue(MapPackSearchPolicy.presentsDropdown(query: "zzzz", hitCount: 0, empty: true, submitted: false))
        XCTAssertTrue(MapPackSearchPolicy.presentsDropdown(query: "zzzz", hitCount: 0, empty: true, submitted: true))
        XCTAssertFalse(MapPackSearchPolicy.presentsDropdown(query: "Walmart Pharmacy", hitCount: 1, empty: false, submitted: true))
        XCTAssertFalse(MapPackSearchPolicy.presentsSheet(query: "", hitCount: 0, empty: false, submitted: true))
        XCTAssertFalse(MapPackSearchPolicy.presentsDropdown(query: "", hitCount: 0, empty: false, submitted: false))
    }

    func testPickStartsNavigateNotCameraOnly() {
        XCTAssertTrue(MapPackSearchPolicy.pickStartsNavigate)
        XCTAssertFalse(MapPackSearchPolicy.pickIsCameraOnly)
        XCTAssertTrue(MapPackSearchPolicy.dropdownRowsStealMapTaps)
    }

    func testSubmitSingleHitPicksAndDoesNotPresentSheet() {
        XCTAssertTrue(MapPackSearchPolicy.shouldPickOnSubmit(hitCount: 1))
        XCTAssertFalse(MapPackSearchPolicy.shouldPickOnSubmit(hitCount: 0))
        XCTAssertFalse(MapPackSearchPolicy.shouldPickOnSubmit(hitCount: 5))
        XCTAssertFalse(MapPackSearchPolicy.presentsSheet(query: "Walmart Pharmacy", hitCount: 1, empty: false, submitted: true))
    }

    func testPickWithOriginAndGraphStartsPreview() {
        XCTAssertTrue(MapPackSearchPolicy.startsWalkPreview(hasOrigin: true, hasGraphRoute: true))
        XCTAssertFalse(MapPackSearchPolicy.locksCompassWhenNoRoute(hasOrigin: true, hasGraphRoute: true))
    }

    func testPickNilOriginLocksDestAndCompass() {
        XCTAssertFalse(MapPackSearchPolicy.startsWalkPreview(hasOrigin: false, hasGraphRoute: false))
        XCTAssertTrue(MapPackSearchPolicy.locksCompassWhenNoRoute(hasOrigin: false, hasGraphRoute: false))
        XCTAssertTrue(MapPackSearchPolicy.pickLocksDestWhenNoRoute)
    }

    func testPickOffGraphLocksDestAndCompass() {
        XCTAssertFalse(MapPackSearchPolicy.startsWalkPreview(hasOrigin: true, hasGraphRoute: false))
        XCTAssertTrue(MapPackSearchPolicy.locksCompassWhenNoRoute(hasOrigin: true, hasGraphRoute: false))
    }

    func testMissEmptyDoesNotHoldChromeForever() {
        XCTAssertFalse(MapPackSearchPolicy.searchMissHoldsChrome)
        XCTAssertFalse(
            MapPackSearchPolicy.holdChrome(
                existingHold: false,
                fieldFocused: false,
                searchMiss: true
            )
        )
        XCTAssertTrue(
            MapPackSearchPolicy.holdChrome(
                existingHold: false,
                fieldFocused: true,
                searchMiss: true
            )
        )
    }

    func testRecedeDoesNotDisableFocusedSearchField() {
        XCTAssertFalse(MapPackSearchPolicy.recedeDisablesFocusedField)
        XCTAssertTrue(
            MapPackSearchPolicy.recedeAllowsHitTesting(
                isReceded: true,
                fieldFocused: true,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            MapPackSearchPolicy.recedeAllowsHitTesting(
                isReceded: true,
                fieldFocused: false,
                reduceMotion: false
            )
        )
        XCTAssertTrue(
            MapPackSearchPolicy.recedeAllowsHitTesting(
                isReceded: true,
                fieldFocused: false,
                reduceMotion: true
            )
        )
    }

    func testCanvasFillsZStackCoverNotLetterboxStrip() {
        XCTAssertTrue(MapChromeLock.canvasIgnoresSafeArea)
        XCTAssertTrue(MapChromeLock.canvasMaxFrameInfinity)
        XCTAssertTrue(MapChromeLock.canvasUIViewAutoresizes)
        XCTAssertTrue(MapChromeLock.canvasCoverNotLetterbox)
        let cover = MapChromeLock.coverZoomScale(
            viewWidth: 390,
            viewHeight: 844,
            canvasWidth: 8000,
            canvasHeight: 3000
        )
        let letterbox = MapChromeLock.letterboxZoomScale(
            viewWidth: 390,
            viewHeight: 844,
            canvasWidth: 8000,
            canvasHeight: 3000
        )
        XCTAssertGreaterThan(cover, letterbox)
        XCTAssertEqual(cover, 844 / 3000, accuracy: 1e-9)
        XCTAssertEqual(letterbox, 390 / 8000, accuracy: 1e-9)
    }

    func testStreetsTopoStayOffUnlessToggledThisSession() {
        XCTAssertFalse(MapChromeLock.streetsLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.topoLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.contoursLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.trailsLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.packTilesLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.streetsTopoReadPersistedOnLaunch)
        XCTAssertFalse(MapChromeLock.paintsPackLabelOverlayWhenTopoOff)
        XCTAssertFalse(MapChromeLock.duskUsesMultiply)
        XCTAssertEqual(MapChromeLock.duskGradeAlpha, 0.22, accuracy: 0.001)
    }

    func testDefaultPaintIsDuskAerialWithoutLabeledUSGS() {
        XCTAssertTrue(MapChromeLock.defaultPaintIsDuskAerial)
        XCTAssertFalse(MapChromeLock.defaultPaintsLabeledUSGS)
        XCTAssertFalse(MapChromeLock.defaultPaintsCountyNames)
        XCTAssertFalse(MapChromeLock.defaultPaintsHighwayShields)
        XCTAssertTrue(MapChromeLock.remapsLabeledPackTilesToDuskAerial)
        XCTAssertEqual(MapChromeLock.layersTitles, ["Streets", "Contours", "Trails"])
        XCTAssertFalse(MapChromeLock.layersTitles.contains("Pack tiles"))
    }

    func testDuskAerialRemapHidesPaperWhiteLabels() {
        let paper = MapChromeLock.duskAerialLuminance(tileLuminance: 0.95)
        XCTAssertLessThan(paper, 0.45)
        let ink = MapChromeLock.duskAerialLuminance(tileLuminance: 0.10)
        XCTAssertGreaterThan(ink, 0.20)
        let washed = MapChromeLock.duskResultLuminance(
            tileLuminance: MapChromeLock.duskAerialLuminance(tileLuminance: 0.50)
        )
        XCTAssertGreaterThan(washed, 0.20)
        XCTAssertLessThan(washed, 0.70)
    }

    func testFieldLayersStartOffExceptPins() {
        XCTAssertFalse(MapChromeLock.streetsLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.contoursLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.trailsLayerDefaultOn)
        XCTAssertTrue(MapChromeLock.pinsDefaultOn)
    }

    func testDuskGradeDoesNotZeroTileLuminance() {
        XCTAssertFalse(MapChromeLock.duskUsesMultiply)
        let washed = MapChromeLock.duskResultLuminance(tileLuminance: 0.70)
        XCTAssertGreaterThan(washed, 0.45)
        XCTAssertLessThan(washed, 0.70)
        XCTAssertGreaterThan(MapChromeLock.duskResultLuminance(tileLuminance: 0.35), 0.20)
    }

    func testPickDismissesHitsAndDropdown() {
        XCTAssertTrue(MapPackSearchPolicy.pickDismissesHits)
        XCTAssertFalse(
            MapPackSearchPolicy.presentsDropdown(
                query: "El Paso Children's Hospital",
                hitCount: 1,
                empty: false,
                picked: true
            )
        )
        XCTAssertTrue(
            MapPackSearchPolicy.presentsDropdown(
                query: "El Paso Children's Hospital",
                hitCount: 1,
                empty: false,
                picked: false
            )
        )
    }

    func testPackSearchQueryChangeDebounces() {
        XCTAssertTrue(MapPackSearchPolicy.runsOnQueryChange)
        XCTAssertEqual(MapPackSearchPolicy.searchDebounceMilliseconds, 180)
        XCTAssertFalse(MapPackSearchPolicy.shouldRunQuerySearch(elapsedMs: 0))
        XCTAssertFalse(MapPackSearchPolicy.shouldRunQuerySearch(elapsedMs: 179))
        XCTAssertTrue(MapPackSearchPolicy.shouldRunQuerySearch(elapsedMs: 180))
    }

    func testMapPaintDoesNotRedrawEveryScrollFrame() {
        XCTAssertFalse(MapChromeLock.redrawCanvasOnPan)
        XCTAssertFalse(MapChromeLock.reportsScaleOnEveryScroll)
        XCTAssertFalse(MapChromeLock.shouldRedrawAfterScroll(zoomIntegerChanged: false))
        XCTAssertTrue(MapChromeLock.shouldRedrawAfterScroll(zoomIntegerChanged: true))
        XCTAssertFalse(MapChromeLock.shouldRedrawForHeading(previous: 10, next: 12))
        XCTAssertTrue(MapChromeLock.shouldRedrawForHeading(previous: 10, next: 20))
        XCTAssertTrue(MapChromeLock.shouldRedrawForHeading(previous: nil, next: 0))
        XCTAssertFalse(MapChromeLock.shouldRedrawForFix(
            previousLat: 31.76,
            previousLon: -106.48,
            nextLat: 31.76001,
            nextLon: -106.48
        ))
        XCTAssertTrue(MapChromeLock.shouldRedrawForFix(
            previousLat: 31.76,
            previousLon: -106.48,
            nextLat: 31.77,
            nextLon: -106.48
        ))
    }
}
