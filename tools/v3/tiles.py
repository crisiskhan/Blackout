"""Turn a pack's street GeoJSON into one PMTiles archive of vector tiles.

The canvas used to hold the whole pack in a `geojson` source, so opening TX WEST
meant MapLibre parsing 40 MB of text before it drew a line, and the pack could
never grow past what a phone would sit still for. Vector tiles cost the reader
only the few tiles under the viewport, so the archive can carry far more ground
than the old file and still open faster.

PMTiles rather than a directory of `.pbf`: the vendored MapLibre links a whole
PMTiles reader (`PMTilesFileSource`, `pmtiles://`), and one addressable file per
pack beats nine thousand loose ones in a bundle and in git.
"""

from __future__ import annotations

import gzip
import json
import math
from pathlib import Path

import mapbox_vector_tile
from pmtiles.tile import Compression, TileType, zxy_to_tileid
from pmtiles.writer import Writer
from shapely.geometry import box, shape
from shapely.ops import unary_union
from shapely.strtree import STRtree
from shapely.validation import make_valid

# How many dimensions a shape covers, so a repaired polygon is not allowed to
# come back as the stray line where its ring crossed itself.
DIMENSION = {"Polygon": 2, "MultiPolygon": 2, "LineString": 1, "MultiLineString": 1, "Point": 0, "MultiPoint": 0}

EXTENT = 4096
# Slop around each tile so a street crossing the seam still joins up instead of
# stopping dead at the edge.
BUFFER = 64

MIN_ZOOM = 6
MAX_ZOOM = 14

# What a zoom is allowed to carry. Drawing every driveway at z10 costs bytes
# nobody can see and time everybody feels.
ROAD_ZOOM = (
    # Starts at the archive floor so zooming out to see the whole pack still
    # shows the interstates rather than an empty screen.
    (MIN_ZOOM, {"motorway", "motorway_link", "trunk", "trunk_link"}),
    (10, {"primary", "primary_link"}),
    (11, {"secondary", "secondary_link"}),
    (12, {"tertiary", "tertiary_link"}),
    # Tracks come in early despite being 13% of all geometry: they are rural, so
    # they land in tiles that hold almost nothing else, and they are the only
    # thing drawn out where someone on foot most needs a line to follow.
    (12, {"track"}),
    (13, {"residential", "unclassified", "living_street"}),
    (13, {"path", "footway", "cycleway", "bridleway", "pedestrian", "steps"}),
    # Driveways and parking aisles are a third of the whole pack and read as
    # noise anywhere above the block you are standing on.
    (14, {"service"}),
)
PLACE_ZOOM = (
    (MIN_ZOOM, {"city", "town"}),
    (12, {"village", "hamlet", "suburb"}),
    (13, {"neighbourhood", "quarter"}),
)
# Anything with one of these keys is a point of interest rather than a place.
POI_ZOOM = 13
WATER_ZOOM = 9
WATERWAY_ZOOM = 11

# Ground cover, drawn as a quiet fill under everything else so the empty parts
# of the pack say what kind of empty they are. It comes in at the archive floor
# and stops before street zoom, where the streets themselves carry the map.
LAND_ZOOM = MIN_ZOOM
LAND_CLASS = {
    ("natural", "scrub"): "desert",
    ("natural", "heath"): "desert",
    ("natural", "grassland"): "desert",
    ("natural", "sand"): "playa",
    ("natural", "dune"): "playa",
    ("landuse", "salt_pond"): "playa",
    ("landuse", "basin"): "playa",
    ("natural", "bare_rock"): "mountain",
    ("natural", "scree"): "mountain",
    ("natural", "ridge"): "mountain",
    ("natural", "cliff"): "mountain",
    ("natural", "wetland"): "bosque",
    ("natural", "wood"): "woodland",
    ("landuse", "forest"): "woodland",
    ("landuse", "farmland"): "farm",
    ("landuse", "orchard"): "farm",
    ("landuse", "meadow"): "farm",
    ("landuse", "vineyard"): "farm",
    ("landuse", "greenhouse_horticulture"): "farm",
    ("landuse", "residential"): "town",
    ("landuse", "recreation_ground"): "park",
    ("landuse", "grass"): "desert",
    ("leisure", "park"): "park",
}

# When each kind of water earns its place. Rivers and canals are the shape of
# the country and belong at the zoom where you are choosing a direction; a
# stock tank or an unnamed wash is only useful once you could walk to it.
WATER_CLASS_ZOOM = {
    "river": 10,
    "canal": 10,
    "body": WATER_ZOOM,
    "reservoir": 11,
    "dam": 12,
    "spring": 12,
    "creek": 12,
    "wash": 13,
    "acequia": 13,
    "drain": 13,
    "tank": 13,
    "tank_other": 13,
    "well": 13,
    "tap": 13,
    "channel": 13,
}

