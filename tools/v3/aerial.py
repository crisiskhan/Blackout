"""Packed walking-desk photo: USGS NAIP over each pack extract, build-time only.

Airplane. The phone never asks the network. Street-scale NAIP covers the
whole packed extract; walking zoom is yard-scale on the walkable ground.
Not a live photo mesh, not a world feed.
"""

from __future__ import annotations

import math
import shutil
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

from pmtiles.reader import MmapSource, Reader, all_tiles
from pmtiles.tile import Compression, TileType, zxy_to_tileid
from pmtiles.writer import Writer

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
# Packed tiles start at z12. Style minzoom is the EYE pack camera so MapLibre
# can underzoom that floor instead of dropping to yellow land-fill.
AERIAL_STYLE_MIN_ZOOM = 6
AERIAL_DETAIL_MIN = 14
AERIAL_FILL_ZOOM = 15
AERIAL_MAX_ZOOM = 17
TILE_PX = 256
WORKERS = 32
JPEG_MAGIC = b"\xff\xd8"
SHARD_MAX_BYTES = 90 * 1024 * 1024
PACK_BUDGET_MIB = 4096
CACHE_DIR = ".naip-cache"
WRITE_DIR = ".aerial-write"
# Leave room for the PMTiles directory so a shard stays under GitHub's 100 MB.
SHARD_PAYLOAD_BYTES = SHARD_MAX_BYTES - (2 * 1024 * 1024)
# Blend this many pixels across a shared tile edge so NAIP is one photo.
FEATHER_PX = 8
# Walking desk Crisis scored: Vinton–Anthony plus Doniphan retail east of Oleaster.
SEAM_BOXES = {
    "tx-west": {
        "south": 31.82,
        "west": -106.68,
        "north": 32.06,
        "east": -106.48,
    }
}

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


def walkable_bbox(pack: dict) -> dict:
    """Union of every slice except the wide region extract."""
    boxes = [
        slice_bbox(sl)
        for key, sl in (pack.get("slices") or {}).items()
        if key != "region"
    ]
    if not boxes:
        return region_bbox(pack)
    return union_photo_bbox(boxes)


def extra_maxzoom(item: dict) -> int:
    return int(item.get("maxzoom") or AERIAL_MAX_ZOOM)


def photo_bboxes(pack: dict) -> list[dict]:
    boxes = [region_bbox(pack), walkable_bbox(pack), metro_bbox(pack)]
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


def source_id_for_file(name: str) -> str:
    if name.endswith(".pmtiles"):
        return name[: -len(".pmtiles")]
    return name


def shard_file_name(index: int) -> str:
    if index == 0:
        return AERIAL_FILE
    return f"aerial-{index}.pmtiles"


def shard_names(dest: Path) -> list[str]:
    files = [p.name for p in dest.glob("aerial*.pmtiles") if p.is_file()]

    def key(name: str) -> tuple[int, int]:
        stem = name.removesuffix(".pmtiles")
        if stem == "aerial":
            return (0, 0)
        _, _, rest = stem.partition("-")
        if rest.startswith("seam"):
            tail = rest[4:]
            part = int(tail[1:]) if tail.startswith("-") and tail[1:].isdigit() else 0
            return (2, part)
        return (1, int(rest) if rest.isdigit() else 0)

    return sorted(files, key=key)


def read_archive(path: Path) -> dict[tuple[int, int, int], bytes]:
    # Walk the PMTiles directory. Do not import tiles.py here: that module
    # pulls mapbox_vector_tile, which the copy-resources python3 does not have.
    got: dict[tuple[int, int, int], bytes] = {}
    with open(path, "rb") as fh:
        for zxy, blob in all_tiles(MmapSource(fh)):
            if blob:
                got[zxy] = blob
    return got


def style_source(name: str = AERIAL_FILE) -> dict:
    return {
        "type": "raster",
        "url": f"pmtiles://{name}",
        "tileSize": TILE_PX,
        "attribution": NAIP_CREDIT,
    }


def style_layer(name: str = AERIAL_FILE) -> dict:
    sid = source_id_for_file(name)
    return {
        "id": sid,
        "type": "raster",
        "source": sid,
        "minzoom": AERIAL_STYLE_MIN_ZOOM,
        "maxzoom": 22,
        "layout": {"visibility": "none"},
        "paint": {
            "raster-opacity": 1,
            "raster-fade-duration": 0,
            "raster-resampling": "linear",
        },
    }


def insert_aerial_layer(layers: list[dict], names: list[str] | None = None) -> None:
    names = names or [AERIAL_FILE]
    kept = [item for item in layers if not str(item.get("id") or "").startswith("aerial")]
    layers.clear()
    layers.extend(kept)
    ids = [item.get("id") for item in layers]
    at = ids.index("land-fill") + 1 if "land-fill" in ids else len(layers)
    for name in names:
        layers.insert(at, style_layer(name))
        at += 1


