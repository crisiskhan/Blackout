"""Packed KHAN EYE photo: USGS NAIP over each pack's metro, build-time only.

Airplane. The phone never asks the network. This is the public-domain NAIP
sheet for the city the pack actually walks, cut to raster tiles so a pitched
desk can read yards and roofs. Empty desert stays hillshade. Not a live photo
mesh, not a world feed.
"""

from __future__ import annotations

import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

from pmtiles.reader import MmapSource, Reader
from pmtiles.tile import Compression, TileType, zxy_to_tileid
from pmtiles.writer import Writer

from .tiles import tile_bounds, tile_range

NAIP_EXPORT = (
    "https://imagery.nationalmap.gov/arcgis/rest/services/"
    "USGSNAIPImagery/ImageServer/exportImage"
)
NAIP_CREDIT = "USGS NAIP, build-time only"
AERIAL_SOURCE_ID = "aerial"
AERIAL_LAYER_ID = "aerial"
AERIAL_FILE = "aerial.pmtiles"
AERIAL_FLOOR_ZOOM = 12
AERIAL_MIN_ZOOM = 12
AERIAL_DETAIL_MIN = 14
AERIAL_MAX_ZOOM = 17
TILE_PX = 256
WORKERS = 12
JPEG_MAGIC = b"\xff\xd8"

# Extra packed photo walks. Metro is downtown; YOU on Oleaster sits west of it.
PHOTO_EXTRA = {
    "tx-west": [
        {
            "name": "Oleaster–Canutillo walk",
            "south": 31.85,
            "west": -106.63,
            "north": 31.94,
            "east": -106.55,
            "maxzoom": 17,
        },
        {
            "name": "Vinton–Anthony walk",
            "south": 31.82,
            "west": -106.68,
            "north": 32.06,
            "east": -106.50,
            "maxzoom": 16,
        },
    ]
}


def slice_bbox(sl: dict) -> dict:
    box = sl.get("bbox") or sl
    return {
        "south": float(box["south"]),
        "west": float(box["west"]),
        "north": float(box["north"]),
        "east": float(box["east"]),
    }


def metro_bbox(pack: dict) -> dict:
    metro = pack.get("slices", {}).get("metro") or {}
    return slice_bbox(metro)


def region_bbox(pack: dict) -> dict:
    region = pack.get("slices", {}).get("region") or {}
    return slice_bbox(region)


def extra_maxzoom(item: dict) -> int:
    return int(item.get("maxzoom") or AERIAL_MAX_ZOOM)


def photo_bboxes(pack: dict) -> list[dict]:
    boxes = [metro_bbox(pack)]
    for item in PHOTO_EXTRA.get(str(pack.get("id") or ""), []):
        boxes.append(
            {
                "south": float(item["south"]),
                "west": float(item["west"]),
                "north": float(item["north"]),
                "east": float(item["east"]),
            }
        )
    return boxes


def union_photo_bbox(boxes: list[dict]) -> dict:
    return {
        "south": min(b["south"] for b in boxes),
        "west": min(b["west"] for b in boxes),
        "north": max(b["north"] for b in boxes),
        "east": max(b["east"] for b in boxes),
    }


def read_archive(path: Path) -> dict[tuple[int, int, int], bytes]:
    got: dict[tuple[int, int, int], bytes] = {}
    with open(path, "rb") as fh:
        reader = Reader(MmapSource(fh))
        header = reader.header()
        bbox = {
            "west": header["min_lon_e7"] / 1e7,
            "south": header["min_lat_e7"] / 1e7,
            "east": header["max_lon_e7"] / 1e7,
            "north": header["max_lat_e7"] / 1e7,
        }
        for z in range(int(header["min_zoom"]), int(header["max_zoom"]) + 1):
            x0, y0, x1, y1 = tile_range(bbox, z)
            for x in range(x0, x1 + 1):
                for y in range(y0, y1 + 1):
                    blob = reader.get(z, x, y)
                    if blob:
                        got[(z, x, y)] = blob
    return got


def style_source() -> dict:
    return {
        "type": "raster",
        "url": f"pmtiles://{AERIAL_FILE}",
        "tileSize": TILE_PX,
        "attribution": NAIP_CREDIT,
    }


def style_layer() -> dict:
    return {
        "id": AERIAL_LAYER_ID,
        "type": "raster",
        "source": AERIAL_SOURCE_ID,
        "minzoom": AERIAL_MIN_ZOOM,
        "maxzoom": 22,
        "layout": {"visibility": "none"},
        "paint": {"raster-opacity": 1, "raster-fade-duration": 0},
    }


def insert_aerial_layer(layers: list[dict]) -> None:
    if any(item.get("id") == AERIAL_LAYER_ID for item in layers):
        return
    ids = [item.get("id") for item in layers]
    if "land-fill" in ids:
        layers.insert(ids.index("land-fill") + 1, style_layer())
    else:
        layers.append(style_layer())


