"""Packed KHAN EYE ground: OSM houses, trees, signals, lamps, and signs.

Airplane only. This is build-time Overpass, the same extract the street archive
already uses. The phone never asks the network. There is no photo mesh: a house
is the footprint OSM recorded, stood up to a height OSM recorded or a class
default. A tree is a mapped tree, not a guessed orchard. Empty desert stays
empty.
"""

from __future__ import annotations

import math
import re
from typing import Any

KHAN_KEEP = {
    "name",
    "highway",
    "natural",
    "building",
    "height",
    "building:levels",
    "roof:height",
    "traffic_sign",
    "traffic_signals",
    "crossing",
}

# Metres. Houses stay houses. Unknown footprints are a short block, not a tower.
BUILDING_HEIGHT_M = {
    "house": 5.0,
    "detached": 5.0,
    "semidetached_house": 5.5,
    "terrace": 6.0,
    "bungalow": 4.0,
    "static_caravan": 3.0,
    "cabin": 4.0,
    "hut": 3.0,
    "shed": 2.5,
    "garage": 3.0,
    "garages": 3.0,
    "carport": 2.5,
    "apartments": 14.0,
    "residential": 8.0,
    "dormitory": 12.0,
    "hotel": 16.0,
    "commercial": 10.0,
    "retail": 8.0,
    "office": 16.0,
    "industrial": 12.0,
    "warehouse": 10.0,
    "manufacture": 12.0,
    "school": 9.0,
    "university": 12.0,
    "hospital": 16.0,
    "church": 14.0,
    "cathedral": 22.0,
    "chapel": 8.0,
    "public": 10.0,
    "civic": 10.0,
    "government": 12.0,
    "train_station": 12.0,
    "transportation": 8.0,
    "parking": 4.0,
    "roof": 3.0,
    "yes": 7.0,
}

TREE_HEIGHT_M = 8.0
WOOD_HEIGHT_M = 9.0
# ~3.8 m canopy. Reads as a tree at street pitch, not a park slab.
TREE_RADIUS_DEG = 0.000034
# Skip a national-forest sheet. A city wood still stands up.
WOOD_MAX_M2 = 80_000
LEVEL_METRES = 3.2
RENDER_DP = 6
RENDER_EPS = 2e-5
OSM_CREDIT = "© OpenStreetMap contributors"

KHAN_SOURCE_ID = "khan"
KHAN_BUILDING_LAYER = "building"
KHAN_FURNITURE_LAYER = "furniture"
KHAN_BUILDINGS_ID = "khan-buildings"
KHAN_TREES_ID = "khan-trees"
KHAN_SIGNALS_ID = "khan-signals"
KHAN_LAMPS_ID = "khan-lamps"
KHAN_SIGNS_ID = "khan-signs"

VOID_INK = "#000000"
ACCENT_INK = "#E10600"
SILVER_INK = "#B8BDC2"
# Pitched desk over 3DEP shade: walls have to read as stone, not mud.
TREE_INK = "#3F8F4E"
WOOD_INK = "#2E6A3A"
HOUSE_INK = "#A39C94"
APARTMENT_INK = "#8A929A"
INDUSTRIAL_INK = "#6E767E"
RETAIL_INK = "#968A7C"
BLOCK_INK = "#8E949C"
LAMP_INK = "#E8A040"


def overpass_query(south: float, west: float, north: float, east: float) -> str:
    box = f"{south},{west},{north},{east}"
    return f"""
[out:json][timeout:90];
(
  way["building"]({box});
  node["natural"="tree"]({box});
  way["natural"="tree"]({box});
  node["natural"="tree_row"]({box});
  way["natural"="tree_row"]({box});
  node["highway"="traffic_signals"]({box});
  node["traffic_signals"="signal"]({box});
  node["crossing"="traffic_signals"]({box});
  node["highway"="street_lamp"]({box});
  node["traffic_sign"]({box});
  node["highway"="stop"]({box});
  node["highway"="give_way"]({box});
);
out geom;
"""


def slim_khan_tags(tags: dict) -> dict:
    return {k: v for k, v in tags.items() if k in KHAN_KEEP}