def _http_jpeg(url: str, timeout: int = 90) -> bytes | None:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "BlackoutPackBuilder/3.0 (offline field vessel; build-time extract)",
            "Accept": "image/jpeg,image/*,*/*",
        },
    )
    last: Exception | None = None
    for _attempt in range(4):
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
    from .tiles import tile_bounds

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
    from .tiles import tile_range

    out: list[tuple[int, int, int]] = []
    for z in range(z0, z1 + 1):
        x0, y0, x1, y1 = tile_range(bbox, z)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                out.append((z, x, y))
    return out


def aerial_jobs(pack: dict) -> list[tuple[int, int, int]]:
    """Street-scale fill on the extract; yard-scale on the walkable ground.

    z17 stays on metro + PHOTO_EXTRA (Oleaster yards). Pack-wide z17 blows
    the 4 GiB IPA/ZIP32 ceiling once the ASK model is in the archive.
    """
    seen: set[tuple[int, int, int]] = set()
    jobs: list[tuple[int, int, int]] = []

    def add(box: dict, z0: int, z1: int) -> None:
        for zxy in wanted_tiles(box, z0, z1):
            if zxy in seen:
                continue
            seen.add(zxy)
            jobs.append(zxy)

    pid = str(pack.get("id") or "")
    region = region_bbox(pack)
    walk = walkable_bbox(pack)
    add(region, AERIAL_FLOOR_ZOOM, AERIAL_FLOOR_ZOOM)
    add(region, AERIAL_DETAIL_MIN, AERIAL_FILL_ZOOM)
    add(walk, 16, 16)
    add(metro_bbox(pack), AERIAL_DETAIL_MIN, AERIAL_MAX_ZOOM)
    for item in PHOTO_EXTRA.get(pid, []):
        box = {
            "south": float(item["south"]),
            "west": float(item["west"]),
            "north": float(item["north"]),
            "east": float(item["east"]),
        }
        add(box, AERIAL_DETAIL_MIN, extra_maxzoom(item))
    return jobs


def cache_path(dest: Path, z: int, x: int, y: int) -> Path:
    return dest / CACHE_DIR / str(z) / str(x) / f"{y}.jpg"


def cache_get(dest: Path, z: int, x: int, y: int) -> bytes | None:
    path = cache_path(dest, z, x, y)
    if not path.is_file():
        return None
    raw = path.read_bytes()
    if raw.startswith(JPEG_MAGIC) and len(raw) > 800:
        return raw
    return None


def cache_put(dest: Path, z: int, x: int, y: int, blob: bytes) -> None:
    path = cache_path(dest, z, x, y)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(blob)
    tmp.replace(path)


def _reuse_into_cache(dest: Path, jobs: list[tuple[int, int, int]], pack_id: str) -> int:
    names = shard_names(dest)
    if not names:
        return 0
    wanted = set(jobs)
    reused = 0
    for name in names:
        with open(dest / name, "rb") as fh:
            for zxy, blob in all_tiles(MmapSource(fh)):
                if zxy not in wanted:
                    continue
                if cache_path(dest, *zxy).is_file():
                    continue
                if blob and blob.startswith(JPEG_MAGIC) and len(blob) > 800:
                    cache_put(dest, *zxy, blob)
                    reused += 1
    print(f"  NAIP {pack_id} reuse {reused} packed jpeg", flush=True)
    return reused


def _fetch_missing(dest: Path, jobs: list[tuple[int, int, int]], pack_id: str) -> None:
    missing = [zxy for zxy in jobs if not cache_path(dest, *zxy).is_file()]
    print(f"  NAIP {pack_id} photo {len(jobs)} tiles, fetch {len(missing)}", flush=True)
    if not missing:
        return
    done = 0
    got = 0
    t0 = time.time()
    batch = max(WORKERS * 8, 256)
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for i in range(0, len(missing), batch):
            chunk = missing[i : i + batch]
            futs = {pool.submit(fetch_tile_jpeg, z, x, y): (z, x, y) for z, x, y in chunk}
            for fut in as_completed(futs):
                zxy = futs[fut]
                done += 1
                try:
                    blob = fut.result()
                except Exception:
                    blob = None
                if blob:
                    cache_put(dest, *zxy, blob)
                    got += 1
                if done % 100 == 0 or done == len(missing):
                    dt = max(time.time() - t0, 0.001)
                    rate = done / dt
                    remain = (len(missing) - done) / rate if rate else 0
                    print(
                        f"  NAIP {pack_id} {done}/{len(missing)} fetched {got} jpeg "
                        f"{rate:.1f}/s eta {remain / 60:.0f}m",
                        flush=True,
                    )


