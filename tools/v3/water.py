"""Classify the water a phone can be standing next to, from the pack's own OSM.

The extract already carries every waterway and water polygon Overpass returned.
What it does not carry is *what kind of water each one is* in the words used in
West Texas and northern New Mexico — tank, acequia, tinaja, playa. Those live in
the name rather than the tag, and reading names is where this gets dangerous:

    tx-west  "Playa Lateral"        waterway=drain    an irrigation lateral
    tx-west  "Playa Drain Canal"    waterway=canal    an irrigation canal
    tx-west  "Mule Springs Creek"   waterway=stream   a creek
    tx-west  "Cañon la Tinaja"      waterway=stream   a creek in a canyon

Eighty-two features in tx-west carry "playa" in the name and none of them is a
playa. So a name may name **standing** water only, never a channel: a tank, a
tinaja, a playa and a spring all sit still, and a line that moves is whatever
its tag says. The single exception is `acequia`, because an acequia *is* a
channel and the word is the channel's own name — all 247 across the three packs
are tagged ditch, canal, drain or stream and named "Acequia Madre", "Pueblo
Acequia", "Griegos Acequia".

Two files come out, because drawing and answering want different things.

`layers/water.geojson` is what the canvas draws at close zoom: one mark per
feature for the classes a line or a fill cannot already say — spring, tank,
acequia, drain, playa, tinaja, canal. Small enough to sit in the style as a
geojson source without putting a parse back in front of the map opening.

`layers/water.bin` is what a press is measured against: every classified record
including the creeks and ponds, sampled along its length so a press in the
middle of a three-kilometre stream still finds it. As JSON that came to 13.3 MB
for tx-west and would have cost a parse of all of it to answer one press, which
is the cost tip-73 just took out of the graph. Same answer here: the arrays, in
the order the reader wants them, mapped rather than read.

No network. The input is the `osm.geojson` already in the tree, so a reviewer
can regenerate every shipped byte and diff it.
"""
from __future__ import annotations

import json
import re
import struct
import sys
from array import array
from pathlib import Path

from .common import ROOT, haversine_m

OSM_CREDIT = "© OpenStreetMap contributors"

# Coordinates at 5 decimals are ~1.1 m, the precision the packs already carry.
COORD_DP = 5

# How far apart sampled points sit along a channel or a shoreline, and the most
# any one feature may contribute. 250 m puts the worst-case nearest point 125 m
# from the press, inside the radius the card is willing to claim; the cap stops
# a single forty-kilometre river from owning the file.
SAMPLE_SPACING_M = 250.0
SAMPLE_CAP = 24

# What a class may be decided by. The card prints this, because "we read the
# tag" and "we read the name" are not the same claim.
VIA_TAGGED = "tagged"
VIA_NAMED = "named"
VIA_GENERIC = "generic"
VIA_VALUES = (VIA_TAGGED, VIA_NAMED, VIA_GENERIC)

# Every class the layer may emit. The first seven are what the close zoom draws;
# the rest are carried because a press has to be answerable when it lands on a
# creek, and because leaving them out would make "no water here" a lie.
CLASSES = (
    "spring",
    "tank",
    "acequia",
    "drain",
    "playa",
    "tinaja",
    "canal",
    "ditch",
    "stream",
    "river",
    "reservoir",
    # Standing water the extract does not say the kind of. Calling it a pond
    # would be a claim; "water" is what is actually known about it.
    "water",
    "wetland",
    "dam",
    "tap",
)
DETAIL_CLASSES = ("spring", "tank", "acequia", "drain", "playa", "tinaja", "canal")

# What the canvas shows when. Far out the fill draws alone and the water is the
# shape of the ground; the lines start where the tile archive actually begins
# carrying waterways; the class marks and then their names come in close.
# Mirrored by WaterZoom in Packages/MapLibreMap — change one, change both.
FILL_MIN_ZOOM = 0
LINE_MIN_ZOOM = 11
DETAIL_MIN_ZOOM = 14
LABEL_MIN_ZOOM = 15

# The tags a decision may lean on, as a closed table so the wire can hold an
# index instead of a string and the phone can print the tag back.
TAGS = (
    "waterway=canal",
    "waterway=drain",
    "waterway=ditch",
    "waterway=stream",
    "waterway=river",
    "waterway=dam",
    "waterway=weir",
    "waterway=lock_gate",
    "waterway=dam_crest",
    "waterway=fish_pass",
    "waterway=floating_barrier",
    "waterway=rapids",
    "waterway=waterfall",
    "natural=water",
    "natural=spring",
    "natural=wetland",
    "landuse=reservoir",
    "landuse=basin",
    "landuse=reservoir_watershed",
    "amenity=drinking_water",
)
TAG_INDEX = {tag: i for i, tag in enumerate(TAGS)}
CLASS_INDEX = {name: i for i, name in enumerate(CLASSES)}
VIA_INDEX = {name: i for i, name in enumerate(VIA_VALUES)}

