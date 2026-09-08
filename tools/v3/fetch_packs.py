"""Fetch real OSM + elevation extracts for TX/NM/FL/NY packs.

Primary walkable pack is tx-west: one El Paso / Franklin / TX+NM border bbox
with walking-zoom streets, names, and a graph built from those same ways.
"""
from __future__ import annotations

import json
import math
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

from .common import ROOT, haversine_m, write_json

OVERPASS = "https://overpass-api.de/api/interpreter"
ELEV = "https://api.open-meteo.com/v1/elevation"
USGS_3DEP = (
    "https://elevation.nationalmap.gov/arcgis/rest/services/"
    "3DEPElevation/ImageServer/exportImage"
)
GLYPH_SOURCES = [
    "https://orangemug.github.io/font-glyphs/glyphs/{stack}/{range}.pbf",
    "https://demotiles.maplibre.org/font/{stack}/{range}.pbf",
]
GLYPH_STACK = "Open Sans Regular"
GLYPH_RANGES = ("0-255", "256-511", "512-767", "768-1023", "8192-8447")

PRIMARY_PACK_ID = "tx-west"
KEEP_TAGS = {
    "name",
    "ref",
    "highway",
    "waterway",
    "natural",
    "place",
    "amenity",
    "emergency",
    "leisure",
    "landuse",
    "boundary",
    "tracktype",
    "surface",
    "oneway",
    "bridge",
    "tunnel",
    "ele",
    "foot",
    "bicycle",
    "access",
}
OSM_CREDIT = "© OpenStreetMap contributors"

PACKS = {
    "tx-west": {
        "id": "tx-west",
        "name": "TX WEST",
        "state": "TX",
        "slices": {
            "metro": {
                "name": "El Paso metro",
                "south": 31.74,
                "west": -106.52,
                "north": 31.82,
                "east": -106.40,
            },
            "wild": {
                "name": "Franklin Mountains wild",
                "south": 31.88,
                "west": -106.52,
                "north": 32.00,
                "east": -106.40,
            },
            "border": {
                "name": "El Paso TX+NM border union",
                "south": 31.70,
                "west": -106.62,
                "north": 31.90,
                "east": -106.35,
            },
        },
        "banners": ["heat-island", "cattle-guard", "border-hospitals"],
        "walkable": True,
    },
    "tx-east": {
        "id": "tx-east",
        "name": "TX EAST",
        "state": "TX",
        "slices": {
            "metro": {
                "name": "Austin metro",
                "south": 30.24,
                "west": -97.78,
                "north": 30.32,
                "east": -97.68,
            },
            "wild": {
                "name": "Lost Pines / Bastrop wild",
                "south": 30.08,
                "west": -97.32,
                "north": 30.18,
                "east": -97.20,
            },
        },
        "banners": ["heat-island", "cattle-guard", "hurricane"],
    },
    "nm": {
        "id": "nm",
        "name": "NM",
        "state": "NM",
        "slices": {
            "metro": {
                "name": "Albuquerque metro",
                "south": 35.06,
                "west": -106.68,
                "north": 35.14,
                "east": -106.55,
            },
            "wild": {
                "name": "Sandia foothills wild",
                "south": 35.15,
                "west": -106.50,
                "north": 35.25,
                "east": -106.38,
            },
        },
        "banners": ["monsoon", "ice-rock", "cattle-guard", "border-hospitals"],
    },
    "fl-north": {
        "id": "fl-north",
        "name": "FL NORTH",
        "state": "FL",
        "slices": {
            "metro": {
                "name": "Jacksonville metro",
                "south": 30.30,
                "west": -81.70,
                "north": 30.38,
                "east": -81.60,
            },
            "wild": {
                "name": "Timucuan / Big Talbot wild",
                "south": 30.45,
                "west": -81.48,
                "north": 30.52,
                "east": -81.38,
            },
        },
        "banners": ["hurricane", "rip", "gator-dusk", "heat-island"],
    },
    "fl-south": {
        "id": "fl-south",
        "name": "FL SOUTH",
        "state": "FL",
        "slices": {
            "metro": {
                "name": "Miami metro",
                "south": 25.74,
                "west": -80.28,
                "north": 25.82,
                "east": -80.18,
            },
            "wild": {
                "name": "Shark Valley / Everglades wild",
                "south": 25.72,
                "west": -80.80,
                "north": 25.80,
                "east": -80.70,
            },
        },
        "banners": ["hurricane", "rip", "gator-dusk", "keys-mm", "heat-island"],
    },
    "ny-metro": {
        "id": "ny-metro",
        "name": "NY METRO",
        "state": "NY",
        "slices": {
            "metro": {
                "name": "Lower Manhattan metro",
                "south": 40.70,
                "west": -74.02,
                "north": 40.76,
                "east": -73.97,
            },
            "wild": {
                "name": "Jamaica Bay wild",
                "south": 40.58,
                "west": -73.90,
                "north": 40.64,
                "east": -73.82,
            },
        },
        "banners": ["subway-north", "hurricane", "heat-island"],
    },
    "ny-upstate": {
        "id": "ny-upstate",
        "name": "NY UPSTATE",
        "state": "NY",
        "slices": {
            "metro": {
                "name": "Albany metro",
                "south": 42.64,
                "west": -73.80,
                "north": 42.70,
                "east": -73.74,
            },
            "wild": {
                "name": "Adirondack High Peaks wild",
                "south": 44.10,
                "west": -73.98,
                "north": 44.16,
                "east": -73.90,
            },
        },
        "banners": ["ice-rock", "subway-north"],
    },
}


