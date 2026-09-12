"""Notable plant, cave, and wildlife-range ground the tiles flatten, derived from the pack's OSM.

The extract already carries `landuse=greenhouse_horticulture` — 2 in TX WEST,
14 in TX EAST, 10 in NM. The tiler's land table did not class them, so they
never reached a fill, and holding the glasshouse answered open ground. It also
carries three cave preserves tagged as parks, and Blowing Sink tagged as
wetland. Those already paint as park or bosque fill; without a silver outline
they look like picnic ground or cottonwoods. FIELD still has
the plant book and the cave card. One wildlife management area in NM would
open picnic tree-use without this file. A nature preserve tagged as woodland
would open picnic tree-use without this file. A botanic garden tagged as a park or as a garden would open woodland tree-use without this file. A mountain ACEC, a prairie
preserve, a named nature reserve, Hueco Tanks, named open-space cover, a
scenic easement, La Tierra Trails, or Sun Mountain would open picnic tree-use without this file. This is the water-detail
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
# overlay — sports fields are not glasshouses. Named Vickery Wholesale
# Greenhouse is the east Hold; unnamed west glasshouse stays the west Hold.
WORKED_LANDUSE = {"greenhouse_horticulture"}

# Phrase match, not a bare contains of the word cave. Must stay in step with
# `Inspect.isCavePreserve`. Bee Cave, Coyote Cave Park, and Cave Drive
# stay out. Karst preserve is a hole. William H. Russell Karst
# Preserve is a hole, not wildlife range. Karst Lane stays a
# road. A nature reserve named for a
# cave is a hole. Blowing Sink is a wetland in the extract; the word
# sink is not a match. Overlay-sheet mouths on Buttercup / Discovery
# Well are Holdable when unique versus the overlay pip and no other
# mouth sits in the probe. Buttercup Blowhole, Cedar Elm Sink, Lime
# Creek Road Sink, and Under Three Oaks. Isolated mouths off those
# sheets: Buttercup Drain Cave and Warton Whirlpool. Overlay-sheet
# mouths also Holdable: Pat's Pit, Persimmon Well, Good Friday,
# and Jumbled Rocks. Unique versus the Buttercup overlay Hold
# (141 m). Cedar Elm Preserve Trail stays a trail. Brook Meadow
# Trail is a road. Godzilla Cave stays unheld — Link's sits 84 m
# off that mouth. Zig Zag stays unheld. Hot Springs Cave is a
# named mouth inside Jemez NRA — rank 1 still beats the overlay.
# Soda Dam is rock, not the hole. Generic Cave and the two La
# Cueva stay unheld. Do not add matcher `good friday`, `hot
# springs`, or `jumbled`.
CAVE_PRESERVE_PHRASES = (
    "cave preserve",
    "cave area of critical",
    "blowing sink",
    "karst preserve",
)
CAVE_PRESERVE_KEEP_OUT = ("bee cave", "cave park", "cave drive")
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
# / `nature center` / `natural area` / `nature area`, not the word
# `preserve`. Godzilla Preserve stays a park. Phrase `wildlife
# preserve`, not the word `wildlife`. Wildlife Drive stays a park.
# Phrase `audubon`, not a street — overlay still needs park keys.
# Phrase `habitat preserve`, not the word `habitat`. Phrase `flora y
# fauna`, not a street. Phrase `national preserve`, not the word
# `preserve`. Phrase `wilderness park`, not the word `wilderness`.
# Wilderness Gate stays apartments. Phrase `canyonlands preserve`,
# not the word `canyonlands`. Canyonlands Trail Park stays a park.
# Phrase `wetland preserve`, not the word `wetland`. Rio Bosque
# Wetlands Park stays bosque. Phrase `canyon preserve`, not the word
# `canyon`. Santa Fe Canyon Preserve is range. Canyon Preserve
# Interpretive Loop Trail stays a path. El Cerro de Los Lunas
# Preserve and Galisteo Basin Preserve stay Open reserve. Phrase
# `management unit`, not `wildlife management area`. A Balcones
# management unit is range. Waste Management Wildlife Park stays Open
# reserve. Phrase `ecological research`, not the word `research`.
# Phrase `hawk watch`, not the word `hawk`. Hawk Watch Trail stays a
# trail. Phrase `experimental range`, not the word `experimental`.
# Phrase `natural history`, not the word `history`. Sandia Mountain
# Natural History Center is range. Phrase `baker sanctuary`, not the
# word `baker`. Phrase `blair woods sanctuary`, not the word `blair`
# or `woods`. Phrase `beck preserve`, not the word `beck`. Beck
# Preserve is Travis Audubon bird sanctuary. Phrase `brodie
# wild`, not the word `brodie`. Brodie Lane stays a road.
# Brodie and Oakdale Properties stay Open reserve. Phrase
# `dahlstrom nature`, not the word `dahlstrom`. Dahlstrom
# Road stays a road. The `nature preserve` phrase already
# matches that sheet. Phrase `bernardo wildlife`, not the
# word `bernardo`. Bernardo Trails Park stays a park. Don
# Bernardo Road stays a road. The `wildlife management area`
# phrase already matches that sheet. Phrase `national
# wildlife`, not the word `valle`. Valle de Oro National
# Wildlife Refuge is range. Valle del Bosque Park stays a
# park. Phrase `stephenson nature`, not the word
# `stephenson`. The `nature preserve` phrase already
# matches that sheet. Phrase `onion creek wildlife`, not the
# word `onion`. Onion Creek Drive stays a road. Onion Creek
# Management Unit is a separate sheet. Phrase `onion creek
# management`, not the word `onion`. The `wildlife sanctuary`
# and `management unit` phrases already match those sheets.
# Phrase `mary gay maxwell`. The `management unit` phrase
# already matches that sheet. Phrase `bull creek management`,
# not the word `bull`. Bull Creek West Loop stays a trail.
# The `management unit` phrase already matches that sheet.
# Phrase `lower barton creek`, not the word `barton`.
# Barton Creek Habitat Preserve and Barton Creek Wilderness
# Park stay their own sheets. Phrase `little bear creek`.
# The `management unit` phrase already matches that sheet.
# Phrase `la joya wildlife`, not the word `joya`. The
# `wildlife management area` phrase already matches that
# sheet. Phrase `canyonlands preserve` already matches
# Grandview Hills, Blackmore, Lake Perspectives, Austin
# Simon, Lime Creek, Romberg, McGregor, and Cuevas East
# as unique titles. Cuevas interiors sit on water. TSNL
# stays unheld — Grandview is in that probe. Hippie
# Hollow Park sits on another McGregor interior. Barrow Nature Preserve
# vertex-avg sits off the sheet; the listed interior is on
# it. The `nature preserve` phrase already matches that
# sheet. Rio Rancho Bosque Nature Preserve is range, not
# bosque overlay. The `nature preserve` phrase already
# matches that sheet. Phrase `wild basin wilderness`, not
# the word `basin`. The `wilderness preserve` phrase already
# matches that sheet. Listed centroid sits on water.
# Phrase `stillhouse hollow`. The `nature preserve` phrase
# already matches that sheet. Listed centroid sits on
# water. Phrase `big walnut creek`, not the word `walnut`.
# The `nature preserve` phrase already matches that sheet.
# Listed centroid sits on Walnut Creek. Phrase `colorado
# river park wildlife`. The `wildlife sanctuary` phrase
# already matches that sheet. Listed centroid sits on the
# Colorado River. Phrase `shady hollow west`, not the word
# `shady`. Lost Oasis Hollow stays a road. Bear Creek
# Management Unit is a separate sheet. The `nature
# preserve` phrase already matches that sheet. `preserve`
# alone is still forbidden. Phrase `nature center` already
# matches Rio Grande Nature Center State Park. Listed
# centroid sits on the park ponds. Calle del Bosque
# Northwest stays a road. Phrase `game commission`, not the
# word `game`. Listed State Game Commission pip sits on
# water. Rio Grande Stables Road stays a road. Other Game
# Commission sheets stay their own. Whitfield dry interiors
# have no nearby name that is not Acequia Madre and stay
# unheld. Phrase `nature preserve` already matches Charlie
# Wakeem/Richard Teschner Nature Preserve of Resler Canyon
# and Blunn Creek Nature Preserve. Cadiz Street and East
# Oltorf Street stay roads. Do not add matcher `charlie`,
# `resler`, or `blunn`. Phrase `national wildlife` already
# matches San Andres National Wildlife Refuge and Sevilleta
# National Wildlife Refuge. Do not add matcher `san andres`
# or `sevilleta`. White Sands Missile Range S Route 287 and
# Old Highway 85 stay roads. Phrase `wildlife refuge` already
# matches Feather Lake Wildlife Refuge. Ditches sit on most
# of that sheet; this corner is 203 m from Bowman Lateral.
# Nottingham Drive stays a road. Do not add matcher `feather`.
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
    "nature area",
    "wildlife preserve",
    "audubon",
    "habitat preserve",
    "flora y fauna",
    "national preserve",
    "wilderness park",
    "canyonlands preserve",
    "wetland preserve",
    "canyon preserve",
    "management unit",
    "ecological research",
    "hawk watch",
    "experimental range",
    "natural history",
    "baker sanctuary",
    "blair woods sanctuary",
    "beck preserve",
    "brodie wild",
)

# A mountain ACEC is not picnic woodland. Phrase `area of critical
# environmental concern`, not the word `critical`. Pronoun Cave is a
# hole and is matched first. Phrase `prairie preserve`, not `prairie`.
# Prairie Hills is apartments. A named nature reserve that is not
# already a hole, wildlife range, or garden is this walk. An unnamed
# reserve is not. Phrase `open space` is not a bare contains —
# Open Space Visitor Center, a farm open space, Alameda/Rio Grande
# Open Space, and a trailhead stay parks. Named open-space cover is
# this walk. Phrase `hueco tanks`, not the word `hueco`. Hueco
# Mountain Park stays a park. Hueco Tanks Road stays a road. Phrase
# `scenic easement`, not the word `easement`. A riverside hike-and-
# bike easement stays a park. Phrase `la tierra trails`, not the
# word `tierra` or `trails`. Tierra Blanca and a trails neighborhood
# park stay parks. Phrase `sun mountain`, not the word `sun` or
# `mountain`. Hyde Memorial and Manzano stay picnic. The peak pin
# stays a peak. Sun Mountain Estates is built-up. Phrase `national
# forest`, not the word `forest`. Cibola and Santa Fe National Forest
# are timber. Lincoln National Forest stays picnic. Must stay in step
# with `Inspect.isOpenReserve`.
OPEN_RESERVE_PHRASES = (
    "area of critical environmental concern",
    "prairie preserve",
    "hueco tanks",
    "scenic easement",
    "la tierra trails",
    "sun mountain",
)
OPEN_SPACE_KEEP_OUT = ("visitor", "farm", "rio grande", "bachechi", "trail")
OPEN_RESERVE_KEEP_OUT = ("national forest",)

# Phrase match, not the word "garden" and not "arboretum". Must stay in step
# with `Inspect.isBotanicGarden`. Conservatory At North Austin is apartments
# and stays out. The Arboretum mall stays out. Cactus Point Park stays a park.
# A beer garden is a bar patio and stays a park. Phrase `wildflower
# preserve`, not the word `wildflower`. Wildflower Park stays a park.
# Phrase `wildflower center`, not the word `wildflower`. Ladybird
# Johnson Wildflower Center is a garden relation in OSM, not a ring
# faked from foot paths. Those paths stay paths. Phrase `lush n lean`,
# not the word `lush`. Phrase `orchard garden`, not the word `orchard`.
# Orchard Gardens Road stays a road. Fiesta Gardens is an event park
# and stays a park. Phrase `harvey cornell`, not `rose park`. Wildrose
# Park stays a park. Rose Park Avenue stays a road. Phrase `japaneese
# garden` is OSM's spelling in El Paso; phrase `japanese garden` is
# the correctly spelled sheet. Phrase `japanese memorial`, not
# Memorial Garden. Phrase `capitol flower`, not `flower gardens`.
# Mayfield Gardens stays out. Phrase `demonstration garden`, not the
# word `demonstration`. Phrase `preston foster`, not `native garden`
# — Native American Garden inside Santa Fe Botanical Garden stays
# nested, not a second sheet. Phrase `xeriscape garden`, not the
# word `xeriscape` — Xeriscape Park stays a park. Phrase `teaching
# garden`, not the word `teaching`. Phrase `fincher iii garden`,
# not the word `fincher`. E.R. Fincher III Garden is a community
# garden without the amenity tag. Phrase `brazos bluff`, not the
# word `brazos` — Brazos Street stays a road. Phrase `explorers
# garden`. Both are Trail Conservancy educational gardens, not a
# meal. Phrase `haozous garden`, not the word `haozous` —
# Haozous Road stays a road. Phrase `este garden`, not the word
# `este`. Celeste Drive stays a road. Alamo Community Garden is
# a separate sheet. Phrase `4th street garden`, not the word
# `4th`. West 4th Avenue stays a road. Phrase `alamogordo
# community garden`, not the word `alamogordo`. The Alamogordo
# street stays a road. The `community garden` phrase already
# matches that sheet. Phrase `albuquerque rose garden`,
# not the word `albuquerque`. Memorial Rose Garden is a
# separate sheet. The `rose garden` phrase already matches
# both. Phrase `la mesa neighborhood`, not `la mesa`.
# Paseo de la Mesa Open Space stays Open reserve. La Mesa
# Court stays a road. The `community garden` phrase already
# matches that sheet. Phrase `international district`, not
# the word `international`. The `community garden` phrase already
# matches that sheet. Phrase `bastrop community`, not the
# word `bastrop`. Bastrop Street stays a road. Bastrop
# State Park stays a park. The `community garden` phrase
# already matches that sheet. Phrase `fort dessau`, not the
# word `dessau`. Fort Dessau Road stays a road. Fort Dessau
# Amenity Center stays a park. The `community garden` phrase
# already matches that sheet. Phrase `windsor park community`,
# not the word `windsor`. Phrase `lamplight community`, not
# the word `lamplight`. Lamplight Village Avenue stays a
# road. Phrase `juan navarro`, not the word `navarro`.
# Phrase `unity park community`, not the word `unity`. Phrase
# `colorado community`, not the word `colorado`. Colorado River
# Park Wildlife Sanctuary stays wildlife. Phrase `alamo
# community`, not the word `alamo`. Alamo Street stays a road.
# Alamo Pocket Park stays a park. Phrase `barelas
# community`, not the word `barelas`. 4th Street Southwest
# stays a road. The
# `community garden` phrase already matches those sheets
# and Colonia Prisma Community Garden. Camino Rojo and
# Vuelta Colorada stay roads. Do not add matcher `prisma`
# or `colonia`. Desert Garden Park stays unheld.
# Winrock Garden is a mall
# bed and stays out.
# Schepps' Garden stays out. Experimental Gardens overlap
# glasshouses and stay out. A named garden without a botanic
# phrase is not this overlay. Memorial Garden stays out.
# `leisure=garden` is botanic-eligible with a phrase; it is not a
# cave, wildlife, or open-reserve key.
BOTANIC_GARDEN_PHRASES = (
    "botanic garden",
    "botanical garden",
    "conservatory",
    "cactus garden",
    "desert garden",
    "rose garden",
    "community garden",
    "wildflower preserve",
    "wildflower center",
    "lush n lean",
    "orchard garden",
    "harvey cornell",
    "japaneese garden",
    "japanese garden",
    "capitol flower",
    "japanese memorial",
    "demonstration garden",
    "preston foster",
    "xeriscape garden",
    "teaching garden",
    "fincher iii garden",
    "brazos bluff",
    "explorers garden",
    "haozous garden",
    "este garden",
    "4th street garden",
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
    if any(keep in name for keep in CAVE_PRESERVE_KEEP_OUT):
        return False
    if any(phrase in name for phrase in CAVE_PRESERVE_PHRASES):
        return True
    return "cave" in name


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
    name = (props.get("name") or "").lower()
    if not any(phrase in name for phrase in BOTANIC_GARDEN_PHRASES):
        return False
    if props.get("leisure") == "garden":
        return True
    park = any(props.get(key) == value for key, value in CAVE_PRESERVE_KEYS)
    return park


def is_named_open_space(name: str) -> bool:
    lowered = name.lower()
    if "open space" not in lowered:
        return False
    return not any(keep in lowered for keep in OPEN_SPACE_KEEP_OUT)


def is_open_reserve(props: dict) -> bool:
    name = (props.get("name") or "").strip()
    lowered = name.lower()
    if any(keep in lowered for keep in OPEN_RESERVE_KEEP_OUT):
        return False
    if props.get("leisure") == "nature_reserve" and name:
        return True
    park = any(props.get(key) == value for key, value in CAVE_PRESERVE_KEYS)
    if not park:
        return False
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
    if is_botanic_garden(props):
        return "botanic"
    if is_open_reserve(props):
        return "reserve"
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
