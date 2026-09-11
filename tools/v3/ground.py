"""Notable plant and cave ground the tiles flatten, derived from the pack's OSM.

The extract already carries `landuse=greenhouse_horticulture` — 2 in TX WEST,
14 in TX EAST, 10 in NM. The tiler's land table did not class them, so they
never reached a fill, and holding the glasshouse answered open ground. It also
carries three cave preserves tagged as parks. Those already paint as park
fill; without a silver outline they look like picnic ground. FIELD still has
the plant book and the cave card. This file is the water-detail pattern for
those records: small enough to sit in the style as a geojson source, tags
intact so a hold names the record rather than a colour.

No network. The input is `osm.geojson` already in the tree. A reviewer can
regenerate every shipped byte and diff it. Animals are not drawn. Nothing
here is a meal. Bee Cave is a town park and is not in this file.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from .common import ROOT

OSM_CREDIT = "© OpenStreetMap contributors"

# Tags the hold card reads off the overlay. The card describes the record, so
# the record has to survive this extract rather than being flattened into ink.
KEEP_TAGS = ("name", "landuse", "leisure", "boundary")

# Worked plant ground the current land tiles miss. Orchard and farmland already
# paint as farm; these glasshouses do not. Recreation ground is named by the
# card already and is a park-coloured class for the next tile cut, not this
# overlay — sports fields are not glasshouses.
WORKED_LANDUSE = {"greenhouse_horticulture"}

# Phrase match, not the word "cave". Must stay in step with
# `Inspect.isCavePreserve`. Bee Cave and Cave Drive stay out.
CAVE_PRESERVE_PHRASES = ("cave preserve", "cave area of critical")
CAVE_PRESERVE_KEYS = {
    ("leisure", "park"),
    ("leisure", "nature_reserve"),
    ("boundary", "protected_area"),
    ("boundary", "national_park"),
}


def write_compact(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")


def is_cave_preserve(props: dict) -> bool:
    park = any(props.get(key) == value for key, value in CAVE_PRESERVE_KEYS)
    if not park:
        return False
    name = (props.get("name") or "").lower()
    return any(phrase in name for phrase in CAVE_PRESERVE_PHRASES)


def records(fc: dict) -> list[dict]:
    """Glasshouse and cave-preserve polygons in one pack, tags slimmed, order stable."""
    out: list[dict] = []
    for feat in fc.get("features") or []:
        props = feat.get("properties") or {}
        geom = feat.get("geometry") or {}
        if geom.get("type") not in ("Polygon", "MultiPolygon"):
            continue
        if props.get("landuse") not in WORKED_LANDUSE and not is_cave_preserve(props):
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
    glass = sum(1 for f in feats if (f["properties"].get("landuse") == "greenhouse_horticulture"))
    caves = len(feats) - glass
    print(
        f"  ground {dest.name} {glass} glasshouses {caves} cave-preserves draw {drawn} bytes",
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
