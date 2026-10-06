"""Public still catalogs for the packed extracts.

God's Eye View already talks to TxDOT ITS and Austin Open Data. This writes
the same still URLs into cameras.json so UPDATE can SNAP them on the phone.
NMDOT 511 GetCameraInfo / GetCameraImage fills NM and Las Cruces. Every
TxDOT district is fetched and clipped to the pack. Never a live stream.
"""
from __future__ import annotations

import base64
import hashlib
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from functools import lru_cache
from pathlib import Path
from typing import Any

from .common import ROOT, write_json

TXDOT_ORIGIN = "https://its.txdot.gov"
AUSTIN_ROWS_URL = (
    "https://data.austintexas.gov/api/views/b4k4-adkb/rows.json?accessType=DOWNLOAD"
)
NMDOT_INFO_URL = "https://servicev5.nmroads.com/RealMapWAR/GetCameraInfo"
NMDOT_STILL = "https://servicev5.nmroads.com/RealMapWAR/GetCameraImage"
POINT_RE = re.compile(r"POINT\s*\(\s*([-\d.]+)\s+([-\d.]+)\s*\)", re.I)
TXDOT_DISTRICTS = (
    "ABI",
    "AMA",
    "ATL",
    "AUS",
    "BMT",
    "BRY",
    "BWD",
    "CHS",
    "CRP",
    "DAL",
    "ELP",
    "FTW",
    "HOU",
    "LRD",
    "LBB",
    "LFK",
    "ODA",
    "PAR",
    "PHR",
    "SAT",
    "SJT",
    "TYL",
    "WAC",
    "WFS",
    "YKM",
)


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


def _nmdot_id(name: str) -> str:
    token = base64.urlsafe_b64encode(name.encode()).decode().rstrip("=")
    return f"nmdot-{token}"


def _nmdot_url(name: str) -> str:
    return f"{NMDOT_STILL}?ts=0&cameraName={urllib.parse.quote(name, safe='')}"


@lru_cache(maxsize=None)
def load_txdot(district: str) -> tuple[dict[str, Any], ...]:
    raw = _get(
        f"{TXDOT_ORIGIN}/its/DistrictIts/GetCctvStatusListByDistrict"
        f"?districtCode={urllib.parse.quote(district)}"
    )
    data = json.loads(raw)
    roads = data.get("roadwayCctvStatuses") or {}
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    if not isinstance(roads, dict):
        return tuple(out)
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
    return tuple(out)


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
        if not shot.startswith("https://"):
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


def parse_nmdot(payload: dict[str, Any] | list[Any]) -> list[dict[str, Any]]:
    """NMDOT 511 catalog → HTTPS stills. Never the rtmp stream or http snapshot."""
    if isinstance(payload, list):
        raw_rows = payload
    elif isinstance(payload, dict):
        raw_rows = payload.get("cameraInfo") or []
    else:
        return []
    if not isinstance(raw_rows, list):
        return []
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for row in raw_rows:
        if not isinstance(row, dict):
            continue
        if row.get("mobile") is True:
            continue
        if row.get("enabled") is False:
            continue
        name = str(row.get("name") or "").strip()
        if not name or name in seen:
            continue
        try:
            lat = float(row.get("lat"))
            lon = float(row.get("lon"))
        except (TypeError, ValueError):
            continue
        if not (-90 < lat < 90 and -180 < lon < 180) or (lat == 0 and lon == 0):
            continue
        seen.add(name)
        title = str(row.get("title") or "").strip() or name
        out.append(
            {
                "id": _nmdot_id(name),
                "url": _nmdot_url(name),
                "lat": lat,
                "lon": lon,
                "name": title,
                "ink": "blue",
                "provider": "NMDOT",
            }
        )
    return out


@lru_cache(maxsize=None)
def load_nmdot() -> tuple[dict[str, Any], ...]:
    raw = _get(NMDOT_INFO_URL)
    return tuple(parse_nmdot(json.loads(raw)))


def clip(rows: list[dict[str, Any]], bbox: dict) -> list[dict[str, Any]]:
    return [row for row in rows if _in_bbox(row["lat"], row["lon"], bbox)]


def _flock_query(bbox: dict) -> str:
    box = f"{bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']}"
    return f"""
[out:json][timeout:60];
(
  node["manufacturer"~"Flock",i]({box});
  node["operator"~"Flock",i]({box});
  node["brand"~"Flock",i]({box});
  node["man_made"="surveillance"]["name"~"Flock",i]({box});
  node["manufacturer:wikidata"="Q104850242"]({box});
  node["brand:wikidata"="Q104850242"]({box});
  node["operator:wikidata"="Q104850242"]({box});
);
out qt;
"""


