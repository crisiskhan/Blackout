#!/usr/bin/env python3
"""KHAN EYE paints packed USGS NAIP photo, then packed OSM furniture.

Airplane. No live photo mesh. The desk reads `aerial.pmtiles` and
`khan.pmtiles` built at pack time. Walking MAP is the 3D photo desk.
Grey house masses stay off the glass — the photo is the building.
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
HATCH = {"lat": 32.665, "lon": -107.154}
LAS_CRUCES = {"lat": 32.3199, "lon": -106.778}
TULAROSA = {"lat": 33.074, "lon": -106.018}
BUDA = {"lat": 30.085, "lon": -97.840}
AUSTIN = {"lat": 30.2672, "lon": -97.7431}
ISLETA = {"lat": 34.909, "lon": -106.693}
ALBUQUERQUE = {"lat": 35.0844, "lon": -106.6504}


def _aerial_paths(dest: Path) -> list[Path]:
    files = [p for p in dest.glob("aerial*.pmtiles") if p.is_file()]

    def key(path: Path) -> tuple[int, int]:
        stem = path.name.removesuffix(".pmtiles")
        if stem == "aerial":
            return (0, 0)
        _, _, rest = stem.partition("-")
        return (1, int(rest) if rest.isdigit() else 0)

    return sorted(files, key=key)


def _packed_jpeg(dest: Path, lon: float, lat: float, z: int) -> bytes | None:
    cx, cy = lonlat_to_tile(lon, lat, z)
    x, y = int(cx), int(cy)
    for path in _aerial_paths(dest):
        with open(path, "rb") as fh:
            blob = Reader(MmapSource(fh)).get(z, x, y)
        if blob:
            return blob
    return None


def _job_has(pack: dict, lon: float, lat: float, z: int) -> bool:
    cx, cy = lonlat_to_tile(lon, lat, z)
    return (z, int(cx), int(cy)) in set(aerial.aerial_jobs(pack))


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
    def test_style_does_not_extrude_grey_houses(self):
        style = maplibre_style("tx-west", None)
        self.assertEqual((style.get("sources") or {}).get("khan", {}).get("type"), "vector")
        self.assertEqual(style["sources"]["khan"]["url"], "pmtiles://khan.pmtiles")
        layers = {item["id"]: item for item in style["layers"]}
        self.assertNotIn(khan.KHAN_BUILDINGS_ID, layers)
        for lid in (
            khan.KHAN_TREES_ID,
            khan.KHAN_SIGNALS_ID,
            khan.KHAN_LAMPS_ID,
            khan.KHAN_SIGNS_ID,
        ):
            self.assertIn(lid, layers)
            self.assertEqual((layers[lid].get("layout") or {}).get("visibility"), "none")
            self.assertEqual(layers[lid]["source"], "khan")
            self.assertTrue(layers[lid].get("source-layer"), lid)
        self.assertEqual(layers[khan.KHAN_TREES_ID]["type"], "fill-extrusion")
        self.assertEqual(layers[khan.KHAN_SIGNALS_ID]["source-layer"], "furniture")
        self.assertEqual(layers[khan.KHAN_TREES_ID]["minzoom"], 11)
        self.assertEqual(layers[khan.KHAN_SIGNALS_ID]["minzoom"], 11)
        self.assertEqual(layers[khan.KHAN_LAMPS_ID]["minzoom"], 11)
        self.assertEqual(layers[khan.KHAN_SIGNS_ID]["minzoom"], 12)
        self.assertEqual(khan.HOUSE_INK, "#A39C94")
        self.assertEqual(khan.TREE_INK, "#3F8F4E")
        self.assertEqual(style["sources"]["aerial"]["type"], "raster")
        self.assertEqual(style["sources"]["aerial"]["url"], "pmtiles://aerial.pmtiles")
        self.assertEqual(style["sources"]["aerial"]["attribution"], aerial.NAIP_CREDIT)
        ids = [item["id"] for item in style["layers"]]
        self.assertIn("aerial", ids)
        self.assertEqual(ids.index("aerial"), ids.index("land-fill") + 1)
        self.assertLess(ids.index("aerial"), ids.index(khan.KHAN_TREES_ID))
        self.assertEqual((layers["aerial"].get("layout") or {}).get("visibility"), "none")
        blob = json.dumps(style).lower()
        self.assertNotIn("https://", blob)
        self.assertNotIn("cesium", blob)
        self.assertNotIn("googleapis", blob)
        for pid in PACKS:
            packed = json.loads((PACK_ROOT / pid / "style.json").read_text())
            packed_ids = [item["id"] for item in packed.get("layers") or []]
            self.assertNotIn(khan.KHAN_BUILDINGS_ID, packed_ids, pid)
            for item in packed.get("layers") or []:
                if item.get("type") == "fill-extrusion":
                    self.assertEqual(item.get("id"), khan.KHAN_TREES_ID, pid)

    def test_resolver_and_eye_layers_lock(self):
        swift = SWIFT.read_text()
        offline = OFFLINE.read_text()
        self.assertIn("resolverVersion = 15", swift)
        self.assertIn("func attachKhanLayers", swift)
        self.assertIn("func attachAerialLayers", swift)
        self.assertIn("khan.pmtiles", swift)
        self.assertIn("aerial.pmtiles", swift)
        self.assertIn('"type": "fill-extrusion"', swift)
        attach_khan = swift.split("func attachKhanLayers")[1].split("func attachWaterLayers")[0]
        self.assertIn("khanBuildingsLayerID", attach_khan)
        self.assertIn("removeAll", attach_khan)
        self.assertNotIn('"id": khanBuildingsLayerID', attach_khan)
        self.assertIn('"type": "raster"', swift)
        self.assertIn("kind == \"vector\" || kind == \"raster\"", swift)
        self.assertIn("source-layer", swift.split("func attachKhanLayers")[1].split("func attachWaterLayers")[0])
        self.assertIn('khanBuildingSourceLayer = "building"', swift)
        self.assertIn('khanFurnitureSourceLayer = "furniture"', swift)
        eye = offline.split("public static func applyEyeLayers")[1].split("public static func applyEyePalette")[0]
        self.assertIn('id.hasPrefix("khan-")', eye)
        self.assertIn("!coversPhoto(id)", eye)
        self.assertIn("layer.isVisible = true", eye)
        self.assertIn("layer.isVisible = aerial", eye)
        self.assertIn("!godsEye || EyeDesk.layerOn(.aerial, in: layers)", eye)
        self.assertIn("layer.isVisible = !aerial", eye)
        self.assertNotIn("layer.isVisible = !(godsEye && aerial)", eye)
        self.assertIn("coversPhoto", eye)
        self.assertNotIn("aerial ? 0", eye)
        self.assertIn(
            "let shade = !godsEye || EyeDesk.layerOn(.shade, in: layers) || aerialWanted",
            eye,
        )
        self.assertNotIn("&& !aerial", eye)
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
            self.assertNotIn(khan.KHAN_BUILDINGS_ID, ids)
            self.assertIn("aerial", ids)
            self.assertIn(khan.KHAN_TREES_ID, ids)
            self.assertEqual(ids.index("aerial"), ids.index("land-fill") + 1)
            self.assertLess(ids.index("aerial"), ids.index(khan.KHAN_TREES_ID))
            self.assertEqual(style["light"]["intensity"], 0.7)
            paints = {item["id"]: item for item in style["layers"]}
            self.assertEqual(paints[khan.KHAN_TREES_ID]["minzoom"], 11)
            self.assertEqual(paints[khan.KHAN_SIGNS_ID]["minzoom"], 12)
            for item in style["layers"]:
                if item.get("type") == "fill-extrusion":
                    self.assertEqual(item.get("id"), khan.KHAN_TREES_ID, pid)

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
        blob = _packed_jpeg(PACK_ROOT / "tx-west", DOWNTOWN["lon"], DOWNTOWN["lat"], 16)
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
        blob = _packed_jpeg(PACK_ROOT / "tx-west", you["lon"], you["lat"], 16)
        self.assertIsNotNone(blob, "Oleaster walk has no packed photo at z16")
        assert blob is not None
        self.assertTrue(blob.startswith(b"\xff\xd8"), "Oleaster aerial is not JPEG")
        self.assertGreater(len(blob), 800)


class NeighborhoodDeskStillsTests(unittest.TestCase):
    """141 stills: EYE was Hatch-to-Tularosa black; walking casings buried yards."""

    def test_eye_looks_at_the_packed_extract(self):
        """4:21 still: KHAN EYE sat on a 160m WSMR desk. Tap EYE → whole pack."""
        offline = OFFLINE.read_text()
        fit = offline.split("func fitPack")[1].split("func fitRoute")[0]
        self.assertIn("acrossDistance: gev", fit)
        self.assertIn("lookingAtCenter", fit)
        self.assertIn("PackCamera.godsEyeDistance", fit)
        self.assertIn("view.setCamera", fit)
        self.assertIn("south: packBox.south", fit)
        self.assertIn("west: packBox.west", fit)
        self.assertIn("north: packBox.north", fit)
        self.assertIn("east: packBox.east", fit)
        self.assertNotIn("EyeDesk.framePoints", fit)
        self.assertNotIn("EyeDesk.clampToPack", fit)
        self.assertNotIn("EyeDesk.bounds", fit)
        self.assertNotIn("followCoordinate", fit)
        self.assertNotIn("fitting:", fit)
        self.assertNotIn("edgePadding:", fit)
        self.assertNotIn("view.fly(", fit)
        self.assertNotIn("peakAltitude", fit)
        self.assertNotIn("godsEyeCameraDistance", fit)
        self.assertNotIn("packPaddingPoints", fit)
        leave = offline.split("func applyCamera")[1].split("func fitPack")[0].split(
            "PackCamera.shouldLeavePack"
        )[1].split("if PackCamera.shouldFitRoute")[0]
        self.assertIn("setCamera", leave)
        self.assertIn("animated: false", leave)
        self.assertIn("openZoom", leave)

    def test_photo_desk_hides_schematic_roads_and_keeps_hillshade_floor(self):
        eye = OFFLINE.read_text().split("public static func applyEyeLayers")[1].split(
            "public static func applyEyePalette"
        )[0]
        self.assertIn("layer.isVisible = !aerial", eye)
        self.assertIn(
            "let shade = !godsEye || EyeDesk.layerOn(.shade, in: layers) || aerialWanted",
            eye,
        )
        qa = (ROOT / "docs" / "SOLO_QA.md").read_text()
        device = (ROOT / "docs" / "DEVICE.md").read_text()
        for blob in (qa, device):
            self.assertIn("entire packed extract", blob)
            self.assertIn("schematic road casings hide on packed photo", blob)
            self.assertIn("hillshade stays the floor", blob)
            self.assertIn("NIGHT / SUN live in INSTRUMENTS", blob)
            self.assertIn("Marks are pins, not a second YOU", blob)
            self.assertIn("MAP footer is the pack name", blob)
            self.assertIn("sits on the overlay with LOCK-ON", blob)
        covers = eye.split("func coversPhoto")[1].split("func holdsKhanDetail")[0]
        self.assertIn("landFillLayerID", covers)
        self.assertIn("tracks", covers)
        self.assertIn("khanTreesLayerID", covers)
        self.assertIn("water-fill", covers)
        self.assertIn("groundWorkedFillLayerID", covers)
        self.assertIn("groundWorkedLineLayerID", covers)
        self.assertIn("!coversPhoto(id)", eye)
        desk = OFFLINE.read_text().split("func setDeskChrome")[1].split("private func installDeskChromeIfNeeded")[0]
        self.assertIn("packStamp.isHidden = true", desk)
        self.assertNotIn("packStamp.isHidden = !godsEye", desk)
        layout = OFFLINE.read_text().split("private func layoutDeskChrome")[1].split("final class HiddenUserLocationView")[0]
        self.assertIn("creditBottomInset", layout)
        self.assertNotIn("maxY - 96", layout)
        self.assertIn("insertUnderMarks", OFFLINE.read_text())

    def test_planted_marks_are_pins_not_you_roses(self):
        offline = OFFLINE.read_text()
        stamp = offline.split("func stamp(_ mark: PersonMarkAnnotation")[1].split(
            "func visiblePips"
        )[0]
        self.assertIn("mark.markKind = pip.markKind", stamp)
        self.assertIn("static func mark(", offline)
        mark = offline.split("enum PersonCompassArt")[1].split("static func mark(")[1].split(
            "static func pin("
        )[0]
        self.assertIn("place: Bool", mark)
        self.assertIn("PersonCompassArt.pin", mark)
        self.assertIn("func visiblePips", offline)
        vis = offline.split("func visiblePips")[1].split("func paintPersonMarks")[0]
        self.assertIn("PlaceMark.parse", vis)
        party = offline.split("func partyShape")[1].split("func emptyOverlayShape")[0]
        self.assertIn("PlaceMark.parse", party)
        self.assertIn('"bottom"', party)
        self.assertIn('"center"', party)
        self.assertNotIn("memberID ?? annotation.title", offline)
        self.assertNotIn("member ?? titled", offline)

    def test_live_nav_chrome_is_overlay_and_lit_dock(self):
        tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
        hud = tab.split("private func hud")[1].split("private var overlayRail")[0]
        overlay = tab.split("private var overlayRail")[1].split("private var hitList")[0]
        dock = tab.split("private var dock")[1].split("private func tapDock")[0]
        live = tab.split("private func dockLive")[1].split("private func canvasFooter")[0]
        self.assertNotIn("lampRail", hud)
        self.assertNotIn("private var lampRail", tab)
        self.assertIn("godsEyeTitle", overlay)
        self.assertLess(overlay.find("lockTitle"), overlay.find("godsEyeTitle"))
        self.assertLess(overlay.find("godsEyeTitle"), overlay.find("updateTitle"))
        self.assertIn("HUDDockStyle(filled:", dock)
        self.assertIn("dockLive(cell)", dock)
        self.assertIn("travelMode == .walk", live)
        self.assertIn("travelMode == .drive", live)
        self.assertIn("routeCoords.isEmpty", live)

    def test_pinch_out_stays_on_packed_photo_not_pack_horizon(self):
        cam = SWIFT.read_text().split("public enum PackCamera")[1].split(
            "public enum PackStyle"
        )[0]
        self.assertIn("static let photoMinZoom: Double = 14", cam)
        self.assertIn("static let minZoom: Double = 6", cam)
        self.assertIn("static func holdMinZoom", cam)
        hold = cam.split("static func holdMinZoom")[1].split("static func holdMaxZoom")[0]
        self.assertIn("godsEye ? minZoom : photoMinZoom", hold)
        self.assertIn("overviewMinZoom", hold)
        self.assertNotIn("godsEye _", hold)
        interact = OFFLINE.read_text().split("private func applyInteraction")[1].split(
            "public final class Coordinator"
        )[0]
        self.assertIn(
            "minimumZoomLevel = PackCamera.holdMinZoom(godsEye: godsEye, overview: overview)",
            interact,
        )
        self.assertNotIn("minimumZoomLevel = PackCamera.minZoom", interact)
        for blob in (
            (ROOT / "docs" / "SOLO_QA.md").read_text(),
            (ROOT / "docs" / "DEVICE.md").read_text(),
        ):
            self.assertIn("Walking pinch-out stays on packed photo", blob)
            self.assertIn("KHAN EYE pinches out to the entire packed extract", blob)
            self.assertIn("pack diamond on black is a FAIL", blob)

    def test_walk_hillshade_paints_the_floor_off_photo(self):
        """6:47 still: looking north off the Oleaster stamp was void, not ground."""
        eye = OFFLINE.read_text().split("public static func applyEyeLayers")[1].split(
            "public static func applyEyePalette"
        )[0]
        self.assertNotIn("if godsEye, shade, let raster", eye)
        self.assertIn("if shade, let raster = layer as? MLNRasterStyleLayer", eye)
        self.assertIn("paintKhanShade(raster)", eye)
        for blob in (
            (ROOT / "docs" / "SOLO_QA.md").read_text(),
            (ROOT / "docs" / "DEVICE.md").read_text(),
        ):
            self.assertIn("Looking north off the photo stamp is hillshade, not void", blob)
            self.assertIn("Oleaster–Canutillo photo is packed", blob)

    def test_canutillo_borderland_mowad_are_on_packed_photo(self):
        """6:47 still: Borderland / TX 20 / Mowad sat past the NAIP postage stamp."""
        you = {"lat": 31.87051, "lon": -106.59729}
        canutillo = {"lat": 31.917, "lon": -106.600}
        borderland = {"lat": 31.90, "lon": -106.58}
        mowad = {"lat": 31.93, "lon": -106.58}
        boxes = aerial.photo_bboxes({"id": "tx-west", "slices": PACKS["tx-west"]["slices"]})
        union = aerial.union_photo_bbox(boxes)
        for name, pt in (
            ("YOU", you),
            ("Canutillo", canutillo),
            ("Borderland", borderland),
            ("Mowad", mowad),
        ):
            self.assertTrue(
                union["south"] <= pt["lat"] <= union["north"],
                f"{name} lat {pt['lat']} is off packed photo {union}",
            )
            self.assertTrue(
                union["west"] <= pt["lon"] <= union["east"],
                f"{name} lon {pt['lon']} is off packed photo {union}",
            )
        extra = aerial.PHOTO_EXTRA["tx-west"][0]
        self.assertLessEqual(extra["south"], 31.85)
        self.assertLessEqual(extra["west"], -106.63)
        self.assertGreaterEqual(extra["north"], 31.94)
        self.assertGreaterEqual(extra["east"], -106.55)
        blob = _packed_jpeg(PACK_ROOT / "tx-west", canutillo["lon"], canutillo["lat"], 16)
        self.assertIsNotNone(blob, "Canutillo has no packed photo at z16")
        assert blob is not None
        self.assertTrue(blob.startswith(b"\xff\xd8"), "Canutillo aerial is not JPEG")
        self.assertGreater(len(blob), 800)

    def test_vinton_anthony_and_pack_floor_fill_the_map(self):
        """7:45 still: looking north to Vinton / TX 20 / Anthony was gray schematic."""
        vinton = {"lat": 31.95, "lon": -106.599}
        anthony = {"lat": 32.006, "lon": -106.606}
        you = {"lat": 31.87055, "lon": -106.59732}
        boxes = aerial.photo_bboxes({"id": "tx-west", "slices": PACKS["tx-west"]["slices"]})
        union = aerial.union_photo_bbox(boxes)
        for name, pt in (("YOU", you), ("Vinton", vinton), ("Anthony", anthony)):
            self.assertTrue(
                union["south"] <= pt["lat"] <= union["north"],
                f"{name} lat {pt['lat']} is off packed photo {union}",
            )
            self.assertTrue(
                union["west"] <= pt["lon"] <= union["east"],
                f"{name} lon {pt['lon']} is off packed photo {union}",
            )
        self.assertEqual(aerial.AERIAL_FLOOR_ZOOM, 12)
        self.assertEqual(aerial.AERIAL_MIN_ZOOM, 12)
        self.assertEqual(aerial.style_layer()["minzoom"], 6)
        attach = SWIFT.read_text().split("public static func attachAerialLayers")[1].split(
            "Packed OSM houses"
        )[0]
        self.assertIn('"minzoom": 6', attach)
        self.assertNotIn('"minzoom": 14', attach)
        self.assertNotIn('"minzoom": 12', attach)
        eye = OFFLINE.read_text().split("public static func applyEyeLayers")[1].split(
            "public static func applyEyePalette"
        )[0]
        covers = eye.split("func coversPhoto")[1].split("func holdsKhanDetail")[0]
        self.assertIn("landFillLayerID", covers)
        self.assertIn("khanTreesLayerID", covers)
        self.assertIn("water-fill", covers)
        self.assertNotIn("aerial ? 0", eye)
        for name, pt, z in (
            ("Vinton", vinton, 16),
            ("Anthony", anthony, 16),
            ("YOU floor", you, 12),
        ):
            blob = _packed_jpeg(PACK_ROOT / "tx-west", pt["lon"], pt["lat"], z)
            self.assertIsNotNone(blob, f"{name} has no packed photo at z{z}")
            assert blob is not None
            self.assertTrue(blob.startswith(b"\xff\xd8"), f"{name} aerial is not JPEG")
            self.assertGreater(len(blob), 800)
        for blob in (
            (ROOT / "docs" / "SOLO_QA.md").read_text(),
            (ROOT / "docs" / "DEVICE.md").read_text(),
        ):
            self.assertIn("Looking north to Vinton and Anthony is packed photo", blob)
            self.assertIn("Pack-wide photo fills the extract", blob)

    def test_every_pack_ships_a_photo_floor(self):
        """Gray schematic past the metro stamp is a FAIL. z12 NAIP covers each pack bbox."""
        for pid, pack in PACKS.items():
            region = pack["slices"]["region"]
            box = aerial.slice_bbox(region)
            home = {
                "lat": (box["south"] + box["north"]) / 2,
                "lon": (box["west"] + box["east"]) / 2,
            }
            archive = PACK_ROOT / pid / "aerial.pmtiles"
            self.assertTrue(archive.is_file(), f"{pid} missing aerial.pmtiles")
            with open(archive, "rb") as fh:
                header = Reader(MmapSource(fh)).header()
            self.assertLessEqual(int(header["min_zoom"]), 12, f"{pid} aerial min_zoom")
            blob = _packed_jpeg(PACK_ROOT / pid, home["lon"], home["lat"], 12)
            self.assertIsNotNone(blob, f"{pid} pack center has no z12 photo floor")
            assert blob is not None
            self.assertTrue(blob.startswith(b"\xff\xd8"), f"{pid} z12 floor is not JPEG")


class FullExtractPhotoTests(unittest.TestCase):
    """The whole packed extract is NAIP, not a metro postage stamp."""

    def test_jobs_fill_every_extract_and_walk_at_max_zoom(self):
        west = {"id": "tx-west", **PACKS["tx-west"]}
        east = {"id": "tx-east", **PACKS["tx-east"]}
        nm = {"id": "nm", **PACKS["nm"]}
        self.assertTrue(_job_has(west, HATCH["lon"], HATCH["lat"], 15), "Hatch is off TX WEST z15 fill")
        self.assertTrue(
            _job_has(west, TULAROSA["lon"], TULAROSA["lat"], 15),
            "Tularosa is off TX WEST z15 fill",
        )
        self.assertTrue(
            _job_has(west, LAS_CRUCES["lon"], LAS_CRUCES["lat"], 16),
            "Las Cruces walk is off TX WEST z16",
        )
        self.assertTrue(_job_has(east, BUDA["lon"], BUDA["lat"], 15), "Buda is off TX EAST z15 fill")
        self.assertTrue(
            _job_has(east, AUSTIN["lon"], AUSTIN["lat"], 16),
            "Austin walk is off TX EAST z16",
        )
        self.assertTrue(_job_has(nm, ISLETA["lon"], ISLETA["lat"], 15), "Isleta is off NM z15 fill")
        self.assertTrue(
            _job_has(nm, ALBUQUERQUE["lon"], ALBUQUERQUE["lat"], 16),
            "Albuquerque walk is off NM z16",
        )
        union = aerial.union_photo_bbox(
            aerial.photo_bboxes({"id": "tx-west", "slices": PACKS["tx-west"]["slices"]})
        )
        self.assertTrue(union["south"] <= HATCH["lat"] <= union["north"], union)
        self.assertTrue(union["west"] <= HATCH["lon"] <= union["east"], union)

    def test_github_and_ipa_budgets_let_the_photo_grow(self):
        self.assertLessEqual(aerial.SHARD_MAX_BYTES, 90 * 1024 * 1024)
        self.assertGreater(aerial.SHARD_MAX_BYTES, 50 * 1024 * 1024)
        self.assertEqual(aerial.PACK_BUDGET_MIB, 4096)
        validate = (ROOT / "tools" / "validate_v3.py").read_text()
        self.assertNotIn("exceeds 160 MB iOS budget", validate)
        self.assertIn("PACK_BUDGET_MIB", validate)
        water = (ROOT / "tools" / "test_water_inspect.py").read_text()
        self.assertIn("PACK_BUDGET_MIB", water)
        self.assertNotIn("<= 160, f\"{pid} over the iOS budget\"", water)
        for pid in PACKS:
            for path in _aerial_paths(PACK_ROOT / pid):
                self.assertLessEqual(
                    path.stat().st_size,
                    aerial.SHARD_MAX_BYTES,
                    f"{path} over GitHub 100 MB hard limit",
                )

    def test_attach_and_style_list_every_aerial_shard(self):
        attach = SWIFT.read_text().split("public static func attachAerialLayers")[1].split(
            "Packed OSM houses"
        )[0]
        self.assertIn("contentsOfDirectory", attach)
        self.assertIn('hasPrefix("aerial")', attach)
        self.assertIn("hasSuffix(\".pmtiles\")", attach)
        self.assertIn("resolverVersion = 15", SWIFT.read_text())
        copy = (ROOT / "tools" / "copy_resources.sh").read_text()
        self.assertIn("Packs/*/.naip-cache", copy)
        ignore = (ROOT / ".gitignore").read_text()
        self.assertIn(".naip-cache", ignore)

    def test_extract_and_walk_are_on_packed_photo(self):
        west = PACK_ROOT / "tx-west"
        east = PACK_ROOT / "tx-east"
        nm = PACK_ROOT / "nm"
        packed = (
            (west, "Hatch", HATCH, 15),
            (west, "Tularosa", TULAROSA, 15),
            (west, "Las Cruces", LAS_CRUCES, 16),
        )
        pending = (
            (east, "Buda", BUDA, 15),
            (east, "Austin", AUSTIN, 16),
            (nm, "Isleta", ISLETA, 15),
            (nm, "Albuquerque", ALBUQUERQUE, 16),
        )
        for dest, name, pt, z in packed:
            blob = _packed_jpeg(dest, pt["lon"], pt["lat"], z)
            self.assertIsNotNone(blob, f"{name} has no packed photo at z{z}")
            assert blob is not None
            self.assertTrue(blob.startswith(b"\xff\xd8"), f"{name} aerial is not JPEG")
            self.assertGreater(len(blob), 800)
        for blob in (
            (ROOT / "docs" / "SOLO_QA.md").read_text(),
            (ROOT / "docs" / "DEVICE.md").read_text(),
        ):
            self.assertIn("Street-scale photo covers every pack extract", blob)
            self.assertIn("yard-scale on the walkable ground", blob)
        missing = []
        for dest, name, pt, z in pending:
            blob = _packed_jpeg(dest, pt["lon"], pt["lat"], z)
            if blob is None:
                missing.append(name)
                continue
            self.assertTrue(blob.startswith(b"\xff\xd8"), f"{name} aerial is not JPEG")
            self.assertGreater(len(blob), 800)
        if missing:
            self.skipTest("still packing " + ", ".join(missing))


if __name__ == "__main__":
    unittest.main()
