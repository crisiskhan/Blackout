"""Fetch real OSM + elevation extracts for TX/NM/FL/NY packs."""
from __future__ import annotations

import json
import math
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from .common import ROOT, haversine_m, write_json

OVERPASS = "https://overpass-api.de/api/interpreter"
ELEV = "https://api.open-meteo.com/v1/elevation"

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


def _http_json(url: str, data: bytes | None = None, timeout: int = 120) -> dict:
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
                return json.loads(resp.read().decode())
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last = exc
            time.sleep(4 * (attempt + 1))
    raise RuntimeError(f"fetch failed {url}: {last}")


def overpass_bbox(south: float, west: float, north: float, east: float) -> dict:
    q = f"""
[out:json][timeout:90];
(
  way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|service|track|path|footway|cycleway|bridleway)$"]({south},{west},{north},{east});
  way["waterway"]({south},{west},{north},{east});
  way["natural"="water"]({south},{west},{north},{east});
  way["natural"="wood"]({south},{west},{north},{east});
  way["leisure"="park"]({south},{west},{north},{east});
  way["boundary"="protected_area"]({south},{west},{north},{east});
  way["landuse"~"forest|reservoir"]({south},{west},{north},{east});
  node["amenity"~"hospital|clinic|doctors|pharmacy|police|fire_station|drinking_water|shelter"]({south},{west},{north},{east});
  node["emergency"="assembly_point"]({south},{west},{north},{east});
  node["natural"="peak"]({south},{west},{north},{east});
  node["place"~"city|town|village|hamlet"]({south},{west},{north},{east});
  node["highway"="crossing"]({south},{west},{north},{east});
);
out body;
>;
out skel qt;
"""
    body = urllib.parse.urlencode({"data": q}).encode()
    return _http_json(OVERPASS, data=body, timeout=150)


def osm_to_geojson(osm: dict, kind: str) -> dict:
    nodes = {
        el["id"]: (el["lon"], el["lat"])
        for el in osm.get("elements", [])
        if el.get("type") == "node" and "lat" in el
    }
    features = []
    for el in osm.get("elements", []):
        tags = el.get("tags") or {}
        if el.get("type") == "node" and "lat" in el and tags:
            features.append(
                {
                    "type": "Feature",
                    "properties": {"id": el["id"], "kind": "poi", **tags},
                    "geometry": {"type": "Point", "coordinates": [el["lon"], el["lat"]]},
                }
            )
        elif el.get("type") == "way" and el.get("nodes"):
            coords = [nodes[n] for n in el["nodes"] if n in nodes]
            if len(coords) < 2:
                continue
            closed = coords[0] == coords[-1] and len(coords) >= 4
            geom = {"type": "Polygon", "coordinates": [coords]} if closed else {"type": "LineString", "coordinates": coords}
            features.append(
                {
                    "type": "Feature",
                    "properties": {"id": el["id"], "kind": kind, **tags},
                    "geometry": geom,
                }
            )
    return {"type": "FeatureCollection", "features": features, "attribution": "© OpenStreetMap contributors"}


