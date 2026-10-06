#!/usr/bin/env python3
"""Flock ALPR on the packed desk. Same red/blue disc as CCTV. No public still."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

OLEASTER = (31.87050, -106.59732)
ABQ = (35.104, -106.650)
AUSTIN = (30.267, -97.743)


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


def haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    from math import asin, cos, radians, sin, sqrt

    lat1, lon1 = map(radians, a)
    lat2, lon2 = map(radians, b)
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    h = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2
    return 6371 * 2 * asin(sqrt(h))


SAMPLE = {
    "elements": [
        {
            "type": "node",
            "id": 3862265063,
            "lat": 30.3913369,
            "lon": -97.9335198,
            "tags": {
                "man_made": "surveillance",
                "surveillance:type": "ALPR",
                "manufacturer": "Flock Safety",
                "addr:street": "Bee Cave Road",
            },
        },
        {
            "type": "node",
            "id": 9,
            "lat": 31.76,
            "lon": -106.48,
            "tags": {
                "man_made": "surveillance",
                "operator:wikidata": "Q104850242",
                "name": "Mesa",
            },
        },
        {
            "type": "node",
            "id": 8,
            "lat": 31.76,
            "lon": -106.48,
            "tags": {
                "man_made": "surveillance",
                "surveillance:type": "ALPR",
                "manufacturer": "Motorola",
            },
        },
        {
            "type": "way",
            "id": 1,
            "tags": {"manufacturer": "Flock Safety"},
        },
        {
            "type": "node",
            "id": 11,
            "lat": 30.267,
            "lon": -97.743,
            "tags": {
                "man_made": "surveillance",
                "manufacturer": "Flock Safety",
                "name": "Flock Safety",
                "addr:street": "South Congress",
            },
        },
    ]
}


class FlockParseTests(unittest.TestCase):
    def test_overpass_nodes_become_location_marks_not_a_still(self):
        from v3.cams import parse_flock

        rows = parse_flock(SAMPLE)
        self.assertEqual(len(rows), 3)
        by_id = {row["id"]: row for row in rows}
        bee = by_id["flock-n3862265063"]
        self.assertEqual(bee["provider"], "Flock")
        self.assertEqual(bee["ink"], "blue")
        self.assertEqual(bee["url"], "")
        self.assertEqual(bee["name"], "Bee Cave Road")
        self.assertAlmostEqual(bee["lat"], 30.3913369)
        mesa = by_id["flock-n9"]
        self.assertEqual(mesa["name"], "Mesa")
        self.assertEqual(mesa["provider"], "Flock")
        congress = by_id["flock-n11"]
        self.assertEqual(congress["name"], "South Congress")
        self.assertEqual(congress["provider"], "Flock")
        self.assertEqual(congress["url"], "")
        self.assertNotIn("flock-n8", by_id)
        self.assertFalse(any(row["url"].startswith("http") for row in rows))


class FlockPackTests(unittest.TestCase):
    def test_every_walkable_pack_paints_flock_marks(self):
        expect = {
            "tx-west": (OLEASTER, 25, 8),
            "tx-east": (AUSTIN, 25, 40),
            "nm": (ABQ, 40, 8),
        }
        for pid, (center, km, floor) in expect.items():
            rows = json.loads((ROOT / "Resources" / "Packs" / pid / "cameras.json").read_text())
            flock = [row for row in rows if row.get("provider") == "Flock"]
            self.assertGreaterEqual(len(flock), floor, pid)
            near = [
                row
                for row in flock
                if haversine_km(center, (row["lat"], row["lon"])) <= km
            ]
            self.assertGreaterEqual(len(near), 1, f"{pid} has no Flock within {km} km")
            ids = set()
            for row in flock:
                self.assertTrue(row["id"].startswith("flock-n"), row["id"])
                self.assertEqual(row["url"], "")
                self.assertIn(row["ink"], ("red", "blue"))
                self.assertTrue(row["name"])
                self.assertNotIn(row["id"], ids)
                ids.add(row["id"])
            stills = [row for row in rows if row.get("provider") != "Flock"]
            self.assertTrue(stills, pid)
            for row in stills:
                self.assertTrue(row["url"].startswith("https://"), row["id"])

    def test_harvest_and_glass_keep_flock_off_the_still_pipe(self):
        src = read("tools", "v3", "cams.py")
        desk = read("Blackout", "CamDesk.swift")
        sock = read("Blackout", "UpdateSocket.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("def parse_flock(", src)
        self.assertIn("def load_flock(", src)
        self.assertIn("load_flock(", src.split("def pack_cameras")[1])
        self.assertIn('provider": "Flock"', src)
        self.assertNotIn("deflock", src.lower())
        self.assertNotIn("flocksafety", src.lower())
        feeds = desk.split("static func feeds(")[1].split("static func sections(")[0]
        self.assertIn("hasPrefix(\"https://\")", feeds)
        marks = desk.split("static func marks(")[1].split("static func naUnlocks")[0]
        self.assertIn("reachable(pack: pack, hops: hops)", marks)
        self.assertIn("cam.url.hasPrefix(\"https://\")", sock.split("func snapTargets")[1])
        self.assertIn("Flock", qa)
        self.assertIn("NO STILL", qa)
        agents = read("AGENTS.md")
        validate = read("tools", "validate_v3.py")
        self.assertIn("test_flock_cams.py", agents)
        self.assertIn("test_flock_cams.py", validate)
        self.assertIn("flock_cams()", validate)


if __name__ == "__main__":
    unittest.main()
