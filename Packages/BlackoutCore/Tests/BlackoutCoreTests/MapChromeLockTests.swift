import XCTest
@testable import BlackoutCore

final class MapChromeLockTests: XCTestCase {
    func testMapIsFullBleedZStackNotACroppedPage() {
        XCTAssertEqual(MapChromeLock.surface, "ZStack.fullBleed")
        XCTAssertFalse(MapChromeLock.mapIsCroppedPage)
        XCTAssertEqual(MapChromeLock.tabCount, 3)
        XCTAssertEqual(RootChromeLock.tabCount, 3)
    }

    func testChipsAre56PaintedWithInvisible64SlopNoLight() {
        XCTAssertEqual(MapChromeLock.chipPaintedHeight, 56)
        XCTAssertEqual(MapChromeLock.chipGlyphPoint, 22)
        XCTAssertEqual(MapChromeLock.chipGap, 8)
        XCTAssertEqual(MapChromeLock.chipHitSlop, 64)
        XCTAssertEqual(MapChromeLock.chipHitSlopInset, 4)
        XCTAssertFalse(MapChromeLock.chipHitIsPainted)
        XCTAssertFalse(MapChromeLock.chipHitIsLayoutMinHeight)
        XCTAssertEqual(MapChromeLock.chipTitles, ["Recenter", "Find civ", "Water", "Packs", "Satellite"])
        XCTAssertTrue(MapChromeLock.showsFindCivWaterChips)
        XCTAssertFalse(MapChromeLock.layersChipOnMap)
        XCTAssertTrue(MapChromeLock.satelliteChipOnMap)
        XCTAssertTrue(MapChromeLock.hideStrangerBlips)
        XCTAssertFalse(MapChromeLock.strangerRadarDefaultOn)
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
        XCTAssertFalse(MapChromeLock.sosIsTabViewSibling)
        XCTAssertFalse(RootChromeLock.sosIsRootViewSibling)
        XCTAssertTrue(RootChromeLock.sosChromeDeleted)
        XCTAssertFalse(RootChromeLock.sosFabOnChrome)
        XCTAssertFalse(RootChromeLock.sosConfirmOnChrome)
        XCTAssertFalse(MapChromeLock.sosPaintsFAB)
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
        XCTAssertEqual(MapChromeLock.layersTitles, [])
        XCTAssertTrue(MapChromeLock.streetsLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.contoursLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.trailsLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.topoLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.duskGradesPackTiles)
        XCTAssertFalse(MapChromeLock.defaultPaintIsDuskAerial)
        XCTAssertTrue(MapChromeLock.daylightStreetsAreBase)
        XCTAssertTrue(MapChromeLock.killsDuskGradePipeline)
        XCTAssertFalse(MapChromeLock.aerialOverlayDefaultOn)
        XCTAssertFalse(MapChromeLock.initsViewshedOnLaunch)
        XCTAssertFalse(MapChromeLock.initsLiDAROnLaunch)
        XCTAssertFalse(MapChromeLock.initsManDownOnLaunch)
        XCTAssertFalse(MapChromeLock.initsSlopeOnLaunch)
        XCTAssertFalse(RootChromeLock.sosOnlyCollapseOnColdLaunch)
        XCTAssertFalse(RootChromeLock.liveActivitySOSEnabled)
        XCTAssertFalse(RootChromeLock.expeditionIsTab)
        XCTAssertEqual(MapChromeLock.basemapAlpha(routeInPlay: false), 1)
        XCTAssertEqual(MapChromeLock.basemapAlpha(routeInPlay: true), 0.42)
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
        XCTAssertFalse(MapChromeLock.paintsVitalsChrome)
        XCTAssertFalse(MapChromeLock.vitalsIsRootSibling)
        XCTAssertFalse(MapChromeLock.vitalsCoversFieldCards)
        XCTAssertFalse(MapChromeLock.sosHidesForKeyboard)
        XCTAssertFalse(MapChromeLock.sosLiftsAboveKeyboard)
        XCTAssertTrue(RootChromeLock.settingsSitsInSegmentRow)
        XCTAssertFalse(RootChromeLock.settingsIsTopLeadingOverlay)
        XCTAssertFalse(RootChromeLock.pttIgnoresBottomSafeArea)
    }

