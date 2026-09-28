#!/usr/bin/env python3
"""Hop-reachable cameras on MAP as pink/orange discs. Stills SNAP the same way.

Packed CCTV stays red/blue. A hop radio is not a camera. Silence is not a camera.
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


def paint(pack_ids: list[str], hops: list[dict]) -> list[dict]:
    """Hop cameras that are not already packed CCTV. Never invent from silence."""
    packed = {pid for pid in pack_ids if pid}
    seen: set[str] = set()
    out: list[dict] = []
    for cam in hops:
        cid = str(cam.get("id") or "").strip()
        lat = cam.get("lat")
        lon = cam.get("lon")
        if not cid or cid in packed or cid in seen:
            continue
        if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
            continue
        if not math.isfinite(lat) or not math.isfinite(lon):
            continue
        seen.add(cid)
        out.append(cam)
    return out


def encode_cam(
    cam_id: str,
    lat: float,
    lon: float,
    name: str,
    url: str,
    provider: str,
) -> str:
    def clean(raw: str) -> str:
        return raw.replace("\t", " ").replace("\n", " ").strip()

    return "\t".join(
        [
            clean(cam_id),
            str(lat),
            str(lon),
            clean(name),
            clean(url),
            clean(provider),
        ]
    )


def parse_cam(raw: str) -> dict | None:
    parts = raw.split("\t")
    if len(parts) < 6:
        return None
    try:
        lat = float(parts[1])
        lon = float(parts[2])
    except ValueError:
        return None
    if not math.isfinite(lat) or not math.isfinite(lon):
        return None
    cid = parts[0].strip()
    if not cid:
        return None
    return {
        "id": cid,
        "lat": lat,
        "lon": lon,
        "name": parts[3],
        "url": parts[4],
        "provider": parts[5],
    }


def parse_cam_batch(raw: str) -> list[dict]:
    out: list[dict] = []
    for line in raw.splitlines():
        parsed = parse_cam(line)
        if parsed is not None:
            out.append(parsed)
    return out


def encode_still(cam_id: str, jpeg: bytes) -> bytes:
    return cam_id.encode("utf-8") + b"\n" + jpeg


def parse_still(data: bytes) -> tuple[str, bytes] | None:
    nl = data.find(b"\n")
    if nl <= 0:
        return None
    cid = data[:nl].decode("utf-8", errors="replace").strip()
    jpeg = data[nl + 1 :]
    if not cid or len(jpeg) < 3 or jpeg[:3] != b"\xff\xd8\xff":
        return None
    return cid, jpeg


def snap_targets(
    pack: list[dict], hops: list[dict], lat: float, lon: float, cap: int = 16
) -> list[dict]:
    """Nearest HTTPS stills from packed CCTV plus hop cameras. One id, one slot."""
    by_id: dict[str, dict] = {}
    for cam in pack + hops:
        cid = str(cam.get("id") or "").strip()
        url = str(cam.get("url") or "")
        if not cid or not url.startswith("https://"):
            continue
        by_id[cid] = cam

    def range2(cam: dict) -> float:
        dlat = float(cam["lat"]) - lat
        dlon = (float(cam["lon"]) - lon) * math.cos(lat * math.pi / 180)
        return dlat * dlat + dlon * dlon

    return sorted(by_id.values(), key=range2)[:cap]


JPEG = bytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])


class MeshCamPaintTests(unittest.TestCase):
    def test_silence_is_not_a_camera(self):
        self.assertEqual(paint([], []), [])

    def test_a_hop_radio_is_not_a_camera(self):
        # Hears never enter paint. An empty cam list stays empty while radios exist.
        self.assertEqual(paint([], []), [])

    def test_pack_id_keeps_the_red_blue_disc(self):
        hops = [
            {
                "id": "txdot-oleaster",
                "lat": 31.87,
                "lon": -106.59,
                "name": "Loop 375",
                "url": "https://its.txdot.gov/a.jpg",
                "provider": "TxDOT",
            },
            {
                "id": "peer-open-1",
                "lat": 31.88,
                "lon": -106.58,
                "name": "Open cam",
                "url": "https://example.invalid/cam.jpg",
                "provider": "HOP",
            },
        ]
        shown = paint(["txdot-oleaster"], hops)
        self.assertEqual([row["id"] for row in shown], ["peer-open-1"])

    def test_duplicate_hop_id_paints_once(self):
        hops = [
            {"id": "a", "lat": 31.1, "lon": -106.1},
            {"id": "a", "lat": 31.2, "lon": -106.2},
        ]
        shown = paint([], hops)
        self.assertEqual(len(shown), 1)
        self.assertEqual(shown[0]["lat"], 31.1)

    def test_broken_coords_stay_off_the_desk(self):
        hops = [
            {"id": "nan", "lat": float("nan"), "lon": -106.1},
            {"id": "blank", "lat": 31.1, "lon": -106.1, "name": ""},
            {"id": "", "lat": 31.1, "lon": -106.1},
        ]
        shown = paint([], hops)
        self.assertEqual([row["id"] for row in shown], ["blank"])


class MeshCamWireTests(unittest.TestCase):
    def test_cam_tsv_roundtrip(self):
        raw = encode_cam(
            "peer-open-1",
            31.8705,
            -106.5973,
            "Loop 375",
            "https://its.txdot.gov/a.jpg",
            "TxDOT",
        )
        parsed = parse_cam(raw)
        self.assertEqual(parsed["id"], "peer-open-1")
        self.assertAlmostEqual(parsed["lat"], 31.8705)
        self.assertAlmostEqual(parsed["lon"], -106.5973)
        self.assertEqual(parsed["name"], "Loop 375")
        self.assertEqual(parsed["url"], "https://its.txdot.gov/a.jpg")
        self.assertEqual(parsed["provider"], "TxDOT")
        self.assertIsNone(parse_cam("only-one-field"))
        self.assertIsNone(parse_cam("id\tx\t-106\tname\turl\tprov"))

    def test_cam_batch_is_one_envelope(self):
        lines = "\n".join(
            [
                encode_cam("a", 31.1, -106.1, "A", "https://a.example/a.jpg", "HOP"),
                encode_cam("b", 31.2, -106.2, "B", "", "HOP"),
            ]
        )
        rows = parse_cam_batch(lines)
        self.assertEqual([row["id"] for row in rows], ["a", "b"])
        self.assertEqual(rows[1]["url"], "")

    def test_still_is_id_then_jpeg(self):
        body = encode_still("peer-open-1", JPEG)
        parsed = parse_still(body)
        self.assertEqual(parsed[0], "peer-open-1")
        self.assertEqual(parsed[1][:3], b"\xff\xd8\xff")
        self.assertIsNone(parse_still(b"peer-open-1\n<html>nope</html>"))
        self.assertIsNone(parse_still(JPEG))


class MeshCamSnapTests(unittest.TestCase):
    def test_snap_unions_pack_and_hop_https_and_caps(self):
        pack = [
            {
                "id": "far-pack",
                "lat": 32.0,
                "lon": -107.0,
                "url": "https://its.txdot.gov/far.jpg",
            },
            {
                "id": "near-pack",
                "lat": 31.8705,
                "lon": -106.5973,
                "url": "https://its.txdot.gov/near.jpg",
            },
        ]
        hops = [
            {
                "id": "near-pack",
                "lat": 31.8705,
                "lon": -106.5973,
                "url": "https://its.txdot.gov/dup.jpg",
            },
            {
                "id": "hop-near",
                "lat": 31.8710,
                "lon": -106.5970,
                "url": "https://peer.example/cam.jpg",
            },
            {
                "id": "hop-no-url",
                "lat": 31.8710,
                "lon": -106.5970,
                "url": "",
            },
        ]
        got = snap_targets(pack, hops, 31.8705, -106.5973, cap=16)
        self.assertEqual([row["id"] for row in got], ["near-pack", "hop-near", "far-pack"])
        self.assertTrue(got[0]["url"].startswith("https://"))
        many = [
            {
                "id": f"c{i}",
                "lat": 31.87 + i * 0.01,
                "lon": -106.59,
                "url": f"https://x.example/{i}.jpg",
            }
            for i in range(20)
        ]
        self.assertEqual(len(snap_targets([], many, 31.87, -106.59, cap=16)), 16)


class MeshCamHudTests(unittest.TestCase):
    def test_map_paints_a_pink_and_orange_disc_per_hop_camera(self):
        art = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MeshCamArt.swift")
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        swift = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        inspect = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "Inspect.swift")
        self.assertIn("enum MeshCamArt", art)
        self.assertIn("static func dot(", art)
        self.assertIn("64.0 / 255.0", art)
        self.assertIn("160.0 / 255.0", art)
        self.assertIn("128.0 / 255.0", art)
        self.assertNotIn("225.0 / 255.0", art)
        self.assertNotIn("61.0 / 255.0", art)
        self.assertIn("mesh-cam-mark", swift + offline + art)
        self.assertIn("enum MeshCamMarks", swift)
        self.assertIn("var meshCams: [CctvMark]", offline)
        spec = offline.split("struct OverlaySpec")[1].split("var spec:")[0]
        self.assertIn("var meshCams: [CctvMark]", spec)
        self.assertIn("static func ==", spec)
        self.assertIn("lhs.meshCams == rhs.meshCams", spec)
        self.assertIn("func paintMeshCams", offline)
        self.assertIn("func meshCamMark(at", offline)
        self.assertIn("MeshCamArt.dot()", offline)
        self.assertIn("MeshCamMarks.layerID", inspect)
        tap = offline.split("func handleTap")[1].split("func handleDoubleTap")[0]
        self.assertIn("meshCamMark(at:", tap)
        self.assertLess(tap.find("cctvMark(at:"), tap.find("meshCamMark(at:"))
        self.assertLess(tap.find("meshCamMark(at:"), tap.find("onMapTap"))
        hold = offline.split("func handleHold")[1].split("func personMark")[0]
        self.assertIn("meshCamMark(at:", hold)
        self.assertLess(hold.find("cctvMark(at:"), hold.find("meshCamMark(at:"))

    def test_hop_kind_carries_cameras_and_stills(self):
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        self.assertIn("enum MeshCamBody", mesh)
        self.assertIn("enum MeshCamStillBody", mesh)
        self.assertIn("enum MeshCamPaint", mesh)
        self.assertIn("func sendCams", mesh)
        self.assertIn("func sendCamStill", mesh)
        self.assertIn('kind: "cam"', mesh)
        self.assertIn('kind: "cam.still"', mesh)
        receive = mesh.split("private func receive")[1].split("private func upsertPip")[0]
        self.assertIn('"cam"', receive)
        self.assertIn('"cam.still"', receive)
        self.assertNotIn("URLSession", mesh)

    def test_update_snaps_hop_stills_the_same_way(self):
        sock = read("Blackout", "UpdateSocket.swift")
        app = read("Blackout", "AppRuntime.swift")
        card = read("Blackout", "CamHoldCard.swift")
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("extraCams", sock)
        self.assertIn("hopStills", sock)
        self.assertIn("func applyHopStills", sock)
        self.assertIn("CctvMarks.snapCap", sock)
        self.assertIn("func stillJPEG", sock)
        self.assertNotIn("AVPlayer", sock)
        self.assertNotIn("WKWebView", sock)
        self.assertIn("var meshCams", app)
        self.assertIn("func advertisePackCams", app)
        hold = app.split("func holdCam")[1].split("func holdAddress")[0]
        self.assertIn("meshCams", hold)
        inbound = app.split("func applyInbound")[1].split("func raiseIncoming")[0]
        self.assertIn('case "cam"', inbound)
        self.assertIn('case "cam.still"', inbound)
        tap = app.split("func tapUpdate")[1].split("func fitPack")[0]
        self.assertIn("hopCamStills", tap)
        self.assertIn("extraCams", tap)
        self.assertIn("sendCamStill", tap)
        self.assertIn("meshCams:", tab)
        self.assertIn("TAP UPDATE", card)
        self.assertIn("NO STILL", card)
        self.assertIn("NO PIPE", card)
        self.assertIn("cam-", card)

    def test_device_script_scores_pink_orange_hop_discs(self):
        qa = read("docs", "SOLO_QA.md")
        agents = read("AGENTS.md")
        self.assertIn("half pink half orange", qa.lower())
        self.assertIn("TAP UPDATE", qa)
        self.assertIn("test_mesh_cams.py", agents)
        validate = read("tools", "validate_v3.py")
        self.assertIn("test_mesh_cams.py", validate)
        self.assertIn("mesh_cams()", validate)


if __name__ == "__main__":
    unittest.main()