def write_compact(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")


def _http_bytes(url: str, data: bytes | None = None, timeout: int = 120) -> bytes:
    req = urllib.request.Request(
        url,
        data=data,
        headers={"User-Agent": "BlackoutPackBuilder/3.0 (offline field vessel; build-time extract)"},
        method="POST" if data else "GET",
    )
    last = None
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read()
        except (urllib.error.URLError, TimeoutError) as exc:
            last = exc
            time.sleep(4 * (attempt + 1))
    raise RuntimeError(f"fetch failed {url}: {last}")


def _http_json(url: str, data: bytes | None = None, timeout: int = 120) -> dict:
    raw = _http_bytes(url, data=data, timeout=timeout)
    try:
        return json.loads(raw.decode())
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"bad json {url}: {exc}") from exc


def slim_tags(tags: dict) -> dict:
    return {k: v for k, v in tags.items() if k in KEEP_TAGS}


def overpass_bbox(south: float, west: float, north: float, east: float) -> dict:
    q = f"""
[out:json][timeout:180];
(
  way["highway"~"^(motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|unclassified|residential|living_street|service|track|path|footway|cycleway|bridleway|pedestrian|steps)$"]({south},{west},{north},{east});
  way["waterway"]({south},{west},{north},{east});
  way["natural"="water"]({south},{west},{north},{east});
  way["natural"="wood"]({south},{west},{north},{east});
  way["leisure"="park"]({south},{west},{north},{east});
  way["boundary"="protected_area"]({south},{west},{north},{east});
  way["landuse"~"forest|reservoir"]({south},{west},{north},{east});
  node["amenity"~"hospital|clinic|doctors|pharmacy|police|fire_station|drinking_water|shelter"]({south},{west},{north},{east});
  node["emergency"="assembly_point"]({south},{west},{north},{east});
  node["natural"="peak"]({south},{west},{north},{east});
  node["place"~"city|town|village|hamlet|suburb|neighbourhood|quarter"]({south},{west},{north},{east});
);
out body;
>;
out skel qt;
"""
    body = urllib.parse.urlencode({"data": q}).encode()
    return _http_json(OVERPASS, data=body, timeout=210)


def tile_bbox(bb: dict, max_span: float = 0.12) -> list[dict]:
    tiles = []
    lat = bb["south"]
    while lat < bb["north"] - 1e-12:
        n = min(bb["north"], lat + max_span)
        lon = bb["west"]
        while lon < bb["east"] - 1e-12:
            e = min(bb["east"], lon + max_span)
            tiles.append({"south": lat, "west": lon, "north": n, "east": e})
            lon = e
        lat = n
    return tiles or [bb]


def merge_osm(parts: list[dict]) -> dict:
    seen_n: set[int] = set()
    seen_w: set[int] = set()
    elements: list[dict] = []
    for osm in parts:
        for el in osm.get("elements") or []:
            eid = el.get("id")
            kind = el.get("type")
            if kind == "node":
                if eid in seen_n:
                    continue
                seen_n.add(eid)
            elif kind == "way":
                if eid in seen_w:
                    continue
                seen_w.add(eid)
            elements.append(el)
    return {"elements": elements}


def osm_to_geojson(osm: dict, kind: str) -> dict:
    nodes = {
        el["id"]: (el["lon"], el["lat"])
        for el in osm.get("elements", [])
        if el.get("type") == "node" and "lat" in el
    }
    features = []
    for el in osm.get("elements", []):
        tags = slim_tags(el.get("tags") or {})
        if el.get("type") == "node" and "lat" in el and tags:
            if tags.get("highway") == "crossing":
                continue
            features.append(
                {
                    "type": "Feature",
                    "properties": {"id": el["id"], "kind": "poi", **tags},
                    "geometry": {"type": "Point", "coordinates": [el["lon"], el["lat"]]},
                }
            )
        elif el.get("type") == "way" and el.get("nodes"):
            if not tags:
                continue
            coords = [nodes[n] for n in el["nodes"] if n in nodes]
            if len(coords) < 2:
                continue
            closed = coords[0] == coords[-1] and len(coords) >= 4
            geom = {"type": "Polygon", "coordinates": [coords]} if closed and tags.get("highway") is None else {
                "type": "LineString",
                "coordinates": coords,
            }
            features.append(
                {
                    "type": "Feature",
                    "properties": {"id": el["id"], "kind": kind, **tags},
                    "geometry": geom,
                }
            )
    return {"type": "FeatureCollection", "features": features, "attribution": OSM_CREDIT}


