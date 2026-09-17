"""Overlay GeoJSON → one vector PMTiles archive per pack.

Contours, wild, flood, public land, ground and water-detail used to ride as
whole-pack GeoJSON sources. Opening the style parsed every line before the
first frame. Same data, tiled, so MapLibre only pays for the viewport.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from shapely.geometry import shape

from . import tiles
from .tiles import Layer, encode_tile, repair, tile_range, zxy_to_tileid
from pmtiles.tile import Compression, TileType
from pmtiles.writer import Writer

OVERLAY_FILE = "overlay.pmtiles"
OVERLAY_SOURCE_ID = "overlay"
MIN_ZOOM = tiles.MIN_ZOOM
MAX_ZOOM = 12

LAYERS = (
    ("contours", "contours.geojson", 6),
    ("wild", "wild.geojson", 10),
    ("public-land", "layers/public_land.geojson", 8),
    ("flood", "layers/flood.geojson", 8),
    ("hazards", "layers/hazards.geojson", 10),
    ("ground", "layers/ground.geojson", 11),
    ("water-detail", "layers/water.geojson", 12),
)

KEEP = (
    "name",
    "contour",
    "unit",
    "highway",
    "natural",
    "landuse",
    "leisure",
    "boundary",
    "class",
    "via",
    "amenity",
    "waterway",
    "ele",
    "ref",
)


def _props(raw: dict) -> dict:
    out = {}
    for key in KEEP:
        val = raw.get(key)
        if val is None or val == "":
            continue
        if isinstance(val, (str, int, float, bool)):
            out[key] = val
        else:
            out[key] = str(val)
    return out


def _explode(geom) -> list:
    if geom is None or geom.is_empty:
        return []
    kind = geom.geom_type
    if kind in ("MultiLineString", "MultiPolygon", "MultiPoint", "GeometryCollection"):
        parts = []
        for part in geom.geoms:
            parts.extend(_explode(part))
        return parts
    return [geom]


def read_layers(pack: Path) -> dict[str, Layer]:
    layers: dict[str, Layer] = {}
    for name, rel, minzoom in LAYERS:
        layer = Layer(name)
        path = pack / rel
        if path.is_file():
            fc = json.loads(path.read_text())
            for feat in fc.get("features") or []:
                geom_raw = feat.get("geometry")
                if not geom_raw:
                    continue
                try:
                    geom = shape(geom_raw)
                except Exception:
                    continue
                geom = repair(geom)
                if geom is None:
                    continue
                keep = _props(feat.get("properties") or {})
                for part in _explode(geom):
                    if part is None or part.is_empty:
                        continue
                    layer.add(part, keep, minzoom)
        layer.index()
        layers[name] = layer
    return layers


def pack_bbox(pack: Path) -> dict[str, float]:
    catalog = json.loads((pack.parent / "catalog.json").read_text())
    for item in catalog.get("packs") or []:
        if item.get("id") == pack.name:
            box = item.get("bbox") or {}
            return {
                "south": float(box["south"]),
                "west": float(box["west"]),
                "north": float(box["north"]),
                "east": float(box["east"]),
            }
    raise SystemExit(f"{pack.name} missing from catalog.json")


def write_overlay(pack: Path) -> dict[str, Any]:
    layers = read_layers(pack)
    bbox = pack_bbox(pack)
    out = pack / OVERLAY_FILE
    tiles_n = 0
    with open(out, "wb") as fh:
        writer = Writer(fh)
        for z in range(MIN_ZOOM, MAX_ZOOM + 1):
            x0, y0, x1, y1 = tile_range(bbox, z)
            for x in range(x0, x1 + 1):
                for y in range(y0, y1 + 1):
                    blob = encode_tile(layers, z, x, y)
                    if not blob:
                        continue
                    writer.write_tile(zxy_to_tileid(z, x, y), blob)
                    tiles_n += 1
        writer.finalize(
            {
                "tile_type": TileType.MVT,
                "tile_compression": Compression.GZIP,
                "min_zoom": MIN_ZOOM,
                "max_zoom": MAX_ZOOM,
                "min_lon_e7": int(bbox["west"] * 1e7),
                "min_lat_e7": int(bbox["south"] * 1e7),
                "max_lon_e7": int(bbox["east"] * 1e7),
                "max_lat_e7": int(bbox["north"] * 1e7),
                "center_zoom": 11,
                "center_lon_e7": int((bbox["west"] + bbox["east"]) / 2 * 1e7),
                "center_lat_e7": int((bbox["south"] + bbox["north"]) / 2 * 1e7),
            },
            {
                "name": f"{pack.name} overlay",
                "format": "pbf",
                "attribution": "© OpenStreetMap contributors",
                "vector_layers": [
                    {"id": name, "minzoom": MIN_ZOOM, "maxzoom": MAX_ZOOM}
                    for name, _, _ in LAYERS
                ],
            },
        )
    return {"tiles": tiles_n, "bytes": out.stat().st_size}


def restyle(style: dict) -> dict:
    sources = style.get("sources") or {}
    for dead in ("contours", "public-land", "flood", "hazards", "wild"):
        sources.pop(dead, None)
    sources[OVERLAY_SOURCE_ID] = {
        "type": "vector",
        "url": f"pmtiles://{OVERLAY_FILE}",
        "attribution": "© OpenStreetMap contributors",
    }
    style["sources"] = sources
    layer_source = {
        "contours": "contours",
        "wild": "wild",
        "wild-roads": "wild",
        "hazards": "hazards",
        "public-land-fill": "public-land",
        "public-land-line": "public-land",
        "flood-fill": "flood",
    }
    for layer in style.get("layers") or []:
        sid = layer.get("id")
        if sid in layer_source:
            layer["source"] = OVERLAY_SOURCE_ID
            layer["source-layer"] = layer_source[sid]
    return style


def restyle_pack(pack: Path) -> None:
    path = pack / "style.json"
    style = json.loads(path.read_text())
    restyle(style)
    path.write_text(json.dumps(style, ensure_ascii=False, indent=2) + "\n")
