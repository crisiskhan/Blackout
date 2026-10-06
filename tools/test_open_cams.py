#!/usr/bin/env python3
"""Open official still catalogs on the packed desk. Same SNAP as CCTV.

NMDOT 511 GetCameraInfo / GetCameraImage. Every TxDOT district, clipped.
Never a live stream. Never an empty NM pack while the catalog is public.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

ABQ = (35.104, -106.650)
LAS_CRUCES = (32.312, -106.778)
OLEASTER = (31.87050, -106.59732)


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


SAMPLE_NMDOT = {
    "cameraInfo": [
        {
            "mobile": False,
            "enabled": True,
            "lon": -106.244,
            "lat": 35.506001,
            "title": "I-25 @ Lower La Bajada",
            "name": "I-25@La_Bajada_Lower",
            "cameraType": "iDome",
            "videoServer": "rtmp://video.nmroads.com/nmroads",
            "snapshotFile": "http://ss.nmroads.com/snapshots/i25_lowerlabajada.jpg",
        },
        {
            "mobile": True,
            "enabled": True,
            "lon": -106.65,
            "lat": 35.10,
            "title": "Portable",
            "name": "portable_1",
        },
        {
            "mobile": False,
            "enabled": False,
            "lon": -106.65,
            "lat": 35.10,
            "title": "Dark",
            "name": "dark_1",
        },
        {
            "mobile": False,
            "enabled": True,
            "lon": 0,
            "lat": 0,
            "title": "Null island",
            "name": "null_1",
        },
    ]
}


class NmdotParseTests(unittest.TestCase):
    def test_get_camera_info_becomes_https_stills_not_a_stream(self):
        from v3.cams import parse_nmdot

        rows = parse_nmdot(SAMPLE_NMDOT)
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["provider"], "NMDOT")
        self.assertEqual(row["ink"], "blue")
        self.assertEqual(row["name"], "I-25 @ Lower La Bajada")
        self.assertTrue(row["id"].startswith("nmdot-"))
        self.assertTrue(row["url"].startswith("https://servicev5.nmroads.com/RealMapWAR/GetCameraImage"))
        self.assertIn("cameraName=", row["url"])
        self.assertIn("I-25", row["url"])
        self.assertNotIn("rtmp", row["url"])
        self.assertNotIn("http://ss.nmroads.com", row["url"])
        self.assertFalse(row["url"].startswith("http://"))

    def test_still_jpeg_accepts_a_raw_nmdot_frame(self):
        from v3.cams import still_jpeg

        jpeg = bytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
        self.assertEqual(still_jpeg(jpeg)[:3], b"\xff\xd8\xff")


class PackOpenCamTests(unittest.TestCase):
    def test_harvest_hits_nmdot_and_every_txdot_district(self):
        src = read("tools", "v3", "cams.py")
        self.assertIn("GetCameraInfo", src)
        self.assertIn("GetCameraImage", src)
        self.assertIn("def parse_nmdot(", src)
        self.assertIn("def load_nmdot(", src)
        self.assertIn("load_nmdot()", src)
        self.assertNotIn("NM has no public camera JSON", src)
        for district in ("ELP", "AUS", "ODA", "SAT", "LBB", "LRD"):
            self.assertIn(f'"{district}"', src)
        pack = src.split("def pack_cameras")[1].split("def write_cams")[0]
        self.assertIn("TXDOT_DISTRICTS", pack)
        self.assertIn("load_nmdot()", pack)
        self.assertNotIn("PACK_DISTRICTS.get", pack)
        catalog_fn = read("tools", "v3", "fetch_packs.py").split("def write_catalog")[1].split(
            "def fetch_pack"
        )[0]
        self.assertIn('"states"', catalog_fn)
        ids = [
            p.get("id")
            for p in json.loads((ROOT / "Resources" / "Packs" / "catalog.json").read_text()).get(
                "packs"
            )
            or []
        ]
        self.assertEqual(ids, ["tx-west", "tx-east", "nm", "states"])

    def test_nm_paints_albuquerque_nmdot_stills(self):
        rows = json.loads((ROOT / "Resources" / "Packs" / "nm" / "cameras.json").read_text())
        self.assertGreaterEqual(len(rows), 80)
        nmdot = [row for row in rows if row.get("provider") == "NMDOT"]
        self.assertGreaterEqual(len(nmdot), 80)
        near = [
            row
            for row in nmdot
            if haversine_km(ABQ, (row["lat"], row["lon"])) <= 40
        ]
        self.assertGreaterEqual(len(near), 20, "Albuquerque has no packed NMDOT within 40 km")
        for row in rows:
            if row.get("provider") == "Flock":
                self.assertEqual(row["url"], "")
                continue
            self.assertTrue(row["url"].startswith("https://"))
            self.assertNotIn("rtmp", row["url"])
            self.assertNotIn("video.nmroads.com", row["url"])
            self.assertIn(row["ink"], ("red", "blue"))
        self.assertTrue(any("GetCameraImage" in row["url"] for row in nmdot))

    def test_tx_west_adds_las_cruces_nmdot_next_to_el_paso_txdot(self):
        rows = json.loads((ROOT / "Resources" / "Packs" / "tx-west" / "cameras.json").read_text())
        nmdot = [row for row in rows if row.get("provider") == "NMDOT"]
        txdot = [row for row in rows if "its.txdot.gov" in row["url"]]
        self.assertGreaterEqual(len(txdot), 40)
        self.assertGreaterEqual(len(nmdot), 8)
        near_lc = [
            row
            for row in nmdot
            if haversine_km(LAS_CRUCES, (row["lat"], row["lon"])) <= 30
        ]
        self.assertGreaterEqual(len(near_lc), 3, "Las Cruces has no packed NMDOT within 30 km")
        near_elp = [
            row
            for row in txdot
            if haversine_km(OLEASTER, (row["lat"], row["lon"])) <= 25
        ]
        self.assertGreaterEqual(len(near_elp), 1)
        self.assertTrue(any("GetCameraImage" in row["url"] for row in nmdot))

    def test_no_live_pipe_on_the_glass(self):
        sock = read("Blackout", "UpdateSocket.swift")
        art = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "CctvArt.swift")
        self.assertIn("func stillJPEG", sock)
        self.assertIn("func snapTargets(", sock)
        self.assertNotIn("AVPlayer", sock)
        self.assertNotIn("WKWebView", sock)
        self.assertNotIn("rtmp", sock)
        self.assertIn("enum CctvArt", art)


class DeviceScriptTests(unittest.TestCase):
    def test_solo_qa_scores_nm_dots_not_an_empty_pack(self):
        qa = read("docs", "SOLO_QA.md")
        cctv = next(line for line in qa.splitlines() if "Packed CCTV" in line)
        self.assertIn("NMDOT", cctv)
        self.assertIn("Las Cruces", cctv)
        self.assertNotIn("NM has none", cctv)
        agents = read("AGENTS.md")
        self.assertIn("test_open_cams.py", agents)
        validate = read("tools", "validate_v3.py")
        self.assertIn("test_open_cams.py", validate)
        self.assertIn("open_cams()", validate)


if __name__ == "__main__":
    unittest.main()