def clip_features(fc: dict, sl: dict) -> dict:
    feats = []
    for f in fc.get("features") or []:
        g = f.get("geometry") or {}
        coords = g.get("coordinates")
        pt = None
        if g.get("type") == "Point" and isinstance(coords, list) and len(coords) >= 2:
            pt = (coords[1], coords[0])
        elif g.get("type") == "LineString" and coords:
            lon, lat = coords[0]
            pt = (lat, lon)
        elif g.get("type") == "Polygon" and coords and coords[0]:
            lon, lat = coords[0][0]
            pt = (lat, lon)
        if pt is None:
            continue
        lat, lon = pt
        if sl["south"] <= lat <= sl["north"] and sl["west"] <= lon <= sl["east"]:
            feats.append(f)
    return {"type": "FeatureCollection", "features": feats, "attribution": OSM_CREDIT}


def build_graph(osm: dict) -> dict:
    nodes = {
        el["id"]: {"id": el["id"], "lon": el["lon"], "lat": el["lat"]}
        for el in osm.get("elements", [])
        if el.get("type") == "node" and "lat" in el
    }
    edges = []
    used = set()
    walk_ok_set = {
        "path",
        "footway",
        "track",
        "residential",
        "unclassified",
        "service",
        "tertiary",
        "tertiary_link",
        "secondary",
        "secondary_link",
        "primary",
        "primary_link",
        "living_street",
        "pedestrian",
        "steps",
        "bridleway",
        "cycleway",
    }
    drive_ok_set = {
        "motorway",
        "motorway_link",
        "trunk",
        "trunk_link",
        "primary",
        "primary_link",
        "secondary",
        "secondary_link",
        "tertiary",
        "tertiary_link",
        "unclassified",
        "residential",
        "service",
        "living_street",
    }
    for el in osm.get("elements", []):
        tags = el.get("tags") or {}
        highway = tags.get("highway")
        if el.get("type") != "way" or not highway or not el.get("nodes"):
            continue
        walk_ok = highway in walk_ok_set
        drive_ok = highway in drive_ok_set
        if not walk_ok and not drive_ok:
            continue
        oneway = tags.get("oneway") in {"yes", "1", "true"}
        ids = [n for n in el["nodes"] if n in nodes]
        for a, b in zip(ids, ids[1:]):
            na, nb = nodes[a], nodes[b]
            dist = haversine_m(na["lat"], na["lon"], nb["lat"], nb["lon"])
            if dist <= 0:
                continue
            rec = {
                "a": a,
                "b": b,
                "m": round(dist, 2),
                "walk": walk_ok,
                "drive": drive_ok,
            }
            edges.append(rec)
            used.add(a)
            used.add(b)
            if not oneway:
                back = dict(rec)
                back["a"], back["b"] = b, a
                edges.append(back)
    slim_nodes = {str(k): v for k, v in nodes.items() if k in used}
    return compact_graph(
        {
            "engine": "osm-graph",
            "valhallaCosting": {
                "walk": {"use_roads": 0.2, "use_hills": 0.4, "walking_speed": 5.1},
                "drive": {"use_highways": 1.0, "use_tolls": 0.0, "top_speed": 90},
            },
            "nodes": slim_nodes,
            "edges": edges,
        }
    )


def compact_graph(g: dict) -> dict:
    """Collapse degree-2 chains so the graph still matches streets without 80MB JSON."""
    nodes = {int(k): v for k, v in (g.get("nodes") or {}).items()}
    fwd: dict[int, list[tuple[int, float, bool, bool]]] = defaultdict(list)
    for e in g.get("edges") or []:
        fwd[int(e["a"])].append((int(e["b"]), float(e["m"]), bool(e["walk"]), bool(e["drive"])))

    rev: dict[int, set[int]] = defaultdict(set)
    for a, lst in fwd.items():
        for b, _, _, _ in lst:
            rev[b].add(a)

    def neigh(nid: int) -> set[int]:
        return {b for b, _, _, _ in fwd.get(nid, [])} | set(rev.get(nid, ()))

    def edge_between(a: int, b: int) -> tuple[float, bool, bool] | None:
        for dest, m, w, d in fwd.get(a, []):
            if dest == b:
                return (m, w, d)
        return None

    def unlink(a: int, b: int) -> None:
        fwd[a] = [t for t in fwd.get(a, []) if t[0] != b]
        if b in rev:
            rev[b].discard(a)
        if not fwd[a]:
            fwd.pop(a, None)

    def link(a: int, b: int, m: float, w: bool, d: bool) -> None:
        unlink(a, b)
        fwd[a].append((b, round(m, 2), w, d))
        rev[b].add(a)

    # iterate a snapshot of deg-2 nodes
    candidates = [nid for nid in list(nodes) if len(neigh(nid)) == 2]
    for nid in candidates:
        nbs = list(neigh(nid))
        if len(nbs) != 2:
            continue
        u, v = nbs
        uv = edge_between(u, nid)
        nv = edge_between(nid, v)
        vu = edge_between(v, nid)
        nu = edge_between(nid, u)
        if uv and nv:
            link(u, v, uv[0] + nv[0], uv[1] and nv[1], uv[2] and nv[2])
        if vu and nu:
            link(v, u, vu[0] + nu[0], vu[1] and nu[1], vu[2] and nu[2])
        unlink(u, nid)
        unlink(nid, u)
        unlink(v, nid)
        unlink(nid, v)
        nodes.pop(nid, None)
        fwd.pop(nid, None)
        rev.pop(nid, None)

    edges = []
    used = set()
    for a, lst in fwd.items():
        for b, m, w, d in lst:
            if a not in nodes or b not in nodes:
                continue
            edges.append({"a": a, "b": b, "m": round(m, 2), "walk": w, "drive": d})
            used.add(a)
            used.add(b)
    slim = {str(k): nodes[k] for k in used if k in nodes}
    return {
        "engine": g.get("engine") or "osm-graph",
        "valhallaCosting": g.get("valhallaCosting"),
        "nodes": slim,
        "edges": edges,
    }