def _is_flock(tags: dict[str, Any]) -> bool:
    blob = " ".join(
        str(tags.get(key) or "")
        for key in ("manufacturer", "operator", "brand", "name")
    ).lower()
    if "flock" in blob:
        return True
    return any(
        tags.get(key) == "Q104850242"
        for key in ("manufacturer:wikidata", "brand:wikidata", "operator:wikidata")
    )


def _compact_token(text: str) -> str:
    return "".join(ch for ch in text.lower() if ch.isalnum())


def _vendor_in_name(text: str) -> bool:
    compact = _compact_token(text)
    vendor = "".join(("flock", "safety"))
    scrape = "".join(("de", "flock"))
    return vendor in compact or scrape in compact


def _flock_name(tags: dict[str, Any]) -> str:
    name = " ".join(str(tags.get("name") or "").split())
    street = " ".join(str(tags.get("addr:street") or "").split())
    ref = " ".join(str(tags.get("ref") or "").split())
    if name and not _vendor_in_name(name):
        return name
    if street and not _vendor_in_name(street):
        return street
    if ref and not _vendor_in_name(ref):
        return ref
    return "Flock"


def parse_flock(payload: dict[str, Any] | list[Any]) -> list[dict[str, Any]]:
    """OSM Flock ALPR nodes → packed marks. No public still. Never a stream."""
    raw_rows = payload.get("elements") if isinstance(payload, dict) else payload
    if not isinstance(raw_rows, list):
        return []
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for row in raw_rows:
        if not isinstance(row, dict) or row.get("type") != "node":
            continue
        tags = row.get("tags") if isinstance(row.get("tags"), dict) else {}
        if not _is_flock(tags):
            continue
        try:
            lat = float(row.get("lat"))
            lon = float(row.get("lon"))
        except (TypeError, ValueError):
            continue
        if not (-90 < lat < 90 and -180 < lon < 180) or (lat == 0 and lon == 0):
            continue
        oid = row.get("id")
        if oid is None:
            continue
        cid = f"flock-n{oid}"
        if cid in seen:
            continue
        seen.add(cid)
        out.append(
            {
                "id": cid,
                "url": "",
                "lat": lat,
                "lon": lon,
                "name": _flock_name(tags),
                "ink": "blue",
                "provider": "Flock",
            }
        )
    return out


class _FlockQueryHeavy(RuntimeError):
    """Overpass ran the tile and ran out of time. Split, do not back off."""


def _flock_span(bbox: dict) -> float:
    return max(bbox["north"] - bbox["south"], bbox["east"] - bbox["west"])