def _http_jpeg(url: str, timeout: int = 90) -> bytes | None:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "BlackoutPackBuilder/3.0 (offline field vessel; build-time extract)",
            "Accept": "image/jpeg,image/*,*/*",
        },
    )
    last: Exception | None = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
            if raw.startswith(JPEG_MAGIC) and len(raw) > 800:
                return raw
            return None
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last = exc
            continue
    if last:
        return None
    return None


def fetch_tile_jpeg(z: int, x: int, y: int) -> bytes | None:
    west, south, east, north = tile_bounds(z, x, y)
    qs = urllib.parse.urlencode(
        {
            "bbox": f"{west},{south},{east},{north}",
            "bboxSR": "4326",
            "size": f"{TILE_PX},{TILE_PX}",
            "imageSR": "4326",
            "format": "jpg",
            "f": "image",
        }
    )
    return _http_jpeg(f"{NAIP_EXPORT}?{qs}")


def wanted_tiles(bbox: dict, z0: int, z1: int) -> list[tuple[int, int, int]]:
    out: list[tuple[int, int, int]] = []
    for z in range(z0, z1 + 1):
        x0, y0, x1, y1 = tile_range(bbox, z)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                out.append((z, x, y))
    return out


def aerial_jobs(pack: dict) -> list[tuple[int, int, int]]:
    """Pack-wide z12 floor plus metro/walk detail. z17 stays on the yards extra."""
    seen: set[tuple[int, int, int]] = set()
    jobs: list[tuple[int, int, int]] = []

    def add(box: dict, z0: int, z1: int) -> None:
        for zxy in wanted_tiles(box, z0, z1):
            if zxy in seen:
                continue
            seen.add(zxy)
            jobs.append(zxy)

    add(region_bbox(pack), AERIAL_FLOOR_ZOOM, AERIAL_FLOOR_ZOOM)
    add(metro_bbox(pack), AERIAL_DETAIL_MIN, AERIAL_MAX_ZOOM)
    for item in PHOTO_EXTRA.get(str(pack.get("id") or ""), []):
        box = {
            "south": float(item["south"]),
            "west": float(item["west"]),
            "north": float(item["north"]),
            "east": float(item["east"]),
        }
        add(box, AERIAL_DETAIL_MIN, extra_maxzoom(item))
    return jobs


def build_aerial(dest: Path, pack: dict) -> dict[str, Any]:
    """Write `aerial.pmtiles` for pack floor plus metro/walk extras. Skip rather than fake photo."""
    jobs = aerial_jobs(pack)
    bbox = region_bbox(pack)
    got: dict[tuple[int, int, int], bytes] = {}
    existing = dest / AERIAL_FILE
    if existing.is_file():
        with open(existing, "rb") as fh:
            reader = Reader(MmapSource(fh))
            for z, x, y in jobs:
                blob = reader.get(z, x, y)
                if blob:
                    got[(z, x, y)] = blob
        print(f"  NAIP {pack['id']} reuse {len(got)} packed jpeg", flush=True)
    missing = [zxy for zxy in jobs if zxy not in got]
    print(f"  NAIP {pack['id']} photo {len(jobs)} tiles, fetch {len(missing)}", flush=True)
    if missing:
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            futs = {pool.submit(fetch_tile_jpeg, z, x, y): (z, x, y) for z, x, y in missing}
            done = 0
            for fut in as_completed(futs):
                zxy = futs[fut]
                done += 1
                try:
                    blob = fut.result()
                except Exception:
                    blob = None
                if blob:
                    got[zxy] = blob
                if done % 40 == 0 or done == len(missing):
                    print(
                        f"  NAIP {pack['id']} {done}/{len(missing)} fetched {len(got)} jpeg",
                        flush=True,
                    )
    if len(got) < 20:
        return {"present": False, "reason": f"NAIP returned {len(got)} tiles", "tiles": 0}
    out = dest / AERIAL_FILE
    with open(out, "wb") as fh:
        writer = Writer(fh)
        for z, x, y in sorted(got):
            writer.write_tile(zxy_to_tileid(z, x, y), got[(z, x, y)])
        writer.finalize(
            {
                "tile_type": TileType.JPEG,
                "tile_compression": Compression.NONE,
                "min_zoom": AERIAL_MIN_ZOOM,
                "max_zoom": AERIAL_MAX_ZOOM,
                "min_lon_e7": int(bbox["west"] * 1e7),
                "min_lat_e7": int(bbox["south"] * 1e7),
                "max_lon_e7": int(bbox["east"] * 1e7),
                "max_lat_e7": int(bbox["north"] * 1e7),
                "center_zoom": 16,
                "center_lon_e7": int((bbox["west"] + bbox["east"]) / 2 * 1e7),
                "center_lat_e7": int((bbox["south"] + bbox["north"]) / 2 * 1e7),
            },
            {
                "name": f"{pack['name']} KHAN EYE photo",
                "format": "jpg",
                "attribution": NAIP_CREDIT,
            },
        )
    return {
        "present": True,
        "file": AERIAL_FILE,
        "tiles": len(got),
        "bytes": out.stat().st_size,
        "attribution": NAIP_CREDIT,
    }