def _write_one_shard(
    path: Path,
    tiles: list[tuple[tuple[int, int, int], bytes]],
    bbox: dict,
    pack: dict,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as fh:
        writer = Writer(fh)
        for zxy, blob in tiles:
            writer.write_tile(zxy_to_tileid(*zxy), blob)
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
                "name": f"{pack['name']} walking photo",
                "format": "jpg",
                "attribution": NAIP_CREDIT,
            },
        )


def merge_phone_archives(dest: Path) -> Path | None:
    """GitHub keeps 90 MB shards. The phone draws one raster source."""
    names = shard_names(dest)
    if not names:
        return None
    out = dest / AERIAL_FILE
    if len(names) == 1 and names[0] == AERIAL_FILE:
        return out if out.is_file() else None
    tiles: dict[tuple[int, int, int], bytes] = {}
    west = south = 180.0
    east = north = -180.0
    for name in names:
        path = dest / name
        if not path.is_file():
            continue
        with open(path, "rb") as fh:
            header = Reader(MmapSource(fh)).header()
        west = min(west, header["min_lon_e7"] / 1e7)
        south = min(south, header["min_lat_e7"] / 1e7)
        east = max(east, header["max_lon_e7"] / 1e7)
        north = max(north, header["max_lat_e7"] / 1e7)
        tiles.update(read_archive(path))
    if not tiles:
        return None
    bbox = {"west": west, "south": south, "east": east, "north": north}
    pack = {"id": dest.name, "name": dest.name}
    staging = dest / WRITE_DIR
    staging.mkdir(parents=True, exist_ok=True)
    merged = staging / AERIAL_FILE
    ordered = sorted(tiles.items(), key=lambda item: zxy_to_tileid(*item[0]))
    _write_one_shard(merged, ordered, bbox, pack)
    merged.replace(out)
    for name in names:
        if name == AERIAL_FILE:
            continue
        path = dest / name
        if path.is_file():
            path.unlink()
    shutil.rmtree(staging, ignore_errors=True)
    return out


def write_shards(
    dest: Path,
    jobs: list[tuple[int, int, int]],
    pack: dict,
) -> list[str]:
    bbox = region_bbox(pack)
    staging = dest / WRITE_DIR
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True, exist_ok=True)
    names: list[str] = []
    current: list[tuple[tuple[int, int, int], bytes]] = []
    size = 0
    tiles = 0

    def flush() -> None:
        nonlocal current, size
        if not current:
            return
        name = shard_file_name(len(names))
        _write_one_shard(staging / name, current, bbox, pack)
        names.append(name)
        current = []
        size = 0

    for zxy in sorted(jobs, key=lambda item: zxy_to_tileid(*item)):
        blob = cache_get(dest, *zxy)
        if not blob:
            continue
        tiles += 1
        payload = len(blob)
        if current and size + payload > SHARD_PAYLOAD_BYTES:
            flush()
        current.append((zxy, blob))
        size += payload
    flush()
    if tiles < 20:
        shutil.rmtree(staging, ignore_errors=True)
        return []
    for old in dest.glob("aerial*.pmtiles"):
        old.unlink()
    for name in names:
        (staging / name).replace(dest / name)
    shutil.rmtree(staging, ignore_errors=True)
    return names


def build_aerial(dest: Path, pack: dict) -> dict[str, Any]:
    """Write `aerial*.pmtiles` shards for the extract plus walkable yards."""
    dest.mkdir(parents=True, exist_ok=True)
    jobs = aerial_jobs(pack)
    pack_id = str(pack.get("id") or dest.name)
    _reuse_into_cache(dest, jobs, pack_id)
    _fetch_missing(dest, jobs, pack_id)
    names = write_shards(dest, jobs, pack)
    if not names:
        present = sum(1 for zxy in jobs if cache_get(dest, *zxy))
        return {"present": False, "reason": f"NAIP returned {present} tiles", "tiles": 0}
    names.extend(write_feather_overlay(dest, pack_id))
    tiles = sum(1 for zxy in jobs if cache_get(dest, *zxy))
    bytes_out = sum((dest / name).stat().st_size for name in names)
    return {
        "present": True,
        "file": names[0],
        "files": names,
        "tiles": tiles,
        "bytes": bytes_out,
        "attribution": NAIP_CREDIT,
    }


def _tile_center(z: int, x: int, y: int) -> tuple[float, float]:
    n = 2.0**z
    lon = (x + 0.5) / n * 360.0 - 180.0
    lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + 0.5) / n))))
    return lon, lat


def _zxy_in_box(z: int, x: int, y: int, box: dict) -> bool:
    lon, lat = _tile_center(z, x, y)
    return box["south"] <= lat <= box["north"] and box["west"] <= lon <= box["east"]