# A tank is only water if the record says so. Around El Paso only 110 of 585
# storage tanks carry `content=water`; 470 say nothing at all and a few say
# fuel. Drawing all of them as water would invent a supply that is as likely
# to be diesel, so the unrecorded ones get their own class and their own ink.
WATER_CONTENT = {"water", "drinking_water", "rainwater", "wastewater", "sewage"}

# Water the style draws as a dot rather than a shape, so it has to reach the
# tile as a point.
#
# These are mapped both ways in OSM — around El Paso 302 of 583 storage tanks
# are an outline and the rest are a node — and `water-points` is a circle
# layer, which has nothing sensible to do with a ring. Between 5m and 32m
# across, every one of them is a pixel or two at the deepest zoom the archive
# holds, so the outline was never going to be worth anything on the glass. The
# centre is: it draws at every zoom and it is where a thumb lands when you hold
# the tank you can see.
WATER_POINT_CLASSES = {"spring", "well", "tank", "tank_other", "tap"}

# An unnamed pool the size of a room and an unnamed reservoir read identically
# off the tags — both are a bare `natural=water`. The outline knows the
# difference, so carry it: measured off the whole record before the tile clips
# it, or a pool that straddles a tile edge would shrink at the seam.
WATER_SPAN_CLASSES = {"body"}


def span_metres(geom) -> int:
    """The longest side of a record's bounding box, on the ground."""
    west, south, east, north = geom.bounds
    lat = math.radians((south + north) / 2.0)
    return int(round(max((east - west) * 111320.0 * math.cos(lat), (north - south) * 110540.0)))


def water_class(props: dict) -> str | None:
    """Which kind of water a record is, in the same words the card uses.

    The raw tags travel into the tile alongside this, because the hold card
    reads the record itself. This is only so the style can decide what to draw
    and at which zoom.
    """
    natural = props.get("natural")
    made = props.get("man_made")
    way = props.get("waterway")
    if natural == "spring":
        return "spring"
    if made == "water_well":
        return "well"
    if made in ("water_tank", "cistern"):
        return "tank"
    if made in ("storage_tank", "reservoir_covered"):
        content = props.get("content")
        if content in WATER_CONTENT:
            return "tank"
        return "tank_other"
    if props.get("amenity") == "drinking_water":
        return "tap"
    if way:
        if way == "river":
            return "river"
        if way == "canal":
            return "canal"
        if way == "ditch":
            return "acequia"
        if way == "drain":
            return "drain"
        if way in ("dam", "dam_crest", "weir", "lock_gate", "fish_pass"):
            return "dam"
        if way in ("stream", "wadi"):
            # An unnamed channel out here runs after rain and is dry the rest
            # of the year. That is a different thing from a creek, and holding
            # one has to say so.
            return "creek" if props.get("name") else "wash"
        return "channel"
    if props.get("landuse") in ("reservoir", "basin") or props.get("water") == "reservoir":
        return "reservoir"
    if natural == "water":
        return "body"
    return None


def land_class(props: dict) -> str | None:
    for key, value in LAND_CLASS.items():
        if props.get(key[0]) == key[1]:
            return value
    if props.get("boundary") in ("protected_area", "national_park") or props.get("leisure") == "nature_reserve":
        return "protected"
    return None


def road_min_zoom(highway: str) -> int:
    for z, kinds in ROAD_ZOOM:
        if highway in kinds:
            return z
    return MAX_ZOOM


def place_min_zoom(props: dict) -> int:
    place = props.get("place")
    if place:
        for z, kinds in PLACE_ZOOM:
            if place in kinds:
                return z
        return MAX_ZOOM
    return POI_ZOOM


def lonlat_to_tile(lon: float, lat: float, z: int) -> tuple[float, float]:
    """Web Mercator tile coordinates, y increasing southward."""
    n = 2.0**z
    x = (lon + 180.0) / 360.0 * n
    lat = max(-85.05112878, min(85.05112878, lat))
    y = (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n
    return x, y


def tile_bounds(z: int, x: int, y: int) -> tuple[float, float, float, float]:
    n = 2.0**z
    west = x / n * 360.0 - 180.0
    east = (x + 1) / n * 360.0 - 180.0
    north = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))
    south = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + 1) / n))))
    return west, south, east, north


def tile_range(bbox: dict, z: int) -> tuple[int, int, int, int]:
    x0, y1 = lonlat_to_tile(bbox["west"], bbox["south"], z)
    x1, y0 = lonlat_to_tile(bbox["east"], bbox["north"], z)
    n = int(2**z)
    clamp = lambda v: max(0, min(n - 1, int(math.floor(v))))
    return clamp(x0), clamp(y0), clamp(x1), clamp(y1)


