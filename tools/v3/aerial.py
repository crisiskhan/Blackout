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
AERIAL_MIN_ZOOM = 14
AERIAL_MAX_ZOOM = 17
TILE_PX = 256
WORKERS = 12
JPEG_MAGIC = b"\xff\xd8"


def metro_bbox(pack: dict) -> dict:
    metro = pack.get("slices", {}).get("metro") or {}
    return {
        "south": float(metro["south"]),
        "west": float(metro["west"]),
        "north": float(metro["north"]),
        "east": float(metro["east"]),
    }


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


def wanted_tiles(bbox: dict) -> list[tuple[int, int, int]]:
    out: list[tuple[int, int, int]] = []
    for z in range(AERIAL_MIN_ZOOM, AERIAL_MAX_ZOOM + 1):
        x0, y0, x1, y1 = tile_range(bbox, z)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                out.append((z, x, y))
    return out


def build_aerial(dest: Path, pack: dict) -> dict[str, Any]:
    """Write `aerial.pmtiles` for the pack metro. Skip rather than fake photo."""
    bbox = metro_bbox(pack)
    jobs = wanted_tiles(bbox)
    got: dict[tuple[int, int, int], bytes] = {}
    print(f"  NAIP {pack['id']} metro {len(jobs)} tiles", flush=True)
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futs = {pool.submit(fetch_tile_jpeg, z, x, y): (z, x, y) for z, x, y in jobs}
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
            if done % 200 == 0 or done == len(jobs):
                print(f"  NAIP {pack['id']} {done}/{len(jobs)} fetched {len(got)} jpeg", flush=True)
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
