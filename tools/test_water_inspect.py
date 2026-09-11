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

from v3 import ground, water
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

    def test_every_pack_ships_the_glasshouse_overlay(self):
        expected = {"tx-west": (2, 0, 0), "tx-east": (14, 2, 2), "nm": (10, 1, 2)}
        for pid in PACKS:
            path = PACK_ROOT / pid / "layers" / "ground.geojson"
            self.assertTrue(path.is_file(), f"{pid} is missing layers/ground.geojson")
            fc = json.loads(path.read_text())
            self.assertGreater(len(fc.get("features") or []), 0, f"{pid} ground overlay is empty")
            blob = path.read_text().lower()
            self.assertNotIn("edible", blob, pid)
            self.assertNotIn("animal-icon", blob, pid)
            self.assertNotIn("bee cave", blob, pid)
            self.assertNotIn("wildlife drive", blob, pid)
            self.assertNotIn("wildlife trail", blob, pid)
            glass = 0
            caves = 0
            wildlife = 0
            for feat in fc["features"]:
                props = feat.get("properties") or {}
                self.assertIn(feat.get("geometry", {}).get("type"), ("Polygon", "MultiPolygon"))
                name = (props.get("name") or "").lower()
                kind = ground.overlay_kind(props)
                self.assertIsNotNone(kind, f"{pid} overlay feature is not glasshouse, cave, or wildlife: {props}")
                self.assertNotIn("bee cave", name)
                if kind == "glasshouse":
                    glass += 1
                elif kind == "cave":
                    caves += 1
                else:
                    self.assertEqual(kind, "wildlife", kind)
                    wildlife += 1
            self.assertEqual((glass, caves, wildlife), expected[pid], pid)
        nm_blob = (PACK_ROOT / "nm" / "layers" / "ground.geojson").read_text().lower()
        self.assertIn("marquez wildlife management area", nm_blob)
        self.assertIn("whitfield wildlife conservation area", nm_blob)
        east_blob = (PACK_ROOT / "tx-east" / "layers" / "ground.geojson").read_text().lower()
        self.assertIn("colorado river park wildlife sanctuary", east_blob)
        self.assertIn("indiangrass wildlife sanctuary", east_blob)

    def test_the_overlay_and_the_card_use_the_same_cave_preserve_phrases(self):
        inspect = INSPECT.read_text()
        for phrase in ground.CAVE_PRESERVE_PHRASES:
            self.assertIn(f'"{phrase}"', inspect)
            self.assertIn(f'"{phrase}"', (ROOT / "tools/v3/ground.py").read_text())
        self.assertNotIn('contains("cave")', inspect)
        for phrase in ground.WILDLIFE_RANGE_PHRASES:
            self.assertIn(f'"{phrase}"', inspect)
            self.assertIn(f'"{phrase}"', (ROOT / "tools/v3/ground.py").read_text())
        self.assertNotIn('contains("wildlife")', inspect)
        self.assertIn("isWildlifeRange", inspect)
        self.assertIn("Wildlife range", inspect)

    def test_the_manifest_counts_the_ground_it_ships(self):
        for pid in PACKS:
            manifest = json.loads((PACK_ROOT / pid / "manifest.json").read_text())
            self.assertIn("layers/ground.geojson", manifest["files"], pid)

    def test_regenerating_ground_from_the_shipped_osm_reproduces_the_shipped_bytes(self):
        for pid in PACKS:
            dest = PACK_ROOT / pid
            fc = json.loads((dest / "osm.geojson").read_text())
            drawn = json.dumps(ground.render_layer(ground.records(fc)), separators=(",", ":"), ensure_ascii=False)
            self.assertEqual(
                drawn,
                (dest / "layers" / "ground.geojson").read_text(),
                f"{pid} ground.geojson is not what the tool produces",
            )

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

    def test_the_class_marks_come_in_close_without_printing_class(self):
        swift = MAP_SWIFT.read_text()
        self.assertIn("waterDetailPointsLayerID", swift)
        self.assertIn("waterDetailLabelsLayerID", swift)
        self.assertIn("WaterZoom.detailMinZoom", swift)
        self.assertIn("let labelMinZoom: Double = 15", SWIFT.read_text())
        self.assertIn(
            'layers.removeAll { $0["id"] as? String == waterDetailLabelsLayerID }',
            swift,
        )
        self.assertNotIn('["coalesce", ["get", "name"], ["get", "class"]]', swift)
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
        self.assertIn('key: "BOOK"', card)
        self.assertIn("InspectField.label", card)
        self.assertIn("held.card.fieldRoute", card)
        self.assertIn("MARKED", card)
        self.assertIn("onField", card)
        self.assertIn("onMark", card)
        self.assertNotIn("animal-icon", card)
        self.assertNotIn("edible", card.lower())

    def test_a_press_opens_the_matching_field_stepper(self):
        inspect = INSPECT.read_text()
        self.assertIn('waterCard = "water-disinfect"', inspect)
        self.assertIn('lostCard = "nav-lost"', inspect)
        self.assertIn('plantUseCard = "plant-use"', inspect)
        self.assertIn('caveCard = "cave-dark"', inspect)
        self.assertIn('snakeTXCard = "tx-snake"', inspect)
        book = json.loads((ROOT / "Resources/Field/field.core.json").read_text())
        ids = {card["id"] for card in book["cards"]}
        self.assertIn("nav-lost", ids)
        self.assertIn("water-disinfect", ids)
        self.assertIn("plant-use", ids)
        self.assertIn("cave-dark", ids)
        self.assertIn("food-game", ids)
        self.assertIn("animal-bite", ids)
        field = FIELD_TAB.read_text()
        self.assertIn("runtime.fieldJump", field)
        self.assertIn("InspectField.presentRoute", field)
        self.assertIn("fieldTrail", field)
        self.assertIn("advanceTrail", field)
        self.assertIn("InspectField.nextAction", field)
        self.assertIn("StepperState(card: card, index: 0", field)

    def test_sos_stays_on_comms(self):
        tokens = TOKENS_SWIFT.read_text()
        block = tokens.split("func sosFAB")[1].split("public enum Color")[0]
        self.assertIn("case .comms:", block)
        self.assertIn("return true", block)
        self.assertIn("case .map:", block)
        self.assertIn("return arranging", block)
        self.assertIn("case .field, .expedition:", block)
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
        self.assertIn("red: 0.77, green: 0.80, blue: 0.84", offline)
        self.assertNotIn("red: 0.12, green: 0.82, blue: 0.94", offline)
        self.assertIn("UserPuck.title", offline)
        self.assertIn("DestinationPin.sourceID", offline)
        self.assertIn('public static let line = "© OpenStreetMap contributors"', MAP_SWIFT.read_text())
        self.assertIn("OSMCredit.line", MAP_TAB.read_text())
        self.assertIn("func resolve(", INSPECT.read_text() + SWIFT.read_text())
        self.assertIn("WaterIndex", (ROOT / "Blackout/AppRuntime.swift").read_text())
        self.assertIn("enum MarkLabel", MAP_SWIFT.read_text())
        self.assertIn("MarkLabel.relabel", (ROOT / "Blackout/AppRuntime.swift").read_text())