def elevation_grid(south: float, west: float, north: float, east: float, step: float = 0.01) -> dict:
    lats = []
    lons = []
    lat = south
    while lat <= north + 1e-9:
        lats.append(round(lat, 5))
        lat += step
    lon = west
    while lon <= east + 1e-9:
        lons.append(round(lon, 5))
        lon += step
    elev = []
    chunk = 80
    pts = [(la, lo) for la in lats for lo in lons]
    for i in range(0, len(pts), chunk):
        part = pts[i : i + chunk]
        qs = urllib.parse.urlencode(
            {
                "latitude": ",".join(str(p[0]) for p in part),
                "longitude": ",".join(str(p[1]) for p in part),
            }
        )
        data = _http_json(f"{ELEV}?{qs}", timeout=60)
        vals = data.get("elevation") or []
        elev.extend(float(v) if v is not None else 0.0 for v in vals)
        time.sleep(0.2)
    grid = []
    idx = 0
    for _la in lats:
        row = []
        for _lo in lons:
            row.append(round(elev[idx], 1) if idx < len(elev) else 0.0)
            idx += 1
        grid.append(row)
    return {
        "west": west,
        "south": south,
        "east": east,
        "north": north,
        "cellDegrees": step,
        "unit": "meters",
        "lats": lats,
        "lons": lons,
        "grid": grid,
        "attribution": "Open-Meteo elevation (SRTM-class DEM), build-time only",
    }


def contours_from_dem(dem: dict, interval: float = 20.0) -> dict:
    """Marching-squares-lite isolines from the DEM grid (real elevations)."""
    grid = dem["grid"]
    lats, lons = dem["lats"], dem["lons"]
    if not grid or not grid[0]:
        return {"type": "FeatureCollection", "features": []}
    lo = min(min(row) for row in grid)
    hi = max(max(row) for row in grid)
    levels = []
    z = math.floor(lo / interval) * interval
    while z <= hi:
        levels.append(z)
        z += interval
    features = []
    for level in levels[:40]:
        segs = []
        for y in range(len(grid) - 1):
            for x in range(len(grid[0]) - 1):
                v = [grid[y][x], grid[y][x + 1], grid[y + 1][x + 1], grid[y + 1][x]]
                pts = [
                    (lons[x], lats[y]),
                    (lons[x + 1], lats[y]),
                    (lons[x + 1], lats[y + 1]),
                    (lons[x], lats[y + 1]),
                ]
                crossings = []
                for i in range(4):
                    a, b = v[i], v[(i + 1) % 4]
                    if (a < level) != (b < level) and a != b:
                        t = (level - a) / (b - a)
                        pa, pb = pts[i], pts[(i + 1) % 4]
                        crossings.append((pa[0] + t * (pb[0] - pa[0]), pa[1] + t * (pb[1] - pa[1])))
                if len(crossings) >= 2:
                    segs.append(crossings[:2])
        if segs:
            features.append(
                {
                    "type": "Feature",
                    "properties": {"contour": level, "unit": "m"},
                    "geometry": {"type": "MultiLineString", "coordinates": segs},
                }
            )
    return {"type": "FeatureCollection", "features": features, "attribution": "Derived from build-time DEM"}


def fetch_3dep_hillshade(bb: dict, dest: Path) -> dict:
    """USGS 3DEP hillshade PNG for the pack bbox. Omit rather than fake DEM."""
    width_deg = abs(bb["east"] - bb["west"])
    height_deg = abs(bb["north"] - bb["south"])
    px_w = 2048
    px_h = max(256, int(px_w * height_deg / max(width_deg, 1e-6)))
    qs = urllib.parse.urlencode(
        {
            "bbox": f"{bb['west']},{bb['south']},{bb['east']},{bb['north']}",
            "bboxSR": "4326",
            "size": f"{px_w},{px_h}",
            "imageSR": "4326",
            "format": "png",
            "pixelType": "U8",
            "interpolation": "RSP_BilinearInterpolation",
            "renderingRule": '{"rasterFunction":"Hillshade Gray"}',
            "f": "image",
        }
    )
    url = f"{USGS_3DEP}?{qs}"
    try:
        raw = _http_bytes(url, timeout=120)
    except Exception as exc:
        return {"present": False, "reason": f"3DEP export failed: {exc}"}
    if len(raw) < 100 or raw[:8] != b"\x89PNG\r\n\x1a\n":
        return {"present": False, "reason": f"3DEP did not return a PNG ({len(raw)} bytes)"}
    mb = len(raw) / (1024 * 1024)
    if mb > 25:
        return {"present": False, "reason": f"3DEP hillshade {mb:.1f} MB exceeds 25 MB budget"}
    dest.write_bytes(raw)
    return {
        "present": True,
        "file": dest.name,
        "bytes": len(raw),
        "width": px_w,
        "height": px_h,
        "attribution": "USGS 3DEP hillshade, build-time only",
    }