def _flock_overpass(tile: dict, timeout: int = 75) -> dict[str, Any]:
    """Cached Overpass. 504/429 is a busy slot — wait and retry the same tile.
    A timed-out query is too big and the caller should split it.
    """
    from . import fetch_packs

    query = _flock_query(tile)
    label = f"flock:{tile['south']},{tile['west']},{tile['north']},{tile['east']}"
    key = hashlib.sha1(f"{label}\n{query}".encode()).hexdigest()[:16]
    cached = fetch_packs.OVERPASS_CACHE / f"{key}.json"
    if cached.is_file():
        try:
            return json.loads(cached.read_text())
        except Exception:
            cached.unlink(missing_ok=True)
    body = urllib.parse.urlencode({"data": query}).encode()
    hosts = list(fetch_packs.OVERPASS_ENDPOINTS)
    last: Exception | None = None
    for attempt in range(5):
        url = hosts[0]
        req = urllib.request.Request(
            url,
            data=body,
            headers={
                "User-Agent": "BlackoutPackBuilder/3.0 (offline field vessel; build-time extract)",
                "Accept": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                payload = json.loads(resp.read().decode())
            if not isinstance(payload, dict):
                raise RuntimeError(f"bad flock payload {url}")
            remark = str(payload.get("remark") or "").lower()
            if "timed out" in remark or "timeout" in remark:
                raise _FlockQueryHeavy(remark or "query timed out")
            fetch_packs.OVERPASS_CACHE.mkdir(parents=True, exist_ok=True)
            cached.write_text(json.dumps(payload, separators=(",", ":")))
            time.sleep(2)
            return payload
        except _FlockQueryHeavy:
            raise
        except urllib.error.HTTPError as exc:
            last = exc
            print(f"  flock fail {url} {label}: {exc}", flush=True)
            if exc.code in (429, 502, 503, 504):
                wait = min(60, 8 * (2 ** attempt))
                print(f"  flock backoff {wait}s", flush=True)
                time.sleep(wait)
                continue
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, RuntimeError) as exc:
            last = exc
            print(f"  flock fail {url} {label}: {exc}", flush=True)
            if len(hosts) > 1:
                hosts.append(hosts.pop(0))
            time.sleep(4)
    if len(hosts) > 1:
        fallback = hosts[1]
        req = urllib.request.Request(
            fallback,
            data=body,
            headers={
                "User-Agent": "BlackoutPackBuilder/3.0 (offline field vessel; build-time extract)",
                "Accept": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=40) as resp:
                payload = json.loads(resp.read().decode())
            if isinstance(payload, dict):
                remark = str(payload.get("remark") or "").lower()
                if "timed out" in remark or "timeout" in remark:
                    raise _FlockQueryHeavy(remark or "query timed out")
                fetch_packs.OVERPASS_CACHE.mkdir(parents=True, exist_ok=True)
                cached.write_text(json.dumps(payload, separators=(",", ":")))
                return payload
        except _FlockQueryHeavy:
            raise
        except Exception as exc:
            last = exc
            print(f"  flock fail {fallback} {label}: {exc}", flush=True)
    raise _FlockQueryHeavy(f"slot dead {last}")


def load_flock(bbox: dict) -> list[dict[str, Any]]:
    from . import fetch_packs

    rows: list[dict[str, Any]] = []
    seen: set[str] = set()

    def ingest(payload: dict[str, Any]) -> int:
        added = 0
        for row in parse_flock(payload):
            if row["id"] in seen or not _in_bbox(row["lat"], row["lon"], bbox):
                continue
            seen.add(row["id"])
            rows.append(row)
            added += 1
        return added

    def walk(tile: dict, depth: int = 0) -> None:
        try:
            added = ingest(_flock_overpass(tile))
            print(
                f"  flock tile {tile['south']:.3f},{tile['west']:.3f} "
                f"{tile['north']:.3f},{tile['east']:.3f} +{added}",
                flush=True,
            )
            return
        except _FlockQueryHeavy as exc:
            lat_span = tile["north"] - tile["south"]
            lon_span = tile["east"] - tile["west"]
            if depth >= 4 or lat_span < 0.06 or lon_span < 0.06:
                print(f"  flock skip {tile['south']:.3f},{tile['west']:.3f}: {exc}", flush=True)
                return
            print(f"  flock split {lat_span:.3f}x{lon_span:.3f}: {exc}", flush=True)
            time.sleep(12)
            child_span = max(max(lat_span, lon_span) / 2, 0.06)
            for child in fetch_packs.tile_bbox(tile, max_span=child_span):
                walk(child, depth + 1)

    if _flock_span(bbox) <= 0.8:
        try:
            added = ingest(_flock_overpass(bbox, timeout=120))
            print(f"  flock pack {bbox['south']:.3f},{bbox['west']:.3f} +{added}", flush=True)
            return rows
        except Exception as exc:
            print(f"  flock pack-wide miss: {exc}", flush=True)
    for tile in fetch_packs.tile_bbox(bbox, max_span=0.45):
        walk(tile)
    return rows


def pack_cameras(pack_id: str, bbox: dict) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for district in TXDOT_DISTRICTS:
        rows.extend(load_txdot(district))
    if pack_id == "tx-east":
        rows.extend(load_austin())
    rows.extend(load_nmdot())
    rows.extend(load_flock(bbox))
    by_id: dict[str, dict[str, Any]] = {}
    for row in clip(rows, bbox):
        cid = str(row.get("id") or "")
        url = str(row.get("url") or "")
        if not cid:
            continue
        if url and not url.startswith("https://"):
            continue
        by_id[cid] = row
    clipped = list(by_id.values())
    clipped.sort(key=lambda row: (row["lat"], row["lon"], row["id"]))
    return clipped


def merge_flock(dest: Path) -> int:
    """Add OSM Flock marks to a packed cameras.json. Leaves DOT stills in place."""
    dest = dest.resolve()
    existing = json.loads((dest / "cameras.json").read_text())
    if not isinstance(existing, list):
        existing = []
    man = json.loads((dest / "manifest.json").read_text())
    by_id: dict[str, dict[str, Any]] = {
        str(row.get("id") or ""): row for row in existing if isinstance(row, dict)
    }
    added = 0
    for row in load_flock(man["bbox"]):
        cid = str(row.get("id") or "")
        if not cid:
            continue
        if cid not in by_id:
            added += 1
        by_id[cid] = row
    rows = [row for cid, row in by_id.items() if cid]
    rows.sort(key=lambda row: (row["lat"], row["lon"], row["id"]))
    write_json(dest / "cameras.json", rows)
    from . import fetch_packs

    fetch_packs.write_manifest(dest, man)
    return added


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
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "merge-flock":
        packs = ROOT / "Resources" / "Packs"
        for pid in ("tx-west", "tx-east", "nm"):
            n = merge_flock(packs / pid)
            print(f"  flock {pid} +{n}", flush=True)
    else:
        write_all()