def parse_metres(raw: object) -> float | None:
    if raw is None:
        return None
    text = str(raw).strip().lower().replace(",", ".")
    if not text:
        return None
    match = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s*(m|meter|meters|metre|metres)?$", text)
    if match:
        return float(match.group(1))
    feet = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s*(ft|feet|'|′)$", text)
    if feet:
        return float(feet.group(1)) * 0.3048
    return None


def parse_levels(raw: object) -> float | None:
    if raw is None:
        return None
    text = str(raw).strip().replace(",", ".")
    first = re.match(r"^([0-9]+(?:\.[0-9]+)?)", text)
    if not first:
        return None
    return float(first.group(1))


def height_m(tags: dict) -> float:
    roof = parse_metres(tags.get("height"))
    if roof is not None and 1.5 <= roof <= 250:
        return roof
    extra = parse_metres(tags.get("roof:height"))
    levels = parse_levels(tags.get("building:levels"))
    if levels is not None and 0.5 <= levels <= 80:
        metres = levels * LEVEL_METRES
        if extra is not None:
            metres += extra
        return metres
    kind = (tags.get("building") or "yes").lower()
    return BUILDING_HEIGHT_M.get(kind, BUILDING_HEIGHT_M["yes"])


def furniture_kind(tags: dict) -> str | None:
    natural = tags.get("natural")
    if natural in {"tree", "tree_row"}:
        return "tree"
    highway = tags.get("highway")
    if (
        highway == "traffic_signals"
        or tags.get("traffic_signals") == "signal"
        or tags.get("crossing") == "traffic_signals"
    ):
        return "signal"
    if highway == "street_lamp":
        return "lamp"
    if tags.get("traffic_sign") or highway in {"stop", "give_way"}:
        return "sign"
    return None


def sign_text(tags: dict) -> str:
    highway = tags.get("highway")
    raw = (tags.get("traffic_sign") or "").strip()
    folded = raw.lower()
    if highway == "stop" or "stop" in folded:
        return "STOP"
    if highway == "give_way" or "yield" in folded or "give_way" in folded:
        return "YIELD"
    if raw and folded not in {"yes", "no"}:
        return re.sub(r"[_/]+", " ", raw).upper()[:12]
    name = (tags.get("name") or "").strip()
    return name.upper()[:12] if name else ""


def _round_pt(lon: float, lat: float) -> list[float]:
    return [round(lon, RENDER_DP), round(lat, RENDER_DP)]


def _way_coords(way: dict) -> list[list[float]]:
    geom = way.get("geometry") or []
    coords = []
    for pt in geom:
        if "lon" in pt and "lat" in pt:
            coords.append(_round_pt(float(pt["lon"]), float(pt["lat"])))
    return coords


def _simplify(coords: list[list[float]], eps: float) -> list[list[float]]:
    if len(coords) < 3 or eps <= 0:
        return coords
    keep = [False] * len(coords)
    keep[0] = keep[-1] = True
    stack = [(0, len(coords) - 1)]
    while stack:
        i, j = stack.pop()
        ax, ay = coords[i]
        bx, by = coords[j]
        dx, dy = bx - ax, by - ay
        den = dx * dx + dy * dy
        far = -1.0
        pick = -1
        for k in range(i + 1, j):
            px, py = coords[k]
            if den == 0:
                dist = math.hypot(px - ax, py - ay)
            else:
                t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / den))
                dist = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
            if dist > far:
                far, pick = dist, k
        if far > eps and pick > 0:
            keep[pick] = True
            stack.append((i, pick))
            stack.append((pick, j))
    return [coords[i] for i in range(len(coords)) if keep[i]]


def _closed_ring(coords: list[list[float]]) -> list[list[float]] | None:
    if len(coords) < 4:
        return None
    ring = [list(pt) for pt in coords]
    if ring[0] != ring[-1]:
        ring.append(list(ring[0]))
    simple = _simplify(ring, RENDER_EPS)
    if simple[0] != simple[-1]:
        simple.append(list(simple[0]))
    if len(simple) < 4:
        return None
    return simple


def tree_disk(lon: float, lat: float, radius: float = TREE_RADIUS_DEG) -> list[list[float]]:
    scale = 1.0 / max(0.2, math.cos(math.radians(lat)))
    ring = []
    for i in range(8):
        ang = 2.0 * math.pi * i / 8.0
        ring.append(
            _round_pt(
                lon + radius * scale * math.cos(ang),
                lat + radius * math.sin(ang),
            )
        )
    ring.append(list(ring[0]))
    return ring


