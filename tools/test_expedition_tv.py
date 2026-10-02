#!/usr/bin/env python3
"""Every pack camera is a red/blue disc. EXPEDITION TV is SNAP stills.

Packs populate on open. Hop cameras use the same disc and the same SNAP
rules. TV is TRAFFIC / BRIDGE / AIRPORT / VENUE / HOP, nearest to farthest
inside each section. Empty sections omit. Open sections never a live
stream — JPEG SNAP only. N/A is a 10s hold, then adult HTTPS HLS.
Tap a still to pinch-zoom the packed JPEG.
"""
from __future__ import annotations

import json
import math
import re
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


ADULT_CAP = 600
ADULT_SCREEN = 8
ADULT_BLOCKED = (
    "teen",
    "underage",
    "child",
    "loli",
    "shota",
    "jailbait",
    "preteen",
    "pedo",
    "minor",
    "under18",
    "younggirl",
    "trans",
    "shemale",
    "ladyboy",
    "tgirl",
)
ADULT_KIND_WORDS = (
    ("new", "NEW"),
    ("dance", "DANCE"),
    ("blonde", "BLONDE"),
    ("brunette", "BRUNETTE"),
    ("redhead", "REDHEAD"),
    ("asian", "ASIAN"),
    ("latina", "LATINA"),
    ("ebony", "EBONY"),
    ("milf", "MILF"),
    ("petite", "PETITE"),
    ("curvy", "CURVY"),
    ("outdoor", "OUTDOOR"),
    ("toys", "TOYS"),
    ("squirt", "SQUIRT"),
    ("anal", "ANAL"),
    ("lesbian", "LESBIAN"),
)
ADULT_MALE = {
    "m",
    "male",
    "c",
    "couple",
    "couples",
    "s",
    "trans",
    "shemale",
    "tgirl",
    "transgender",
    "transsexual",
    "ts",
}
ADULT_WOMAN = {"f", "female", "w", "woman", "women"}


def adult_playlist(raw: str) -> str | None:
    """HTTPS HLS only. Refuse guest advert / preview clips."""
    text = str(raw or "").strip()
    if not text.lower().startswith("https://"):
        return None
    low = text.lower()
    if "/cpa/" in low or "mouflon-advert" in low:
        return None
    if ".m3u8" not in low:
        return None
    return text


def adult_allows(name: str) -> bool:
    blob = str(name or "").lower()
    if not blob.strip():
        return False
    return not any(token in blob for token in ADULT_BLOCKED)


def adult_clean(blob: str) -> bool:
    text = str(blob or "").lower()
    if not text.strip():
        return True
    return not any(token in text for token in ADULT_BLOCKED)


def adult_stream(payload: object) -> str | None:
    """Public room HLS only. Private or empty is no stream."""
    if not isinstance(payload, dict):
        return None
    status = str(payload.get("room_status") or "").strip().lower()
    if status != "public":
        return None
    raw = payload.get("hls_source")
    if raw is None or str(raw).strip() == "":
        raw = payload.get("url")
    return adult_playlist(str(raw or ""))


def adult_woman(model: object) -> bool:
    """Directory is women. Refuse male, couple, and trans gender tags."""
    if not isinstance(model, dict):
        return False
    gender = str(model.get("gender") or "").strip().lower()
    if not gender:
        return True
    if gender in ADULT_MALE:
        return False
    return gender in ADULT_WOMAN


def adult_still(raw: str) -> str | None:
    """HTTPS JPEG still only. Never a playlist or advert clip."""
    text = str(raw or "").strip()
    if not text.lower().startswith("https://"):
        return None
    low = text.lower()
    if "/cpa/" in low or ".m3u8" in low:
        return None
    return text


def adult_image(model: object) -> str:
    if not isinstance(model, dict):
        return ""
    for key in ("image_url_360p", "image_url"):
        hit = adult_still(str(model.get(key) or ""))
        if hit:
            return hit
    return ""