class Layer:
    """Features of one kind, indexed so a tile can ask what falls inside it."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.geoms: list = []
        self.props: list[dict] = []
        self.minzoom: list[int] = []
        self._tree: STRtree | None = None

    def add(self, geom, props: dict, minzoom: int) -> None:
        self.geoms.append(geom)
        self.props.append(props)
        self.minzoom.append(minzoom)

    def index(self) -> None:
        self._tree = STRtree(self.geoms) if self.geoms else None

    def query(self, region, z: int) -> list[tuple[object, dict]]:
        if self._tree is None:
            return []
        out = []
        for i in self._tree.query(region):
            if self.minzoom[i] > z:
                continue
            out.append((self.geoms[i], self.props[i]))
        return out


# Tags the hold card reads off a tile. The card describes the record, so the
# record has to survive tiling rather than being flattened into a colour.
RECORD_TAGS = (
    "name",
    "natural",
    "waterway",
    "man_made",
    "water",
    "content",
    "landuse",
    "leisure",
    "boundary",
    "amenity",
    "intermittent",
)


def repair(geom):
    """Make a geometry safe to clip against a tile, or drop it.

    OSM has plenty of areas whose ring crosses itself — a field traced twice,
    a lake with a pinched neck. Shapely will index them happily and then throw
    a topology error the moment a tile tries to clip one, which killed a whole
    pack build over a single bad polygon near Austin. Repair rather than
    refuse: `make_valid` keeps the shape and fixes the ring, and only the
    parts with the same dimension as the original are kept so a broken polygon
    cannot come back as a stray line.
    """
    if geom.is_valid:
        return geom
    fixed = make_valid(geom)
    if fixed.is_empty:
        return None
    if fixed.geom_type != "GeometryCollection":
        return fixed
    wanted = DIMENSION.get(geom.geom_type)
    parts = [g for g in fixed.geoms if DIMENSION.get(g.geom_type) == wanted]
    if not parts:
        return None
    merged = unary_union(parts)
    return None if merged.is_empty else merged


def read_layers(pack: Path) -> dict[str, Layer]:
    """Split the pack's GeoJSON into the source layers the style names."""
    road = Layer("road")
    water = Layer("water")
    land = Layer("land")
    place = Layer("place")
    fc = json.loads((pack / "osm.geojson").read_text())
    for feat in fc["features"]:
        props = feat.get("properties") or {}
        try:
            geom = shape(feat["geometry"])
        except Exception:
            continue
        if geom.is_empty:
            continue
        geom = repair(geom)
        if geom is None or geom.is_empty:
            continue
        highway = props.get("highway")
        if highway:
            keep = {"highway": highway}
            for k in ("name", "ref"):
                if props.get(k):
                    keep[k] = props[k]
            road.add(geom, keep, road_min_zoom(highway))
            continue
        kind = water_class(props)
        if kind:
            keep = {k: v for k, v in props.items() if k in RECORD_TAGS}
            keep["class"] = kind
            if kind in WATER_SPAN_CLASSES and geom.geom_type in ("Polygon", "MultiPolygon"):
                keep["span_m"] = span_metres(geom)
            if kind in WATER_POINT_CLASSES and geom.geom_type != "Point":
                geom = geom.representative_point()
            water.add(geom, keep, WATER_CLASS_ZOOM.get(kind, WATERWAY_ZOOM))
            continue
        # A cave, sink, or named tree mapped as an area is still a point the
        # hold has to name. The land table has no class for a hole, and a
        # canopy ring is not woodland fill — FIELD opens cave or tree-use,
        # never a meal, never an animal pin.
        natural = props.get("natural")
        if natural in ("cave", "cave_entrance", "sinkhole", "tree"):
            if geom.geom_type != "Point":
                geom = geom.representative_point()
            keep = {
                k: v
                for k, v in props.items()
                if k in ("place", "name", "amenity", "emergency", "natural")
            }
            if keep:
                place.add(geom, keep, place_min_zoom(props))
            continue
        ground = land_class(props)
        if ground and geom.geom_type in ("Polygon", "MultiPolygon"):
            keep = {k: v for k, v in props.items() if k in RECORD_TAGS}
            keep["class"] = ground
            land.add(geom, keep, LAND_ZOOM)
            continue
        if geom.geom_type == "Point":
            keep = {
                k: v
                for k, v in props.items()
                if k in ("place", "name", "amenity", "emergency", "natural")
            }
            if keep:
                place.add(geom, keep, place_min_zoom(props))
    layers = {"land": land, "road": road, "water": water, "place": place}
    for layer in layers.values():
        layer.index()
    return layers


