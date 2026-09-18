#!/usr/bin/env python3
"""NEAR dots are heard radios, clustered. A hop carries store. Discovery is not a peer.

Airplane + Bluetooth. A stranger's radio cannot relay packets unless it runs
Blackout or answers the hop GATT. The glass never invents a house from silence.
"""
from __future__ import annotations

import math
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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


def cluster(
    points: list[dict],
    radius_m: float = 45.0,
) -> list[dict]:
    """One mark per house-sized bunch. Count sits on the mark."""
    leftover = sorted(points, key=lambda p: p["id"])
    out: list[dict] = []
    while leftover:
        seed = leftover.pop(0)
        bunch = [seed]
        kept: list[dict] = []
        for point in leftover:
            if _haversine_m((seed["lat"], seed["lon"]), (point["lat"], point["lon"])) <= radius_m:
                bunch.append(point)
            else:
                kept.append(point)
        leftover = kept
        lat = sum(p["lat"] for p in bunch) / len(bunch)
        lon = sum(p["lon"] for p in bunch) / len(bunch)
        kinds = []
        for p in bunch:
            kind = p.get("kind") or ""
            if kind and kind not in kinds:
                kinds.append(kind)
        out.append(
            {
                "id": f"NEAR·{lat:.5f},{lon:.5f}",
                "lat": lat,
                "lon": lon,
                "count": len(bunch),
                "kinds": kinds,
            }
        )
    return out


def _accessory(name: str, services: list[str]) -> bool:
    n = name.lower()
    phones = ("iphone", "ipad", "galaxy", "samsung", "pixel", "motorola")
    if any(word in n for word in phones):
        return False
    accessories = (
        "airpods",
        "watch",
        "pencil",
        "keyboard",
        "mouse",
        "buds",
        "pixel buds",
    )
    if any(word in n for word in accessories):
        return True
    return "1812" in {s.lower() for s in services}


def classify(name: str, manufacturer: int | None, services: list[str]) -> str:
    n = name.lower()
    if any(s.lower() == "hop" for s in services):
        return "hop"
    if "iphone" in n or "ipad" in n:
        return "apple"
    if "galaxy" in n or "samsung" in n or n.startswith("sm-"):
        return "samsung"
    if manufacturer == 0x004C and not _accessory(name, services):
        return "apple"
    if manufacturer == 0x0075 and not _accessory(name, services):
        return "samsung"
    return "device"


def should_probe(name: str, services: list[str]) -> bool:
    if any(s.lower() == "hop" for s in services):
        return True
    return not _accessory(name, services)


def marks(
    hears: list[dict],
    you: tuple[float, float] | None,
) -> list[dict]:
    """Only a real fix paints. YOU is not a house of strangers."""
    _ = you
    placed: list[dict] = []
    for hear in hears:
        lat = hear.get("lat")
        lon = hear.get("lon")
        if lat is None or lon is None:
            continue
        placed.append(
            {
                "id": hear["id"],
                "lat": lat,
                "lon": lon,
                "kind": hear.get("kind") or "",
            }
        )
    return cluster(placed)


def signal(was: int | None, now: int | None) -> str:
    """Higher RSSI is louder. Six dB is a step. Empty when nobody is heard."""
    if now is None:
        return ""
    if was is None:
        return "NEAR · LIVE"
    if now - was >= 6:
        return "NEAR · LOUDER"
    if was - now >= 6:
        return "NEAR · QUIETER"
    return ""


def lasts(
    remembered: list[dict],
    live: list[dict],
    now_s: float,
    keep_s: float = 1800.0,
) -> list[dict]:
    """Hop POS outlives the 25 s hear. A live house replaces a last."""
    kept = [p for p in remembered if now_s - float(p.get("at") or 0) <= keep_s]
    out: list[dict] = []
    for point in kept:
        if any(
            _haversine_m((point["lat"], point["lon"]), (m["lat"], m["lon"])) <= 45.0
            for m in live
        ):
            continue
        out.append(
            {
                "id": f"LAST·{point['lat']:.5f},{point['lon']:.5f}",
                "lat": point["lat"],
                "lon": point["lon"],
                "count": int(point.get("count") or 1),
                "kinds": list(point.get("kinds") or ["hop"]),
            }
        )
    return out