def fetch_glyphs(dest: Path) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    stack_dir = dest / GLYPH_STACK
    stack_dir.mkdir(parents=True, exist_ok=True)
    wrote = 0
    for rng in GLYPH_RANGES:
        out = stack_dir / f"{rng}.pbf"
        last = None
        for tmpl in GLYPH_SOURCES:
            url = tmpl.format(stack=urllib.parse.quote(GLYPH_STACK), range=rng)
            try:
                raw = _http_bytes(url, timeout=60)
            except Exception as exc:
                last = exc
                continue
            if len(raw) < 40:
                last = f"short glyph {len(raw)}"
                continue
            out.write_bytes(raw)
            wrote += 1
            break
        else:
            print(f"  glyph miss {rng}: {last}", flush=True)
    return wrote


def maplibre_style(pack_id: str, hillshade: dict | None = None) -> dict:
    sources: dict = {
        "osm": {
            "type": "geojson",
            "data": "osm.geojson",
            "attribution": OSM_CREDIT,
        },
        "contours": {"type": "geojson", "data": "contours.geojson"},
        "public-land": {"type": "geojson", "data": "layers/public_land.geojson"},
        "flood": {"type": "geojson", "data": "layers/flood.geojson"},
        "hazards": {"type": "geojson", "data": "layers/hazards.geojson"},
        "wild": {"type": "geojson", "data": "wild.geojson"},
    }
    layers: list[dict] = [
        {"id": "void", "type": "background", "paint": {"background-color": "#0c0e10"}},
    ]
    if hillshade and hillshade.get("present"):
        sources["hillshade"] = {
            "type": "image",
            "url": hillshade["file"],
            "coordinates": hillshade["coordinates"],
        }
        layers.append(
            {
                "id": "hillshade",
                "type": "raster",
                "source": "hillshade",
                "paint": {"raster-opacity": 0.38},
            }
        )
    layers.extend(
        [
            {
                "id": "public-land-fill",
                "type": "fill",
                "source": "public-land",
                "paint": {"fill-color": "#1a2a1a", "fill-opacity": 0.28},
            },
            {
                "id": "flood-fill",
                "type": "fill",
                "source": "flood",
                "paint": {"fill-color": "#143044", "fill-opacity": 0.28},
            },
            {
                "id": "water-fill",
                "type": "fill",
                "source": "osm",
                "filter": ["==", ["get", "natural"], "water"],
                "paint": {"fill-color": "#1a3a4a", "fill-opacity": 0.7},
            },
            {
                "id": "water",
                "type": "line",
                "source": "osm",
                "filter": ["has", "waterway"],
                "paint": {
                    "line-color": "#3a6a88",
                    "line-width": ["interpolate", ["linear"], ["zoom"], 10, 0.8, 15, 2.6],
                },
            },
            {
                "id": "contours",
                "type": "line",
                "source": "contours",
                "paint": {"line-color": "#6a7060", "line-width": 0.55, "line-opacity": 0.55},
            },
            {
                "id": "tracks",
                "type": "line",
                "source": "osm",
                "minzoom": 12,
                "filter": [
                    "in",
                    ["get", "highway"],
                    ["literal", ["track", "path", "footway", "bridleway", "cycleway", "steps"]],
                ],
                "paint": {
                    "line-color": "#c4b48a",
                    "line-width": ["interpolate", ["linear"], ["zoom"], 12, 0.7, 16, 2.0],
                    "line-dasharray": [2, 1.1],
                },
            },
            {
                "id": "roads",
                "type": "line",
                "source": "osm",
                "filter": ["has", "highway"],
                "paint": {
                    "line-color": "#c5cdd6",
                    "line-width": ["interpolate", ["linear"], ["zoom"], 10, 0.7, 13, 1.5, 15, 3.4, 17, 6.2],
                },
            },
            {
                "id": "wild-roads",
                "type": "line",
                "source": "wild",
                "filter": ["has", "highway"],
                "paint": {"line-color": "#e8eef4", "line-width": 2.4},
            },
            {
                "id": "hazards",
                "type": "line",
                "source": "hazards",
                "paint": {"line-color": "#c43b3b", "line-width": 1.2},
            },
            {
                "id": "osm-points",
                "type": "circle",
                "source": "osm",
                "filter": ["==", ["geometry-type"], "Point"],
                "paint": {
                    "circle-color": "#c5cdd6",
                    "circle-radius": 2.2,
                    "circle-stroke-color": "#0c0e10",
                    "circle-stroke-width": 0.6,
                },
            },
            {
                "id": "road-labels",
                "type": "symbol",
                "source": "osm",
                "minzoom": 13,
                "filter": ["all", ["has", "highway"], ["any", ["has", "name"], ["has", "ref"]]],
                "layout": {
                    "text-field": ["coalesce", ["get", "name"], ["get", "ref"]],
                    "symbol-placement": "line",
                    "text-size": ["interpolate", ["linear"], ["zoom"], 13, 10, 16, 13],
                    "text-font": [GLYPH_STACK],
                    "text-max-angle": 40,
                    "text-padding": 2,
                    "text-optional": True,
                },
                "paint": {
                    "text-color": "#e8eef4",
                    "text-halo-color": "#0c0e10",
                    "text-halo-width": 1.2,
                },
            },
            {
                "id": "place-labels",
                "type": "symbol",
                "source": "osm",
                "minzoom": 10,
                "filter": ["has", "place"],
                "layout": {
                    "text-field": ["get", "name"],
                    "text-size": ["interpolate", ["linear"], ["zoom"], 10, 12, 14, 16],
                    "text-font": [GLYPH_STACK],
                    "text-anchor": "top",
                    "text-optional": True,
                },
                "paint": {
                    "text-color": "#f0f4f8",
                    "text-halo-color": "#0c0e10",
                    "text-halo-width": 1.4,
                },
            },
        ]
    )
    return {
        "version": 8,
        "name": f"Blackout {pack_id}",
        "glyphs": "glyphs/{fontstack}/{range}.pbf",
        "sources": sources,
        "layers": layers,
        "metadata": {
            "engine": "maplibre-metal-offline",
            "network": "deny-all",
            "attribution": OSM_CREDIT,
            "walkingZoom": True,
        },
    }


