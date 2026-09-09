#!/usr/bin/env python3
"""Lock the inspect card and the water/land layer to what they may claim.

Two things are being guarded here. One is mechanical: the ground and water
records have to survive tiling, because the card reads the record rather than
a colour, and a layer that draws without its `source-layer` draws nothing at
all. The other is a promise. This is the first surface in the app that offers
an opinion about water, and the line it must not cross is telling anyone that
water is safe. The card rates the record. It never rates the drink.
"""
from __future__ import annotations

import gzip
import json
import re
import sys
from pathlib import Path

import mapbox_vector_tile
from pmtiles.reader import MmapSource, Reader

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from v3.fetch_packs import OSM_SOURCE_LAYER, PACKS, maplibre_style  # noqa: E402
from v3.tiles import (  # noqa: E402
    LAND_CLASS,
    WATER_CLASS_ZOOM,
    land_class,
    lonlat_to_tile,
    water_class,
)

# One record of every kind the tiler can class, used to check that the Swift
# reader can name all of them.
EVERY_KIND_OF_THING: tuple[dict[str, str], ...] = tuple(
    [{key: value} for key, value in LAND_CLASS]
    + [
        {"natural": "spring"},
        {"natural": "water"},
        {"man_made": "water_well"},
        {"man_made": "water_tank"},
        {"man_made": "storage_tank"},
        {"man_made": "storage_tank", "content": "water"},
        {"man_made": "cistern"},
        {"man_made": "reservoir_covered"},
        {"amenity": "drinking_water"},
        {"waterway": "river"},
        {"waterway": "canal"},
        {"waterway": "ditch"},
        {"waterway": "drain"},
        {"waterway": "stream"},
        {"waterway": "wadi"},
        {"waterway": "dam"},
        {"waterway": "weir"},
        {"landuse": "reservoir"},
        {"boundary": "protected_area"},
    ]
)

# Words that turn a record into permission. None of them belong on the card,
# in the layer names, or in the style.
DRINK_WORDS = ("potable", "drinkable", "safe to drink", "safe water", "purified", "sterile")
FOOD_WORDS = ("edible", "forage", "harvestable")
CRITTER_WORDS = ("animal-icon", "wildlife-icon", "critter")

MAP = ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap"
APP = ROOT / "Blackout"
FIELD = ROOT / "Resources" / "Field"
TOKENS = (ROOT / "Packages" / "Tokens" / "Sources" / "Tokens" / "Tokens.swift").read_text()


def fail(msg: str) -> None:
    print("FAIL", msg)
    raise SystemExit(1)


def code_only(body: str) -> str:
    """Drop `//` comments. A comment explaining a rule is not breaking it."""
    return "\n".join(l for l in body.splitlines() if not l.strip().startswith("//"))


def assert_the_card_never_sells_the_water() -> None:
    """Nothing the card can show may say a thing is safe to drink or eat."""
    for path in (MAP / "Inspect.swift", APP / "HoldCard.swift"):
        body = path.read_text()
        low = code_only(body).lower()
        for word in DRINK_WORDS + FOOD_WORDS + CRITTER_WORDS:
            if word in low:
                fail(f"{path.name} says {word!r} — the card rates the record, not the drink")
        # SURE has to be introduced as confidence in the record, in the file
        # that produces it, so nobody can quietly repurpose the number.
        whole = body.lower()
        if "confidence" not in whole or "record" not in whole:
            fail(f"{path.name} must say what SURE% is confidence in")
    print("OK   hold card claims nothing about drinking or eating")


def assert_sos_is_not_on_the_map_hold() -> None:
    """A thumb resting on a map is not a call for help."""
    for path in (MAP / "Inspect.swift", APP / "HoldCard.swift"):
        # A comment may explain the rule; code may not call it.
        if re.search(r"\bSOS\b", code_only(path.read_text())):
            fail(f"{path.name} reaches for SOS — SOS is a Comms button only")
    held = APP / "MapTab.swift"
    body = held.read_text()
    if "onMapHold" not in body:
        fail("MapTab does not wire the hold")
    if re.search(r"onMapHold.*SOS", body, re.S | re.I):
        fail("the map hold path reaches for SOS")
    # The other half of the same rule. `.isModal` is the tidy way to write a
    # card over a map and it hides everything outside its own subtree from
    # VoiceOver, tab bar included — and Comms, which is where SOS is, is on
    # the tab bar. A card must not be able to put SOS out of reach.
    if "isModal" in code_only((APP / "HoldCard.swift").read_text()):
        fail("the card traps VoiceOver, so a screen reader cannot reach Comms while it is open")
    print("OK   map hold never calls SOS, and never puts Comms out of reach")