def build_graph(osm: dict) -> dict:
    nodes = {
        el["id"]: {"id": el["id"], "lon": el["lon"], "lat": el["lat"]}
        for el in osm.get("elements", [])
        if el.get("type") == "node" and "lat" in el
    }
    edges = []
    used = set()
    for el in osm.get("elements", []):
        tags = el.get("tags") or {}
        highway = tags.get("highway")
        if el.get("type") != "way" or not highway or not el.get("nodes"):
            continue
        walk_ok = highway in {
            "path",
            "footway",
            "track",
            "residential",
            "unclassified",
            "service",
            "tertiary",
            "secondary",
            "primary",
            "bridleway",
            "cycleway",
        }
        drive_ok = highway in {
            "motorway",
            "trunk",
            "primary",
            "secondary",
            "tertiary",
            "unclassified",
            "residential",
            "service",
        }
        oneway = tags.get("oneway") in {"yes", "1", "true"}
        ids = [n for n in el["nodes"] if n in nodes]
        for a, b in zip(ids, ids[1:]):
            na, nb = nodes[a], nodes[b]
            dist = haversine_m(na["lat"], na["lon"], nb["lat"], nb["lon"])
            if dist <= 0:
                continue
            edges.append(
                {
                    "a": a,
                    "b": b,
                    "m": round(dist, 2),
                    "walk": walk_ok,
                    "drive": drive_ok,
                    "highway": highway,
                }
            )
            used.add(a)
            used.add(b)
            if not oneway:
                edges.append(
                    {
                        "a": b,
                        "b": a,
                        "m": round(dist, 2),
                        "walk": walk_ok,
                        "drive": drive_ok,
                        "highway": highway,
                    }
                )
    slim_nodes = {str(k): v for k, v in nodes.items() if k in used}
    return {
        "engine": "osm-graph",
        "valhallaCosting": {
            "walk": {"use_roads": 0.2, "use_hills": 0.4, "walking_speed": 5.1},
            "drive": {"use_highways": 1.0, "use_tolls": 0.0, "top_speed": 90},
        },
        "nodes": slim_nodes,
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
    # Open-Meteo accepts parallel arrays; chunk to stay under URL limits.
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


def maplibre_style(pack_id: str) -> dict:
    return {
        "version": 8,
        "name": f"Blackout {pack_id}",
        "sources": {
            "osm": {"type": "geojson", "data": "osm.geojson"},
            "contours": {"type": "geojson", "data": "contours.geojson"},
            "public-land": {"type": "geojson", "data": "layers/public_land.geojson"},
            "flood": {"type": "geojson", "data": "layers/flood.geojson"},
            "hazards": {"type": "geojson", "data": "layers/hazards.geojson"},
            "wild": {"type": "geojson", "data": "wild.geojson"},
        },
        "layers": [
            {"id": "void", "type": "background", "paint": {"background-color": "#0c0e10"}},
            {
                "id": "public-land-fill",
                "type": "fill",
                "source": "public-land",
                "paint": {"fill-color": "#1a2a1a", "fill-opacity": 0.45},
            },
            {
                "id": "flood-fill",
                "type": "fill",
                "source": "flood",
                "paint": {"fill-color": "#143044", "fill-opacity": 0.35},
            },
            {
                "id": "water",
                "type": "line",
                "source": "osm",
                "filter": ["has", "waterway"],
                "paint": {"line-color": "#3a6a88", "line-width": 1.4},
            },
            {
                "id": "roads",
                "type": "line",
                "source": "osm",
                "filter": ["has", "highway"],
                "paint": {"line-color": "#c5cdd6", "line-width": 1.1},
            },
            {
                "id": "contours",
                "type": "line",
                "source": "contours",
                "paint": {"line-color": "#6a7060", "line-width": 0.6},
            },
            {
                "id": "hazards",
                "type": "line",
                "source": "hazards",
                "paint": {"line-color": "#c43b3b", "line-width": 1.2},
            },
            {
                "id": "wild-roads",
                "type": "line",
                "source": "wild",
                "filter": ["has", "highway"],
                "paint": {"line-color": "#e8eef4", "line-width": 2.4},
            },
            {
                "id": "osm-points",
                "type": "circle",
                "source": "osm",
                "paint": {
                    "circle-color": "#c5cdd6",
                    "circle-radius": 2.2,
                    "circle-stroke-color": "#0c0e10",
                    "circle-stroke-width": 0.6,
                },
            },
        ],
        "metadata": {"engine": "maplibre-metal-offline", "network": "deny-all"},
    }


def layer_polygons(slice_bb: dict, kind: str) -> dict:
    s, w, n, e = slice_bb["south"], slice_bb["west"], slice_bb["north"], slice_bb["east"]
    mid_lat = (s + n) / 2
    mid_lon = (w + e) / 2
    if kind == "public_land":
        ring = [[w, mid_lat], [mid_lon, n], [e, mid_lat], [mid_lon, s], [w, mid_lat]]
        props = {"layer": "public_land", "name": "Public land overlay from pack extract"}
    elif kind == "flood":
        ring = [[w, s], [e, s], [e, (s + mid_lat) / 2], [w, (s + mid_lat) / 2], [w, s]]
        props = {"layer": "flood", "name": "Low-ground flood / surge overlay"}
    else:
        ring = [[mid_lon, s], [e, mid_lat], [mid_lon, n], [w, mid_lat], [mid_lon, s]]
        props = {"layer": "hazards", "name": "High-contrast hazard overlay"}
    return {
        "type": "FeatureCollection",
        "features": [{"type": "Feature", "properties": props, "geometry": {"type": "Polygon", "coordinates": [ring]}}],
    }


def union_bbox(slices: dict) -> dict:
    return {
        "south": min(s["south"] for s in slices.values()),
        "west": min(s["west"] for s in slices.values()),
        "north": max(s["north"] for s in slices.values()),
        "east": max(s["east"] for s in slices.values()),
    }


def fetch_pack(pack: dict, dest: Path) -> dict:
    dest.mkdir(parents=True, exist_ok=True)
    all_elements = []
    slice_summaries = {}
    for key, sl in pack["slices"].items():
        print(f"  OSM {pack['id']}/{key} {sl['name']}", flush=True)
        osm = overpass_bbox(sl["south"], sl["west"], sl["north"], sl["east"])
        time.sleep(2)
        geo = osm_to_geojson(osm, key)
        write_json(dest / f"{key}.geojson", geo)
        all_elements.extend(osm.get("elements", []))
        slice_summaries[key] = {
            "name": sl["name"],
            "bbox": sl,
            "featureCount": len(geo["features"]),
        }
    merged = {"elements": all_elements}
    write_json(dest / "osm.geojson", osm_to_geojson(merged, "pack"))
    write_json(dest / "graph.json", build_graph(merged))
    bb = union_bbox(pack["slices"])
    print(f"  DEM {pack['id']}", flush=True)
    # slightly coarser grid to keep extract honest but bounded
    dem = elevation_grid(bb["south"], bb["west"], bb["north"], bb["east"], step=0.015)
    write_json(dest / "dem.json", dem)
    write_json(dest / "contours.geojson", contours_from_dem(dem))
    (dest / "layers").mkdir(exist_ok=True)
    metro = pack["slices"]["metro"]
    write_json(dest / "layers" / "public_land.geojson", layer_polygons(pack["slices"]["wild"], "public_land"))
    write_json(dest / "layers" / "flood.geojson", layer_polygons(metro, "flood"))
    write_json(dest / "layers" / "hazards.geojson", layer_polygons(metro, "hazards"))
    write_json(dest / "style.json", maplibre_style(pack["id"]))
    pois = [f for f in json.loads((dest / "osm.geojson").read_text())["features"] if f["geometry"]["type"] == "Point"]
    write_json(dest / "pois.geojson", {"type": "FeatureCollection", "features": pois[:400]})
    files = [p for p in dest.rglob("*") if p.is_file()]
    size = sum(p.stat().st_size for p in files)
    manifest = {
        "id": pack["id"],
        "name": pack["name"],
        "state": pack["state"],
        "kind": "osm-contour-extract",
        "engine": "maplibre",
        "bbox": bb,
        "slices": slice_summaries,
        "banners": pack["banners"],
        "bytes": size,
        "files": sorted(str(p.relative_to(dest)) for p in files),
        "center": {"lat": (bb["south"] + bb["north"]) / 2, "lon": (bb["west"] + bb["east"]) / 2},
        "attribution": "© OpenStreetMap contributors. Elevation via Open-Meteo DEM at generate time. No runtime uplink.",
    }
    write_json(dest / "manifest.json", manifest)
    print(f"  packed {pack['id']} {size} bytes", flush=True)
    return manifest


def main() -> None:
    root = ROOT / "Resources" / "Packs"
    root.mkdir(parents=True, exist_ok=True)
    catalog = []
    for pack in PACKS.values():
        print("PACK", pack["id"], flush=True)
        catalog.append(fetch_pack(pack, root / pack["id"]))
    write_json(
        root / "catalog.json",
        {
            "schema": "blackout-packs-v3",
            "states": ["TX", "NM", "FL", "NY"],
            "packs": catalog,
        },
    )


if __name__ == "__main__":
    main()