def adult_room_kinds(model: object) -> list[str]:
    if not isinstance(model, dict):
        return []
    tags = model.get("tags") or []
    if isinstance(tags, list):
        tag_blob = " ".join(str(tag) for tag in tags)
    else:
        tag_blob = str(tags)
    blob = f"{tag_blob} {model.get('room_subject') or ''}".lower()
    tokens = set(blob.split())
    found: list[str] = []
    seen: set[str] = set()
    if model.get("is_new") or "new" in tokens:
        seen.add("NEW")
        found.append("NEW")
    for needle, chip in ADULT_KIND_WORDS:
        if needle == "new":
            continue
        if needle in blob and chip not in seen and adult_clean(chip):
            seen.add(chip)
            found.append(chip)
    return found


def adult_kinds(rooms: list[dict]) -> list[str]:
    seen: set[str] = set()
    for room in rooms:
        for kind in room.get("kinds") or []:
            chip = str(kind).strip().upper()
            if chip:
                seen.add(chip)
    return sorted(seen)


def adult_pick(rooms: list[dict], kind: str = "", query: str = "") -> list[dict]:
    chip = str(kind or "").strip().upper()
    needle = str(query or "").strip().lower()
    out: list[dict] = []
    for room in rooms:
        kinds = [str(item).strip().upper() for item in (room.get("kinds") or [])]
        if chip and chip != "ALL" and chip not in kinds:
            continue
        if needle:
            blob = " ".join(
                [
                    str(room.get("name") or ""),
                    str(room.get("handle") or ""),
                    " ".join(kinds),
                ]
            ).lower()
            if needle not in blob:
                continue
        out.append(room)
    return out


def adult_rooms(payload: object) -> list[dict]:
    """Live public women rooms, highest viewers first, cap ADULT_CAP. HLS later."""
    models: list[object] = []
    if isinstance(payload, list):
        models = payload
    elif isinstance(payload, dict):
        raw = payload.get("results")
        if raw is None:
            raw = payload.get("models")
        if raw is None:
            raw = payload.get("items")
        if isinstance(raw, dict):
            raw = raw.get("results") or raw.get("models") or raw.get("items") or []
        if isinstance(raw, list):
            models = raw
    rooms: list[dict] = []
    seen: set[str] = set()
    for model in models:
        if not isinstance(model, dict):
            continue
        show = str(model.get("current_show") or model.get("status") or "").strip().lower()
        if show != "public":
            continue
        try:
            years = int(model.get("age"))
        except (TypeError, ValueError):
            continue
        if years < 18:
            continue
        if not adult_woman(model):
            continue
        handle = str(model.get("username") or model.get("slug") or "").strip()
        name = str(model.get("display_name") or handle).strip()
        if not handle or not adult_allows(handle) or not adult_allows(name):
            continue
        tags = model.get("tags") or []
        if isinstance(tags, list):
            tag_blob = " ".join(str(tag) for tag in tags)
        else:
            tag_blob = str(tags)
        subject = str(model.get("room_subject") or "")
        if not adult_clean(tag_blob) or not adult_clean(subject):
            continue
        rid = f"adult-{handle.lower()}"
        if rid in seen:
            continue
        viewers = model.get("num_users")
        if viewers is None:
            viewers = model.get("viewersCount")
        if viewers is None:
            viewers = model.get("viewers")
        try:
            count = int(viewers)
        except (TypeError, ValueError):
            count = 0
        seen.add(rid)
        rooms.append(
            {
                "id": rid,
                "name": name.upper(),
                "handle": handle,
                "url": "",
                "viewers": count,
                "image": adult_image(model),
                "kinds": adult_room_kinds(model),
            }
        )
    rooms.sort(key=lambda row: (-int(row["viewers"]), str(row["name"])))
    return rooms[:ADULT_CAP]


def adult_page(
    rooms: list[dict],
    offset: int = 0,
    limit: int = ADULT_SCREEN,
    kind: str = "",
    query: str = "",
) -> list[dict]:
    """One screen of picked live rooms. TV never mounts the whole directory."""
    picked = adult_pick(rooms, kind=kind, query=query)
    start = max(0, int(offset))
    if limit <= 0:
        return []
    return picked[start : start + limit]


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
        self.assertIn("openStill", tv)
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