def encode_tile(layers: dict[str, Layer], z: int, x: int, y: int) -> bytes | None:
    west, south, east, north = tile_bounds(z, x, y)
    pad_x = (east - west) * BUFFER / EXTENT
    pad_y = (north - south) * BUFFER / EXTENT
    region = box(west - pad_x, south - pad_y, east + pad_x, north + pad_y)
    span_x = east - west
    span_y = north - south

    def to_tile(lon: float, lat: float) -> tuple[int, int]:
        # Straight linear map inside the tile. Mercator's curve over one tile is
        # far below a single unit of the 4096 grid, and staying linear keeps the
        # edges of neighbouring tiles on exactly the same seam.
        return (
            int(round((lon - west) / span_x * EXTENT)),
            int(round((north - lat) / span_y * EXTENT)),
        )

    out = []
    for name, layer in layers.items():
        found = layer.query(region, z)
        if not found:
            continue
        feats = []
        for geom, props in found:
            try:
                clipped = geom.intersection(region)
            except Exception:
                # Repaired at load, so this is rare, but one stubborn shape
                # must not cost the pack every tile it appears in.
                continue
            if clipped.is_empty:
                continue
            shifted = _to_tile_geometry(clipped, to_tile)
            if shifted is None:
                continue
            feats.append({"geometry": shifted, "properties": props})
        if feats:
            out.append({"name": name, "features": feats})
    if not out:
        return None
    blob = mapbox_vector_tile.encode(out, extents=EXTENT, y_coord_down=True, check_winding_order=False)
    # The header advertises gzip, so the tiles have to actually be gzipped or
    # the reader hands raw protobuf to the decompressor and gets nothing.
    return gzip.compress(blob, 6)


def _to_tile_geometry(geom, to_tile):
    """Rewrite a lon/lat geometry into the tile's integer grid."""
    kind = geom.geom_type
    if kind == "Point":
        return {"type": "Point", "coordinates": list(to_tile(geom.x, geom.y))}
    if kind == "MultiPoint":
        return {"type": "MultiPoint", "coordinates": [list(to_tile(p.x, p.y)) for p in geom.geoms]}
    if kind == "LineString":
        pts = _dedupe([to_tile(*c[:2]) for c in geom.coords])
        return {"type": "LineString", "coordinates": pts} if len(pts) >= 2 else None
    if kind in ("MultiLineString", "GeometryCollection"):
        parts = []
        for part in geom.geoms:
            sub = _to_tile_geometry(part, to_tile)
            if sub and sub["type"] == "LineString":
                parts.append(sub["coordinates"])
        return {"type": "MultiLineString", "coordinates": parts} if parts else None
    if kind == "Polygon":
        rings = []
        for ring in [geom.exterior, *geom.interiors]:
            pts = _dedupe([to_tile(*c[:2]) for c in ring.coords])
            if len(pts) >= 4:
                rings.append(pts)
        return {"type": "Polygon", "coordinates": rings} if rings else None
    if kind == "MultiPolygon":
        polys = []
        for part in geom.geoms:
            sub = _to_tile_geometry(part, to_tile)
            if sub:
                polys.append(sub["coordinates"])
        return {"type": "MultiPolygon", "coordinates": polys} if polys else None
    return None


def _dedupe(points: list[tuple[int, int]]) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    for p in points:
        if not out or out[-1] != p:
            out.append(p)
    return out


def build(pack: Path, bbox: dict, name: str) -> dict:
    """Write `osm.pmtiles` for one pack and report what went into it."""
    layers = read_layers(pack)
    out = pack / "osm.pmtiles"
    tiles = 0
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
                    tiles += 1
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
                "center_zoom": MAX_ZOOM - 1,
                "center_lon_e7": int((bbox["west"] + bbox["east"]) / 2 * 1e7),
                "center_lat_e7": int((bbox["south"] + bbox["north"]) / 2 * 1e7),
            },
            {
                "name": name,
                "format": "pbf",
                "attribution": "© OpenStreetMap contributors",
                "vector_layers": [
                    {"id": "land", "minzoom": LAND_ZOOM, "maxzoom": MAX_ZOOM,
                     "fields": {"class": "String", "natural": "String", "landuse": "String",
                                "leisure": "String", "boundary": "String", "name": "String"}},
                    {"id": "road", "minzoom": MIN_ZOOM, "maxzoom": MAX_ZOOM,
                     "fields": {"highway": "String", "name": "String", "ref": "String"}},
                    {"id": "water", "minzoom": WATER_ZOOM, "maxzoom": MAX_ZOOM,
                     "fields": {"class": "String", "natural": "String", "waterway": "String",
                                "man_made": "String", "amenity": "String", "name": "String"}},
                    {"id": "place", "minzoom": MIN_ZOOM, "maxzoom": MAX_ZOOM,
                     "fields": {"place": "String", "name": "String", "amenity": "String"}},
                ],
            },
        )
    return {"tiles": tiles, "bytes": out.stat().st_size}