def _sample_line(coords: list[list[float]], spacing_deg: float = 0.00008) -> list[list[float]]:
    if len(coords) < 2:
        return coords[:1]
    out = [coords[0]]
    acc = 0.0
    for (x0, y0), (x1, y1) in zip(coords, coords[1:]):
        span = math.hypot(x1 - x0, y1 - y0)
        if span <= 0:
            continue
        acc += span
        while acc >= spacing_deg:
            acc -= spacing_deg
            t = 1.0 - (acc / span)
            out.append([x0 + (x1 - x0) * t, y0 + (y1 - y0) * t])
    if out[-1] != coords[-1]:
        out.append(coords[-1])
    return out


def _feature(props: dict, geom: dict) -> dict:
    return {"type": "Feature", "properties": props, "geometry": geom}


def _building_props(tags: dict) -> dict:
    kind = (tags.get("building") or "yes").lower()
    if kind in {"no", "entrance"}:
        return {}
    props: dict[str, Any] = {"kind": kind, "height_m": height_m(tags)}
    if tags.get("name"):
        props["name"] = tags["name"]
    return props


def _tree_props() -> dict[str, Any]:
    return {"kind": "tree", "height_m": TREE_HEIGHT_M}


def _furniture_props(kind: str, tags: dict) -> dict[str, Any]:
    props: dict[str, Any] = {"kind": kind}
    if tags.get("name"):
        props["name"] = tags["name"]
    if kind == "sign":
        text = sign_text(tags)
        if text:
            props["sign"] = text
    return props


def elements_to_geojson(osm: dict) -> dict:
    """OSM `out geom` elements to the GeoJSON the KHAN tiler cuts."""
    features: list[dict] = []
    for el in osm.get("elements") or []:
        tags = slim_khan_tags(el.get("tags") or {})
        kind = el.get("type")
        if kind == "node" and "lat" in el and "lon" in el:
            lon, lat = float(el["lon"]), float(el["lat"])
            furn = furniture_kind(tags)
            if furn == "tree":
                features.append(
                    _feature(_tree_props(), {"type": "Polygon", "coordinates": [tree_disk(lon, lat)]})
                )
                continue
            if furn:
                features.append(
                    _feature(
                        _furniture_props(furn, tags),
                        {"type": "Point", "coordinates": _round_pt(lon, lat)},
                    )
                )
            continue
        if kind != "way":
            continue
        coords = _way_coords(el)
        if len(coords) < 2:
            continue
        if tags.get("building"):
            ring = _closed_ring(coords)
            if not ring:
                continue
            props = _building_props(tags)
            if not props:
                continue
            features.append(_feature(props, {"type": "Polygon", "coordinates": [ring]}))
            continue
        furn = furniture_kind(tags)
        if furn == "tree":
            closed = coords[0] == coords[-1] and len(coords) >= 4
            if closed:
                ring = _closed_ring(coords)
                if ring:
                    props = _tree_props()
                    features.append(_feature(props, {"type": "Polygon", "coordinates": [ring]}))
                    continue
            for lon, lat in _sample_line(coords):
                features.append(
                    _feature(_tree_props(), {"type": "Polygon", "coordinates": [tree_disk(lon, lat)]})
                )
    return {"type": "FeatureCollection", "features": features, "attribution": OSM_CREDIT}


def _polygon_area_m2(ring: list) -> float:
    if not ring or len(ring) < 4:
        return 0.0
    lat = sum(pt[1] for pt in ring[:-1]) / max(1, len(ring) - 1)
    scale = 111320.0 * math.cos(math.radians(lat))
    area = 0.0
    for (x0, y0), (x1, y1) in zip(ring, ring[1:]):
        area += (x0 * scale) * (y1 * 110540.0) - (x1 * scale) * (y0 * 110540.0)
    return abs(area) / 2.0


def canopy_from_osm_feature(feat: dict) -> dict | None:
    """A mapped wood sheet, stood up as a short canopy. Not a guessed forest."""
    props = feat.get("properties") or {}
    geom = feat.get("geometry") or {}
    if props.get("natural") not in {"wood"} and props.get("landuse") not in {"forest"}:
        return None
    kind = geom.get("type")
    coords = geom.get("coordinates")
    if kind == "Polygon" and coords:
        rings = coords
    elif kind == "MultiPolygon" and coords:
        rings = coords[0] if coords else None
    else:
        return None
    if not rings:
        return None
    area = _polygon_area_m2(rings[0])
    if area <= 0 or area > WOOD_MAX_M2:
        return None
    return _feature(
        {"kind": "wood", "height_m": WOOD_HEIGHT_M},
        {"type": "Polygon", "coordinates": rings},
    )