    func testWalkChromeMatchesMockExceptSOS() {
        XCTAssertTrue(MapChromeLock.paintsWalkTurnPlate)
        XCTAssertFalse(MapChromeLock.walkTurnPlateShowsMuteEnd)
        XCTAssertTrue(MapChromeLock.paintsWalkLockOnBanner)
        XCTAssertEqual(MapChromeLock.walkLockOnBannerHeight, 56)
        XCTAssertTrue(MapChromeLock.paintsWalkScaleAndCompass)
        XCTAssertTrue(MapChromeLock.hidesSearchDuringWalk)
        XCTAssertTrue(MapChromeLock.walkShowsEndUnderTurnPlate)
        XCTAssertFalse(MapChromeLock.paintsScaleBarOnMap)
        XCTAssertFalse(MapChromeLock.paintsVitalsChrome)
        XCTAssertFalse(MapChromeLock.paintsRadarOnMap(radarOn: true))
        XCTAssertEqual(MapChromeLock.sosDiameter, 88)
        XCTAssertEqual(SOSChrome.trailing, 16)
        XCTAssertEqual(SOSChrome.gap, 8)
        XCTAssertTrue(MapPackSearchPolicy.pickAutoStartsGuidance)
        XCTAssertTrue(MapChromeLock.headingUpWhileWalk)
        XCTAssertTrue(MapChromeLock.appliesHeadingUp(walkActive: true, headingUp: true))
        XCTAssertFalse(MapChromeLock.appliesHeadingUp(walkActive: false, headingUp: true))
        XCTAssertFalse(MapChromeLock.appliesHeadingUp(walkActive: true, headingUp: false))
        XCTAssertTrue(MapChromeLock.walkOffCourseHaptic)
        XCTAssertTrue(MapChromeLock.shouldFireOffCourseHaptic(wasOffRoute: false, nowOffRoute: true))
        XCTAssertFalse(MapChromeLock.shouldFireOffCourseHaptic(wasOffRoute: true, nowOffRoute: true))
        XCTAssertFalse(MapChromeLock.shouldFireOffCourseHaptic(wasOffRoute: false, nowOffRoute: false))
        XCTAssertTrue(MapChromeLock.paintsReturnBreadcrumbOnMap)
        XCTAssertFalse(MapChromeLock.showsShareReturnLastMarkOnMap)
        XCTAssertTrue(MapChromeLock.showsFindCivWaterChips)
        XCTAssertFalse(MapChromeLock.layersIncludeFind)
        XCTAssertFalse(MapChromeLock.layersIncludeHeadingUp)
        XCTAssertFalse(MapChromeLock.packGapZ16TownInsetsInTree)
        XCTAssertFalse(MapChromeLock.packGapStatewideGraphsInTree)
    }

    func testVitalsChromeIsGoneOnEveryTabSoloOrParty() {
        XCTAssertFalse(MapChromeLock.paintsVitalsChrome)
        for tab in ["map", "comms", "field", "expedition"] {
            XCTAssertFalse(
                MapChromeLock.showsVitalsOverlay(
                    tab: tab,
                    nearbyPeerCount: 0,
                    partyPeerCount: 0,
                    expeditionOpen: false
                ),
                "dual must be gone on \(tab) when solo"
            )
            XCTAssertFalse(
                MapChromeLock.showsVitalsOverlay(
                    tab: tab,
                    nearbyPeerCount: 3,
                    partyPeerCount: 3,
                    expeditionOpen: true
                ),
                "dual must be gone on \(tab) when a party is present"
            )
        }
    }

