"""Public CCTV catalogs for the packed extracts.

God's Eye View already talks to TxDOT ITS and Austin Open Data. This writes
the same still URLs into cameras.json so UPDATE can SNAP them on the phone.
Never a live stream. NM has no public camera JSON — empty list is honest.
"""
from __future__ import annotations

import base64
import json
import re
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from .common import ROOT, write_json

TXDOT_ORIGIN = "https://its.txdot.gov"
AUSTIN_ROWS_URL = (
    "https://data.austintexas.gov/api/views/b4k4-adkb/rows.json?accessType=DOWNLOAD"
)
POINT_RE = re.compile(r"POINT\s*\(\s*([-\d.]+)\s+([-\d.]+)\s*\)", re.I)
PACK_DISTRICTS = {
    "tx-west": ("ELP",),
    "tx-east": ("AUS",),
    "nm": (),
}


def still_jpeg(data: bytes) -> bytes | None:
    """Raw JPEG, or TxDOT JSON `{snippet: base64 jpeg}`. Nothing else."""
    if len(data) >= 3 and data[0] == 0xFF and data[1] == 0xD8:
        return data
    try:
        obj = json.loads(data)
    except json.JSONDecodeError:
        return None
    if not isinstance(obj, dict):
        return None
    snippet = obj.get("snippet") or obj.get("Snippet")
    if not isinstance(snippet, str) or not snippet:
        return None
    try:
        raw = base64.b64decode(snippet)
    except Exception:
        return None
    if len(raw) >= 3 and raw[0] == 0xFF and raw[1] == 0xD8:
        return raw
    return None


def _get(url: str, timeout: int = 20) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "BlackoutPack/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _in_bbox(lat: float, lon: float, bbox: dict) -> bool:
    return bbox["south"] <= lat <= bbox["north"] and bbox["west"] <= lon <= bbox["east"]


def _txdot_id(district: str, icd: str) -> str:
    token = base64.urlsafe_b64encode(icd.encode()).decode().rstrip("=")
    return f"txdot-{district.lower()}-{token}"


def _txdot_url(district: str, icd: str) -> str:
    q = urllib.parse.quote(icd, safe="")
    return (
        f"{TXDOT_ORIGIN}/its/DistrictIts/GetCctvSnapshotByIcdId"
        f"?icdId={q}&districtCode={urllib.parse.quote(district)}"
    )


def load_txdot(district: str) -> list[dict[str, Any]]:
    raw = _get(
        f"{TXDOT_ORIGIN}/its/DistrictIts/GetCctvStatusListByDistrict"
        f"?districtCode={urllib.parse.quote(district)}"
    )
    data = json.loads(raw)
    roads = data.get("roadwayCctvStatuses") or {}
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    if not isinstance(roads, dict):
        return out
    for rows in roads.values():
        if not isinstance(rows, list):
            continue
        for row in rows:
            if not isinstance(row, dict):
                continue
            status = str(row.get("statusDescription") or "")
            if status.lower() != "device online" or not row.get("hasSnapshot"):
                continue
            try:
                lat = float(row.get("latitude"))
                lon = float(row.get("longitude"))
            except (TypeError, ValueError):
                continue
            if not (-90 < lat < 90 and -180 < lon < 180) or (lat == 0 and lon == 0):
                continue
            icd = str(row.get("icd_Id") or row.get("name") or "").strip()
            if not icd or icd in seen:
                continue
            seen.add(icd)
            name = str(row.get("name") or icd).strip() or icd
            out.append(
                {
                    "id": _txdot_id(district, icd),
                    "url": _txdot_url(district, icd),
                    "lat": lat,
                    "lon": lon,
                    "name": name,
                    "ink": "blue",
                    "provider": "TxDOT",
                }
            )
    return out


def load_austin() -> list[dict[str, Any]]:
    raw = _get(AUSTIN_ROWS_URL)
    payload = json.loads(raw)
    cols = payload.get("meta", {}).get("view", {}).get("columns") or []
    idx = {c.get("fieldName"): i for i, c in enumerate(cols)}
    need = ("camera_id", "location_name", "camera_status", "screenshot_address", "location")
    if any(k not in idx for k in need):
        return []
    out: list[dict[str, Any]] = []
    for row in payload.get("data") or []:
        if not isinstance(row, list):
            continue
        status = str(row[idx["camera_status"]] or "")
        if status.upper() != "TURNED_ON":
            continue
        shot = str(row[idx["screenshot_address"]] or "").strip()
        if not shot.startswith("http"):
            continue
        loc = row[idx["location"]]
        lat = lon = None
        if isinstance(loc, str):
            hit = POINT_RE.search(loc)
            if hit:
                lon = float(hit.group(1))
                lat = float(hit.group(2))
        if lat is None or lon is None:
            continue
        cam_id = str(row[idx["camera_id"]] or "").strip()
        if not cam_id:
            continue
        name = str(row[idx["location_name"]] or "").strip() or cam_id
        out.append(
            {
                "id": f"austin-{cam_id}",
                "url": shot,
                "lat": lat,
                "lon": lon,
                "name": name,
                "ink": "red",
                "provider": "Austin",
            }
        )
    return out


def clip(rows: list[dict[str, Any]], bbox: dict) -> list[dict[str, Any]]:
    return [row for row in rows if _in_bbox(row["lat"], row["lon"], bbox)]


def pack_cameras(pack_id: str, bbox: dict) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for district in PACK_DISTRICTS.get(pack_id, ()):
        rows.extend(load_txdot(district))
    if pack_id == "tx-east":
        rows.extend(load_austin())
    clipped = clip(rows, bbox)
    clipped.sort(key=lambda row: (row["lat"], row["lon"], row["id"]))
    return clipped


def write_cams(dest: Path) -> int:
    dest = dest.resolve()
    man = json.loads((dest / "manifest.json").read_text())
    bbox = man["bbox"]
    rows = pack_cameras(dest.name, bbox)
    write_json(dest / "cameras.json", rows)
    from . import fetch_packs

    fetch_packs.write_manifest(dest, man)
    return len(rows)


def write_all(root: Path | None = None) -> dict[str, int]:
    packs = root or (ROOT / "Resources" / "Packs")
    counts: dict[str, int] = {}
    for pid in ("tx-west", "tx-east", "nm"):
        dest = packs / pid
        counts[pid] = write_cams(dest)
        print(f"  cameras {pid} {counts[pid]}", flush=True)
    from . import fetch_packs

    fetch_packs.write_catalog(packs)
    return counts


if __name__ == "__main__":
    write_all()
