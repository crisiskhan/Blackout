#!/usr/bin/env python3
"""Every pack camera is a red/blue disc. EXPEDITION TV is SNAP stills.

Packs populate on open. Hop cameras use the same disc and the same SNAP
rules. TV is nearest to farthest. Never a live stream.
"""
from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


def _finite(value: object) -> bool:
    return isinstance(value, (int, float)) and math.isfinite(value)


def haversine_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lon1 = map(math.radians, a)
    lat2, lon2 = map(math.radians, b)
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371000.0 * 2 * math.asin(math.sqrt(h))


def tv_rows(
    pack: list[dict], hops: list[dict], lat: float, lon: float
) -> list[dict]:
    """Every reachable camera, pack first on a shared id, nearest to farthest."""
    by_id: dict[str, dict] = {}
    for cam in pack:
        cid = str(cam.get("id") or "").strip()
        if not cid or not _finite(cam.get("lat")) or not _finite(cam.get("lon")):
            continue
        by_id[cid] = cam
    packed = set(by_id)
    seen: set[str] = set()
    for cam in hops:
        cid = str(cam.get("id") or "").strip()
        if not cid or cid in packed or cid in seen:
            continue
        if not _finite(cam.get("lat")) or not _finite(cam.get("lon")):
            continue
        seen.add(cid)
        by_id[cid] = cam
    return sorted(
        by_id.values(),
        key=lambda cam: haversine_m((lat, lon), (float(cam["lat"]), float(cam["lon"]))),
    )


YOU = (31.87050, -106.59732)


class TvOrderTests(unittest.TestCase):
    def test_nearest_camera_is_first(self):
        pack = [
            {
                "id": "far-pack",
                "lat": 32.3,
                "lon": -107.2,
                "name": "Far",
                "url": "https://its.txdot.gov/far.jpg",
            },
            {
                "id": "near-pack",
                "lat": 31.8706,
                "lon": -106.5974,
                "name": "Near",
                "url": "https://its.txdot.gov/near.jpg",
            },
        ]
        hops = [
            {
                "id": "mid-hop",
                "lat": 31.90,
                "lon": -106.62,
                "name": "Mid",
                "url": "https://peer.example/cam.jpg",
            },
            {
                "id": "near-pack",
                "lat": 31.99,
                "lon": -106.80,
                "name": "Dup",
                "url": "https://peer.example/dup.jpg",
            },
            {
                "id": "broken",
                "lat": float("nan"),
                "lon": -106.1,
                "name": "No",
                "url": "https://peer.example/no.jpg",
            },
        ]
        got = tv_rows(pack, hops, YOU[0], YOU[1])
        self.assertEqual([row["id"] for row in got], ["near-pack", "mid-hop", "far-pack"])
        self.assertEqual(got[0]["name"], "Near")

    def test_empty_pack_and_silence_is_empty(self):
        self.assertEqual(tv_rows([], [], YOU[0], YOU[1]), [])


class OneDiscTests(unittest.TestCase):
    def test_pack_and_hop_cameras_are_the_same_red_blue_disc(self):
        cctv = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "CctvArt.swift")
        hop = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MeshCamArt.swift")
        marks = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        tab = read("Blackout", "MapTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        desk = read("Blackout", "CamDesk.swift")
        self.assertIn("enum CctvArt", cctv)
        self.assertIn("225.0 / 255.0", cctv)
        self.assertIn("61.0 / 255.0", cctv)
        self.assertIn("CctvArt.dot()", hop)
        self.assertNotIn("64.0 / 255.0", hop)
        self.assertNotIn("160.0 / 255.0", hop)
        self.assertNotIn("128.0 / 255.0", hop)
        self.assertIn("enum CamDesk", desk)
        self.assertIn("static func marks(", desk)
        self.assertIn("static func feeds(", desk)
        self.assertIn("MeshCamPaint.visible", desk)
        self.assertIn("GraphRouter.haversine", desk)
        self.assertIn("sorted", desk)
        self.assertIn("CamDesk.marks", tab)
        self.assertIn("meshCams: []", tab)
        extra = app.split("func tapUpdate")[1].split("func fitPack")[0]
        self.assertNotIn('ink: "pink"', extra)
        hold = app.split("func holdCam")[1].split("func holdAddress")[0]
        self.assertNotIn('"pink"', hold)
        self.assertIn('?? "blue"', hold)
        self.assertIn("Same red/blue disc", marks)
        switch = app.split("func switchPack")[1].split("func applyMapKeepAwake")[0]
        self.assertIn("loadPackCams()", switch)
        self.assertIn("pullMapSnap()", switch)

    def test_pack_open_and_tv_use_the_same_snap(self):
        app = read("Blackout", "AppRuntime.swift")
        exped = read("Blackout", "ExpeditionTab.swift")
        tv = read("Blackout", "TvPlate.swift")
        sock = read("Blackout", "UpdateSocket.swift")
        self.assertIn("case .tv", exped)
        self.assertIn('return "TV"', exped)
        self.assertIn("TvPlate", exped)
        self.assertIn("pullMapSnap()", exped)
        self.assertIn("struct TvPlate", tv)
        self.assertIn("CamDesk.feeds", tv)
        self.assertIn("TAP UPDATE", tv)
        self.assertIn("NO STILL", tv)
        self.assertIn("NO PIPE", tv)
        self.assertIn("NO CAMERAS", tv)
        self.assertIn("cam-", tv)
        self.assertIn("watchSeconds", tv + desk_text())
        self.assertIn("pullMapSnap()", tv)
        self.assertIn("BlackoutTokens.Distance.hud", tv + desk_text())
        self.assertNotIn("AVPlayer", tv)
        self.assertNotIn("WKWebView", tv)
        self.assertNotIn("rtmp", tv.lower())
        self.assertNotIn("AVPlayer", sock)
        self.assertNotIn("WKWebView", sock)
        self.assertIn("func pullMapSnap(", app)
        self.assertIn("tapUpdate()", app.split("func pullMapSnap")[1].split("func tapUpdate")[0])


class DeviceScriptTests(unittest.TestCase):
    def test_solo_qa_and_audit_score_one_disc_and_tv(self):
        qa = read("docs", "SOLO_QA.md")
        agents = read("AGENTS.md")
        validate = read("tools", "validate_v3.py")
        hop = next(line for line in qa.splitlines() if "Hop cameras" in line)
        self.assertIn("red/blue", hop)
        self.assertNotIn("pink", hop.lower())
        self.assertNotIn("orange", hop.lower())
        tv = next(line for line in qa.splitlines() if "EXPEDITION `TV`" in line)
        self.assertIn("TV", tv)
        self.assertIn("SNAP", tv)
        self.assertIn("nearest", tv.lower())
        self.assertIn("never a live stream", tv.lower())
        self.assertIn("test_expedition_tv.py", agents)
        self.assertIn("test_expedition_tv.py", validate)
        self.assertIn("expedition_tv()", validate)


def desk_text() -> str:
    return read("Blackout", "CamDesk.swift")


if __name__ == "__main__":
    unittest.main()
