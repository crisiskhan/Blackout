"""Fetch real OSM + elevation extracts for TX/NM walkable packs.

Primary walkable pack is tx-west: one El Paso / Franklin / TX+NM border bbox
with walking-zoom streets, names, and a graph built from those same ways.
Walkable catalog packs: nm (Albuquerque / Sandia) and tx-east (Austin metro
+ Lost Pines / Bastrop). Neither steals default open — Crisis keeps tx-west
first-open until they say switch. FL/NY sticker packs are not catalogued
or bundled.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import math
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

from shapely.geometry import Polygon, mapping
from shapely.ops import unary_union
from shapely.validation import make_valid

from . import graphbin, ground, tiles
from .common import ROOT, haversine_m, write_json

OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]
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

# graph.json wire format. Coordinates at 5 decimals are ~1.1 m — finer than any
# street the canvas draws — and segment lengths to 0.1 m. The flags say which
# way a segment may be walked and which way it may be driven, so one record
# replaces the two directed edges that used to spell it out.
GRAPH_WIRE_VERSION = 2
COORD_DP = 5
METRES_DP = 1
# Drawn geometry keeps one more decimal than the router graph: 11 cm, so a
# street never visibly kinks even at full zoom.
OVERPASS_TRIES = 6
OVERPASS_CACHE = Path(tempfile.gettempdir()) / "blackout-overpass"

RENDER_DP = 6
# Douglas-Peucker tolerance in degrees. 1e-5 is about 1.1 m — under one lane
# width, so the canvas draws the same street and the pack buys area with the
# vertices it stops shipping.
RENDER_EPS = 1e-5
WALK_FORWARD, DRIVE_FORWARD, WALK_BACK, DRIVE_BACK = 1, 2, 4, 8

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
    # A tank, a well and a cistern are all `man_made`, and they are the only
    # water most of this country has. `water` separates a stock pond from a
    # reservoir, and `intermittent` is the difference between a creek and a
    # wash that is dry eleven months a year.
    "man_made",
    "water",
    # Whether a tank holds water or diesel. Without it a storage tank is an
    # unknown, and an unknown drawn as water is a lie.
    "content",
    "intermittent",
    "seasonal",
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
VOID_INK = "#000000"
ACCENT_INK = "#E10600"
SILVER_INK = "#B8BDC2"
WATER_INK = "#6E747A"
WATER_FILL = "#1A1C1E"
WATER_EPHEMERAL = "#54595E"
TRACK_HIGHWAYS = ["track", "path", "footway", "bridleway", "cycleway", "steps"]
# Ground cover ink. All of it is within a few points of black on purpose: the
# job is to tell desert from bosque at a glance without ever competing with a
# silver street or a red route. Anything the tiler classes and this does not
# name falls through to the default and draws as plain ground.
LAND_INK = [
    "match",
    ["get", "class"],
    "desert", "#17120c",
    "playa", "#1a1a1e",
    "mountain", "#121417",
    "bosque", "#0b1410",
    "woodland", "#0a120d",
    "farm", "#0e1410",
    "town", "#141417",
    "park", "#0a140a",
    "protected", "#0c1310",
    "#101010",
]
MAJOR_HIGHWAYS = [
    "motorway",
    "motorway_link",
    "trunk",
    "trunk_link",
    "primary",
    "primary_link",
    "secondary",
    "secondary_link",
]
ARTERIAL_HIGHWAYS = ["motorway", "trunk", "primary"]

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
            "corridor": {
                "name": "El Paso / Las Cruces corridor",
                "south": 31.65,
                "west": -106.85,
                "north": 32.40,
                "east": -106.20,
            },
            # Widest slice, so it sets the pack bbox. El Paso and Juarez stay in
            # the middle of it; the room goes to Fort Bliss and the Franklins,
            # Santa Teresa and Sunland Park west, Horizon City east, and the
            # I-10 run north through Anthony to Las Cruces and the Organs.
            # South and west sit a whole tile below the previous edge so the
            # Overpass grid still lands on tiles already fetched.
            "region": {
                "name": "El Paso / Las Cruces / Organ Mountains region",
                "south": 30.95,
                "west": -107.60,
                "north": 33.15,
                "east": -105.35,
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
            "union": {
                "name": "Austin / Lost Pines walkable union",
                "south": 30.08,
                "west": -97.90,
                "north": 30.42,
                "east": -97.20,
            },
            # Widest slice: Austin core out to Pflugerville and Manor north,
            # Elgin and Bastrop east, Buda and Kyle south.
            "region": {
                "name": "Austin / Bastrop / Buda region",
                "south": 30.05,
                "west": -97.95,
                "north": 30.50,
                "east": -97.20,
            },
        },
        "banners": ["heat-island", "cattle-guard", "hurricane"],
        "walkable": True,
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
            "union": {
                "name": "Albuquerque / Rio Rancho / Sandia union",
                "south": 34.95,
                "west": -106.85,
                "north": 35.35,
                "east": -106.35,
            },
            # Widest slice: Albuquerque out to Bernalillo and Placitas north,
            # Sandia crest east, South Valley and Isleta south, Rio Puerco west.
            "region": {
                "name": "Albuquerque / Bernalillo / Isleta region",
                "south": 34.35,
                "west": -107.45,
                "north": 35.95,
                "east": -105.65,
            },
        },
        "banners": ["monsoon", "ice-rock", "cattle-guard", "border-hospitals"],
        "walkable": True,
    },
}


def walkable_ids() -> set[str]:
    return {pid for pid, pack in PACKS.items() if pack.get("walkable")}


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


RESOURCE_TAGS = {
    "natural": "^(spring|scrub|sand|dune|bare_rock|scree|wetland|heath|grassland|sinkhole|cave|cave_entrance|tree)$",
    "man_made": "^(water_well|water_tank|storage_tank|cistern|reservoir_covered)$",
    "landuse": "^(farmland|orchard|meadow|vineyard|basin|salt_pond|greenhouse_horticulture|residential)$",
}


def overpass_resources(south: float, west: float, north: float, east: float) -> dict:
    """The water and ground the first pass never asked for.

    The original query fetched streets, waterways and lakes. It did not fetch
    the springs, wells and stock tanks that are the only water out here, and it
    did not fetch the scrub, sand and bare rock that say what the ground is.
    This is a second, narrow pass for exactly those, run over the same bbox so
    it merges into the extract already on disk instead of replacing it.
    """
    box = f"{south},{west},{north},{east}"
    lines = []
    for key, pattern in RESOURCE_TAGS.items():
        lines.append(f'  node["{key}"~"{pattern}"]({box});')
        lines.append(f'  way["{key}"~"{pattern}"]({box});')
    body = "\n".join(lines)
    q = f"""