def real_layer_features(fc: dict, keys: set[str]) -> dict:
    feats = []
    for f in fc.get("features") or []:
        props = f.get("properties") or {}
        if any(props.get(k) in keys or k in props and props.get(k) for k in keys):
            if (f.get("geometry") or {}).get("type") in {"Polygon", "MultiPolygon", "LineString"}:
                if props.get("leisure") == "park" or props.get("boundary") == "protected_area":
                    feats.append(f)
                elif props.get("natural") in {"wood", "water"}:
                    feats.append(f)
                elif props.get("landuse") in {"forest", "reservoir"}:
                    feats.append(f)
    return {"type": "FeatureCollection", "features": feats[:800], "attribution": OSM_CREDIT}


def union_bbox(slices: dict) -> dict:
    return {
        "south": min(s["south"] for s in slices.values()),
        "west": min(s["west"] for s in slices.values()),
        "north": max(s["north"] for s in slices.values()),
        "east": max(s["east"] for s in slices.values()),
    }


def pack_stats(fc: dict, graph: dict) -> dict:
    feats = fc.get("features") or []
    hwy = [f for f in feats if (f.get("properties") or {}).get("highway") and (f.get("geometry") or {}).get("type") == "LineString"]
    named = [f for f in hwy if (f.get("properties") or {}).get("name") or (f.get("properties") or {}).get("ref")]
    water = [f for f in feats if (f.get("properties") or {}).get("waterway") or (f.get("properties") or {}).get("natural") == "water"]
    places = [f for f in feats if (f.get("properties") or {}).get("place")]
    names = []
    seen = set()
    for f in named:
        n = (f.get("properties") or {}).get("name") or (f.get("properties") or {}).get("ref")
        if n and n not in seen:
            seen.add(n)
            names.append(n)
        if len(names) >= 12:
            break
    return {
        "features": len(feats),
        "highwayLines": len(hwy),
        "namedStreets": len(named),
        "sampleStreetNames": names,
        "water": len(water),
        "places": len(places),
        "graphEdges": len(graph.get("edges") or []),
        "graphNodes": len(graph.get("nodes") or {}),
        "streetsVisibleAtWalkingZoom": len(named) >= 50 and len(hwy) >= 200,
    }


def write_catalog(root: Path) -> None:
    packs = []
    order = [PRIMARY_PACK_ID] + [pid for pid in PACKS if pid != PRIMARY_PACK_ID]
    for pid in order:
        man = root / pid / "manifest.json"
        if man.is_file():
            packs.append(json.loads(man.read_text()))
    write_json(
        root / "catalog.json",
        {
            "schema": "blackout-packs-v3",
            "states": ["TX", "NM", "FL", "NY"],
            "defaultPack": PRIMARY_PACK_ID,
            "packs": packs,
        },
    )


