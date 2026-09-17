#!/usr/bin/env python3
"""Dead engines off the phone. Map coverage stays. Linux contracts only."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "third_party"))
sys.path.insert(0, str(ROOT / "tools"))


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


class CesiumGoneTests(unittest.TestCase):
    def test_cesium_globe_does_not_ship(self):
        self.assertFalse((ROOT / "Blackout" / "GlobeView.swift").exists())
        self.assertFalse((ROOT / "Resources" / "Globe").exists())
        copy = read("tools", "copy_resources.sh")
        self.assertIn("--exclude 'Globe'", copy)
        pbx = read("Blackout.xcodeproj", "project.pbxproj")
        self.assertIn("copy_resources.sh", pbx)
        gen = read("tools", "v3", "generate_project.py")
        self.assertIn("copy_resources.sh", gen)
        for path in (ROOT / "Blackout").rglob("*.swift"):
            blob = path.read_text()
            self.assertNotIn("WKWebView", blob, path.name)
            self.assertNotIn("import WebKit", blob, path.name)
        for path in (ROOT / "Packages").rglob("*.swift"):
            blob = path.read_text()
            self.assertNotIn("WKWebView", blob, str(path.relative_to(ROOT)))
        audit = read("tools", "audit_offline.sh")
        self.assertNotIn("Cesium globe pack", audit)
        self.assertIn("no WKWebView", audit)
        agents = read("AGENTS.md")
        self.assertIn("no wkwebview", agents.lower())
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("OfflineMapView(", tab)
        self.assertNotIn("GlobeView(", tab)


class LlamaUnlinkedTests(unittest.TestCase):
    def test_ask_has_no_llama_binary_until_a_model_ships(self):
        pkg = read("Packages", "FieldAsk", "Package.swift")
        llama = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldAskLlama.swift")
        ask = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldAsk.swift")
        self.assertNotIn("import llama", llama)
        self.assertNotIn("llama-b8638-xcframework.zip", pkg)
        self.assertNotIn(".binaryTarget", pkg)
        self.assertNotIn('"llama"', pkg)
        self.assertIn("static func complete(", llama)
        self.assertIn("return nil", llama)
        self.assertIn("NO ASK MODEL", ask)
        self.assertNotIn("URLSession", llama)
        inspect = read("tools", "tf_ipa_inspect.py")
        self.assertIn("org.ggml.llama", inspect)
        ci = read("tools", "test_ci_opt.py")
        self.assertNotIn(
            'fail("re-sign must name llama.framework so it is not sealed as MapLibre")',
            ci,
        )


class LeftoverSliceTests(unittest.TestCase):
    def test_copy_leaves_slice_geojson_and_desk3d_off_the_phone(self):
        copy = read("tools", "copy_resources.sh")
        for name in (
            "metro.geojson",
            "region.geojson",
            "union.geojson",
            "corridor.geojson",
            "border.geojson",
            "desk3d.geojson",
            "pois.geojson",
            "walk-dem.json",
        ):
            self.assertIn(f"--exclude 'Packs/*/{name}'", copy, name)
        self.assertIn("--exclude 'Packs/*/osm.geojson'", copy)
        self.assertIn("--exclude 'Packs/*/khan.geojson'", copy)


class OneAerialOnPhoneTests(unittest.TestCase):
    def test_phone_merge_collapses_github_shards(self):
        aerial = read("tools", "v3", "aerial.py")
        phone = read("tools", "pack_phone.py")
        copy = read("tools", "copy_resources.sh")
        swift = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        )
        self.assertIn("def merge_phone_archives", aerial)
        self.assertIn("merge_phone_archives", phone)
        self.assertIn("collapse_style_aerial", phone)
        self.assertIn("writes the bundle copy", phone)
        self.assertIn("pack_phone.py", copy)
        head = aerial.split("def ")[0]
        self.assertNotIn("from .tiles import", head)
        self.assertIn("all_tiles", aerial.split("def read_archive")[1].split("def style_source")[0])
        attach = swift.split("public static func attachAerialLayers")[1].split(
            "Packed OSM houses"
        )[0]
        self.assertIn("aerialFileName", attach)
        self.assertIn('hasPrefix("aerial")', attach)

    def test_copy_phase_imports_without_mapbox_vector_tile(self):
        # Unsigned compile and TestFlight run copy_resources.sh with the
        # runner's python3. Only tools/third_party is on that PYTHONPATH.
        env = dict(os.environ)
        env["PYTHONPATH"] = f"{ROOT / 'tools' / 'third_party'}:{ROOT / 'tools'}"
        proc = subprocess.run(
            [sys.executable, "-S", "-c", "import pack_phone"],
            cwd=str(ROOT),
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_repo_may_keep_shards_under_github_cap(self):
        from v3 import aerial as aerial_mod

        self.assertLessEqual(aerial_mod.SHARD_MAX_BYTES, 90 * 1024 * 1024)
        west = ROOT / "Resources" / "Packs" / "tx-west"
        shards = list(west.glob("aerial*.pmtiles"))
        self.assertGreaterEqual(len(shards), 1)
        for path in shards:
            self.assertLessEqual(path.stat().st_size, aerial_mod.SHARD_MAX_BYTES)


class CompassTickTests(unittest.TestCase):
    def test_heading_ticks_do_not_walk_the_style_or_rebake_unmoved_you(self):
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        sync = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        )
        apply = offline.split("func apply(_ spec: OverlaySpec")[1].split(
            "func stamp(_ mark"
        )[0]
        self.assertIn("OverlaySync.needsEyeLayerPass", apply)
        self.assertIn("PersonMarkPaint.needsImage", offline)
        self.assertIn("enum PersonMarkPaint", sync)
        self.assertIn("enum OverlaySync", sync)
        self.assertIn("static func needsEyeLayerPass", sync)
        paint = offline.split("func paintPersonMarks")[1].split("func syncRoute")[0]
        self.assertIn("PersonMarkPaint.needsImage", paint)


class BootActivePackTests(unittest.TestCase):
    def test_boot_loads_the_open_pack_only(self):
        app = read("Blackout", "AppRuntime.swift")
        boot = app.split("private func runBoot()")[1].split("private func prefetchField")[0]
        self.assertNotIn("catalog.count * 2", boot)
        self.assertIn("store.active", boot)
        self.assertIn("RouteGraph.load", boot)
        self.assertIn("WaterIndex.load", boot)
        self.assertIn("warmupActiveGraph", app)
        switch = app.split("func switchPack")[1].split("func applyMapKeepAwake")[0]
        self.assertIn("warmupActiveGraph", switch)


class PauseOffMapTests(unittest.TestCase):
    def test_maplibre_stays_mounted_and_pauses_off_map(self):
        root = read("Blackout", "RootChrome.swift")
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        self.assertIn("MapTab(runtime: runtime)", root)
        self.assertNotIn("case .map: MapTab(runtime: runtime)", root)
        self.assertIn("preferredFramesPerSecond", offline)
        chrome = offline.split("private func applyInteraction")[1].split(
            "private var overlaySpec"
        )[0]
        self.assertIn("interactive", chrome)
        self.assertIn("preferredFramesPerSecond", chrome)
        self.assertIn("MLNMapViewPreferredFramesPerSecond.default", chrome)
        self.assertIn("MLNMapViewPreferredFramesPerSecond(rawValue: 1)", chrome)
        self.assertNotIn("\n            : 1\n", chrome)


class OverlayTilesTests(unittest.TestCase):
    def test_pack_overlays_are_vector_tiles_not_whole_geojson(self):
        overlay = read("tools", "v3", "overlay.py")
        self.assertIn("OVERLAY_FILE = \"overlay.pmtiles\"", overlay)
        self.assertIn("def write_overlay", overlay)
        copy = read("tools", "copy_resources.sh")
        for name in (
            "contours.geojson",
            "wild.geojson",
            "layers/public_land.geojson",
            "layers/flood.geojson",
            "layers/hazards.geojson",
            "layers/ground.geojson",
            "layers/water.geojson",
        ):
            self.assertIn(f"--exclude 'Packs/*/{name}'", copy, name)
        self.assertNotIn("--exclude 'Packs/*/layers/water.bin'", copy)
        for pid in ("tx-west", "nm", "tx-east"):
            dest = ROOT / "Resources" / "Packs" / pid
            self.assertTrue((dest / "overlay.pmtiles").is_file(), pid)
            style = json.loads((dest / "style.json").read_text())
            sources = style["sources"]
            self.assertEqual(sources["overlay"]["type"], "vector")
            self.assertEqual(sources["overlay"]["url"], "pmtiles://overlay.pmtiles")
            for dead in ("contours", "public-land", "flood", "hazards", "wild"):
                src = sources.get(dead) or {}
                self.assertNotEqual(src.get("type"), "geojson", f"{pid} {dead}")
            by_id = {layer["id"]: layer for layer in style["layers"]}
            self.assertEqual(by_id["contours"]["source"], "overlay")
            self.assertEqual(by_id["contours"]["source-layer"], "contours")
            self.assertEqual(by_id["wild-roads"]["source"], "overlay")
            self.assertEqual(by_id["wild-roads"]["source-layer"], "wild")
            self.assertEqual(by_id["public-land-fill"]["source"], "overlay")
            self.assertEqual(by_id["flood-fill"]["source"], "overlay")
            swift = read(
                "Packages",
                "MapLibreMap",
                "Sources",
                "MapLibreMap",
                "MapLibreMap.swift",
            )
            self.assertIn("overlay.pmtiles", swift)
            self.assertIn("source-layer", swift.split("attachWorkedGround")[1].split("enum OverlaySync")[0])
            offline = read(
                "Packages",
                "MapLibreMap",
                "Sources",
                "MapLibreMap",
                "OfflineMapView.swift",
            )
            worked = offline.split("func packWorkedGround")[1].split("func covers")[0]
            self.assertIn("overlaySourceID", worked)
            self.assertIn("MLNVectorTileSource", worked)


class WatchStaysOmittedTests(unittest.TestCase):
    def test_watch_target_exists_and_stays_out_of_the_ipa(self):
        pbx = read("Blackout.xcodeproj", "project.pbxproj")
        self.assertIn("name = BlackoutWatch;", pbx)
        self.assertNotIn("BlackoutWatch.app in Embed Watch Content", pbx)


if __name__ == "__main__":
    unittest.main()
