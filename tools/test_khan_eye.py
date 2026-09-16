#!/usr/bin/env python3
"""KHAN EYE paints packed USGS NAIP photo, then packed OSM houses.

Airplane. No live photo mesh. The desk reads `aerial.pmtiles` and
`khan.pmtiles` built at pack time. Walking MAP is the 3D photo desk.
"""
from __future__ import annotations

import gzip
import json
import sys
import unittest
from pathlib import Path

import mapbox_vector_tile
from pmtiles.reader import MmapSource, Reader

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from v3 import aerial, khan  # noqa: E402
from v3.fetch_packs import PACKS, maplibre_style  # noqa: E402
from v3.tiles import lonlat_to_tile  # noqa: E402

PACK_ROOT = ROOT / "Resources" / "Packs"
SWIFT = ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift"
OFFLINE = ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "OfflineMapView.swift"
DOWNTOWN = {"lat": 31.7587, "lon": -106.4869}


class HeightAndKindTests(unittest.TestCase):
    def test_a_house_is_a_house(self):
        self.assertEqual(khan.height_m({"building": "house"}), 5.0)
        self.assertEqual(khan.height_m({"building": "apartments"}), 14.0)
        self.assertEqual(khan.height_m({"building": "yes", "height": "11"}), 11.0)
        self.assertAlmostEqual(khan.height_m({"building": "yes", "building:levels": "3"}), 9.6)
        self.assertAlmostEqual(khan.height_m({"building": "yes", "height": "32 ft"}), 32 * 0.3048)
        self.assertEqual(khan.height_m({"building": "shed"}), 2.5)

    def test_street_furniture_kinds(self):
        self.assertEqual(khan.furniture_kind({"natural": "tree"}), "tree")
        self.assertEqual(khan.furniture_kind({"highway": "traffic_signals"}), "signal")
        self.assertEqual(khan.furniture_kind({"highway": "street_lamp"}), "lamp")
        self.assertEqual(khan.furniture_kind({"highway": "stop"}), "sign")
        self.assertEqual(khan.sign_text({"highway": "stop"}), "STOP")
        self.assertEqual(khan.sign_text({"traffic_sign": "yield"}), "YIELD")
        self.assertIsNone(khan.furniture_kind({"highway": "residential"}))

    def test_geom_buildings_and_tree_disks(self):
        osm = {
            "elements": [
                {
                    "type": "way",
                    "id": 1,
                    "tags": {"building": "house", "height": "6"},
                    "geometry": [
                        {"lat": 31.76, "lon": -106.49},
                        {"lat": 31.76, "lon": -106.489},
                        {"lat": 31.761, "lon": -106.489},
                        {"lat": 31.761, "lon": -106.49},
                        {"lat": 31.76, "lon": -106.49},
                    ],
                },
                {
                    "type": "node",
                    "id": 2,
                    "lat": 31.7602,
                    "lon": -106.4902,
                    "tags": {"natural": "tree"},
                },
                {
                    "type": "node",
                    "id": 3,
                    "lat": 31.7603,
                    "lon": -106.4903,
                    "tags": {"highway": "traffic_signals"},
                },
            ]
        }
        fc = khan.elements_to_geojson(osm)
        kinds = [f["properties"]["kind"] for f in fc["features"]]
        self.assertIn("house", kinds)
        self.assertIn("tree", kinds)
        self.assertIn("signal", kinds)
        house = next(f for f in fc["features"] if f["properties"]["kind"] == "house")
        self.assertEqual(house["geometry"]["type"], "Polygon")
        self.assertEqual(house["properties"]["height_m"], 6.0)
        tree = next(f for f in fc["features"] if f["properties"]["kind"] == "tree")
        self.assertEqual(tree["geometry"]["type"], "Polygon")