class OpenStillTests(unittest.TestCase):
    def test_open_sections_are_snap_stills_only(self):
        tv = read("Blackout", "TvPlate.swift")
        live = read("Blackout", "NaLive.swift")
        sock = read("Blackout", "UpdateSocket.swift")
        self.assertFalse((ROOT / "Blackout" / "DeskLive.swift").exists())
        open_tv = open_body(tv)
        self.assertNotIn("DeskLive", tv)
        self.assertNotIn("NaLiveWell", open_tv)
        self.assertNotIn("TAP PLAY", open_tv)
        self.assertNotIn("AVPlayer", tv)
        self.assertNotIn("WKWebView", tv)
        self.assertNotIn("rtmp", tv.lower())
        self.assertNotIn("zoocams.elpasozoo.org", tv.lower())
        self.assertNotIn("zoocams.elpasozoo.org", live.lower())
        self.assertNotIn("zoocams.elpasozoo.org", sock.lower())
        self.assertIn("TAP UPDATE", tv)
        self.assertIn("NO STILL", tv)
        self.assertIn("CamDesk.sections", tv)
        self.assertIn("openStill", tv)
        self.assertIn("AVPlayer", live)
        self.assertIn("TAP PLAY", live)
        self.assertIn("NO STREAM", live)
        self.assertIn("NO PIPE", live)


