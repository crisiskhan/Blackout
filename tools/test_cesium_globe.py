#!/usr/bin/env python3
"""Cesium is the only map. UPDATE is the only socket. Airplane otherwise."""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text(errors="ignore")


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
        self.assertIn("GlobeView(", tab)
        self.assertNotIn("OfflineMapView(", tab)
        self.assertIn("aerial.pmtiles", tab)
        self.assertIn("dem.json", tab)
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