[out:json][timeout:180];
(
{body}
);
out body;
>;
out skel qt;
"""
    return _overpass(q, f"res:{box}")


# Phrase match, not a dump of every protected forest. Must stay in step with
# `Inspect.isWildlifeRange` / `ground.WILDLIFE_RANGE_PHRASES`. Lincoln National
# Forest does not match. Wildlife Drive is a street and is not a relation
# with these phrases.
NOTABLE_WILDLIFE_NAME = (
    "wildlife refuge|wildlife management area|national wildlife|"
    "wildlife sanctuary|wildlife conservation area|game commission|"
    "wilderness preserve|nature preserve|nature center|natural area|"
    "nature area|wildlife preserve|habitat preserve|national preserve|"
    "wilderness park|audubon|flora y fauna|"
    "canyonlands preserve|wetland preserve"
)


def overpass_notable(south: float, west: float, north: float, east: float) -> dict:
    """Named nature-reserve polygons, cave mouths, and named trees.

    The tiled street query never asked for relations, and `osm_to_geojson`
    used to drop them even when Overpass returned them. This is a separate
    pass so a huge reserve does not ride the 0.12° street tiles. It does not
    ask for every `boundary=protected_area` forest — Lincoln National Forest
    is not a picnic dump. A wildlife-named protected-area relation is range,
    not timber. Cave *areas* come in as ways so the tiler can put a mouth
    on the place slice. Size is not a reason to skip a record the Hold
    can name. Animals are range, never a GPS pin. Nothing here is a meal.
    """
    box = f"{south},{west},{north},{east}"
    q = f"""
[out:json][timeout:300];
(
  relation["leisure"="nature_reserve"]({box});
  way["leisure"="nature_reserve"]({box});
  relation["boundary"="protected_area"]["name"~"{NOTABLE_WILDLIFE_NAME}",i]({box});
  way["leisure"="park"]["name"~"{NOTABLE_WILDLIFE_NAME}",i]({box});
  node["natural"="cave"]({box});
  node["natural"="cave_entrance"]({box});
  node["natural"="sinkhole"]({box});
  way["natural"="cave"]({box});
  way["natural"="cave_entrance"]({box});
  way["natural"="sinkhole"]({box});
  relation["natural"="cave"]({box});
  node["natural"="tree"]["name"]({box});
  way["natural"="tree"]["name"]({box});
);
out body;
>;
out skel qt;
"""
    return _overpass(q, f"notable:{box}", timeout=330)


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
  node["natural"="cave"]({south},{west},{north},{east});
  node["natural"="cave_entrance"]({south},{west},{north},{east});
  node["natural"="tree"]({south},{west},{north},{east});
  node["place"~"city|town|village|hamlet|suburb|neighbourhood|quarter"]({south},{west},{north},{east});
);
out body;
>;
out skel qt;
"""
    return _overpass(q, f"{south},{west},{north},{east}")


def _overpass(q: str, cache_key: str, timeout: int = 210) -> dict:
    body = urllib.parse.urlencode({"data": q}).encode()
    # A pack is well over a hundred tiles now, so one refused slot must not
    # throw away the tiles already paid for. Cache each answer on disk and back
    # off rather than failing the run.
    #
    # The query is part of the key, not just the bbox. Asking a wider question
    # about the same ground has to miss the cache, or adding a tag would
    # silently reuse answers from before it was asked for.
    key = hashlib.sha1(f"{cache_key}\n{q}".encode()).hexdigest()[:16]
    cached = OVERPASS_CACHE / f"{key}.json"
    if cached.is_file():
        try:
            return json.loads(cached.read_text())
        except Exception:
            cached.unlink(missing_ok=True)
    last: Exception | None = None
    for attempt in range(OVERPASS_TRIES):
        for url in OVERPASS_ENDPOINTS:
            try:
                out = _http_json(url, data=body, timeout=timeout)
                OVERPASS_CACHE.mkdir(parents=True, exist_ok=True)
                cached.write_text(json.dumps(out, separators=(",", ":")))
                return out
            except Exception as exc:
                last = exc
                print(f"  overpass fail {url}: {exc}", flush=True)
        wait = min(60, 4 * 2**attempt)
        print(f"  overpass retry {attempt + 1}/{OVERPASS_TRIES} in {wait}s", flush=True)
        time.sleep(wait)
    raise RuntimeError(f"overpass failed: {last}")


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
    seen_r: set[int] = set()
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
            elif kind == "relation":
                if eid in seen_r:
                    continue
                seen_r.add(eid)
            elements.append(el)
    return {"elements": elements}


def simplify(coords: list[list[float]], eps: float) -> list[list[float]]:
    """Douglas-Peucker, so a street costs the bytes its shape needs.

    OSM carries survey-grade vertices. At the zooms a phone draws, a run of
    points inside a metre of the same straight line is bytes the canvas cannot
    show. Endpoints are always kept, so ways still meet where they met.
    """
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
                d = math.hypot(px - ax, py - ay)
            else:
                t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / den))
                d = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
            if d > far:
                far, pick = d, k
        if far > eps and pick > 0:
            keep[pick] = True
            stack.append((i, pick))
            stack.append((pick, j))
    return [c for c, k in zip(coords, keep) if k]


def _way_chain(
    el: dict, nodes: dict[int, tuple[float, float]]
) -> list[tuple[float, float]] | None:
    nids = el.get("nodes") or []
    if nids:
        coords = [nodes[n] for n in nids if n in nodes]
        if len(coords) >= 2:
            return coords
    geom = el.get("geometry") or []
    if len(geom) < 2:
        return None
    out = [
        (round(p["lon"], RENDER_DP), round(p["lat"], RENDER_DP))
        for p in geom
        if "lon" in p and "lat" in p
    ]
    return out if len(out) >= 2 else None


def _join_rings(chains: list[list[tuple[float, float]]]) -> list[list[list[float]]]:
    """Join member ways that share endpoints into closed rings.

    OSM multipolygons are often several open ways, not one closed way. Treating
    each way as its own polygon dropped Franklin Mountains State Park.
    Incomplete rings are skipped rather than closed across the pack.
    """
    remaining = [list(chain) for chain in chains if len(chain) >= 2]
    rings: list[list[list[float]]] = []
    while remaining:
        ring = remaining.pop(0)
        progressed = True
        while progressed:
            progressed = False
            if len(ring) >= 4 and ring[0] == ring[-1]:
                break
            for i, other in enumerate(remaining):
                if ring[-1] == other[0]:
                    ring.extend(other[1:])
                elif ring[-1] == other[-1]:
                    ring.extend(reversed(other[:-1]))
                elif ring[0] == other[-1]:
                    ring = other[:-1] + ring
                elif ring[0] == other[0]:
                    ring = list(reversed(other[1:])) + ring
                else:
                    continue
                remaining.pop(i)
                progressed = True
                break
        if len(ring) < 4 or ring[0] != ring[-1]:
            continue
        closed = [list(pt) for pt in ring]
        simplified = simplify(closed, RENDER_EPS)
        if not simplified:
            continue
        if simplified[0] != simplified[-1]:
            simplified.append(simplified[0])
        if len(simplified) >= 4:
            rings.append(simplified)
    return rings


