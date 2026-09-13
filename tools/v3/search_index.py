"""Compact named-search index from a pack's OSM extract.

`osm.geojson` stays off the phone. `search.json` is the book MAP SEARCH ranks:
unique name + kind + one point. Streets, peaks, water, and places — not the
first 800 points in the extract.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

OSM_CREDIT = "© OpenStreetMap contributors"

WATER_NATURAL = {"water", "spring", "hot_spring", "bay", "strait"}


def kind_of(props: dict[str, Any]) -> str:
    natural = str(props.get("natural") or "")
    if natural == "peak":
        return "peak"
    if natural == "cave_entrance":
        return "cave_entrance"
    if natural == "tree":
        return "tree"
    if natural in WATER_NATURAL:
        return "water"
    amenity = str(props.get("amenity") or "")
    if amenity:
        return amenity
    if props.get("highway"):
        return "street"
    if props.get("waterway") or props.get("water"):
        return "water"
    return "place"


def _mid(coords: Any) -> tuple[float, float] | None:
    if not isinstance(coords, list) or not coords:
        return None
    first = coords[0]
    if isinstance(first, (int, float)) and len(coords) >= 2 and isinstance(coords[1], (int, float)):
        return float(coords[0]), float(coords[1])
    return _mid(coords[len(coords) // 2])


def point_of(geom: dict[str, Any]) -> tuple[float, float, int] | None:
    """lon, lat, priority (0 = Point)."""
    kind = geom.get("type")
    coords = geom.get("coordinates")
    xy = _mid(coords)
    if xy is None:
        return None
    lon, lat = xy
    pri = 0 if kind == "Point" else 1
    return lon, lat, pri


def docs_from_osm(fc: dict[str, Any]) -> list[list[Any]]:
    best: dict[tuple[str, str], tuple[int, float, float]] = {}
    for feat in fc.get("features") or []:
        props = feat.get("properties") or {}
        name = str(props.get("name") or "").strip()
        if not name or name.lower() == "unnamed":
            continue
        geom = feat.get("geometry") or {}
        pt = point_of(geom)
        if pt is None:
            continue
        lon, lat, pri = pt
        packed = kind_of(props)
        key = (name, packed)
        old = best.get(key)
        if old is None or pri < old[0]:
            best[key] = (pri, round(lat, 6), round(lon, 6))
    rows = [[name, packed, lat, lon] for (name, packed), (_, lat, lon) in best.items()]
    rows.sort(key=lambda row: (row[0].casefold(), row[1]))
    return rows


def write_search(dest: Path, fc: dict[str, Any] | None = None) -> Path:
    if fc is None:
        fc = json.loads((dest / "osm.geojson").read_text())
    payload = {
        "attribution": OSM_CREDIT,
        "docs": docs_from_osm(fc),
    }
    path = dest / "search.json"
    path.write_text(json.dumps(payload, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    from . import addrfeat

    addrfeat.attach_addr(dest)
    return path