class GroundFieldSync(unittest.TestCase):
    """Hold names the biome; FIELD opens that pack's plant, bite, cave cards.

    The map must not invent wildlife GPS. Range is the Field book of the
    open pack. Marks are silver circles on records the extract actually has.
    """

    def test_the_button_names_the_procedure_from_the_route(self):
        field = SWIFT.read_text()
        self.assertIn('case .water: return "FIELD · WATER"', field)
        self.assertIn('case .animal: return "FIELD · ANIMAL"', field)
        self.assertIn('case .plant: return "FIELD · PLANT"', field)
        self.assertIn('case .bite: return "FIELD · BITE"', field)
        self.assertIn('case .cave: return "FIELD · CAVE"', field)
        self.assertIn('case .lost: return "FIELD · LOST"', field)
        hold = CARD.read_text()
        self.assertIn("InspectField.label(for:", hold)
        self.assertIn("InspectField.presentRoute", hold)
        self.assertIn("InspectField.bookLine", hold)
        self.assertIn('key: "BOOK"', hold)
        self.assertNotIn("held.card.fieldRoute.first", hold)
        self.assertNotIn("held.card.kind == .water", hold)
        app = (ROOT / "Blackout/AppRuntime.swift").read_text()
        self.assertIn("import FieldCorpus", app)
        self.assertIn("fieldBookIDs", app)
        self.assertIn("loadFieldBookIDs", app)
        field = SWIFT.read_text()
        self.assertIn("func bookLine(for", field)
        self.assertIn("func bookWord(for", field)
        tab = FIELD_TAB.read_text()
        self.assertIn("fieldTrailBook", tab)
        self.assertIn("InspectField.bookLine", tab)

    def test_woodland_and_scrub_ask_for_the_state_books(self):
        inspect = INSPECT.read_text()
        self.assertIn("plantTXCard, plantNMCard", inspect)
        self.assertIn("snakeTXCard, snakeNMCard", inspect)
        self.assertIn("cactusTXCard, cactusNMCard", inspect)
        self.assertIn("gameTXCard, gameNMCard", inspect)
        self.assertIn("treeUseTXCard, treeUseNMCard", inspect)
        self.assertIn("mammalTXCard, mammalNMCard", inspect)
        self.assertIn('treeUseEastCard = "tx-east-tree-use"', inspect)
        self.assertIn('mammalEastCard = "tx-east-mammal"', inspect)
        self.assertIn('gameEastCard = "tx-east-game"', inspect)
        self.assertIn('snakeEastCard = "tx-east-snake"', inspect)
        self.assertIn("extra: [plantUseCard", inspect)
        self.assertIn("extra: [biteCard", inspect)
        self.assertIn('plantUseCard = "plant-use"', inspect)
        self.assertIn('caveCard = "cave-dark"', inspect)
        self.assertIn("packGroundPointNaturals", inspect)
        self.assertIn('"place"', inspect)
        cover = inspect.split("private static func plantCover", 1)[1].split(
            "private static func snakeCountry", 1
        )[0]
        self.assertLess(
            cover.index("treeUseTXCard"),
            cover.index("plantTXCard"),
            "woodland must open this pack's tree-use card, not oleander, first",
        )
        tree = inspect.split('case "tree":', 1)[1].split('case "wood":', 1)[0]
        self.assertIn("treeUseTXCard", tree)
        self.assertNotIn("mammalTXCard", tree)
        hole = inspect.split('case "cave", "cave_entrance", "sinkhole":', 1)[1].split(
            'case "tree":', 1
        )[0]
        self.assertIn('caveCard', hole)
        self.assertIn('coldCard', hole)
        self.assertIn('case "grassland", "grass":', inspect)
        self.assertIn("isCavePreserve", inspect)
        self.assertIn("cave preserve", inspect)
        self.assertIn("cave area of critical", inspect)
        self.assertIn("isWildlifeRange", inspect)
        self.assertIn("wildlife refuge", inspect)
        self.assertIn("wildlife management area", inspect)
        self.assertIn("national wildlife", inspect)
        self.assertIn("wildlife sanctuary", inspect)
        self.assertIn("wildlife conservation area", inspect)
        land = inspect.split("private static func land(", 1)[1]
        self.assertLess(
            land.index("isWildlifeRange"),
            land.index('case "wood":'),
            "a wildlife sanctuary tagged as wood must still be range, not picnic woodland",
        )
        do = SWIFT.read_text()
        self.assertIn("Javelina and coyote range", do)
        self.assertIn("coyote and deer range", do)
        self.assertIn("black bear range", do)
        self.assertIn("Copperhead and cottonmouth country", do)
        self.assertIn("Cottonmouth country", do)
        self.assertIn("loblolly pine", do)
        self.assertIn("Hog country", do)
        self.assertIn("Pretty is not food", do)
        self.assertIn("This is range, not a pin", do)
        self.assertIn("tx-east", do)
        self.assertNotIn("ice and cold cards", do)

    def test_ground_marks_are_circles_without_class_labels_or_animals(self):
        swift = MAP_SWIFT.read_text()
        self.assertIn("attachGroundLayers", swift)
        self.assertIn("groundPointsLayerID", swift)
        self.assertIn("groundLabelsLayerID", swift)
        self.assertIn(
            'layers.removeAll { $0["id"] as? String == groundLabelsLayerID }',
            swift,
        )
        self.assertIn("packGroundPointNaturals", INSPECT.read_text())
        self.assertNotIn("animal-icon", swift.lower())
        self.assertNotIn("wildlife-icon", swift.lower())
        self.assertNotIn("edible", swift.lower())
        inspect = INSPECT.read_text()
        overlay = inspect.split("overlayLayerIDs", 1)[1].split("waterCard", 1)[0]
        self.assertNotIn("groundPointsLayerID", overlay)
        self.assertNotIn("groundLabelsLayerID", overlay)
        self.assertNotIn("groundWorkedFillLayerID", overlay)
        self.assertNotIn("groundWorkedLineLayerID", overlay)
        pick = inspect.split("public static func pick", 1)[1].split("packSourceID", 1)[0]
        self.assertIn("isCavePreserve", pick)
        self.assertIn("isWildlifeRange", pick)
        self.assertIn("greenhouse_horticulture", pick)

    def test_glasshouses_are_worked_ground_not_a_meal(self):
        inspect = INSPECT.read_text()
        self.assertIn('case "greenhouse_horticulture":', inspect)
        self.assertIn("mapped as glasshouses", inspect)
        self.assertIn('klass: "Glasshouse"', inspect)
        self.assertIn("workedCover", inspect)
        self.assertNotIn("mammalEastCard", inspect.split("private static func workedCover", 1)[1].split("private static func wildlifeRange", 1)[0])
        tiles = (ROOT / "tools/v3/tiles.py").read_text()
        self.assertIn('("landuse", "greenhouse_horticulture"): "farm"', tiles)
        swift = MAP_SWIFT.read_text()
        self.assertIn("layers/ground.geojson", swift)
        self.assertIn("groundWorkedFillLayerID", swift)
        self.assertIn("groundWorkedLineLayerID", swift)
        self.assertNotIn("edible", swift.lower())
        self.assertIn("resolverVersion = 6", swift)

    def test_the_next_fetch_asks_for_caves_and_trees(self):
        fetch = (ROOT / "tools/v3/fetch_packs.py").read_text()
        self.assertIn("sinkhole|cave|cave_entrance|tree", fetch)
        self.assertIn('node["natural"="cave"]', fetch)
        self.assertIn('node["natural"="tree"]', fetch)

    def test_the_core_book_ships_the_biome_cards(self):
        book = json.loads((ROOT / "Resources/Field/field.core.json").read_text())
        ids = {card["id"] for card in book["cards"]}
        for cid in ("plant-use", "cave-dark", "food-game", "plant-unknown", "animal-bite", "fungi-leave"):
            self.assertIn(cid, ids, cid)
        by_id = {card["id"]: card for card in book["cards"]}
        for cid in ("plant-use", "cave-dark", "food-game"):
            blob = json.dumps(by_id[cid]).lower()
            self.assertNotIn("edible", blob, cid)
            self.assertNotIn("safe to eat", blob, cid)

    def test_solo_qa_scores_the_biome_handoff(self):
        qa = (ROOT / "docs/SOLO_QA.md").read_text()
        self.assertIn("FIELD · PLANT", qa)
        self.assertIn("FIELD · BITE", qa)
        self.assertIn("FIELD · CAVE", qa)
        self.assertIn("NEXT · PLANT", qa)
        self.assertIn("NEXT · BITE", qa)
        self.assertIn("No animal icon", qa)
        self.assertIn("Never edible", qa)
        self.assertIn("NEXT · ANIMAL", qa)
        self.assertIn("CARD 1 OF", qa)
        self.assertIn("BOOK", qa)
        self.assertIn("PLANT · ANIMAL · FOOD · BITE · SHELTER · FUNGI", qa)
        self.assertIn("tree-use card", qa)
        self.assertIn("FIELD · ANIMAL", qa)
        self.assertIn("FIELD · ANIMAL", qa)
        self.assertIn("NEXT · COLD", qa)
        self.assertIn("CAVE · COLD", qa)
        self.assertIn("coyote and deer range", qa)
        self.assertIn("javelina / coyote", qa)
        self.assertIn("cottonmouth", qa)
        self.assertIn("Irrigated ground", qa)
        self.assertIn("Glasshouse", qa)
        self.assertIn("Vickery Wholesale Greenhouse", qa)
        self.assertIn("glasshouse", qa)
        self.assertIn("Discovery Well Cave Preserve", qa)
        self.assertIn("Bee Cave Central Park", qa)
        self.assertIn("Marquez Wildlife Management Area", qa)
        self.assertIn("Wildlife Drive", qa)
        self.assertIn("loblolly", qa)
        self.assertIn("Colorado River Park Wildlife Sanctuary", qa)

    def test_the_state_book_names_the_vision_species_as_range(self):
        """Hold and Field must speak the same animals and trees the Vision book has.

        Species names live in the book, not as GPS pins. The map still must
        not draw an animal icon.
        """
        for state in ("tx", "nm"):
            vision = json.loads((ROOT / f"Resources/Vision/labels.{state}.json").read_text())
            book = json.loads((ROOT / f"Resources/Field/field.{state}.json").read_text())
            ids = {card["id"] for card in book["cards"]}
            self.assertIn(f"{state}-tree-use", ids)
            self.assertIn(f"{state}-mammal", ids)
            self.assertIn(f"{state}-cactus", ids)
            self.assertIn(f"{state}-game", ids)
            blob = json.dumps(
                [c for c in book["cards"] if c["id"].startswith(f"{state}-")]
            ).lower()
            self.assertNotIn("edible", blob)
            self.assertNotIn("wildlife-icon", blob)
            kinds: dict[str, list[str]] = {}
            for lab in vision["labels"]:
                kinds.setdefault(lab["kind"], []).append(lab["name"]["en"].lower())

            def hits(card_id: str, names: list[str]) -> list[str]:
                card = next(c for c in book["cards"] if c["id"] == card_id)
                text = json.dumps(card).lower()
                return [n for n in names if n.split()[0] in text or n in text]

            self.assertGreaterEqual(
                len(hits(f"{state}-tree-use", kinds.get("tree", []))),
                2,
                f"{state} tree-use missing vision trees: {kinds.get('tree')}",
            )
            self.assertGreaterEqual(
                len(hits(f"{state}-mammal", kinds.get("mammal", []))),
                2,
                f"{state} mammal missing vision mammals: {kinds.get('mammal')}",
            )
            cactus_names = kinds.get("cactus", []) + kinds.get("cacti_yucca", [])
            self.assertGreaterEqual(
                len(hits(f"{state}-cactus", cactus_names)),
                2,
                f"{state} cactus missing vision cactus/yucca: {cactus_names}",
            )
            self.assertGreaterEqual(
                len(hits(f"{state}-game", kinds.get("mammal", []))),
                1,
                f"{state} game missing vision mammals: {kinds.get('mammal')}",
            )
            snake_blob = json.dumps(
                next(c for c in book["cards"] if c["id"] == f"{state}-snake")
            ).lower()
            for name in kinds.get("snake", []):
                self.assertTrue(
                    name.split()[0] in snake_blob or name in snake_blob,
                    f"{state}-snake missing vision snake {name}",
                )
            mammal = json.dumps(
                next(c for c in book["cards"] if c["id"] == f"{state}-mammal")
            ).lower()
            self.assertNotIn("edible", mammal)
            if state == "tx":
                self.assertIn("javelina charges", mammal)
                self.assertIn("bite card", mammal)
            else:
                self.assertIn("do not run", mammal)
                self.assertIn("elk", mammal)

        tx_tree = json.dumps(
            next(
                c
                for c in json.loads((ROOT / "Resources/Field/field.tx.json").read_text())["cards"]
                if c["id"] == "tx-tree-use"
            )
        ).lower()
        self.assertIn("cedar elm", tx_tree)

        app = (ROOT / "Blackout/AppRuntime.swift").read_text()
        hold = app.split("func holdInspect", 1)[1].split("func closeHold", 1)[0]
        self.assertIn("state: packs?.active?.state", hold)
        self.assertIn("pack: packs?.active?.id", hold)
        self.assertNotIn("animal-icon", INSPECT.read_text().lower())
        field = SWIFT.read_text()
        self.assertIn('case .animal: return "NEXT · ANIMAL"', field)
        self.assertIn('case .plant: return "NEXT · PLANT"', field)
        self.assertIn('case .bite: return "NEXT · BITE"', field)
        self.assertIn('case .shelter: return "NEXT · SHELTER"', field)
        self.assertIn("func presentRoute(", field)
        tab = FIELD_TAB.read_text()
        self.assertIn("InspectField.presentRoute", tab)
        self.assertIn("fieldTrail", tab)
        self.assertIn("leaveCard()", tab)
        self.assertIn("advanceTrail()", tab)
        self.assertNotIn('Button(s.isLast ? "DONE" : "NEXT")', tab)
        self.assertIn("fieldTrailTotal", tab)
        self.assertIn("CARD \\(at) OF", tab)
        field = SWIFT.read_text()
        self.assertIn("func fieldRoute(forVision", field)
        vision_fn = field.split("func fieldRoute(forVision", 1)[1].split(
            "public struct InspectFinding", 1
        )[0]
        self.assertIn("pack: String? = nil", vision_fn)
        self.assertIn("Inspect.treeUseEastCard", vision_fn)
        self.assertIn("Inspect.mammalEastCard", vision_fn)
        self.assertIn("Inspect.snakeEastCard", vision_fn)
        self.assertIn("g.labelId", tab)
        self.assertIn("InspectField.fieldRoute(", tab)
        self.assertIn("forVision:", tab)
        self.assertIn("InspectField.label(for:", tab)
        self.assertIn("pack: runtime.packs?.active?.id", tab)
        qa = (ROOT / "docs/SOLO_QA.md").read_text()
        self.assertIn("VISION still opens", qa)
        self.assertIn("FIELD · ANIMAL", qa)
        self.assertIn("tx-east-tree-use", qa)
        self.assertIn("tx-javelina", qa)
        self.assertIn("tx-plant-danger", qa)

    def test_east_texas_ships_its_own_field_chapter(self):
        """East woodland must not open west mesquite / javelina cards.

        Both packs load field.tx.json. Range is the open pack's chapter.
        A photographed javelina still opens the west mammal card.
        """
        inspect = INSPECT.read_text()
        cover = inspect.split("private static func plantCover", 1)[1].split(
            "private static func snakeCountry", 1
        )[0]
        self.assertLess(
            cover.index("treeUseTXCard"),
            cover.index("plantTXCard"),
            "west woodland local: must be written before east, or oleander sorts first",
        )
        self.assertIn("treeUseEastCard", cover)
        self.assertIn("mammalEastCard", cover)
        self.assertIn("gameEastCard", cover)
        snake = inspect.split("private static func snakeCountry", 1)[1]
        self.assertIn("snakeEastCard", snake)
        field = SWIFT.read_text()
        procedure = field.split("func procedure(for cardID", 1)[1].split(
            "public static func label", 1
        )[0]
        self.assertIn("Inspect.treeUseEastCard", procedure)
        self.assertIn("Inspect.mammalEastCard", procedure)
        self.assertIn("Inspect.gameEastCard", procedure)
        self.assertIn("Inspect.snakeEastCard", procedure)
        book = json.loads((ROOT / "Resources/Field/field.tx.json").read_text())
        by_id = {c["id"]: c for c in book["cards"]}
        for cid in ("tx-east-tree-use", "tx-east-mammal", "tx-east-game", "tx-east-snake"):
            self.assertIn(cid, by_id, cid)
            blob = json.dumps(by_id[cid]).lower()
            self.assertNotIn("edible", blob, cid)
            self.assertNotIn("wildlife-icon", blob, cid)
            self.assertTrue(
                (ROOT / "Resources/Field/images" / f"{cid}.png").is_file(),
                cid,
            )
        east_tree = json.dumps(by_id["tx-east-tree-use"]).lower()
        self.assertIn("live oak", east_tree)
        self.assertIn("cedar elm", east_tree)
        self.assertIn("loblolly", east_tree)
        self.assertNotIn("mesquite", east_tree)
        east_mammal = json.dumps(by_id["tx-east-mammal"]).lower()
        self.assertIn("coyote", east_mammal)
        self.assertIn("deer", east_mammal)
        self.assertIn("hog", east_mammal)
        self.assertNotIn("javelina", east_mammal)
        east_game = json.dumps(by_id["tx-east-game"]).lower()
        self.assertIn("deer", east_game)
        self.assertIn("hog", east_game)
        self.assertNotIn("javelina", east_game)
        east_snake = json.dumps(by_id["tx-east-snake"]).lower()
        self.assertIn("copperhead", east_snake)
        self.assertIn("cottonmouth", east_snake)
        west_mammal = json.dumps(by_id["tx-mammal"]).lower()
        self.assertIn("javelina", west_mammal)
        west_tree = json.dumps(by_id["tx-tree-use"]).lower()
        self.assertIn("mesquite", west_tree)

    def test_all_cards_lists_this_pack_chapter_not_the_other(self):
        """Hold and VISION keep the whole Texas book so a javelina still opens.

        ALL CARDS is the menu of this pack. East must not list mesquite and
        javelina as if they were the local chapter.
        """
        corpus = (
            ROOT / "Packages/FieldCorpus/Sources/FieldCorpus/FieldCorpus.swift"
        ).read_text()
        self.assertIn("func chapter(", corpus)
        self.assertIn("var packs: [String]?", corpus)
        tab = FIELD_TAB.read_text()
        self.assertIn("listCards", tab)
        self.assertIn("FieldCorpus.chapter(", tab)
        self.assertIn("ForEach(listCards)", tab)
        self.assertIn("runtime.packs?.active?.id", tab)
        book = json.loads((ROOT / "Resources/Field/field.tx.json").read_text())
        by_id = {c["id"]: c for c in book["cards"]}
        self.assertEqual(by_id["tx-mammal"].get("packs"), ["tx-west"])
        self.assertEqual(by_id["tx-tree-use"].get("packs"), ["tx-west"])
        self.assertEqual(by_id["tx-game"].get("packs"), ["tx-west"])
        self.assertEqual(by_id["tx-snake"].get("packs"), ["tx-west"])
        self.assertEqual(by_id["tx-east-mammal"].get("packs"), ["tx-east"])
        self.assertEqual(by_id["tx-east-tree-use"].get("packs"), ["tx-east"])
        self.assertEqual(by_id["tx-east-game"].get("packs"), ["tx-east"])
        self.assertEqual(by_id["tx-east-snake"].get("packs"), ["tx-east"])
        self.assertNotIn("packs", by_id["tx-plant-danger"])
        self.assertNotIn("packs", by_id["tx-cactus"])
        qa = (ROOT / "docs/SOLO_QA.md").read_text()
        self.assertIn("ALL CARDS", qa)
        self.assertIn("tx-mammal", qa)


if __name__ == "__main__":
    unittest.main(verbosity=2)
