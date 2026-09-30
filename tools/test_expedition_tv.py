#!/usr/bin/env python3
"""Every pack camera is a red/blue disc. EXPEDITION TV is SNAP stills.

Packs populate on open. Hop cameras use the same disc and the same SNAP
rules. TV is TRAFFIC / BRIDGE / AIRPORT / VENUE / HOP, nearest to farthest
inside each section. Empty sections omit. Official city/zoo HLS play on
BRIDGE / VENUE. N/A is a 10s hold for adult only. TRAFFIC / AIRPORT / HOP
never a live stream.
"""
from __future__ import annotations

import json
import math
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

KINDS = ("TRAFFIC", "BRIDGE", "AIRPORT", "VENUE", "N/A", "HOP")
NA_HOLD_SECONDS = 10


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
        row = dict(cam)
        if not str(row.get("provider") or "").strip():
            row["provider"] = "HOP"
        by_id[cid] = row
    return sorted(
        by_id.values(),
        key=lambda cam: haversine_m((lat, lon), (float(cam["lat"]), float(cam["lon"]))),
    )


def section(cam: dict) -> str:
    """HOP first. BOTA / PASO DEL NORTE are BRIDGE. AIRPORT is AIRPORT.

    Zaragoza street cams and Paseo Del Norte stay TRAFFIC. VENUE is reserved.
    N/A is provider N/A only — never a street name. Open sections omit N/A.
    """
    provider = str(cam.get("provider") or "").strip().upper()
    if provider == "HOP":
        return "HOP"
    if provider in ("N/A", "NA"):
        return "N/A"
    name = str(cam.get("name") or "").strip().upper()
    if not name:
        name = str(cam.get("id") or "").strip().upper()
    if "BOTA" in name or "PASO DEL NORTE" in name:
        return "BRIDGE"
    if "AIRPORT" in name:
        return "AIRPORT"
    return "TRAFFIC"


def sectioned(
    pack: list[dict], hops: list[dict], lat: float, lon: float
) -> list[tuple[str, list[dict]]]:
    buckets: dict[str, list[dict]] = {kind: [] for kind in KINDS}
    for row in tv_rows(pack, hops, lat, lon):
        buckets[section(row)].append(row)
    return [
        (kind, buckets[kind])
        for kind in KINDS
        if kind != "N/A" and buckets[kind]
    ]


def na_rows(pack: list[dict], hops: list[dict], lat: float, lon: float) -> list[dict]:
    return [row for row in tv_rows(pack, hops, lat, lon) if section(row) == "N/A"]


def na_unlocks(elapsed: float) -> bool:
    return elapsed >= NA_HOLD_SECONDS


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
        self.assertIn("NaLive", tv)
        self.assertIn("func pullMapSnap(", app)
        self.assertIn("tapUpdate()", app.split("func pullMapSnap")[1].split("func tapUpdate")[0])
        self.assertIn("CamDesk.sections", tv)
        self.assertIn("kind.rawValue", tv)
        desk = desk_text()
        self.assertIn("enum Kind", desk)
        self.assertIn("static func kind(", desk)
        self.assertIn("static func sections(", desk)
        self.assertIn('"TRAFFIC"', desk)
        self.assertIn('"BRIDGE"', desk)
        self.assertIn('"AIRPORT"', desk)
        self.assertIn('"VENUE"', desk)
        self.assertIn('"N/A"', desk)
        self.assertIn('"HOP"', desk)
        self.assertIn("BOTA", desk)
        self.assertIn("PASO DEL NORTE", desk)
        self.assertIn("naHoldSeconds", desk)
        self.assertIn("HOLD 10", tv)
        self.assertIn("naHoldSeconds", tv)
        self.assertIn("naUnlocks", tv + desk)


