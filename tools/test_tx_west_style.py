#!/usr/bin/env python3
"""Lock TX WEST default MapLibre style to on-device walking-zoom readability.

Washed charcoal/gray + 10–13pt labels fail this contract. Tokens are
#000000 / #E10600 / #B8BDC2. OSM data must stay walkable (not a sticker).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from v3.fetch_packs import (  # noqa: E402
    OSM_CREDIT,
    PRIMARY_PACK_ID,
    maplibre_style,
    walkable_ids,
)

VOID = "#000000"
ACCENT = "#E10600"
SILVER = "#B8BDC2"
WASHED_VOID = "#0c0e10"
WASHED_ROAD = "#c5cdd6"
WASHED_LABEL = "#e8eef4"


def fail(msg: str) -> None:
    print("FAIL", msg)
    raise SystemExit(1)


def layer(style: dict, layer_id: str) -> dict:
    for item in style.get("layers") or []:
        if item.get("id") == layer_id:
            return item
    fail(f"missing layer {layer_id}")
    return {}


def interpolate_at(expr: object, zoom: float) -> float:
    if not isinstance(expr, list) or not expr or expr[0] != "interpolate":
        fail(f"expected interpolate expression, got {expr!r}")
    stops: list[tuple[float, float]] = []
    i = 3
    while i + 1 < len(expr):
        stops.append((float(expr[i]), float(expr[i + 1])))
        i += 2
    if not stops:
        fail("empty interpolate")
    if zoom <= stops[0][0]:
        return stops[0][1]
    if zoom >= stops[-1][0]:
        return stops[-1][1]
    for (z0, v0), (z1, v1) in zip(stops, stops[1:]):
        if z0 <= zoom <= z1:
            t = (zoom - z0) / (z1 - z0)
            return v0 + t * (v1 - v0)
    return stops[-1][1]


def dump_json(obj: object) -> str:
    return json.dumps(obj, ensure_ascii=False).lower()


def assert_no_remote_tiles(style: dict, label: str) -> None:
    blob = dump_json(style)
    for needle in (
        "googleapis",
        "google.com/maps",
        "apple.com/maps",
        "mapkit",
        "mapbox.com",
        "satellite",
        "raster-tiles",
        "http://",
        "https://",
    ):
        if needle in blob:
            fail(f"{label} must stay offline local — found {needle}")
    glyphs = style.get("glyphs") or ""
    if str(glyphs).startswith("http") or "://" in str(glyphs):
        fail(f"{label} glyphs must be local, got {glyphs}")


def assert_readable_style(style: dict, label: str) -> None:
    assert_no_remote_tiles(style, label)
    layers = style.get("layers") or []
    ids = [item.get("id") for item in layers]
    if "roads" not in ids:
        fail(f"{label} missing roads")
    if "road-labels" not in ids:
        fail(f"{label} missing road-labels")
    if "tracks" not in ids:
        fail(f"{label} missing tracks")
    if "place-labels" not in ids:
        fail(f"{label} missing place-labels")

    void = layer(style, "void")
    if (void.get("paint") or {}).get("background-color") != VOID:
        fail(f"{label} void must be {VOID}, not washed {WASHED_VOID}")

    roads = layer(style, "roads")
    road_color = (roads.get("paint") or {}).get("line-color")
    if road_color != SILVER:
        fail(f"{label} roads must be silver {SILVER}, got {road_color}")
    width = (roads.get("paint") or {}).get("line-width")
    if interpolate_at(width, 15) < 4.5:
        fail(f"{label} walking-zoom road width too thin at z15: {interpolate_at(width, 15)}")
    if interpolate_at(width, 17) < 8.0:
        fail(f"{label} walking-zoom road width too thin at z17: {interpolate_at(width, 17)}")

    labels = layer(style, "road-labels")
    if float(labels.get("minzoom") or 99) > 12:
        fail(f"{label} road-labels minzoom must be <= 12 for walking approach")
    paint = labels.get("paint") or {}
    if paint.get("text-color") != SILVER:
        fail(f"{label} road-labels must be {SILVER}, not washed {WASHED_LABEL}")
    if paint.get("text-halo-color") != VOID:
        fail(f"{label} road-label halo must be {VOID}")
    if float(paint.get("text-halo-width") or 0) < 1.8:
        fail(f"{label} road-label halo too thin: {paint.get('text-halo-width')}")
    size = (labels.get("layout") or {}).get("text-size")
    if interpolate_at(size, 14) < 14:
        fail(f"{label} road names too small at z14: {interpolate_at(size, 14)}")
    if interpolate_at(size, 16) < 16:
        fail(f"{label} road names too small at z16: {interpolate_at(size, 16)}")
    layout = labels.get("layout") or {}
    if float(layout.get("symbol-spacing") or 999) > 110:
        fail(f"{label} road-label spacing too sparse at walking zoom: {layout.get('symbol-spacing')}")
    if float(layout.get("text-max-angle") or 0) < 40:
        fail(f"{label} road-label max-angle too tight: {layout.get('text-max-angle')}")
    points = next((item for item in layers if item.get("id") == "osm-points"), None)
    vis = ((points or {}).get("layout") or {}).get("visibility")
    if vis != "none":
        fail(f"{label} osm-points must stay quiet (visibility none), got {vis}")

    blob = dump_json(style)
    if ACCENT.lower() not in blob:
        fail(f"{label} must use accent {ACCENT} for highway refs / arterial contrast")
    if WASHED_VOID in blob or WASHED_ROAD in blob or WASHED_LABEL in blob:
        fail(f"{label} still ships washed default palette")

    hill = next((item for item in layers if item.get("id") == "hillshade"), None)
    if hill:
        opacity = float((hill.get("paint") or {}).get("raster-opacity") or 1)
        if opacity > 0.22:
            fail(f"{label} hillshade {opacity} washes street contrast")

    meta = style.get("metadata") or {}
    if meta.get("attribution") != OSM_CREDIT:
        fail(f"{label} missing OSM credit in style metadata")
    if not meta.get("walkingZoom"):
        fail(f"{label} walkingZoom metadata missing")
    if meta.get("network") != "deny-all":
        fail(f"{label} network must stay deny-all")


def assert_walkable_osm(pack_id: str) -> None:
    pack = ROOT / "Resources" / "Packs" / pack_id
    osm_path = pack / "osm.geojson"
    if not osm_path.is_file():
        fail(f"{pack_id} missing osm.geojson")
    mb = osm_path.stat().st_size / (1024 * 1024)
    if mb < 15:
        fail(f"{pack_id} OSM {mb:.1f} MB looks like a sticker — do not replace walkable data")
    osm = json.loads(osm_path.read_text())
    feats = osm.get("features") or []
    hwy = [
        f
        for f in feats
        if (f.get("properties") or {}).get("highway")
        and (f.get("geometry") or {}).get("type") == "LineString"
    ]
    named = [
        f
        for f in hwy
        if (f.get("properties") or {}).get("name") or (f.get("properties") or {}).get("ref")
    ]
    if len(hwy) < 1000 or len(named) < 200:
        fail(f"{pack_id} walking streets too thin hwy={len(hwy)} named={len(named)}")
    print(f"OK   {pack_id} OSM {mb:.1f} MB hwy={len(hwy)} named={len(named)}")


def main() -> None:
    if PRIMARY_PACK_ID != "tx-west":
        fail(f"default open pack drifted to {PRIMARY_PACK_ID}")
    if walkable_ids() != {"tx-west", "nm", "tx-east"}:
        fail(f"walkable set {walkable_ids()} — keep nm + tx-east packs and tx-west default open")

    catalog = json.loads((ROOT / "Resources" / "Packs" / "catalog.json").read_text())
    if catalog.get("defaultPack") != "tx-west":
        fail("catalog defaultPack must stay tx-west")
    if (catalog.get("packs") or [{}])[0].get("id") != "tx-west":
        fail("catalog first pack must stay tx-west")
    nm = next((p for p in catalog.get("packs") or [] if p.get("id") == "nm"), None)
    if not nm:
        fail("nm pack missing from catalog")
    east = next((p for p in catalog.get("packs") or [] if p.get("id") == "tx-east"), None)
    if not east:
        fail("tx-east pack missing from catalog")
    if set(catalog.get("states") or []) != {"TX", "NM"}:
        fail(f"catalog states must be TX/NM only, got {catalog.get('states')}")

    style_path = ROOT / "Resources" / "Packs" / "tx-west" / "style.json"
    style = json.loads(style_path.read_text())
    assert_readable_style(style, "tx-west/style.json")

    existing = json.loads(style_path.read_text())
    hill = existing.get("sources", {}).get("hillshade")
    hillshade = None
    if hill:
        hillshade = {
            "present": True,
            "file": hill.get("url"),
            "coordinates": hill.get("coordinates"),
        }
    generated = maplibre_style("tx-west", hillshade)
    assert_readable_style(generated, "maplibre_style(tx-west)")

    refs = next((item for item in style.get("layers") or [] if item.get("id") == "road-refs"), None)
    if not refs:
        fail("tx-west needs a road-refs layer so highway numbers read in #E10600")
    if float(refs.get("minzoom") or 99) > 12:
        fail("road-refs must appear by walking approach zoom")
    if (refs.get("paint") or {}).get("text-color") != ACCENT:
        fail(f"road-refs must be {ACCENT}")
    if (refs.get("paint") or {}).get("text-halo-color") != SILVER:
        fail("road-refs need a silver halo so #E10600 reads on void")
    if interpolate_at((refs.get("layout") or {}).get("text-size"), 16) < 18:
        fail("road-refs too small at walking zoom")
    ref_key = (refs.get("layout") or {}).get("symbol-sort-key")
    if not isinstance(ref_key, (int, float)) or float(ref_key) > 1:
        fail("road-refs must sort ahead of local names (symbol-sort-key <= 1)")

    casing = next((item for item in style.get("layers") or [] if item.get("id") == "roads-casing"), None)
    if not casing:
        fail("tx-west needs roads-casing so silver streets pop off void")
    arterial = next((item for item in style.get("layers") or [] if item.get("id") == "roads-arterial-casing"), None)
    major = next((item for item in style.get("layers") or [] if item.get("id") == "roads-major"), None)
    if not arterial or not major:
        fail("tx-west needs arterial red casing and major silver fill")
    for z in (13, 15, 17):
        red = interpolate_at((arterial.get("paint") or {}).get("line-width"), z)
        fill = interpolate_at((major.get("paint") or {}).get("line-width"), z)
        if red - fill < 1.8:
            fail(f"arterial red casing invisible under major fill at z{z}: red={red} fill={fill}")

    assert_walkable_osm("tx-west")
    assert_walkable_osm("nm")
    assert_walkable_osm("tx-east")

    tokens = (ROOT / "Packages" / "Tokens" / "Sources" / "Tokens" / "Tokens.swift").read_text()
    if 'voidHex = "#000000"' not in tokens:
        fail("Tokens.MapInk.voidHex missing")
    if 'silverHex = "#B8BDC2"' not in tokens:
        fail("Tokens.MapInk.silverHex missing")
    if 'accentHex = "#E10600"' not in tokens:
        fail("Tokens.MapInk.accentHex missing")

    fallback = (
        ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift"
    ).read_text()
    if SILVER not in fallback or ACCENT not in fallback or VOID not in fallback:
        fail("PackStyle fallback layers must use Blackout map ink")
    if '"text-size": 11' in fallback or "text-size\": 11" in fallback:
        fail("PackStyle fallback road labels still 11pt")

    pbx = (ROOT / "Blackout.xcodeproj" / "project.pbxproj").read_text()
    if "CURRENT_PROJECT_VERSION = 1;" not in pbx:
        fail("CPV must stay 1")

    print("OK   TX WEST style uses Blackout ink; walking-zoom names read")


if __name__ == "__main__":
    main()