def _jpeg_decode(blob: bytes):
    from io import BytesIO

    from PIL import Image

    return Image.open(BytesIO(blob)).convert("RGB")


def _jpeg_encode(im) -> bytes:
    from io import BytesIO

    buf = BytesIO()
    im.save(buf, format="JPEG", quality=90, optimize=True, subsampling=0)
    return buf.getvalue()


def feather_tiles(
    tiles: dict[tuple[int, int, int], bytes],
    px: int = FEATHER_PX,
) -> dict[tuple[int, int, int], bytes]:
    """Blend shared edges so independently stretched NAIP tiles read as one photo."""
    orig = {}
    for zxy, blob in tiles.items():
        if blob and blob.startswith(JPEG_MAGIC):
            orig[zxy] = _jpeg_decode(blob)
    out = dict(tiles)
    for (z, x, y), im in orig.items():
        width, height = im.size
        band = min(px, width // 4, height // 4)
        if band < 1:
            continue
        src = im.load()
        new = im.copy()
        dst = new.load()
        changed = False

        right = orig.get((z, x + 1, y))
        if right is not None:
            rp = right.load()
            for i in range(band):
                col = width - band + i
                t = (i + 1) / (2 * band)
                for row in range(height):
                    a = src[col, row]
                    b = rp[i, row]
                    dst[col, row] = tuple(int(a[c] * (1 - t) + b[c] * t) for c in range(3))
            changed = True

        left = orig.get((z, x - 1, y))
        if left is not None:
            lp = left.load()
            lw = left.size[0]
            for i in range(band):
                col = i
                t = (band - i) / (2 * band)
                for row in range(height):
                    a = src[col, row]
                    b = lp[lw - band + i, row]
                    dst[col, row] = tuple(int(a[c] * (1 - t) + b[c] * t) for c in range(3))
            changed = True

        below = orig.get((z, x, y + 1))
        if below is not None:
            bp = below.load()
            for i in range(band):
                row = height - band + i
                t = (i + 1) / (2 * band)
                for col in range(width):
                    a = src[col, row]
                    b = bp[col, i]
                    dst[col, row] = tuple(int(a[c] * (1 - t) + b[c] * t) for c in range(3))
            changed = True

        above = orig.get((z, x, y - 1))
        if above is not None:
            ap = above.load()
            ah = above.size[1]
            for i in range(band):
                row = i
                t = (band - i) / (2 * band)
                for col in range(width):
                    a = src[col, row]
                    b = ap[col, ah - band + i]
                    dst[col, row] = tuple(int(a[c] * (1 - t) + b[c] * t) for c in range(3))
            changed = True

        if changed:
            blob = _jpeg_encode(new)
            if blob.startswith(JPEG_MAGIC) and len(blob) > 800:
                out[(z, x, y)] = blob
    return out


def write_feather_overlay(dest: Path, pack_id: str) -> list[str]:
    """`aerial-seam.pmtiles` is last. Phone merge applies these tiles so the walk desk is one photo."""
    box = SEAM_BOXES.get(pack_id)
    if not box:
        return []
    tiles: dict[tuple[int, int, int], bytes] = {}
    for name in shard_names(dest):
        if name.startswith("aerial-seam"):
            continue
        tiles.update(read_archive(dest / name))
    core = {zxy for zxy in tiles if zxy[0] >= 14 and _zxy_in_box(*zxy, box)}
    wanted = set(core)
    for z, x, y in core:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nbr = (z, x + dx, y + dy)
            if nbr in tiles:
                wanted.add(nbr)
    if len(wanted) < 8:
        return []
    subset = {zxy: tiles[zxy] for zxy in wanted}
    feathered = feather_tiles(subset)
    bbox = {
        "west": box["west"],
        "south": box["south"],
        "east": box["east"],
        "north": box["north"],
    }
    pack = {"id": pack_id, "name": pack_id}
    ordered = sorted(feathered.items(), key=lambda item: zxy_to_tileid(*item[0]))
    written: list[str] = []
    current: list[tuple[tuple[int, int, int], bytes]] = []
    size = 0
    part = 0
    for old in dest.glob("aerial-seam*.pmtiles"):
        old.unlink()
    for item in ordered:
        payload = len(item[1])
        if current and size + payload > SHARD_PAYLOAD_BYTES:
            name = "aerial-seam.pmtiles" if part == 0 else f"aerial-seam-{part}.pmtiles"
            _write_one_shard(dest / name, current, bbox, pack)
            written.append(name)
            part += 1
            current = []
            size = 0
        current.append(item)
        size += payload
    if current:
        name = "aerial-seam.pmtiles" if part == 0 else f"aerial-seam-{part}.pmtiles"
        _write_one_shard(dest / name, current, bbox, pack)
        written.append(name)
    return written
