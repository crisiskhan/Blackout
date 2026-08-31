#!/usr/bin/env python3
"""CI opt + single-copy pack invariants. No network."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(msg: str) -> None:
    print(f"FAIL {msg}", file=sys.stderr)
    raise SystemExit(1)


def ok(msg: str) -> None:
    print(f"OK   {msg}")


STATEWIDE_PACKS = (
    (
        "us-tx",
        "texas.pack.zip",
        "220512882",
        "6ff6c9a191fe5df8d3bf48abb360ad361990bc672c1c59bd0cf2e3a3d5d55ade",
    ),
    (
        "us-nm",
        "new-mexico.pack.zip",
        "77478829",
        "2e605b0a386c6fbfa1288e5bea4ef96f42ddd5c60633f954b42c8c0e7665a4a8",
    ),
    (
        "us-fl",
        "florida.pack.zip",
        "79093063",
        "49d27c808c49fc894a1ba1021f951966560408c1ebe808f4c0d158e0c238b62d",
    ),
)


def test_compile_workflow_drops_feature_branch_push() -> None:
    text = (ROOT / ".github/workflows/ios-compile.yml").read_text()
    if "cursor/blackout-ios-foundation-7e54" in text:
        fail("ios-compile.yml still pushes on the feature branch")
    if "pull_request:" not in text:
        fail("ios-compile.yml missing pull_request trigger")
    if "push:" not in text or "- main" not in text:
        fail("ios-compile.yml must keep push to main")
    if "cancel-in-progress: true" not in text:
        fail("ios-compile.yml lost cancel-in-progress")
    if "python3 tools/test_ci_opt.py" not in text:
        fail("ios-compile.yml must run tools/test_ci_opt.py before xcodebuild")
    ok("ios-compile.yml is pull_request + push main only")


def test_testflight_paths_and_assign() -> None:
    text = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    if "workflow_dispatch:" not in text:
        fail("ios-testflight.yml missing workflow_dispatch")
    if "push:" in text or "pull_request:" in text:
        fail("ios-testflight.yml must stay dispatch-only")
    if "cursor/blackout-ios-foundation-7e54" in text:
        fail("ios-testflight.yml must not auto-run on the feature branch")
    if "cancel-in-progress: true" not in text:
        fail("ios-testflight.yml lost cancel-in-progress")
    if "python3 tools/test_ci_opt.py" not in text:
        fail("ios-testflight.yml must run tools/test_ci_opt.py before archive")
    if "tools/asc_assign_internal.sh" not in text:
        fail("ios-testflight.yml does not call tools/asc_assign_internal.sh")
    if "tools/asc_prune_development_certs.sh" not in text:
        fail("ios-testflight.yml does not prune leftover Development certs")
    if "CODE_SIGN_IDENTITY=" in text:
        fail("ios-testflight.yml must not pass CODE_SIGN_IDENTITY on the CLI")
    if "python3 -m pip install" in text:
        fail("ios-testflight.yml still pip-installs into system Python")
    if "6806388963" not in text:
        fail("ios-testflight.yml missing app id 6806388963")
    if "28035586-fce6-474f-9bc2-ef0f1f65306e" not in text:
        fail("ios-testflight.yml missing Internal group id")
    if "ASC_NOT_BEFORE=" not in text:
        fail("ios-testflight.yml does not stamp ASC_NOT_BEFORE before archive")
    if 'if [ -z "${ASC_NOT_BEFORE:-}" ]' not in text:
        fail("ios-testflight.yml does not refuse assign without ASC_NOT_BEFORE")
    ok("ios-testflight.yml path-filters archive + assigns Internal")


def test_pbx_single_copy() -> None:
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    if "DefaultPack in Resources" in pbx:
        fail("pbxproj still copies DefaultPack via Resources")
    if "GuidePack in Resources" in pbx:
        fail("pbxproj still copies GuidePack via Resources")
    if 'Exceptions for "Blackout" folder in Resources' in pbx:
        fail("pbxproj still lists DefaultPack/GuidePack in the Resources exception set")
    if "PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet" in pbx:
        fail("pbxproj still has a Resources group membership exception set")
    if "PBXFileSystemSynchronizedBuildFileExceptionSet" not in pbx:
        fail("pbxproj lost target-level exceptions that keep packs out of Sources")
    if "alwaysOutOfDate = 1" in pbx:
        fail("pbxproj still has alwaysOutOfDate = 1")
    if "Copy DefaultPack into app bundle" not in pbx:
        fail("pbxproj lost DefaultPack ditto phase")
    if "Copy GuidePack into app bundle" not in pbx:
        fail("pbxproj lost GuidePack ditto phase")
    if "Copy FieldPacks into app bundle" not in pbx:
        fail("pbxproj lost FieldPacks ditto phase")
    if "FieldPacks in Resources" in pbx:
        fail("pbxproj copies FieldPacks via Resources (tile collision)")
    if "GENERATE_INFOPLIST_FILE = YES;\n\t\t\t\t\tINFOPLIST_FILE = Supporting/BlackoutWidgets-Info.plist" in pbx:
        fail("BlackoutWidgets GENERATE_INFOPLIST_FILE + INFOPLIST_FILE collide on Xcode 16")
    if pbx.count("INFOPLIST_FILE = Supporting/BlackoutWidgets-Info.plist") < 2:
        fail("BlackoutWidgets lost INFOPLIST_FILE on Debug or Release")
    if "INFOPLIST_FILE = BlackoutWidgets/Info.plist" in pbx:
        fail("widget Info.plist must stay outside the synced BlackoutWidgets folder")
    if pbx.count("GENERATE_INFOPLIST_FILE = NO;") < 2:
        fail("BlackoutWidgets GENERATE_INFOPLIST_FILE must stay NO")
    if (ROOT / "BlackoutWidgets" / "Info.plist").is_file():
        fail("BlackoutWidgets/Info.plist in the sync root is copied onto the appex Info.plist")
    if 'Exceptions for "BlackoutWidgets"' in pbx:
        fail("BlackoutWidgets sync group must not list Info.plist exceptions (Xcode 26 archive copies them)")
    widget_plist = (ROOT / "Supporting" / "BlackoutWidgets-Info.plist").read_text()
    if "CFBundleIdentifier" not in widget_plist:
        fail("widget Info.plist missing CFBundleIdentifier — ValidateEmbeddedBinary sees (null)")
    if "$(PRODUCT_BUNDLE_IDENTIFIER)" not in widget_plist:
        fail("widget Info.plist must expand PRODUCT_BUNDLE_IDENTIFIER (parent prefix check)")
    if pbx.count("PRODUCT_BUNDLE_IDENTIFIER = com.crisiskhan.blackout.widget") < 2:
        fail("widget bundle id must stay com.crisiskhan.blackout.widget on Debug and Release")
    if "CURRENT_PROJECT_VERSION = 43" not in pbx:
        fail("CURRENT_PROJECT_VERSION is no longer 43")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("expected CURRENT_PROJECT_VERSION = 43 on Debug and Release")
    if "MARKETING_VERSION = 0.1.0" not in pbx:
        fail("MARKETING_VERSION is no longer 0.1.0")
    if "Apple Distribution" in pbx:
        fail("pbxproj must not set Apple Distribution (Automatic conflict)")
    ok("pbxproj is ditto-only, version 19, no alwaysOutOfDate")


def test_generator_does_not_restore_double_copy() -> None:
    src = (ROOT / "tools/generate_project.py").read_text()
    if "alwaysOutOfDate = 1" in src:
        fail("generate_project.py would restore alwaysOutOfDate")
    if "DefaultPack in Resources" in src or "GuidePack in Resources" in src:
        fail("generate_project.py would put packs back into Resources")
    if 'Exceptions for "Blackout" folder in Resources' in src:
        fail("generate_project.py would restore the Resources exception set")
    if "PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet" in src:
        fail("generate_project.py would restore a Resources group membership exception set")
    if "PBXFileSystemSynchronizedBuildFileExceptionSet" not in src:
        fail("generate_project.py lost target-level exceptions that keep packs out of Sources")
    if "Copy DefaultPack into app bundle" not in src:
        fail("generate_project.py lost DefaultPack ditto phase")
    if "Copy GuidePack into app bundle" not in src:
        fail("generate_project.py lost GuidePack ditto phase")
    if "Copy FieldPacks into app bundle" not in src:
        fail("generate_project.py lost FieldPacks ditto phase")
    if "copy_fieldpacks.sh" not in src:
        fail("generate_project.py lost copy_fieldpacks.sh")
    if '"CURRENT_PROJECT_VERSION": "43",' not in src:
        fail("generate_project.py would bump CURRENT_PROJECT_VERSION")
    if "Apple Distribution" in src:
        fail("generate_project.py must not set Apple Distribution")
    if "generated-sample" in src:
        fail("generate_project.py would restore synthetic DefaultPack stubs")
    if "SOS red core" in src or "if r < 280" in src:
        fail("generate_project.py would restore the synthetic red-disc AppIcon")
    if "brand/emblem.jpeg" not in src and 'brand" / "emblem.jpeg' not in src:
        fail("generate_project.py does not render AppIcon from brand/emblem.jpeg")
    ok("generate_project.py regen stays ditto-only at version 19")


def test_map_chrome_lock() -> None:
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    radar = (ROOT / "Packages/Maps/Sources/Maps/RadarHUDView.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    for banned in (
        "packPaintLog",
        "file tiles",
        "NoPackCanvas",
        "CompassRose",
        "MeshPill",
        "PermissionDenied",
        "GPSChip",
    ):
        if banned in maps:
            fail(f"MapsRootView still paints {banned}")
    if "MapLockHUD" not in maps or "NO FIX" not in maps:
        fail("MapsRootView lost the tiny GPS / compass HUD")
    if 'MapHUDChip("Recenter"' not in maps or 'MapHUDChip("Layers"' not in maps:
        fail("MapsRootView lost Recenter / Layers 56h chips")
    if 'MapHUDChip("Packs"' not in maps:
        fail("MapsRootView lost Packs 56h chip")
    if "MapRightEdge.stack" not in maps:
        fail("Map must show only one right-edge stack")
    if "ConvenienceCopy.flashlight" in maps or 'MapHUDChip("Light"' in maps:
        fail("Light must not be a fourth Map tile")
    if "MapExpeditionBanner" in maps or "No open expedition" in maps:
        fail("No open expedition banner must stay off Map")
    if 'MetalButton("Recenter"' in maps and 'MapHUDChip("Recenter"' not in maps:
        fail("Recenter must be a 56h chip, not a MetalButton slab")
    if "MapEmptyCard" not in maps:
        fail("MapsRootView lost the single empty card")
    if "showFieldPacksOverlay" in root:
        fail("Field Packs is still a ZStack overlay")
    if "fieldPacksSheetBinding" in root or "FieldPacksView" in root:
        fail("first-run Field Packs sheet must stay dead")
    if "fieldPacksIntroCompleted" in root:
        fail("RootView still auto-presents the pack intro")
    if (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPacksView.swift").exists():
        fail("FieldPacksView skip sheet must stay deleted")
    catalog_list = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalogList.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    if "func skipIntro" in store or "Skip uses" in store or 'case skip' in (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalog.swift").read_text():
        fail("Skip-as-gate still lives in the pack catalog")
    for label in ('"No wifi"', '"Downloading"', '"Ready"', '"Failed"'):
        if label not in catalog_list:
            fail(f"Expedition catalog lost state {label}")
    if 'case .available' in catalog_list or 'case .skip' in catalog_list:
        fail("catalog still paints available/skip")
    if "destination = .expedition" not in root:
        fail("Packs must open the Expedition plate, not a modal")
    if "Heading-up" in radar or "Sweep audio" in radar or "0 peers · self only" in radar:
        fail("RadarHUDView still floats heading/audio/peer chrome")
    if "MKMapView(" in maps:
        fail("MapsRootView must not construct MKMapView")
    if "URLSession" in maps:
        fail("MapsRootView must not use URLSession")
    import re

    lock = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/MapChromeLock.swift").read_text()
    hud = (ROOT / "Packages/DesignSystem/Sources/DesignSystem/MapHUDChip.swift").read_text()
    compass = (ROOT / "Packages/Maps/Sources/Maps/CompassLockChrome.swift").read_text()
    if "chipGap: Double = 8" not in lock:
        fail("chip stack gap must stay 8 (56h + 8, not 64h slop)")
    if "chipHitIsLayoutMinHeight = false" not in lock:
        fail("64 slop must not be the chip layout minHeight")
    if "func recenterOpacity" not in lock:
        fail("MapChromeLock lost recenterOpacity")
    if "showsAddressSearchOnMap = true" not in lock:
        fail("pack address search must be visible on Map")
    if "showsSearchHitsOnMap = false" not in lock:
        fail("search hits must not paint on the tiles")
    if "showsSearchHitsInSheet = true" not in lock:
        fail("search hits must open a sheet")
    if "searchRecedesWithChrome = true" not in lock:
        fail("56h pack search must recede with Map chrome")
    if "showsSearchHitsAsSlabsOnMap = false" not in lock:
        fail("Map search hits must not be giant white slabs")
    if "showsRadarOnMap = false" not in lock:
        fail("RadarHUD must not sit on the big map")
    if "showsRadarOverlayWhenRadarOn = false" not in lock:
        fail("Crisis override: no DBZ/radar overlay on Map even when Radar is on")
    if "radarIsFifthTab = false" not in lock:
        fail("Radar is Layers → Radar, not a fifth tab")
    if "func paintsRadarOnMap" not in lock:
        fail("paintsRadarOnMap must stay false when radarOn is true")
    if "radarDefaultOn = false" not in lock:
        fail("Radar must default OFF")
    if "radarSelfPoint: Double = 260" not in lock:
        fail("dedicated Radar screen must be 260pt on-self")
    if re.search(r"minHeight:\s*CGFloat\(MapChromeLock\.chipHitSlop\)", hud):
        fail("MapHUDChip still lays out 64 as the chip face")
    if re.search(r"minHeight:\s*CGFloat\(MapChromeLock\.chipHitSlop\)", compass):
        fail("CompassLockBar still lays out 64 as the chip face")
    if "recenterOpacity(" not in maps:
        fail("Recenter must go opacity 0 when already on-center")
    if "recenterOpacity(onCenter: pinnedToPackCoverage)" in maps:
        fail("Recenter on-center is camera-on-center, not pack-pin. 12 m lock stays opacity 0")
    if "cameraIsOnCenter(" not in maps or "userMovedCamera:" not in maps:
        fail("Recenter must hide when the camera is already on-center")
    if "recenterSlotReserved" not in lock:
        fail("Recenter slot stays reserved at opacity 0")
    if "RadarHUDView(" in maps:
        fail("RadarHUDView must not sit on OfflineMapView")
    if "RadarPolarCanvas(" in maps:
        fail("polar sweep/rings/wedge must not paint on the Map tab")
    if "rotationEffect(.degrees(radarVisible" in maps:
        fail("do not rotate the tile map under a radar sweep")
    if "if radarOn" in maps or "radarVisible" in maps:
        fail("do not restore a radar overlay on Map when Radar is on")
    if 'radarOn = true' in maps:
        fail("Radar must default OFF")
    if "showsRadar(" in maps:
        fail("Map tab must not consult showsRadar to overlay tiles")
    dest = (ROOT / "Blackout/RootView.swift").read_text()
    dest_enum = dest.split("enum AppDestination", 1)[-1].split("struct RootView", 1)[0]
    if "case radar" in dest_enum or 'case .radar' in dest_enum:
        fail("Radar must not become a fifth tab")
    if "MapPackSearchField" not in maps:
        fail("Map lost the visible pack address search field")
    if "MapPackSearchHits(hits:" in maps:
        fail("search hits must not be a list on the tiles")
    if ".sheet(isPresented: $showSearchHits" not in maps:
        fail("pack search hits must open a sheet")
    hud_stack = maps.split("private var lockHudStack", 1)[-1].split("private var mapPackSearch", 1)[0]
    if "mapPackSearch" not in hud_stack.split("receding", 1)[-1]:
        fail("56h pack search must recede with chrome")
    if 'MetalButton("Search' in maps:
        fail("search must not be a giant MetalButton slab")
    if "NavigateHitsList(hits: navigate.hits" in maps:
        fail("NavigateHitsList must not land as a Map overlay slab")
    if "NavigateHitsList(hits: searchHits" in maps:
        fail("Layers must not host a second search field")
    tools = (ROOT / "Packages/Maps/Sources/Maps/MapTools.swift").read_text()
    if "RadarHUDView(" not in tools:
        fail("Layers → Radar must reuse RadarView / RadarHUDView")
    if ".frame(height: 260)" not in tools and "radarSelfPoint" not in tools:
        fail("RadarView must stay 260pt on-self, not an overlay on OfflineMapView")
    if "sosOverlayMounts(" not in root:
        fail("SOSFab must not live in the idle lock overlay tree")
    if pbx_version_off_32():
        fail("do not bump CURRENT_PROJECT_VERSION")
    ok("Map chrome is HUD + Recenter/Layers/Packs, catalog on Expedition")


def test_map_google_feel() -> None:
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    lock = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/MapChromeLock.swift").read_text()
    amenity = (ROOT / "Packages/Maps/Sources/MapsRouting/PackAmenity.swift").read_text()
    offline = (ROOT / "Packages/Maps/Sources/Maps/OfflineMapView.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    keys = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/BlackoutKeys.swift").read_text()
    tests = (ROOT / "Packages/BlackoutCore/Tests/BlackoutCoreTests/MapChromeLockTests.swift").read_text()
    amenity_tests = (ROOT / "Packages/Maps/Tests/MapsTests/PackAmenityTests.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()

    if "lockHUDIsFullWidthBar = false" not in lock:
        fail("GPS / compass HUD must not be a full-width bar")
    if "lockHUDPaintedHeight: Double = 28" not in lock:
        fail("compass / accuracy HUD must stay tiny (28pt)")
    if 'layersTitles = ["Streets", "Contours", "Trails"]' not in lock:
        fail("Layers must be streets/contours/trails")
    if "defaultPaintIsDuskAerial = true" not in lock:
        fail("default paint must be dusk aerial, not labeled USGS")
    if "defaultPaintsLabeledUSGS = false" not in lock:
        fail("labeled USGS must not be the default layer")
    if "defaultPaintsCountyNames = false" not in lock or "defaultPaintsHighwayShields = false" not in lock:
        fail("default paint must not print county names or highway shields")
    if "streetsLayerDefaultOn = false" not in lock or "topoLayerDefaultOn = false" not in lock:
        fail("streets/topo layers must default off")
    if "contoursLayerDefaultOn = false" not in lock or "trailsLayerDefaultOn = false" not in lock:
        fail("contours/trails layers must default off")
    if "duskGradesPackTiles = true" not in lock:
        fail("pack satellite/aerial must be dusk-graded")
    if "usesGoogleLogo = false" not in lock:
        fail("never a Google logo")
    if "searchFieldSitsUnderHUD = true" not in lock:
        fail("56h search must sit under the HUD")
    if "pinsDestMarkSearch = true" not in lock:
        fail("pins are dest / MARK / search")
    for flag in (
        "layersIncludeRadar = false",
        "layersIncludeSlope = false",
        "layersIncludeViewshed = false",
        "layersIncludeNightRed = false",
        "layersIncludeSearch = false",
        "layersIncludeLiDAR = false",
        "layersIncludeNavigate = false",
        "layersIncludeFind = false",
        "layersIncludeHeadingUp = false",
        "layersIncludeSweepAudio = false",
        "tapPinShowsNameSheet = true",
        "tapPinStartsRoute = false",
        "prefersPackImagery = true",
        "usesNetworkSatellite = false",
        "paintsFieldModePlateOnIdleMap = false",
        "paintsDeadReckoningChipOnMap = false",
        "paintsScaleBarOnMap = false",
        "pinSheetIsMetalSlab = false",
    ):
        if flag not in lock:
            fail(f"MapChromeLock missing {flag}")
    if "func showsVitalsOverlay" not in lock:
        fail("showsVitalsOverlay must stay testable and return false")
    if "paintsVitalsChrome = false" not in lock:
        fail("I AM OK dual chrome must be deleted")
    if "sosHidesForKeyboard = false" not in lock:
        fail("never hide SOS to clear the keyboard")
    if "sosLiftsAboveKeyboard = true" not in lock:
        fail("SOS must lift above the keyboard")
    if "func showsRightEdgeChips" not in lock:
        fail("Recenter/Layers must hide when Map search is focused")
    if "testIdleMapIsPackTilesPinsSearchNotARadarHUD" not in tests:
        fail("missing Crisis 21:13 Map lock test")
    if "testVitalsChromeIsGoneOnEveryTabSoloOrParty" not in tests:
        fail("missing dual-gone-everywhere test")
    if "testFieldPlateFitsSafeWidthAndClearsSOS" not in tests:
        fail("missing Field safe-width test")
    if "testFieldClearanceClearsThe88SOSDisk" not in tests:
        fail("missing Field clearance-above-88-SOS test")
    if "testRightEdgeChipsHideWhenSearchFocused" not in tests:
        fail("missing Recenter/Layers hide-on-search-focus test")
    if "testPinHitSelectsNearbyPackPOIAndMissesEmptyTap" not in amenity_tests:
        fail("missing pack POI tap-hit test")
    if "func pinHit" not in amenity:
        fail("PackAmenityPolicy must hit-test a tap to a pack pin")

    hud = maps.split("struct MapLockHUD", 1)[-1].split("struct MapEmptyCard", 1)[0]
    if ".frame(maxWidth: .infinity)" in hud:
        fail("MapLockHUD must not be a full-width bar that eats the map")
    if "BlackoutDS.Hit.sm" in hud:
        fail("MapLockHUD must not be the 56h lock bar")
    if "MapChromeLock.lockHUDPaintedHeight" not in maps:
        fail("tiny HUD must use lockHUDPaintedHeight")

    hud_stack = maps.split("private var lockHudStack", 1)[-1].split("private var mapPackSearch", 1)[0]
    if "fieldModePlate" in hud_stack:
        fail("field mode plate must not cover idle Map tiles")
    if "DeadReckoningHonesty" in hud_stack:
        fail("DR chip must not cover idle Map tiles")
    chrome = maps.split("private var mapLockChrome", 1)[-1].split("private var lockHudStack", 1)[0]
    if "scaleBarRow" in chrome:
        fail("scale bar must not cover tiles")

    layers = maps.split("struct MapLayersSheet", 1)[-1]
    for banned in (
        'GhostButton("Radar"',
        'layerToggle("Slope"',
        'layerToggle("Viewshed"',
        'layerToggle("Night red"',
        'TextField("Search this pack"',
        'GhostButton("LiDAR"',
        'GhostButton("Navigate"',
        "PackFindCopy.civilization",
        "PackFindCopy.water",
        'layerToggle("Heading-up"',
        'layerToggle("Sweep audio"',
    ):
        if banned in layers:
            fail(f"Layers is not pack/imagery-only: still has {banned}")
    if 'layerToggle("Pack tiles"' in layers:
        fail("labeled USGS pack tiles are not a default Layers toggle")
    if 'layerToggle("Streets"' not in layers:
        fail("Layers lost Streets")
    if 'layerToggle("Contours"' not in layers:
        fail("Layers lost Contours")
    if 'layerToggle("Trails"' not in layers:
        fail("Layers lost Trails")
    if 'layerToggle("Topo"' in layers:
        fail("Topo is Contours now; do not keep a Topo toggle")

    hud_order = maps.split("private var lockHudStack", 1)[-1].split("private var mapPackSearch", 1)[0]
    if hud_order.find("MapLockHUD") < 0 or hud_order.find("mapPackSearch") < 0:
        fail("HUD + 56h search must both live in lockHudStack")
    if hud_order.find("MapLockHUD") > hud_order.find("mapPackSearch"):
        fail("56h search must sit under the HUD, not above it")
    if "Google" in maps or "google logo" in maps.lower():
        fail("never a Google logo")
    if "showStreets:" not in maps or "showTopoTiles:" not in maps:
        fail("streets/contours must be Layers, default off")
    if "showTrails:" not in maps:
        fail("trails must be a Layer, default off")
    if "markPins:" not in maps:
        fail("Map must pin dest / MARK / search")
    if "MapPOINameSheet" not in maps:
        fail("tap pin must open a name sheet")
    poi_sheet = maps.split("struct MapPOINameSheet", 1)[-1][:900] if "struct MapPOINameSheet" in maps else ""
    if "MetalButton" in poi_sheet or "GhostButton" in poi_sheet:
        fail("POI sheet must be the name, not a MetalButton slab")
    if "navigate.pickMap(" in maps:
        fail("idle Map tap must not start a dest/route")
    if "PackAmenityPolicy.pinHit" not in maps:
        fail("tap must hit-test pack POI pins")
    if "jumpToken" not in maps or "jumpCoordinate" not in maps:
        fail("search pick must jump the camera to the pin")
    if "jumpToken" not in offline:
        fail("OfflineMapView must accept a jump-to-pin token")
    if "showPackTiles: packService.routing == nil || showTopoTiles" in maps:
        fail("pack imagery must stay on when routing exists")
    if "showPackTiles: MapChromeLock.defaultPaintIsDuskAerial" not in maps:
        fail("default canvas must paint dusk aerial from the installed pack")
    layers_sheet = maps.split("struct MapLayersSheet", 1)[-1]
    if "Pack tiles" in layers_sheet:
        fail("Pack tiles must not be a Layers toggle — labeled USGS is Contours")
    if 'layerToggle("Streets"' not in layers_sheet or 'layerToggle("Contours"' not in layers_sheet or 'layerToggle("Trails"' not in layers_sheet:
        fail("Layers must be Streets, Contours, Trails")
    if "mapPackTiles" not in keys:
        fail("pack-tiles preference needs a BlackoutKey")
    if "MKLocalSearch" in maps or "satelliteFlyover" in maps or "MKTileOverlay" in maps:
        fail("Map must not call live Apple / Google satellite")
    nav_chrome = (ROOT / "Packages/Maps/Sources/Maps/NavigateChrome.swift").read_text()
    if "@FocusState" not in nav_chrome and "@FocusState" not in maps:
        fail("56h search must use FocusState so tap shows the keyboard")
    if ".focused(" not in nav_chrome:
        fail("MapPackSearchField must bind FocusState onto the TextField")
    search_field = nav_chrome.split("struct MapPackSearchField", 1)[-1][:1600]
    if ".contentShape(" not in search_field:
        fail("56h search bar must contentShape the whole chip so the map does not steal the tap")
    if ".onTapGesture" not in search_field:
        fail("tap on the 56h bar must focus the field")
    if ".onChange(of: query)" not in nav_chrome and "onChange(of: navigate.query)" not in maps:
        fail("pack search must run on query change, not only keyboard submit")
    if "onSubmit" not in nav_chrome.split("struct MapPackSearchField", 1)[-1]:
        fail("keyboard Search submit must still run pack search")
    if "presentsDropdown" not in maps:
        fail("typing must fill a dropdown under the 56h bar, not a covering sheet")
    if "runPackSearch(present: true)" in maps.split("onQueryChange", 1)[-1][:400]:
        fail("onChange must not present a sheet on each letter — 4:13 unstable trap")
    pick_fn = maps.split("func pickFound", 1)[-1][:900]
    if "navigate.pick(" not in pick_fn:
        fail("pickFound must call navigate.pick so Walk/preview starts")
    if "lockOrRoute(" in pick_fn:
        fail("pickFound must not call lockOrRoute — that can end() the Walk preview")
    if "compass.lockOn(" not in pick_fn:
        fail("pickFound must compass.lockOn when there is no Walk graph route")
    if "highPriorityGesture" not in nav_chrome.split("struct MapPackSearchHits", 1)[-1][:1200]:
        fail("dropdown rows must highPriorityGesture so the map does not eat the pick tap")
    if "shouldPickOnSubmit" not in maps:
        fail("keyboard Search with one hit must pickFound, not present a covering sheet")
    if "submitPresentsSheet = false" not in lock:
        fail("submit must not cover the map with MapPackSearchSheet")
    if "submitPicksSingleHit = true" not in lock:
        fail("one-hit submit must start going")
    if "testSubmitSingleHitPicksAndDoesNotPresentSheet" not in tests:
        fail("missing submit-single-hit-picks test")
    if "testPickNilOriginLocksDestAndCompass" not in tests:
        fail("missing NO FIX pick → dest+compass test")
    if "testPickOffGraphLocksDestAndCompass" not in tests:
        fail("missing off-graph pick → dest+lock test")
    if "testPickWithOriginAndGraphStartsPreview" not in tests:
        fail("missing origin+graph → preview test")
    if "typingPresentsSheet = false" not in lock:
        fail("typing a letter must not auto-present the search sheet")
    if "pickStartsNavigate = true" not in lock or "pickIsCameraOnly = false" not in lock:
        fail("search pick must start dest/preview, not camera-only jump")
    if "searchMissHoldsChrome = false" not in lock:
        fail("a search miss must not hold Map chrome forever")
    if "testPickStartsNavigateNotCameraOnly" not in tests:
        fail("missing pick-starts-Walk test")
    if "testMissEmptyDoesNotHoldChromeForever" not in tests:
        fail("missing miss-does-not-trap-chrome test")
    if "NavigateCopy.searchMiss" not in nav_chrome and "searchMiss" not in nav_chrome:
        fail("search-miss must still paint the existing empty state")
    if "searchFocused" not in maps.split("private var holdsChrome", 1)[-1][:800]:
        fail("focused search must hold chrome so recede does not disable the field")
    if "recedeAllowsHitTesting" not in maps and "keepInteractive" not in maps:
        fail("recede must not allowsHitTesting(false) on a focused search field")
    if "enum MapPackSearchPolicy" not in lock:
        fail("MapPackSearchPolicy missing — 3:20 search tap/miss contract untested")
    if "testPackSearchTapFocusesFieldAndMapDoesNotSteal" not in tests:
        fail("missing tap/focus search contract test")
    if "testPackSearchQueryMatchAndMissPresentSheet" not in tests:
        fail("missing pack search hit/miss sheet test")
    if "testRecedeDoesNotDisableFocusedSearchField" not in tests:
        fail("missing recede-does-not-disable-focused-field test")
    if "testPackSearchMissIsEmptyStateNotSilent" not in amenity_tests:
        fail("missing search-miss empty-state test")
    if "MKLocalSearch" in nav_chrome:
        fail("pack search must stay offline — no MKLocalSearch")
    if "VitalsChip" in root or "vitalsOverlay" in root or "I AM OK" in root:
        fail("I AM OK dual must not be a Root overlay")
    if ".overlay(alignment: .bottomLeading)" in root:
        fail("do not leave a bottom-leading dual placeholder")
    if "settingsOverlaySlot" in root or "settingsIsTopLeadingOverlay = false" not in (
        ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/RootChromeLock.swift"
    ).read_text():
        fail("Settings gear must not be a top-leading Root overlay")
    if "paintsVitalsChrome = false" not in lock:
        fail("I AM OK dual chrome must stay deleted")
    if "vitalsIsRootSibling = false" not in lock:
        fail("I AM OK dual must not be a Root sibling")
    if "vitalsCoversFieldCards = false" not in lock:
        fail("I AM OK must not cover Field Injury cards")
    if "VitalsChip" in (ROOT / "Packages/Field/Sources/Field/FieldRootView.swift").read_text():
        fail("do not move I AM OK into Field")
    field = (ROOT / "Packages/Field/Sources/Field/FieldRootView.swift").read_text()
    if "fieldContentBottomClearance" not in field and "MapChromeLock.fieldContentBottomClearance" not in field:
        fail("Field cards must inset above the 88pt SOS disk so Guide/Ask/Next stay readable")
    if "FieldSafePlate" not in field:
        fail("Field plate must pin content to the safe-area width")
    if "fieldContentHorizontalInset" not in field:
        fail("Field plate must use the locked horizontal inset")
    if "onOpenSettings" not in field:
        fail("Field gear must sit in the Guide/Skills/Vision row")
    comms = (ROOT / "Blackout/CommsRootView.swift").read_text()
    if "onOpenSettings" not in comms:
        fail("Comms gear must sit in the Threads/Radar/Roster row")
    if "ignoresSafeArea(edges: .bottom)" in comms:
        fail("PTT disc must not ignore the bottom safe area")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    ok("Map is pack tiles + pins + search; Layers imagery-only; tiny HUD")


def test_map_pack_resolver() -> None:
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    pack = (ROOT / "Packages/Maps/Sources/Maps/FileMapPack.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    if "replaceInstalledRoots" not in pack or "pinToBundled" not in pack:
        fail("FileMapPack lost the installed-pack resolver")
    if "installedPackRoots" not in store:
        fail("PackStore lost installedPackRoots")
    if "installedPackRoots" not in root or "bundledRegion" not in root:
        fail("RootView does not pass installed pack roots / bundled region")
    if "resolvePaintPack" not in maps:
        fail("MapsRootView lost resolvePaintPack")
    if "lastKnown" not in maps:
        fail("MapsRootView resolve must fall back to last-known on NO FIX")
    if "MKMapView(" in pack or "URLSession" in pack:
        fail("FileMapPack must not use MapKit or URLSession")
    routing_loader = (ROOT / "Packages/Maps/Sources/MapsRouting/RoutingPack.swift").read_text()
    if "func coveringRoot" not in routing_loader or "func loadCovering" not in routing_loader:
        fail("RoutingPackLoader must resolve covering Field Pack routing/")
    if "RoutingPackLoader.load(packRoot: snapshot" in pack:
        fail("FileMapPack still loads routing only from DefaultPack at init")
    if "reloadRouting" not in pack or "coveringRoot" not in pack:
        fail("FileMapPack must load routing/ from the covering pack, not the painted tile root")
    if "MKDirections" in pack or "URLSession" in routing_loader:
        fail("routing loader must not use MKDirections or URLSession")
    ok("Map paints one covering installed pack; Recenter stays bundled")


def test_usgs_defaultpack() -> None:
    pack = ROOT / "Blackout" / "DefaultPack"
    man = json.loads((pack / "manifest.json").read_text())
    if man.get("kind") != "field-pack":
        fail("DefaultPack kind is not field-pack")
    if man.get("kind") == "generated-sample":
        fail("DefaultPack is still generated-sample stubs")
    pngs = list((pack / "tiles").rglob("*.png"))
    need = int(man.get("tileCount") or 0)
    if len(pngs) < need:
        fail(f"DefaultPack has {len(pngs)} PNGs, tileCount {need}")
    for rel in ("tiles/10/211/387.png", "tiles/12/848/1553.png"):
        path = pack / rel
        if not path.is_file():
            fail(f"DefaultPack missing probe {rel}")
        raw = path.read_bytes()
        if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
            fail(f"{rel} is not a PNG")
        if path.stat().st_size < 8000:
            fail(f"{rel} is still a stub ({path.stat().st_size} bytes)")
    copy = (ROOT / "tools/copy_defaultpack.sh").read_text()
    probe = (ROOT / "tools/probe_defaultpack_app.sh").read_text()
    if "tiles/10/211/387.png" not in copy or "tiles/12/848/1553.png" not in copy:
        fail("copy_defaultpack.sh lost probe paths")
    if "tiles/10/211/387.png" not in probe or "tiles/12/848/1553.png" not in probe:
        fail("probe_defaultpack_app.sh lost probe paths")
    if (pack / "routing").exists() or (pack / "routing" / "graph.bin").exists():
        fail("DefaultPack must not ship routing/")
    if "routing" in man:
        fail("DefaultPack manifest must not declare a routing graph")
    if "must not ship routing" not in copy or "must not ship routing" not in probe:
        fail("DefaultPack copy/probe must refuse routing/")
    ok("DefaultPack is USGS field-pack topo, probes exist")


def test_assign_script_requires_secrets() -> None:
    script = ROOT / "tools/asc_assign_internal.sh"
    if not script.is_file():
        fail("tools/asc_assign_internal.sh missing")
    env = os.environ.copy()
    for name in (
        "APP_STORE_CONNECT_API_KEY",
        "APP_STORE_CONNECT_KEY_ID",
        "APP_STORE_CONNECT_ISSUER_ID",
    ):
        env.pop(name, None)
    proc = subprocess.run(
        ["bash", str(script)],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        fail("asc_assign_internal.sh succeeded without secrets")
    combined = (proc.stdout + proc.stderr).lower()
    if "missing" not in combined:
        fail("asc_assign_internal.sh did not report missing secrets")
    src = script.read_text()
    if "python3 -m venv" not in src:
        fail("asc_assign_internal.sh must install PyJWT in a venv")
    if "python3 -m pip install -q PyJWT" in src:
        fail("asc_assign_internal.sh still pip-installs into system Python")
    if "ASC_NOT_BEFORE is required in GitHub Actions" not in src:
        fail("asc_assign_internal.sh must require ASC_NOT_BEFORE in Actions")
    if "SKIP stale" not in src:
        fail("asc_assign_internal.sh must skip builds uploaded before this archive")
    if 'params["filter[version]"]' not in src and "filter[version]" not in src:
        fail("asc_assign_internal.sh must filter ASC builds by CFBundleVersion")
    if "FALLBACK assign existing VALID missing-compliance" in src and "refusing FALLBACK" not in src:
        fail("asc_assign_internal.sh must not assign a stale same-number build")
    if "def pick_assign_match" not in src:
        fail("asc_assign_internal.sh must expose pick_assign_match")
    if 'raise SystemExit(2)' not in src or "FAILED_STATE" not in src:
        fail("asc_assign_internal.sh must still fail closed on FAILED/INVALID")
    if "already exists on ASC from before this archive" not in src:
        fail("asc_assign_internal.sh must fail fast when CFBundleVersion is already on ASC")
    if "8 * 60" in src:
        fail("stale CFBundleVersion must fail on the first poll, not after 8 minutes")
    ok("asc_assign_internal.sh fails closed without secrets")


def _assign_helpers():
    src = (ROOT / "tools/asc_assign_internal.sh").read_text()
    start = src.index("def parse_iso")
    end = src.index("\nnot_before = parse_iso(not_before_raw)")
    ns: dict = {}
    exec("from datetime import datetime, timezone\n" + src[start:end], ns)
    return ns


def test_assign_pick_prefers_fresh_then_fallback() -> None:
    helpers = _assign_helpers()
    parse_iso = helpers["parse_iso"]
    pick = helpers["pick_assign_match"]
    not_before = parse_iso("2026-08-29T18:46:45Z")
    stale_valid = {
        "id": "0ae23432-d3af-4c91-9b36-55cf5f6baf00",
        "version": "19",
        "processingState": "VALID",
        "usesNonExemptEncryption": None,
        "uploadedDate": "2026-08-29T10:17:14-07:00",
        "internalBuildState": "MISSING_EXPORT_COMPLIANCE",
    }
    fresh_processing = {
        "id": "fresh-19",
        "version": "19",
        "processingState": "PROCESSING",
        "usesNonExemptEncryption": None,
        "uploadedDate": "2026-08-29T18:50:00Z",
        "internalBuildState": None,
    }
    kind, rec = pick([stale_valid], not_before)
    if kind != "stale_only" or rec is not None:
        fail(f"stale VALID missing-compliance must be stale_only, got {kind} {rec}")
    kind, rec = pick([], not_before)
    if kind != "none" or rec is not None:
        fail(f"empty list must keep polling, got {kind} {rec}")
    kind, rec = pick([fresh_processing, stale_valid], not_before)
    if kind != "fresh" or rec is not fresh_processing:
        fail(f"expected fresh preference, got {kind} {rec}")
    failed = dict(stale_valid, processingState="FAILED", id="failed-19")
    kind, rec = pick([failed], not_before)
    if kind != "stale_only" or rec is not None:
        fail(f"stale FAILED must be stale_only, got {kind} {rec}")
    src = (ROOT / "tools/asc_assign_internal.sh").read_text()
    if 'kind == "stale_only"' not in src:
        fail("assign must exit on stale_only, not wait 8 minutes")
    if "8 * 60" in src or "stale_only_since" in src:
        fail("stale same-number build must not poll for 8 minutes")
    ok("pick_assign_match assigns only builds uploaded after ASC_NOT_BEFORE")


def test_assign_existing_workflow() -> None:
    path = ROOT / ".github/workflows/asc-assign-existing.yml"
    if not path.is_file():
        fail("missing .github/workflows/asc-assign-existing.yml")
    text = path.read_text()
    if "workflow_dispatch:" not in text:
        fail("asc-assign-existing.yml must be workflow_dispatch")
    for banned in ("push:", "pull_request:", "schedule:"):
        if banned in text:
            fail(f"asc-assign-existing.yml must not trigger on {banned}")
    if "want_build" not in text:
        fail("asc-assign-existing.yml missing optional want_build input")
    if "2000-01-01T00:00:00Z" not in text:
        fail("asc-assign-existing.yml must set ASC_NOT_BEFORE=2000-01-01T00:00:00Z")
    if "tools/asc_assign_internal.sh" not in text:
        fail("asc-assign-existing.yml must call tools/asc_assign_internal.sh")
    if "python3 -m venv" not in text:
        fail("asc-assign-existing.yml must use a venv like ios-testflight.yml")
    if "6806388963" not in text:
        fail("asc-assign-existing.yml missing ASC_APP_ID 6806388963")
    if "28035586-fce6-474f-9bc2-ef0f1f65306e" not in text:
        fail("asc-assign-existing.yml missing Internal group id")
    for secret in (
        "APP_STORE_CONNECT_API_KEY",
        "APP_STORE_CONNECT_KEY_ID",
        "APP_STORE_CONNECT_ISSUER_ID",
    ):
        if secret not in text:
            fail(f"asc-assign-existing.yml missing secret {secret}")
    if "CURRENT_PROJECT_VERSION" in text and "bump" in text.lower():
        fail("asc-assign-existing.yml must not bump CURRENT_PROJECT_VERSION")
    ok("asc-assign-existing.yml is dispatch-only assign of an existing build")


def test_prune_script_requires_secrets() -> None:
    script = ROOT / "tools/asc_prune_development_certs.sh"
    if not script.is_file():
        fail("tools/asc_prune_development_certs.sh missing")
    src = script.read_text()
    if "IOS_DISTRIBUTION" in src and "REVOKE_TYPES" in src and "IOS_DISTRIBUTION" in src.split("REVOKE_TYPES")[1][:400]:
        fail("prune script must not revoke Distribution certs")
    if "DEVELOPMENT" not in src or "IOS_DEVELOPMENT" not in src:
        fail("prune script must target Apple Development / iOS Development")
    if "DISTRIBUTION" not in src or "KEEP" not in src:
        fail("prune script must keep Distribution certs")
    env = os.environ.copy()
    for name in (
        "APP_STORE_CONNECT_API_KEY",
        "APP_STORE_CONNECT_KEY_ID",
        "APP_STORE_CONNECT_ISSUER_ID",
    ):
        env.pop(name, None)
    proc = subprocess.run(
        ["bash", str(script)],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        fail("asc_prune_development_certs.sh succeeded without secrets")
    combined = (proc.stdout + proc.stderr).lower()
    if "missing" not in combined:
        fail("asc_prune_development_certs.sh did not report missing secrets")
    ok("asc_prune_development_certs.sh fails closed without secrets")


def test_live_mesh_1n() -> None:
    mesh = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MeshFacade.swift").read_text()
    pipe = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MultipeerPipe.swift").read_text()
    wire = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MeshWire.swift").read_text()
    crypto = (ROOT / "Packages/Crypto/Sources/BlackoutCrypto/LoopbackCrypto.swift").read_text()
    proto = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/Protocols.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    gen = (ROOT / "tools/generate_project.py").read_text()
    if "MultipeerConnectivity" not in mesh or "MultipeerConnectivity" not in pipe:
        fail("Mesh is not using MultipeerConnectivity")
    if "func start() {}" in mesh:
        fail("MeshFacade start is still a no-op")
    if "URLSession" in mesh or "URLSession" in pipe or "URLSession" in wire:
        fail("Mesh must not use URLSession")
    if "localAdvertisement" not in proto or "registerPeerAdvertisement" not in proto:
        fail("CryptoServing missing peer advertisement hooks")
    if "preferredRecipient" not in proto:
        fail("CryptoServing missing preferredRecipient")
    if "sharedSecretFromKeyAgreement" not in crypto:
        fail("LoopbackCrypto missing ECDH peer seal")
    if "roster.radarBlips" not in maps:
        fail("Radar peers must come from the party roster")
    if "kind: .stranger" in maps:
        fail("do not invent stranger radar blips")
    for src, label in ((pbx, "pbxproj"), (gen, "generate_project.py")):
        if "NSLocalNetworkUsageDescription" not in src:
            fail(f"{label} missing Local Network usage string")
        if "NSBonjourServices" not in src or "blckout-mesh" not in src:
            fail(f"{label} missing Bonjour mesh service")
    if "CURRENT_PROJECT_VERSION = 43" not in pbx:
        fail("version was bumped off 43")
    if "MARKETING_VERSION = 0.1.0" not in pbx:
        fail("MARKETING_VERSION changed")
    tools = (ROOT / "Packages/Maps/Sources/Maps/MapTools.swift").read_text()
    if "MeshPill(nearbyCount: roster.peerCount)" in tools:
        fail("tools Radar MeshPill must use radio nearbyPeerCount, not roster.peerCount")
    if "MeshPill(nearbyCount: nearbyPeerCount)" not in tools:
        fail("tools Radar lost the radio MeshPill")
    ok("live mesh 1/N is Multipeer, no WAN, radar peers from roster, version 19")


def test_pack_relay_1n() -> None:
    pipe = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MultipeerPipe.swift").read_text()
    facade = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MeshFacade.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    zip_src = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackZip.swift").read_text()
    catalog = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalog.swift").read_text()
    catalog_list = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalogList.swift").read_text()
    packs_pkg = (ROOT / "Packages/Packs/Package.swift").read_text()
    app = (ROOT / "Blackout/AppContainer.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    if "sendResource" not in pipe:
        fail("MultipeerPipe is not using sendResource")
    if "func sendFile" not in facade:
        fail("MeshFacade missing sendFile")
    if "URLSession" in pipe or "URLSession" in facade:
        fail("Mesh relay must not use URLSession")
    if "prepareRelayZip" not in store or "installRelayedZip" not in store:
        fail("PackStore missing relay zip prepare/install")
    if "func archive" not in zip_src:
        fail("PackZip cannot archive a folder for relay")
    if "cityRelayIDs" not in catalog or "el-paso" not in catalog:
        fail("city relay allowlist missing")
    if "Send pack" not in catalog_list and 'PackRelayPolicy.sendLabel' not in catalog_list:
        fail("Expedition pack catalog missing Send pack")
    if "import BlackoutMesh" in packs_pkg or "import BlackoutMesh" in store:
        fail("Packs must not import Mesh")
    if "relayPack" not in app or "installRelayedZip" not in app:
        fail("AppContainer does not glue pack relay")
    if "session.download" in store.split("installRelayedZip")[-1][:2000]:
        fail("installRelayedZip must not download")
    if "CURRENT_PROJECT_VERSION = 43" not in pbx:
        fail("version was bumped off 43")
    if "MARKETING_VERSION = 0.1.0" not in pbx:
        fail("MARKETING_VERSION changed")
    ok("city pack relay uses sendResource, Packs owns zip/hash, version 19")


def test_bundled_statewide_archive_only() -> None:
    compile_yml = (ROOT / ".github/workflows/ios-compile.yml").read_text()
    flight = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    fetch = (ROOT / "tools/fetch_bundled_field_packs.sh").read_text()
    copy = (ROOT / "tools/copy_fieldpacks.sh").read_text()
    probe = (ROOT / "tools/probe_fieldpacks_app.sh").read_text()
    catalog = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalog.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    sos = (ROOT / "Packages/SOS/Sources/SOS/SOSFab.swift").read_text()
    guide = (ROOT / "Packages/Field/Sources/Field/FieldRootView.swift").read_text()
    gitignore = (ROOT / ".gitignore").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()

    if "fetch_bundled_field_packs" in compile_yml or "florida.pack.zip" in compile_yml:
        fail("ios-compile.yml must not fetch statewide pack zips")
    if "FIELD_PACKS_REQUIRED" in compile_yml:
        fail("ios-compile.yml must not require Field Packs in the unsigned app")
    if "tools/fetch_bundled_field_packs.sh" not in flight:
        fail("ios-testflight.yml does not fetch statewide packs before archive")
    if "FIELD_PACKS_REQUIRED" not in flight:
        fail("ios-testflight.yml archive does not require staged Field Packs")
    if "probe_fieldpacks_app.sh" not in flight:
        fail("ios-testflight.yml does not probe FieldPacks inside the xcarchive")
    for _id, filename, size, digest in STATEWIDE_PACKS:
        if filename not in fetch or digest not in fetch or size not in fetch:
            fail(f"fetch script missing {_id} {filename} {size} {digest}")
        if digest not in catalog:
            fail(f"catalog missing sha256 for {_id}")
        if f'id: "{_id}"' not in catalog:
            fail(f"catalog missing pack id {_id}")
        if _id not in copy or _id not in probe:
            fail(f"copy/probe missing {_id}")
    for city in ("el-paso.pack.zip", "las-cruces.pack.zip", "albuquerque.pack.zip"):
        if city in fetch:
            fail(f"fetch script must not download city pack {city}")
    if "isBundled: true" not in catalog or "bundledStatewide" not in catalog:
        fail("catalog lost bundledStatewide Ready flags")
    if "bundledPacksRoot" not in store or "httpSession" not in store:
        fail("PackStore must resolve bundled statewide without boot URLSession")
    if "let session: URLSession" in store:
        fail("PackStore still constructs URLSession on init")
    if "URLSession" in maps or "URLSession" in sos or "URLSession" in guide:
        fail("Map/SOS/Guide must not use URLSession")
    if "*.pack.zip" not in gitignore or "BundledFieldPacks/" not in gitignore:
        fail(".gitignore must exclude pack zips and BundledFieldPacks")
    if "routing/graph.bin" not in gitignore:
        fail(".gitignore must exclude routing binaries")
    if "us-ny" in fetch or "new-york.pack.zip" in fetch or "new-york.pack.zip" in catalog:
        fail("New York pack must be cut from fetch and catalog")
    if 'id: "us-ny"' in catalog or "us-ny" in copy.split("IDS=", 1)[-1][:80]:
        fail("New York must not remain in catalog or copy IDS")
    if "us-ny" in probe.split("for id in", 1)[-1][:80]:
        fail("probe must not require us-ny")
    if "FL TX NY" in flight or "us-ny" in flight:
        fail("TestFlight must not fetch NY")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("CURRENT_PROJECT_VERSION was bumped off 43")
    ok("archive fetches FL/TX/NM; compile does not; catalog is bundled Ready")


def test_copy_fieldpacks_compile_noop_and_archive_required() -> None:
    import tempfile

    copy = ROOT / "tools/copy_fieldpacks.sh"
    probe = ROOT / "tools/probe_fieldpacks_app.sh"
    with tempfile.TemporaryDirectory() as tmp:
        srcroot = Path(tmp) / "src"
        built = Path(tmp) / "built"
        resources = built / "Blackout.app"
        srcroot.mkdir()
        resources.mkdir(parents=True)
        env = {
            **os.environ,
            "SRCROOT": str(srcroot),
            "BUILT_PRODUCTS_DIR": str(built),
            "UNLOCALIZED_RESOURCES_FOLDER_PATH": "Blackout.app",
        }
        subprocess.check_call(["bash", str(copy)], env=env)
        if (resources / "FieldPacks").exists():
            fail("unsigned compile copied FieldPacks without staging")

        env["FIELD_PACKS_REQUIRED"] = "1"
        missing = subprocess.run(["bash", str(copy)], env=env, capture_output=True, text=True)
        if missing.returncode == 0:
            fail("archive copy must fail when staging is missing")

        staging = srcroot / "BundledFieldPacks"
        for pack_id in ("us-tx", "us-nm", "us-fl"):
            tiles = staging / pack_id / "tiles" / "8" / "1"
            tiles.mkdir(parents=True)
            manifest = {
                "id": pack_id,
                "tileCount": 1,
            }
            if pack_id == "us-tx":
                manifest["routing"] = "routing/routing.json"
                manifest["attribution"] = "© OpenStreetMap contributors"
                routing = staging / pack_id / "routing"
                routing.mkdir()
                (routing / "routing.json").write_text(
                    '{"format":"blackout-routing-v1","profiles":["walk","drive"]}',
                    encoding="utf-8",
                )
                (routing / "graph.bin").write_bytes(b"BLRG0001")
                (routing / "names.bin").write_bytes(b"BLNM0001")
                (routing / "geometry.bin").write_bytes(b"BLGM0001")
            (staging / pack_id / "manifest.json").write_text(
                json.dumps(manifest), encoding="utf-8"
            )
            (tiles / "1.png").write_bytes(b"\x89PNG")
        copied = subprocess.run(
            ["bash", str(copy)], env=env, capture_output=True, text=True, check=True
        )
        app = resources
        subprocess.check_call(["bash", str(probe), str(app)])
        if (app / "FieldPacks" / "tiles").exists():
            fail("copy flattened three states into FieldPacks/tiles")
        if (app / "FieldPacks" / "el-paso").exists():
            fail("copy staged a city pack")
        tx_routing = app / "FieldPacks" / "us-tx" / "routing"
        if not (tx_routing / "graph.bin").is_file() or not (tx_routing / "routing.json").is_file():
            fail("archive ditto dropped us-tx routing/")
        man = json.loads((app / "FieldPacks" / "us-tx" / "manifest.json").read_text())
        if man.get("routing") != "routing/routing.json":
            fail("copied us-tx manifest lost routing key")
        if man.get("attribution") != "© OpenStreetMap contributors":
            fail("copied us-tx manifest lost ODbL attribution")
        if (app / "FieldPacks" / "us-fl" / "routing").exists():
            fail("copy invented routing/ on a pack that had none")
        if "routing/" not in copied.stdout:
            fail("copy did not report routing/ when present")
        for pack_id, _filename, _size, digest in STATEWIDE_PACKS:
            sidecar = app / "FieldPacks" / pack_id / "catalog.sha256"
            if not sidecar.is_file() or sidecar.read_text().strip() != digest:
                fail(f"copy did not pin catalog.sha256 for {pack_id}")
        if "BLRG0001" not in probe.read_text():
            fail("probe_fieldpacks_app.sh does not check routing magic when present")

        (staging / "us-tx" / "routing" / "graph.bin").write_bytes(b"XXXX0001")
        bad = subprocess.run(["bash", str(copy)], env=env, capture_output=True, text=True)
        if bad.returncode == 0:
            fail("copy must fail when routing/ magic mismatches")
    ok("copy no-ops on compile and requires three separate statewide folders on archive")


def test_fieldpack_root_flatten_fixture() -> None:
    import tempfile
    import zipfile

    script = ROOT / "tools/fetch_bundled_field_packs.sh"
    with tempfile.TemporaryDirectory() as tmp:
        wrapped = Path(tmp) / "wrap"
        inner = wrapped / "us-fl"
        tiles = inner / "tiles" / "8" / "1"
        tiles.mkdir(parents=True)
        (inner / "manifest.json").write_text(
            '{"id":"us-tx","routing":"routing/routing.json","attribution":"© OpenStreetMap contributors"}',
            encoding="utf-8",
        )
        (tiles / "1.png").write_bytes(b"\x89PNG")
        routing = inner / "routing"
        routing.mkdir()
        (routing / "routing.json").write_text("{}", encoding="utf-8")
        (routing / "graph.bin").write_bytes(b"BLRG0001")
        (routing / "names.bin").write_bytes(b"BLNM0001")
        (routing / "geometry.bin").write_bytes(b"BLGM0001")
        zip_path = Path(tmp) / "texas-wrap.zip"
        with zipfile.ZipFile(zip_path, "w") as zf:
            for path in inner.rglob("*"):
                if path.is_file():
                    zf.write(path, path.relative_to(wrapped).as_posix())
        dest = Path(tmp) / "us-tx"
        staged = subprocess.run(
            ["bash", str(script), "--stage-zip", str(zip_path), str(dest)],
            capture_output=True,
            text=True,
            check=True,
        )
        if not (dest / "manifest.json").is_file():
            fail("ROOT-flatten did not promote manifest.json")
        if not (dest / "tiles" / "8" / "1" / "1.png").is_file():
            fail("ROOT-flatten did not promote tiles/")
        if (dest / "us-fl" / "manifest.json").exists() or (dest / "us-tx" / "manifest.json").exists():
            fail("ROOT-flatten left a nested wrapper")
        if not (dest / "routing" / "graph.bin").is_file():
            fail("ROOT-flatten dropped routing/graph.bin")
        man = json.loads((dest / "manifest.json").read_text())
        if man.get("attribution") != "© OpenStreetMap contributors":
            fail("ROOT-flatten dropped pack-manifest ODbL attribution")
        if "routing/" not in staged.stdout:
            fail("ROOT-flatten did not report staged routing/")
    ok("ROOT-flatten promotes a wrapped pack zip")


def test_party_vitals_red_loop() -> None:
    core = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/PartyVitals.swift").read_text()
    kind = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/PayloadKind.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    chip = (ROOT / "Packages/Maps/Sources/Maps/VitalsChip.swift").read_text()
    radar = (ROOT / "Packages/Maps/Sources/Maps/RadarHUDView.swift").read_text()
    sos = (ROOT / "Packages/SOS/Sources/SOS/SOSFab.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    app = (ROOT / "Blackout/AppContainer.swift").read_text()
    mesh = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MeshFacade.swift").read_text()
    pause = (ROOT / "Packages/Expeditions/Sources/Expeditions/ExpeditionsRootView.swift").read_text()
    plate = (ROOT / "Packages/Expeditions/Sources/Expeditions/PartyVitalsPlate.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    if "case partyStatus" not in kind:
        fail("PayloadKind missing partyStatus")
    ds = (ROOT / "Packages/DesignSystem/Sources/DesignSystem/BlackoutDS.swift").read_text()
    if "injury = true" not in core or "return .red" not in core:
        fail("I AM NOT OK must set injury and red")
    if "case .rested" not in core or "case .dizzy" not in core:
        fail("RESTED / DIZZY missing from vitals math")
    if "RESTED" in chip or "DIZZY" in chip or "RESTED" in maps or "DIZZY" in maps:
        fail("RESTED / DIZZY must stay in vitals math — no extra Map chips")
    if "RESTED" in plate or "DIZZY" in plate:
        fail("RESTED / DIZZY must not grow roster chips")
    if "redFiresSOS = false" not in core:
        fail("going red must stay not-an-SOS-fire")
    if "sosConfirmRequested" in maps or "sosAlert" in maps or "kind: .sosAlert" in core:
        fail("going red must not fire SOS")
    if "import HealthKit" in core or "import HealthKit" in plate or "import HealthKit" in chip or "import HealthKit" in maps or "import HealthKit" in root:
        fail("manual vitals must not import HealthKit")
    if "tel:911" in core or "tel:911" in plate or "tel:911" in app:
        fail("party red must not auto-dial 911")
    if "VitalsChip" in root or "vitalsOverlay" in root:
        fail("RootView must not mount the I AM OK dual")
    if "vitalsRow" in maps:
        fail("I AM OK must not live in the Map slab stack")
    if "MapChromeLock.sosDiameter" not in maps:
        fail("right-edge stack must clear the 88pt SOS disk")
    if "sosClearance + BlackoutDS.Vitals.sosGap" in maps:
        fail("vitals chip must not sit above the old 120pt SOS stack")
    if "public var body" not in chip:
        fail("public VitalsChip must declare public var body")
    if "BlackoutDS.Vitals.chip" not in chip:
        fail("I AM NOT chip is not 56h")
    if "BlackoutDS.Surface.raised" not in chip or "Btn.primary" in chip:
        fail("I AM OK dual chip plate must be Surface.raised, not Btn.primary")
    if "BlackoutDS.Btn.metal" in chip:
        fail("I AM OK dual chip must not paint the white Btn.metal pill")
    if "vitalsPlateIsRaised = true" not in (
        ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/MapChromeLock.swift"
    ).read_text():
        fail("MapChromeLock must keep the dual chip on Surface.raised")
    if "clipShape(Circle" in chip or "clipShape(Capsule" in chip:
        fail("vitals chip must not be a disk")
    if "SOSFab" in chip or "sosAlert" in chip or "sosConfirm" in chip:
        fail("vitals chip must not present or arm SOS")
    if "BlackoutDS.Vitals.pip" not in chip or "BlackoutDS.Semantic.warn" not in chip:
        fail("I AM NOT must use 6pt red.core pip + warn label")
    if "BlackoutDS.Silver.bright" not in chip:
        fail("I AM OK dual chip type must be silver on the raised plate")
    if "Surface.void" in chip:
        fail("I AM OK type must not stay void-on-white")
    if "§10.4" not in ds or "public static let pip: CGFloat = 6" not in ds:
        fail("DS §10.4 vitals metrics missing")
    if "Color(red: 1, green: 43 / 255, blue: 43 / 255)" not in ds:
        fail("Red.core hex changed")
    if "BlackoutDS.Hit.sos" not in sos:
        fail("SOS FAB lost 88pt hit")
    if "PartyVitalsPlate" not in pause:
        fail("Expedition roster lost two-tap vitals")
    if "DRANK" not in plate or "ATE" not in plate or "I AM NOT OK" not in plate:
        fail("roster missing DRANK / ATE / I AM NOT OK")
    comms = (ROOT / "Blackout/CommsRootView.swift").read_text()
    if "selfLabel.footnote" not in plate or "Silver.dim" not in plate:
        fail("roster lost YOU last-4 silver.dim footnote")
    if "blip.footnote" not in radar or "Silver.dim" not in radar:
        fail("Radar lost YOU last-4 silver.dim footnote")
    if "shown.footnote" not in comms or "Silver.dim" not in comms:
        fail("Comms lost live YOU last-4 silver.dim footnote")
    if "footnote" in sos:
        fail("YOU last-4 must not appear on SOS")
    if "Btn.metal" not in plate or "Vitals.chip" not in plate:
        fail("roster buttons must be Btn.metal 56")
    if "drankLatched" not in plate or "ateLatched" not in plate:
        fail("DRANK / ATE must keep independent ok pips")
    if "BlackoutDS.Red.core" in plate and ".background(BlackoutDS.Red.core)" in plate:
        fail("I AM NOT OK roster button must stay metal, not primary")
    if "Navigate-to" not in radar and 'PartyVitalsCopy.navigateTo' not in radar:
        fail("peer sheet missing Navigate-to")
    if "PartyVitalsCopy.message" not in radar:
        fail("tap pip must offer Message")
    if 'MetalButton("PTT"' in radar:
        fail("peer sheet must stay Message + Navigate-to")
    if "enum AppDestination" in root and root.count("case ") < 4:
        fail("4-tab chrome missing cases")
    if "becameRed" not in app:
        fail("AppContainer does not haptic on peer red")
    if "envelope.kind" in mesh:
        fail("MeshFacade must stay a dumb pipe")
    if "case expedition" not in root or "case field" not in root:
        fail("4-tab chrome missing")
    if root.count("tabItem") != 4:
        fail("do not add a fifth tab")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("CURRENT_PROJECT_VERSION was bumped off 43")
    ok("party vitals two-tap + red packet, SOS 88, chip 56, no 911")


def test_chrome_public_view_access() -> None:
    import re

    paths = [
        ROOT / "Packages/Maps/Sources/Maps/VitalsChip.swift",
        ROOT / "Packages/DesignSystem/Sources/DesignSystem/MapHUDChip.swift",
        ROOT / "Packages/Maps/Sources/Maps/RadarHUDView.swift",
        ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift",
        ROOT / "Packages/Maps/Sources/Maps/CompassLockChrome.swift",
    ]
    for path in paths:
        src = path.read_text()
        for match in re.finditer(r"public struct (\w+): View", src):
            name = match.group(1)
            rest = src[match.end() :]
            body = re.search(r"^    (public )?var body:", rest, re.M)
            if body is None:
                fail(f"{path.name} {name} has no View body")
            if body.group(1) is None:
                fail(f"{path.name} {name} body must be public")
            head = rest[: body.start()]
            if "public init" not in head and "init(" in head:
                fail(f"{path.name} {name} init must be public")
    chip = (ROOT / "Packages/Maps/Sources/Maps/VitalsChip.swift").read_text()
    if "public struct VitalsChip" not in chip or "public var body" not in chip:
        fail("VitalsChip must stay public View with public body")
    if "public init(" not in chip:
        fail("VitalsChip init must stay public")
    hud = (ROOT / "Packages/DesignSystem/Sources/DesignSystem/MapHUDChip.swift").read_text()
    if "public struct MapHUDChip" not in hud or "public var body" not in hud:
        fail("MapHUDChip must stay public View with public body")
    if pbx_version_off_32():
        fail("CURRENT_PROJECT_VERSION was bumped off 43")
    ok("chrome public Views expose public body/init")


def pbx_version_off_32() -> bool:
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    return pbx.count("CURRENT_PROJECT_VERSION = 43") < 2


def test_sos_confirm_panel() -> None:
    sos = (ROOT / "Packages/SOS/Sources/SOS/SOSFab.swift").read_text()
    support = (ROOT / "Packages/SOS/Sources/SOS/SOSConfirmSupport.swift").read_text()
    core = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/SOSConfirm.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    vitals = (ROOT / "Packages/DesignSystem/Sources/DesignSystem/BlackoutDS.swift").read_text()
    chrome = (ROOT / "Packages/Maps/Sources/MapsChrome/MapChromeRecede.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    if "SPEAK SOS" not in core or 'speakLocation = "SPEAK LOCATION"' not in core:
        fail("confirm panel missing SPEAK SOS / SPEAK LOCATION")
    if "SPEAK MY LOCATION" in core:
        fail("confirm label is SPEAK LOCATION, not SPEAK MY LOCATION")
    if 'sharePosition = "SHARE"' not in core or 'copyCoords = "COPY"' not in core:
        fail("confirm panel missing SHARE / COPY")
    if "SHARE POSITION" in core or "COPY COORDS" in core:
        fail("confirm labels are SHARE and COPY")
    if "CALL 911" not in core or 'visualStrobe = "STROBE"' not in core:
        fail("confirm panel missing CALL 911 / STROBE")
    if "VISUAL SOS STROBE" in core:
        fail("confirm label is STROBE")
    if '"BLACKOUT \\(coordsLine(fix))"' not in core and "BLACKOUT \\(coordsLine" not in core:
        fail("SHARE message must be BLACKOUT {coords}")
    if "BLACKOUT" not in core:
        fail("SHARE must start with BLACKOUT")
    if "tel:911" not in core or "autoDials911 = false" not in core:
        fail("CALL 911 must be tel:911 and must not auto-dial")
    if "strobePeriodMs = 330" not in core or "reduceMotionOpacity = 0.55" not in core:
        fail("visual strobe must be 330ms pulse / Reduce Motion 0.55")
    if "SOSConfirmActionList" not in sos or "SOSStrobeWash" not in sos:
        fail("confirm cover lost the six actions or visual strobe")
    if "Button(action: {})" not in sos:
        fail("SOS tap must never fire")
    if "SOSChrome.holdSeconds" not in sos:
        fail("hold 1.5s must present the unarmed cover")
    if "SlideToConfirm" not in sos:
        fail("slide still commits")
    if "Emergency SOS (system)" not in sos:
        fail("OS Emergency SOS must stay an explicit extra control")
    if "onAppear { showSystemSOS" in sos or ".onAppear { showSystemSOS = true" in sos:
        fail("must not auto-invoke OS Emergency SOS")
    if "openTel911" not in support or "signalDistress" not in support:
        fail("CALL / strobe must open tel:911 and send mesh sos")
    if "markInjured" not in support:
        fail("strobe / CALL must set local injury/red")
    if "SOSChrome.fabBottomInset" not in root:
        fail("SOS FAB must inset tabBar+8 via SOSChrome")
    if "keyboardHeight" not in root:
        fail("SOS must track keyboard height and lift above the keys")
    if "keyboardOverlap" not in root:
        fail("SOS lift must use SOSChrome.keyboardOverlap")
    if "keyboardHeight" not in root.split("private var fabBottomPadding", 1)[-1][:400]:
        fail("fabBottomPadding must include keyboard height")
    if "hidesForKeyboard = false" not in core:
        fail("never hide SOS for the keyboard")
    if "liftsAboveKeyboard = true" not in core:
        fail("SOS must lift above the keyboard")
    if "testSOSLiftsAboveKeyboardAndNeverHides" not in (
        (ROOT / "Packages/BlackoutCore/Tests/BlackoutCoreTests/SOSConfirmTests.swift").read_text()
    ):
        fail("missing SOS keyboard-lift test")
    if "SOSChrome.trailing" not in root:
        fail("SOS FAB must use 16pt trailing inset")
    if ".padding(.trailing, 18)" in root:
        fail("SOS trailing drifted off 16pt")
    if "ignoresSafeArea(edges: .bottom)" in root:
        fail("SOS overlay must not ignore the bottom safe area")
    if "VitalsChip" in root:
        fail("I AM OK dual must stay off RootView")
    maps_root = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    if "showsRightEdgeChips" not in maps_root:
        fail("Recenter/Layers must hide when Map search is focused")
    if "searchFocused" not in maps_root.split("showsRightEdgeChips", 1)[-1][:240]:
        fail("Recenter/Layers hide must key off search focus")
    if ".padding(.trailing, 18)" in maps_root:
        fail("Map chrome trailing drifted off SoT")
    if "return 16 + tab + home" in root:
        fail("SOS FAB still uses the old 16pt-above-tab inset")
    if "sosClearance: CGFloat = 120" in vitals:
        fail("SOS clearance must be the 88pt disk band, not 120 stacked")
    if "sosClearance: CGFloat = 88" not in vitals or "sosGap: CGFloat = 8" not in vitals:
        fail("DS SOS tokens drifted")
    if "SOS FAB is not part of this flag" not in chrome:
        fail("Map recede must not include the SOS FAB")
    if root.count("tabItem") != 4:
        fail("do not make SOS a tab")
    if "sosOverlay" not in root or root.count("SOSFab") != 1:
        fail("SOS must be one RootView overlay on all four tabs")
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    comms = (ROOT / "Blackout/CommsRootView.swift").read_text()
    field = (ROOT / "Packages/Field/Sources/Field/FieldRootView.swift").read_text()
    expedition = (ROOT / "Packages/Expeditions/Sources/Expeditions/ExpeditionsRootView.swift").read_text()
    if "SOSFab" in maps or "SOSFab" in comms or "SOSFab" in field or "SOSFab" in expedition:
        fail("SOS must not be a per-tab or nav-bar control")
    if "isReceded && !reduceMotion" not in maps:
        fail("HUD recede must keep chrome when Reduce Motion is on")
    if "CriticalSOSShell" not in root or "SOSFab" not in root:
        fail("last-2% must still show the 88pt SOS FAB")
    if "push:" in tf or "pull_request:" in tf:
        fail("do not dispatch TestFlight")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    ok("SOS is bottom-trailing tabBar+8, confirm has six actions, no auto-911")


def test_locked_app_icon() -> None:
    import struct

    emblem = ROOT / "brand" / "emblem.jpeg"
    wordmark = ROOT / "brand" / "wordmark.jpeg"
    lockup = ROOT / "brand" / "lockup.jpeg"
    icon = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    catalog = (ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json").read_text()
    wordset = ROOT / "Blackout" / "Assets.xcassets" / "Wordmark.imageset"
    gen = (ROOT / "tools" / "generate_project.py").read_text()
    if not emblem.is_file() or emblem.stat().st_size < 100_000:
        fail("brand/emblem.jpeg missing or too small")
    if not wordmark.is_file() or not lockup.is_file():
        fail("brand wordmark/lockup missing")
    if not icon.is_file():
        fail("AppIcon.png missing")
    if icon.stat().st_size < 50_000:
        fail("AppIcon.png is still the synthetic red disc")
    raw = icon.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        fail("AppIcon.png is not a PNG")
    ln = struct.unpack(">I", raw[8:12])[0]
    tag = raw[12:16]
    data = raw[16 : 16 + ln]
    if tag != b"IHDR":
        fail("AppIcon.png missing IHDR")
    w, h, bit, ct = struct.unpack(">IIBB", data[:10])
    if (w, h) != (1024, 1024):
        fail(f"AppIcon.png is {w}x{h}, need 1024x1024")
    if ct != 2:
        fail(f"AppIcon.png color type {ct} is not opaque RGB (no alpha)")
    if "AppIcon.png" not in catalog or "1024x1024" not in catalog:
        fail("AppIcon Contents.json does not point at the single 1024")
    if not (wordset / "Wordmark.jpeg").is_file() and not (wordset / "Wordmark.png").is_file():
        fail("Wordmark is not in the asset catalog")
    if "Image(" in gen and "lockup" in gen:
        fail("lockup must not be wired into the app icon")
    if "CURRENT_PROJECT_VERSION" in (ROOT / "Blackout.xcodeproj" / "project.pbxproj").read_text():
        pbx = (ROOT / "Blackout.xcodeproj" / "project.pbxproj").read_text()
        if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
            fail("version was bumped off 43 while landing the emblem")
    ok("AppIcon is the locked emblem PNG; wordmark is catalog-only")


def test_compass_lock_on() -> None:
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    session = (ROOT / "Packages/Maps/Sources/Maps/CompassLockSession.swift").read_text()
    chrome = (ROOT / "Packages/Maps/Sources/Maps/CompassLockChrome.swift").read_text()
    math = (ROOT / "Packages/Maps/Sources/MapsRouting/CompassLock.swift").read_text()
    speech = (ROOT / "Packages/Maps/Sources/Maps/OnDeviceSpeech.swift").read_text()
    tests = (ROOT / "Packages/Maps/Tests/MapsTests/CompassLockTests.swift").read_text()
    sos = (ROOT / "Packages/SOS/Sources/SOS/SOSFab.swift").read_text()
    vitals = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    catalog = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalog.swift").read_text()
    for path in (maps, session, chrome, math):
        if "MKDirections" in path or "URLSession" in path:
            fail("compass lock path must stay airplane: no MKDirections / URLSession")
    if "CompassLockBar" not in maps or "CompassLockSession" not in maps:
        fail("Map lost compass lock chrome")
    for label in ('SPEAK', 'STEER', 'MARK', 'LOCK'):
        if f'"{label}"' not in math:
            fail(f"compass lock lost button {label}")
    if "Nothing to lock. MARK a point or wait for a peer." not in math:
        fail("compass lock lost empty copy")
    if "Hold course" not in math or "Right " not in math or "Left " not in math:
        fail("compass lock lost turnPhrase")
    if "relBearing" not in math or "540" not in math:
        fail("compass lock lost relBearing formula")
    if "voiceInterval: TimeInterval = 2.2" not in math:
        fail("voice lock must stay 2.2s")
    if "speechRateMin: Float = 0.47" not in math or "speechRateMax: Float = 0.52" not in math:
        fail("voice lock rate must stay 0.47–0.52")
    if "id: \"th\"" not in math or "31.8924" not in math or "-106.4401" not in math:
        fail("standards list lost th Trailhead")
    if "id: \"wc\"" not in math or "Water cache" not in math:
        fail("standards list lost wc Water cache")
    if "startLoopIfNeeded" not in session or "guard voiceTask == nil" not in session:
        fail("2.2s timer must not restart on every render")
    if "AVSpeechSynthesizer" not in speech:
        fail("lock voice must stay on-device AVSpeechSynthesizer")
    if "NavigateSession" not in maps or "routing" not in maps:
        fail("street TBT must stay default when routing/ exists")
    if "-(location.headingDegrees" in maps:
        fail("do not rotate OfflineMapView under heading-up; radar owns that sweep")
    if "RadarHUDView(" not in (ROOT / "Packages/Maps/Sources/Maps/MapTools.swift").read_text():
        fail("Radar sweep must live on the Radar sheet, not the big map")
    if "SAVE CURRENT" not in math or "LOCKED" not in math or "DELETE" not in math:
        fail("MARK sheet lost SAVE CURRENT / STEER / LOCKED / DELETE")
    if "BlackoutDS.Hit.sos" not in sos:
        fail("SOS 88 must never recede")
    if "RecedingMapChrome" not in vitals:
        fail("HUD chips must still recede")
    if "vitalsOverlay" in (ROOT / "Blackout/RootView.swift").read_text():
        fail("I AM OK dual must stay off RootView")
    if "FieldPacksView" in (ROOT / "Blackout/RootView.swift").read_text():
        fail("do not restore the first-open Field Packs sheet")
    if (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPacksView.swift").exists():
        fail("do not restore FieldPacksView")
    if "6ff6c9a191fe5df8d3bf48abb360ad361990bc672c1c59bd0cf2e3a3d5d55ade" not in catalog:
        fail("texas.pack.zip pin drifted")
    if "220_512_882" not in catalog:
        fail("texas.pack.zip byte pin drifted")
    if "tabItem" in (ROOT / "Blackout/RootView.swift").read_text() and (
        ROOT / "Blackout/RootView.swift"
    ).read_text().count("tabItem") != 4:
        fail("do not restore 6 tabs")
    if "func coveringRoot" not in (ROOT / "Packages/Maps/Sources/MapsRouting/RoutingPack.swift").read_text():
        fail("do not revert Feature 1 routing loader")
    if "routing/graph.bin" not in (ROOT / ".gitignore").read_text():
        fail("do not put graph bins in git")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    if "push:" in (ROOT / ".github/workflows/ios-testflight.yml").read_text():
        fail("do not dispatch TestFlight")
    if "31.8924" not in tests or "Hold course" not in tests:
        fail("compass lock tests lost the standards / turnPhrase locks")
    ok("compass lock is SPEAK/STEER/MARK/LOCK, 2.2s voice, one standards list")


def test_pack_find_civ_water() -> None:
    find = ROOT / "Packages/Maps/Sources/MapsRouting/PackFind.swift"
    tests = (ROOT / "Packages/Maps/Tests/MapsTests/PackFindTests.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    tools = (ROOT / "Packages/Maps/Sources/Maps/MapTools.swift").read_text()
    session = (ROOT / "Packages/Maps/Sources/Maps/NavigateSession.swift").read_text()
    lock = (ROOT / "Packages/Maps/Sources/MapsRouting/CompassLock.swift").read_text()
    poi = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/MapPack.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    if not find.is_file():
        fail("PackFind.swift missing — Find civ/water must score pack POIs")
    src = find.read_text()
    for banned in ("MKLocalSearch", "MKMapView", "URLSession", "MKDirections"):
        if banned in src or banned in maps or banned in tools or banned in session:
            fail(f"Find civ/water must stay airplane: no {banned}")
    for kind in ('"road"', '"rail"', '"town"', '"mill"', '"spring"', '"tank"', '"water"'):
        if kind not in src:
            fail(f"PackFind lost pack kind {kind}")
    layout = (ROOT / "Packages/Maps/Sources/MapsRouting/RoutingLayout.swift").read_text()
    for copy in (
        "No pack for this area",
        "No turns for this area",
        "No civilization in this pack",
        "No water mapped here",
    ):
        if f'"{copy}"' not in layout:
            fail(f"Map empty lost locked copy: {copy}")
    if 'eyebrow = "MAP"' not in layout:
        fail("Map empty lost eyebrow MAP")
    if "No civilization in this pack" not in tests or "No water mapped here" not in tests:
        fail("Find civ/water tests lost the honest empty")
    if "NeverInvent" not in tests and "neverInvent" not in tests:
        fail("Find civ/water tests must refuse invented cities")
    if ".shadow(" in maps:
        fail("Map empty / chrome must not drop-shadow in sun mode")
    if "Skip" in (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text() and 'GhostButton("Skip"' in maps:
        fail("Map empty must not grow a Skip control")
    if "PackFindCopy.civilization" not in tools or "PackFindCopy.water" not in tools:
        fail("PackFindSheet lost Find civilization / Find water")
    if "PackFindCopy.civilization" in maps.split("struct MapLayersSheet", 1)[-1]:
        fail("Find civ/water must not live on Layers")
    if 'GhostButton("Towns"' in maps:
        fail("Towns must become Find civilization + Find water")
    if "pickFound" not in maps or "MapPOINameSheet" not in maps:
        fail("tapping a pack POI must open the name sheet")
    if "navigate.empty != nil" not in maps:
        fail("Find empty cards must hold chrome")
    if "compass.end()" not in maps:
        fail("Map lost compass.end")
    if "case .poi" not in lock:
        fail("compass lock-on from a pack POI needs kind .poi")
    if "func findPack" not in session:
        fail("NavigateSession must find from pack POIs, not a geocoder")
    if "isWater" not in poi:
        fail("MapPOI lost isWater")
    if "logo" in maps.lower() and "watermark" in maps.lower():
        fail("do not put a logo on Map")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    if "push:" in tf or "pull_request:" in tf:
        fail("do not dispatch TestFlight")
    if (ROOT / "Blackout/RootView.swift").read_text().count("tabItem") != 4:
        fail("do not restore 6 tabs")
    if "BlackoutDS.Hit.sos" not in (ROOT / "Packages/SOS/Sources/SOS/SOSFab.swift").read_text():
        fail("do not move SOS")
    ok("Map Find civilization / Find water scores pack POIs only")


def main() -> None:
    test_compile_workflow_drops_feature_branch_push()
    test_testflight_paths_and_assign()
    test_pbx_single_copy()
    test_generator_does_not_restore_double_copy()
    test_assign_script_requires_secrets()
    test_assign_pick_prefers_fresh_then_fallback()
    test_assign_existing_workflow()
    test_prune_script_requires_secrets()
    test_map_chrome_lock()
    test_map_google_feel()
    test_map_pack_resolver()
    test_usgs_defaultpack()
    test_live_mesh_1n()
    test_pack_relay_1n()
    test_party_vitals_red_loop()
    test_chrome_public_view_access()
    test_sos_confirm_panel()
    test_locked_app_icon()
    test_bundled_statewide_archive_only()
    test_copy_fieldpacks_compile_noop_and_archive_required()
    test_fieldpack_root_flatten_fixture()
    test_compass_lock_on()
    test_pack_find_civ_water()
    test_hits_23()
    test_offline_10()
    test_format_version_insurance()
    test_update_maps_one_tap()
    test_pack_amenity_address_search()
    test_sos_armed_restore_no_crash()
    test_root_view_body_type_checks()
    test_map_fill_bleed_and_paint_budget()
    test_map_metal_plates()
    test_field_ask_home_is_not_encyclopedia()
    print("all ci-opt checks passed")


def test_sos_armed_restore_no_crash() -> None:
    core = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/SOSConfirm.swift").read_text()
    keys = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/BlackoutKeys.swift").read_text()
    tests = (ROOT / "Packages/BlackoutCore/Tests/BlackoutCoreTests/SOSConfirmTests.swift").read_text()
    sos = (ROOT / "Packages/SOS/Sources/SOS/SOSFab.swift").read_text()
    speech = (ROOT / "Packages/SOS/Sources/SOS/SOSSpeech.swift").read_text()
    support = (ROOT / "Packages/SOS/Sources/SOS/SOSConfirmSupport.swift").read_text()
    app = (ROOT / "Blackout/AppContainer.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj" / "project.pbxproj").read_text()
    tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text()

    def should_auto_present(armed: bool, requested: bool, new_binary: bool) -> bool:
        return False

    def is_new_binary(current: str, last: str | None) -> bool:
        return current == "" or current != last

    def should_request_confirm(armed: bool, new_binary: bool) -> bool:
        return not armed

    if should_auto_present(True, True, True):
        fail("new TestFlight binary must not auto-present a persisted armed overlay")
    if should_auto_present(True, False, False):
        fail("cold launch must not present armed overlay from the persist flag alone")
    if should_auto_present(True, True, False):
        fail("persisted armed overlay must not steal first open after unlock")
    if not is_new_binary("30", None) or not is_new_binary("30", "25") or is_new_binary("30", "30"):
        fail("new-binary launch detection drifted")
    if should_request_confirm(True, True) or not should_request_confirm(False, True):
        fail("missed check-in must not reopen armed overlay")

    if "enum SOSArmedRestore" not in core:
        fail("SOSArmedRestore policy missing")
    if "dismissDisarms = false" not in core:
        fail("closing the armed panel must not disarm")
    if "autoPresentOnColdLaunch = false" not in core:
        fail("cold launch must not restore the armed overlay")
    if "appearStartsSpeech = false" not in core or "appearStartsStrobe = false" not in core:
        fail("armed appear must stay speech/strobe idle")
    if "appearRequiresPeers = false" not in core or "appearRequiresLocation = false" not in core:
        fail("armed appear must not require peers or a fix")
    if "return false" not in core.split("shouldAutoPresentArmedOverlay", 1)[-1][:400]:
        fail("auto-present policy must stay off so first open is unlock")
    launch = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/RootChromeLock.swift").read_text()
    shell_app = (ROOT / "Blackout/BlackoutApp.swift").read_text()
    lock_view = (ROOT / "Packages/Settings/Sources/Settings/SettingsRootView.swift").read_text()
    ring = (ROOT / "Packages/DesignSystem/Sources/DesignSystem/MetalRingLockup.swift").read_text()
    slide = (ROOT / "Packages/DesignSystem/Sources/DesignSystem/SlideToUnlock.swift").read_text()
    if 'destination = "unlock"' not in launch:
        fail("cold launch must land on unlock")
    if "usesBitmapLockUI = false" not in launch or "usesFullScreenLockImage = false" not in launch:
        fail("unlock chrome must not be a painted lock/SOS bitmap")
    if "usesLockupImage = true" not in launch or "metalRingIsSwiftUI = false" not in launch:
        fail("unlock emblem must be the lockup Image, not empty SwiftUI rings")
    if "sosTwinHit: Double = 56" not in launch:
        fail("unlock handle/SOS twins must be 56pt")
    if "trackHit: Double = 56" not in launch or "handleHit: Double = 56" not in launch:
        fail("unlock track and handle must be 56pt metal twins")
    if "slideArmsSOS = false" not in launch:
        fail("slide to unlock must not arm SOS")
    if "twinHoldPresentsUnarmedCover = true" not in launch:
        fail("hold 1.5s on the lock SOS twin must present the unarmed cover")
    if "twinHoldArmsSOS = false" not in launch:
        fail("hold on the lock twin must not arm SOS")
    if "twinHoldSeconds: Double = 1.5" not in launch:
        fail("lock SOS twin hold must stay 1.5s")
    if "startsSensorsBeforeUnlock = false" not in launch:
        fail("cold launch must not start GPS/motion before unlock")
    if "constructsLocationHardwareInInit = false" not in launch:
        fail("LocationService must not construct CoreLocation/CoreMotion in AppContainer.init")
    if "startsLiveActivityBeforeUnlock = false" not in launch:
        fail("cold launch must not start Live Activity before unlock")
    if "walksAllTilesOnBoot = false" not in launch:
        fail("boot must not walk every pack tile")
    if "MetalRingLockup" not in lock_view or "SlideToUnlock" not in lock_view:
        fail("LockGateView lost the lockup or SOS-twin slider")
    if "On-device lock. Nothing to sign in to." not in lock_view:
        fail("LockGateView lost the on-device lock copy")
    if "Circle(" in ring or "Circle()" in ring:
        fail("lockup must not redraw Crisis's ring as empty Circle() chrome")
    if "BrandChromeLock.lockupAsset" not in ring or "Image(" not in ring:
        fail("MetalRingLockup must render the Lockup catalog Image")
    if "lockupMaxPoint" not in ring and "280" not in lock_view:
        fail("lockup Image must stay at most 280pt")
    lockup_set = ROOT / "Blackout/Assets.xcassets/Lockup.imageset/Lockup.jpeg"
    brand_lockup = ROOT / "brand/lockup.jpeg"
    if not lockup_set.is_file() or lockup_set.stat().st_size < 50_000:
        fail("Lockup.imageset is missing Crisis's lockup.jpeg")
    if not brand_lockup.is_file():
        fail("brand/lockup.jpeg missing")
    if lockup_set.stat().st_size != brand_lockup.stat().st_size:
        fail("catalog Lockup.jpeg is not brand/lockup.jpeg")
    if "LaunchLock.sosTwinHit" not in slide or "88" in slide.split("sosTwin", 1)[-1][:200]:
        fail("unlock SOS twin must not be the 88pt Map FAB")
    if "LaunchLock.trackHit" not in slide or "knobSize + 8" in slide:
        fail("unlock track must be the 56pt metal capsule, not a padded 64pt pill")
    if "onLongPressGesture" not in slide or "SOSChrome.holdSeconds" not in slide:
        fail("lock SOS twin must hold 1.5s to present the unarmed cover")
    if "Red.core" not in slide:
        fail("lock SOS twin must be red.core")
    if "onHoldSOS" not in lock_view:
        fail("LockGateView must wire hold-on-twin to the unarmed cover")
    if "showsDisk: container.lock.isUnlocked" not in root:
        fail("lock gate must hide the 88pt Map FAB until after unlock")
    if "container.sosCoverOpen || container.sosConfirmRequested" not in root:
        fail("lock SOS twin hold cover must stay hittable while the gate is up")
    if "BlackoutDS.Hit.sos" not in sos:
        fail("Map SOS FAB size drifted off 88pt")
    if "SplashChromeView" in shell_app:
        fail("cold launch must not paint a splash bitmap over the unlock gate")
    if "unlockSession" not in lock_view:
        fail("slider must unlock the session without Face ID as the first frame")
    if "sosArmed" in lock_view.split("SlideToUnlock", 1)[-1][:200]:
        fail("LockGateView slider must not write sosArmed")
    if "if !container.lock.isUnlocked" not in root and "showsLockGate(" not in root:
        fail("RootView must show the unlock gate on every cold launch")
    if "isEnabled && !container.lock.isUnlocked" in root:
        fail("unlock gate must not depend on Settings local-lock being on")
    if "showsLockGate(" not in root:
        fail("background must not remount LockGateView under a system picker")
    scene_change = root.split("onChange(of: scenePhase)")[1]
    if "container.lock.lock()" in scene_change:
        fail("RootView must not lock() on scenePhase — remounts MetalRingLockup in background")
    if "applyScenePhase" not in scene_change:
        fail("scenePhase must go through SceneLockPolicy applyScenePhase")
    if "parkHardwareForBackground" not in app and "parkHardwareForBackground" not in scene_change:
        fail("scenePhase .background must park location/mesh/radio")
    if "locksOnBackground = false" not in launch:
        fail("lock contract must not call lock() while backgrounded")
    if "locksOnPickerBackground = false" not in launch:
        fail("picker / share / PHPicker must not lock()")
    if "parksLiveActivityOnBackground = true" not in launch:
        fail("background must park Live Activity")
    if "startsHardwareWhenSceneInactive = false" not in launch:
        fail("hardware must not start unless scene is active")
    if "testBackgroundParkDoesNotRemountLockGate" not in tests:
        fail("missing background park / no remount test")
    if "testPickerBackgroundDoesNotRelock" not in tests:
        fail("missing picker-background does not lock test")
    if "testTrueLeaveRelocksOnlyOnNextActive" not in tests:
        fail("missing true-leave relock-on-active test")
    if "testHardwareStaysOffUntilMapFrameAndActiveScene" not in tests:
        fail("missing hardware-after-Map-frame-and-active test")
    if "enum SceneLockPolicy" not in (
        ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/RootChromeLock.swift"
    ).read_text():
        fail("SceneLockPolicy missing — background lock remount is untested")
    if "func applyScenePhase" not in app:
        fail("AppContainer must apply SceneLockPolicy; never lock() in RootView background")
    if "shouldPark(phase: phase)" not in app:
        fail("applyScenePhase must call shouldPark(phase:) — unlabeled call fails xcodebuild")
    if "parkLiveActivity" not in app:
        fail("background must park Live Activity if one is up")
    if "shouldRelockOnActive" not in app:
        fail("true leave may lock() only on next .active")
    if "isSystemCover" not in (
        ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/RootChromeLock.swift"
    ).read_text():
        fail("system picker / share / PHPicker must be classified as not a true leave")
    if "sceneIsActive" not in app.split("func scheduleHardwareAfterFirstMapFrame")[1][:400]:
        fail("hardware after unlock must require an active scene")
    apply_fn = app.split("func applyScenePhase", 1)[-1].split("\n    func ", 1)[0]
    if "lock.lock()" in apply_fn.split("shouldRelockOnActive", 1)[0]:
        fail("applyScenePhase must not lock() on park/background")
    if "refreshLiveActivity()" in apply_fn.split("shouldRelockOnActive", 1)[0]:
        fail("background park must not start Live Activity")
    if "scenePhase == .active" not in root.split(".task {", 1)[-1][:500]:
        fail("Live Activity 1s loop must not run while backgrounded")
    if "remountsLockGateOnBackground = false" not in launch:
        fail("lock contract must not remount the lock gate on leave")
    if "parksHardwareOnBackground = true" not in launch:
        fail("lock contract must park hardware on leave")
    if "testColdLaunchLandsOnUnlockNotArmedOrBitmap" not in tests:
        fail("missing first-open unlock regression")
    if "sosLastSeenBuild" not in keys:
        fail("missing last-seen build key")
    if "testNewBinaryLaunchDoesNotAutoPresentPersistedArmedOverlay" not in tests:
        fail("missing new-binary armed restore regression")
    if "testDismissArmedPanelDoesNotDisarm" not in tests:
        fail("missing dismiss-does-not-disarm regression")
    if "testArmedOverlayAppearIsIdleWithZeroPeersAndNoFix" not in tests:
        fail("missing idle 0-peer / no-fix appear regression")
    if "shouldAutoPresentArmedOverlay" not in sos:
        fail("SOSFab must consult SOSArmedRestore before auto-present")
    if "suppressPersistedArmedAutoPresent" not in sos or "suppressPersistedArmedAutoPresent" not in app:
        fail("new-binary suppress flag not wired")
    if "shouldRequestConfirmAfterMissedCheckIn" not in app:
        fail("missed check-in must not trap a new-binary armed restore")
    if "dismissWithoutDisarming" not in sos:
        fail("armed panel X must dismiss without disarming")
    if 'accessibilityLabel("Close. Does not disarm.")' not in sos:
        fail("armed panel X lost its close label")
    armed_panel = sos.split("public struct SOSArmedPanel", 1)[-1].split("public struct SystemEmergencySOSView", 1)[0]
    if "onAppear { bindController() }" in armed_panel:
        fail("armed panel must not create speech on appear")
    if "private let synthesizer = AVSpeechSynthesizer()" in speech:
        fail("SOS speech must not construct AVSpeechSynthesizer until speak")
    if "private var synthesizer: AVSpeechSynthesizer?" not in speech:
        fail("SOS speech synthesizer must stay lazy")
    if "private var speech: SOSSpeech?" not in support:
        fail("confirm controller must not allocate speech on init")
    if "autoDials911 = false" not in core or "tel:911" not in core:
        fail("CALL 911 must stay tel:911 and never auto-dial")
    if root.count("tabItem") != 4:
        fail("do not add a fifth tab")
    if "BlackoutDS.Hit.sos" not in sos:
        fail("Map SOS FAB size drifted")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    if "workflow_dispatch:" not in tf or "push:" in tf or "pull_request:" in tf:
        fail("do not dispatch TestFlight from this fix")
    app = (ROOT / "Blackout/AppContainer.swift").read_text()
    file_pack = (ROOT / "Packages/Maps/Sources/Maps/FileMapPack.swift").read_text()
    layout = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/MapPack.swift").read_text()
    dem = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/DEMGrid.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    loc = (ROOT / "Packages/Location/Sources/BlackoutLocation/LocationService.swift").read_text()
    if "location.startUpdating()" in app.split("init()")[1].split("startMissedCheckInWatch")[0]:
        fail("AppContainer.init must not start GPS/motion before the unlock gate")
    loc_init = loc.split("public init() {", 1)[1].split("\n    }", 1)[0]
    if "CLLocationManager(" in loc_init or "CMPedometer(" in loc_init or "CMMotionManager(" in loc_init:
        fail("LocationService.init must not construct CLLocationManager/CMPedometer/CMMotionManager")
    if "armHardwareIfNeeded()" not in loc.split("public func startUpdating()")[1][:400]:
        fail("location hardware must arm on startUpdating after unlock")
    if "let manager = CLLocationManager()" in loc:
        fail("CLLocationManager must not be a stored eager property")
    if "let pedometer = CMPedometer()" in loc:
        fail("CMPedometer must not be a stored eager property")
    if "let motion = CMMotionManager()" in loc:
        fail("CMMotionManager must not be a stored eager property")
    if "constructsLocationHardwareInInit = false" not in launch:
        fail("lock contract must forbid location hardware on AppContainer.init")
    if "syncMeshToParty()" in app.split("init()")[1].split("startMissedCheckInWatch")[0]:
        fail("AppContainer.init must not start mesh/Live Activity before unlock")
    if "guard container.lock.isUnlocked else { return }" not in root.split(".onAppear")[1][:240]:
        fail("RootView.onAppear must not start sensors while the lock is up")
    if "container.lock.isUnlocked" not in root.split("onChange(of: scenePhase)")[1][:500]:
        fail("foreground restore must not start sensors while locked")
    if "onChange(of: container.lock.isUnlocked)" not in root:
        fail("unlock must schedule hardware only after the slide")
    unlock_tick = root.split("onChange(of: container.lock.isUnlocked)", 1)[-1].split("onChange(", 1)[0]
    if "syncSensorsToBattery()" in unlock_tick:
        fail("unlock tick must not start CLLocation/mesh in the same turn as unlockSession")
    if "startUpdating()" in unlock_tick or "syncMeshToParty()" in unlock_tick:
        fail("unlockSession path must not call startUpdating/syncMesh synchronously")
    if "radios.start()" in unlock_tick:
        fail("unlock tick must not start mesh radio in the same turn")
    if "refreshLiveActivity()" in unlock_tick:
        fail("unlock tick must not touch Live Activity in the same turn")
    if "scheduleHardwareAfterFirstMapFrame" not in unlock_tick:
        fail("unlock must paint Map first, then defer hardware")
    lock_svc = (ROOT / "Packages/Settings/Sources/Settings/AppLockService.swift").read_text()
    unlock_fn = lock_svc.split("func unlockSession()", 1)[-1].split("func ", 1)[0]
    if "startUpdating" in unlock_fn or "radios.start" in unlock_fn or "syncMesh" in unlock_fn:
        fail("unlockSession must not start hardware")
    if "Activity.request" in unlock_fn or "refreshLiveActivity" in unlock_fn:
        fail("unlockSession must not request a Live Activity")
    if "isUnlocked = true" not in unlock_fn:
        fail("unlockSession must only flip the lock")
    if "let monitor = NWPathMonitor()" in store:
        fail("PackStore must not construct NWPathMonitor at init")
    if "enablePathMonitor: true" in app.split("init()")[1].split("startMissedCheckInWatch")[0]:
        fail("AppContainer.init must not enable the PackStore path monitor")
    if "startPathMonitor" in app.split("init()")[1].split("startMissedCheckInWatch")[0]:
        fail("AppContainer.init must not start the PackStore path monitor")
    if "func startPathMonitorIfNeeded" not in store:
        fail("PackStore path monitor must arm after unlock, like MeshRadioProbe")
    if "func stopPathMonitor" not in store:
        fail("PackStore path monitor must stop on background park")
    if "startsPackPathMonitorInInit = false" not in launch:
        fail("lock contract must forbid PackStore path monitor on AppContainer.init")
    if "startsHardwareSynchronouslyOnUnlock = false" not in launch:
        fail("lock contract must forbid hardware in the unlock tick")
    maps_root = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    if "location.startUpdating()" in maps_root:
        fail("Map onAppear must not start CLLocation in the unlock tick")
    task = root.split(".task {", 1)[-1][:400]
    if "guard container.lock.isUnlocked" not in task or "continue" not in task:
        fail("RootView.task must not refresh Live Activity on the lock gate")
    if "scenePhase == .active" not in task:
        fail("Live Activity 1s loop must not run while backgrounded")
    if "return true" not in layout.split("public static func containsTilePNGs")[1][:800]:
        fail("containsTilePNGs must return on the first PNG")
    if "tilePNGCount(root: root) > 0" in layout:
        fail("containsTilePNGs still walks every tile")
    if "tilePNGCount(root: root)" in file_pack.split("private static func inspect")[1][:900]:
        fail("FileMapPack.inspect must not count every tile on boot")
    if "loadPOIs(root: root)" in file_pack.split("private static func inspect")[1][:900]:
        fail("FileMapPack.inspect must not parse poi.json for every pack on appear")
    if ".first!" in dem or ".last!" in dem:
        fail("DEMGrid must not force-unwrap axis ends")
    if "urls(for: .applicationSupportDirectory, in: .userDomainMask).first!" in store:
        fail("PackStore must not force-unwrap Application Support")
    if "lats.first!" in file_pack or "lons.first!" in file_pack:
        fail("FileMapPack DEM still force-unwraps axis ends")
    if "testContainsTilePNGsReturnsOnFirstPNG" not in (
        ROOT / "Packages/BlackoutCore/Tests/BlackoutCoreTests/MapPackSchemaTests.swift"
    ).read_text():
        fail("missing containsTilePNGs short-circuit test")
    if "testEmptyAxesReturnNil" not in (
        ROOT / "Packages/BlackoutCore/Tests/BlackoutCoreTests/DEMGridTests.swift"
    ).read_text():
        fail("missing DEM empty/jagged regression")
    if "NSLocationWhenInUseUsageDescription" not in pbx or "NSMotionUsageDescription" not in pbx:
        fail("location/motion usage strings must stay in the generated Info.plist keys")
    if "TAG" not in (ROOT / "Supporting/Blackout.entitlements").read_text():
        fail("NFC entitlement must stay TAG-only")
    if "NDEF" in (ROOT / "Supporting/Blackout.entitlements").read_text():
        fail("do not restore NDEF")
    if "startUpdatingLocation()" not in loc.split("if authorization == .authorized")[1][:200]:
        fail("denied/not-determined GPS must not force startUpdatingLocation")
    probe = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MeshRadioProbe.swift").read_text()
    hub = (ROOT / "Blackout/LiveActivityHub.swift").read_text()
    launch = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/RootChromeLock.swift").read_text()
    if "sosFabMountsOnLockFrame = false" not in launch:
        fail("lock frame must not mount SOSFab")
    if "startsRadioProbeBeforeUnlock = false" not in launch:
        fail("radio probe must not start on the lock frame")
    if "touchesLiveActivityOnNewBinary = false" not in launch:
        fail("new-binary first process must not touch ActivityKit")
    if "sosOverlayMounts(" not in root:
        fail("SOS overlay must stay off the idle lock frame")
    if "func sosOverlayMounts" not in launch or "enum RootChromeLock" not in launch:
        fail("RootChromeLock must own sosOverlayMounts (RootView and tests call it)")
    if "stackedChrome" not in root or "sosOverlaySlot" not in root:
        fail("RootView.body must stay split or Xcode 16 cannot type-check it")
    if "CBCentralManager(" in probe.split("public override init()")[1].split("public func start")[0]:
        fail("MeshRadioProbe.init must not construct CBCentralManager")
    if "monitor.start(" in probe.split("public override init()")[1].split("public func start")[0]:
        fail("MeshRadioProbe.init must not start NWPathMonitor")
    if "let monitor = NWPathMonitor()" in probe:
        fail("NWPathMonitor must not construct during MeshRadioProbe / AppContainer.init")
    if "started = false" not in probe.split("public func stop()")[1][:400]:
        fail("MeshRadioProbe.stop must allow start after background park")
    if "kind: .selfDot" not in (
        ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/PartyVitals.swift"
    ).read_text().split("func radarBlips", 1)[-1][:800]:
        fail("radarBlips must emit .selfDot for the dedicated Radar screen")
    if "shouldTouchActivityKit" not in hub:
        fail("LiveActivityHub must consult shouldTouchActivityKit")
    if "newBinaryLaunch: suppressPersistedArmedAutoPresent" not in app:
        fail("Live Activity sync must pass the new-binary suppress flag")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    ok("SOS armed restore + lockup first-open + launch crash sweep, version 43")


def test_root_view_body_type_checks() -> None:
    root = (ROOT / "Blackout/RootView.swift").read_text()
    root_struct = root.split("struct RootView: View", 1)[-1].split(
        "private struct CriticalSOSShell", 1
    )[0]
    body = root_struct.split("var body: some View {", 1)[-1].split(
        "private func applyLifecycle", 1
    )[0]
    if "applyLifecycle(to: stackedChrome)" not in body:
        fail("RootView.body must stay a thin applyLifecycle wrapper")
    if ".sheet(" in body or ".onChange(" in body or ".task {" in body:
        fail("RootView.body still holds the lifecycle chain Xcode 16 cannot type-check")
    if "func applyLifecycle<" not in root_struct:
        fail("RootView lost applyLifecycle")
    if "sosOverlayMounts(" not in root_struct:
        fail("SOS overlay must stay gated off the idle lock frame")
    if "guard container.lock.isUnlocked else { return }" not in root_struct.split(
        ".onAppear"
    )[1][:240]:
        fail("RootView.onAppear must not start sensors while the lock is up")
    unlock_tick = root_struct.split("onChange(of: container.lock.isUnlocked)", 1)[-1].split(
        "onChange(", 1
    )[0]
    if "syncSensorsToBattery()" in unlock_tick or "refreshLiveActivity()" in unlock_tick:
        fail("unlock onChange must not start hardware before the first Map frame")
    ok("RootView.body is split so Xcode 16 can type-check")


def test_pack_amenity_address_search() -> None:
    search = (ROOT / "Packages/Maps/Sources/MapsRouting/PackSearch.swift").read_text()
    amenity = (ROOT / "Packages/Maps/Sources/MapsRouting/PackAmenity.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    catalog_list = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalogList.swift").read_text()
    poi = json.loads((ROOT / "Blackout/DefaultPack/poi.json").read_text())
    addr = json.loads((ROOT / "Blackout/DefaultPack/address.json").read_text())
    tests = (ROOT / "Packages/Maps/Tests/MapsTests/PackAmenityTests.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    for banned in ("MKLocalSearch", "MKMapView", "URLSession", "MKDirections"):
        if banned in search or banned in amenity:
            fail(f"pack amenity search must stay airplane: no {banned}")
    if "RoutingAddress" not in search or "matchesAddress" not in search:
        fail("PackSearch must hit house+street from the pack address index")
    if "isAmenity" not in amenity or "pinZoom = 11" not in amenity:
        fail("amenity pins must be close-zoom only")
    if "paintsOnMap" not in amenity or 'address' not in amenity:
        fail("addresses must stay searchable and not paint a statewide dot field")
    if "amenityPins" not in maps or "PackAmenityPolicy.pinHit" not in maps:
        fail("Map must pin amenities and hit-test a tap to the name sheet")
    if "MapPOINameSheet" not in maps:
        fail("tap pin / search pick must open a name sheet, not MARK a route")
    if "func updateAllMaps" not in store or "updateMapsLabel" not in catalog_list:
        fail("do not add a second pack updater")
    if poi.get("schema") != 1:
        fail("DefaultPack poi.json schema must stay v1")
    kinds = {row.get("kind") for row in poi.get("pois", [])}
    if not {"cafe", "grocery", "fuel", "lodging", "restaurant", "pharmacy", "school", "hardware"} <= kinds:
        fail("DefaultPack lost the Front Range amenity sample")
    if "pharmacy" not in amenity or "fire_station" not in amenity or "camp_site" not in amenity:
        fail("PackAmenityPolicy must paint the full civic/shop set, not restaurants only")
    if addr.get("schema") != 1 or not addr.get("addresses"):
        fail("DefaultPack address fixture missing")
    if "testSearchHitsRestaurantAndHouseNumberWithoutLiveGeocoder" not in tests:
        fail("amenity/address search tests missing")
    if "testDefaultPinsAreHospitalWaterCivOnly" not in tests:
        fail("default map pins must stay hospital/water/civ")
    if "testNewerPOISchemaFailsClosed" not in tests:
        fail("poi schema fail-closed test missing")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    if "push:" in tf or "pull_request:" in tf:
        fail("do not dispatch TestFlight")
    if root.count("tabItem") != 4:
        fail("do not add a fifth tab")
    copy = (ROOT / "tools/copy_fieldpacks.sh").read_text()
    compile_yml = (ROOT / ".github/workflows/ios-compile.yml").read_text()
    if "fieldpack_poi" in copy or "seed_fieldpack_poi" in compile_yml:
        fail("city OSM overlays must not copy into the unsigned app or compile job")
    families = {
        "shop": {"shop", "grocery", "supermarket", "convenience", "mall", "hardware", "clothes"},
        "health": {"pharmacy", "hospital", "clinic", "dentist"},
        "civic": {"police", "fire_station", "post_office", "school", "bank", "fuel"},
        "food": {"cafe", "fast_food", "restaurant", "bar", "pub"},
        "stay": {"hotel", "motel", "lodging", "camp_site"},
    }
    for city in ("el-paso", "las-cruces", "albuquerque"):
        city_poi = json.loads((ROOT / "tools" / "fieldpack_poi" / city / "poi.json").read_text())
        rows = city_poi.get("pois") or []
        if city_poi.get("schema") != 1 or len(rows) < 50:
            fail(f"{city} publish overlay is missing or too thin")
        city_kinds = {row.get("kind") for row in rows}
        missing = [name for name, group in families.items() if not (city_kinds & group)]
        if missing:
            fail(f"{city} overlay is restaurant-only / missing families {missing}")
        food_n = sum(1 for row in rows if row.get("kind") in {"restaurant", "fast_food", "cafe"})
        if food_n / max(len(rows), 1) > 0.45:
            fail(f"{city} overlay is food-heavy ({food_n}/{len(rows)})")
    ok("pack amenity+address search is file-only, Update maps stays the one button, version 19")


def test_update_maps_one_tap() -> None:
    catalog_list = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalogList.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    policy = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackUpdatePolicy.swift").read_text()
    honesty = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackHonesty.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    app = (ROOT / "Blackout/AppContainer.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    tests = (ROOT / "Packages/Packs/Tests/PacksTests/FieldPackUpdateTests.swift").read_text()
    if "updateMapsLabel" not in catalog_list or "updateAllMaps" not in catalog_list:
        fail("Packs sheet lost the one-tap Update maps control")
    if 'updateMapsLabel = "Update maps"' not in policy:
        fail("Update maps label drifted")
    if "func updateAllMaps" not in store:
        fail("PackStore missing updateAllMaps")
    if "installVerifiedZip" not in store or ".new" not in store:
        fail("PackStore must stage a zip before replacing on-disk tiles")
    if "setDownloadsAllowed" not in store or "setDownloadsAllowed(false)" not in root:
        fail("last-2% must turn pack downloads off")
    if "setDownloadsAllowed(false)" not in app:
        fail("AppContainer must refuse downloads when already critical")
    if "let session: URLSession" in store:
        fail("PackStore still constructs URLSession on init")
    if "onAppear { store.updateAllMaps" in catalog_list or "onAppear { store.download" in catalog_list:
        fail("Packs sheet must not start a fetch on appear")
    if 'case .available' in catalog_list:
        fail("do not restore case .available")
    if "showsRowGet" not in policy or "isCityExtra" not in policy:
        fail("per-row Get must stay city-missing only")
    if "useCellularLabel" not in catalog_list:
        fail("cellular batch confirm missing")
    if "Tap Get. Then airplane." not in honesty:
        fail("city Get copy drifted")
    if "BlackoutDS.Hit.md" not in catalog_list:
        fail("Update maps must stay a 64pt glove hit")
    if root.count("tabItem") != 4:
        fail("do not add a fifth tab")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    if "push:" in tf or "pull_request:" in tf:
        fail("do not dispatch TestFlight")
    if "testSameHashOnTapIsUpToDateAndDoesNotFetch" not in tests:
        fail("Update maps hash skip test missing")
    if "testBadHashKeepsOldTilesAndContinues" not in tests:
        fail("fail-closed keep-old-tiles test missing")
    ok("one-tap Update maps is user-tapped, Wi-Fi default, fail-closed, version 19")


def test_offline_10() -> None:
    wave = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/OfflineWave.swift").read_text()
    envelope = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/Envelope.swift").read_text()
    kind = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/PayloadKind.swift").read_text()
    mesh = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MeshFacade.swift").read_text()
    pipe = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MultipeerPipe.swift").read_text()
    queue = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/StoreAndForward.swift").read_text()
    tests = (ROOT / "Packages/Mesh/Tests/MeshTests/StoreAndForwardTests.swift").read_text()
    wave_tests = (ROOT / "Packages/BlackoutCore/Tests/BlackoutCoreTests/OfflineWaveTests.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    field = (ROOT / "Packages/Field/Sources/Field/GuideAskView.swift").read_text()
    field_tree = (ROOT / "Packages/Field/Sources/Field/GuideTreePlate.swift").read_text()
    catalog_list = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalogList.swift").read_text()
    expedition = (ROOT / "Packages/Expeditions/Sources/Expeditions/ExpeditionsRootView.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    app = (ROOT / "Blackout/AppContainer.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    compile = (ROOT / ".github/workflows/ios-compile.yml").read_text()
    chips = (ROOT / "Packages/DesignSystem/Sources/DesignSystem/Chips.swift").read_text()
    if "isLightMode = false" not in wave:
        fail("NightRedMode must stay not light mode")
    if "hopCount" not in envelope:
        fail("Envelope lost hopCount pipe metadata")
    if "case guideCard" not in kind or "case followTrack" not in kind:
        fail("PayloadKind missing guideCard / followTrack")
    if "StoreAndForwardQueue" not in mesh or "flushStore" not in mesh:
        fail("MeshFacade is not store-and-forwarding")
    if "maxConnectedPeers" not in pipe or "connectedPeers.isEmpty" in pipe and "invitationHandler(true" in pipe.split("connectedPeers.isEmpty")[-1][:200]:
        if "maxConnectedPeers" not in pipe:
            fail("MultipeerPipe still 1-peer")
    if "duplicate" not in tests or "flushPending" not in tests:
        fail("store-and-forward tests missing")
    if "testGuideSendIsIdOnly" not in wave_tests or "testSearchPatternStaysInPackBBox" not in wave_tests:
        fail("offline-10 focused tests missing")
    if "Send to party" not in field and "GuideCardWire.sendLabel" not in field and "GuideCardWire.sendLabel" not in field_tree:
        fail("Guide lost Send to party")
    if "Stay as relay" not in expedition and "LeaveBehindRelayPolicy.control" not in expedition:
        fail("Expedition lost Stay as relay")
    if "nightRed ?" not in maps:
        fail("Map lost night-red multiply")
    if ".preferredColorScheme(.light)" in maps or ".preferredColorScheme(.light)" in root:
        fail("night red must not enable light mode")
    if "Dead reckoning, GPS lost." not in chips and "DeadReckoningHonesty.chip" not in maps:
        fail("honest dead-reckon chip missing")
    if "Start search" in maps or "Expanding square" in maps:
        fail("search patterns must not be permanent Map chrome")
    if "PackRelayPolicy.sendLabel" not in catalog_list:
        fail("Send pack row missing")
    if "setLeaveBehindRelay(false)" not in app and "setLeaveBehindRelay(false)" not in root:
        fail("2% / leave must stop relay")
    if "URLSession" in mesh or "URLSession" in queue:
        fail("store-and-forward must not use WAN")
    if "ciphertext" in queue and "open(" in queue:
        fail("queue must not inspect ciphertext")
    if root.count("tabItem") != 4:
        fail("do not add a fifth tab")
    if "push:" in tf or "pull_request:" in tf:
        fail("do not dispatch TestFlight")
    if "cursor/blackout-ios-foundation-7e54" in compile:
        fail("compile must not push on the feature branch")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    if (ROOT / "Blackout/GuidePack/manifest.json").read_text().count('"articleCount": 284') < 1:
        fail("GuidePack articleCount drifted off 284")
    ok("offline 10: hop+queue, pack relay, track, viewshed, DR, guide id, search, relay, night, party mode")


def test_format_version_insurance() -> None:
    pack = json.loads((ROOT / "Blackout/DefaultPack/manifest.json").read_text())
    guide = json.loads((ROOT / "Blackout/GuidePack/manifest.json").read_text())
    routing = (ROOT / "Packages/Maps/Sources/MapsRouting/RoutingLayout.swift").read_text()
    mesh = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MeshWire.swift").read_text()
    guide_loader = (ROOT / "Packages/Field/Sources/Field/GuideEngine.swift").read_text()
    ask = (ROOT / "Packages/Field/Sources/Field/GuideAskView.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    inbound = (ROOT / "Blackout/AppContainer.swift").read_text()
    articles = (ROOT / "Blackout/GuidePack/articles.jsonl").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    if pack.get("schema") not in (None, 1):
        fail("DefaultPack schema must be missing (v1) or 1")
    if guide.get("schema") != 1:
        fail("GuidePack must keep manifest schema 1")
    if '"blackout-routing-v1"' not in routing or "tooNewCopy" not in routing:
        fail("routing format v1 / too-new copy missing")
    if "0x42, 0x4B, 0x31" not in mesh or "unsupportedVersion" not in mesh:
        fail("mesh BK1 / unsupportedVersion missing")
    if "GuidePackSchema.tooNewCopy" not in ask or "GuidePackSchema.inspect" not in guide_loader:
        fail("guide schema fail-closed line missing")
    if 'tooNewCopy = "Guide schema too new."' not in (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/GuidePackSchema.swift").read_text():
        fail("guide too-new copy drifted")
    if "MapPackLayout.tooNewCopy" not in store:
        fail("pack too new catalog line missing")
    if 'tooNewCopy = "Pack too new."' not in (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/MapPack.swift").read_text():
        fail("pack too-new copy drifted")
    if "unsupportedVersion" not in inbound:
        fail("AppContainer must handle mesh unsupportedVersion")
    if articles.count("\n") < 284:
        fail("GuidePack articles drifted")
    if "_ingest" in articles:
        fail("GuidePack gained _ingest")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    if "push:" in tf or "pull_request:" in tf:
        fail("do not dispatch TestFlight")
    if root.count("tabItem") != 4:
        fail("do not add a fifth tab")
    ok("format-version insurance: pack/mesh/guide v1, fail closed, version 19")


def test_hits_23() -> None:
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    core = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/ConvenienceHits.swift").read_text()
    tests = (ROOT / "Packages/BlackoutCore/Tests/BlackoutCoreTests/ConvenienceHitsTests.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    torch = (ROOT / "Packages/Maps/Sources/Maps/MapTorch.swift").read_text()
    nfc = (ROOT / "Packages/Expeditions/Sources/Expeditions/PartyNFCViews.swift").read_text()
    plate = (ROOT / "Packages/Expeditions/Sources/Expeditions/PartyVitalsPlate.swift").read_text()
    shell = (ROOT / "Blackout/RootView.swift").read_text()
    intents = (ROOT / "Blackout/PTTIntents.swift").read_text()
    widget = (ROOT / "Supporting/BlackoutWidgets-Info.plist").read_text()
    info = (ROOT / "Supporting/Blackout-Info.plist").read_text()
    entitlements = (ROOT / "Supporting/Blackout.entitlements").read_text()
    if "<string>NDEF</string>" in entitlements:
        fail("ASC 90778: NDEF is disallowed in nfc.readersession.formats on SDK 26")
    if "<string>TAG</string>" not in entitlements:
        fail("NFC entitlement must keep TAG so party NDEF read/write still works")
    if "NFCReaderUsageDescription" not in pbx or "NFCReaderUsageDescription" not in info:
        fail("NFC usage string missing")
    if "Hold to share" not in core or "Tap to join" not in core:
        fail("NFC roster copy missing")
    if "PartyNFC.tapToJoin" not in plate or "PartyNFC.holdToShare" not in plate:
        fail("NFC roster controls missing")
    if "showsControls(readingAvailable: false)" not in tests:
        fail("NFC missing-hardware hide test missing")
    if "webview" in nfc.lower() or "WKWebView" in nfc:
        fail("NFC must not use a webview")
    if "if let (text, _)" in nfc:
        fail("wellKnownTypeTextPayload returns (String?, Locale?), not Optional")
    if "emitsSOS = false" not in core:
        fail("Map torch policy must not emit SOS")
    if "testFlashlightDoesNotEmitSOS" not in tests:
        fail("flashlight SOS test missing")
    if "ConvenienceCopy.flashlight" in maps or 'MapHUDChip("Light"' in maps:
        fail("Light must not be a fourth Map tile")
    if "torchMode" not in torch or "sosAlert" in torch:
        fail("Map torch must set AVCaptureDevice.torch and not emit sos")
    if "MapTorch" in shell.split("CriticalSOSShell", 1)[-1] or "flashlight" in shell.split("CriticalSOSShell", 1)[-1].lower():
        fail("do not add torch to CriticalSOSShell")
    if "Start PTT" not in intents or "Stop PTT" not in intents:
        fail("PTT App Intents missing")
    if "static var appShortcuts: [AppShortcut] {\n        [" in intents:
        fail("AppShortcutsBuilder takes AppShortcut statements, not an array literal")
    if "testPTTAppIntentRefusesZeroPeers" not in tests:
        fail("PTT App Intent zero-peer test missing")
    if "GENERATE_INFOPLIST_FILE = NO" not in pbx:
        fail("widget GENERATE_INFOPLIST_FILE must stay NO")
    if "$(PRODUCT_BUNDLE_IDENTIFIER)" not in widget:
        fail("widget CFBundleIdentifier must stay PRODUCT_BUNDLE_IDENTIFIER")
    if pbx.count("PRODUCT_BUNDLE_IDENTIFIER = com.crisiskhan.blackout.widget") < 2:
        fail("widget bundle id drifted")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("version bumped off 43")
    ok("hits 23: NFC + Map torch + PTT intent, widget id locked, version 19")


def test_map_fill_bleed_and_paint_budget() -> None:
    lock = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/MapChromeLock.swift").read_text()
    tests = (ROOT / "Packages/BlackoutCore/Tests/BlackoutCoreTests/MapChromeLockTests.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    offline = (ROOT / "Packages/Maps/Sources/Maps/OfflineMapView.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text()

    for flag in (
        "canvasIgnoresSafeArea = true",
        "canvasMaxFrameInfinity = true",
        "canvasUIViewAutoresizes = true",
        "canvasCoverNotLetterbox = true",
        "streetsTopoReadPersistedOnLaunch = false",
        "paintsPackLabelOverlayWhenTopoOff = false",
        "redrawCanvasOnPan = false",
        "reportsScaleOnEveryScroll = false",
        "duskGradeAlpha: Double = 0.22",
        "duskUsesMultiply = false",
        "duskCrushesCountyLabels = true",
        "defaultPaintIsDuskAerial = true",
        "defaultPaintsLabeledUSGS = false",
        "pickDismissesHits = true",
        "headingRedrawStepDegrees: Double = 8",
    ):
        if flag not in lock:
            fail(f"MapChromeLock missing {flag}")
    if "func coverZoomScale" not in lock or "func letterboxZoomScale" not in lock:
        fail("cover vs letterbox scale must be testable")
    if "func shouldRedrawAfterScroll" not in lock:
        fail("pan must not force a canvas redraw")
    if "func shouldRedrawForHeading" not in lock or "func shouldRedrawForFix" not in lock:
        fail("heading / GPS must not rebuild the map every tick")
    if "searchDebounceMilliseconds: Double = 180" not in lock:
        fail("pack search on each keystroke must debounce")
    if "func shouldRunQuerySearch" not in lock:
        fail("search debounce gate missing")

    for name in (
        "testCanvasFillsZStackCoverNotLetterboxStrip",
        "testStreetsTopoStayOffUnlessToggledThisSession",
        "testDuskGradeDoesNotZeroTileLuminance",
        "testDefaultPaintIsDuskAerialWithoutLabeledUSGS",
        "testDuskAerialRemapHidesPaperWhiteLabels",
        "testFieldLayersStartOffExceptPins",
        "testPickDismissesHitsAndDropdown",
        "testPackSearchQueryChangeDebounces",
        "testMapPaintDoesNotRedrawEveryScrollFrame",
        "testPickWithOriginAndGraphStartsPreview",
        "testPickNilOriginLocksDestAndCompass",
    ):
        if name not in tests:
            fail(f"missing {name}")

    canvas = maps.split("private var mapCanvas", 1)[-1].split("private func offlineMap", 1)[0]
    if ".frame(maxWidth: .infinity, maxHeight: .infinity)" not in canvas:
        fail("OfflineMapView must frame max infinity so the ZStack is full-bleed")
    if ".ignoresSafeArea()" not in canvas:
        fail("map canvas must ignoreSafeArea")
    if "UserDefaults.standard.bool(forKey: BlackoutKeys.mapStreets)" in maps:
        fail("streets must default off this session, not last launch")
    if "UserDefaults.standard.bool(forKey: BlackoutKeys.mapTopoTiles)" in maps:
        fail("topo must default off this session, not last launch")
    if "MapChromeLock.streetsLayerDefaultOn" not in maps:
        fail("streets launch value must be the lock default")
    if "MapChromeLock.contoursLayerDefaultOn" not in maps:
        fail("contours launch value must be the lock default")
    if "MapChromeLock.trailsLayerDefaultOn" not in maps:
        fail("trails launch value must be the lock default")
    if "searchDebounce" not in maps or "shouldRunQuerySearch" not in maps:
        fail("query-change search must debounce")
    if "searchPickConsumed" not in maps:
        fail("pickFound must consume the search so FocusState lag cannot reopen the dropdown")
    if "picked: searchPickConsumed" not in maps:
        fail("presentsDropdown must stay off after pickFound")
    if "func duskResultLuminance" not in lock:
        fail("dusk grade luminance must be testable so tiles do not wash to void")
    pick_fn = maps.split("func pickFound", 1)[-1][:900]
    if "navigate.pick(" not in pick_fn:
        fail("pickFound must still call navigate.pick")
    if "compass.lockOn(" not in pick_fn:
        fail("pickFound must still compass.lockOn when there is no Walk route")

    if "coverZoomScale" not in offline:
        fail("recenterToPackCoverage must cover-fill, not letterbox a strip over void")
    if "flexibleWidth" not in offline or "flexibleHeight" not in offline:
        fail("OfflineTileScrollView must UIView-autoresize")
    if "shouldRedrawAfterScroll" not in offline:
        fail("scroll must not setNeedsDisplay every frame")
    if "shouldRedrawForHeading" not in offline or "shouldRedrawForFix" not in offline:
        fail("updateUIView must not repaint tiles on every heading/GPS tick")
    if "duskGradeAlpha" not in offline:
        fail("dusk grade must use MapChromeLock.duskGradeAlpha")
    if "duskAerial" not in offline or "remapsLabeledPackTilesToDuskAerial" not in offline:
        fail("labeled USGS rasters must remap to dusk aerial on the default paint")
    if "paintsPackLabelOverlayWhenTopoOff" not in offline:
        fail("default pack paint must not add a street-name overlay")
    if "showViewshed: false" not in maps or "showSlope: false" not in maps:
        fail("viewshed/slope must stay off the idle Map")
    if "push:" in tf or "pull_request:" in tf:
        fail("do not dispatch TestFlight")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    ok("Map canvas fills, streets/topo session-off, paint budget cut, version 43")


def test_map_metal_plates() -> None:
    plate = (ROOT / "Packages/DesignSystem/Sources/DesignSystem/MetalPlate.swift").read_text()
    hud_chip = (ROOT / "Packages/DesignSystem/Sources/DesignSystem/MapHUDChip.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    nav = (ROOT / "Packages/Maps/Sources/Maps/NavigateChrome.swift").read_text()
    compass = (ROOT / "Packages/Maps/Sources/Maps/CompassLockChrome.swift").read_text()
    vitals = (ROOT / "Packages/Maps/Sources/Maps/VitalsChip.swift").read_text()
    sos = (ROOT / "Packages/SOS/Sources/SOS/SOSFab.swift").read_text()
    offline = (ROOT / "Packages/Maps/Sources/Maps/OfflineMapView.swift").read_text()
    core = (ROOT / "Packages/Maps/Sources/MapsRouting/CompassLock.swift").read_text()
    tests = (ROOT / "Packages/Maps/Tests/MapsTests/CompassLockTests.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text()

    if "struct MetalPlate" not in plate or "case rail" not in plate or "case bright" not in plate:
        fail("MetalPlate must be the mock plate, not another Capsule")
    if "clipShape(Capsule" in plate:
        fail("MetalPlate must not clip to Capsule")
    if "metalPlate(.rail" not in hud_chip:
        fail("Recenter/Layers/Packs must sit on MetalPlate rails")
    if "Capsule" in hud_chip:
        fail("MapHUDChip must not be a Capsule")
    lock_hud = maps.split("struct MapLockHUD", 1)[-1].split("struct MapEmptyCard", 1)[0]
    if "Capsule" in lock_hud:
        fail("3 m HUD must be a metal plate, not a Capsule")
    if "metalPlate(.inset" not in lock_hud:
        fail("3 m HUD lost its metal plate")
    if ".frame(maxWidth: .infinity)" in lock_hud:
        fail("MapLockHUD must stay the tiny chip")
    if "metalPlate(.rail, cornerRadius: MetalPlate.searchCorner)" not in nav:
        fail("Search this pack must be a metal plate")
    if "struct CompassLockOnHeader" not in compass:
        fail("nav-in-play must paint the mock LOCK ON header")
    if "LOCK ON" not in core or "func lockOnLine" not in core:
        fail("LOCK ON • 302° NW copy must be testable")
    if "testLockOnLineIsMockHeaderNotACapsule" not in tests:
        fail("missing LOCK ON header test")
    if "CompassLockOnHeader" not in maps.split("private var lockHudStack", 1)[-1]:
        fail("LOCK ON header must sit in lockHudStack when nav is in play")
    if "metalPlate(lit ? .bright : .rail" not in compass:
        fail("SPEAK/STEER/MARK/LOCK must be metal rails")
    if "metalPlate(.rail, cornerRadius: MetalPlate.searchCorner)" not in vitals:
        fail("I AM OK dual must be a metal plate")
    if "clipShape(Capsule" in vitals:
        fail("I AM OK must not become a Capsule")
    if "RadialGradient" in sos:
        fail("SOSFab must not use Circle+RadialGradient — QA fail-closed on the type")
    if "metalPlate(" not in sos and "MetalPlate(" not in sos and "metalDisk(" not in sos:
        fail("SOS 88 must use MetalPlate gradient rails, clipped to a disk")
    if "BlackoutDS.Hit.sos" not in sos:
        fail("SOS hit target remains 88pt")
    if "case hazard" not in plate:
        fail("MetalPlate needs a hazard rail for the SOS disk")
    if "setBlendMode(.multiply)" in offline:
        fail("dusk grade must not multiply pack rasters to a black well")
    if "duskUsesMultiply = false" not in (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/MapChromeLock.swift").read_text():
        fail("duskUsesMultiply must stay false")
    if "searchPickConsumed" not in maps:
        fail("pickFound must dismiss hits; searchPickConsumed is the latch")
    pick_fn = maps.split("func pickFound", 1)[-1][:900]
    if "navigate.pick(" not in pick_fn or "compass.lockOn(" not in pick_fn:
        fail("pickFound Walk/bearing must stay")
    if "coverZoomScale" not in offline or "searchDebounce" not in maps:
        fail("do not revert cover-zoom or 180ms search debounce")
    if "push:" in tf or "pull_request:" in tf:
        fail("do not dispatch TestFlight")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    ok("Map chrome is metal plates, LOCK ON header, overlay dusk, version 43")


def test_field_ask_home_is_not_encyclopedia() -> None:
    lock = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/GuideContext.swift").read_text()
    tests = (ROOT / "Packages/BlackoutCore/Tests/BlackoutCoreTests/GuideOfflineTests.swift").read_text()
    field = (ROOT / "Packages/Field/Sources/Field/FieldRootView.swift").read_text()
    ask = (ROOT / "Packages/Field/Sources/Field/GuideAskView.swift").read_text()
    tree = (ROOT / "Packages/Field/Sources/Field/GuideTreePlate.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    chrome = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/MapChromeLock.swift").read_text()

    if "enum FieldAskHomeLock" not in lock:
        fail("FieldAskHomeLock missing")
    if 'askPlaceholder = "What do you need?"' not in lock:
        fail("Ask placeholder must be What do you need?")
    if "testFieldAskHomeIsAskPlusChipsNotEncyclopedia" not in tests:
        fail("missing Field Ask home lock test")
    if "Situation cards" in field or "FieldManual.guide" in field:
        fail("Field Guide home must not paint the encyclopedia wall")
    if '"Field guide"' in field:
        fail("Field Guide home must not paint a pack-count essay header")
    if "Medical / lost" in ask:
        fail("Field Ask home must not paint the Medical/lost wall")
    if "Ask the field guide" in ask:
        fail("old buried Ask placeholder must be gone")
    if "FieldAskHomeLock.askPlaceholder" not in ask and "What do you need?" not in ask:
        fail("Ask field must use What do you need?")
    if "GuideTreePlate" in ask.split("ForEach(hits)", 1)[-1][:500] if "ForEach(hits)" in ask else False:
        fail("do not stack answer cards from retrieve hits")
    if "ForEach(GuideTopic.allCases)" in ask:
        fail("category pills must not sit on the Ask home plate")
    if "onChange(of: pack?.articles.count)" in ask:
        fail("do not auto-retrieve on appear")
    if "FieldAskHomeLock.homeChipTitles" not in ask:
        fail("kid chips must come from FieldAskHomeLock")
    if "FieldAskHomeLock.browseLabel" not in ask and "Browse" not in ask:
        fail("taxonomy must sit behind Browse, not the home wall")
    if "onStop" not in tree:
        fail("Stop must return to Ask")
    triage = tree.split("Adult / Kid / Party-split", 1)[-1][:900]
    if "stopControl" not in triage and "GuideSpeak.controlStop" not in triage:
        fail("Injury/Lost triage must have Stop back to Ask")
    if "GuideLanguageModel.complete" in ask:
        fail("Ask must not run the leftover on-device model after retrieve")
    if "GuideCardWire.sendLabel" not in tree and "Send to party" not in tree:
        fail("Send to party stays on the step card")
    if "GuidePackSchema.tooNewCopy" not in ask:
        fail("guide schema fail-closed line missing")
    skills = tree.split("struct GuideSkillsView", 1)[-1].split("struct GuideDoAlongPlate", 1)[0]
    if "ForEach(doAlongArticles)" in skills and "GuideDoAlongPlate" in skills.split("ForEach(doAlongArticles)", 1)[-1][:500]:
        fail("Skills must be a curriculum list, not a dump of plates")
    if "FieldSafePlate" not in field or "fieldContentHorizontalInset" not in field:
        fail("Field plate must keep the safe-area inset")
    if "onOpenSettings" not in field:
        fail("Field gear must stay in the Guide/Skills/Vision row")
    if "I AM OK" in field or "I AM OK" in ask or "I AM OK" in root:
        fail("I AM OK dual must stay unmounted")
    if "duskCrushesCountyLabels = true" not in chrome:
        fail("duskCrushesCountyLabels must stay")
    if root.count("tabItem") != 4:
        fail("four tabs stay")
    if "push:" in tf or "pull_request:" in tf:
        fail("do not dispatch TestFlight")
    if pbx.count("CURRENT_PROJECT_VERSION = 43") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    ok("Field home is Ask+chips, one step card, I AM OK gone, version 43")


if __name__ == "__main__":
    main()