def style_source() -> dict:
    return {
        "type": "vector",
        "url": "pmtiles://khan.pmtiles",
        "attribution": OSM_CREDIT,
    }


def style_layers() -> list[dict]:
    hidden = {"visibility": "none"}
    building_color = [
        "match",
        ["get", "kind"],
        "tree",
        TREE_INK,
        "wood",
        WOOD_INK,
        "house",
        HOUSE_INK,
        "detached",
        HOUSE_INK,
        "apartments",
        APARTMENT_INK,
        "residential",
        APARTMENT_INK,
        "industrial",
        INDUSTRIAL_INK,
        "warehouse",
        INDUSTRIAL_INK,
        "retail",
        RETAIL_INK,
        "commercial",
        RETAIL_INK,
        BLOCK_INK,
    ]
    return [
        {
            "id": KHAN_BUILDINGS_ID,
            "type": "fill-extrusion",
            "source": KHAN_SOURCE_ID,
            "source-layer": KHAN_BUILDING_LAYER,
            "minzoom": 11,
            "filter": ["!", ["in", ["get", "kind"], ["literal", ["tree", "wood"]]]],
            "layout": dict(hidden),
            "paint": {
                "fill-extrusion-color": building_color,
                "fill-extrusion-height": ["to-number", ["get", "height_m"]],
                "fill-extrusion-base": 0,
                "fill-extrusion-opacity": 1.0,
                "fill-extrusion-vertical-gradient": True,
            },
        },
        {
            "id": KHAN_TREES_ID,
            "type": "fill-extrusion",
            "source": KHAN_SOURCE_ID,
            "source-layer": KHAN_BUILDING_LAYER,
            "minzoom": 11,
            "filter": ["in", ["get", "kind"], ["literal", ["tree", "wood"]]],
            "layout": dict(hidden),
            "paint": {
                "fill-extrusion-color": [
                    "match",
                    ["get", "kind"],
                    "wood",
                    WOOD_INK,
                    TREE_INK,
                ],
                "fill-extrusion-height": ["to-number", ["get", "height_m"]],
                "fill-extrusion-base": 0,
                "fill-extrusion-opacity": 0.9,
                "fill-extrusion-vertical-gradient": True,
            },
        },
        {
            "id": KHAN_SIGNALS_ID,
            "type": "circle",
            "source": KHAN_SOURCE_ID,
            "source-layer": KHAN_FURNITURE_LAYER,
            "minzoom": 11,
            "filter": ["==", ["get", "kind"], "signal"],
            "layout": dict(hidden),
            "paint": {
                "circle-color": ACCENT_INK,
                "circle-radius": ["interpolate", ["linear"], ["zoom"], 11, 2.8, 16, 5.6],
                "circle-stroke-color": VOID_INK,
                "circle-stroke-width": 1.0,
            },
        },
        {
            "id": KHAN_LAMPS_ID,
            "type": "circle",
            "source": KHAN_SOURCE_ID,
            "source-layer": KHAN_FURNITURE_LAYER,
            "minzoom": 11,
            "filter": ["==", ["get", "kind"], "lamp"],
            "layout": dict(hidden),
            "paint": {
                "circle-color": LAMP_INK,
                "circle-radius": ["interpolate", ["linear"], ["zoom"], 11, 2.2, 16, 4.4],
                "circle-stroke-color": VOID_INK,
                "circle-stroke-width": 0.8,
            },
        },
        {
            "id": KHAN_SIGNS_ID,
            "type": "symbol",
            "source": KHAN_SOURCE_ID,
            "source-layer": KHAN_FURNITURE_LAYER,
            "minzoom": 12,
            "filter": ["==", ["get", "kind"], "sign"],
            "layout": {
                "visibility": "none",
                "text-field": ["coalesce", ["get", "sign"], ["get", "name"], ""],
                "text-size": 12,
                "text-font": ["Open Sans Regular"],
                "text-anchor": "bottom",
                "text-offset": [0, -0.4],
                "text-optional": True,
            },
            "paint": {
                "text-color": [
                    "match",
                    ["get", "sign"],
                    "STOP",
                    ACCENT_INK,
                    "YIELD",
                    LAMP_INK,
                    SILVER_INK,
                ],
                "text-halo-color": VOID_INK,
                "text-halo-width": 2.0,
            },
        },
    ]
