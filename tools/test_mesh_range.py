#!/usr/bin/env python3
"""Blue ring around YOU is the farthest mesh hop plus one radio.

Shows only when other devices are on the map. A spoke NEAR dot is already
at hear range — it does not invent a second hop. Silence is no ring.
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


def _haversine_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    r = 6371000.0
    p1 = math.radians(a[0])
    p2 = math.radians(b[0])
    dphi = math.radians(b[0] - a[0])
    dl = math.radians(b[1] - a[1])
    h = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(h)))


def reach_meters(rssi: int) -> float:
    clamped = max(-100, min(-35, rssi))
    return 50.0 + ((-35 - clamped) * 2.0)


RADIO_MAX_M = reach_meters(-100)


def mesh_range_meters(
    you: tuple[float, float] | None,
    nodes: list[dict],
) -> float | None:
    """Farthest communication from YOU through hops we already have a fix for."""
    if you is None or not nodes:
        return None
    if not math.isfinite(you[0]) or not math.isfinite(you[1]):
        return None
    reach = 0.0
    any_ok = False
    for node in nodes:
        lat = node.get("lat")
        lon = node.get("lon")
        if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
            continue
        if not math.isfinite(lat) or not math.isfinite(lon):
            continue
        dist = _haversine_m(you, (lat, lon))
        any_ok = True
        if node.get("spoke"):
            reach = max(reach, dist)
        elif node.get("hop"):
            reach = max(reach, dist + RADIO_MAX_M)
        else:
            reach = max(reach, dist)
    if not any_ok or reach <= 0:
        return None
    return reach


YOU = (31.76190, -106.49000)


def _offset(lat: float, lon: float, meters: float, bearing: float) -> tuple[float, float]:
    r = 6_371_000.0
    br = math.radians(bearing)
    p1 = math.radians(lat)
    ang = meters / r
    p2 = math.asin(
        math.sin(p1) * math.cos(ang) + math.cos(p1) * math.sin(ang) * math.cos(br)
    )
    l2 = math.radians(lon) + math.atan2(
        math.sin(br) * math.sin(ang) * math.cos(p1),
        math.cos(ang) - math.sin(p1) * math.sin(p2),
    )
    return (math.degrees(p2), math.degrees(l2))


class MeshRangeMathTests(unittest.TestCase):
    def test_silence_is_no_ring(self):
        self.assertIsNone(mesh_range_meters(None, []))
        self.assertIsNone(mesh_range_meters(YOU, []))
        self.assertIsNone(mesh_range_meters(None, [{"lat": 31.76, "lon": -106.49, "hop": True}]))

    def test_spoke_near_dot_is_hear_range_not_a_second_hop(self):
        dest = _offset(YOU[0], YOU[1], 100.0, 45.0)
        meters = mesh_range_meters(
            YOU,
            [{"lat": dest[0], "lon": dest[1], "hop": True, "spoke": True}],
        )
        self.assertIsNotNone(meters)
        self.assertAlmostEqual(meters, 100.0, delta=2.0)
        self.assertLess(meters, RADIO_MAX_M + 50)

    def test_hop_pos_adds_one_radio_beyond_the_fix(self):
        dest = _offset(YOU[0], YOU[1], 400.0, 90.0)
        meters = mesh_range_meters(
            YOU,
            [{"lat": dest[0], "lon": dest[1], "hop": True, "spoke": False}],
        )
        self.assertIsNotNone(meters)
        self.assertAlmostEqual(meters, 400.0 + RADIO_MAX_M, delta=3.0)
        self.assertGreater(meters, 200.0)

    def test_farthest_hop_wins(self):
        near = _offset(YOU[0], YOU[1], 80.0, 0.0)
        far = _offset(YOU[0], YOU[1], 250.0, 180.0)
        meters = mesh_range_meters(
            YOU,
            [
                {"lat": near[0], "lon": near[1], "hop": True, "spoke": False},
                {"lat": far[0], "lon": far[1], "hop": True, "spoke": False},
            ],
        )
        self.assertAlmostEqual(meters, 250.0 + RADIO_MAX_M, delta=3.0)

    def test_a_closed_radio_does_not_extend_the_mesh(self):
        dest = _offset(YOU[0], YOU[1], 90.0, 10.0)
        meters = mesh_range_meters(
            YOU,
            [{"lat": dest[0], "lon": dest[1], "hop": False, "spoke": False}],
        )
        self.assertAlmostEqual(meters, 90.0, delta=2.0)


class MeshRangeHudTests(unittest.TestCase):
    def test_map_paints_one_blue_line_around_you(self):
        presence = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshPresence.swift")
        desk = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "EyeDesk.swift")
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        inspect = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "Inspect.swift")
        app = read("Blackout", "AppRuntime.swift")
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("enum MeshRange", presence)
        self.assertIn("static func meters(", presence)
        self.assertIn("radioMaxMeters", presence)
        self.assertIn("mesh-range-line", desk + offline + inspect)
        self.assertIn("meshRangeMeters", offline)
        spec = offline.split("struct OverlaySpec")[1].split("var spec:")[0]
        self.assertIn("var meshRangeMeters: Double?", spec)
        self.assertIn("static func ==", spec)
        self.assertIn("lhs.meshRangeMeters == rhs.meshRangeMeters", spec)
        self.assertIn("func paintMeshRange", offline)
        self.assertIn("61.0 / 255.0", offline.split("func paintMeshRange")[1].split("func ")[0])
        self.assertIn("158.0 / 255.0", offline.split("func paintMeshRange")[1].split("func ")[0])
        self.assertNotIn("fillColor", offline.split("func paintMeshRange")[1].split("func ")[0])
        self.assertIn("func eyeMeshRangeMeters", app)
        self.assertIn("MeshRange.meters", app)
        self.assertIn("meshRangeMeters:", tab)
        self.assertIn("EyeDesk.meshRangeLayerID", inspect)
        keep = offline.split("private static func keepsLine")[1].split(
            "private static func keepsCircle"
        )[0]
        self.assertIn("meshRangeLayerID", keep)

    def test_device_script_scores_the_blue_mesh_ring(self):
        qa = read("docs", "SOLO_QA.md")
        agents = read("AGENTS.md")
        self.assertIn("blue", qa.lower())
        self.assertIn("mesh range", qa.lower())
        self.assertIn("test_mesh_range.py", agents)
        validate = read("tools", "validate_v3.py")
        self.assertIn("test_mesh_range.py", validate)
        self.assertIn("mesh_range()", validate)


if __name__ == "__main__":
    unittest.main()