class SectionTests(unittest.TestCase):
    def test_kind_tokens_are_honest(self):
        self.assertEqual(section({"name": "US-62/Paisano East @ BOTA", "provider": "TxDOT"}), "BRIDGE")
        self.assertEqual(section({"name": "Paso del Norte", "provider": "TxDOT"}), "BRIDGE")
        self.assertEqual(section({"name": "Airway Blvd @ Airport", "provider": "TxDOT"}), "AIRPORT")
        self.assertEqual(section({"name": "Airport @ Founders", "provider": "TxDOT"}), "AIRPORT")
        self.assertEqual(section({"name": "SP-601 @ Airport", "provider": "TxDOT"}), "AIRPORT")
        self.assertEqual(section({"name": "LP-375 @ Paseo Del Norte", "provider": "TxDOT"}), "TRAFFIC")
        self.assertEqual(section({"name": "LP-375 @ Zaragoza", "provider": "TxDOT"}), "TRAFFIC")
        self.assertEqual(section({"name": "FM-659/Zaragoza @ Pellicano", "provider": "TxDOT"}), "TRAFFIC")
        self.assertEqual(section({"name": "IH-10 @ Zaragoza", "provider": "TxDOT"}), "TRAFFIC")
        self.assertEqual(section({"name": "IH-10 @ Airway", "provider": "TxDOT"}), "TRAFFIC")
        self.assertEqual(section({"name": "Airport @ Founders", "provider": "HOP"}), "HOP")
        self.assertEqual(section({"name": "US-62/Paisano East @ BOTA", "provider": "hop"}), "HOP")
        self.assertEqual(section({"name": "Club", "provider": "N/A"}), "N/A")
        self.assertEqual(section({"name": "Club", "provider": "NA"}), "N/A")
        self.assertEqual(section({"name": "Doniphan @ Club", "provider": "TxDOT"}), "TRAFFIC")

    def test_sections_omit_empty_and_sort_inside(self):
        pack = [
            {
                "id": "near",
                "lat": 31.8706,
                "lon": -106.5974,
                "name": "IH-10 @ Artcraft",
                "provider": "TxDOT",
            },
            {
                "id": "paseo",
                "lat": 31.90,
                "lon": -106.58,
                "name": "LP-375 @ Paseo Del Norte",
                "provider": "TxDOT",
            },
            {
                "id": "z-street",
                "lat": 31.75,
                "lon": -106.32,
                "name": "FM-659/Zaragoza @ Pellicano",
                "provider": "TxDOT",
            },
            {
                "id": "bota",
                "lat": 31.764,
                "lon": -106.451,
                "name": "US-62/Paisano East @ BOTA",
                "provider": "TxDOT",
            },
            {
                "id": "pdn",
                "lat": 31.76,
                "lon": -106.48,
                "name": "Paso del Norte",
                "provider": "TxDOT",
            },
            {
                "id": "air-near",
                "lat": 31.80,
                "lon": -106.40,
                "name": "Airway Blvd @ Airport",
                "provider": "TxDOT",
            },
            {
                "id": "air-far",
                "lat": 32.0,
                "lon": -106.3,
                "name": "SP-601 @ Airport",
                "provider": "TxDOT",
            },
            {
                "id": "airway",
                "lat": 31.78,
                "lon": -106.42,
                "name": "IH-10 @ Airway",
                "provider": "TxDOT",
            },
        ]
        hops = [
            {
                "id": "hop-mid",
                "lat": 31.88,
                "lon": -106.60,
                "name": "Peer",
                "url": "https://peer.example/a.jpg",
            },
            {
                "id": "hop-air",
                "lat": 31.81,
                "lon": -106.41,
                "name": "Airport @ Founders",
                "provider": "HOP",
            },
        ]
        got = sectioned(pack, hops, YOU[0], YOU[1])
        self.assertEqual([kind for kind, _ in got], ["TRAFFIC", "BRIDGE", "AIRPORT", "HOP"])
        by_kind = {kind: [row["id"] for row in rows] for kind, rows in got}
        self.assertEqual(by_kind["TRAFFIC"][0], "near")
        self.assertLess(
            haversine_m(YOU, (31.80, -106.40)),
            haversine_m(YOU, (32.0, -106.3)),
        )
        self.assertEqual(by_kind["AIRPORT"], ["air-near", "air-far"])
        self.assertEqual(by_kind["BRIDGE"], ["pdn", "bota"])
        self.assertEqual(by_kind["HOP"][0], "hop-mid")
        self.assertIn("hop-air", by_kind["HOP"])
        self.assertNotIn("VENUE", [kind for kind, _ in got])
        self.assertNotIn("N/A", [kind for kind, _ in got])
        for _kind, rows in got:
            meters = [
                haversine_m(YOU, (float(row["lat"]), float(row["lon"])))
                for row in rows
            ]
            self.assertEqual(meters, sorted(meters))

    def test_tx_west_el_paso_names_section_honestly(self):
        cams = json.loads(read("Resources", "Packs", "tx-west", "cameras.json"))
        by_name = {row["name"]: row for row in cams}
        self.assertEqual(section(by_name["US-62/Paisano East @ BOTA"]), "BRIDGE")
        self.assertEqual(section(by_name["Airway Blvd @ Airport"]), "AIRPORT")
        self.assertEqual(section(by_name["Airport @ Founders"]), "AIRPORT")
        self.assertEqual(section(by_name["SP-601 @ Airport"]), "AIRPORT")
        self.assertEqual(section(by_name["LP-375 @ Paseo Del Norte"]), "TRAFFIC")
        self.assertEqual(section(by_name["LP-375 @ Zaragoza"]), "TRAFFIC")
        self.assertEqual(section(by_name["FM-659/Zaragoza @ Pellicano"]), "TRAFFIC")
        self.assertEqual(section(by_name["IH-10 @ Airway"]), "TRAFFIC")
        self.assertEqual(section(by_name["IH-10 @ Zaragoza"]), "TRAFFIC")
        for row in cams:
            self.assertNotEqual(section(row), "N/A")