def assert_the_credit_survives_the_card() -> None:
    """The card covers the footer, and the footer carried OSM's line.

    Capping the card at half the screen means the map keeps drawing above it,
    so the attribution has to move up there with it. Hiding the footer and
    stopping there drops the credit for as long as a card is open, and the
    older guards only check that the string is somewhere in the file.
    """
    body = (APP / "MapTab.swift").read_text()
    if "OSMCredit.line" not in body:
        fail("MapTab does not credit OpenStreetMap at all")
    if not any(
        "OSMCredit.line" in brace_body(body, match.end() - 1)
        for match in re.finditer(r"runtime\.held != nil \{", body)
    ):
        fail("the hold card hides the footer and takes the OpenStreetMap credit with it")
    print("OK   OpenStreetMap keeps its credit while the card is open")


def assert_the_card_offers_exactly_two_actions() -> None:
    """Two buttons. A third turns a glance into a menu."""
    body = (APP / "HoldCard.swift").read_text()
    buttons = re.findall(r"Button\(action:", body)
    if len(buttons) != 2:
        fail(f"hold card has {len(buttons)} actions, expected 2")
    for want in ("FIELD", "MARK"):
        if f'"{want}"' not in body:
            fail(f"hold card is missing its {want} action")
    if "holdCardMaxActions: Int = 2" not in TOKENS:
        fail("holdCardMaxActions is not 2")
    if "holdCardMaxHeightFraction: Double = 0.5" not in TOKENS:
        fail("the card is not capped at half the screen")
    print("OK   hold card offers FIELD and MARK and nothing else")


def assert_a_hold_is_not_a_pan() -> None:
    """The recogniser has to give the drag back if the thumb moves."""
    body = (MAP / "OfflineMapView.swift").read_text()
    if "UILongPressGestureRecognizer" not in body:
        fail("no long press on the map")
    if "allowableMovement" not in body:
        fail("the hold never fails on drift, so a pan would raise a card")
    if "tap.require(toFail: hold)" not in body:
        fail("a tap inside a hold would still move the destination")
    inspect = (MAP / "Inspect.swift").read_text()
    if "holdSeconds = 0.4" not in inspect:
        fail("the hold is not 0.4s")
    if "liftIntoView" not in body:
        fail("a hold low on the canvas would open the card over its own pin")
    # MapLibreMap cannot import Tokens, so the two halves of "the pin stays
    # visible" are only tied together here: the card owns the bottom half, and
    # a point below that gets lifted clear of it.
    cap = float(number(TOKENS, "holdCardMaxHeightFraction"))
    below = float(number(inspect, "holdLiftBelow"))
    lift = float(number(inspect, "holdLiftTo"))
    if below > 1 - cap:
        fail(f"the card covers the bottom {cap:.0%} but holds are only lifted below {below:.0%}")
    if not 0 < lift < below:
        fail(f"a hold at {below:.0%} would be lifted to {lift:.0%}, which is not above it")
    # The lift measures the canvas, so the cap has to as well. Half an 852pt
    # screen is most of a 529pt map, so a screen-sized card lands back on top
    # of the pin the camera just moved out from under it.
    card = (APP / "HoldCard.swift").read_text()
    if "UIScreen" in card:
        fail("the card is capped against the screen, not the canvas the pin is in")
    if "GeometryReader" not in card:
        fail("the card never measures the canvas it is capped against")
    print(f"OK   a thumb that moves pans the map, and one below {below:.0%} is lifted to {lift:.0%}")


def number(body: str, name: str) -> str:
    found = re.search(rf"{name}(?::\s*Double)?\s*=\s*([0-9.]+)", body)
    if not found:
        fail(f"cannot find {name}")
    return found.group(1)


