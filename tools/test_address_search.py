#!/usr/bin/env python3
"""MAP SEARCH finds every packed address. The card is the record, not a pin dump."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from v3 import addrfeat  # noqa: E402


class HouseQueryTests(unittest.TestCase):
    def test_number_plus_street_is_an_address_query(self):
        self.assertEqual(addrfeat.house_query("221 montana"), (221, ["montana"]))
        self.assertEqual(addrfeat.house_query("221 N Kansas St"), (221, ["n", "kansas", "st"]))
        self.assertEqual(addrfeat.house_query("221A Montana Avenue"), (221, ["montana", "avenue"]))

    def test_ordinal_street_is_not_a_house_number(self):
        self.assertIsNone(addrfeat.house_query("10th Street"))
        self.assertIsNone(addrfeat.house_query("21st"))
        self.assertIsNone(addrfeat.house_query("montana"))
        self.assertIsNone(addrfeat.house_query("221"))


class InterpolateTests(unittest.TestCase):
    def test_interpolates_along_the_range(self):
        lat, lon = addrfeat.interpolate(221, 201, 299, 31.76, -106.50, 31.78, -106.40)
        self.assertAlmostEqual(lat, 31.764, places=3)
        self.assertAlmostEqual(lon, -106.48, places=2)

    def test_parity_keeps_the_odd_side(self):
        self.assertTrue(addrfeat.hn_on_range(221, 201, 299))
        self.assertFalse(addrfeat.hn_on_range(220, 201, 299))
        self.assertTrue(addrfeat.hn_on_range(220, 200, 298))


class GeocodeTests(unittest.TestCase):
    def test_221_montana_lands_on_the_range(self):
        book = addrfeat.AddressBook.from_ranges(
            [
                {
                    "street": "Montana Avenue",
                    "from_hn": 201,
                    "to_hn": 299,
                    "zipcode": "79902",
                    "lat0": 31.777,
                    "lon0": -106.475,
                    "lat1": 31.779,
                    "lon1": -106.455,
                }
            ]
        )
        hit = book.geocode("221 montana")
        self.assertIsNotNone(hit)
        self.assertEqual(hit["kind"], "address")
        self.assertTrue(hit["name"].startswith("221 "))
        self.assertIn("Montana", hit["name"])
        self.assertEqual(hit["post"], "79902")
        self.assertEqual(hit["city"], "El Paso")
        self.assertGreaterEqual(hit["sure"], 70)
        self.assertIn("census", hit["why"].lower())

    def test_wrong_street_is_not_invented(self):
        book = addrfeat.AddressBook.from_ranges(
            [
                {
                    "street": "Montana Avenue",
                    "from_hn": 201,
                    "to_hn": 299,
                    "zipcode": "79902",
                    "lat0": 31.777,
                    "lon0": -106.475,
                    "lat1": 31.779,
                    "lon1": -106.455,
                }
            ]
        )
        self.assertIsNone(book.geocode("221 kansas"))


class PackedSearchTests(unittest.TestCase):
    """The phone book has to actually carry the ranges, not just the streets."""

    def test_tx_west_can_find_a_montana_house(self):
        blob = json.loads((ROOT / "Resources" / "Packs" / "tx-west" / "search.json").read_text())
        addr = blob.get("addr") or {}
        streets = addr.get("streets") or []
        ranges = addr.get("ranges") or []
        self.assertGreater(len(ranges), 1000, "tx-west search.json has no address ranges")
        folded = [s.casefold() for s in streets]
        self.assertTrue(any("montana" in s for s in folded), "Montana missing from addr streets")
        book = addrfeat.AddressBook.from_packed(blob)
        hit = book.geocode("221 montana")
        self.assertIsNotNone(hit)
        self.assertEqual(hit["kind"], "address")
        self.assertTrue(31.70 <= hit["lat"] <= 31.90)
        self.assertTrue(-106.62 <= hit["lon"] <= -106.35)

    def test_each_pack_ships_address_ranges(self):
        for pack_id in ("tx-west", "tx-east", "nm"):
            blob = json.loads((ROOT / "Resources" / "Packs" / pack_id / "search.json").read_text())
            ranges = (blob.get("addr") or {}).get("ranges") or []
            self.assertGreater(len(ranges), 500, f"{pack_id} search.json has no address ranges")
            names = {row[0] for row in blob.get("docs") or [] if isinstance(row, list) and row}
            if pack_id == "tx-west":
                self.assertIn("Montana Avenue", names)
                self.assertIn("Gardner Peak", names)


if __name__ == "__main__":
    unittest.main()