class NaHoldTests(unittest.TestCase):
    def test_na_is_gated_and_ten_seconds(self):
        self.assertFalse(na_unlocks(0))
        self.assertFalse(na_unlocks(9.99))
        self.assertTrue(na_unlocks(10))
        self.assertTrue(na_unlocks(12))
        pack = [
            {
                "id": "na-near",
                "lat": 31.871,
                "lon": -106.597,
                "name": "Club",
                "provider": "N/A",
            },
            {
                "id": "near",
                "lat": 31.8706,
                "lon": -106.5974,
                "name": "IH-10 @ Artcraft",
                "provider": "TxDOT",
            },
        ]
        open_kinds = [kind for kind, _ in sectioned(pack, [], YOU[0], YOU[1])]
        self.assertEqual(open_kinds, ["TRAFFIC"])
        self.assertEqual([row["id"] for row in na_rows(pack, [], YOU[0], YOU[1])], ["na-near"])
        desk = desk_text()
        self.assertIn("static let naHoldSeconds", desk)
        self.assertIn("= 10", desk.split("naHoldSeconds")[1].split("\n")[0])
        self.assertIn("static func naUnlocks", desk)
        tv = read("Blackout", "TvPlate.swift")
        self.assertIn("HOLD 10", tv)
        self.assertIn("N/A", tv)
        self.assertNotIn("AVPlayer", tv)
        self.assertNotIn("WKWebView", tv)


OFFICIAL_HLS = (
    "https://zoocams.elpasozoo.org/BridgeStanton3.m3u8",
    "https://zoocams.elpasozoo.org/bridgepdn1.m3u8",
    "https://zoocams.elpasozoo.org/bridgesantafe3.m3u8",
    "https://zoocams.elpasozoo.org/bridgesantafe4.m3u8",
    "https://zoocams.elpasozoo.org/BridgeZaragoza1.m3u8",
    "https://zoocams.elpasozoo.org/BridgeZaragoza2.m3u8",
    "https://zoocams.elpasozoo.org/BridgeZaragoza3.m3u8",
    "https://zoocams.elpasozoo.org/ZOOGF.m3u8",
    "https://zoocams.elpasozoo.org/ZooM.m3u8",
)