class StyleAndResolverTests(unittest.TestCase):
    def test_style_extrudes_houses_only_in_khan_eye(self):
        style = maplibre_style("tx-west", None)
        self.assertEqual((style.get("sources") or {}).get("khan", {}).get("type"), "vector")
        self.assertEqual(style["sources"]["khan"]["url"], "pmtiles://khan.pmtiles")
        layers = {item["id"]: item for item in style["layers"]}
        for lid in (
            khan.KHAN_BUILDINGS_ID,
            khan.KHAN_TREES_ID,
            khan.KHAN_SIGNALS_ID,
            khan.KHAN_LAMPS_ID,
            khan.KHAN_SIGNS_ID,
        ):
            self.assertIn(lid, layers)
            self.assertEqual((layers[lid].get("layout") or {}).get("visibility"), "none")
            self.assertEqual(layers[lid]["source"], "khan")
            self.assertTrue(layers[lid].get("source-layer"), lid)
        self.assertEqual(layers[khan.KHAN_BUILDINGS_ID]["type"], "fill-extrusion")
        self.assertEqual(layers[khan.KHAN_TREES_ID]["type"], "fill-extrusion")
        self.assertEqual(layers[khan.KHAN_BUILDINGS_ID]["source-layer"], "building")
        self.assertEqual(layers[khan.KHAN_SIGNALS_ID]["source-layer"], "furniture")
        self.assertEqual(layers[khan.KHAN_BUILDINGS_ID]["minzoom"], 11)
        self.assertEqual(layers[khan.KHAN_TREES_ID]["minzoom"], 11)
        self.assertEqual(layers[khan.KHAN_SIGNALS_ID]["minzoom"], 11)
        self.assertEqual(layers[khan.KHAN_LAMPS_ID]["minzoom"], 11)
        self.assertEqual(layers[khan.KHAN_SIGNS_ID]["minzoom"], 12)
        self.assertEqual(layers[khan.KHAN_BUILDINGS_ID]["paint"]["fill-extrusion-opacity"], 1.0)
        self.assertEqual(khan.HOUSE_INK, "#A39C94")
        self.assertEqual(khan.TREE_INK, "#3F8F4E")
        self.assertEqual(style["sources"]["aerial"]["type"], "raster")
        self.assertEqual(style["sources"]["aerial"]["url"], "pmtiles://aerial.pmtiles")
        self.assertEqual(style["sources"]["aerial"]["attribution"], aerial.NAIP_CREDIT)
        ids = [item["id"] for item in style["layers"]]
        self.assertIn("aerial", ids)
        self.assertEqual(ids.index("aerial"), ids.index("land-fill") + 1)
        self.assertLess(ids.index("aerial"), ids.index(khan.KHAN_BUILDINGS_ID))
        self.assertEqual((layers["aerial"].get("layout") or {}).get("visibility"), "none")
        blob = json.dumps(style).lower()
        self.assertNotIn("https://", blob)
        self.assertNotIn("cesium", blob)
        self.assertNotIn("googleapis", blob)

    def test_resolver_and_eye_layers_lock(self):
        swift = SWIFT.read_text()
        offline = OFFLINE.read_text()
        self.assertIn("resolverVersion = 11", swift)
        self.assertIn("func attachKhanLayers", swift)
        self.assertIn("func attachAerialLayers", swift)
        self.assertIn("khan.pmtiles", swift)
        self.assertIn("aerial.pmtiles", swift)
        self.assertIn('"type": "fill-extrusion"', swift)
        self.assertIn('"type": "raster"', swift)
        self.assertIn("kind == \"vector\" || kind == \"raster\"", swift)
        self.assertIn("source-layer", swift.split("func attachKhanLayers")[1].split("func attachWaterLayers")[0])
        self.assertIn('khanBuildingSourceLayer = "building"', swift)
        self.assertIn('khanFurnitureSourceLayer = "furniture"', swift)
        eye = offline.split("public static func applyEyeLayers")[1].split("public static func applyEyePalette")[0]
        self.assertIn('id.hasPrefix("khan-")', eye)
        self.assertIn("layer.isVisible = true", eye)
        self.assertIn("layer.isVisible = aerial", eye)
        self.assertIn("!godsEye || EyeDesk.layerOn(.aerial, in: layers)", eye)
        self.assertIn("layer.isVisible = !(godsEye && aerial)", eye)
        self.assertIn("coversPhoto", eye)
        self.assertIn("aerial ? 0", eye)
        self.assertNotIn("URLSession", swift)
        self.assertNotIn("WKWebView", swift)
        tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
        inst = (ROOT / "Blackout" / "InstrumentsView.swift").read_text()
        self.assertIn("OfflineMapView(", tab)
        self.assertNotIn("GlobeView(", tab)
        self.assertNotIn("eyeDeskRail", tab)
        self.assertNotIn("HUDGlassCard", tab)
        desk = inst.split("private var eyeDeskPlate")[1].split("private func eyeDeskCaption")[0]
        self.assertIn("HUDGlassCard", desk)
        self.assertIn("eyeDeskCaption", desk)
        self.assertIn("LAYERS", desk)
        self.assertIn("LOOK", desk)
        self.assertIn("MARK", desk)
        self.assertIn("SCENE", desk)
        self.assertNotIn("padding(.top, 52)", tab)
        hud = tab.split("private func hud")[1].split("private var overlayRail")[0]
        self.assertIn("overlayRail", hud)
        self.assertIn("if !runtime.godsEye", hud)
        self.assertNotIn("eyeDeskRail", hud)
        self.assertEqual(tab.count("runtime.hudLayout.overlay"), 2)
        self.assertIn("layers[index] = layer", swift.split("func attachKhanLayers")[1].split("func attachWaterLayers")[0])
        tests = (
            ROOT
            / "Packages"
            / "MapLibreMap"
            / "Tests"
            / "MapLibreMapTests"
            / "MapLibreMapTests.swift"
        ).read_text()
        self.assertIn("PackStyle.khanBuildingsLayerID", tests)
        count = 0
        for path in ROOT.joinpath("Packages", "MapLibreMap", "Tests").rglob("*.swift"):
            import re

            count += len(re.findall(r"func test[A-Z]\w+\(", path.read_text()))
        self.assertEqual(count, 177)


