"""Notable plant, cave, and wildlife-range ground the tiles flatten, derived from the pack's OSM.

The extract already carries `landuse=greenhouse_horticulture` — 2 in TX WEST,
14 in TX EAST, 10 in NM. The tiler's land table did not class them, so they
never reached a fill, and holding the glasshouse answered open ground. It also
carries three cave preserves tagged as parks, and Blowing Sink tagged as
wetland. Those already paint as park or bosque fill; without a silver outline
they look like picnic ground or cottonwoods. FIELD still has
the plant book and the cave card. One wildlife management area in NM would
open picnic tree-use without this file. A nature preserve tagged as woodland
would open picnic tree-use without this file. A botanic garden tagged as a park
would open woodland tree-use without this file. A mountain ACEC, a prairie
preserve, a named nature reserve, or Hueco Tanks would open picnic tree-use
without this file. This is the water-detail
pattern for those records: small enough to sit in the style as a geojson
source, tags intact so a hold names the record rather than a colour.

No network. The input is `osm.geojson` already in the tree. A reviewer can
regenerate every shipped byte and diff it. Animals are not drawn. Nothing
here is a meal. Bee Cave is a town park and is not in this file. Wildlife
Drive is a street and is not in this file. Conservatory At North Austin is
apartments and is not in this file.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from .common import ROOT

OSM_CREDIT = "© OpenStreetMap contributors"

# Tags the hold card reads off the overlay. The card describes the record, so
# the record has to survive this extract rather than being flattened into ink.
KEEP_TAGS = ("name", "landuse", "leisure", "boundary", "amenity")

# Worked plant ground the current land tiles miss. Orchard and farmland already
# paint as farm; these glasshouses do not. Recreation ground is named by the
# card already and is a park-coloured class for the next tile cut, not this
# overlay — sports fields are not glasshouses.
WORKED_LANDUSE = {"greenhouse_horticulture"}

# Phrase match, not the word "cave" and not the word "sink". Must stay in
# step with `Inspect.isCavePreserve`. Bee Cave and Cave Drive stay out.
# Blowing Sink is a wetland in the extract; the word sink is not a match.
CAVE_PRESERVE_PHRASES = ("cave preserve", "cave area of critical", "blowing sink")
CAVE_PRESERVE_KEYS = {
    ("leisure", "park"),
    ("leisure", "nature_reserve"),
    ("boundary", "protected_area"),
    ("boundary", "national_park"),
}

# Phrase match, not the word "wildlife". Must stay in step with
# `Inspect.isWildlifeRange`. Wildlife Drive and Wildlife Trail stay out.
# Phrase `game commission`, not the word `game`. The Game & Fish office
# stays a park. Phrase `wilderness preserve`, not the word `wilderness`.
# Wilderness Gate is apartments and stays out. Phrase `nature preserve`
# / `nature center` / `natural area`, not the word `preserve`. Godzilla
# Preserve stays a park.
WILDLIFE_RANGE_PHRASES = (
    "wildlife refuge",
    "wildlife management area",
    "national wildlife",
    "wildlife sanctuary",
    "wildlife conservation area",
    "game commission",
    "wilderness preserve",
    "nature preserve",
    "nature center",
    "natural area",
)

# A mountain ACEC is not picnic woodland. Phrase `area of critical
# environmental concern`, not the word `critical`. Pronoun Cave is a
# hole and is matched first. Phrase `prairie preserve`, not `prairie`.
# Prairie Hills is apartments. A named nature reserve that is not
# already a hole, wildlife range, or garden is this walk. An unnamed
# reserve is not. Phrase `open space` is not a bare contains —
# Open Space Visitor Center, a farm open space, bosque along the
# Rio Grande, and a trailhead stay parks. Named open-space cover is
# this walk. Phrase `hueco tanks`, not the word `hueco`. Hueco
# Mountain Park stays a park. Hueco Tanks Road stays a road. Must
# stay in step with `Inspect.isOpenReserve`.
OPEN_RESERVE_PHRASES = (
    "area of critical environmental concern",
    "prairie preserve",
    "hueco tanks",
)
OPEN_SPACE_KEEP_OUT = ("visitor", "farm", "rio grande", "bachechi", "trail")

# Phrase match, not the word "garden" and not "arboretum". Must stay in step
# with `Inspect.isBotanicGarden`. Conservatory At North Austin is apartments
# and stays out. The Arboretum mall stays out. Cactus Point Park stays a park.
# A beer garden is a bar patio and stays a park.
BOTANIC_GARDEN_PHRASES = (
    "botanic garden",
    "botanical garden",
    "conservatory",
    "cactus garden",
    "desert garden",
    "rose garden",
    "community garden",
)


def write_compact(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")


def is_cave_preserve(props: dict) -> bool:
    name = (props.get("name") or "").lower()
    if "blowing sink" in name and not props.get("highway"):
        return True
    park = any(props.get(key) == value for key, value in CAVE_PRESERVE_KEYS)
    if not park:
        return False
    return any(phrase in name for phrase in CAVE_PRESERVE_PHRASES)


def is_wildlife_range(props: dict) -> bool:
    park = any(props.get(key) == value for key, value in CAVE_PRESERVE_KEYS)
    if not park:
        return False
    name = (props.get("name") or "").lower()
    return any(phrase in name for phrase in WILDLIFE_RANGE_PHRASES)


def is_botanic_garden(props: dict) -> bool:
    amenity = (props.get("amenity") or "").lower()
    if amenity in ("community_garden", "community garden"):
        return True
    park = any(props.get(key) == value for key, value in CAVE_PRESERVE_KEYS)
    if not park:
        return False
    name = (props.get("name") or "").lower()
    return any(phrase in name for phrase in BOTANIC_GARDEN_PHRASES)


def is_named_open_space(name: str) -> bool:
    lowered = name.lower()
    if "open space" not in lowered:
        return False
    return not any(keep in lowered for keep in OPEN_SPACE_KEEP_OUT)


def is_open_reserve(props: dict) -> bool:
    name = (props.get("name") or "").strip()
    if props.get("leisure") == "nature_reserve" and name:
        return True
    park = any(props.get(key) == value for key, value in CAVE_PRESERVE_KEYS)
    if not park:
        return False
    lowered = name.lower()
    if any(phrase in lowered for phrase in OPEN_RESERVE_PHRASES):
        return True
    return is_named_open_space(name)


def overlay_kind(props: dict) -> str | None:
    if props.get("landuse") in WORKED_LANDUSE:
        return "glasshouse"
    if is_cave_preserve(props):
        return "cave"
    if is_wildlife_range(props):
        return "wildlife"
    if is_open_reserve(props):
        return "reserve"
    if is_botanic_garden(props):
        return "botanic"
    return None


def records(fc: dict) -> list[dict]:
    """Glasshouse, cave-preserve, wildlife-range, open-reserve, and botanic-garden polygons, tags slimmed, order stable."""
    out: list[dict] = []
    for feat in fc.get("features") or []:
        props = feat.get("properties") or {}
        geom = feat.get("geometry") or {}
        if geom.get("type") not in ("Polygon", "MultiPolygon"):
            continue
        if overlay_kind(props) is None:
            continue
        keep = {k: props[k] for k in KEEP_TAGS if props.get(k)}
        out.append({"type": "Feature", "properties": keep, "geometry": geom})
    out.sort(
        key=lambda f: (
            (f["properties"].get("name") or ""),
            json.dumps(f["geometry"], sort_keys=True, separators=(",", ":")),
        )
    )
    return out


def render_layer(feats: list[dict]) -> dict:
    return {
        "type": "FeatureCollection",
        "features": feats,
        "attribution": OSM_CREDIT,
    }


def build(dest: Path) -> dict:
    """Write `layers/ground.geojson` for one pack from its own `osm.geojson`."""
    fc = json.loads((dest / "osm.geojson").read_text())
    feats = records(fc)
    write_compact(dest / "layers" / "ground.geojson", render_layer(feats))
    drawn = (dest / "layers" / "ground.geojson").stat().st_size
    kinds = [overlay_kind(f["properties"]) for f in feats]
    glass = kinds.count("glasshouse")
    caves = kinds.count("cave")
    wildlife = kinds.count("wildlife")
    botanic = kinds.count("botanic")
    reserve = kinds.count("reserve")
    print(
        f"  ground {dest.name} {glass} glasshouses {caves} cave-preserves {wildlife} wildlife-range {botanic} botanic {reserve} open-reserve draw {drawn} bytes",
        flush=True,
    )
    return {"records": len(feats), "drawBytes": drawn}


def refresh(ids: list[str] | None = None) -> None:
    """Add the ground overlay to packs that already exist, and recount the ship.

    `fetch_packs --rebuild` would do this too, but it also re-cuts the vector
    tiles. This touches the one overlay file and the byte counts that have to
    agree with what is now on disk.
    """
    from . import fetch_packs

    root = ROOT / "Resources" / "Packs"
    for pid in ids or list(fetch_packs.PACKS):
        dest = root / pid
        build(dest)
        fetch_packs.write_manifest(dest)
        print(f"  packed {pid}", flush=True)
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
