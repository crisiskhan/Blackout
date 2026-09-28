#!/usr/bin/env python3
"""UPDATE SNAPs every camera we can reach. Not the nearest 16.

Packed CCTV plus hop HTTPS cameras. Hop JPEGs still write when there is
no pipe. Never a live stream.
"""
from __future__ import annotations

import json
import math
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

SNAP_AT_ONCE = 8
REQUEST_SECONDS = 8
RESOURCE_PAD_SECONDS = 30


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


def snap_targets(pack: list[dict], extra: list[dict]) -> list[dict]:
    """Every packed + hop HTTPS camera. Pack wins a shared id. No nearest cut."""
    by_id: dict[str, dict] = {}
    for cam in pack:
        cid = str(cam.get("id") or "").strip()
        url = str(cam.get("url") or "")
        if not cid or not url.startswith("https://"):
            continue
        by_id[cid] = cam
    for cam in extra:
        cid = str(cam.get("id") or "").strip()
        url = str(cam.get("url") or "")
        if not cid or cid in by_id or not url.startswith("https://"):
            continue
        by_id[cid] = cam
    return list(by_id.values())


def snap_resource_seconds(count: int, at_once: int = SNAP_AT_ONCE) -> int:
    n = max(0, count)
    batch = max(1, at_once)
    batches = max(1, math.ceil(n / batch) if n else 1)
    return REQUEST_SECONDS * batches + RESOURCE_PAD_SECONDS


class SnapAllCamTests(unittest.TestCase):
    def test_far_packed_cameras_are_not_dropped(self):
        pack = [
            {
                "id": f"cam-{i}",
                "url": f"https://its.txdot.gov/{i}.jpg",
                "lat": 31.87 + i * 0.01,
                "lon": -106.59,
            }
            for i in range(20)
        ]
        extra = [
            {
                "id": "hop-1",
                "url": "https://its.txdot.gov/hop.jpg",
                "lat": 31.90,
                "lon": -106.50,
            },
            {
                "id": "cam-0",
                "url": "https://evil.example/overwrite.jpg",
                "lat": 0,
                "lon": 0,
            },
            {"id": "http-only", "url": "http://its.txdot.gov/no.jpg", "lat": 1, "lon": 1},
            {"id": "", "url": "https://its.txdot.gov/empty.jpg", "lat": 1, "lon": 1},
        ]
        got = snap_targets(pack, extra)
        ids = {row["id"] for row in got}
        self.assertEqual(len(got), 21)
        self.assertIn("cam-19", ids)
        self.assertIn("hop-1", ids)
        self.assertNotIn("http-only", ids)
        self.assertEqual(next(row["url"] for row in got if row["id"] == "cam-0"), pack[0]["url"])

    def test_tx_west_and_tx_east_are_bigger_than_sixteen(self):
        west = len(snap_targets(
            json.loads((ROOT / "Resources" / "Packs" / "tx-west" / "cameras.json").read_text()),
            [],
        ))
        east = len(snap_targets(
            json.loads((ROOT / "Resources" / "Packs" / "tx-east" / "cameras.json").read_text()),
            [],
        ))
        self.assertGreater(west, 16)
        self.assertGreater(east, 16)
        self.assertGreaterEqual(west, 200)
        self.assertGreaterEqual(east, 1000)

    def test_resource_timeout_covers_every_batch(self):
        self.assertEqual(snap_resource_seconds(0), 38)
        self.assertEqual(snap_resource_seconds(8), 38)
        self.assertEqual(snap_resource_seconds(9), 46)
        self.assertEqual(snap_resource_seconds(211), 8 * 27 + 30)
        self.assertGreater(snap_resource_seconds(211), 12)


class UpdateAllCamHudTests(unittest.TestCase):
    def test_update_snaps_every_https_camera_not_the_nearest_sixteen(self):
        sock = read("Blackout", "UpdateSocket.swift")
        marks = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        app = read("Blackout", "AppRuntime.swift")
        burst = sock.split("func burst(")[1].split("private func get(")[0]
        self.assertIn("func snapTargets(", sock)
        self.assertIn("func snapResourceSeconds(", sock)
        self.assertIn("snapAtOnce", marks)
        self.assertIn("CctvMarks.snapAtOnce", sock)
        self.assertNotIn("CctvMarks.snapCap", sock)
        self.assertNotIn("CctvMarks.snapCap", marks)
        self.assertNotIn(".prefix(CctvMarks.snapCap)", burst)
        self.assertNotIn("snapCap", burst)
        self.assertIn("snapTargets(", burst)
        self.assertIn("extraCams", burst)
        self.assertIn("withTaskGroup", burst)
        self.assertIn("nonisolated static func fetch(", sock)
        self.assertIn("timeoutIntervalForResource", burst)
        self.assertIn("snapResourceSeconds(", burst)
        self.assertNotIn("timeoutIntervalForResource = 12", burst)
        tap = app.split("func tapUpdate")[1].split("func fitPack")[0]
        self.assertIn("extraCams", tap)
        self.assertIn("hopCamStills", tap)
        self.assertIn("func applyHopStills", sock)
        self.assertNotIn("AVPlayer", sock)
        self.assertNotIn("WKWebView", sock)

    def test_device_script_scores_every_reachable_camera(self):
        qa = read("docs", "SOLO_QA.md")
        agents = read("AGENTS.md")
        cctv = next(line for line in qa.splitlines() if "Packed CCTV" in line)
        hop = next(line for line in qa.splitlines() if "Hop cameras" in line)
        self.assertIn("every", cctv.lower())
        self.assertNotIn("nearest stills", cctv)
        self.assertIn("every", hop.lower())
        self.assertIn("test_update_all_cams.py", agents)
        validate = read("tools", "validate_v3.py")
        self.assertIn("test_update_all_cams.py", validate)
        self.assertIn("update_all_cams()", validate)


if __name__ == "__main__":
    unittest.main()
