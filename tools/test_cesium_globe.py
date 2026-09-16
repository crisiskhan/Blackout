#!/usr/bin/env python3
"""Cesium is the only map. UPDATE is the only socket. Airplane otherwise."""
from __future__ import annotations

import json
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text(errors="ignore")


def _desk3d_covers(feat: dict, lon: float, lat: float) -> bool:
    geom = feat.get("geometry") or {}
    coords = geom.get("coordinates")
    pad = 0.02
    if geom.get("type") == "Polygon" and coords and coords[0]:
        xs = [p[0] for p in coords[0]]
        ys = [p[1] for p in coords[0]]
        return min(xs) - pad <= lon <= max(xs) + pad and min(ys) - pad <= lat <= max(ys) + pad
    if geom.get("type") == "Point" and coords:
        return abs(coords[0] - lon) < pad and abs(coords[1] - lat) < pad
    return False


class CesiumGlobeTests(unittest.TestCase):
    def test_globe_files_are_local_cesium(self):
        page = read("Resources", "Globe", "index.html")
        desk = read("Resources", "Globe", "desk.js")
        cesium = ROOT / "Resources" / "Globe" / "Cesium" / "Cesium.js"
        self.assertTrue(cesium.is_file(), "vendored Cesium.js")
        self.assertGreater(cesium.stat().st_size, 100_000)
        self.assertIn('window.CESIUM_BASE_URL = "./Cesium/"', page)
        self.assertIn("./Cesium/Cesium.js", page)
        self.assertIn("./pmtiles.js", page)
        self.assertIn("./desk.js", page)
        self.assertIn('Cesium.Ion.defaultAccessToken = ""', desk)
        self.assertIn("NO PIPE", desk)
        self.assertIn("CustomHeightmapTerrainProvider", desk)
        self.assertIn("PMTiles", desk)
        self.assertIn("USGS NAIP, build-time only", desk)
        self.assertNotIn("ion.cesium.com", desk)
        self.assertNotIn('chrome = "LIVE"', desk)
        self.assertNotIn("best in class", desk.lower())
        self.assertNotIn("Waze", desk)
        blob = page.lower() + desk.lower()
        self.assertNotIn("googleapis", blob)
        self.assertNotIn("opensky", blob)
        self.assertNotIn("mapkit", blob)

    def test_globe_view_is_file_webview_with_no_network(self):
        globe = read("Blackout", "GlobeView.swift")
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("WKWebView", globe)
        self.assertIn("loadFileURL", globe)
        self.assertIn("allowingReadAccessTo", globe)
        self.assertIn("decidePolicyFor", globe)
        self.assertIn("decisionHandler(.cancel)", globe)
        self.assertIn("isUserInteractionEnabled = interactive", globe)
        self.assertIn("OfflineMapView(", tab)
        self.assertNotIn("GlobeView(", tab)
        self.assertIn("bootStyleURL", tab)
        self.assertNotIn("URLSession", globe)
        self.assertNotIn("ion.cesium", globe.lower())
        self.assertNotIn('chrome = "LIVE"', globe)
        self.assertIn("OSMCredit.line", globe)
        self.assertNotIn("OSMCredit.line", tab)
        self.assertIn("BlackoutTokens.MapOverlay.updateTitle", tab)
        self.assertIn("BlackoutTokens.MapOverlay.godsEyeTitle", tab)
        lamp = tab.split("private var lampRail")[1].split("private var hitList")[0]
        self.assertIn("NIGHT", lamp)
        self.assertIn("SUN", lamp)
        self.assertIn("godsEyeTitle", lamp)
        overlay = tab.split("private var overlayRail")[1].split("private var lampRail")[0]
        self.assertIn("instrumentsTitle", overlay)
        self.assertIn("lockTitle", overlay)
        self.assertIn("updateTitle", overlay)
        self.assertNotIn("godsEyeTitle", overlay)

    def test_update_socket_is_the_only_pipe(self):
        sock = read("Blackout", "UpdateSocket.swift")
        app = read("Blackout", "AppRuntime.swift")
        desk = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "EyeDesk.swift")
        self.assertIn("URLSession", sock)
        self.assertIn("allowsExpensiveNetworkAccess", sock)
        self.assertIn("allowsConstrainedNetworkAccess", sock)
        self.assertNotIn("allowsExpensiveAccess =", sock)
        self.assertNotIn("allowsConstrainedAccess =", sock)
        self.assertIn("NWPathMonitor", sock)
        self.assertIn("EyeDesk.noPipe", sock)
        self.assertIn("SNAP", sock)
        self.assertIn("cameras.json", sock)
        self.assertIn("earthquake.usgs.gov", sock)
        self.assertIn("api.open-meteo.com", sock)
        self.assertNotIn('chrome = "LIVE"', sock)
        self.assertNotIn('stamp: "LIVE"', sock)
        self.assertNotIn("opensky", sock.lower())
        self.assertNotIn("ion.cesium", sock.lower())
        self.assertIn("func tapUpdate()", app)
        self.assertIn("updateSocket.tap(", app)
        self.assertIn('noPipe = "NO PIPE"', desk)
        self.assertIn('offTerrain = "OFF TERRAIN"', desk)
        self.assertIn("func terrainChrome", desk)
        self.assertIn("func updatedChrome", desk)
        self.assertIn('NET · NONE', desk)
        self.assertIn("case vectors", desk)
        self.assertIn("case snap", desk)

    def test_globe_shows_pack_ground_not_void(self):
        """Device stills: puck on black. Hillshade + OSM cover the pack; photo is extra."""
        desk = read("Resources", "Globe", "desk.js")
        globe = read("Blackout", "GlobeView.swift")
        tab = read("Blackout", "MapTab.swift")
        page = read("Resources", "Globe", "index.html")
        self.assertIn("XMLHttpRequest", desk)
        self.assertNotIn("return fetch(url)", desk)
        self.assertIn("hillshade.png", desk)
        self.assertIn("osm.pmtiles", desk)
        self.assertIn("khan.pmtiles", desk)
        self.assertIn("tileLoadProgressEvent", desk)
        self.assertNotIn("#141414", desk)
        self.assertIn("#4a463c", page)
        self.assertIn("backgroundColor = Cesium.Color.fromCssColorString(GROUND)", desk)
        self.assertIn("../Packs/", globe)
        self.assertIn("hillshade.png", globe)
        self.assertIn("osm.pmtiles", globe)
        self.assertIn("khan.pmtiles", globe)
        self.assertIn("OfflineMapView(", tab)
        self.assertIn("style.json", tab)
        self.assertIn("hillshade", read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"))

    def test_globe_paints_yards_houses_and_street_names(self):
        """Oleaster still: houses and yards, not gray lines on black."""
        desk = read("Resources", "Globe", "desk.js")
        globe = read("Blackout", "GlobeView.swift")
        tab = read("Blackout", "MapTab.swift")
        apply = desk.split("function apply(spec)")[1].split("function boot")[0]
        paint = desk.split("function paintMvt(")[1].split("function paintKhan")[0]
        puck = desk.split("function upsertPuck")[1].split("function drawCoins")[0]
        osm = desk.split("function loadOsm(")[1].split("function loadKhan(")[0]
        self.assertNotIn("function paintMvtInk", desk)
        self.assertNotIn("osmInkLayer", desk)
        self.assertEqual(osm.count("new PMTilesMVT"), 1)
        self.assertEqual(osm.count("addImageryProvider"), 1)
        self.assertIn("function paintKhan", desk)
        self.assertIn("layers.land", paint)
        self.assertIn("layers.water", paint)
        self.assertIn("layers.road", paint)
        self.assertIn("props.name", paint)
        self.assertIn("layers.building", desk)
        self.assertIn("layers.furniture", desk)
        self.assertIn("(level || 0) < 13", paint)
        self.assertIn("paint(canvas.getContext(\"2d\"), bytes, 256, level)", desk)
        self.assertIn("loadKhan", apply)
        self.assertLess(apply.find("loadKhan"), apply.find("loadAerial"))
        self.assertGreater(apply.find("raiseToTop(osmLayer)"), apply.find("loadAerial"))
        self.assertGreater(apply.find("raiseToTop(khanLayer)"), apply.find("loadAerial"))
        self.assertIn("lastKhan", desk)
        self.assertIn('text: "YOU"', puck)
        self.assertIn("khanUrl", globe)
        self.assertIn("TAP a street", tab)
        field = tab.split("fieldChrome")[1].split("if runtime.hudCrisis")[0]
        self.assertNotIn("allowsHitTesting(false)", field)
        self.assertNotIn("best in class", desk.lower())
        self.assertNotIn("Waze", desk)
        self.assertNotIn("Google", tab)

    def test_globe_reads_pack_bytes_by_offset(self):
        """134 brown void: whole osm+khan+aerial ArrayBuffers jetsam WebContent."""
        desk = read("Resources", "Globe", "desk.js")
        globe = read("Blackout", "GlobeView.swift")
        osm = desk.split("function loadOsm(")[1].split("function loadKhan(")[0]
        khan = desk.split("function loadKhan(")[1].split("function loadAerial(")[0]
        aerial = desk.split("function loadAerial(")[1].split("function loadGeo(")[0]
        apply = desk.split("function apply(spec)")[1].split("function boot")[0]
        self.assertIn("function PackSource", desk)
        self.assertIn("offset=", desk)
        self.assertIn("length=", desk)
        self.assertIn("new PackSource(url)", osm)
        self.assertIn("new PackSource(url)", khan)
        self.assertIn("new PackSource(url)", aerial)
        self.assertNotIn('xhr(url, "arraybuffer")', osm)
        self.assertNotIn('xhr(url, "arraybuffer")', khan)
        self.assertNotIn('xhr(url, "arraybuffer")', aerial)
        self.assertGreater(osm.find("lastOsm = url"), osm.find("addImageryProvider"))
        self.assertGreater(apply.find("lastGroundKey = groundKey"), apply.find("loadOsm"))
        self.assertIn("groundBusy", apply)
        self.assertIn("setURLSchemeHandler", globe)
        self.assertIn("packfile", globe)
        self.assertIn("archives", globe)
        self.assertIn("mappedIfSafe", globe)
        self.assertIn("subdata(in:", globe)
        self.assertIn("offset", globe)
        self.assertIn("length", globe)
        self.assertIn('scheme == "packfile"', globe)
        self.assertIn("packfile://blackout/", globe)

    def test_globe_paints_puck_before_pack_files(self):
        """128: black AND no puck. apply() waited on hillshade/OSM/NAIP first."""
        desk = read("Resources", "Globe", "desk.js")
        apply = desk.split("function apply(spec)")[1].split("function boot")[0]
        self.assertIn("upsertPuck(spec)", apply)
        self.assertIn("cameraFor(spec)", apply)
        self.assertLess(apply.find("upsertPuck(spec)"), apply.find("loadShade"))
        self.assertLess(apply.find("cameraFor(spec)"), apply.find("loadOsm"))
        self.assertLess(apply.find("requestRender()"), apply.find("loadAerial"))
        self.assertIn("req.timeout", desk)

    def test_tx_west_naip_covers_the_device_puck(self):
        aerial = (ROOT / "Resources" / "Packs" / "tx-west" / "aerial.pmtiles").read_bytes()[:127]
        min_lon = struct.unpack_from("<i", aerial, 102)[0] / 1e7
        min_lat = struct.unpack_from("<i", aerial, 106)[0] / 1e7
        max_lon = struct.unpack_from("<i", aerial, 110)[0] / 1e7
        max_lat = struct.unpack_from("<i", aerial, 114)[0] / 1e7
        lat, lon = 31.87049, -106.597333
        inside_naip = min_lat <= lat <= max_lat and min_lon <= lon <= max_lon
        self.assertTrue(inside_naip, "device YOU must sit inside packed NAIP")
        shade = ROOT / "Resources" / "Packs" / "tx-west" / "hillshade.png"
        osm = ROOT / "Resources" / "Packs" / "tx-west" / "osm.pmtiles"
        khan = ROOT / "Resources" / "Packs" / "tx-west" / "khan.pmtiles"
        self.assertTrue(shade.is_file())
        self.assertTrue(osm.is_file())
        self.assertTrue(khan.is_file())
        header = osm.read_bytes()[:127]
        o_min_lon = struct.unpack_from("<i", header, 102)[0] / 1e7
        o_min_lat = struct.unpack_from("<i", header, 106)[0] / 1e7
        o_max_lon = struct.unpack_from("<i", header, 110)[0] / 1e7
        o_max_lat = struct.unpack_from("<i", header, 114)[0] / 1e7
        self.assertTrue(o_min_lat <= lat <= o_max_lat and o_min_lon <= lon <= o_max_lon)

    def test_map_navigation_is_on_the_globe(self):
        """Nav is the globe: tap routes on Cesium. Overlay chips must not steal the canvas."""
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("Spacer(minLength: 0)\n                .allowsHitTesting(false)", tab)
        tap = tab.split("onMapTap:")[1].split("onMapHold:")[0]
        self.assertIn("pickDestination(lat: lat, lon: lon)", tap)
        self.assertIn("navigate(mode:", tap)

    def test_shade_request_image_is_a_promise(self):
        """Device: TypeError a.then is not a function in processImagery."""
        desk = read("Resources", "Globe", "desk.js")
        shade = desk.split("ShadeTile.prototype.requestImage")[1].split("function loadShade")[0]
        self.assertIn("Promise.resolve(this._img)", shade)
        self.assertIn("showRenderLoopErrors: false", desk)

    def test_globe_does_not_reload_pack_on_live_ticks(self):
        """Device stills: streets then void then streets. GPS apply() reloaded pack tiles."""
        desk = read("Resources", "Globe", "desk.js")
        apply = desk.split("function apply(spec)")[1].split("function boot")[0]
        self.assertIn("lastGround", apply)
        self.assertLess(apply.find("lastGround"), apply.find("loadShade"))
        self.assertIn("lastLive", apply)
        self.assertLess(apply.find("upsertPuck"), apply.find("clearCoins"))
        puck = desk.split("function upsertPuck")[1].split("function drawCoins")[0]
        self.assertIn('getById("puck")', puck)
        clear = desk.split("function clearCoins")[1].split("function drawPackBox")[0]
        self.assertNotIn('id === "puck"', clear)
        camera = desk.split("function cameraFor(spec)")[1].split("function pickId")[0]
        lock = camera.split("spec.lockOn")[1].split("spec.fitToken")[0]
        self.assertIn("lookAt", lock)
        self.assertIn("HeadingPitchRange", lock)
        self.assertIn("cancelFlight", lock)
        self.assertNotIn("trackedEntity = tracked", lock)
        self.assertNotIn("shouldAnimate = true", lock)

    def test_globe_does_not_flash_on_live_heading_ticks(self):
        """136 stills: packed photo, then brown void with no YOU, then photo again."""
        desk = read("Resources", "Globe", "desk.js")
        globe = read("Blackout", "GlobeView.swift")
        tab = read("Blackout", "MapTab.swift")
        root = read("Blackout", "RootChrome.swift")
        camera = desk.split("function cameraFor(spec)")[1].split("function pickId")[0]
        apply = desk.split("function apply(spec)")[1].split("function boot")[0]
        canvas = tab.split("private func canvas")[1].split("private var coverUp")[0]
        hud = tab.split("private func hud")[1].split("private var overlayRail")[0]
        tab_chrome = root.split("private var tabChrome")[1].split("overlayBottomPad")[0]
        self.assertIn("lastCam", desk)
        self.assertLess(camera.find("lastCam"), camera.find("trackedEntity"))
        self.assertLess(camera.find("lastCam"), camera.find("flyToBoundingSphere"))
        self.assertNotIn('type: "pulse"', apply)
        self.assertNotIn('puck["heading"]', globe)
        self.assertIn("transaction { $0.animation = nil }", canvas)
        self.assertNotIn("chromeAwake", canvas)
        self.assertNotIn("chromeAwake", tab_chrome)
        self.assertIn("chromeAwake", hud)

    def test_map_stays_photo_with_readable_hud(self):
        """137 stills: Oleaster photo, HUD gone, five RALLY rows, brown void."""
        desk = read("Resources", "Globe", "desk.js")
        globe = read("Blackout", "GlobeView.swift")
        tab = read("Blackout", "MapTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        apply = desk.split("function apply(spec)")[1].split("function boot")[0]
        dem_catch = desk.split("function loadDem(")[1].split("function ShadeTile")[0].split(".catch")[1]
        hud = tab.split("private func hud")[1].split("private var overlayRail")[0]
        pull = app.split("func pullFix()")[1].split("func notePipFix")[0]
        ground_catch = apply.split("loadAerial")[1].split(".catch")[1].split("loadGeo")[0]
        self.assertIn("pulse()", pull)
        self.assertNotIn("markList", hud)
        self.assertIn("shadeOn", apply)
        self.assertLess(apply.find("shadeOn"), apply.find("loadShade"))
        self.assertIn("!aerialOn", apply.split("loadShade")[0])
        self.assertNotIn("EllipsoidTerrainProvider", dem_catch)
        self.assertIn("lastGroundKey = groundKey", ground_catch)
        self.assertIn("max-age", globe)
        self.assertIn("maximumScreenSpaceError", desk)
        self.assertNotIn('puck["heading"]', globe)

    def test_locked_stays_on_the_neighborhood_photo(self):
        """138 stills: LOCKED brown void, Oleaster photo, then the globe limb."""
        desk = read("Resources", "Globe", "desk.js")
        globe = read("Blackout", "GlobeView.swift")
        dem = read("Resources", "Packs", "tx-west", "dem.json")
        camera = desk.split("function cameraFor(spec)")[1].split("function pickId")[0]
        key = desk.split("function cameraKey(spec)")[1].split("function cameraFor")[0]
        lock = camera.split("spec.lockOn")[1].split("spec.fitToken")[0]
        dem_load = desk.split("function loadDem(")[1].split("function ShadeTile")[0]
        boot = desk.split("function boot()")[1].split("window.KHAN")[0]
        handler = globe.split("final class PackFileSchemeHandler")[1]
        self.assertIn("json.grid", dem_load)
        self.assertIn('"grid"', dem)
        self.assertNotIn('"heights"', dem[:800])
        self.assertIn("puck.lat", key)
        self.assertIn("spec.lockOn", key)
        self.assertIn("lookAt", lock)
        self.assertIn("HeadingPitchRange", lock)
        self.assertIn("cancelFlight", lock)
        self.assertIn("fromDegrees", lock)
        self.assertIn("spec.height", lock)
        self.assertNotIn("trackedEntity = tracked", lock)
        self.assertNotIn("shouldAnimate = true", camera)
        self.assertIn("maximumZoomDistance", camera)
        self.assertIn("maximumZoomDistance", boot)
        self.assertIn("tileCacheSize", boot)
        self.assertIn("preloadSiblings", boot)
        self.assertIn("archives", handler)
        self.assertIn("mappedIfSafe", handler)
        self.assertIn("subdata(in:", handler)

    def test_packed_3d_nav_is_usgs_osm_not_google(self):
        """Off-grid 3D desk: packed NAIP + OSM houses + walk DEM. Never Google tiles."""
        desk = read("Resources", "Globe", "desk.js")
        globe = read("Blackout", "GlobeView.swift")
        tab = read("Blackout", "MapTab.swift")
        blob = (desk + globe + tab).lower()
        self.assertNotIn("googleapis", blob)
        self.assertNotIn("maps.google", blob)
        self.assertNotIn("mt.google", blob)
        desk3d = json.loads(read("Resources", "Packs", "tx-west", "desk3d.geojson"))
        walk = json.loads(read("Resources", "Packs", "tx-west", "walk-dem.json"))
        feats = desk3d.get("features") or []
        self.assertGreaterEqual(len(feats), 40)
        self.assertTrue(any((f.get("properties") or {}).get("height_m") for f in feats))
        lat, lon = 31.87050, -106.59732
        self.assertTrue(any(_desk3d_covers(f, lon, lat) for f in feats))
        self.assertLess(float(walk["cellDegrees"]), 0.002)
        self.assertLessEqual(walk["west"], lon)
        self.assertGreaterEqual(walk["east"], lon)
        self.assertLessEqual(walk["south"], lat)
        self.assertGreaterEqual(walk["north"], lat)
        self.assertIn("extrudedHeight", desk)
        self.assertIn("RELATIVE_TO_GROUND", desk)
        self.assertIn("loadKhan3d", desk)
        self.assertIn("OfflineMapView(", tab)
        self.assertNotIn("GlobeView(", tab)
        cam = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        self.assertIn("walkPitch: Double = 55", cam)
        self.assertIn("static func followHeading(", cam)
        offline = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift")
        self.assertIn("holdPitch(godsEye: false)", offline)
        self.assertIn("PackCamera.followHeading", offline)
        layers = offline.split("public static func applyEyeLayers")[1].split("public static func applyEyePalette")[0]
        self.assertNotIn("godsEye && EyeDesk.layerOn(.aerial", layers)
        self.assertIn("!godsEye || EyeDesk.layerOn(.aerial, in: layers)", layers)
        self.assertIn("layer.isVisible = !aerial", layers)
        self.assertNotIn("layer.isVisible = !(godsEye && aerial)", layers)
        self.assertIn(
            "let shade = !godsEye || EyeDesk.layerOn(.shade, in: layers) || aerialWanted",
            layers,
        )
        self.assertIn('id.hasPrefix("khan-")', layers)
        self.assertIn("layer.isVisible = true", layers)
        camera = desk.split("function cameraFor(spec)")[1].split("function pickId")[0]
        lock = camera.split("spec.lockOn")[1].split("spec.fitToken")[0]
        self.assertIn("lookAt", lock)
        self.assertIn("HeadingPitchRange", lock)

    def test_globe_looks_at_oleaster_not_the_pack_horizon(self):
        """135 stills: EYE is stretched hillshade; LOCKED is a white disk over YOU."""
        desk = read("Resources", "Globe", "desk.js")
        globe = read("Blackout", "GlobeView.swift")
        puck = desk.split("function upsertPuck")[1].split("function drawCoins")[0]
        camera = desk.split("function cameraFor(spec)")[1].split("function pickId")[0]
        eye = camera.split("spec.godsEye")[1].split("spec.lockOn")[0]
        boot = desk.split("function boot()")[1].split("window.KHAN")[0]
        self.assertNotIn("semiMajorAxis", puck)
        self.assertNotIn("ellipse:", puck)
        self.assertIn("viewFrom", puck)
        self.assertIn("minimumZoomDistance", boot)
        self.assertIn("sphere.radius", eye)
        self.assertIn("spec.height", eye)
        self.assertNotIn("spec.range ||", eye)
        self.assertNotIn("holdPitch(godsEye: true) - 90", globe)
        self.assertIn("godsEye ? -90 : -55", globe)

    def test_turns_do_not_cover_the_globe(self):
        """Device stills: TURNS plate sits on the route. Dest rail already names the next street."""
        tab = read("Blackout", "MapTab.swift")
        card = read("Blackout", "SpeakTurnCard.swift")
        app = read("Blackout", "AppRuntime.swift")
        cover = tab.split("private var coverUp")[1].split("private func hud")[0]
        hud = tab.split("private func hud")[1].split("private var searchField")[0]
        chrome = app.split("func applyRemainingChrome")[1].split("func resetLiveGuide")[0]
        speak = app.split("func speakMap()")[1].split("func closeSpeakTurns")[0]
        dest = tab.split("MapFieldDestRail(")[1].split("private struct MapFieldDestRail")[0]
        self.assertNotIn("showSpeakTurns", cover)
        self.assertIn("SpeakTurnCard(", hud)
        self.assertNotIn("HoldGlassShell(", card)
        self.assertIn("prefix(2)", card)
        self.assertIn('Button("CLOSE")', card)
        self.assertNotIn("showSpeakTurns", chrome)
        self.assertNotIn("showSpeakTurns = !speakHUDTurns.isEmpty", speak)
        self.assertIn("toggleSpeakTurns", dest)
        self.assertIn("func toggleSpeakTurns()", app)

    def test_four_tabs_four_dock_no_fifth(self):
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        tab = read("Blackout", "MapTab.swift")
        root = read("Blackout", "RootChrome.swift")
        self.assertIn("case map, comms, field, expedition", tokens)
        self.assertIn("case mark, walk, drive, speak", tokens)
        self.assertIn("BlackoutTokens.MapDock.allCases", tab)
        self.assertIn("ForEach(BlackoutTab.allCases)", root)
        self.assertNotIn("case .watch", tokens)
        self.assertIn('updateTitle = "UPDATE"', tokens)
        self.assertIn('godsEyeTitle = "KHAN EYE"', tokens)


if __name__ == "__main__":
    unittest.main()