def assert_style_draws_ground_and_water(pack_id: str) -> None:
    style = maplibre_style(pack_id, None)
    layers = {l["id"]: l for l in style["layers"]}
    for want in ("land-fill", "water-fill", "water", "water-ephemeral", "water-points", "water-labels"):
        if want not in layers:
            fail(f"{pack_id} style is missing {want}")
    for layer in style["layers"]:
        if layer.get("source") != "osm":
            continue
        if not layer.get("source-layer"):
            fail(f"{pack_id} layer {layer['id']} reads the tiles but names no slice — it draws nothing")
        if layer["source-layer"] != OSM_SOURCE_LAYER[layer["id"]]:
            fail(f"{pack_id} layer {layer['id']} points at the wrong slice")

    # Ground cover is a hint at the zoom where there is nothing else, and is
    # nearly gone by the zoom where streets carry the map.
    stops = layers["land-fill"]["paint"]["fill-opacity"][3:]
    far, close = stops[1], stops[-1]
    if not far > close:
        fail(f"{pack_id} land fill does not quieten as you zoom in ({far} -> {close})")
    if close > 0.2:
        fail(f"{pack_id} land fill is still {close} at street zoom — it will fight the streets")

    # A wash is dry most of the year. A solid line would promise otherwise.
    if "line-dasharray" not in layers["water-ephemeral"]["paint"]:
        fail(f"{pack_id} draws washes as solid water")
    print(f"OK   {pack_id} style draws ground and water at their own zooms")


def assert_the_record_survives_tiling(pack_id: str) -> None:
    """The card reads tags out of the tile, so the tags have to be in there."""
    pack = ROOT / "Resources" / "Packs" / pack_id
    manifest = json.loads((pack / "manifest.json").read_text())
    home = manifest["home"]
    found_water: dict[str, int] = {}
    found_land: dict[str, int] = {}
    with open(pack / "osm.pmtiles", "rb") as fh:
        reader = Reader(MmapSource(fh))
        for z, span in ((14, 3), (11, 2), (8, 1)):
            cx, cy = lonlat_to_tile(home["lon"], home["lat"], z)
            for dx in range(-span, span + 1):
                for dy in range(-span, span + 1):
                    blob = reader.get(z, int(cx) + dx, int(cy) + dy)
                    if not blob:
                        continue
                    tile = mapbox_vector_tile.decode(gzip.decompress(blob))
                    for name, bucket in (("water", found_water), ("land", found_land)):
                        for feature in tile.get(name, {}).get("features", []):
                            kind = feature["properties"].get("class")
                            if not kind:
                                fail(f"{pack_id} {name} feature has no class: {feature['properties']}")
                            bucket[kind] = bucket.get(kind, 0) + 1
    if not found_water:
        fail(f"{pack_id} draws no water anywhere near home")
    if not found_land:
        fail(f"{pack_id} draws no ground cover anywhere near home")
    for kind in found_water:
        if kind not in WATER_CLASS_ZOOM:
            fail(f"{pack_id} tiles a water class the style does not know: {kind}")
    known_land = set(LAND_CLASS.values()) | {"protected"}
    for kind in found_land:
        if kind not in known_land:
            fail(f"{pack_id} tiles a land class the style does not know: {kind}")
    print(f"OK   {pack_id} water={dict(sorted(found_water.items()))} land={dict(sorted(found_land.items()))}")


def swift_branches_on(swift: str) -> set[tuple[str, str]]:
    """The `(tag, value)` pairs `Inspect.swift` actually tests for.

    Reading the file for a bare `"residential"` is not enough: the word is in
    the list of paved highway kinds, so a search finds it while the land
    reader walks straight past `landuse=residential` into Open ground. That is
    the exact miss this catches, so it has to read the branches.
    """
    pairs: set[tuple[str, str]] = set()
    for key, value in re.findall(r't\["(\w+)"\]\s*==\s*"([\w:]+)"', swift):
        pairs.add((key, value))

    def cases_in(block: str, key: str) -> None:
        for case in re.findall(r"case ([^:\n]+):", block):
            for literal in re.findall(r'"([\w:]+)"', case):
                pairs.add((key, literal))

    # `switch t["content"] { ... }`, and the bound form the tag switches use:
    # `if let made = t["man_made"] { switch made { ... } }`.
    for match in re.finditer(r'switch t\["(\w+)"\]\s*\{', swift):
        cases_in(brace_body(swift, match.end() - 1), match.group(1))
    for match in re.finditer(r'if let (\w+) = t\["(\w+)"\]', swift):
        bound, key = match.group(1), match.group(2)
        rest = swift[match.end():]
        opened = re.search(r"switch " + re.escape(bound) + r"\s*\{", rest)
        if opened:
            cases_in(brace_body(rest, opened.end() - 1), key)
    return pairs