class AdultDeskTests(unittest.TestCase):
    def test_directory_keeps_live_public_rooms_and_resolves_hls(self):
        payload = {
            "results": [
                {
                    "username": "alpha",
                    "display_name": "alpha",
                    "age": 24,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 900,
                    "tags": ["dance", "blonde"],
                    "room_subject": "live",
                    "image_url": "https://img.example/alpha.jpg",
                    "image_url_360p": "https://img.example/alpha-360.jpg",
                },
                {
                    "username": "teenstar",
                    "display_name": "teenstar",
                    "age": 22,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 5000,
                    "tags": [],
                    "room_subject": "",
                },
                {
                    "username": "beta",
                    "display_name": "beta",
                    "age": 28,
                    "gender": "f",
                    "current_show": "private",
                    "num_users": 800,
                    "tags": [],
                    "room_subject": "",
                },
                {
                    "username": "gamma",
                    "display_name": "gamma",
                    "age": 17,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 10,
                    "tags": [],
                    "room_subject": "",
                },
                {
                    "username": "delta",
                    "display_name": "delta",
                    "age": 30,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 100,
                    "tags": ["teen"],
                    "room_subject": "",
                },
                {
                    "username": "echo",
                    "display_name": "echo",
                    "age": 26,
                    "current_show": "public",
                    "num_users": 400,
                    "tags": [],
                    "room_subject": "live",
                },
                {
                    "username": "omega",
                    "display_name": "omega",
                    "age": 29,
                    "gender": "m",
                    "current_show": "public",
                    "num_users": 8000,
                    "tags": ["dance"],
                    "room_subject": "live",
                    "image_url": "https://img.example/omega.jpg",
                },
                {
                    "username": "sigma",
                    "display_name": "sigma",
                    "age": 31,
                    "gender": "c",
                    "current_show": "public",
                    "num_users": 7000,
                    "tags": ["lesbian"],
                    "room_subject": "live",
                },
                {
                    "username": "tau",
                    "display_name": "tau",
                    "age": 27,
                    "gender": "s",
                    "current_show": "public",
                    "num_users": 6500,
                    "tags": ["dance"],
                    "room_subject": "live",
                },
                {
                    "username": "upsilon",
                    "display_name": "upsilon",
                    "age": 25,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 6000,
                    "tags": ["trans"],
                    "room_subject": "live",
                },
                {
                    "username": "phi",
                    "display_name": "phi",
                    "age": 28,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 5500,
                    "tags": ["shemale"],
                    "room_subject": "live",
                },
            ]
        }
        got = adult_rooms(payload)
        self.assertEqual([row["id"] for row in got], ["adult-alpha", "adult-echo"])
        self.assertEqual(got[0]["name"], "ALPHA")
        self.assertEqual(got[0]["handle"], "alpha")
        self.assertEqual(got[0]["url"], "")
        self.assertEqual(got[0]["image"], "https://img.example/alpha-360.jpg")
        self.assertEqual(got[0]["kinds"], ["DANCE", "BLONDE"])
        self.assertEqual(got[1]["handle"], "echo")
        self.assertEqual(got[1]["image"], "")
        self.assertEqual(got[1]["kinds"], [])
        self.assertTrue(adult_woman({"gender": "f"}))
        self.assertTrue(adult_woman({}))
        self.assertFalse(adult_woman({"gender": "m"}))
        self.assertFalse(adult_woman({"gender": "male"}))
        self.assertFalse(adult_woman({"gender": "c"}))
        self.assertFalse(adult_woman({"gender": "s"}))
        self.assertFalse(adult_woman({"gender": "trans"}))
        self.assertFalse(adult_woman({"gender": "shemale"}))
        self.assertFalse(adult_woman({"gender": "tgirl"}))
        self.assertFalse(adult_allows("transgirl"))
        self.assertFalse(adult_clean("shemale"))
        self.assertFalse(adult_clean("ladyboy live"))
        self.assertEqual(
            adult_image({"image_url": "https://img.example/a.jpg"}),
            "https://img.example/a.jpg",
        )
        self.assertEqual(
            adult_still("https://img.example/a.jpg"),
            "https://img.example/a.jpg",
        )
        self.assertIsNone(adult_still("http://img.example/a.jpg"))
        self.assertIsNone(adult_still("https://edge.example/live.m3u8"))
        self.assertEqual(adult_kinds(got), ["BLONDE", "DANCE"])
        self.assertEqual(
            [row["id"] for row in adult_pick(got, kind="DANCE")],
            ["adult-alpha"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(got, query="echo")],
            ["adult-echo"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(got, kind="ALL")],
            ["adult-alpha", "adult-echo"],
        )
        self.assertTrue(adult_allows("alpha"))
        self.assertFalse(adult_allows("teenstar"))
        self.assertIsNone(adult_playlist("http://insecure.example/x.m3u8"))
        self.assertIsNone(
            adult_playlist("https://media-hls.example/b-hls-1/cpa/v2/stream.m3u8")
        )
        self.assertEqual(
            adult_stream(
                {
                    "room_status": "public",
                    "hls_source": "https://edge.example/live-hls/amlst:alpha/playlist.m3u8",
                }
            ),
            "https://edge.example/live-hls/amlst:alpha/playlist.m3u8",
        )
        self.assertIsNone(
            adult_stream(
                {
                    "room_status": "public",
                    "hls_source": "https://media-hls.example/b-hls-1/cpa/v2/stream.m3u8",
                }
            )
        )
        self.assertIsNone(
            adult_stream({"room_status": "private", "hls_source": "https://edge.example/x.m3u8"})
        )
        desk = read("Blackout", "AdultDesk.swift")
        sock = read("Blackout", "UpdateSocket.swift")
        live = read("Blackout", "NaLive.swift")
        tv = read("Blackout", "TvPlate.swift")
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn("enum AdultDesk", desk)
        self.assertIn("static let cap", desk)
        self.assertIn("= 600", desk)
        self.assertIn("static let pageSize", desk)
        self.assertIn("static let pages", desk)
        self.assertIn("static func parse(", desk)
        self.assertIn("static func playlist(", desk)
        self.assertIn("static func directory(", desk)
        self.assertIn("static func context(", desk)
        self.assertIn("static func edge(", desk)
        self.assertIn("static func stream(", desk)
        self.assertIn("get_edge_hls_url_ajax", desk)
        self.assertIn("offset", desk)
        self.assertIn("chaturbate.com", desk.lower())
        self.assertIn("affiliates/onlinerooms", desk)
        self.assertIn('static let tags = ["f"]', desk)
        self.assertNotIn('["f", "c", "m", "s"]', desk)
        self.assertIn("static func still(", desk)
        self.assertIn("static func pick(", desk)
        self.assertIn("static func kinds(", desk)
        self.assertIn("static func woman(", desk)
        self.assertIn("image_url_360p", desk)
        self.assertIn("image_url", desk)
        self.assertIn("var image:", desk)
        self.assertIn("var kinds:", desk)
        self.assertIn("gender", desk)
        self.assertIn("\"trans\"", desk)
        self.assertIn("\"shemale\"", desk)
        self.assertIn("\"ladyboy\"", desk)
        self.assertIn("\"tgirl\"", desk)
        self.assertIn("hls_source", desk)
        self.assertIn("current_show", desk)
        self.assertIn("num_users", desk)
        self.assertNotIn("lovescape", desk.lower())
        self.assertNotIn("onlyfans", desk.lower())
        self.assertNotIn("fansly", desk.lower())
        self.assertNotIn("fanbase", desk.lower())
        self.assertNotIn("hlsPlaylist", desk)
        self.assertNotIn("iframe_embed", desk)
        self.assertIn("func pullAdult(", sock)
        self.assertIn("func pullAdultStills(", sock)
        self.assertIn("func liveAdult(", sock)
        self.assertIn("fetchAdult", sock)
        self.assertIn("adultRooms", sock)
        self.assertIn("AdultDesk.parse", sock)
        self.assertIn("AdultDesk.stream", sock)
        self.assertIn("AdultDesk.context", sock)
        self.assertIn("AdultDesk.edge", sock)
        self.assertIn("fetchAdultPost", sock)
        self.assertIn("AdultDesk.pages", sock)
        self.assertIn("offset:", sock)
        self.assertIn("User-Agent", sock)
        self.assertIn("X-Requested-With", sock)
        self.assertNotIn("lovescape", sock.lower())
        self.assertNotIn("WKWebView", desk)
        self.assertNotIn("WKWebView", sock)
        self.assertNotIn("URLSession", desk)
        self.assertNotIn("AVPlayer", sock)
        self.assertNotIn("AVPlayer", desk)
        self.assertIn("NaLive.rows", tv)
        self.assertIn("adultRooms", tv)
        self.assertIn("pullAdult", tv)
        self.assertIn("pullAdultStills", tv)
        self.assertIn('HUDField("SEARCH"', tv)
        self.assertIn("HUDWrapRail", tv)
        self.assertIn("naKind", tv)
        self.assertIn("naQuery", tv)
        self.assertIn("AdultDesk.pick", tv)
        self.assertIn("AdultDesk.kinds", tv)
        self.assertIn("NO MATCH", tv)
        self.assertIn("onPlay", tv)
        self.assertIn("liveAdult", tv)
        self.assertIn("liveAdult", app)
        gate = na_gate_body(tv)
        self.assertIn("NaLiveWell", gate)
        self.assertIn("naLiveRows", gate)
        self.assertNotIn("NaLiveWell", open_body(tv))
        self.assertIn("LIVE", live)
        self.assertIn("AdultDesk.Room", live)
        self.assertIn("onPlay", live)
        self.assertIn("handle", live)
        self.assertIn("var image:", live)
        self.assertIn("var kinds:", live)
        self.assertIn("let still: UIImage?", live)
        self.assertIn("static let screen", live)
        self.assertIn("static func page(", live)
        self.assertIn("static let screen = 8", live)
        self.assertIn("preferredForwardBufferDuration", live)
        self.assertNotIn("zoocams.elpasozoo.org", live.lower())
        self.assertIn("ForEach(naPageRows)", tv)
        self.assertNotIn("ForEach(naLiveRows)", tv)
        self.assertIn("MORE", gate)
        self.assertIn("BACK", gate)
        self.assertIn("adultReady", tv)
        self.assertIn("if naUnlocked { naGate }", tv)
        self.assertLess(tv.find("if naUnlocked { naGate }"), tv.find("ForEach(openBlocks)"))
        self.assertIn("adultReady", sock)
        self.assertIn("fetchAdultPages", sock)
        self.assertIn("Task.detached", sock)
        watch = tv.split(".task")[1].split("private var you")[0]
        self.assertNotIn("pullAdult", watch)
        rooms = [
            {"id": f"adult-{index}", "name": f"R{index}", "handle": f"r{index}", "url": "", "viewers": 100 - index}
            for index in range(30)
        ]
        self.assertEqual([row["id"] for row in adult_page(rooms)], [f"adult-{index}" for index in range(8)])
        self.assertEqual(len(adult_page(rooms, offset=8)), 8)
        self.assertEqual([row["id"] for row in adult_page(rooms, offset=24)], ["adult-24", "adult-25", "adult-26", "adult-27", "adult-28", "adult-29"])
        self.assertEqual(adult_page(rooms, offset=30), [])
        self.assertEqual(adult_page(rooms, offset=-4)[0]["id"], "adult-0")
        for word in ("truelook", "earthcam", "insecam", "stripchat"):
            self.assertNotIn(word, desk.lower())
            self.assertNotIn(word, live.lower())
            self.assertNotIn(word, sock.lower())
        for word in ("chaturbate",):
            self.assertNotIn(word, live.lower())
            self.assertNotIn(word, sock.lower())