CHANNEL_TAGS = {
    "canal": "canal",
    "drain": "drain",
    "ditch": "ditch",
    "stream": "stream",
    "river": "river",
}
STRUCTURE_TAGS = {"dam", "weir", "lock_gate", "dam_crest", "fish_pass", "floating_barrier"}
# Moving water whose tag does not say which channel carries it.
FLOW_TAGS = {"rapids", "waterfall"}
STANDING_NATURAL = {"water", "wetland"}
STANDING_LANDUSE = {"reservoir", "basin", "reservoir_watershed"}

ACEQUIA_RX = re.compile(r"acequia", re.IGNORECASE)
TINAJA_RX = re.compile(r"tinaja|hueco", re.IGNORECASE)
PLAYA_RX = re.compile(r"playa|laguna|dry\s+lake|salt\s+flat", re.IGNORECASE)
TANK_RX = re.compile(r"\btanks?\b|\bcharco\b", re.IGNORECASE)
SPRING_RX = re.compile(r"\bspring(s)?\b|\bojo(s)?\b|\bmanantial\b", re.IGNORECASE)
# A name carrying one of these describes moving water, so it cannot make the
# feature a spring however many times it also says "Spring".
FLOWING_RX = re.compile(
    r"\bcreek\b|\bbranch\b|\briver\b|\bcanyon\b|\bca[ñn]on\b|\bdraw\b|\barroyo\b|\bwash\b|\bfork\b",
    re.IGNORECASE,
)

MAGIC = b"BLKTWTR\x01"
VERSION = 1
HEADER = struct.Struct("<8sIIII")
RECORD = struct.Struct("<BBBBIHHI")
COORD_SCALE = 10_000_000  # e7, as the graph does.


def _standing_class(name: str | None) -> str | None:
    """Which kind of standing water the name says this is, if it says at all.

    Order matters where a name carries two words: "Hueco Tanks" is the tinaja
    site it is named for rather than a stock tank, and "Spring Tank" is a stock
    tank called Spring rather than a spring.
    """
    if not name:
        return None
    if TINAJA_RX.search(name):
        return "tinaja"
    if PLAYA_RX.search(name):
        return "playa"
    if TANK_RX.search(name):
        return "tank"
    if SPRING_RX.search(name) and not FLOWING_RX.search(name):
        return "spring"
    return None


def classify(props: dict, geom_type: str) -> tuple[str, str, str] | None:
    """`(class, via, tag)` for one OSM feature, or None when it is not water.

    `tag` is the tag the decision leaned on, so the card can say what it read
    instead of asking anyone to take the answer on faith.
    """
    props = props or {}
    name = props.get("name")
    waterway = props.get("waterway")
    natural = props.get("natural")
    landuse = props.get("landuse")

    if props.get("amenity") == "drinking_water":
        return "tap", VIA_TAGGED, "amenity=drinking_water"
    if natural == "spring":
        return "spring", VIA_TAGGED, "natural=spring"

    if waterway:
        tag = f"waterway={waterway}"
        if tag not in TAG_INDEX:
            return None
        if waterway in STRUCTURE_TAGS:
            return "dam", VIA_TAGGED, tag
        if waterway in FLOW_TAGS:
            return "stream", VIA_GENERIC, tag
        channel = CHANNEL_TAGS.get(waterway)
        if channel is None:
            return None
        # The one name allowed to rename a channel, because it names the
        # channel rather than the ground the channel crosses.
        if name and ACEQUIA_RX.search(name):
            return "acequia", VIA_NAMED, tag
        return channel, VIA_TAGGED, tag

    if natural in STANDING_NATURAL:
        tag = f"natural={natural}"
    elif landuse in STANDING_LANDUSE:
        tag = f"landuse={landuse}"
    else:
        return None

    # Name evidence names standing water only; a line keeps its tag.
    if geom_type in ("Polygon", "MultiPolygon", "Point"):
        named = _standing_class(name)
        if named:
            return named, VIA_NAMED, tag
    if natural == "wetland":
        return "wetland", VIA_TAGGED, tag
    if landuse in STANDING_LANDUSE:
        return "reservoir", VIA_TAGGED, tag
    return "water", VIA_GENERIC, tag