def brace_body(text: str, open_brace: int) -> str:
    """The text between `text[open_brace]` and the `}` that closes it."""
    depth = 0
    for i in range(open_brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace + 1:i]
    return text[open_brace + 1:]


def assert_the_tiler_and_the_card_know_the_same_words() -> None:
    """Anything the tiler draws, the card has to be able to name.

    These live in two languages and drift silently: the tiler starts shipping
    `landuse=residential` as town-coloured ground, the card never learns the
    tag, and holding the whole of El Paso answers "nothing is mapped at this
    point". So every record the tiler gives a class to has to be a record the
    card branches on.
    """
    swift = (MAP / "Inspect.swift").read_text()
    branches = swift_branches_on(swift)
    missing = []
    for tags in EVERY_KIND_OF_THING:
        if (water_class(tags) or land_class(tags)) is None:
            fail(f"the tiler classes nothing for {tags}")
        if not any((key, value) in branches for key, value in tags.items()):
            missing.append(tags)
    if missing:
        fail(f"the tiler draws these and the card reads straight past them: {missing}")
    classed = {water_class(t) or land_class(t) for t in EVERY_KIND_OF_THING}
    print(f"OK   card branches on every one of the {len(classed)} classes the tiler draws")


def swift_constants() -> dict[tuple[str, str], str]:
    """`Type.name` -> the string it is declared as, across the map sources."""
    found: dict[tuple[str, str], str] = {}
    for path in MAP.glob("*.swift"):
        body = path.read_text()
        for match in re.finditer(r"\benum (\w+)\s*[:{]", body):
            opened = body.find("{", match.end() - 1)
            for name, value in re.findall(
                r'static let (\w+)(?::\s*\w+)? = "([^"]+)"', brace_body(body, opened)
            ):
                found[(match.group(1), name)] = value
    return found


def assert_a_hold_reads_the_pack_and_not_the_apps_own_ink() -> None:
    """The probe has to skip every layer the app draws for itself.

    A hold asks MapLibre what is under the thumb and gets back whatever the
    style drew there, which includes the route line, the puck and the two
    pins. None of those is a record — they are the app talking to itself — and
    a pin the card reads as a feature would come back as "Open ground" laid
    over the spring the thumb was actually on. The skip list is written out by
    hand, so a layer added later is in the answer until somebody remembers it.
    """
    names = swift_constants()

    def resolve(expr: str) -> str:
        expr = expr.strip()
        if expr.startswith('"'):
            return expr.strip('"')
        owner, _, name = expr.partition(".")
        if (owner, name) not in names:
            fail(f"cannot resolve the layer id {expr}")
        return names[(owner, name)]

    swift = (MAP / "Inspect.swift").read_text()
    opener = "overlayLayerIDs: Set<String> = ["
    skips = swift[swift.index(opener) + len(opener):]
    skips = skips[:skips.index("]")]
    listed = {resolve(part) for part in skips.split(",") if part.strip()}
    drawn = {
        resolve(expr)
        for path in MAP.glob("*.swift")
        for expr in re.findall(r"MLN\w*StyleLayer\(identifier: ([^,]+),", path.read_text())
    }
    if not drawn:
        fail("no style layers found at all — the scan is looking in the wrong place")
    if drawn - listed:
        fail(f"the app draws {sorted(drawn - listed)} and a hold would read them as records")
    if listed - drawn:
        fail(f"the skip list names {sorted(listed - drawn)}, which nothing draws")
    print(f"OK   a hold looks through all {len(drawn)} layers the app draws for itself")