def relation_geometry(
    el: dict, nodes: dict[int, tuple[float, float]], ways: dict[int, dict]
) -> dict | None:
    """Assemble a relation into Polygon / MultiPolygon from member ways.

    Overpass ``out body; >; out skel qt`` inlines member ways and nodes.
    Size is not a reason to skip a named nature reserve.
    """
    outers: list[list[tuple[float, float]]] = []
    inners: list[list[tuple[float, float]]] = []
    for mem in el.get("members") or []:
        if mem.get("type") != "way":
            continue
        way = ways.get(mem.get("ref"))
        if not way:
            continue
        chain = _way_chain(way, nodes)
        if not chain:
            continue
        role = mem.get("role") or "outer"
        if role == "inner":
            inners.append(chain)
        else:
            outers.append(chain)
    outer_rings = _join_rings(outers)
    inner_rings = _join_rings(inners)
    if not outer_rings:
        return None
    inner_polys: list[tuple[list[list[float]], object]] = []
    for inner in inner_rings:
        try:
            hole = make_valid(Polygon(inner))
        except (ValueError, TypeError):
            continue
        if hole.is_empty:
            continue
        inner_polys.append((inner, hole))
    polys: list = []
    for outer in outer_rings:
        try:
            poly = make_valid(Polygon(outer))
        except (ValueError, TypeError):
            continue
        if poly.is_empty:
            continue
        holes = []
        for inner, hole in inner_polys:
            try:
                if poly.contains(hole.representative_point()):
                    holes.append(inner)
            except (ValueError, TypeError):
                continue
        try:
            poly = make_valid(Polygon(outer, holes))
        except (ValueError, TypeError):
            continue
        if not poly.is_empty:
            polys.append(poly)
    if not polys:
        return None
    geom = unary_union(polys)
    if geom.is_empty:
        return None
    if geom.geom_type == "GeometryCollection":
        geom = unary_union(
            [g for g in geom.geoms if g.geom_type in ("Polygon", "MultiPolygon")]
        )
        if geom.is_empty:
            return None
    mapped = mapping(geom)
    if mapped.get("type") not in ("Polygon", "MultiPolygon"):
        return None
    return mapped


def osm_to_geojson(osm: dict) -> dict:
    """OSM elements to the GeoJSON the canvas draws.

    Coordinates keep RENDER_DP decimals — 11 cm, finer than any line MapLibre
    can put on a phone — instead of Overpass's 7. The OSM element id and the
    old constant `kind` property are dropped: no style layer filters on them
    and no Swift reads them, so they were 2 MB of dead weight per pack.
    Relations are assembled from member ways: a nature reserve mapped as a
    multipolygon is a polygon here, not silence.
    """
    nodes = {
        el["id"]: (round(el["lon"], RENDER_DP), round(el["lat"], RENDER_DP))
        for el in osm.get("elements", [])
        if el.get("type") == "node" and "lat" in el
    }
    ways = {
        el["id"]: el
        for el in osm.get("elements", [])
        if el.get("type") == "way"
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
                    "properties": tags,
                    "geometry": {"type": "Point", "coordinates": list(nodes[el["id"]])},
                }
            )
        elif el.get("type") == "relation":
            if not tags:
                continue
            geom = relation_geometry(el, nodes, ways)
            if not geom:
                continue
            features.append({"type": "Feature", "properties": tags, "geometry": geom})
        elif el.get("type") == "way" and el.get("nodes"):
            if not tags:
                continue
            coords = [list(nodes[n]) for n in el["nodes"] if n in nodes]
            if len(coords) < 2:
                continue
            closed = coords[0] == coords[-1] and len(coords) >= 4
            if closed and tags.get("highway") is None:
                geom = {"type": "Polygon", "coordinates": [simplify(coords, RENDER_EPS)]}
            else:
                geom = {"type": "LineString", "coordinates": simplify(coords, RENDER_EPS)}
            features.append({"type": "Feature", "properties": tags, "geometry": geom})
    return {"type": "FeatureCollection", "features": features, "attribution": OSM_CREDIT}


def _clip_anchor(geom: dict) -> tuple[float, float] | None:
    coords = geom.get("coordinates")
    kind = geom.get("type")
    if kind == "Point" and isinstance(coords, list) and len(coords) >= 2:
        return (coords[1], coords[0])
    if kind == "LineString" and coords:
        lon, lat = coords[0]
        return (lat, lon)
    if kind == "Polygon" and coords and coords[0]:
        lon, lat = coords[0][0]
        return (lat, lon)
    if kind == "MultiPolygon" and coords and coords[0] and coords[0][0]:
        lon, lat = coords[0][0][0]
        return (lat, lon)
    return None


def clip_features(fc: dict, sl: dict) -> dict:
    feats = []
    for f in fc.get("features") or []:
        pt = _clip_anchor(f.get("geometry") or {})
        if pt is None:
            continue
        lat, lon = pt
        if sl["south"] <= lat <= sl["north"] and sl["west"] <= lon <= sl["east"]:
            feats.append(f)
    return {"type": "FeatureCollection", "features": feats, "attribution": OSM_CREDIT}


BLOCKED = {"no", "private"}
ALLOWED = {"yes", "designated", "permissive", "destination"}


def way_access(
    tags: dict, highway: str, walk_set: set[str], drive_set: set[str]
) -> tuple[bool, bool]:
    """Who is actually allowed down this way, not just what it is tagged as."""
    walk = highway in walk_set
    drive = highway in drive_set
    if tags.get("access") in BLOCKED:
        walk = False
        drive = False
    foot = tags.get("foot")
    if foot in BLOCKED:
        walk = False
    elif foot in ALLOWED:
        walk = True
    if (tags.get("motor_vehicle") or tags.get("vehicle")) in BLOCKED:
        drive = False
    return walk, drive


