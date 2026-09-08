#!/usr/bin/env python3
"""Repo-only: pull USGS National Map topo into Blackout/DefaultPack.

Runtime Map paint never uses URLSession. Re-run this script to refresh tiles.
"""
from __future__ import annotations

import json
import math
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "Blackout" / "DefaultPack"
TILES = PACK / "tiles"
BASE = "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile"
UA = "Blackout/0.1.0 (offline DefaultPack fetch; +https://github.com/crisiskhan/Blackout)"
CENTER_LAT = 39.74
CENTER_LON = -105.3
SPAN_LAT = 0.32
SPAN_LON = 0.50
ZOOMS = (10, 11, 12)
PROBE = ((10, 211, 387), (12, 848, 1553))
MIN_BYTES = 8_000


def lonlat_to_tile(lon: float, lat: float, z: int) -> tuple[int, int]:
    n = 2**z
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(min(max(lat, -85.05112878), 85.05112878))
    y = int((1.0 - math.log(math.tan(lat_rad) + 1.0 / math.cos(lat_rad)) / math.pi) / 2.0 * n)
    return x, y


def coverage_tiles() -> list[tuple[int, int, int]]:
    west = CENTER_LON - SPAN_LON / 2
    east = CENTER_LON + SPAN_LON / 2
    south = CENTER_LAT - SPAN_LAT / 2
    north = CENTER_LAT + SPAN_LAT / 2
    out: set[tuple[int, int, int]] = set()
    for z in ZOOMS:
        x0, y1 = lonlat_to_tile(west, south, z)
        x1, y0 = lonlat_to_tile(east, north, z)
        if x0 > x1:
            x0, x1 = x1, x0
        if y0 > y1:
            y0, y1 = y1, y0
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                out.add((z, x, y))
    out.update(PROBE)
    return sorted(out)


def write_png(path: Path, data: bytes) -> None:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        path.write_bytes(data)
        return
    proc = subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", "pipe:0", str(path)],
        input=data,
        check=False,
        capture_output=True,
    )
    if proc.returncode != 0 or not path.is_file() or path.stat().st_size < MIN_BYTES:
        err = (proc.stderr or b"").decode("utf-8", "replace")
        raise RuntimeError(f"jpeg→png failed for {path}: {err[:300]}")


def fetch_one(z: int, x: int, y: int) -> tuple[int, int, int, bytes]:
    url = f"{BASE}/{z}/{y}/{x}"
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "image/png"})
    last_err: Exception | None = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                data = resp.read()
            if not (data.startswith(b"\x89PNG\r\n\x1a\n") or data.startswith(b"\xff\xd8\xff")):
                raise RuntimeError(f"{z}/{x}/{y} is not an image ({len(data)} bytes)")
            if len(data) < MIN_BYTES:
                raise RuntimeError(f"{z}/{x}/{y} too small ({len(data)} bytes) — still a stub")
            return z, x, y, data
        except (urllib.error.URLError, TimeoutError, RuntimeError, OSError) as exc:
            last_err = exc
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"failed {z}/{x}/{y}: {last_err}")


def main() -> None:
    wanted = coverage_tiles()
    print(f"fetching {len(wanted)} USGS topo tiles into {TILES}", flush=True)
    TILES.mkdir(parents=True, exist_ok=True)
    written: list[dict[str, int]] = []
    errors: list[str] = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        futs = [pool.submit(fetch_one, z, x, y) for z, x, y in wanted]
        for fut in as_completed(futs):
            try:
                z, x, y, data = fut.result()
            except Exception as exc:  # noqa: BLE001 — surface every tile failure
                errors.append(str(exc))
                continue
            path = TILES / str(z) / str(x) / f"{y}.png"
            path.parent.mkdir(parents=True, exist_ok=True)
            write_png(path, data)
            written.append({"z": z, "x": x, "y": y})
            print(f"  {z}/{x}/{y} {path.stat().st_size} bytes", flush=True)
    if errors:
        print("FAIL", *errors, sep="\n", file=sys.stderr)
        raise SystemExit(1)
    written.sort(key=lambda t: (t["z"], t["x"], t["y"]))
    # Drop any leftover stub tiles that are not in this fetch.
    keep = {(t["z"], t["x"], t["y"]) for t in written}
    for png in TILES.rglob("*.png"):
        try:
            z, x, y = int(png.parent.parent.name), int(png.parent.name), int(png.stem)
        except ValueError:
            png.unlink()
            continue
        if (z, x, y) not in keep:
            png.unlink()
    manifest = {
        "name": "Front Range sample",
        "kind": "field-pack",
        "disclaimer": (
            "USGS National Map topo sample for the Denver / Front Range window. "
            "Not a world map. Extra regions come from Field Packs on disk, never from Map paint."
        ),
        "center": {"lat": CENTER_LAT, "lon": CENTER_LON},
        "span": {"lat": SPAN_LAT, "lon": SPAN_LON},
        "minZoom": 10,
        "maxZoom": 12,
        "tileTemplate": "tiles/{z}/{x}/{y}.png",
        "poi": "poi.json",
        "dem": "dem.json",
        "tileCount": len(written),
        "tiles": written,
    }
    (PACK / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    for z, x, y in PROBE:
        path = TILES / str(z) / str(x) / f"{y}.png"
        if not path.is_file() or path.stat().st_size < MIN_BYTES:
            raise SystemExit(f"probe missing or stub: {path}")
    print(f"DefaultPack USGS topo ok: {len(written)} PNGs")


if __name__ == "__main__":
    main()