    func testFieldPlateFitsSafeWidthAndClearsSOS() {
        XCTAssertTrue(MapChromeLock.fieldPlateUsesSafeArea)
        XCTAssertTrue(MapChromeLock.fieldContentFitsSafeWidth)
        XCTAssertEqual(MapChromeLock.fieldContentHorizontalInset, 20)
    }

    func testFieldClearanceClearsThe88SOSDisk() {
        let expected = SOSChrome.fab + SOSChrome.gap + SOSChrome.fabBottomInset(hasTabBar: true)
        XCTAssertEqual(MapChromeLock.fieldContentBottomClearance(hasTabBar: true), expected)
        XCTAssertGreaterThan(
            MapChromeLock.fieldContentBottomClearance(hasTabBar: true),
            SOSChrome.fab + SOSChrome.fabBottomInset(hasTabBar: true)
        )
        XCTAssertGreaterThan(
            MapChromeLock.fieldContentBottomClearance(hasTabBar: true),
            MapChromeLock.vitalsPaintedHeight + SOSChrome.gap + SOSChrome.fabBottomInset(hasTabBar: true)
        )
    }

    func testRightEdgeChipsHideWhenSearchFocused() {
        XCTAssertTrue(MapChromeLock.showsRightEdgeChips(searchFocused: false))
        XCTAssertFalse(MapChromeLock.showsRightEdgeChips(searchFocused: true))
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
        XCTAssertTrue(MapPackSearchPolicy.pickAutoStartsGuidance)
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
        XCTAssertTrue(MapChromeLock.streetsLayerDefaultOn)
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
        XCTAssertFalse(MapChromeLock.defaultPaintIsDuskAerial)
        XCTAssertTrue(MapChromeLock.daylightStreetsAreBase)
        XCTAssertFalse(MapChromeLock.aerialOverlayDefaultOn)
        XCTAssertFalse(MapChromeLock.defaultPaintsLabeledUSGS)
        XCTAssertFalse(MapChromeLock.defaultPaintsCountyNames)
        XCTAssertFalse(MapChromeLock.defaultPaintsHighwayShields)
        XCTAssertFalse(MapChromeLock.remapsLabeledPackTilesToDuskAerial)
        XCTAssertEqual(MapChromeLock.layersTitles, [])
        XCTAssertFalse(MapChromeLock.layersTitles.contains("Pack tiles"))
    }

    func testDuskAerialRemapHidesPaperWhiteLabels() {
        XCTAssertTrue(MapChromeLock.duskCrushesCountyLabels)
        XCTAssertFalse(MapChromeLock.duskRemapBlocksDraw)
        XCTAssertTrue(MapChromeLock.duskRemapCachesTiles)
        XCTAssertTrue(MapChromeLock.canvasRedrawsVisibleRectOnly)
        let paper = MapChromeLock.duskAerialLuminance(tileLuminance: 0.95)
        let ink = MapChromeLock.duskAerialLuminance(tileLuminance: 0.10)
        XCTAssertLessThan(paper, 0.35)
        XCTAssertLessThan(ink, 0.35)
        XCTAssertLessThan(abs(paper - ink), 0.12)
        let washed = MapChromeLock.duskResultLuminance(
            tileLuminance: MapChromeLock.duskAerialLuminance(tileLuminance: 0.50)
        )
        XCTAssertGreaterThan(washed, 0.20)
        XCTAssertLessThan(washed, 0.70)
    }

    func testFieldLayersStartOffExceptPins() {
        XCTAssertTrue(MapChromeLock.streetsLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.contoursLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.trailsLayerDefaultOn)
        XCTAssertTrue(MapChromeLock.pinsDefaultOn)
        XCTAssertFalse(MapChromeLock.layersChipOnMap)
        XCTAssertTrue(MapChromeLock.satelliteChipOnMap)
        XCTAssertFalse(MapChromeLock.actionButtonDefaultOn)
        XCTAssertFalse(MapChromeLock.backTapDefaultOn)
        XCTAssertFalse(MapChromeLock.controlCenterDefaultOn)
        XCTAssertFalse(MapChromeLock.flashlightDefaultOn)
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