def way_directions(tags: dict) -> tuple[bool, bool, bool, bool]:
    """Direction is per travel mode.

    `oneway` is a rule about cars. A pedestrian walks a one-way street in both
    directions, so folding the car restriction into the walk graph invented
    detours -- and sometimes no path at all -- on the side of the street the
    traffic happens to run against. Only `oneway:foot` binds feet.
    """
    def sides(value: str | None) -> tuple[bool, bool]:
        # "-1" means the traffic runs against the way's node order, so the
        # passable direction is the reverse one, not neither.
        if value == "-1":
            return False, True
        return True, value not in {"yes", "1", "true"}

    ow = tags.get("oneway")
    if tags.get("junction") in {"roundabout", "circular"} and ow is None:
        ow = "yes"
    drive_fwd, drive_back = sides(ow)
    walk_fwd, walk_back = sides(tags.get("oneway:foot"))
    return walk_fwd, walk_back, drive_fwd, drive_back


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
        walk_ok, drive_ok = way_access(tags, highway, walk_ok_set, drive_ok_set)
        if not walk_ok and not drive_ok:
            continue
        walk_fwd, walk_back, drive_fwd, drive_back = way_directions(tags)
        ids = [n for n in el["nodes"] if n in nodes]
        for a, b in zip(ids, ids[1:]):
            na, nb = nodes[a], nodes[b]
            dist = haversine_m(na["lat"], na["lon"], nb["lat"], nb["lon"])
            if dist <= 0:
                continue
            for (x, y), walk_dir, drive_dir in (
                ((a, b), walk_fwd, drive_fwd),
                ((b, a), walk_back, drive_back),
            ):
                walk = walk_ok and walk_dir
                drive = drive_ok and drive_dir
                if not walk and not drive:
                    continue
                edges.append(
                    {"a": x, "b": y, "m": round(dist, 2), "walk": walk, "drive": drive}
                )
                used.add(x)
                used.add(y)
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


def pack_graph(g: dict) -> dict:
    """Squeeze the router graph onto the wire without losing a single turn.

    Nodes stop repeating their OSM id and become dense indices into parallel
    lat/lon arrays. A street segment stops being two spelled-out edges with
    `"walk":true,"drive":true` on each and becomes one `a, b, metres, flags`
    record, where the flags say which way you may walk and which way you may
    drive. Same directed graph, about a fifth of the bytes.

    Mirrored by PackedGraph in Packages/Router. Change one, change both.
    """
    nodes = g.get("nodes") or {}
    ids = sorted(int(k) for k in nodes)
    index = {n: i for i, n in enumerate(ids)}
    lat = [round(float(nodes[str(n)]["lat"]), COORD_DP) for n in ids]
    lon = [round(float(nodes[str(n)]["lon"]), COORD_DP) for n in ids]

    scale = 10**METRES_DP
    span: dict[tuple[int, int], float] = {}

    def metres_between(a: int, b: int) -> float:
        """Length of the segment as the shipped coordinates place it.

        Packing rounds coordinates to COORD_DP, which can move an endpoint about
        a metre. The router steers A* by the straight line between these same
        shipped points, so a stored length shorter than that line would make the
        heuristic inadmissible and the "shortest" route no longer shortest.
        Measure after the rounding and never round the answer down.
        """
        if (a, b) not in span:
            raw = haversine_m(lat[a], lon[a], lat[b], lon[b])
            span[(a, b)] = max(math.ceil(raw * scale) / scale, 1 / scale)
        return span[(a, b)]

    segments: dict[tuple[int, int, float], int] = {}
    for e in g.get("edges") or []:
        a = index.get(int(e["a"]))
        b = index.get(int(e["b"]))
        if a is None or b is None:
            continue
        backward = a > b
        lo, hi = (b, a) if backward else (a, b)
        metres = metres_between(lo, hi)
        key = (lo, hi, metres)
        flags = 0
        if e.get("walk"):
            flags |= WALK_BACK if backward else WALK_FORWARD
        if e.get("drive"):
            flags |= DRIVE_BACK if backward else DRIVE_FORWARD
        segments[key] = segments.get(key, 0) | flags

    flat: list[float] = []
    for (a, b, metres), flags in segments.items():
        flat += [a, b, metres, flags]
    return {
        "v": GRAPH_WIRE_VERSION,
        "engine": g.get("engine") or "osm-graph",
        "valhallaCosting": g.get("valhallaCosting"),
        "lat": lat,
        "lon": lon,
        "e": flat,
    }


def unpack_graph(g: dict) -> dict:
    """Wire format back to nodes/edges, exactly as RouteGraph.load reads it."""
    if g.get("v") != GRAPH_WIRE_VERSION:
        return g
    lat = g.get("lat") or []
    lon = g.get("lon") or []
    nodes = {str(i): {"id": i, "lon": lon[i], "lat": lat[i]} for i in range(len(lat))}
    flat = g.get("e") or []
    edges = []
    for i in range(0, len(flat) - 3, 4):
        a, b, metres, flags = int(flat[i]), int(flat[i + 1]), float(flat[i + 2]), int(flat[i + 3])
        if str(a) not in nodes or str(b) not in nodes:
            continue
        if flags & (WALK_FORWARD | DRIVE_FORWARD):
            edges.append({"a": a, "b": b, "m": metres, "walk": bool(flags & WALK_FORWARD), "drive": bool(flags & DRIVE_FORWARD)})
        if flags & (WALK_BACK | DRIVE_BACK):
            edges.append({"a": b, "b": a, "m": metres, "walk": bool(flags & WALK_BACK), "drive": bool(flags & DRIVE_BACK)})
    return {
        "engine": g.get("engine"),
        "valhallaCosting": g.get("valhallaCosting"),
        "nodes": nodes,
        "edges": edges,
    }


def write_graph_binary(path: Path, graph: dict) -> int:
    """Write the router graph as `graph.bin`, and say how big it came out.

    `pack_graph` still does the thinking — dense ids, one record per segment,
    lengths measured after coordinate rounding so they never fall under the
    straight line the router steers by. This only lays the same numbers out as
    fixed-width arrays grouped by source node, which is the shape the phone
    reads them in. It parses nothing on the other end.
    """
    packed = pack_graph(graph)
    lat, lon, flat = packed["lat"], packed["lon"], packed["e"]
    segments: dict[tuple[int, int, float], int] = {}
    for i in range(0, len(flat) - 3, 4):
        key = (int(flat[i]), int(flat[i + 1]), float(flat[i + 2]))
        segments[key] = segments.get(key, 0) | int(flat[i + 3])
    csr = graphbin.csr_from_segments(len(lat), segments)
    return graphbin.write(path, lat, lon, csr["rowStart"], csr["target"], csr["millis"], csr["mode"])


def read_graph(path: Path) -> dict:
    """Load a pack graph as nodes/edges whatever is on disk."""
    if path.suffix == ".bin":
        g = graphbin.read(path)
        nodes = {
            str(i): {"id": i, "lon": g["lon"][i], "lat": g["lat"][i]}
            for i in range(len(g["lat"]))
        }
        return {"engine": "osm-graph", "valhallaCosting": None, "nodes": nodes, "edges": graphbin.edges(g)}
    return unpack_graph(json.loads(path.read_text()))


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
    if wrote < len(GLYPH_RANGES):
        packs_root = dest.parent.parent
        for sibling_id in ("nm", "tx-west"):
            src = packs_root / sibling_id / "glyphs" / GLYPH_STACK
            if not src.is_dir():
                continue
            for rng in GLYPH_RANGES:
                out = stack_dir / f"{rng}.pbf"
                cand = src / f"{rng}.pbf"
                if not out.is_file() and cand.is_file():
                    out.write_bytes(cand.read_bytes())
                    wrote += 1
            break
    return wrote


