"""Ask Overpass how heavy a candidate pack bbox is before fetching it.

Growing a pack is cheap in desert and expensive in city, and the difference is
an order of magnitude. `out count` costs one small query per box, so we can
size a bbox against the packs already on disk instead of fetching 40 MB to
find out we overshot the iOS budget.
"""
from __future__ import annotations

import json
import sys
import time
import urllib.parse

from .common import ROOT
from .fetch_packs import PACKS, _http_json, OVERPASS_ENDPOINTS, union_bbox

# Calibrated against the shipped packs: bytes on disk per Overpass way, and per
# way for the node coordinates those ways drag in. Refreshed by --calibrate.
BYTES_PER_WAY = 700


def count_bbox(south: float, west: float, north: float, east: float) -> dict:
    q = f"""
[out:json][timeout:180];
(
  way["highway"]({south},{west},{north},{east});
  way["waterway"]({south},{west},{north},{east});
  way["natural"="water"]({south},{west},{north},{east});
);
out count;
"""
    body = urllib.parse.urlencode({"data": q}).encode()
    last: Exception | None = None
    for url in OVERPASS_ENDPOINTS:
        try:
            data = _http_json(url, data=body, timeout=210)
            tags = (data.get("elements") or [{}])[0].get("tags") or {}
            return {k: int(v) for k, v in tags.items()}
        except Exception as exc:  # noqa: BLE001 - endpoint fallback
            last = exc
            print(f"  count fail {url}: {exc}", flush=True)
            time.sleep(2)
    raise RuntimeError(f"overpass count failed: {last}")


def km2(bb: dict) -> float:
    import math

    mid = math.radians((bb["south"] + bb["north"]) / 2)
    return (bb["north"] - bb["south"]) * 110.9 * (bb["east"] - bb["west"]) * 111.3 * math.cos(mid)


def calibrate() -> float:
    """Bytes on disk per Overpass way, measured on the packs we already ship."""
    ratios = []
    for pid, pack in PACKS.items():
        man = ROOT / "Resources" / "Packs" / pid / "manifest.json"
        if not man.is_file():
            continue
        bb = union_bbox(pack["slices"])
        ways = count_bbox(bb["south"], bb["west"], bb["north"], bb["east"]).get("ways", 0)
        size = json.loads(man.read_text())["bytes"]
        if ways:
            ratios.append(size / ways)
            print(f"  {pid:8s} {ways:7d} ways  {size / 1048576:6.1f} MB  {size / ways:6.0f} B/way")
        time.sleep(1.5)
    return sum(ratios) / len(ratios) if ratios else BYTES_PER_WAY


def estimate(name: str, bb: dict, per_way: float) -> dict:
    ways = count_bbox(bb["south"], bb["west"], bb["north"], bb["east"]).get("ways", 0)
    mb = ways * per_way / 1048576
    print(f"  {name:10s} {km2(bb):7.0f} km²  {ways:7d} ways  ~{mb:6.1f} MB")
    return {"name": name, "bbox": bb, "ways": ways, "mb": mb}


def main(argv: list[str]) -> None:
    per_way = BYTES_PER_WAY
    if "--calibrate" in argv:
        print("calibrating on shipped packs")
        per_way = calibrate()
        print(f"  bytes per way = {per_way:.0f}")
    boxes = json.loads(sys.stdin.read()) if not sys.stdin.isatty() else {}
    for name, bb in boxes.items():
        estimate(name, bb, per_way)
        time.sleep(1.5)


if __name__ == "__main__":
    main(sys.argv[1:])