def assert_every_field_card_the_map_can_open_is_really_shipped() -> None:
    """FIELD has to land on a card, and the id at the end of the list has to
    be one every state ships.

    The hold card asks for the state's own card first — Texas wrote a heat
    island card, New Mexico wrote one about ice on rock — and the state book
    holding it is often not the one that is loaded, so falling through is the
    normal case rather than a fault. That makes the last id on the list the
    only one that has to be there, and it has to be in `field.core.json`. Both
    halves are ids written out by hand in Swift against a corpus in JSON, so a
    rename on either side is silent: FIELD switches the tab and shows the list.
    """
    swift = (MAP / "Inspect.swift").read_text()
    ids = dict(re.findall(r'static let (\w+Card) = "([\w-]+)"', swift))
    if not ids:
        fail("Inspect names no Field cards at all")

    books = {path.stem.split(".")[-1]: json.loads(path.read_text()) for path in FIELD.glob("field.*.json")}
    shipped = {name: {card["id"] for card in book["cards"]} for name, book in books.items()}
    if "core" not in shipped:
        fail("no core Field book to fall back to")
    everywhere = shipped["core"]
    states = set().union(*(cards for name, cards in shipped.items() if name != "core"))

    def named(block: str) -> list[str]:
        return [ids[word] for word in re.findall(r"\w+Card", block) if word in ids]

    fallbacks = named(" ".join(re.findall(r"field: (\w+Card)", swift)))
    if not fallbacks:
        fail("no reading falls back to a core card")
    for card in fallbacks:
        if card not in everywhere:
            fail(f"a hold falls back to {card}, which field.core.json does not ship")

    preferred = named(" ".join(re.findall(r"local\s*[:=]\s*\[([^\]]*)\]", swift)))
    if not preferred:
        fail("no ground prefers its own state's card — the biome route is gone")
    for card in preferred:
        if card in everywhere:
            fail(f"{card} is core, so preferring it over a core card does nothing")
        if card not in states:
            fail(f"a hold prefers {card}, which no state book ships")

    # The runtime has to hand over the whole route, and the tab has to walk it
    # rather than take the head. Either half alone loses the fallback, and it
    # only shows up in the state that does not ship the preferred card.
    if not re.search(r"var fieldJump: \[String\]\?", (APP / "AppRuntime.swift").read_text()):
        fail("the hold card hands FIELD one id, so a card the loaded book lacks has nothing behind it")
    tab = (APP / "FieldTab.swift").read_text()
    jump = brace_body(tab, tab.index("private func jump()"))
    if "runtime.fieldJump" not in jump:
        fail("FieldTab never reads the hold card's request")
    if not re.search(r"for \w+ in route\b", jump):
        fail("FieldTab does not walk the route, so a state card that is not loaded opens nothing")
    print(f"OK   {len(set(fallbacks))} core Field cards behind {len(set(preferred))} state ones, all shipped")


def assert_the_pack_says_when_it_was_pulled(pack_id: str) -> None:
    manifest = json.loads((ROOT / "Resources" / "Packs" / pack_id / "manifest.json").read_text())
    when = manifest.get("osmFetched")
    if not when or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", when):
        fail(f"{pack_id} manifest has no osmFetched date, so the card cannot say how old the record is")
    print(f"OK   {pack_id} records its OSM as pulled {when}")


def assert_the_generator_cannot_undo_the_audit() -> None:
    """`emit_app` had drifted from every file it writes.

    Running it would have put back the map screen from before the chips
    worked and the two extension stubs that broke signing. Its writer now has
    to refuse a file whose bytes differ.
    """
    body = (ROOT / "tools" / "v3" / "emit_app.py").read_text()
    if "path.exists() and path.read_text" not in body:
        fail("emit_app.w() will overwrite hand-edited sources again")
    print("OK   the app generator cannot clobber hand-edited sources")


def main() -> None:
    assert_the_card_never_sells_the_water()
    assert_sos_is_not_on_the_map_hold()
    assert_the_card_offers_exactly_two_actions()
    assert_the_credit_survives_the_card()
    assert_a_hold_is_not_a_pan()
    assert_the_generator_cannot_undo_the_audit()
    assert_the_tiler_and_the_card_know_the_same_words()
    assert_a_hold_reads_the_pack_and_not_the_apps_own_ink()
    assert_every_field_card_the_map_can_open_is_really_shipped()
    for pack_id in PACKS:
        assert_style_draws_ground_and_water(pack_id)
        assert_the_pack_says_when_it_was_pulled(pack_id)
        assert_the_record_survives_tiling(pack_id)
    print("PASS hold card and the water/land layer")


if __name__ == "__main__":
    main()