def zoom_stops(*pairs: float) -> list:
    expr: list = ["interpolate", ["linear"], ["zoom"]]
    expr.extend(pairs)
    return expr


def highway_in(values: list[str]) -> list:
    return ["in", ["get", "highway"], ["literal", values]]


# `osm.geojson` stays in the tree as the input the vector tiles are built from,
# but the app's copy step leaves it behind. The manifest describes what a phone
# receives, so it must not count a file the phone never sees.
STAMP = "osm.fetched"
# Build-time only. The extract is the tiler's input, and the date it carries
# reaches the phone through the manifest rather than as a loose file.
NOT_SHIPPED = {"osm.geojson", STAMP}


def stamp_fetch(dest: Path) -> str:
    """Record the day this pack's OSM was pulled, next to the extract itself.

    The manifest is rebuilt every time the tiling changes, so the date cannot
    live only there or a restyle would silently re-date year-old records. It
    lives in a file that is only written when Overpass is actually called.
    """
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    (dest / STAMP).write_text(day + "\n", encoding="utf-8")
    return day


def osm_fetched(dest: Path) -> str | None:
    """The recorded pull date, or nothing. Never a guess.

    A pack built before this was recorded has no honest answer, and the card
    prints no date at all rather than implying the record is fresh.
    """
    stamp = dest / STAMP
    if not stamp.is_file():
        return None
    day = stamp.read_text().strip()
    return day or None


def shipped_files(dest: Path) -> list[Path]:
    return [p for p in dest.rglob("*") if p.is_file() and p.name not in NOT_SHIPPED]


def write_manifest(dest: Path, manifest: dict | None = None) -> dict:
    """Recount shipped files and bytes after a derived layer is added.

    Used when glasshouses or water marks land on disk without recutting tiles.
    The phone's copy step ships whatever the manifest lists, so the list and
    the byte count have to agree with what is actually there. The manifest is
    itself a shipped file, so the count is written, measured, and written
    again if listing the new file changed the manifest's own size.
    """
    if manifest is None:
        manifest = json.loads((dest / "manifest.json").read_text())
    files = shipped_files(dest)
    manifest["files"] = sorted(str(p.relative_to(dest)) for p in files)
    write_json(dest / "manifest.json", manifest)
    for _ in range(3):
        actual = sum(p.stat().st_size for p in shipped_files(dest))
        if manifest.get("bytes") == actual:
            return manifest
        manifest["bytes"] = actual
        write_json(dest / "manifest.json", manifest)
    return manifest


def build_tiles(dest: Path, pack: dict) -> dict:
    """Cut the pack's streets into the vector tiles the canvas reads."""
    info = tiles.build(dest, union_bbox(pack["slices"]), pack["name"])
    print(f"  tiled {pack['id']} {info['tiles']:,} tiles {info['bytes'] / 1e6:.1f} MB", flush=True)
    return info


