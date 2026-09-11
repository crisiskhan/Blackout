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
        expected = {"tx-west": (2, 0, 0, 4, 7), "tx-east": (14, 3, 7, 1, 1), "nm": (10, 1, 8, 2, 26)}
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
            self.assertNotIn("conservatory at north austin", blob, pid)
            self.assertNotIn("madison at the arboretum", blob, pid)
            self.assertNotIn("wilderness gate", blob, pid)
            self.assertNotIn("prairie hills", blob, pid)
            self.assertNotIn("gracecus", blob, pid)
            glass = 0
            caves = 0
            wildlife = 0
            botanic = 0
            reserve = 0
            for feat in fc["features"]:
                props = feat.get("properties") or {}
                self.assertIn(feat.get("geometry", {}).get("type"), ("Polygon", "MultiPolygon"))
                name = (props.get("name") or "").lower()
                kind = ground.overlay_kind(props)
                self.assertIsNotNone(
                    kind,
                    f"{pid} overlay feature is not glasshouse, cave, wildlife, botanic, or reserve: {props}",
                )
                self.assertNotIn("bee cave", name)
                if kind == "glasshouse":
                    glass += 1
                elif kind == "cave":
                    caves += 1
                elif kind == "wildlife":
                    wildlife += 1
                elif kind == "reserve":
                    reserve += 1
                else:
                    self.assertEqual(kind, "botanic", kind)
                    botanic += 1
            self.assertEqual((glass, caves, wildlife, botanic, reserve), expected[pid], pid)
        nm_blob = (PACK_ROOT / "nm" / "layers" / "ground.geojson").read_text().lower()
        self.assertIn("marquez wildlife management area", nm_blob)
        self.assertIn("whitfield wildlife conservation area", nm_blob)
        self.assertIn("state game commission land", nm_blob)
        self.assertIn("rio grande nature center", nm_blob)
        self.assertNotIn("department of game", nm_blob)
        self.assertNotIn("game on", nm_blob)
        self.assertNotIn("open space visitor center", nm_blob)
        self.assertNotIn("candelaria farm preserve open space", nm_blob)
        self.assertNotIn("bachechi open space", nm_blob)
        self.assertNotIn("alameda/rio grande open space", nm_blob)
        self.assertNotIn("embudito trailhead open space", nm_blob)
        self.assertIn("jones canyon area of critical environmental concern", nm_blob)
        self.assertIn("paseo de la mesa open space", nm_blob)
        self.assertIn("golden open space", nm_blob)
        self.assertIn("placitas open space", nm_blob)
        self.assertIn("bear canyon scenic easement", nm_blob)
        self.assertIn("la tierra trails", nm_blob)
        self.assertIn("sun mountain", nm_blob)
        self.assertNotIn("sun mountain estates", nm_blob)
        self.assertNotIn("hyde memorial", nm_blob)
        self.assertNotIn("manzano mountains", nm_blob)
        self.assertIn("pronoun cave area of critical environmental concern", nm_blob)
        self.assertIn("albuquerque biopark botanic garden", nm_blob)
        self.assertIn("barelas community garden", nm_blob)
        east_blob = (PACK_ROOT / "tx-east" / "layers" / "ground.geojson").read_text().lower()
        self.assertIn("discovery well cave preserve", east_blob)
        self.assertIn("buttercup creek cave preserve", east_blob)
        self.assertIn("blowing sink", east_blob)
        self.assertIn("colorado river park wildlife sanctuary", east_blob)
        self.assertIn("indiangrass wildlife sanctuary", east_blob)
        self.assertIn("wild basin wilderness preserve", east_blob)
        self.assertIn("barrow nature preserve", east_blob)
        self.assertIn("stillhouse hollow nature preserve", east_blob)
        self.assertIn("big walnut creek nature preserve", east_blob)
        self.assertIn("bright leaf natural area", east_blob)
        self.assertIn("decker tallgrass prairie preserve", east_blob)
        self.assertIn("crestview commons neighborhood park", east_blob)
        self.assertNotIn("moontower saloon beer garden", east_blob)
        self.assertNotIn("godzilla preserve", east_blob)
        self.assertNotIn("whitestone preserve", east_blob)
        self.assertNotIn("westside preserve", east_blob)
        self.assertNotIn("37 lone oak trail open space", east_blob)
        west_blob = (PACK_ROOT / "tx-west" / "layers" / "ground.geojson").read_text().lower()
        self.assertIn("chihuahuan desert conservatory", west_blob)
        self.assertIn("three crosses cactus garden", west_blob)
        self.assertIn("desert garden park", west_blob)
        self.assertIn("rose garden", west_blob)
        self.assertIn("alamo mountain area of critical environmental concern", west_blob)
        self.assertIn("hueco tanks state park and historic site", west_blob)
        self.assertNotIn("cactus point park", west_blob)
        self.assertNotIn("parque cactus del desierto", west_blob)
        self.assertNotIn("hueco mountain park", west_blob)
        self.assertNotIn("hueco tanks road", west_blob)

    def test_a_botanic_garden_is_worked_ground_not_a_meal(self):
        self.assertEqual(
            ground.overlay_kind(
                {"leisure": "park", "name": "Albuquerque BioPark Botanic Garden"}
            ),
            "botanic",
        )
        self.assertEqual(
            ground.overlay_kind(
                {
                    "boundary": "protected_area",
                    "name": "Chihuahuan Desert Conservatory",
                }
            ),
            "botanic",
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"landuse": "residential", "name": "Conservatory At North Austin"}
            )
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"landuse": "residential", "name": "Madison at the Arboretum"}
            )
        )
        self.assertIsNone(
            ground.overlay_kind({"leisure": "park", "name": "Bee Cave Central Park"})
        )
        self.assertEqual(
            ground.overlay_kind({"natural": "wetland", "name": "Blowing Sink"}),
            "cave",
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"highway": "residential", "name": "Blowing Sink Road"}
            )
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"natural": "wetland", "name": "Great Northern Reservoir"}
            )
        )
        self.assertEqual(
            ground.overlay_kind(
                {"leisure": "park", "name": "Three Crosses Cactus Garden"}
            ),
            "botanic",
        )
        self.assertIsNone(
            ground.overlay_kind({"leisure": "park", "name": "Cactus Point Park"})
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"leisure": "park", "name": "Parque Cactus del Desierto"}
            )
        )
        self.assertEqual(
            ground.overlay_kind({"leisure": "park", "name": "Desert Garden Park"}),
            "botanic",
        )
        self.assertEqual(
            ground.overlay_kind({"leisure": "park", "name": "Rose Garden"}),
            "botanic",
        )
        self.assertEqual(
            ground.overlay_kind(
                {"leisure": "park", "name": "Barelas Community Garden"}
            ),
            "botanic",
        )
        self.assertEqual(
            ground.overlay_kind(
                {
                    "leisure": "park",
                    "amenity": "community garden",
                    "name": "Crestview Commons Neighborhood Park",
                }
            ),
            "botanic",
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"leisure": "park", "name": "Moontower Saloon Beer Garden"}
            )
        )
        self.assertIsNone(
            ground.overlay_kind({"leisure": "park", "name": "Garden Park"})
        )

    def test_game_commission_land_is_range_not_an_office(self):
        """NMDGF parcels are range. The Game & Fish office is a park.

        Phrase `game commission`, not the word `game`. Game On and Calle
        Puerto Game stay streets. Wildlife Drive still stays a park.
        """
        self.assertEqual(
            ground.overlay_kind(
                {
                    "leisure": "nature_reserve",
                    "boundary": "protected_area",
                    "name": "State Game Commission Land",
                }
            ),
            "wildlife",
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"leisure": "park", "name": "New Mexico Department of Game & Fish"}
            )
        )
        self.assertIsNone(
            ground.overlay_kind({"leisure": "park", "name": "Game On"})
        )
        self.assertIsNone(
            ground.overlay_kind({"leisure": "park", "name": "Wildlife Drive Park"})
        )
        self.assertEqual(
            ground.overlay_kind(
                {
                    "leisure": "nature_reserve",
                    "boundary": "protected_area",
                    "name": "Wild Basin Wilderness Preserve",
                }
            ),
            "wildlife",
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"landuse": "residential", "name": "Wilderness Gate"}
            )
        )
        self.assertEqual(
            ground.overlay_kind(
                {
                    "leisure": "nature_reserve",
                    "natural": "wood",
                    "name": "Barrow Nature Preserve",
                }
            ),
            "wildlife",
        )
        self.assertEqual(
            ground.overlay_kind(
                {"leisure": "park", "name": "Rio Grande Nature Center State Park"}
            ),
            "wildlife",
        )
        self.assertEqual(
            ground.overlay_kind(
                {"leisure": "park", "natural": "wood", "name": "Bright Leaf Natural Area"}
            ),
            "wildlife",
        )
        self.assertIsNone(
            ground.overlay_kind({"leisure": "park", "name": "Godzilla Preserve"})
        )
        self.assertIsNone(
            ground.overlay_kind({"leisure": "park", "name": "Open Space Visitor Center"})
        )
        self.assertIsNone(
            ground.overlay_kind({"leisure": "park", "name": "Whitestone Preserve"})
        )
        self.assertIsNone(
            ground.overlay_kind({"leisure": "park", "name": "Westside Preserve"})
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"leisure": "park", "name": "Candelaria Farm Preserve Open Space"}
            )
        )
        self.assertEqual(
            ground.overlay_kind(
                {
                    "leisure": "nature_reserve",
                    "boundary": "protected_area",
                    "name": "Paseo de la Mesa Open Space",
                }
            ),
            "reserve",
        )
        self.assertEqual(
            ground.overlay_kind({"leisure": "park", "name": "Golden Open Space"}),
            "reserve",
        )
        self.assertEqual(
            ground.overlay_kind(
                {"leisure": "park", "name": "Bear Canyon Open Space West"}
            ),
            "reserve",
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"leisure": "park", "name": "Alameda/Rio Grande Open Space"}
            )
        )
        self.assertIsNone(
            ground.overlay_kind({"leisure": "park", "name": "Bachechi Open Space"})
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"leisure": "park", "name": "Embudito Trailhead Open Space"}
            )
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"leisure": "park", "name": "37 Lone Oak Trail Open Space"}
            )
        )
        self.assertEqual(
            ground.overlay_kind(
                {"leisure": "park", "name": "Bear Canyon Scenic Easement"}
            ),
            "reserve",
        )
        self.assertIsNone(
            ground.overlay_kind(
                {
                    "leisure": "park",
                    "name": "Ann and Roy Butler Hike and Bike 222 Riverside Easement",
                }
            )
        )
        self.assertEqual(
            ground.overlay_kind(
                {
                    "leisure": "park",
                    "landuse": "recreation_ground",
                    "name": "La Tierra Trails",
                }
            ),
            "reserve",
        )
        self.assertIsNone(
            ground.overlay_kind({"leisure": "park", "name": "Tierra Blanca"})
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"leisure": "park", "name": "Desert Trails Community Park"}
            )
        )
        self.assertEqual(
            ground.overlay_kind(
                {"boundary": "protected_area", "name": "Sun Mountain"}
            ),
            "reserve",
        )
        self.assertIsNone(
            ground.overlay_kind({"natural": "peak", "name": "Sun Mountain"})
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"highway": "residential", "name": "Sun Mountain Road"}
            )
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"highway": "residential", "name": "Sun Mountain Street"}
            )
        )
        self.assertIsNone(
            ground.overlay_kind(
                {
                    "landuse": "residential",
                    "place": "neighbourhood",
                    "name": "Sun Mountain Estates",
                }
            )
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"boundary": "protected_area", "name": "Hyde Memorial State Park"}
            )
        )
        self.assertIsNone(
            ground.overlay_kind(
                {
                    "boundary": "protected_area",
                    "landuse": "recreation_ground",
                    "name": "Manzano Mountains State Park",
                }
            )
        )
        self.assertIsNone(ground.overlay_kind({"leisure": "nature_reserve"}))
        self.assertIsNone(
            ground.overlay_kind({"leisure": "nature_reserve", "name": ""})
        )

    def test_an_open_reserve_is_not_picnic_woodland(self):
        """A mountain ACEC opens vipers, not mesquite tree-use.

        Phrase `area of critical environmental concern`, not `critical`.
        Pronoun Cave is still a hole. Phrase `prairie preserve`, not
        `prairie`. Prairie Hills stays apartments.
        """
        self.assertEqual(
            ground.overlay_kind(
                {
                    "leisure": "nature_reserve",
                    "boundary": "protected_area",
                    "name": "Alamo Mountain Area of Critical Environmental Concern",
                }
            ),
            "reserve",
        )
        self.assertEqual(
            ground.overlay_kind(
                {
                    "leisure": "nature_reserve",
                    "name": "Decker Tallgrass Prairie Preserve",
                }
            ),
            "reserve",
        )
        self.assertEqual(
            ground.overlay_kind(
                {
                    "leisure": "nature_reserve",
                    "boundary": "protected_area",
                    "name": "Pronoun Cave Area of Critical Environmental Concern",
                }
            ),
            "cave",
        )
        self.assertIsNone(
            ground.overlay_kind({"highway": "residential", "name": "Gracecus Way"})
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"landuse": "residential", "name": "Prairie Hills Apartments"}
            )
        )
        self.assertEqual(
            ground.overlay_kind(
                {
                    "leisure": "park",
                    "boundary": "protected_area",
                    "name": "Hueco Tanks State Park and Historic Site",
                }
            ),
            "reserve",
        )
        self.assertIsNone(
            ground.overlay_kind({"leisure": "park", "name": "Hueco Mountain Park"})
        )
        self.assertIsNone(
            ground.overlay_kind({"highway": "tertiary", "name": "Hueco Tanks Road"})
        )
        self.assertIsNone(
            ground.overlay_kind(
                {"name": "Hueco Tanks State Park Dam", "waterway": "dam"}
            )
        )

    def test_the_overlay_and_the_card_use_the_same_cave_preserve_phrases(self):
        inspect = INSPECT.read_text()
        for phrase in ground.CAVE_PRESERVE_PHRASES:
            self.assertIn(f'"{phrase}"', inspect)
            self.assertIn(f'"{phrase}"', (ROOT / "tools/v3/ground.py").read_text())
        self.assertNotIn('contains("cave")', inspect)
        self.assertNotIn('contains("sink")', inspect)
        for phrase in ground.WILDLIFE_RANGE_PHRASES:
            self.assertIn(f'"{phrase}"', inspect)
            self.assertIn(f'"{phrase}"', (ROOT / "tools/v3/ground.py").read_text())
        self.assertNotIn('contains("wildlife")', inspect)
        self.assertNotIn('contains("wilderness")', inspect)
        self.assertNotIn('contains("preserve")', inspect)
        self.assertNotIn('contains("nature")', inspect)
        self.assertIn("isWildlifeRange", inspect)
        self.assertIn("Wildlife range", inspect)
        for phrase in ground.OPEN_RESERVE_PHRASES:
            self.assertIn(f'"{phrase}"', inspect)
            self.assertIn(f'"{phrase}"', (ROOT / "tools/v3/ground.py").read_text())
        self.assertNotIn('contains("critical")', inspect)
        self.assertNotIn('contains("prairie")', inspect)
        self.assertNotIn('contains("hueco")', inspect)
        self.assertNotIn('contains("easement")', inspect)
        self.assertNotIn('contains("tierra")', inspect)
        self.assertNotIn('contains("trails")', inspect)
        self.assertNotIn('contains("sun")', inspect)
        self.assertNotIn('contains("mountain")', inspect)
        self.assertIn("isOpenReserve", inspect)
        self.assertIn("Open reserve", inspect)
        self.assertIn('t["leisure"] == "nature_reserve"', inspect)
        self.assertIn('props.get("leisure") == "nature_reserve"', (ROOT / "tools/v3/ground.py").read_text())
        self.assertNotIn('contains("open space")', inspect)
        self.assertIn('range(of: "open space")', inspect)
        self.assertIn('"open space" not in lowered', (ROOT / "tools/v3/ground.py").read_text())
        self.assertIn('contains("visitor")', inspect)
        self.assertIn('contains("farm")', inspect)
        self.assertIn('contains("rio grande")', inspect)
        self.assertIn('contains("bachechi")', inspect)
        self.assertIn('contains("trail")', inspect)
        for phrase in ground.BOTANIC_GARDEN_PHRASES:
            self.assertIn(f'"{phrase}"', inspect)
            self.assertIn(f'"{phrase}"', (ROOT / "tools/v3/ground.py").read_text())
        self.assertNotIn('contains("arboretum")', inspect)
        self.assertIn("isBotanicGarden", inspect)
        self.assertIn("Botanic garden", inspect)

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
        self.assertNotIn(
            "cactusTXCard",
            cover,
            "picnic woodland is not a cactus garden; scrub and cactus gardens carry spines",
        )
        self.assertNotIn(
            "snakeEastCard",
            cover,
            "a city park is not cottonmouth country; bosque carries the east snake card",
        )
        self.assertIn("wetlandCover", inspect)
        wet = inspect.split("private static func wetlandCover", 1)[1].split(
            "private static func plantCover", 1
        )[0]
        self.assertLess(
            wet.index("treeUseEastCard"),
            wet.index("snakeEastCard"),
            "east bosque still opens tree-use, then cottonmouth treatment",
        )
        self.assertLess(
            wet.index("gameEastCard"),
            wet.index("snakeEastCard"),
            "snake after game keeps woodland BOOK order",
        )
        self.assertNotIn("cactusTXCard", wet)
        wet_case = inspect.split('if t["natural"] == "wetland"', 1)[1].split(
            'if t["leisure"] == "park"', 1
        )[0]
        self.assertIn("wetlandCover", wet_case)
        self.assertNotIn("plantCover(", wet_case)
        self.assertIn("irrigatedCover", inspect)
        farm_case = inspect.split('case "farmland"', 1)[1].split(
            'case "greenhouse_horticulture"', 1
        )[0]
        self.assertIn("irrigatedCover", farm_case)
        self.assertNotIn("plantCover(", farm_case)
        irr = inspect.split("private static func irrigatedCover", 1)[1].split(
            "private static func snakeCountry", 1
        )[0]
        self.assertLess(
            irr.index("treeUseTXCard"),
            irr.index("plantTXCard"),
            "a field opens this pack's trees, not oleander first",
        )
        self.assertNotIn(
            "mammalTXCard",
            irr,
            "a field is not javelina country; wildlife range carries the animals",
        )
        self.assertNotIn("cactusTXCard", irr)
        self.assertNotIn("gameTXCard", irr)
        tree = inspect.split('case "tree":', 1)[1].split('case "wood":', 1)[0]
        self.assertIn("treeUseTXCard", tree)
        self.assertNotIn("mammalTXCard", tree)
        hole = inspect.split('case "cave", "cave_entrance", "sinkhole":', 1)[1].split(
            'case "tree":', 1
        )[0]
        self.assertIn('caveCard', hole)
        self.assertIn('coldCard', hole)
        peak = inspect.split('if t["natural"] == "peak"', 1)[1].split(
            'if let natural = t["natural"]', 1
        )[0]
        self.assertIn(
            "extra: [biteCard]",
            peak,
            "a peak walk includes bite treatment, like a mammal still",
        )
        self.assertNotIn("plantTXCard", peak)
        self.assertNotIn("snakeTXCard", peak)
        rock = inspect.split('case "bare_rock"', 1)[1].split(
            'case "grassland"', 1
        )[0]
        self.assertIn(
            "extra: [biteCard]",
            rock,
            "bare rock names animals on the hold; Field must open bite",
        )
        self.assertNotIn("plantTXCard", rock)
        self.assertIn('case "grassland", "grass":', inspect)
        self.assertIn("isCavePreserve", inspect)
        self.assertIn("cave preserve", inspect)
        self.assertIn("cave area of critical", inspect)
        self.assertIn("blowing sink", inspect)
        self.assertIn("isWildlifeRange", inspect)
        self.assertIn("wildlife refuge", inspect)
        self.assertIn("wildlife management area", inspect)
        self.assertIn("national wildlife", inspect)
        self.assertIn("wildlife sanctuary", inspect)
        self.assertIn("wildlife conservation area", inspect)
        self.assertIn("game commission", inspect)
        self.assertIn("wilderness preserve", inspect)
        self.assertIn("nature preserve", inspect)
        self.assertIn("nature center", inspect)
        self.assertIn("natural area", inspect)
        land = inspect.split("private static func land(", 1)[1]
        self.assertLess(
            land.index("isWildlifeRange"),
            land.index('case "wood":'),
            "a wildlife sanctuary tagged as wood must still be range, not picnic woodland",
        )
        self.assertIn("isBotanicGarden", inspect)
        self.assertIn("botanic garden", inspect)
        self.assertIn("botanical garden", inspect)
        self.assertIn("conservatory", inspect)
        self.assertIn("cactus garden", inspect)
        self.assertLess(
            land.index("isBotanicGarden"),
            land.index('case "wood":'),
            "a botanic garden tagged as a park must still be worked ground, not picnic woodland",
        )
        self.assertIn("isOpenReserve", inspect)
        self.assertIn("area of critical environmental concern", inspect)
        self.assertIn("prairie preserve", inspect)
        self.assertIn("hueco tanks", inspect)
        self.assertIn("scenic easement", inspect)
        self.assertIn("la tierra trails", inspect)
        self.assertIn("sun mountain", inspect)
        self.assertIn("Open reserve", inspect)
        self.assertIn('range(of: "open space")', inspect)
        self.assertLess(
            land.index("isOpenReserve"),
            land.index('case "wood":'),
            "a mountain ACEC must open vipers, not picnic tree-use",
        )
        self.assertLess(
            land.index('if t["natural"] == "wetland"'),
            land.index('if t["leisure"] == "park"'),
            "a named bosque tagged as a park is still bosque, not picnic",
        )
        self.assertLess(
            land.index('if t["leisure"] == "park"'),
            land.index('case "scrub", "heath":'),
            "a city park tagged as scrub fill is kept ground, not viper country",
        )
        self.assertLess(
            land.index("isBotanicGarden"),
            land.index("isOpenReserve"),
            "a botanic garden is worked ground; an ACEC is snake country",
        )
        self.assertLess(
            land.index("isCavePreserve"),
            land.index("isOpenReserve"),
            "Pronoun Cave is a hole, not open reserve",
        )
        cactus_fn = inspect.split("static func isCactusGarden", 1)[1].split(
            "static func isBotanicGarden", 1
        )[0]
        self.assertIn("cactus garden", cactus_fn)
        self.assertIn("desert garden", cactus_fn)
        self.assertIn("desert conservatory", cactus_fn)
        self.assertNotIn("oleander", cactus_fn)
        self.assertIn("isCactusGarden", inspect)
        self.assertIn("cactusGardenCover", inspect)
        self.assertIn("Cactus garden", inspect)
        self.assertLess(
            land.index("isCactusGarden"),
            land.index("isBotanicGarden"),
            "a cactus garden must open spines, not oleander",
        )
        cactus = inspect.split("private static func cactusGardenCover", 1)[1].split(
            "private static func workedCover", 1
        )[0]
        self.assertIn("cactusTXCard", cactus)
        self.assertNotIn(
            "plantTXCard",
            cactus,
            "a cactus garden must not open oleander; spines are the cactus card",
        )
        self.assertNotIn("plantNMCard", cactus)
        self.assertNotIn("plantUseCard", cactus)
        self.assertNotIn("treeUseTXCard", cactus)
        self.assertNotIn("mammalTXCard", cactus)
        do = SWIFT.read_text()
        self.assertIn("Javelina, coyote, and deer range", do)
        self.assertIn("coyote and deer range", do)
        self.assertIn("black bear and elk range", do)
        self.assertIn("Copperhead and cottonmouth country", do)
        self.assertIn("Hog range", do)
        self.assertIn("Cottonmouth country", do)
        self.assertIn("loblolly pine", do)
        self.assertIn("Hog country", do)
        self.assertIn("Pretty is not food", do)
        self.assertIn("Botanic garden", do)
        self.assertIn("plantDangerLine", do)
        poison = do.split("private static func plantDangerLine", 1)[1].split(
            "private static func landDoLine", 1
        )[0].lower()
        self.assertIn("oleander", poison)
        self.assertIn("texas mountain laurel", poison)
        self.assertIn("datura", poison)
        self.assertIn("pretty is not food", poison)
        self.assertIn("brush off, then water", poison)
        self.assertNotIn("cholla", poison)
        self.assertNotIn("prickly pear", poison)
        self.assertNotIn("edible", poison)
        self.assertNotIn("lives here", poison)
        self.assertIn('case "Named tree", "Tree", "Irrigated ground":', do)
        self.assertIn("treeUseLine", do)
        named_tree = do.split("private static func treeUseLine", 1)[1].split(
            "private static func animalRangeLine", 1
        )[0].lower()
        self.assertIn("cottonwood", named_tree)
        self.assertIn("loblolly pine", named_tree)
        self.assertIn("mesquite", named_tree)
        self.assertIn("rio grande cottonwood", named_tree)
        self.assertIn("not a meal", named_tree)
        self.assertIn("deadfall", named_tree)
        self.assertIn("wind break", named_tree)
        self.assertNotIn("the bite card", named_tree)
        self.assertNotIn("javelina", named_tree)
        self.assertNotIn("hog", named_tree)
        self.assertNotIn("coyote", named_tree)
        self.assertNotIn("bear", named_tree)
        self.assertNotIn("aspen", named_tree)
        woodland_hold = do.split("private static func treeRangeLine", 1)[1].split(
            "private static func treeUseLine", 1
        )[0].lower()
        self.assertIn("javelina", woodland_hold)
        self.assertIn("hog country", woodland_hold)
        self.assertIn("mule deer", woodland_hold)
        self.assertIn("deer range", woodland_hold)
        self.assertIn("cottonwood", woodland_hold)
        self.assertIn("rio grande cottonwood", woodland_hold)
        self.assertIn("mesquite", woodland_hold)
        self.assertIn("loblolly pine", woodland_hold)
        self.assertIn("the bite card", woodland_hold)
        self.assertIn("deadfall", woodland_hold)
        self.assertIn("south-side shade", woodland_hold)
        self.assertIn("wind break", woodland_hold)
        self.assertIn("give it the road", woodland_hold)
        self.assertNotIn("the food card", woodland_hold)
        self.assertNotIn("no ice", woodland_hold)
        self.assertNotIn("give it room", woodland_hold)
        self.assertNotIn("aspen", woodland_hold)
        self.assertNotIn("edible", woodland_hold)
        bosque = do.split('case "Bosque or wetland":', 1)[1].split(
            'case "Desert scrub"', 1
        )[0].lower()
        self.assertIn("cottonmouth", bosque)
        self.assertIn("the bite card", bosque)
        self.assertIn("south-side shade", bosque)
        self.assertIn("wind break", bosque)
        self.assertIn("give it the road", bosque)
        self.assertIn("no ice, no cut, no suck", bosque)
        self.assertNotIn("the food card", bosque)
        tx_plant_do = next(
            c
            for c in json.loads((ROOT / "Resources/Field/field.tx.json").read_text())["cards"]
            if c["id"] == "tx-plant-danger"
        )["steps"][0]["do"]["en"].lower()
        self.assertIn("oleander", tx_plant_do)
        self.assertIn("pretty is not food", tx_plant_do)
        self.assertIn("brush off", tx_plant_do)
        nm_plant_do = next(
            c
            for c in json.loads((ROOT / "Resources/Field/field.nm.json").read_text())["cards"]
            if c["id"] == "nm-plant-danger"
        )["steps"][0]["do"]["en"].lower()
        self.assertIn("datura", nm_plant_do)
        self.assertNotIn(
            "cholla",
            nm_plant_do,
            "botanic SPEAK is datura; jumping cholla lives on the cactus card",
        )
        self.assertIn("Cactus garden", do)
        self.assertIn("Spines, not a meal", do)
        cactus_hold = do.split('case "Cactus garden":', 1)[1].split(
            'case "Wildlife range":', 1
        )[0].lower()
        self.assertIn("prickly pear", cactus_hold)
        self.assertIn("cholla", cactus_hold)
        self.assertIn("sotol", cactus_hold)
        self.assertIn("comb glochids out", cactus_hold)
        self.assertIn("give it room", cactus_hold)
        self.assertNotIn("edible", cactus_hold)
        self.assertNotIn("lives here", cactus_hold)
        tx_cactus_card = next(
            c
            for c in json.loads((ROOT / "Resources/Field/field.tx.json").read_text())["cards"]
            if c["id"] == "tx-cactus"
        )
        tx_cactus = json.dumps(tx_cactus_card).lower()
        self.assertIn("prickly pear", tx_cactus)
        self.assertIn("yucca", tx_cactus)
        tx_cactus_do = tx_cactus_card["steps"][0]["do"]["en"].lower()
        self.assertIn("prickly pear", tx_cactus_do)
        self.assertIn("yucca", tx_cactus_do)
        self.assertIn("glochids", tx_cactus_do)
        nm_cactus_card = next(
            c
            for c in json.loads((ROOT / "Resources/Field/field.nm.json").read_text())["cards"]
            if c["id"] == "nm-cactus"
        )
        nm_cactus = json.dumps(nm_cactus_card).lower()
        self.assertIn("cholla", nm_cactus)
        self.assertIn("sotol", nm_cactus)
        nm_cactus_do = nm_cactus_card["steps"][0]["do"]["en"].lower()
        self.assertIn("cholla", nm_cactus_do)
        self.assertIn("sotol", nm_cactus_do)
        self.assertIn("This is range, not a pin", do)
        self.assertIn("tx-east", do)
        self.assertNotIn("ice and cold cards", do)
        peak_hold = do.split('case "Peak":', 1)[1].split('case "Rock":', 1)[0].lower()
        self.assertNotIn(
            "bite card",
            peak_hold,
            "peak DO names animals and cold; bite treatment is on the walk",
        )
        self.assertNotIn("food card", peak_hold)
        self.assertIn("javelina", peak_hold)
        self.assertIn("elk", peak_hold)
        self.assertIn("give it the road", peak_hold)
        rock_hold = do.split('case "Rock":', 1)[1].split('case "Built-up ground":', 1)[0].lower()
        self.assertNotIn("bite card", rock_hold)
        self.assertNotIn("food card", rock_hold)
        self.assertIn("do not go in alone", do.lower())
        self.assertIn("stay in daylight", do.lower())
        self.assertIn(
            'case "Desert scrub", "Grassland", "Sand or playa floor", "Salt flat", "Open reserve":',
            do,
        )
        rng = inspect.split("private static func wildlifeRange", 1)[1].split(
            "private static func builtUp", 1
        )[0]
        self.assertLess(
            rng.index("mammalTXCard"),
            rng.index("snakeTXCard"),
            "wildlife range must open this pack's mammal card, not picnic tree-use",
        )
        self.assertLess(rng.index("snakeTXCard"), rng.index("gameTXCard"))
        self.assertLess(rng.index("gameTXCard"), rng.index("treeUseTXCard"))
        self.assertLess(rng.index("mammalEastCard"), rng.index("snakeEastCard"))
        self.assertIn("extra: [biteCard, plantUseCard, gameCard]", rng)
        self.assertNotIn("shelterCard", rng)
        self.assertNotIn("fungiCard", rng)

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
        self.assertIn("isBotanicGarden", pick)
        self.assertIn("isOpenReserve", pick)
        self.assertIn("greenhouse_horticulture", pick)
        self.assertIn("pointWater", pick)
        self.assertIn("it beats a named street", inspect.split("public static func pick", 1)[0])
        self.assertIn("A drain in the thumb box is not", inspect.split("public static func pick", 1)[0])

    def test_glasshouses_are_worked_ground_not_a_meal(self):
        inspect = INSPECT.read_text()
        self.assertIn('case "greenhouse_horticulture":', inspect)
        self.assertIn("mapped as glasshouses", inspect)
        self.assertIn('klass: "Glasshouse"', inspect)
        self.assertIn("workedCover", inspect)
        worked = inspect.split("private static func workedCover", 1)[1].split(
            "private static func wildlifeRange", 1
        )[0]
        self.assertNotIn("mammalEastCard", worked)
        self.assertNotIn("cactusTXCard", worked)
        self.assertNotIn("cactusNMCard", worked)
        self.assertNotIn(
            "plantUseCard",
            worked,
            "a glasshouse is not woodland tree-use; don't chew, then unknown",
        )
        self.assertIn("plantTXCard", worked)
        tiles = (ROOT / "tools/v3/tiles.py").read_text()
        self.assertIn('("landuse", "greenhouse_horticulture"): "farm"', tiles)
        swift = MAP_SWIFT.read_text()
        self.assertIn("layers/ground.geojson", swift)
        self.assertIn("groundWorkedFillLayerID", swift)
        self.assertIn("groundWorkedLineLayerID", swift)
        self.assertNotIn("edible", swift.lower())
        self.assertIn("resolverVersion = 6", swift)

    def test_a_hold_asks_the_overlay_source_and_the_glass_holds_real_sheets(self):
        """Faint fill and walking-zoom are for the eye. The hold still has to
        name the sheet. Glass tests press interiors taken from the extract.
        """
        offline = OFFLINE_SWIFT.read_text()
        self.assertIn("packWorkedGround", offline)
        self.assertIn("features(matching:", offline)
        self.assertIn("PackStyle.groundWorkedSourceID", offline)
        glass = (
            ROOT / "Packages/MapLibreMap/Tests/MapLibreMapTests/HoldOnTheGlassTests.swift"
        ).read_text()
        self.assertIn("Sierra de Ciudad Juárez", glass)
        self.assertIn("Desert scrub", glass)
        self.assertIn("31.71809", glass)
        self.assertIn("31.94284", glass)
        self.assertIn("Three Crosses Cactus Garden", glass)
        self.assertIn("Chihuahuan Desert Conservatory", glass)
        self.assertIn("Rio Bosque Wetlands Park", glass)
        self.assertIn("Rose Garden", glass)
        self.assertIn("Beaukiss Woods", glass)
        self.assertIn("Isleta Rectangle", glass)
        self.assertIn("La Cruz Peak", glass)
        self.assertIn("Barton Hill", glass)
        self.assertIn("Alamo Mountain Area of Critical Environmental Concern", glass)
        self.assertIn("32.332036", glass)
        self.assertIn("-106.782070", glass)
        self.assertIn("33.157743", glass)
        self.assertIn("-107.242346", glass)
        self.assertIn("31.638834", glass)
        self.assertIn("-106.308840", glass)
        self.assertIn("31.513892", glass)
        self.assertIn("-106.593002", glass)
        self.assertIn("33.100215", glass)
        self.assertIn("-105.802406", glass)
        self.assertIn("32.911739", glass)
        self.assertIn("-105.959273", glass)
        self.assertIn("32.502967", glass)
        self.assertIn("-106.933833", glass)
        self.assertIn("32.032331", glass)
        self.assertIn("-105.633755", glass)
        self.assertIn("31.694905", glass)
        self.assertIn("-106.441133", glass)
        self.assertIn("Cactus garden", glass)
        self.assertIn("Open reserve", glass)
        self.assertIn("Glasshouse", glass)
        self.assertIn("Cave or hole", glass)
        self.assertIn("Wildlife range", glass)
        self.assertIn("Indiangrass Wildlife Sanctuary", glass)
        self.assertIn("Discovery Well Cave Preserve", glass)
        self.assertIn("Blowing Sink", glass)
        self.assertIn("Decker Tallgrass Prairie Preserve", glass)
        self.assertIn("30.315667", glass)
        self.assertIn("-97.591821", glass)
        self.assertIn("30.490391", glass)
        self.assertIn("-97.855063", glass)
        self.assertIn("30.193035", glass)
        self.assertIn("-97.850443", glass)
        self.assertIn("30.294331", glass)
        self.assertIn("-97.603942", glass)
        self.assertIn("30.423083", glass)
        self.assertIn("-97.227224", glass)
        self.assertIn("30.194954", glass)
        self.assertIn("-97.688346", glass)
        self.assertIn("30.065769", glass)
        self.assertIn("-97.882228", glass)
        self.assertIn('packId: "tx-east"', glass)
        self.assertIn("Albuquerque BioPark Botanic Garden", glass)
        self.assertIn("Marquez Wildlife Management Area", glass)
        self.assertIn("Pronoun Cave Area of Critical Environmental Concern", glass)
        self.assertIn("35.093625", glass)
        self.assertIn("-106.680958", glass)
        self.assertIn("35.327562", glass)
        self.assertIn("-107.319389", glass)
        self.assertIn("34.750796", glass)
        self.assertIn("-107.344750", glass)
        self.assertIn("34.939900", glass)
        self.assertIn("-106.320316", glass)
        self.assertIn("34.628816", glass)
        self.assertIn("-105.915768", glass)
        self.assertIn("34.392837", glass)
        self.assertIn("-107.420040", glass)
        self.assertIn("30.048502", glass)
        self.assertIn("-97.745559", glass)
        self.assertIn("Cerro Pelado Burn Scar", glass)
        self.assertIn("35.785371", glass)
        self.assertIn("-106.573932", glass)
        self.assertIn("Mount Franklin", glass)
        self.assertIn("31.832051", glass)
        self.assertIn("-106.492210", glass)
        self.assertIn("Jones Canyon Area of Critical Environmental Concern", glass)
        self.assertIn("35.846906", glass)
        self.assertIn("-107.025703", glass)
        self.assertIn('packId: "nm"', glass)
        self.assertIn("Botanic garden", glass)
        self.assertIn("Irrigated ground", glass)
        self.assertIn("Woodland", glass)
        self.assertIn("loblolly", glass)
        self.assertIn("datura", glass)
        self.assertIn("mule deer", glass)
        self.assertIn("FIELD · ANIMAL", glass)
        self.assertIn("ANIMAL · BITE · FOOD · PLANT", glass)
        self.assertIn("BITE · ANIMAL · PLANT · FOOD · HEAT", glass)
        self.assertIn("PLANT · ANIMAL · FOOD · BITE · SHELTER · FUNGI", glass)
        self.assertIn("named sink", glass)
        self.assertIn("Bosque or wetland", glass)
        self.assertIn('contains("edible")', glass)
        self.assertNotIn("safe to eat", glass.lower())
        self.assertNotIn("edible unlock", glass.lower())

        def pip(lon: float, lat: float, ring: list) -> bool:
            inside = False
            n = len(ring)
            j = n - 1
            for i in range(n):
                xi, yi = ring[i][0], ring[i][1]
                xj, yj = ring[j][0], ring[j][1]
                if ((yi > lat) != (yj > lat)) and (
                    lon < (xj - xi) * (lat - yi) / (yj - yi) + xi
                ):
                    inside = not inside
                j = i
            return inside

        def rings_of(geom: dict) -> list:
            kind = geom.get("type")
            coords = geom.get("coordinates") or []
            if kind == "Polygon":
                return [coords[0]] if coords else []
            if kind == "MultiPolygon":
                return [poly[0] for poly in coords]
            return []

        west = json.loads((PACK_ROOT / "tx-west" / "layers" / "ground.geojson").read_text())
        cactus_hit = False
        conservatory_hit = False
        rose_hit = False
        glass_hit = False
        reserve_hit = False
        hueco_hit = False
        for feat in west["features"]:
            props = feat.get("properties") or {}
            kind = ground.overlay_kind(props)
            for ring in rings_of(feat.get("geometry") or {}):
                if kind == "botanic" and pip(-106.782070, 32.332036, ring):
                    cactus_hit = props.get("name") == "Three Crosses Cactus Garden"
                if kind == "botanic" and pip(-107.242346, 33.157743, ring):
                    conservatory_hit = props.get("name") == "Chihuahuan Desert Conservatory"
                if kind == "botanic" and pip(-105.959273, 32.911739, ring):
                    rose_hit = props.get("name") == "Rose Garden"
                if kind == "glasshouse" and pip(-106.933833, 32.502967, ring):
                    glass_hit = True
                if kind == "reserve" and pip(-105.633755, 32.032331, ring):
                    reserve_hit = (
                        props.get("name")
                        == "Alamo Mountain Area of Critical Environmental Concern"
                    )
                if kind == "reserve" and pip(-106.042815, 31.911873, ring):
                    hueco_hit = (
                        props.get("name") == "Hueco Tanks State Park and Historic Site"
                    )
        self.assertTrue(cactus_hit, "glass cactus hold is not inside Three Crosses")
        self.assertTrue(
            conservatory_hit, "glass conservatory hold is not inside Chihuahuan Desert Conservatory"
        )
        self.assertTrue(rose_hit, "glass rose-garden hold is not inside Rose Garden")
        self.assertTrue(glass_hit, "glass glasshouse hold is not inside a greenhouse sheet")
        self.assertTrue(reserve_hit, "glass ACEC hold is not inside Alamo Mountain")
        self.assertTrue(
            hueco_hit,
            "SOLO_QA Hueco Tanks hold is not inside the named desert park",
        )

        osm = json.loads((PACK_ROOT / "tx-west" / "osm.geojson").read_text())
        sink = False
        bosque = False
        farm = False
        west_wood = False
        sierra = False
        unnamed_heath = False
        for feat in osm["features"]:
            props = feat.get("properties") or {}
            geom = feat.get("geometry") or {}
            if props.get("natural") == "sinkhole" and geom.get("type") == "Point":
                lon, lat = geom["coordinates"][:2]
                if abs(lat - 31.694905) < 1e-6 and abs(lon - (-106.441133)) < 1e-6:
                    sink = True
            if (
                props.get("natural") == "wetland"
                and props.get("name") == "Rio Bosque Wetlands Park"
            ):
                for ring in rings_of(geom):
                    if pip(-106.308840, 31.638834, ring):
                        bosque = True
            if props.get("natural") == "heath" and props.get("name") == "Sierra de Ciudad Juárez":
                for ring in rings_of(geom):
                    if pip(-106.61330, 31.71809, ring):
                        sierra = True
            if props.get("natural") == "heath" and not props.get("name"):
                for ring in rings_of(geom):
                    if pip(-106.75415, 31.94284, ring):
                        unnamed_heath = True
            if props.get("landuse") == "farmland":
                for ring in rings_of(geom):
                    if pip(-106.593002, 31.513892, ring):
                        farm = True
            if props.get("natural") == "wood" and not props.get("name"):
                for ring in rings_of(geom):
                    if pip(-105.802406, 33.100215, ring):
                        west_wood = True
        self.assertTrue(sink, "glass sinkhole hold is not the unnamed west sinkhole")
        self.assertTrue(bosque, "glass bosque hold is not inside Rio Bosque")
        self.assertTrue(farm, "glass irrigated hold is not inside west farmland")
        self.assertTrue(west_wood, "glass west woodland hold is not inside unnamed west wood")
        self.assertTrue(sierra, "glass named-ground hold is not inside Sierra de Ciudad Juárez heath")
        self.assertTrue(unnamed_heath, "glass empty-desert hold is not inside unnamed west heath")

        east = json.loads((PACK_ROOT / "tx-east" / "layers" / "ground.geojson").read_text())
        wildlife_hit = False
        cave_hit = False
        blowing_hit = False
        decker_hit = False
        buttercup_hit = False
        for feat in east["features"]:
            props = feat.get("properties") or {}
            kind = ground.overlay_kind(props)
            for ring in rings_of(feat.get("geometry") or {}):
                if kind == "wildlife" and pip(-97.591821, 30.315667, ring):
                    wildlife_hit = props.get("name") == "Indiangrass Wildlife Sanctuary"
                if kind == "cave" and pip(-97.855063, 30.490391, ring):
                    cave_hit = props.get("name") == "Discovery Well Cave Preserve"
                if kind == "cave" and pip(-97.850443, 30.193035, ring):
                    blowing_hit = props.get("name") == "Blowing Sink"
                if kind == "cave" and pip(-97.839459, 30.494626, ring):
                    buttercup_hit = props.get("name") == "Buttercup Creek Cave Preserve"
                if kind == "reserve" and pip(-97.603942, 30.294331, ring):
                    decker_hit = props.get("name") == "Decker Tallgrass Prairie Preserve"
        self.assertTrue(
            wildlife_hit, "glass wildlife hold is not inside Indiangrass"
        )
        self.assertTrue(
            cave_hit, "glass cave hold is not inside Discovery Well"
        )
        self.assertTrue(
            blowing_hit, "glass named-sink hold is not inside Blowing Sink"
        )
        self.assertTrue(
            buttercup_hit, "SOLO_QA Buttercup hold is not inside Buttercup Creek Cave Preserve"
        )
        self.assertTrue(
            decker_hit, "glass east open-reserve hold is not inside Decker"
        )

        east_osm = json.loads((PACK_ROOT / "tx-east" / "osm.geojson").read_text())
        woods = False
        east_bosque = False
        east_peak = False
        east_scrub = False
        for feat in east_osm["features"]:
            props = feat.get("properties") or {}
            geom = feat.get("geometry") or {}
            if props.get("name") == "Beaukiss Woods":
                for ring in rings_of(geom):
                    if pip(-97.227224, 30.423083, ring):
                        woods = True
            if props.get("natural") == "wetland" and not props.get("name"):
                for ring in rings_of(geom):
                    if pip(-97.688346, 30.194954, ring):
                        east_bosque = True
            if props.get("natural") == "scrub" and not props.get("name"):
                for ring in rings_of(geom):
                    if pip(-97.745559, 30.048502, ring):
                        east_scrub = True
            if props.get("natural") == "peak" and geom.get("type") == "Point":
                lon, lat = geom["coordinates"][:2]
                if (
                    props.get("name") == "Barton Hill"
                    and abs(lat - 30.065769) < 1e-6
                    and abs(lon - (-97.882228)) < 1e-6
                ):
                    east_peak = True
        self.assertTrue(woods, "glass east woodland hold is not inside Beaukiss Woods")
        self.assertTrue(east_bosque, "glass east bosque hold is not inside an unnamed wetland")
        self.assertTrue(east_peak, "glass east peak hold is not Barton Hill")
        self.assertTrue(east_scrub, "glass east scrub hold is not inside unnamed east scrub")

        nm = json.loads((PACK_ROOT / "nm" / "layers" / "ground.geojson").read_text())
        botanic_hit = False
        nm_wildlife_hit = False
        nm_cave_hit = False
        for feat in nm["features"]:
            props = feat.get("properties") or {}
            kind = ground.overlay_kind(props)
            for ring in rings_of(feat.get("geometry") or {}):
                if kind == "botanic" and pip(-106.680958, 35.093625, ring):
                    botanic_hit = props.get("name") == "Albuquerque BioPark Botanic Garden"
                if kind == "wildlife" and pip(-107.319389, 35.327562, ring):
                    nm_wildlife_hit = props.get("name") == "Marquez Wildlife Management Area"
                if kind == "cave" and pip(-107.344750, 34.750796, ring):
                    nm_cave_hit = (
                        props.get("name")
                        == "Pronoun Cave Area of Critical Environmental Concern"
                    )
        self.assertTrue(
            botanic_hit, "glass botanic hold is not inside BioPark"
        )
        self.assertTrue(
            nm_wildlife_hit, "glass NM wildlife hold is not inside Marquez"
        )
        self.assertTrue(
            nm_cave_hit, "glass NM cave hold is not inside Pronoun Cave"
        )

        peak = False
        for feat in osm["features"]:
            props = feat.get("properties") or {}
            geom = feat.get("geometry") or {}
            if props.get("natural") != "peak" or geom.get("type") != "Point":
                continue
            lon, lat = geom["coordinates"][:2]
            if (
                props.get("name") == "Mount Franklin"
                and abs(lat - 31.832051) < 1e-6
                and abs(lon - (-106.492210)) < 1e-6
            ):
                peak = True
        self.assertTrue(peak, "glass west peak hold is not Mount Franklin")

        nm_reserve_hit = False
        for feat in nm["features"]:
            props = feat.get("properties") or {}
            kind = ground.overlay_kind(props)
            for ring in rings_of(feat.get("geometry") or {}):
                if kind == "reserve" and pip(-107.025703, 35.846906, ring):
                    nm_reserve_hit = (
                        props.get("name")
                        == "Jones Canyon Area of Critical Environmental Concern"
                    )
        self.assertTrue(
            nm_reserve_hit, "glass NM open-reserve hold is not inside Jones Canyon"
        )

        nm_mesa_hit = False
        for feat in nm["features"]:
            props = feat.get("properties") or {}
            kind = ground.overlay_kind(props)
            for ring in rings_of(feat.get("geometry") or {}):
                if kind == "reserve" and pip(-106.774776, 35.149083, ring):
                    nm_mesa_hit = props.get("name") == "Paseo de la Mesa Open Space"
        self.assertTrue(
            nm_mesa_hit,
            "SOLO_QA Paseo de la Mesa hold is not inside the named nature reserve",
        )

        nm_golden_hit = False
        for feat in nm["features"]:
            props = feat.get("properties") or {}
            kind = ground.overlay_kind(props)
            for ring in rings_of(feat.get("geometry") or {}):
                if kind == "reserve" and pip(-106.332577, 35.257427, ring):
                    nm_golden_hit = props.get("name") == "Golden Open Space"
        self.assertTrue(
            nm_golden_hit,
            "SOLO_QA Golden Open Space hold is not inside the named open space",
        )

        nm_scenic_hit = False
        for feat in nm["features"]:
            props = feat.get("properties") or {}
            kind = ground.overlay_kind(props)
            for ring in rings_of(feat.get("geometry") or {}):
                if kind == "reserve" and pip(-106.444016, 35.155131, ring):
                    nm_scenic_hit = props.get("name") == "Bear Canyon Scenic Easement"
        self.assertTrue(
            nm_scenic_hit,
            "SOLO_QA Bear Canyon Scenic Easement hold is not inside the scenic easement",
        )

        nm_tierra_hit = False
        for feat in nm["features"]:
            props = feat.get("properties") or {}
            kind = ground.overlay_kind(props)
            for ring in rings_of(feat.get("geometry") or {}):
                if kind == "reserve" and pip(-105.953136, 35.722229, ring):
                    nm_tierra_hit = props.get("name") == "La Tierra Trails"
        self.assertTrue(
            nm_tierra_hit,
            "SOLO_QA La Tierra Trails hold is not inside the trail system",
        )

        nm_sun_hit = False
        for feat in nm["features"]:
            props = feat.get("properties") or {}
            kind = ground.overlay_kind(props)
            for ring in rings_of(feat.get("geometry") or {}):
                if kind == "reserve" and pip(-105.912801, 35.662198, ring):
                    nm_sun_hit = props.get("name") == "Sun Mountain"
        self.assertTrue(
            nm_sun_hit,
            "SOLO_QA Sun Mountain hold is not inside the slope sheet",
        )

        nm_osm = json.loads((PACK_ROOT / "nm" / "osm.geojson").read_text())
        nm_wood = False
        nm_bosque = False
        nm_peak = False
        nm_scrub = False
        for feat in nm_osm["features"]:
            props = feat.get("properties") or {}
            geom = feat.get("geometry") or {}
            if props.get("name") == "Isleta Rectangle":
                for ring in rings_of(geom):
                    if pip(-106.320316, 34.939900, ring):
                        nm_wood = True
            if props.get("natural") == "wetland" and not props.get("name"):
                for ring in rings_of(geom):
                    if pip(-105.915768, 34.628816, ring):
                        nm_bosque = True
            if (
                props.get("natural") == "scrub"
                and props.get("name") == "Cerro Pelado Burn Scar"
            ):
                for ring in rings_of(geom):
                    if pip(-106.573932, 35.785371, ring):
                        nm_scrub = True
            if props.get("natural") == "peak" and geom.get("type") == "Point":
                lon, lat = geom["coordinates"][:2]
                if (
                    props.get("name") == "La Cruz Peak"
                    and abs(lat - 34.392837) < 1e-6
                    and abs(lon - (-107.420040)) < 1e-6
                ):
                    nm_peak = True
        self.assertTrue(nm_wood, "glass NM woodland hold is not inside Isleta Rectangle")
        self.assertTrue(nm_bosque, "glass NM bosque hold is not inside an unnamed wetland")
        self.assertTrue(nm_peak, "glass NM peak hold is not La Cruz Peak")
        self.assertTrue(nm_scrub, "glass NM scrub hold is not inside Cerro Pelado Burn Scar")

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
        cave_do = by_id["cave-dark"]["steps"][0]["do"]["en"].lower()
        self.assertIn("hole", cave_do)
        self.assertIn("cold", cave_do)
        self.assertIn("do not go in alone", cave_do)
        field_py = (ROOT / "tools/v3/field.py").read_text()
        self.assertIn("def plant_danger_do_en", field_py)
        self.assertIn("plant_danger_do_en(cid)", field_py)
        self.assertIn("Oleander or Texas mountain laurel", field_py)
        self.assertIn("A hole, sink, or cave mouth", field_py)

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
        self.assertIn("tx-east-snake", qa)
        self.assertIn("aspen is high country", qa.lower())
        self.assertIn("food stays on wildlife range", qa)
        self.assertIn("south-side shade", qa.lower())
        self.assertIn("wind break", qa.lower())
        self.assertIn("Give it room", qa)
        self.assertIn("Sierra de Ciudad Juárez", qa)
        self.assertIn("Cerro Pelado Burn Scar", qa)
        self.assertIn("SPEAK names that pack", qa)
        self.assertIn("SPEAK names oleander", qa)
        self.assertIn("dark, still air, cold", qa)
        self.assertIn("tree-use card", qa)
        self.assertIn("FIELD · ANIMAL", qa)
        self.assertIn("FIELD · ANIMAL", qa)
        self.assertIn("NEXT · COLD", qa)
        self.assertIn("Peak walk includes bite treatment", qa)
        self.assertIn("ANIMAL · BITE · COLD", qa)
        self.assertIn("CAVE · COLD", qa)
        self.assertIn("coyote and deer range", qa)
        self.assertIn("Stay in daylight", qa)
        self.assertIn("black bear and elk", qa)
        self.assertIn("javelina / coyote", qa)
        self.assertIn("cottonmouth", qa)
        self.assertIn("Irrigated ground", qa)
        self.assertIn("Not javelina country", qa)
        self.assertIn("Glasshouse", qa)
        self.assertIn("Hold DO names oleander", qa)
        self.assertIn("not plant-use", qa)
        self.assertIn("Vickery Wholesale Greenhouse", qa)
        self.assertIn("glasshouse", qa)
        self.assertIn("Discovery Well Cave Preserve", qa)
        self.assertIn("Buttercup Creek Cave Preserve", qa)
        self.assertIn("30.494626", qa)
        self.assertIn("35.093625", qa)
        self.assertIn("33.157743", qa)
        self.assertIn("30.490391", qa)
        self.assertIn("vertex-avg sits off the sheet", qa)
        self.assertIn("Blowing Sink", qa)
        self.assertIn("Indiangrass Wildlife Sanctuary", qa)
        self.assertIn("Bee Cave Central Park", qa)
        self.assertIn("Marquez Wildlife Management Area", qa)
        self.assertIn("Wildlife Drive", qa)
        self.assertIn("State Game Commission Land", qa)
        self.assertIn("loblolly", qa)
        self.assertIn("Colorado River Park Wildlife Sanctuary", qa)
        self.assertIn("ANIMAL · BITE · FOOD · PLANT", qa)
        self.assertIn("give it the road", qa)
        self.assertIn("Botanic garden", qa)
        self.assertIn("Cactus garden", qa)
        self.assertIn("tx-cactus", qa)
        self.assertIn("Walk does not open plant-danger", qa)
        self.assertIn("pear still", qa.lower())
        self.assertIn("Albuquerque BioPark Botanic Garden", qa)
        self.assertIn("not jumping cholla", qa)
        self.assertIn("Chihuahuan Desert Conservatory", qa)
        self.assertIn("Conservatory At North Austin", qa)
        self.assertIn("Three Crosses Cactus Garden", qa)
        self.assertIn("Desert Garden Park", qa)
        self.assertIn("Barelas Community Garden", qa)
        self.assertIn("Beer Garden", qa)
        self.assertIn("Open reserve", qa)
        self.assertIn("Alamo Mountain Area of Critical Environmental Concern", qa)
        self.assertIn("Jones Canyon Area of Critical Environmental Concern", qa)
        self.assertIn("Paseo de la Mesa Open Space", qa)
        self.assertIn("35.149083", qa)
        self.assertIn("Golden Open Space", qa)
        self.assertIn("35.257427", qa)
        self.assertIn("Bachechi Open Space", qa)
        self.assertIn("Bear Canyon Scenic Easement", qa)
        self.assertIn("35.155131", qa)
        self.assertIn("La Tierra Trails", qa)
        self.assertIn("35.722229", qa)
        self.assertIn("Sun Mountain", qa)
        self.assertIn("35.662198", qa)
        self.assertIn("Hueco Tanks State Park and Historic Site", qa)
        self.assertIn("31.911873", qa)
        self.assertIn("Hueco Mountain Park", qa)
        self.assertIn("Decker Tallgrass Prairie Preserve", qa)
        self.assertIn("Wild Basin Wilderness Preserve", qa)
        self.assertIn("Barrow Nature Preserve", qa)
        self.assertIn("Stillhouse Hollow Nature Preserve", qa)
        self.assertIn("Big Walnut Creek Nature Preserve", qa)
        self.assertIn("Bright Leaf Natural Area", qa)
        self.assertIn("Beaukiss Woods", qa)
        self.assertIn("Isleta Rectangle", qa)
        self.assertIn("Rio Bosque Wetlands Park", qa)
        self.assertIn("Rose Garden", qa)
        self.assertIn("Mount Franklin", qa)
        self.assertIn("Barton Hill", qa)
        self.assertIn("La Cruz Peak", qa)
        self.assertIn("Rio Grande Nature Center State Park", qa)
        self.assertIn("Open Space Visitor Center", qa)
        self.assertIn("Godzilla Preserve", qa)
        self.assertIn("Wilderness Gate", qa)
        self.assertIn("Prairie Hills", qa)
        self.assertIn("BITE · ANIMAL · PLANT · FOOD · HEAT", qa)
        self.assertIn("Hold DO on wildlife range names the food card", qa)
        self.assertIn("Hold DO on wildlife range names give it the road", qa)
        self.assertIn("Hold DO on wildlife range names cook through or leave it", qa)
        self.assertIn("Hold DO on wildlife range names no ice, no cut, no suck", qa)
        self.assertIn("Hold DO names give it the road", qa)
        self.assertIn("no ice, no cut, no suck", qa)
        self.assertIn("Brush off, then water", qa)
        self.assertIn("Comb glochids out", qa)
        self.assertIn("Give it room", qa)
        self.assertIn("wind break", qa.lower())
        self.assertIn("Peak DO does not name the bite card", qa)

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
            snake_cards = [
                c
                for c in book["cards"]
                if c["id"] in {f"{state}-snake", f"{state}-east-snake"}
            ]
            snake_blob = json.dumps(snake_cards).lower()
            for name in kinds.get("snake", []):
                self.assertTrue(
                    name.split()[0] in snake_blob or name in snake_blob,
                    f"{state} snake cards missing vision snake {name}",
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
        mammal_still = vision_fn.split("case .mammal:", 1)[1].split("case .tree:", 1)[0]
        self.assertIn(
            "biteCard",
            mammal_still,
            "a mammal still includes bite treatment, like a snake still",
        )
        self.assertNotIn("plantTXCard", mammal_still)
        cactus_still = vision_fn.split("case .cactus:", 1)[1]
        self.assertNotIn(
            "plantTXCard",
            cactus_still,
            "a prickly-pear still is the cactus card, not oleander",
        )
        self.assertNotIn("plantNMCard", cactus_still)
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
        self.assertIn("bite treatment", qa)
        self.assertIn("tx-plant-danger", qa)

    def test_the_field_tree_card_names_the_hold_trees(self):
        """Hold woodland and bosque name trees. FIELD · PLANT must name the same ones.

        Cottonwood is bosque range the hold already speaks. It is not a GPS pin
        and not an edible unlock. NM Field must name the Vision Rio Grande
        cottonwood. West titles stay pack-true, like the west snake card.
        """
        hold = SWIFT.read_text()
        self.assertIn("Rio Grande cottonwood, juniper, piñon", hold)
        self.assertIn("Cottonwoods and pecan along the water", hold)
        notes = CARD.read_text().split("if let note")[1].split("Spacer")[0]
        self.assertIn(
            ".lineLimit(6)",
            notes,
            "four lines clips woodland deadfall and wildlife cook-through on a phone",
        )

        def blob(state: str, cid: str) -> str:
            book = json.loads((ROOT / f"Resources/Field/field.{state}.json").read_text())
            return json.dumps(
                next(c for c in book["cards"] if c["id"] == cid),
                ensure_ascii=False,
            ).lower()

        nm = blob("nm", "nm-tree-use")
        self.assertIn("cottonwood", nm)
        self.assertIn("rio grande cottonwood", nm)
        self.assertIn("juniper", nm)
        self.assertIn("piñon", nm)
        self.assertIn("aspen", nm)
        self.assertNotIn("edible", nm)
        nm_do = json.loads((ROOT / "Resources/Field/field.nm.json").read_text())
        nm_tree_do = next(c for c in nm_do["cards"] if c["id"] == "nm-tree-use")["steps"][0]["do"]["en"].lower()
        self.assertIn("rio grande cottonwood", nm_tree_do)
        self.assertIn("high country", nm_tree_do)

        west = blob("tx", "tx-tree-use")
        self.assertIn("mesquite", west)
        self.assertIn("cottonwood", west)
        self.assertIn("west texas trees", west)
        self.assertNotIn("edible", west)
        west_tree_do = json.loads((ROOT / "Resources/Field/field.tx.json").read_text())
        west_do = next(c for c in west_tree_do["cards"] if c["id"] == "tx-tree-use")["steps"][0]["do"]["en"].lower()
        self.assertIn("mesquite", west_do)
        self.assertIn("live oak", west_do)

        east = blob("tx", "tx-east-tree-use")
        self.assertIn("loblolly", east)
        self.assertIn("cottonwood", east)
        self.assertNotIn("mesquite", east)
        self.assertNotIn("edible", east)
        east_do = next(c for c in west_tree_do["cards"] if c["id"] == "tx-east-tree-use")["steps"][0]["do"]["en"].lower()
        self.assertIn("loblolly", east_do)
        self.assertNotIn("mesquite", east_do)

        west_mammal = blob("tx", "tx-mammal")
        self.assertIn("west texas mammals", west_mammal)
        self.assertIn("javelina", west_mammal)

        qa = (ROOT / "docs/SOLO_QA.md").read_text()
        self.assertIn("nm-tree-use", qa)
        self.assertIn("Rio Grande cottonwood", qa)
        self.assertIn("West Texas trees", qa)

    def test_nm_hold_names_the_field_rattlesnakes_and_mammals(self):
        """NM Field and Vision name prairie rattler, diamondback, and mule deer.

        Hold scrub opens the bite card. Wildlife range opens the mammal card.
        Range speech, not a GPS pin, not an edible unlock.
        """
        do = SWIFT.read_text()
        animal = do.split("private static func animalRangeLine", 1)[1].split(
            "private static func plantDangerLine", 1
        )[0]
        west_scrub = animal.split("case .txWest:", 1)[1].split("case .txEast:", 1)[0].lower()
        self.assertIn("diamondback", west_scrub)
        self.assertIn("javelina", west_scrub)
        self.assertIn("the bite card", west_scrub)
        self.assertIn("no ice, no cut, no suck", west_scrub)
        self.assertIn("give it room", west_scrub)
        self.assertNotIn("cottonmouth", west_scrub)
        nm_scrub = animal.split("case .nm:", 1)[1].split("case .unknown:", 1)[0].lower()
        self.assertIn("prairie rattler", nm_scrub)
        self.assertIn("diamondback", nm_scrub)
        self.assertIn("cholla", nm_scrub)
        self.assertIn("sotol", nm_scrub)
        self.assertIn("the bite card", nm_scrub)
        self.assertIn("no ice, no cut, no suck", nm_scrub)
        self.assertIn("give it room", nm_scrub)
        self.assertNotIn("lives here", nm_scrub)
        east_scrub = animal.split("case .txEast:", 1)[1].split("case .nm:", 1)[0].lower()
        self.assertIn("cottonmouth", east_scrub)
        self.assertIn("hog", east_scrub)
        self.assertIn("the bite card", east_scrub)
        self.assertIn("no ice, no cut, no suck", east_scrub)
        self.assertIn("give it room", east_scrub)
        self.assertNotIn("javelina", east_scrub)
        wildlife = do.split('case "Wildlife range":', 1)[1].split(
            'case "Bosque or wetland":', 1
        )[0]
        nm_range = wildlife.split("case .nm:", 1)[1].split("case .unknown:", 1)[0].lower()
        self.assertIn("mule deer", nm_range)
        self.assertIn("black bear", nm_range)
        self.assertIn("elk", nm_range)
        self.assertIn("prairie rattler", nm_range)
        self.assertIn("diamondback", nm_range)
        self.assertIn("the bite card", nm_range)
        self.assertIn("the food card", nm_range)
        self.assertIn("give it the road", nm_range)
        self.assertIn("cook through or leave it", nm_range)
        self.assertIn("no ice, no cut, no suck", nm_range)
        self.assertNotIn("cottonwood", nm_range)
        self.assertNotIn("lives here", nm_range)

        book = json.loads((ROOT / "Resources/Field/field.nm.json").read_text())
        snake = json.dumps(
            next(c for c in book["cards"] if c["id"] == "nm-snake")
        ).lower()
        self.assertIn("diamondback", snake)
        self.assertIn("prairie", snake)
        snake_do = next(c for c in book["cards"] if c["id"] == "nm-snake")["steps"][0]["do"]["en"].lower()
        self.assertIn("prairie rattler", snake_do)
        self.assertIn("diamondback", snake_do)
        mammal_card = next(c for c in book["cards"] if c["id"] == "nm-mammal")
        mammal = json.dumps(mammal_card).lower()
        self.assertIn("mule deer", mammal)
        self.assertIn("black bear", mammal)
        self.assertNotIn("edible", mammal)
        nm_do = mammal_card["steps"][0]["do"]["en"].lower()
        self.assertIn("mule deer", nm_do)
        self.assertIn("give it the road", nm_do)
        self.assertIn(
            "the bite card",
            nm_do,
            "NM mammal SPEAK names the bite card, like Texas",
        )
        self.assertIn("the food card", nm_do)
        self.assertNotIn("food-game card", nm_do)

        qa = (ROOT / "docs/SOLO_QA.md").read_text()
        self.assertIn("Prairie rattler", qa)
        self.assertIn("diamondback", qa)
        self.assertIn("NM mammal SPEAK names the bite card", qa)
        self.assertIn("Hold DO on wildlife range names the bite card", qa)
        self.assertIn("Hold DO on wildlife range names the food card", qa)
        self.assertIn("Hold DO on wildlife range names give it the road", qa)
        self.assertIn("Hold DO on wildlife range names cook through or leave it", qa)
        self.assertIn("Hold DO on wildlife range names no ice, no cut, no suck", qa)
        self.assertIn("Hold DO names give it the road", qa)
        self.assertIn("no ice, no cut, no suck", qa)
        self.assertIn("Brush off, then water", qa)
        self.assertIn("Comb glochids out", qa)
        self.assertIn("Give it room", qa)
        self.assertIn("wind break", qa.lower())
        self.assertIn("Peak DO does not name the bite card", qa)

    def test_wildlife_range_names_the_pack_mammal_book(self):
        """Wildlife range opens FIELD · ANIMAL. Hold names that pack's mammals.

        Range, not a pin. Neighborhood parks named after trees stay parks.
        """
        do = SWIFT.read_text()
        wildlife = do.split('case "Wildlife range":', 1)[1].split(
            'case "Bosque or wetland":', 1
        )[0]
        west = wildlife.split("case .txWest:", 1)[1].split("case .txEast:", 1)[0].lower()
        self.assertIn("javelina", west)
        self.assertIn("coyote", west)
        self.assertIn("deer", west)
        self.assertIn("diamondback", west)
        self.assertIn("the bite card", west)
        self.assertIn("the food card", west)
        self.assertIn("give it the road", west)
        self.assertIn("cook through or leave it", west)
        self.assertIn("no ice, no cut, no suck", west)
        self.assertNotIn("cottonwood", west)
        self.assertNotIn("mesquite", west)
        self.assertNotIn("oleander", west)
        self.assertNotIn("cottonmouth", west)
        self.assertNotIn("lives here", west)
        east = wildlife.split("case .txEast:", 1)[1].split("case .nm:", 1)[0].lower()
        self.assertIn("hog", east)
        self.assertIn("deer", east)
        self.assertIn("copperhead", east)
        self.assertIn("cottonmouth", east)
        self.assertIn("the bite card", east)
        self.assertIn("the food card", east)
        self.assertIn("give it the road", east)
        self.assertIn("cook through or leave it", east)
        self.assertIn("no ice, no cut, no suck", east)
        self.assertNotIn("javelina", east)
        self.assertNotIn("diamondback", east)
        self.assertNotIn("cottonwood", east)
        nm = wildlife.split("case .nm:", 1)[1].split("case .unknown:", 1)[0].lower()
        self.assertIn("mule deer", nm)
        self.assertIn("black bear", nm)
        self.assertIn("prairie rattler", nm)
        self.assertIn("diamondback", nm)
        self.assertIn("the bite card", nm)
        self.assertIn("the food card", nm)
        self.assertIn("give it the road", nm)
        self.assertIn("cook through or leave it", nm)
        self.assertIn("no ice, no cut, no suck", nm)
        self.assertNotIn("cottonwood", nm)

        west_mammal_card = next(
            c
            for c in json.loads((ROOT / "Resources/Field/field.tx.json").read_text())["cards"]
            if c["id"] == "tx-mammal"
        )
        west_mammal = json.dumps(west_mammal_card).lower()
        self.assertIn("javelina", west_mammal)
        self.assertIn("white-tailed deer", west_mammal)
        self.assertNotIn("edible", west_mammal)
        west_do = west_mammal_card["steps"][0]["do"]["en"].lower()
        self.assertIn("white-tailed deer", west_do)
        self.assertIn("give it the road", west_do)
        self.assertIn("the bite card", west_do)
        self.assertIn("the food card", west_do)
        self.assertNotIn("food-game card", west_do)
        west_game = next(
            c
            for c in json.loads((ROOT / "Resources/Field/field.tx.json").read_text())["cards"]
            if c["id"] == "tx-game"
        )
        west_game_do = west_game["steps"][0]["do"]["en"].lower()
        self.assertIn("javelina", west_game_do)
        self.assertIn("white-tailed deer", west_game_do)
        self.assertIn("do not hunt", west_game_do)
        self.assertNotIn("edible", west_game_do)

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
        self.assertIn("feral hog", by_id["tx-east-game"]["steps"][0]["do"]["en"].lower())
        east_snake = json.dumps(by_id["tx-east-snake"]).lower()
        self.assertIn("copperhead", east_snake)
        self.assertIn("cottonmouth", east_snake)
        east_snake_do = by_id["tx-east-snake"]["steps"][0]["do"]["en"].lower()
        self.assertIn("copperhead", east_snake_do)
        self.assertIn("cottonmouth", east_snake_do)
        west_snake = json.dumps(by_id["tx-snake"]).lower()
        self.assertIn("diamondback", west_snake)
        self.assertNotIn("cottonmouth", west_snake)
        self.assertNotIn("copperhead", west_snake)
        west_snake_do = by_id["tx-snake"]["steps"][0]["do"]["en"].lower()
        self.assertIn("diamondback", west_snake_do)
        self.assertNotIn("cottonmouth", west_snake_do)
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