class DeskLiveTests(unittest.TestCase):
    def test_official_hls_plays_on_open_bridge_and_venue(self):
        desk = read("Blackout", "DeskLive.swift")
        live = read("Blackout", "NaLive.swift")
        tv = read("Blackout", "TvPlate.swift")
        self.assertIn("enum DeskLive", desk)
        self.assertIn("AVPlayer", live)
        self.assertNotIn("WKWebView", desk)
        self.assertNotIn("WKWebView", live)
        self.assertNotIn("rtmp", desk.lower())
        self.assertNotIn("rtmp", live.lower())
        for url in OFFICIAL_HLS:
            self.assertIn(url, desk)
            self.assertNotIn(url, live)
        self.assertIn("zoocams.elpasozoo.org", desk)
        self.assertNotIn("zoocams.elpasozoo.org", live)
        self.assertNotIn("stantonbridge1.m3u8", desk.lower().replace("bridgestanton3", ""))
        self.assertNotIn("BridgeStanton2", desk)
        for word in ("truelook", "earthcam", "insecam", "chaturbate", "stripchat", "lovescape"):
            self.assertNotIn(word, desk.lower())
            self.assertNotIn(word, live.lower())
        self.assertIn("case .bridge", desk)
        self.assertIn("case .venue", desk)
        self.assertIn("DeskLive.rows", tv)
        self.assertIn("NaLiveWell", tv)
        self.assertNotIn("DeskLive.rows", na_gate_body(tv))
        self.assertIn("TAP PLAY", live)
        self.assertIn("NO STREAM", live)
        self.assertIn("NO PIPE", live)


class NaLiveTests(unittest.TestCase):
    def test_na_is_adult_only_after_hold(self):
        live = read("Blackout", "NaLive.swift")
        tv = read("Blackout", "TvPlate.swift")
        self.assertIn("enum NaLive", live)
        self.assertIn("AVPlayer", live)
        self.assertNotIn("WKWebView", live)
        self.assertNotIn("rtmp", live.lower())
        self.assertNotIn("zoocams.elpasozoo.org", live)
        for url in OFFICIAL_HLS:
            self.assertNotIn(url, live)
        self.assertIn("NaLive.rows", tv)
        self.assertIn("NaLiveWell", tv)
        self.assertIn("HOLD 10", tv)
        gate = na_gate_body(tv)
        self.assertIn("naLiveRows", gate)
        self.assertNotIn("DeskLive.rows", gate)


class ClosedSourcesTests(unittest.TestCase):
    def test_tv_and_harvest_refuse_unsecured_alpr_and_streams(self):
        paths = (
            ("tools", "v3", "cams.py"),
            ("Blackout", "CamDesk.swift"),
            ("Blackout", "TvPlate.swift"),
            ("Blackout", "UpdateSocket.swift"),
            ("Resources", "Packs", "tx-west", "cameras.json"),
        )
        banned = (
            "insecam",
            "deflock",
            "flocksafety",
            "earthcam",
            "truelook",
            "chaturbate",
            "stripchat",
            "cam4",
            "onlyfans",
            ".m3u8",
            "rtmp://",
        )
        for parts in paths:
            blob = read(*parts).lower()
            for word in banned:
                self.assertNotIn(word, blob, parts)


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
        self.assertIn("TRAFFIC", tv)
        self.assertIn("BRIDGE", tv)
        self.assertIn("AIRPORT", tv)
        self.assertIn("VENUE", tv)
        self.assertIn("`N/A`", tv)
        self.assertIn("HOLD 10", tv)
        self.assertIn("10s hold", tv)
        self.assertIn("adult", tv.lower())
        self.assertIn("city", tv.lower())
        self.assertIn("zoo", tv.lower())
        self.assertIn("section", tv.lower())
        self.assertNotIn("insecam", tv.lower())
        self.assertIn("test_expedition_tv.py", agents)
        self.assertIn("test_expedition_tv.py", validate)
        self.assertIn("expedition_tv()", validate)


def desk_text() -> str:
    return read("Blackout", "CamDesk.swift")


def na_gate_body(tv: str) -> str:
    start = tv.index("private var naGate")
    end = tv.index("private var naHoldRow", start)
    return tv[start:end]


if __name__ == "__main__":
    unittest.main()