def maplibre_style(pack_id: str, hillshade: dict | None = None) -> dict:
    """Blackout void/red/silver style. Streets and names must read at walking zoom."""
    sources: dict = {
        # Streets ride as vector tiles. As one `geojson` blob the canvas had to
        # parse the entire pack before drawing anything, which both slowed the
        # open and put a ceiling on how much ground a pack could carry.
        "osm": {
            "type": "vector",
            "url": "pmtiles://osm.pmtiles",
            "attribution": OSM_CREDIT,
        },
        "contours": {"type": "geojson", "data": "contours.geojson"},
        "public-land": {"type": "geojson", "data": "layers/public_land.geojson"},
        "flood": {"type": "geojson", "data": "layers/flood.geojson"},
        "hazards": {"type": "geojson", "data": "layers/hazards.geojson"},
        "wild": {"type": "geojson", "data": "wild.geojson"},
    }
    layers: list[dict] = [
        {"id": "void", "type": "background", "paint": {"background-color": VOID_INK}},
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
                "paint": {
                    "raster-opacity": 0.16,
                    "raster-saturation": -0.65,
                    "raster-brightness-max": 0.38,
                    "raster-contrast": 0.12,
                },
            }
        )
    street = ["all", ["has", "highway"], ["!", highway_in(TRACK_HIGHWAYS)]]
    layers.extend(
        [
            {
                # What kind of empty the empty ground is. Loudest zoomed out,
                # where there is nothing else to look at, and almost gone by
                # the zoom you walk at, where the streets do the talking.
                "id": "land-fill",
                "type": "fill",
                "source": "osm",
                "paint": {
                    "fill-color": LAND_INK,
                    "fill-opacity": zoom_stops(6, 0.62, 11, 0.46, 13, 0.22, 14, 0.12),
                },
            },
            {
                "id": "public-land-fill",
                "type": "fill",
                "source": "public-land",
                "paint": {"fill-color": "#0a140a", "fill-opacity": 0.34},
            },
            {
                "id": "flood-fill",
                "type": "fill",
                "source": "flood",
                "paint": {"fill-color": "#0a1822", "fill-opacity": 0.34},
            },
            {
                "id": "water-fill",
                "type": "fill",
                "source": "osm",
                "filter": ["in", ["get", "class"], ["literal", ["body", "reservoir"]]],
                "paint": {"fill-color": WATER_FILL, "fill-opacity": 0.82},
            },
            {
                # Rivers and canals: the shape of the country, drawn from the
                # zoom where you pick a direction.
                "id": "water",
                "type": "line",
                "source": "osm",
                "filter": ["in", ["get", "class"], ["literal", ["river", "canal", "creek", "acequia", "dam"]]],
                "paint": {
                    "line-color": WATER_INK,
                    "line-width": zoom_stops(10, 0.8, 15, 2.6),
                },
            },
            {
                # A wash is a line that is dry most of the year, and a solid
                # stroke would promise water that is not there. Dashes say
                # sometimes without needing a word.
                "id": "water-ephemeral",
                "type": "line",
                "source": "osm",
                "filter": ["in", ["get", "class"], ["literal", ["wash", "drain", "channel"]]],
                "paint": {
                    "line-color": WATER_EPHEMERAL,
                    "line-width": zoom_stops(12, 0.7, 15, 2.0),
                    "line-dasharray": [2.5, 2.0],
                },
            },
            {
                # Springs, wells, tanks and taps. A ring, not a badge: it says
                # the record puts water here, not that the water is good. A
                # tank whose contents nobody recorded gets a grey ring instead
                # of the water ring, because out here it is as likely to be
                # diesel.
                "id": "water-points",
                "type": "circle",
                "source": "osm",
                "filter": [
                    "in",
                    ["get", "class"],
                    ["literal", ["spring", "well", "tank", "tank_other", "tap"]],
                ],
                "paint": {
                    "circle-color": WATER_INK,
                    "circle-radius": zoom_stops(12, 2.2, 15, 5.0),
                    "circle-stroke-color": [
                        "match", ["get", "class"],
                        "tank_other", "#5a5f66",
                        SILVER_INK,
                    ],
                    "circle-stroke-width": 1.4,
                },
            },
            {
                # The ring above is 5 points at street zoom. MapLibre's
                # visibleFeatures only returns what the style drew large enough
                # to hit, so a hold on the tank you can see came back empty.
                # This one is the size of the hold itself, inked at zero, so
                # the painted query and the thumb agree.
                "id": "water-points-hit",
                "type": "circle",
                "source": "osm",
                "filter": [
                    "in",
                    ["get", "class"],
                    ["literal", ["spring", "well", "tank", "tank_other", "tap"]],
                ],
                "paint": {
                    "circle-color": WATER_FILL,
                    # Zero opacity is treated as not drawn, so visibleFeatures
                    # skips it. One percent is enough for the query and not
                    # enough for a thumb to see a second ring.
                    "circle-opacity": 0.01,
                    "circle-radius": 22,
                    "circle-stroke-width": 0,
                },
            },
            {
                "id": "contours",
                "type": "line",
                "source": "contours",
                "paint": {"line-color": "#2a2e28", "line-width": 0.45, "line-opacity": 0.4},
            },
            {
                "id": "roads-casing",
                "type": "line",
                "source": "osm",
                "filter": street,
                "layout": {"line-cap": "round", "line-join": "round"},
                "paint": {
                    "line-color": VOID_INK,
                    "line-width": zoom_stops(10, 4.2, 13, 6.8, 15, 10.6, 17, 16.8),
                    "line-opacity": 0.96,
                },
            },
            {
                "id": "roads-arterial-casing",
                "type": "line",
                "source": "osm",
                "filter": highway_in(ARTERIAL_HIGHWAYS),
                "layout": {"line-cap": "round", "line-join": "round"},
                "paint": {
                    "line-color": ACCENT_INK,
                    "line-width": zoom_stops(10, 3.6, 13, 5.6, 15, 9.0, 17, 15.0),
                    "line-opacity": 0.92,
                },
            },
            {
                "id": "roads",
                "type": "line",
                "source": "osm",
                "filter": street,
                "layout": {"line-cap": "round", "line-join": "round"},
                "paint": {
                    "line-color": SILVER_INK,
                    "line-width": zoom_stops(10, 0.9, 13, 2.4, 15, 5.0, 17, 9.4),
                },
            },
            {
                "id": "roads-major",
                "type": "line",
                "source": "osm",
                "filter": highway_in(MAJOR_HIGHWAYS),
                "layout": {"line-cap": "round", "line-join": "round"},
                "paint": {
                    "line-color": SILVER_INK,
                    "line-width": zoom_stops(10, 1.4, 13, 3.2, 15, 6.6, 17, 12.0),
                },
            },
            {
                "id": "tracks",
                "type": "line",
                "source": "osm",
                "minzoom": 12,
                "filter": highway_in(TRACK_HIGHWAYS),
                "paint": {
                    "line-color": SILVER_INK,
                    "line-opacity": 0.72,
                    "line-width": zoom_stops(12, 0.9, 16, 2.4),
                    "line-dasharray": [2, 1.1],
                },
            },
            {
                "id": "wild-roads",
                "type": "line",
                "source": "wild",
                "filter": ["has", "highway"],
                "paint": {"line-color": SILVER_INK, "line-width": 2.6},
            },
            {
                "id": "hazards",
                "type": "line",
                "source": "hazards",
                "paint": {"line-color": ACCENT_INK, "line-width": 1.4},
            },
            {
                "id": "osm-points",
                "type": "circle",
                "source": "osm",
                "filter": ["==", ["geometry-type"], "Point"],
                "layout": {"visibility": "none"},
                "paint": {
                    "circle-color": SILVER_INK,
                    "circle-radius": 2.4,
                    "circle-stroke-color": VOID_INK,
                    "circle-stroke-width": 0.8,
                },
            },
            {
                # Named water, in the water's own colour so it never reads as
                # a street. Only named records: printing "Unnamed" across a
                # wash would be the map talking to itself.
                "id": "water-labels",
                "type": "symbol",
                "source": "osm",
                "minzoom": 12,
                "filter": ["all", ["has", "name"], ["has", "class"]],
                "layout": {
                    "text-field": ["get", "name"],
                    "symbol-placement": "line",
                    "symbol-spacing": 240,
                    "text-size": zoom_stops(12, 11, 15, 14, 18, 17),
                    "text-font": [GLYPH_STACK],
                    "text-max-angle": 40,
                    "text-padding": 2,
                    "text-optional": True,
                    "text-keep-upright": True,
                },
                "paint": {
                    "text-color": "#7fa6b8",
                    "text-halo-color": VOID_INK,
                    "text-halo-width": 2.0,
                    "text-halo-blur": 0.15,
                },
            },
            {
                "id": "road-labels",
                "type": "symbol",
                "source": "osm",
                "minzoom": 12,
                "filter": ["all", ["has", "highway"], ["has", "name"]],
                "layout": {
                    "text-field": ["get", "name"],
                    "symbol-placement": "line",
                    "symbol-spacing": 100,
                    "text-size": zoom_stops(12, 12, 14, 15, 16, 19, 18, 22),
                    "text-font": [GLYPH_STACK],
                    "text-max-angle": 40,
                    "text-padding": 2,
                    "text-letter-spacing": 0.03,
                    "text-optional": True,
                    "text-keep-upright": True,
                    "symbol-sort-key": [
                        "match",
                        ["get", "highway"],
                        ["motorway", "trunk", "primary"],
                        1,
                        ["secondary", "tertiary"],
                        2,
                        3,
                    ],
                },
                "paint": {
                    "text-color": SILVER_INK,
                    "text-halo-color": VOID_INK,
                    "text-halo-width": 2.2,
                    "text-halo-blur": 0.15,
                },
            },
            {
                "id": "road-refs",
                "type": "symbol",
                "source": "osm",
                "minzoom": 11,
                "filter": ["all", ["has", "highway"], ["has", "ref"]],
                "layout": {
                    "text-field": ["get", "ref"],
                    "symbol-placement": "line",
                    "symbol-spacing": 300,
                    "text-size": zoom_stops(11, 15, 14, 18, 16, 21, 17, 23),
                    "text-font": [GLYPH_STACK],
                    "text-max-angle": 28,
                    "text-padding": 1,
                    "text-letter-spacing": 0.06,
                    "text-optional": True,
                    "text-keep-upright": True,
                    "symbol-sort-key": 0,
                },
                "paint": {
                    "text-color": SILVER_INK,
                    "text-halo-color": VOID_INK,
                    "text-halo-width": 2.0,
                    "text-halo-blur": 0.05,
                },
            },
            {
                "id": "place-labels",
                "type": "symbol",
                "source": "osm",
                "minzoom": 10,
                # Town names stop stealing collision slots from street names once the
                # walker is inside the block.
                "maxzoom": 16,
                "filter": ["has", "place"],
                "layout": {
                    "text-field": ["get", "name"],
                    "text-size": zoom_stops(10, 13, 14, 18),
                    "text-font": [GLYPH_STACK],
                    "text-anchor": "top",
                    "text-optional": True,
                    "text-letter-spacing": 0.04,
                },
                "paint": {
                    "text-color": SILVER_INK,
                    "text-halo-color": VOID_INK,
                    "text-halo-width": 2.0,
                },
            },
        ]
    )
    stamp_source_layers(layers)
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
            "palette": "blackout-void-red-silver",
            "tokens": {"void": VOID_INK, "accent": ACCENT_INK, "silver": SILVER_INK},
        },
    }