class MeshPresenceBatteryTests(unittest.TestCase):
    def test_house_cluster_is_one_dot_with_a_count(self):
        a = {"id": "a", "lat": 31.76190, "lon": -106.49000, "kind": "apple"}
        b = {"id": "b", "lat": 31.76191, "lon": -106.49001, "kind": "samsung"}
        c = {"id": "c", "lat": 31.78000, "lon": -106.51000, "kind": "hop"}
        out = cluster([a, b, c])
        self.assertEqual(len(out), 2)
        house = next(m for m in out if m["count"] == 2)
        self.assertEqual(house["count"], 2)
        self.assertEqual(set(house["kinds"]), {"apple", "samsung"})
        self.assertTrue(house["id"].startswith("NEAR·"))
        lone = next(m for m in out if m["count"] == 1)
        self.assertEqual(lone["kinds"], ["hop"])

    def test_hears_without_a_fix_stay_off_the_canvas(self):
        hears = [
            {"id": "p1", "kind": "apple"},
            {"id": "p2", "kind": "apple"},
        ]
        self.assertEqual(marks(hears, you=None), [])
        self.assertEqual(marks(hears, you=(31.76, -106.49)), [])

    def test_signal_names_louder_and_quieter(self):
        self.assertEqual(signal(None, None), "")
        self.assertEqual(signal(None, -70), "NEAR · LIVE")
        self.assertEqual(signal(-80, -70), "NEAR · LOUDER")
        self.assertEqual(signal(-70, -80), "NEAR · QUIETER")
        self.assertEqual(signal(-70, -68), "")

    def test_last_hop_outlives_the_hear(self):
        live = [{"id": "NEAR·31.78000,-106.51000", "lat": 31.78000, "lon": -106.51000}]
        remembered = [
            {"lat": 31.76190, "lon": -106.49000, "at": 10.0, "count": 1, "kinds": ["hop"]},
            {"lat": 31.78000, "lon": -106.51000, "at": 10.0, "count": 1, "kinds": ["hop"]},
            {"lat": 31.70, "lon": -106.40, "at": -4000.0, "count": 1, "kinds": ["hop"]},
        ]
        out = lasts(remembered, live, now_s=20.0, keep_s=1800.0)
        self.assertEqual(len(out), 1)
        self.assertTrue(out[0]["id"].startswith("LAST·"))
        self.assertAlmostEqual(out[0]["lat"], 31.76190, places=4)
        gone = lasts(remembered, live, now_s=2000.0, keep_s=1800.0)
        self.assertEqual(gone, [])

    def test_every_device_is_heard(self):
        self.assertEqual(classify("Crisis iPhone", 0x004C, []), "apple")
        self.assertEqual(classify("Galaxy S24", 0x0075, []), "samsung")
        self.assertEqual(classify("SM-S921U", None, []), "samsung")
        self.assertEqual(classify("Pixel 8", None, []), "device")
        self.assertEqual(classify("Motorola", None, []), "device")
        self.assertEqual(classify("AirPods Pro", 0x004C, []), "device")
        self.assertEqual(classify("Watch", 0x004C, []), "device")
        self.assertEqual(classify("", 0x00E0, []), "device")
        self.assertEqual(classify("", None, ["hop"]), "hop")
        self.assertEqual(classify("", 0x004C, ["1812"]), "device")
        self.assertTrue(should_probe("Pixel 8", []))
        self.assertTrue(should_probe("Crisis iPhone", []))
        self.assertTrue(should_probe("", ["hop"]))
        self.assertTrue(should_probe("", [""]))
        self.assertFalse(should_probe("AirPods Pro", []))
        self.assertFalse(should_probe("Watch", []))
        self.assertFalse(should_probe("", ["1812"]))

    def test_swift_cluster_and_radio_exist(self):
        presence = read(
            "Packages", "MeshDTN", "Sources", "MeshDTN", "MeshPresence.swift"
        )
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        live = read("Packages", "MeshDTN", "Sources", "MeshDTN", "LiveMeshRadio.swift")
        tests = read(
            "Packages", "MeshDTN", "Tests", "MeshDTNTests", "MeshDTNTests.swift"
        )
        art = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        app = read("Blackout", "AppRuntime.swift")
        tab = read("Blackout", "MapTab.swift")
        card = read("Blackout", "NearHoldCard.swift")
        comms = read("Blackout", "CommsTab.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("enum MeshPresence", presence)
        self.assertIn("static func cluster(", presence)
        self.assertIn("houseMeters", presence)
        self.assertIn("hop, device", presence)
        self.assertIn("shouldProbe", presence)
        self.assertIn("probeCap", presence)
        self.assertIn("NEAR·", presence)
        self.assertIn("LAST·", presence)
        self.assertIn("NEAR · LOUDER", presence)
        self.assertIn("func signal(", presence)
        self.assertIn("func lasts(", presence)
        self.assertIn("ble, hop", mesh)
        self.assertIn("chromeNear", mesh)
        self.assertIn("chromeSignal", mesh)
        self.assertIn("noteHear", mesh)
        self.assertIn("noteHop", mesh)
        self.assertIn("func startListen(", mesh)
        self.assertIn("func stopParty(", mesh)
        self.assertIn("join: false", mesh)
        self.assertIn("Discovery-only scan is not a peer", live)
        self.assertIn("scanForPeripherals", live)
        self.assertIn("hopUUID", live)
        self.assertIn("onHear", live)
        self.assertIn("shouldProbe", live)
        self.assertIn("probedClosed", live)
        self.assertIn("testHearIsNotAPeer", tests)
        self.assertIn("testHopCarriesStore", tests)
        self.assertIn("static func presence(", art)
        self.assertIn("presence", app.split("func eyeCanvasPips")[1].split("func eyeTrails")[0])
        self.assertIn("heldNear", app)
        self.assertIn("listenNet", app)
        self.assertIn("quietRadio", app)
        self.assertIn("NearHoldCard", tab)
        self.assertIn("NEAR", card)
        self.assertIn("DEVICE", card)
        self.assertIn("WALK", card)
        self.assertIn("NO PLACE", card)
        self.assertNotIn("tel://", card)
        self.assertIn("chromeNear", comms)
        self.assertIn("LISTEN", comms)
        self.assertIn("QUIET", comms)
        field = read("Blackout", "FieldTab.swift")
        self.assertIn("chromeSignal", field)
        self.assertIn("NEAR ·", qa)
        self.assertIn("LOUDER", qa)
        self.assertIn("green", qa.lower())
        for blob, name in (
            (presence, "MeshPresence"),
            (live, "LiveMeshRadio"),
            (card, "NearHoldCard"),
        ):
            self.assertNotIn("URLSession", blob, name)
            self.assertNotIn("WKWebView", blob, name)
            self.assertNotIn("tel://", blob, name)
            self.assertNotIn("Whisper", blob, name)


if __name__ == "__main__":
    unittest.main()
