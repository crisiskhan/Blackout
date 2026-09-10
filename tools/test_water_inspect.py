#!/usr/bin/env python3
"""Hold-to-inspect: the shipped water, the zoom gates, and the two tables that
have to agree about what a byte on the wire means.

The water layers are derived from `osm.geojson`, which is in the tree, so the
first thing checked here is that regenerating them reproduces the shipped bytes
exactly. That is what makes the data reviewable rather than something that
merely appeared in a commit.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from v3 import water
from v3.fetch_packs import PACKS

PACK_ROOT = ROOT / "Resources" / "Packs"
SWIFT = ROOT / "Packages/MapLibreMap/Sources/MapLibreMap/WaterInspect.swift"
GESTURE_SWIFT = ROOT / "Packages/MapLibreMap/Sources/MapLibreMap/InspectGesture.swift"
MAP_SWIFT = ROOT / "Packages/MapLibreMap/Sources/MapLibreMap/MapLibreMap.swift"
OFFLINE_SWIFT = ROOT / "Packages/MapLibreMap/Sources/MapLibreMap/OfflineMapView.swift"
TOKENS_SWIFT = ROOT / "Packages/Tokens/Sources/Tokens/Tokens.swift"
MAP_TAB = ROOT / "Blackout/MapTab.swift"
CARD = ROOT / "Blackout/HoldCard.swift"
INSPECT = ROOT / "Packages/MapLibreMap/Sources/MapLibreMap/Inspect.swift"
FIELD_TAB = ROOT / "Blackout/FieldTab.swift"


def style_of(pack_id: str) -> dict:
    return json.loads((PACK_ROOT / pack_id / "style.json").read_text())


def layer(style: dict, layer_id: str) -> dict | None:
    for entry in style.get("layers") or []:
        if entry.get("id") == layer_id:
            return entry
    return None


class ShippedWaterLayers(unittest.TestCase):
    def test_every_pack_ships_both_water_files(self):
        for pid in PACKS:
            for name in ("water.geojson", "water.bin"):
                path = PACK_ROOT / pid / "layers" / name
                self.assertTrue(path.is_file(), f"{pid} is missing layers/{name}")
                self.assertGreater(path.stat().st_size, 1024, f"{pid} layers/{name} is empty")

    def test_the_manifest_counts_the_water_it_ships(self):
        for pid in PACKS:
            manifest = json.loads((PACK_ROOT / pid / "manifest.json").read_text())
            files = set(manifest["files"])
            self.assertIn("layers/water.geojson", files, pid)
            self.assertIn("layers/water.bin", files, pid)
            on_disk = sum(
                (PACK_ROOT / pid / rel).stat().st_size
                for rel in manifest["files"]
                if (PACK_ROOT / pid / rel).is_file()
            )
            self.assertEqual(manifest["bytes"], on_disk, f"{pid} manifest bytes disagree with disk")
            self.assertLessEqual(manifest["bytes"] / (1024 * 1024), 160, f"{pid} over the iOS budget")

    def test_the_catalog_agrees_with_the_manifests(self):
        catalog = json.loads((PACK_ROOT / "catalog.json").read_text())
        by_id = {p["id"]: p for p in catalog["packs"]}
        for pid in PACKS:
            manifest = json.loads((PACK_ROOT / pid / "manifest.json").read_text())
            self.assertEqual(by_id[pid]["bytes"], manifest["bytes"], pid)

    def test_regenerating_from_the_shipped_osm_reproduces_the_shipped_bytes(self):
        # No network, no hidden input: the extract in the tree is the whole
        # source, so a reviewer can run the tool and diff nothing.
        for pid in PACKS:
            dest = PACK_ROOT / pid
            fc = json.loads((dest / "osm.geojson").read_text())
            recs = water.records(fc)
            drawn = json.dumps(water.render_layer(recs), separators=(",", ":"), ensure_ascii=False)
            self.assertEqual(
                drawn,
                (dest / "layers" / "water.geojson").read_text(),
                f"{pid} water.geojson is not what the tool produces",
            )
            self.assertEqual(
                water.index_bytes(recs),
                (dest / "layers" / "water.bin").read_bytes(),
                f"{pid} water.bin is not what the tool produces",
            )

    def test_the_drawn_layer_only_carries_what_the_close_zoom_draws(self):
        for pid in PACKS:
            fc = json.loads((PACK_ROOT / pid / "layers" / "water.geojson").read_text())
            self.assertEqual(fc.get("attribution"), water.OSM_CREDIT, pid)
            for feature in fc["features"]:
                self.assertEqual(feature["geometry"]["type"], "Point", pid)
                props = feature["properties"]
                self.assertIn(props["class"], water.DETAIL_CLASSES, f"{pid} draws {props['class']}")
                self.assertIn(props["via"], water.VIA_VALUES, pid)

    def test_the_index_carries_the_creeks_the_drawn_layer_leaves_out(self):
        # A press on a stream has to be answerable, or "no water here" is a lie.
        recs = water.read_index((PACK_ROOT / "tx-west" / "layers" / "water.bin").read_bytes())
        kinds = {r["class"] for r in recs}
        self.assertIn("stream", kinds)
        self.assertIn("water", kinds)
        self.assertTrue(kinds.issuperset({"canal", "drain", "ditch", "tank", "acequia", "tap"}))
        for r in recs:
            self.assertIn(r["class"], water.CLASSES)
            self.assertIn(r["via"], water.VIA_VALUES)
            self.assertIn(r["tag"], water.TAGS)
            self.assertTrue(0 < len(r["points"]) <= water.SAMPLE_CAP)

    def test_new_mexico_keeps_its_acequias_and_texas_its_tanks(self):
        nm = water.class_counts(water.read_index((PACK_ROOT / "nm" / "layers" / "water.bin").read_bytes()))
        tx = water.class_counts(water.read_index((PACK_ROOT / "tx-west" / "layers" / "water.bin").read_bytes()))
        self.assertGreaterEqual(nm.get("acequia", 0), 200)
        self.assertGreaterEqual(tx.get("tank", 0), 200)
        self.assertGreaterEqual(tx.get("canal", 0), 1000)
        self.assertGreaterEqual(tx.get("drain", 0), 3000)


class Classification(unittest.TestCase):
    """The names in this extract lie, and the classifier has to know which."""

    def test_a_line_named_for_a_playa_is_the_lateral_that_drains_one(self):
        # Eighty-two tx-west features say "playa" and every one is a channel.
        for tag, name, want in [
            ("drain", "Playa Lateral", "drain"),
            ("canal", "Playa Drain Canal", "canal"),
            ("drain", "Playa Lateral No 2", "drain"),
        ]:
            self.assertEqual(water.classify({"waterway": tag, "name": name}, "LineString")[0], want)

    def test_a_creek_with_spring_in_its_name_is_a_creek(self):
        for tag, name, want in [
            ("stream", "Mule Springs Creek", "stream"),
            ("stream", "Indian Springs Canyon", "stream"),
            ("river", "Short Spring Branch", "river"),
            ("stream", "Arroyo del Ojo del Orro", "stream"),
            ("stream", "Cañon la Tinaja", "stream"),
        ]:
            self.assertEqual(water.classify({"waterway": tag, "name": name}, "LineString")[0], want)

    def test_the_one_name_allowed_to_rename_a_channel_is_the_channels_own(self):
        for tag in ("ditch", "canal", "drain", "stream"):
            got = water.classify({"waterway": tag, "name": "Acequia Madre"}, "LineString")
            self.assertEqual(got[0], "acequia")
            self.assertEqual(got[1], water.VIA_NAMED)
            self.assertEqual(got[2], f"waterway={tag}")

    def test_standing_water_takes_the_name_the_country_gives_it(self):
        cases = [
            ("Fivemile Tank", "tank"),
            ("Spring Tank", "tank"),
            ("Hueco Tanks", "tinaja"),
            ("Laguna El Barreal", "playa"),
            ("Courtyard Spring", "spring"),
            (None, "water"),
        ]
        for name, want in cases:
            props = {"natural": "water"}
            if name:
                props["name"] = name
            self.assertEqual(water.classify(props, "Polygon")[0], want, name)

    def test_a_tag_that_names_the_class_outright_needs_no_name(self):
        self.assertEqual(water.classify({"natural": "spring"}, "Point"), ("spring", "tagged", "natural=spring"))
        self.assertEqual(
            water.classify({"amenity": "drinking_water"}, "Point"),
            ("tap", "tagged", "amenity=drinking_water"),
        )
        self.assertEqual(
            water.classify({"landuse": "reservoir"}, "Polygon"),
            ("reservoir", "tagged", "landuse=reservoir"),
        )

    def test_a_street_is_never_water_however_it_is_named(self):
        for name in ("Acequia Rd", "Spring St", "Tank Farm Road", "Playa Vista Dr"):
            self.assertIsNone(water.classify({"highway": "residential", "name": name}, "LineString"), name)

    def test_the_index_round_trips_what_the_classifier_decided(self):
        recs = [
            {"class": "acequia", "via": "named", "tag": "waterway=ditch", "name": "Acequia Madre",
             "points": [(35.1, -106.65), (35.101, -106.651)]},
            {"class": "water", "via": "generic", "tag": "natural=water", "name": "",
             "points": [(31.1, -105.3)]},
        ]
        self.assertEqual(water.read_index(water.index_bytes(recs)), [
            {**recs[0], "points": [(35.1, -106.65), (35.101, -106.651)]},
            {**recs[1], "points": [(31.1, -105.3)]},
        ])


class ZoomGates(unittest.TestCase):
    def test_far_out_the_water_is_fill_and_nothing_else(self):
        for pid in PACKS:
            style = style_of(pid)
            fill = layer(style, "water-fill")
            self.assertIsNotNone(fill, pid)
            self.assertEqual(fill["type"], "fill")
            self.assertLessEqual(fill.get("minzoom", 0), water.FILL_MIN_ZOOM, pid)

    def test_the_lines_wait_for_the_zoom_the_tiles_carry_them_at(self):
        for pid in PACKS:
            line = layer(style_of(pid), "water")
            self.assertIsNotNone(line, pid)
            self.assertEqual(line["type"], "line")
        swift = MAP_SWIFT.read_text()
        self.assertIn("attachWaterLayers", swift)
        self.assertIn("WaterZoom.lineMinZoom", swift)

    def test_the_class_marks_and_then_their_names_come_in_close(self):
        swift = MAP_SWIFT.read_text()
        self.assertIn("waterDetailPointsLayerID", swift)
        self.assertIn("waterDetailLabelsLayerID", swift)
        self.assertIn("WaterZoom.detailMinZoom", swift)
        self.assertIn("WaterZoom.labelMinZoom", swift)
        self.assertGreater(water.LABEL_MIN_ZOOM, water.DETAIL_MIN_ZOOM)

    def test_the_marks_read_the_shipped_file_and_nothing_remote(self):
        swift = MAP_SWIFT.read_text()
        self.assertIn("layers/water.geojson", swift)
        self.assertIn("waterDetailSourceID", swift)
        self.assertNotIn("http://", swift)
        self.assertNotIn("https://", swift)

    def test_the_marks_are_a_dot_and_a_word_rather_than_an_icon(self):
        compact = MAP_SWIFT.read_text().replace(" ", "").replace("\n", "")
        self.assertIn('"type":"circle"', compact)
        self.assertIn('"circle-radius"', compact)
        self.assertIn("waterInk", MAP_SWIFT.read_text())
        self.assertIn("Open Sans Regular", MAP_SWIFT.read_text())

    def test_the_water_work_left_the_streets_where_they_were(self):
        for pid in PACKS:
            style = style_of(pid)
            labels = layer(style, "road-labels")
            self.assertLessEqual(labels.get("minzoom", 99), 12, pid)
            self.assertEqual(style["sources"]["osm"]["url"], "pmtiles://osm.pmtiles", pid)
            self.assertEqual(style["glyphs"], "glyphs/{fontstack}/{range}.pbf", pid)
            vector = {k for k, v in style["sources"].items() if v.get("type") == "vector"}
            for entry in style["layers"]:
                if entry.get("source") in vector:
                    self.assertTrue(entry.get("source-layer"), f"{pid} {entry['id']} draws nothing")
            self.assertEqual(style["metadata"]["network"], "deny-all", pid)


class TablesThatMustAgree(unittest.TestCase):
    """One table on the wire, two readers. A drift renames every record."""

    def setUp(self):
        self.swift = SWIFT.read_text()

    def test_the_class_codes_are_the_same_on_both_sides(self):
        block = self.swift.split("public enum WaterClass")[1].split("\n\n")[0]
        cases = re.findall(r"case (\w+) = (\d+)", block)
        self.assertEqual([name for name, _ in cases], list(water.CLASSES))
        self.assertEqual([int(code) for _, code in cases], list(range(len(water.CLASSES))))

    def test_the_evidence_codes_are_the_same_on_both_sides(self):
        block = self.swift.split("public enum WaterEvidence")[1].split("}")[0]
        cases = re.findall(r"case (\w+) = (\d+)", block)
        self.assertEqual([name for name, _ in cases], list(water.VIA_VALUES))

    def test_the_tag_table_is_the_same_on_both_sides(self):
        block = self.swift.split("public static let wire: [String] = [")[1].split("]")[0]
        self.assertEqual(re.findall(r'"([^"]+)"', block), list(water.TAGS))

    def test_the_close_zoom_draws_the_same_seven_classes_on_both_sides(self):
        block = self.swift.split("public var isDetail: Bool")[1].split("return true")[0]
        cases = re.findall(r"\.(\w+)", block)
        self.assertEqual(set(cases), set(water.DETAIL_CLASSES))

    def test_the_zoom_gates_are_the_same_on_both_sides(self):
        for name, value in [
            ("fillMinZoom", water.FILL_MIN_ZOOM),
            ("lineMinZoom", water.LINE_MIN_ZOOM),
            ("detailMinZoom", water.DETAIL_MIN_ZOOM),
            ("labelMinZoom", water.LABEL_MIN_ZOOM),
        ]:
            found = re.search(rf"let {name}: Double = (\d+)", self.swift)
            self.assertIsNotNone(found, name)
            self.assertEqual(int(found.group(1)), value, name)

    def test_the_wire_header_is_the_same_on_both_sides(self):
        self.assertIn('Array("BLKTWTR".utf8) + [1]', self.swift)
        self.assertEqual(water.MAGIC, b"BLKTWTR\x01")
        self.assertEqual(
            int(re.search(r"static let version: UInt32 = (\d+)", self.swift).group(1)),
            water.VERSION,
        )
        self.assertEqual(
            int(re.search(r"static let header = (\d+)", self.swift).group(1)),
            water.HEADER.size,
        )
        self.assertEqual(
            int(re.search(r"static let recordStride = (\d+)", self.swift).group(1)),
            water.RECORD.size,
        )


class HoldToInspect(unittest.TestCase):
    def test_a_press_is_a_press_and_a_drag_is_a_pan(self):
        inspect = INSPECT.read_text()
        seconds = float(re.search(r"holdSeconds = ([\d.]+)", inspect).group(1))
        slop = float(re.search(r"holdDriftPoints = ([\d.]+)", inspect).group(1))
        self.assertTrue(0.3 < seconds < 0.8, seconds)
        self.assertTrue(0 < slop <= 16, slop)
        offline = OFFLINE_SWIFT.read_text()
        self.assertIn("hold.minimumPressDuration = Inspect.holdSeconds", offline)
        self.assertIn("hold.allowableMovement = CGFloat(Inspect.holdDriftPoints)", offline)
        self.assertIn("guard interactive, gesture.state == .began", offline)

    def test_the_press_swallows_the_tap_that_ends_the_same_touch(self):
        offline = OFFLINE_SWIFT.read_text()
        self.assertIn("tap.require(toFail: hold)", offline)

    def test_the_card_is_half_the_glass_at_most(self):
        tokens = TOKENS_SWIFT.read_text()
        self.assertIn("holdCardMaxHeightFraction: Double = 0.5", tokens)
        self.assertIn("liftIntoView", OFFLINE_SWIFT.read_text())

    def test_the_card_does_not_put_the_disclaimer_on_the_glass(self):
        swift = SWIFT.read_text()
        said = re.search(r'disclaimer =\s*"([^"]+)"', swift).group(1).lower()
        self.assertIn("record", said)
        self.assertNotIn("WaterSure.disclaimer", CARD.read_text())

    def test_the_card_carries_class_sure_why_do_field_and_mark(self):
        card = CARD.read_text()
        self.assertIn("held.card.title", card)
        self.assertIn('key: "SURE"', card)
        self.assertIn('key: "DO"', card)
        self.assertIn("FIELD · WATER", card)
        self.assertIn('"FIELD"', card)
        self.assertIn("MARKED", card)
        self.assertIn("onField", card)
        self.assertIn("onMark", card)

    def test_a_press_opens_the_matching_field_stepper(self):
        inspect = INSPECT.read_text()
        self.assertIn('waterCard = "water-disinfect"', inspect)
        self.assertIn('lostCard = "nav-lost"', inspect)
        book = json.loads((ROOT / "Resources/Field/field.core.json").read_text())
        ids = {card["id"] for card in book["cards"]}
        self.assertIn("nav-lost", ids)
        self.assertIn("water-disinfect", ids)
        field = FIELD_TAB.read_text()
        self.assertIn("runtime.fieldJump", field)
        self.assertIn("StepperState(card: card, index: 0", field)

    def test_sos_stays_on_comms(self):
        tokens = TOKENS_SWIFT.read_text()
        block = tokens.split("func sosFAB")[1].split("public enum Color")[0]
        self.assertIn("case .comms:", block)
        self.assertIn("return true", block)
        self.assertIn("case .map, .field, .expedition:", block)
        self.assertIn("return false", block)
        self.assertNotIn("SOSHold(", MAP_TAB.read_text())
        self.assertNotIn("SOSHold(", CARD.read_text())

    def test_the_press_reads_the_pack_on_disk_and_nothing_else(self):
        for path in (SWIFT, INSPECT, CARD, MAP_TAB):
            text = path.read_text()
            for banned in ("URLSession", "http://", "https://", "MapKit", "CoreML"):
                self.assertNotIn(banned, text, f"{path.name} reaches for {banned}")

    def test_the_index_is_mapped_rather_than_read_whole(self):
        self.assertIn("options: .mappedIfSafe", SWIFT.read_text())

    def test_the_map_still_draws_what_it_already_proved(self):
        offline = OFFLINE_SWIFT.read_text()
        self.assertIn("red: 0.12, green: 0.82, blue: 0.94", offline)
        self.assertIn("UserPuck.title", offline)
        self.assertIn("DestinationPin.sourceID", offline)
        self.assertIn('public static let line = "© OpenStreetMap contributors"', MAP_SWIFT.read_text())
        self.assertIn("OSMCredit.line", MAP_TAB.read_text())
        self.assertIn("func resolve(", INSPECT.read_text() + SWIFT.read_text())
        self.assertIn("WaterIndex", (ROOT / "Blackout/AppRuntime.swift").read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