def fetch_pack(pack: dict, dest: Path) -> dict:
    dest.mkdir(parents=True, exist_ok=True)
    bb = union_bbox(pack["slices"])
    walkable = bool(pack.get("walkable"))
    parts = []
    if walkable:
        tiles = tile_bbox(bb, max_span=0.12)
        print(f"  OSM {pack['id']} walkable union {bb} tiles={len(tiles)}", flush=True)
        for i, tile in enumerate(tiles, 1):
            print(f"  tile {i}/{len(tiles)} {tile}", flush=True)
            parts.append(overpass_bbox(tile["south"], tile["west"], tile["north"], tile["east"]))
            time.sleep(1.2)
        merged = merge_osm(parts)
    else:
        all_elements = []
        for key, sl in pack["slices"].items():
            print(f"  OSM {pack['id']}/{key} {sl['name']}", flush=True)
            osm = overpass_bbox(sl["south"], sl["west"], sl["north"], sl["east"])
            time.sleep(2)
            all_elements.extend(osm.get("elements", []))
        merged = merge_osm([{"elements": all_elements}])

    fc = osm_to_geojson(merged, "pack")
    graph = build_graph(merged)
    write_compact(dest / "osm.geojson", fc)
    write_compact(dest / "graph.json", graph)

    slice_summaries = {}
    for key, sl in pack["slices"].items():
        clipped = clip_features(fc, sl)
        # Keep wild lines for the wild-roads overlay; metro/border are catalog
        # slices only — do not duplicate the full OSM extract on disk.
        if key == "wild":
            write_compact(dest / f"{key}.geojson", clipped)
        else:
            write_compact(
                dest / f"{key}.geojson",
                {"type": "FeatureCollection", "features": clipped["features"][:80], "attribution": OSM_CREDIT},
            )
        slice_summaries[key] = {
            "name": sl["name"],
            "bbox": sl,
            "featureCount": len(clipped["features"]),
        }

    print(f"  DEM {pack['id']}", flush=True)
    dem = elevation_grid(bb["south"], bb["west"], bb["north"], bb["east"], step=0.015)
    write_json(dest / "dem.json", dem)
    write_compact(dest / "contours.geojson", contours_from_dem(dem))

    (dest / "layers").mkdir(exist_ok=True)
    write_compact(
        dest / "layers" / "public_land.geojson",
        real_layer_features(fc, {"leisure", "boundary", "landuse", "natural"}),
    )
    water_only = {
        "type": "FeatureCollection",
        "features": [
            f
            for f in fc["features"]
            if (f.get("properties") or {}).get("natural") == "water"
            or (f.get("properties") or {}).get("landuse") == "reservoir"
        ][:400],
        "attribution": OSM_CREDIT,
    }
    write_compact(dest / "layers" / "flood.geojson", water_only)
    write_compact(
        dest / "layers" / "hazards.geojson",
        {"type": "FeatureCollection", "features": [], "attribution": OSM_CREDIT},
    )

    hillshade_meta: dict = {"present": False, "reason": "not requested"}
    if walkable:
        print(f"  3DEP hillshade {pack['id']}", flush=True)
        hs = fetch_3dep_hillshade(bb, dest / "hillshade.png")
        if hs.get("present"):
            hs["coordinates"] = [
                [bb["west"], bb["north"]],
                [bb["east"], bb["north"]],
                [bb["east"], bb["south"]],
                [bb["west"], bb["south"]],
            ]
            print(f"  3DEP hillshade {hs['bytes']} bytes", flush=True)
        else:
            print(f"  3DEP omitted: {hs.get('reason')}", flush=True)
            dead = dest / "hillshade.png"
            if dead.exists():
                dead.unlink()
        hillshade_meta = hs
        n_glyphs = fetch_glyphs(dest / "glyphs")
        print(f"  glyphs {n_glyphs}", flush=True)

    write_json(dest / "style.json", maplibre_style(pack["id"], hillshade_meta if hillshade_meta.get("present") else None))
    pois = [f for f in fc["features"] if f["geometry"]["type"] == "Point"]
    write_compact(dest / "pois.geojson", {"type": "FeatureCollection", "features": pois[:800], "attribution": OSM_CREDIT})

    stats = pack_stats(fc, graph)
    files = [p for p in dest.rglob("*") if p.is_file()]
    size = sum(p.stat().st_size for p in files)
    terrain_note = (
        "USGS 3DEP hillshade bundled; contours from build-time Open-Meteo DEM."
        if hillshade_meta.get("present")
        else f"3DEP omitted ({hillshade_meta.get('reason')}); contours from build-time Open-Meteo DEM (real elevations, not fake)."
    )
    manifest = {
        "id": pack["id"],
        "name": pack["name"],
        "state": pack["state"],
        "kind": "osm-contour-extract",
        "engine": "maplibre",
        "defaultOpen": pack["id"] == PRIMARY_PACK_ID,
        "walkable": walkable,
        "bbox": bb,
        "slices": slice_summaries,
        "banners": pack["banners"],
        "bytes": size,
        "files": sorted(str(p.relative_to(dest)) for p in files),
        "center": {"lat": (bb["south"] + bb["north"]) / 2, "lon": (bb["west"] + bb["east"]) / 2},
        "attribution": f"{OSM_CREDIT}. {terrain_note} No runtime uplink.",
        "terrain": hillshade_meta,
        "stats": stats,
    }
    write_json(dest / "manifest.json", manifest)
    print(
        f"  packed {pack['id']} {size} bytes streets={stats['namedStreets']} "
        f"hwy={stats['highwayLines']} edges={stats['graphEdges']} "
        f"walking={stats['streetsVisibleAtWalkingZoom']}",
        flush=True,
    )
    print(f"  sample streets: {stats['sampleStreetNames']}", flush=True)
    return manifest


