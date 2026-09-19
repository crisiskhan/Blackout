#!/usr/bin/env python3
"""Packed CCTV access as red/blue dots. UPDATE SNAPs stills. Never a live stream."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

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


class PackCamTests(unittest.TestCase):
    def test_every_pack_ships_a_camera_list(self):
        for pid in ("tx-west", "tx-east", "nm"):
            path = ROOT / "Resources" / "Packs" / pid / "cameras.json"
            self.assertTrue(path.is_file(), pid)
            rows = json.loads(path.read_text())
            self.assertIsInstance(rows, list, pid)
            man = json.loads((ROOT / "Resources" / "Packs" / pid / "manifest.json").read_text())
            self.assertIn("cameras.json", man["files"], pid)

    def test_tx_west_has_el_paso_dot_cameras_near_oleaster(self):
        rows = json.loads((ROOT / "Resources" / "Packs" / "tx-west" / "cameras.json").read_text())
        self.assertGreaterEqual(len(rows), 40)
        near = [
            row
            for row in rows
            if haversine_km(OLEASTER, (row["lat"], row["lon"])) <= 25
        ]
        self.assertGreaterEqual(len(near), 1, "Oleaster Dr has no packed CCTV within 25 km")
        for row in rows:
            self.assertTrue(row["id"])
            self.assertTrue(row["url"].startswith("https://"))
            self.assertIn(row["ink"], ("red", "blue"))
            self.assertTrue(row["name"])
        self.assertTrue(any(row["ink"] == "blue" for row in rows))
        self.assertTrue(
            any("its.txdot.gov" in row["url"] for row in rows),
            "TX WEST must pack TxDOT ITS stills",
        )

    def test_tx_east_paints_city_red_and_dot_blue(self):
        rows = json.loads((ROOT / "Resources" / "Packs" / "tx-east" / "cameras.json").read_text())
        self.assertGreaterEqual(len(rows), 40)
        inks = {row["ink"] for row in rows}
        self.assertIn("red", inks)
        self.assertIn("blue", inks)
        self.assertTrue(any("austinmobility.io" in row["url"] for row in rows))
        self.assertTrue(any("its.txdot.gov" in row["url"] for row in rows))


class StillDecodeTests(unittest.TestCase):
    def test_txdot_json_snippet_becomes_a_jpeg(self):
        from v3.cams import still_jpeg

        jpeg = bytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
        import base64

        envelope = json.dumps({"icd_Id": "x", "snippet": base64.b64encode(jpeg).decode()}).encode()
        self.assertEqual(still_jpeg(envelope)[:3], b"\xff\xd8\xff")
        self.assertEqual(still_jpeg(jpeg)[:3], b"\xff\xd8\xff")
        self.assertIsNone(still_jpeg(b"null"))
        self.assertIsNone(still_jpeg(b"<html>nope</html>"))


class HudAndSnapTests(unittest.TestCase):
    def test_map_paints_a_red_and_blue_dot_per_camera(self):
        art = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "CctvArt.swift")
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        swift = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        self.assertIn("enum CctvArt", art)
        self.assertIn("static func dot(", art)
        self.assertIn("225.0 / 255.0", art)
        self.assertIn("61.0 / 255.0", art)
        self.assertIn("cctv-mark", swift + offline + art)
        self.assertIn("Inspect.holdProbePoints", offline)
        self.assertIn("onCctvHold", offline)
        self.assertIn("onCctvTap", offline)
        self.assertIn("func cctvMark(at", offline)
        tap = offline.split("func handleTap")[1].split("func handleDoubleTap")[0]
        self.assertIn("cctvMark(at:", tap)
        self.assertNotIn("godsEye == true", tap)
        self.assertLess(tap.find("personMark(at:"), tap.find("cctvMark(at:"))
        self.assertLess(tap.find("cctvMark(at:"), tap.find("onMapTap"))
        hold = offline.split("func handleHold")[1].split("func personMark")[0]
        self.assertIn("cctvMark(at:", hold)
        self.assertIn("CctvMarks.layerID", read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "Inspect.swift"))

    def test_update_snaps_nearest_stills_not_a_live_pipe(self):
        sock = read("Blackout", "UpdateSocket.swift")
        self.assertIn("func stillJPEG", sock)
        self.assertIn("CctvMarks.snapCap", sock)
        self.assertIn("snippet", sock)
        self.assertNotIn("AVPlayer", sock)
        self.assertNotIn("WKWebView", sock)
        self.assertIn("cameras.json", sock)
        self.assertIn("cam-", sock)

    def test_hold_card_shows_the_still_or_says_why(self):
        card = read("Blackout", "CamHoldCard.swift")
        tab = read("Blackout", "MapTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn("struct CamHoldCard", card)
        self.assertIn("NO STILL", card)
        self.assertIn("TAP UPDATE", card)
        self.assertIn("NO PIPE", card)
        self.assertIn("heldCam", tab)
        self.assertIn("func holdCam", app)
        self.assertIn("packCams", app)
        self.assertIn("cameras.json", app)
        copy = read("tools", "copy_resources.sh")
        self.assertNotIn("cameras.json", copy.split("rsync")[1].split("pack_phone")[0])


if __name__ == "__main__":
    unittest.main()