class NaLiveTests(unittest.TestCase):
    def test_na_is_adult_only_after_hold(self):
        live = read("Blackout", "NaLive.swift")
        tv = read("Blackout", "TvPlate.swift")
        self.assertIn("enum NaLive", live)
        self.assertIn("AVPlayer", live)
        self.assertNotIn("WKWebView", live)
        self.assertNotIn("rtmp", live.lower())
        self.assertNotIn("zoocams.elpasozoo.org", live)
        self.assertIn("NaLive.rows", tv)
        self.assertIn("NaLiveWell", tv)
        self.assertIn("HOLD 10", tv)
        gate = na_gate_body(tv)
        self.assertIn("naLiveRows", gate)
        self.assertIn('HUDField("SEARCH"', gate)
        self.assertIn("HUDWrapRail", gate)
        self.assertIn("still:", gate)
        self.assertIn("pullAdultStills", gate)
        self.assertNotIn("DeskLive", gate)


class StillZoomTests(unittest.TestCase):
    def test_still_tap_opens_native_pinch_zoom(self):
        zoom = read("Blackout", "StillZoom.swift")
        tv = read("Blackout", "TvPlate.swift")
        card = read("Blackout", "CamHoldCard.swift")
        root = read("Blackout", "RootChrome.swift")
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn("struct StillZoom", zoom)
        self.assertIn("UIScrollView", zoom)
        self.assertIn("maximumZoomScale", zoom)
        self.assertIn("CLOSE", zoom)
        self.assertIn("contentsOfFile", zoom)
        self.assertNotIn("fullScreenCover", zoom)
        self.assertNotIn(".spring(", zoom)
        self.assertNotIn("WKWebView", zoom)
        self.assertIn("openStill", tv)
        self.assertIn("openStill", card)
        self.assertIn("zoomStillName", app)
        self.assertIn("func openStill(", app)
        self.assertIn("func closeStill(", app)
        self.assertIn("StillZoom", root)
        self.assertIn("closeStill", root)
        self.assertNotIn("fullScreenCover", root)


