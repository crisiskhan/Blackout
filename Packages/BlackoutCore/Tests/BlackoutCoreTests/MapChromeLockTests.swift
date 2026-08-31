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
        XCTAssertEqual(MapChromeLock.layersTitles, ["Pack tiles", "Streets", "Topo"])
        XCTAssertFalse(MapChromeLock.streetsLayerDefaultOn)
        XCTAssertFalse(MapChromeLock.topoLayerDefaultOn)
        XCTAssertTrue(MapChromeLock.duskGradesPackTiles)
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
        XCTAssertTrue(MapPackSearchPolicy.missOpensSheet)
        XCTAssertTrue(MapPackSearchPolicy.submitStillRuns)
        XCTAssertTrue(MapPackSearchPolicy.presentsSheet(query: "mesa pharmacy", hitCount: 1, empty: false))
        XCTAssertTrue(MapPackSearchPolicy.presentsSheet(query: "zzzz", hitCount: 0, empty: true))
        XCTAssertFalse(MapPackSearchPolicy.presentsSheet(query: "", hitCount: 0, empty: false))
        XCTAssertFalse(MapPackSearchPolicy.presentsSheet(query: "   ", hitCount: 0, empty: false))
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
}