# Which slice of the tile archive each style layer reads. A vector source is
# addressed by layer, unlike the single undifferentiated blob it replaced, so
# every layer drawing from `osm` has to name where it looks.
OSM_SOURCE_LAYER = {
    "land-fill": "land",
    "water-fill": "water",
    "water": "water",
    "water-ephemeral": "water",
    "water-points": "water",
    "water-points-hit": "water",
    "water-labels": "water",
    "roads-casing": "road",
    "roads-arterial-casing": "road",
    "roads": "road",
    "roads-major": "road",
    "tracks": "road",
    "osm-points": "place",
    "road-labels": "road",
    "road-refs": "road",
    "place-labels": "place",
}


def stamp_source_layers(layers: list[dict]) -> None:
    """Point every `osm` layer at its slice, and refuse to guess for new ones."""
    for layer in layers:
        if layer.get("source") != "osm":
            continue
        known = OSM_SOURCE_LAYER.get(layer["id"])
        if known is None:
            raise SystemExit(
                f"style layer {layer['id']!r} reads the tile source but no source-layer "
                "is declared for it; add one to OSM_SOURCE_LAYER or it draws nothing"
            )
        layer["source-layer"] = known


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


def home_point(slices: dict, bb: dict) -> dict:
    """Where the canvas opens when there is no GPS fix.

    The bbox midpoint is often terrain: TX WEST's is the Franklin Mountains
    crest, NM's is the Sandia foothills, TX EAST's is farmland east of Austin.
    Opening there at walking zoom shows a near-empty canvas, so prefer the
    metro slice — the part of the pack with the street grid on it.
    """
    metro = slices.get("metro") or {}
    # PACKS holds slice bounds flat; a written manifest nests them under "bbox".
    metro = metro.get("bbox") or metro
    box = metro if {"south", "west", "north", "east"} <= set(metro) else bb
    return {
        "lat": (box["south"] + box["north"]) / 2,
        "lon": (box["west"] + box["east"]) / 2,
    }


def union_bbox(slices: dict) -> dict:
    return {
        "south": min(s["south"] for s in slices.values()),
        "west": min(s["west"] for s in slices.values()),
        "north": max(s["north"] for s in slices.values()),
        "east": max(s["east"] for s in slices.values()),
    }


def pack_stats(fc: dict, graph: dict) -> dict:
    # Count the graph the phone loads, not the one we built in memory. Packing
    # folds exact duplicate records (same pair, same length, same modes) into
    # one, so the shipped edge count runs a little under the raw one.
    shipped = unpack_graph(pack_graph(graph))
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
        "graphEdges": len(shipped.get("edges") or []),
        "graphNodes": len(shipped.get("nodes") or {}),
        "streetsVisibleAtWalkingZoom": len(named) >= 50 and len(hwy) >= 200,
    }