class LiveZoomTests(unittest.TestCase):
    def test_live_tap_opens_full_field_pinch(self):
        zoom = read("Blackout", "LiveZoom.swift")
        live = read("Blackout", "NaLive.swift")
        tv = read("Blackout", "TvPlate.swift")
        root = read("Blackout", "RootChrome.swift")
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn("struct LiveZoom", zoom)
        self.assertIn("AVPlayer", zoom)
        self.assertIn("UIScrollView", zoom)
        self.assertIn("maximumZoomScale", zoom)
        self.assertIn("CLOSE", zoom)
        self.assertIn("TAP FULL", live)
        self.assertIn("onFull", live)
        self.assertIn("openLive", tv)
        self.assertIn("zoomLive", app)
        self.assertIn("func openLive(", app)
        self.assertIn("func closeLive(", app)
        self.assertIn("LiveZoom", root)
        self.assertIn("closeLive", root)
        self.assertNotIn("fullScreenCover", zoom)
        self.assertNotIn("WKWebView", zoom)
        self.assertNotIn(".spring(", zoom)
        self.assertNotIn("rtmp", zoom.lower())


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
            "fansly",
            "fanbase",
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
        self.assertIn("TAP FULL", tv)
        self.assertIn("zoom", tv.lower())
        self.assertIn("section", tv.lower())
        self.assertIn("not a preview clip", tv.lower())
        self.assertIn("women", tv.lower())
        self.assertIn("no trans", tv.lower())
        self.assertIn("eight at a time", tv)
        self.assertIn("SEARCH", tv)
        self.assertIn("still", tv.lower())
        self.assertNotIn("insecam", tv.lower())
        self.assertNotIn("best in class", tv.lower())
        self.assertIn("test_expedition_tv.py", agents)
        self.assertIn("test_expedition_tv.py", validate)
        self.assertIn("expedition_tv()", validate)


def desk_text() -> str:
    return read("Blackout", "CamDesk.swift")


def na_gate_body(tv: str) -> str:
    start = tv.index("private var naGate")
    end = tv.index("private var naHoldRow", start)
    return tv[start:end]


def open_body(tv: str) -> str:
    return tv.split("private var naGate")[0]


if __name__ == "__main__":
    unittest.main()