class PackedArchiveTests(unittest.TestCase):
    def test_every_walkable_pack_ships_khan_tiles(self):
        for pid in PACKS:
            dest = PACK_ROOT / pid
            archive = dest / "khan.pmtiles"
            self.assertTrue(archive.is_file(), f"{pid} missing khan.pmtiles")
            self.assertGreater(archive.stat().st_size, 1000, f"{pid} khan.pmtiles is empty")
            manifest = json.loads((dest / "manifest.json").read_text())
            files = manifest.get("files") or []
            self.assertIn("khan.pmtiles", files)
            self.assertNotIn("khan.geojson", files)
            self.assertIn("aerial.pmtiles", files)
            archive_air = dest / "aerial.pmtiles"
            self.assertTrue(archive_air.is_file(), f"{pid} missing aerial.pmtiles")
            self.assertGreater(archive_air.stat().st_size, 1000, f"{pid} aerial.pmtiles is empty")
            style = json.loads((dest / "style.json").read_text())
            self.assertEqual(style["sources"]["khan"]["url"], "pmtiles://khan.pmtiles")
            self.assertEqual(style["sources"]["aerial"]["url"], "pmtiles://aerial.pmtiles")
            self.assertEqual(style["sources"]["aerial"]["type"], "raster")
            ids = [layer["id"] for layer in style["layers"]]
            self.assertIn(khan.KHAN_BUILDINGS_ID, ids)
            self.assertIn("aerial", ids)
            self.assertEqual(ids.index("aerial"), ids.index("land-fill") + 1)
            self.assertLess(ids.index("aerial"), ids.index(khan.KHAN_BUILDINGS_ID))
            self.assertEqual(style["light"]["intensity"], 0.7)
            paints = {item["id"]: item for item in style["layers"]}
            self.assertEqual(paints[khan.KHAN_TREES_ID]["minzoom"], 11)
            self.assertEqual(paints[khan.KHAN_SIGNS_ID]["minzoom"], 12)
            self.assertIn(khan.HOUSE_INK, json.dumps(paints[khan.KHAN_BUILDINGS_ID]))

    def test_downtown_el_paso_has_houses(self):
        archive = PACK_ROOT / "tx-west" / "khan.pmtiles"
        self.assertTrue(archive.is_file())
        found = 0
        kinds: set[str] = set()
        with open(archive, "rb") as fh:
            reader = Reader(MmapSource(fh))
            for z in (12, 13, 14):
                cx, cy = lonlat_to_tile(DOWNTOWN["lon"], DOWNTOWN["lat"], z)
                blob = reader.get(z, int(cx), int(cy))
                if not blob:
                    continue
                tile = mapbox_vector_tile.decode(gzip.decompress(blob))
                for feat in tile.get("building", {}).get("features", []):
                    kind = (feat.get("properties") or {}).get("kind")
                    if kind and kind not in {"tree", "wood"}:
                        found += 1
                        kinds.add(str(kind))
        self.assertGreater(found, 8, f"downtown El Paso has no packed houses, kinds={kinds}")

    def test_downtown_el_paso_has_photo(self):
        archive = PACK_ROOT / "tx-west" / "aerial.pmtiles"
        self.assertTrue(archive.is_file())
        with open(archive, "rb") as fh:
            reader = Reader(MmapSource(fh))
            cx, cy = lonlat_to_tile(DOWNTOWN["lon"], DOWNTOWN["lat"], 16)
            blob = reader.get(16, int(cx), int(cy))
        self.assertIsNotNone(blob, "downtown El Paso has no packed photo at z16")
        assert blob is not None
        self.assertTrue(blob.startswith(b"\xff\xd8"), "downtown El Paso aerial is not JPEG")
        self.assertGreater(len(blob), 800)

    def test_oleaster_walk_has_photo(self):
        """Device YOU on Oleaster Dr. Packed USGS NAIP, not a live feed."""
        you = {"lat": 31.87049, "lon": -106.597333}
        boxes = aerial.photo_bboxes({"id": "tx-west", "slices": PACKS["tx-west"]["slices"]})
        union = aerial.union_photo_bbox(boxes)
        self.assertGreaterEqual(len(boxes), 2)
        self.assertTrue(union["south"] <= you["lat"] <= union["north"])
        self.assertTrue(union["west"] <= you["lon"] <= union["east"])
        archive = PACK_ROOT / "tx-west" / "aerial.pmtiles"
        with open(archive, "rb") as fh:
            reader = Reader(MmapSource(fh))
            cx, cy = lonlat_to_tile(you["lon"], you["lat"], 16)
            blob = reader.get(16, int(cx), int(cy))
        self.assertIsNotNone(blob, "Oleaster walk has no packed photo at z16")
        assert blob is not None
        self.assertTrue(blob.startswith(b"\xff\xd8"), "Oleaster aerial is not JPEG")
        self.assertGreater(len(blob), 800)


if __name__ == "__main__":
    unittest.main()