def write_catalog(root: Path) -> None:
    packs = []
    order = [PRIMARY_PACK_ID] + [pid for pid in PACKS if pid != PRIMARY_PACK_ID]
    for pid in order:
        man = root / pid / "manifest.json"
        if man.is_file():
            packs.append(json.loads(man.read_text()))
    states: list[str] = []
    for pack in packs:
        state = pack.get("state")
        if state and state not in states:
            states.append(state)
    write_json(
        root / "catalog.json",
        {
            "schema": "blackout-packs-v3",
            "states": states,
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

    fc = osm_to_geojson(merged)
    graph = build_graph(merged)
    stamp_fetch(dest)
    write_compact(dest / "osm.geojson", fc)
    write_graph_binary(dest / "graph.bin", graph)
    build_tiles(dest, pack)

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
    ground.build(dest)

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
    terrain_note = (
        "USGS 3DEP hillshade bundled; contours from build-time Open-Meteo DEM."
        if hillshade_meta.get("present")
        else f"3DEP omitted ({hillshade_meta.get('reason')}); contours from build-time Open-Meteo DEM (real elevations, not fake)."
    )
    manifest = write_manifest(
        dest,
        {
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
            "center": {"lat": (bb["south"] + bb["north"]) / 2, "lon": (bb["west"] + bb["east"]) / 2},
            "home": home_point(pack["slices"], bb),
            "osmFetched": osm_fetched(dest),
            "attribution": f"{OSM_CREDIT}. {terrain_note} No runtime uplink.",
            "terrain": hillshade_meta,
            "stats": stats,
        },
    )
    print(
        f"  packed {pack['id']} {manifest['bytes']} bytes streets={stats['namedStreets']} "
        f"hwy={stats['highwayLines']} edges={stats['graphEdges']} "
        f"walking={stats['streetsVisibleAtWalkingZoom']}",
        flush=True,
    )
    print(f"  sample streets: {stats['sampleStreetNames']}", flush=True)
    return manifest


def feature_key(f: dict) -> str:
    """A feature's identity for merge purposes.

    `osm_to_geojson` drops the OSM element id, so two passes over the same
    ground have to be reconciled on what they draw instead. Shape plus tags is
    exact enough: two records with the same geometry and the same tags are the
    same record however many tiles returned it.
    """
    props = json.dumps(f.get("properties") or {}, sort_keys=True, separators=(",", ":"))
    geom = json.dumps(f.get("geometry") or {}, sort_keys=True, separators=(",", ":"))
    return hashlib.sha1(f"{props}|{geom}".encode()).hexdigest()


def grow_resources(dest: Path, pack: dict, span: float = 0.5) -> dict:
    """Add the water and land-cover records to a pack already on disk.

    Purely additive. Nothing is removed and no street is touched, so the graph
    the router walks comes out of this byte-identical — which is the check that
    proves the El Paso map still works.
    """
    fc = json.loads((dest / "osm.geojson").read_text())
    before = len(fc["features"])
    have = {feature_key(f) for f in fc["features"]}

    bb = union_bbox(pack["slices"])
    # Resource records are sparse next to streets, so these tiles can be four
    # times the width the street pass needs and still answer in a couple of
    # seconds.
    tiles = tile_bbox(bb, max_span=span)
    print(f"  resources {pack['id']} tiles={len(tiles)}", flush=True)
    parts = []
    for i, tile in enumerate(tiles, 1):
        print(f"  tile {i}/{len(tiles)} {tile}", flush=True)
        parts.append(overpass_resources(tile["south"], tile["west"], tile["north"], tile["east"]))
        time.sleep(1.0)

    grown = osm_to_geojson(merge_osm(parts))
    added = []
    for f in grown["features"]:
        key = feature_key(f)
        if key in have:
            continue
        have.add(key)
        added.append(f)
    fc["features"].extend(added)
    stamp_fetch(dest)
    write_compact(dest / "osm.geojson", fc)
    print(f"  resources {pack['id']} {before} -> {len(fc['features'])} features (+{len(added)})", flush=True)
    return {"before": before, "added": len(added), "after": len(fc["features"])}


def grow_notable(dest: Path, pack: dict, span: float = 5.0) -> dict:
    """Add named nature-reserve relations, cave mouths, and named trees.

    Additive. Streets and the router graph stay where they are. Relations
    that the tiled street pass never asked for land here, assembled into
    polygons so a hold can name Franklin Mountains State Park instead of
    picnic woodland. Size is not a reason to skip a record.
    """
    fc = json.loads((dest / "osm.geojson").read_text())
    before = len(fc["features"])
    have = {feature_key(f) for f in fc["features"]}

    bb = union_bbox(pack["slices"])
    tiles = tile_bbox(bb, max_span=span)
    print(f"  notable {pack['id']} tiles={len(tiles)}", flush=True)
    parts = []
    for i, tile in enumerate(tiles, 1):
        print(f"  tile {i}/{len(tiles)} {tile}", flush=True)
        parts.append(
            overpass_notable(tile["south"], tile["west"], tile["north"], tile["east"])
        )
        time.sleep(1.0)

    grown = osm_to_geojson(merge_osm(parts))
    added = []
    for f in grown["features"]:
        key = feature_key(f)
        if key in have:
            continue
        have.add(key)
        added.append(f)
    fc["features"].extend(added)
    stamp_fetch(dest)
    write_compact(dest / "osm.geojson", fc)
    print(
        f"  notable {pack['id']} {before} -> {len(fc['features'])} features (+{len(added)})",
        flush=True,
    )
    return {"before": before, "added": len(added), "after": len(fc["features"])}


def finalize_existing(dest: Path) -> dict:
    """Finish a pack after OSM/DEM/3DEP files are already on disk (no re-fetch)."""
    fc = json.loads((dest / "osm.geojson").read_text())
    # The graph on disk is already what `build_graph` compacted during the
    # fetch, and compaction is not a no-op the second time: collapsing a chain
    # can leave its neighbours degree-2, so another pass finds more to collapse.
    # Measured on TX WEST it took 263,512 nodes to 251,334, then 249,254, each
    # pass quietly straightening another slice of the drawn route. So this path
    # re-encodes the graph and leaves its shape alone.
    graph = read_graph(dest / ("graph.bin" if (dest / "graph.bin").exists() else "graph.json"))
    write_graph_binary(dest / "graph.bin", graph)
    print(f"  graph nodes={len(graph['nodes'])} edges={len(graph['edges'])}", flush=True)

    pack = PACKS[dest.name]
    build_tiles(dest, pack)
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
    ground.build(dest)

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
    terrain_note = (
        "USGS 3DEP hillshade bundled; contours from build-time Open-Meteo DEM."
        if hillshade_meta.get("present")
        else f"3DEP omitted ({hillshade_meta.get('reason')}); contours from build-time Open-Meteo DEM."
    )
    manifest = write_manifest(
        dest,
        {
            "id": pack["id"],
            "name": pack["name"],
            "state": pack["state"],
            "kind": "osm-contour-extract",
            "engine": "maplibre",
            "defaultOpen": pack["id"] == PRIMARY_PACK_ID,
            "walkable": True,
            "bbox": bb,
            "slices": slice_summaries,
            "banners": pack["banners"],
            "center": {"lat": (bb["south"] + bb["north"]) / 2, "lon": (bb["west"] + bb["east"]) / 2},
            "home": home_point(pack["slices"], bb),
            "osmFetched": osm_fetched(dest),
            "attribution": f"{OSM_CREDIT}. {terrain_note} No runtime uplink.",
            "terrain": hillshade_meta,
            "stats": stats,
        },
    )
    print(
        f"  packed {pack['id']} {manifest['bytes']} bytes streets={stats['namedStreets']} "
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


def rebuild(ids: list[str] | None = None) -> None:
    """Redo tiles, style and manifest from the OSM already on disk.

    Overpass is slow and rate-limited, and most changes here are to how the
    data is cut rather than to the data. This re-runs everything downstream of
    the fetch so a style or tiling change does not cost an hour of network.
    """
    root = ROOT / "Resources" / "Packs"
    for pid in ids or list(PACKS):
        print("REBUILD", pid, flush=True)
        finalize_existing(root / pid)
    write_catalog(root)


def resources(ids: list[str] | None = None) -> None:
    """Add the water and land-cover pass to packs already on disk, then rebuild.

    Additive only. The router's graph is re-encoded from the bytes already
    there rather than rebuilt from the extract, so growing a pack this way
    cannot move a street.
    """
    root = ROOT / "Resources" / "Packs"
    for pid in ids or list(PACKS):
        print("RESOURCES", pid, flush=True)
        grow_resources(root / pid, PACKS[pid])
        finalize_existing(root / pid)
    write_catalog(root)


def notable(ids: list[str] | None = None) -> None:
    """Add named reserves, cave mouths, and named trees, then rebuild tiles.

    Additive only. The router's graph is re-encoded from the bytes already
    there rather than rebuilt from the extract, so growing a pack this way
    cannot move a street.
    """
    root = ROOT / "Resources" / "Packs"
    for pid in ids or list(PACKS):
        print("NOTABLE", pid, flush=True)
        grow_notable(root / pid, PACKS[pid])
        finalize_existing(root / pid)
    write_catalog(root)


if __name__ == "__main__":
    argv = sys.argv[1:]
    if argv and argv[0] == "--rebuild":
        rebuild(argv[1:] or None)
    elif argv and argv[0] == "--resources":
        resources(argv[1:] or None)
    elif argv and argv[0] == "--notable":
        notable(argv[1:] or None)
    else:
        main(argv or None)