def finalize_existing(dest: Path) -> dict:
    """Finish a pack after OSM/DEM/3DEP files are already on disk (no re-fetch)."""
    fc = json.loads((dest / "osm.geojson").read_text())
    raw_graph = json.loads((dest / "graph.json").read_text())
    print(f"  compact graph edges={len(raw_graph.get('edges') or [])}", flush=True)
    graph = compact_graph(raw_graph)
    write_compact(dest / "graph.json", graph)
    print(f"  compacted edges={len(graph['edges'])} nodes={len(graph['nodes'])}", flush=True)

    pack = PACKS[dest.name]
    bb = union_bbox(pack["slices"])
    slice_summaries = {}
    for key, sl in pack["slices"].items():
        clipped = clip_features(fc, sl)
        if key == "wild":
            write_compact(dest / f"{key}.geojson", clipped)
        else:
            write_compact(
                dest / f"{key}.geojson",
                {"type": "FeatureCollection", "features": clipped["features"][:80], "attribution": OSM_CREDIT},
            )
        slice_summaries[key] = {"name": sl["name"], "bbox": sl, "featureCount": len(clipped["features"])}

    (dest / "layers").mkdir(exist_ok=True)
    write_compact(
        dest / "layers" / "public_land.geojson",
        real_layer_features(fc, {"leisure", "boundary", "landuse", "natural"}),
    )
    write_compact(
        dest / "layers" / "flood.geojson",
        {
            "type": "FeatureCollection",
            "features": [
                f
                for f in fc["features"]
                if (f.get("properties") or {}).get("natural") == "water"
                or (f.get("properties") or {}).get("landuse") == "reservoir"
            ][:400],
            "attribution": OSM_CREDIT,
        },
    )
    write_compact(dest / "layers" / "hazards.geojson", {"type": "FeatureCollection", "features": [], "attribution": OSM_CREDIT})

    hill = dest / "hillshade.png"
    hillshade_meta: dict = {"present": False, "reason": "no hillshade.png"}
    if hill.is_file() and hill.stat().st_size > 100:
        hillshade_meta = {
            "present": True,
            "file": "hillshade.png",
            "bytes": hill.stat().st_size,
            "attribution": "USGS 3DEP hillshade, build-time only",
            "coordinates": [
                [bb["west"], bb["north"]],
                [bb["east"], bb["north"]],
                [bb["east"], bb["south"]],
                [bb["west"], bb["south"]],
            ],
        }
    n_glyphs = fetch_glyphs(dest / "glyphs")
    print(f"  glyphs {n_glyphs}", flush=True)
    write_json(dest / "style.json", maplibre_style(pack["id"], hillshade_meta if hillshade_meta.get("present") else None))
    pois = [f for f in fc["features"] if f["geometry"]["type"] == "Point"]
    write_compact(dest / "pois.geojson", {"type": "FeatureCollection", "features": pois[:800], "attribution": OSM_CREDIT})
    stats = pack_stats(fc, graph)
    files = [p for p in dest.rglob("*") if p.is_file()]
    size = sum(p.stat().st_size for p in files)
    terrain_note = (
        "USGS 3DEP hillshade bundled; contours from build-time Open-Meteo DEM."
        if hillshade_meta.get("present")
        else f"3DEP omitted ({hillshade_meta.get('reason')}); contours from build-time Open-Meteo DEM."
    )
    manifest = {
        "id": pack["id"],
        "name": pack["name"],
        "state": pack["state"],
        "kind": "osm-contour-extract",
        "engine": "maplibre",
        "defaultOpen": True,
        "walkable": True,
        "bbox": bb,
        "slices": slice_summaries,
        "banners": pack["banners"],
        "bytes": size,
        "files": sorted(str(p.relative_to(dest)) for p in files),
        "center": {"lat": (bb["south"] + bb["north"]) / 2, "lon": (bb["west"] + bb["east"]) / 2},
        "attribution": f"{OSM_CREDIT}. {terrain_note} No runtime uplink.",
        "terrain": hillshade_meta,
        "stats": stats,
    }
    write_json(dest / "manifest.json", manifest)
    print(
        f"  packed {pack['id']} {size} bytes streets={stats['namedStreets']} "
        f"hwy={stats['highwayLines']} edges={stats['graphEdges']} "
        f"walking={stats['streetsVisibleAtWalkingZoom']}",
        flush=True,
    )
    print(f"  sample streets: {stats['sampleStreetNames']}", flush=True)
    return manifest


def main(ids: list[str] | None = None) -> None:
    root = ROOT / "Resources" / "Packs"
    root.mkdir(parents=True, exist_ok=True)
    wanted = ids or list(PACKS)
    for pid in wanted:
        pack = PACKS[pid]
        print("PACK", pack["id"], flush=True)
        fetch_pack(pack, root / pack["id"])
    write_catalog(root)


if __name__ == "__main__":
    main(sys.argv[1:] or None)