def _lines(geom: dict) -> list[list[list[float]]]:
    """Every position run in a geometry, whatever shape it arrived as."""
    kind = geom.get("type")
    coords = geom.get("coordinates") or []
    if not coords:
        return []
    if kind == "Point":
        return [[coords]]
    if kind in ("LineString", "MultiPoint"):
        return [coords]
    if kind in ("Polygon", "MultiLineString"):
        return [ring for ring in coords if ring]
    if kind == "MultiPolygon":
        return [ring for poly in coords for ring in poly if ring]
    return []


def _sample(line: list[list[float]]) -> list[tuple[float, float]]:
    """Points spaced along one run, with the run's middle put first.

    The first point is the anchor — where a label hangs and where a record
    reports itself from — so it should be the middle of the run rather than an
    end that may be off the far side of the screen.
    """
    pts = [(p[1], p[0]) for p in line if isinstance(p, (list, tuple)) and len(p) >= 2]
    if len(pts) <= 1:
        return pts
    total = 0.0
    for a, b in zip(pts, pts[1:]):
        total += haversine_m(a[0], a[1], b[0], b[1])
    if total <= SAMPLE_SPACING_M:
        return [pts[len(pts) // 2]]
    wanted = min(SAMPLE_CAP, int(total // SAMPLE_SPACING_M) + 1)
    step = total / (wanted - 1)
    out: list[tuple[float, float]] = [pts[0]]
    walked = 0.0
    target = step
    for a, b in zip(pts, pts[1:]):
        seg = haversine_m(a[0], a[1], b[0], b[1])
        if seg <= 0:
            continue
        while walked + seg >= target and len(out) < wanted:
            t = (target - walked) / seg
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            target += step
        walked += seg
    if len(out) < wanted:
        out.append(pts[-1])
    middle = len(out) // 2
    out[0], out[middle] = out[middle], out[0]
    return out


def feature_points(geom: dict) -> list[tuple[float, float]]:
    pts: list[tuple[float, float]] = []
    for line in _lines(geom):
        pts.extend(_sample(line))
        if len(pts) >= SAMPLE_CAP:
            break
    return [(round(lat, COORD_DP), round(lon, COORD_DP)) for lat, lon in pts[:SAMPLE_CAP]]


def records(fc: dict) -> list[dict]:
    """One record per classified water feature, in the extract's own order."""
    out: list[dict] = []
    for feat in fc.get("features") or []:
        geom = feat.get("geometry") or {}
        decided = classify(feat.get("properties") or {}, geom.get("type") or "")
        if decided is None:
            continue
        pts = feature_points(geom)
        if not pts:
            continue
        cls, via, tag = decided
        out.append(
            {
                "class": cls,
                "via": via,
                "tag": tag,
                "name": (feat.get("properties") or {}).get("name") or "",
                "points": pts,
            }
        )
    return out


def class_counts(recs: list[dict]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for r in recs:
        counts[r["class"]] = counts.get(r["class"], 0) + 1
    return {k: counts[k] for k in sorted(counts)}


def render_layer(recs: list[dict]) -> dict:
    """The close-zoom marks: one point per feature, detail classes only."""
    feats = []
    for r in recs:
        if r["class"] not in DETAIL_CLASSES:
            continue
        lat, lon = r["points"][0]
        props: dict = {"class": r["class"], "via": r["via"]}
        if r["name"]:
            props["name"] = r["name"]
        feats.append(
            {
                "type": "Feature",
                "properties": props,
                "geometry": {"type": "Point", "coordinates": [lon, lat]},
            }
        )
    return {"type": "FeatureCollection", "features": feats, "attribution": OSM_CREDIT}


def _le(typecode: str, values) -> bytes:
    a = array(typecode, values)
    if struct.pack("=H", 1) != struct.pack("<H", 1):
        a.byteswap()
    return a.tobytes()


def index_bytes(recs: list[dict]) -> bytes:
    """The press index.

    Layout, little-endian, mirrored by WaterIndex in Packages/MapLibreMap.
    Change one, change both.

        0   8   magic "BLKTWTR\\x01"
        8   4   uint32  version
        12  4   uint32  recordCount
        16  4   uint32  pointCount
        20  4   uint32  nameBytes
        24  16R records: uint8 class, uint8 via, uint8 tag, uint8 points,
                         uint32 nameAt, uint16 nameLen, uint16 pad,
                         uint32 firstPoint
            8P  int32   latE7[pointCount], lonE7[pointCount] interleaved
            N   utf8    name blob
    """
    names = bytearray()
    seen: dict[str, tuple[int, int]] = {}
    rows = bytearray()
    lats: list[int] = []
    lons: list[int] = []
    for r in recs:
        pts = r["points"]
        if not 0 < len(pts) <= SAMPLE_CAP:
            raise SystemExit(f"record {r['name']!r} has {len(pts)} points, which will not fit the wire")
        name = r["name"]
        if name:
            if name not in seen:
                blob = name.encode("utf-8")
                if len(blob) > 0xFFFF:
                    blob = blob[:0xFFFF]
                seen[name] = (len(names), len(blob))
                names += blob
            at, length = seen[name]
        else:
            at, length = 0, 0
        rows += RECORD.pack(
            CLASS_INDEX[r["class"]],
            VIA_INDEX[r["via"]],
            TAG_INDEX[r["tag"]],
            len(pts),
            at,
            length,
            0,
            len(lats),
        )
        for lat, lon in pts:
            lats.append(int(round(lat * COORD_SCALE)))
            lons.append(int(round(lon * COORD_SCALE)))

    coords: list[int] = []
    for lat, lon in zip(lats, lons):
        coords.append(lat)
        coords.append(lon)
    return (
        HEADER.pack(MAGIC, VERSION, len(recs), len(lats), len(names))
        + bytes(rows)
        + _le("i", coords)
        + bytes(names)
    )


def read_index(blob: bytes) -> list[dict]:
    """Read the press index back, for guards that want to check it."""
    magic, version, n, points, name_bytes = HEADER.unpack_from(blob, 0)
    if magic != MAGIC:
        raise SystemExit(f"not a water index ({magic!r})")
    if version != VERSION:
        raise SystemExit(f"water index is wire v{version}, this tool speaks v{VERSION}")
    want = HEADER.size + RECORD.size * n + 8 * points + name_bytes
    if len(blob) != want:
        raise SystemExit(f"water index is {len(blob)} bytes, expected {want}")
    coords_at = HEADER.size + RECORD.size * n
    names_at = coords_at + 8 * points
    out = []
    for i in range(n):
        cls, via, tag, count, at, length, _pad, first = RECORD.unpack_from(blob, HEADER.size + RECORD.size * i)
        pts = []
        for k in range(count):
            lat, lon = struct.unpack_from("<ii", blob, coords_at + 8 * (first + k))
            pts.append((lat / COORD_SCALE, lon / COORD_SCALE))
        out.append(
            {
                "class": CLASSES[cls],
                "via": VIA_VALUES[via],
                "tag": TAGS[tag],
                "name": blob[names_at + at : names_at + at + length].decode("utf-8") if length else "",
                "points": pts,
            }
        )
    return out


def write_compact(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")


def build(dest: Path) -> dict:
    """Write both water files for one pack from its own `osm.geojson`."""
    fc = json.loads((dest / "osm.geojson").read_text())
    recs = records(fc)
    write_compact(dest / "layers" / "water.geojson", render_layer(recs))
    (dest / "layers" / "water.bin").write_bytes(index_bytes(recs))
    drawn = (dest / "layers" / "water.geojson").stat().st_size
    indexed = (dest / "layers" / "water.bin").stat().st_size
    counts = class_counts(recs)
    print(
        f"  water {dest.name} {len(recs):,} records "
        f"draw {drawn / 1e6:.2f} MB index {indexed / 1e6:.2f} MB {counts}",
        flush=True,
    )
    return {"records": len(recs), "drawBytes": drawn, "indexBytes": indexed, "classes": counts}


def refresh(ids: list[str] | None = None) -> None:
    """Add the water layers to packs that already exist, and nothing else.

    `fetch_packs --rebuild` would do this too, but it also re-cuts the vector
    tiles and re-fetches the glyphs, and neither has anything to do with water.
    This touches the two water files, the style that reads them, and the byte
    counts that have to agree with what is now on disk.
    """
    # fetch_packs imports this module, so importing it back at the top would be
    # a cycle. The style is generated there and must stay generated there, so
    # the import is deferred rather than the code duplicated.
    from . import fetch_packs

    root = ROOT / "Resources" / "Packs"
    for pid in ids or list(fetch_packs.PACKS):
        dest = root / pid
        build(dest)
        manifest = json.loads((dest / "manifest.json").read_text())
        terrain = manifest.get("terrain") or {}
        fetch_packs.write_json(
            dest / "style.json",
            fetch_packs.maplibre_style(pid, terrain if terrain.get("present") else None),
        )
        fetch_packs.write_manifest(dest, manifest)
        print(f"  packed {pid} {manifest['bytes']} bytes", flush=True)
    fetch_packs.write_catalog(root)


def main(ids: list[str] | None = None) -> None:
    root = ROOT / "Resources" / "Packs"
    for pid in ids or ["tx-west", "tx-east", "nm"]:
        build(root / pid)


if __name__ == "__main__":
    argv = sys.argv[1:]
    if argv and argv[0] == "--refresh":
        refresh(argv[1:] or None)
    else:
        main(argv or None)
