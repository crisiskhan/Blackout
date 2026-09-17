#!/usr/bin/env python3
"""MapLibre is the only map. UPDATE is the only socket. Airplane otherwise."""
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


class NativeMapTests(unittest.TestCase):
    def test_cesium_is_gone(self):
        self.assertFalse((ROOT / "Blackout" / "GlobeView.swift").exists())
        self.assertFalse((ROOT / "Resources" / "Globe").exists())
        for path in list((ROOT / "Blackout").rglob("*.swift")) + list(
            (ROOT / "Packages").rglob("*.swift")
        ):
            blob = path.read_text(errors="ignore")
            self.assertNotIn("WKWebView", blob, path.name)
            self.assertNotIn("import WebKit", blob, path.name)
            self.assertNotIn("ion.cesium", blob.lower(), path.name)

    def test_map_is_offline_maplibre(self):
        tab = read("Blackout", "MapTab.swift")
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        self.assertIn("OfflineMapView(", tab)
        self.assertNotIn("GlobeView(", tab)
        self.assertIn("bootStyleURL", tab)
        self.assertIn("OSMCredit.line", offline)
        self.assertNotIn("OSMCredit.line", tab)
        self.assertIn("BlackoutTokens.MapOverlay.updateTitle", tab)
        self.assertIn("BlackoutTokens.MapOverlay.godsEyeTitle", tab)
        self.assertNotIn("private var lampRail", tab)
        overlay = tab.split("private var overlayRail")[1].split("private var hitList")[0]
        self.assertIn("instrumentsTitle", overlay)
        self.assertIn("lockTitle", overlay)
        self.assertIn("updateTitle", overlay)
        self.assertIn("godsEyeTitle", overlay)
        self.assertNotIn("NIGHT", overlay)
        self.assertNotIn("SUN", overlay)
        inst = read("Blackout", "InstrumentsView.swift")
        hud = inst.split('sectionLabel("HUD")')[1].split('sectionLabel("MAP")')[0]
        self.assertIn('Button("NIGHT")', hud)
        self.assertIn('Button("SUN")', hud)

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
        self.assertIn("NET · NONE", desk)
        self.assertIn("case vectors", desk)
        self.assertIn("case snap", desk)

    def test_pack_ground_is_hillshade_osm_khan_naip(self):
        tab = read("Blackout", "MapTab.swift")
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        swift = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        )
        west = ROOT / "Resources" / "Packs" / "tx-west"
        self.assertTrue((west / "hillshade.png").is_file())
        self.assertTrue((west / "osm.pmtiles").is_file())
        self.assertTrue((west / "khan.pmtiles").is_file())
        self.assertTrue((west / "aerial.pmtiles").is_file() or list(west.glob("aerial*.pmtiles")))
        self.assertIn("hillshade", offline)
        style = read("Resources", "Packs", "tx-west", "style.json")
        self.assertIn("osm.pmtiles", style)
        self.assertIn("khan.pmtiles", swift)
        self.assertIn("OfflineMapView(", tab)
        self.assertIn("style.json", tab)

    def test_yards_houses_and_street_names(self):
        tab = read("Blackout", "MapTab.swift")
        swift = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        )
        self.assertIn("khan-buildings", swift)
        self.assertIn("attachKhanLayers", swift)
        self.assertIn("road-labels", swift + read("Resources", "Packs", "tx-west", "style.json"))
        self.assertNotIn("TAP a street", tab)
        footer = tab.split("private func canvasFooter")[1].split("private func deskStyleURL")[0]
        self.assertNotIn("eyeHUDLines", footer)
        self.assertIn("packName", footer)
        self.assertIn("EyeDesk.noPipe", footer)
        field = tab.split("fieldChrome")[1].split("if runtime.hudCrisis")[0]
        self.assertNotIn("allowsHitTesting(false)", field)
        self.assertNotIn("Google", tab)
        self.assertNotIn("Waze", tab)

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

    def test_map_navigation_is_on_the_canvas(self):
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("Spacer(minLength: 0)\n                .allowsHitTesting(false)", tab)
        tap = tab.split("onMapTap:")[1].split("onMapHold:")[0]
        self.assertIn("pickDestination(lat: lat, lon: lon)", tap)
        self.assertIn("navigate(mode:", tap)

    def test_heading_ticks_do_not_flash(self):
        tab = read("Blackout", "MapTab.swift")
        root = read("Blackout", "RootChrome.swift")
        canvas = tab.split("private func canvas")[1].split("private var coverUp")[0]
        hud = tab.split("private func hud")[1].split("private var overlayRail")[0]
        tab_chrome = root.split("private var tabChrome")[1].split("overlayBottomPad")[0]
        self.assertIn("transaction { $0.animation = nil }", canvas)
        self.assertNotIn("chromeAwake", canvas)
        self.assertNotIn("chromeAwake", tab_chrome)
        self.assertIn("chromeAwake", hud)
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        self.assertIn("PersonMarkPaint.needsImage", offline)
        self.assertIn("OverlaySync.needsEyeLayerPass", offline)

    def test_map_stays_photo_with_readable_hud(self):
        tab = read("Blackout", "MapTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        hud = tab.split("private func hud")[1].split("private var overlayRail")[0]
        pull = app.split("func pullFix()")[1].split("func notePipFix")[0]
        self.assertIn("pulse()", pull)
        self.assertNotIn("markList", hud)

    def test_packed_3d_nav_is_usgs_osm_not_google(self):
        tab = read("Blackout", "MapTab.swift")
        swift = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        )
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        blob = (swift + tab + offline).lower()
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
        self.assertIn("OfflineMapView(", tab)
        self.assertNotIn("GlobeView(", tab)
        self.assertIn("walkPitch: Double = 55", swift)
        self.assertIn("static func followHeading(", swift)
        self.assertIn("holdPitch(godsEye: false)", offline)
        self.assertIn("PackCamera.followHeading", offline)
        layers = offline.split("public static func applyEyeLayers")[1].split(
            "public static func applyEyePalette"
        )[0]
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

    def test_turns_do_not_cover_the_map(self):
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
