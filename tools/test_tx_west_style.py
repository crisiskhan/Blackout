#!/usr/bin/env python3
"""Lock TX WEST default MapLibre style to on-device walking-zoom readability.

Washed charcoal/gray + 10–13pt labels fail this contract. Tokens are
#000000 / #E10600 / #B8BDC2. OSM data must stay walkable (not a sticker).
"""
from __future__ import annotations

import gzip
import json
import re
import sys
from pathlib import Path

import mapbox_vector_tile
from pmtiles.reader import MmapSource, Reader
from pmtiles.tile import TileType

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from v3.fetch_packs import (  # noqa: E402
    OSM_CREDIT,
    PRIMARY_PACK_ID,
    maplibre_style,
    walkable_ids,
)
from v3.tiles import MIN_ZOOM, lonlat_to_tile  # noqa: E402

VOID = "#000000"
ACCENT = "#E10600"
SILVER = "#B8BDC2"
WASHED_VOID = "#0c0e10"
WASHED_ROAD = "#c5cdd6"
WASHED_LABEL = "#e8eef4"


def fail(msg: str) -> None:
    print("FAIL", msg)
    raise SystemExit(1)


def layer(style: dict, layer_id: str) -> dict:
    for item in style.get("layers") or []:
        if item.get("id") == layer_id:
            return item
    fail(f"missing layer {layer_id}")
    return {}


def interpolate_at(expr: object, zoom: float) -> float:
    if not isinstance(expr, list) or not expr or expr[0] != "interpolate":
        fail(f"expected interpolate expression, got {expr!r}")
    stops: list[tuple[float, float]] = []
    i = 3
    while i + 1 < len(expr):
        stops.append((float(expr[i]), float(expr[i + 1])))
        i += 2
    if not stops:
        fail("empty interpolate")
    if zoom <= stops[0][0]:
        return stops[0][1]
    if zoom >= stops[-1][0]:
        return stops[-1][1]
    for (z0, v0), (z1, v1) in zip(stops, stops[1:]):
        if z0 <= zoom <= z1:
            t = (zoom - z0) / (z1 - z0)
            return v0 + t * (v1 - v0)
    return stops[-1][1]


def dump_json(obj: object) -> str:
    return json.dumps(obj, ensure_ascii=False).lower()


def assert_no_remote_tiles(style: dict, label: str) -> None:
    blob = dump_json(style)
    for needle in (
        "googleapis",
        "google.com/maps",
        "apple.com/maps",
        "mapkit",
        "mapbox.com",
        "satellite",
        "raster-tiles",
        "http://",
        "https://",
    ):
        if needle in blob:
            fail(f"{label} must stay offline local — found {needle}")
    glyphs = style.get("glyphs") or ""
    if str(glyphs).startswith("http") or "://" in str(glyphs):
        fail(f"{label} glyphs must be local, got {glyphs}")


def assert_readable_style(style: dict, label: str) -> None:
    assert_no_remote_tiles(style, label)
    layers = style.get("layers") or []
    ids = [item.get("id") for item in layers]
    if "roads" not in ids:
        fail(f"{label} missing roads")
    if "road-labels" not in ids:
        fail(f"{label} missing road-labels")
    if "tracks" not in ids:
        fail(f"{label} missing tracks")
    if "place-labels" not in ids:
        fail(f"{label} missing place-labels")

    void = layer(style, "void")
    if (void.get("paint") or {}).get("background-color") != VOID:
        fail(f"{label} void must be {VOID}, not washed {WASHED_VOID}")

    roads = layer(style, "roads")
    road_color = (roads.get("paint") or {}).get("line-color")
    if road_color != SILVER:
        fail(f"{label} roads must be silver {SILVER}, got {road_color}")
    width = (roads.get("paint") or {}).get("line-width")
    if interpolate_at(width, 15) < 4.5:
        fail(f"{label} walking-zoom road width too thin at z15: {interpolate_at(width, 15)}")
    if interpolate_at(width, 17) < 8.0:
        fail(f"{label} walking-zoom road width too thin at z17: {interpolate_at(width, 17)}")

    labels = layer(style, "road-labels")
    if float(labels.get("minzoom") or 99) > 12:
        fail(f"{label} road-labels minzoom must be <= 12 for walking approach")
    paint = labels.get("paint") or {}
    if paint.get("text-color") != SILVER:
        fail(f"{label} road-labels must be {SILVER}, not washed {WASHED_LABEL}")
    if paint.get("text-halo-color") != VOID:
        fail(f"{label} road-label halo must be {VOID}")
    if float(paint.get("text-halo-width") or 0) < 1.8:
        fail(f"{label} road-label halo too thin: {paint.get('text-halo-width')}")
    size = (labels.get("layout") or {}).get("text-size")
    if interpolate_at(size, 14) < 14:
        fail(f"{label} road names too small at z14: {interpolate_at(size, 14)}")
    if interpolate_at(size, 16) < 16:
        fail(f"{label} road names too small at z16: {interpolate_at(size, 16)}")
    layout = labels.get("layout") or {}
    if float(layout.get("symbol-spacing") or 999) > 110:
        fail(f"{label} road-label spacing too sparse at walking zoom: {layout.get('symbol-spacing')}")
    if float(layout.get("text-max-angle") or 0) < 40:
        fail(f"{label} road-label max-angle too tight: {layout.get('text-max-angle')}")
    points = next((item for item in layers if item.get("id") == "osm-points"), None)
    vis = ((points or {}).get("layout") or {}).get("visibility")
    if vis != "none":
        fail(f"{label} osm-points must stay quiet (visibility none), got {vis}")

    blob = dump_json(style)
    if ACCENT.lower() not in blob:
        fail(f"{label} must use accent {ACCENT} for highway refs / arterial contrast")
    if WASHED_VOID in blob or WASHED_ROAD in blob or WASHED_LABEL in blob:
        fail(f"{label} still ships washed default palette")

    hill = next((item for item in layers if item.get("id") == "hillshade"), None)
    if hill:
        opacity = float((hill.get("paint") or {}).get("raster-opacity") or 1)
        if opacity > 0.22:
            fail(f"{label} hillshade {opacity} washes street contrast")

    land = layer(style, "land-fill")
    color = (land.get("paint") or {}).get("fill-color")
    if not isinstance(color, list) or not color or color[0] != "match":
        fail(f"{label} land-fill must class ground cover, got {color!r}")
    body = color[2:]
    if len(body) < 3:
        fail(f"{label} land-fill match is empty")
    pairs = dict(zip(body[0:-1:2], body[1:-1:2]))
    desert = pairs.get("desert")
    bosque = pairs.get("bosque")
    playa = pairs.get("playa")
    if not desert or not bosque or not playa:
        fail(f"{label} land-fill is missing desert/bosque/playa ink")
    if desert == bosque:
        fail(f"{label} desert and bosque use the same ink {desert}")
    if desert == playa:
        fail(f"{label} desert and playa use the same ink {desert}")
    opacity = interpolate_at((land.get("paint") or {}).get("fill-opacity"), 15)
    if opacity < 0.15:
        fail(f"{label} land fill {opacity} at z15 — desert and bosque vanish")
    if opacity > 0.2:
        fail(f"{label} land fill {opacity} at z15 fights the streets")

    water = layer(style, "water-fill")
    water_color = (water.get("paint") or {}).get("fill-color")
    if water_color == VOID:
        fail(f"{label} water fill is void — lakes vanish")
    if str(water_color).lower() == "#1a1c1e":
        fail(f"{label} water fill {water_color} is too close to void to read")

    meta = style.get("metadata") or {}
    if meta.get("attribution") != OSM_CREDIT:
        fail(f"{label} missing OSM credit in style metadata")
    if not meta.get("walkingZoom"):
        fail(f"{label} walkingZoom metadata missing")
    if meta.get("network") != "deny-all":
        fail(f"{label} network must stay deny-all")


def open_zoom() -> float:
    """PackCamera.openZoom — the zoom the canvas actually opens at."""
    src = (
        ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift"
    ).read_text()
    found = re.search(r"openZoom: Double = ([0-9.]+)", src)
    if not found:
        fail("PackCamera.openZoom missing — canvas has no declared open zoom")
    return float(found.group(1))


def assert_opens_on_street_names(pack_id: str, zoom: float) -> None:
    """Fitting a whole pack bbox lands near z11 and hides every street name.

    The canvas must open at or above the zoom where this pack's own style
    starts drawing road labels, or TX WEST reads as unnamed lines again.
    """
    style = json.loads((ROOT / "Resources" / "Packs" / pack_id / "style.json").read_text())
    labels = layer(style, "road-labels")
    minzoom = float(labels.get("minzoom") or 0)
    if zoom < minzoom:
        fail(f"{pack_id} opens at z{zoom} but road-labels start at z{minzoom} — no street names on open")
    size = interpolate_at((labels.get("layout") or {}).get("text-size"), zoom)
    if size < 14:
        fail(f"{pack_id} street names are {size}pt at the open zoom z{zoom}")
    offline = (
        ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "OfflineMapView.swift"
    ).read_text()
    if "zoomLevel: PackCamera.openZoom" not in offline:
        fail("OfflineMapView must open the camera at PackCamera.openZoom")
    if "setVisibleCoordinateBounds" not in offline or "func fitPack" not in offline:
        fail("FIT PACK must still be able to show the whole region")
    print(f"OK   {pack_id} opens at z{zoom}; road names {size:.0f}pt from z{minzoom}")


def assert_home_is_on_streets(pack_id: str) -> None:
    """`home` is where the canvas opens with no GPS. It must have streets on it.

    The bbox midpoint does not: TX WEST's is the Franklin Mountains crest and
    TX EAST's is farmland east of Austin. Opening at walking zoom there paints
    a near-empty canvas that reads as a broken map.
    """
    pack = ROOT / "Resources" / "Packs" / pack_id
    man = json.loads((pack / "manifest.json").read_text())
    home = man.get("home")
    if not home:
        fail(f"{pack_id} manifest has no home point")
    catalog = json.loads((ROOT / "Resources" / "Packs" / "catalog.json").read_text())
    listed = next((p for p in catalog.get("packs") or [] if p.get("id") == pack_id), {})
    if listed.get("home") != home:
        fail(f"{pack_id} catalog home {listed.get('home')} does not match manifest {home}")
    bb = man["bbox"]
    if not (bb["south"] <= home["lat"] <= bb["north"] and bb["west"] <= home["lon"] <= bb["east"]):
        fail(f"{pack_id} home {home} is outside its own pack")

    # A walking-zoom screen at z15 is roughly 0.01deg tall on an iPhone.
    reach = 0.02
    osm = json.loads((pack / "osm.geojson").read_text())
    named = 0
    for feature in osm.get("features") or []:
        props = feature.get("properties") or {}
        if not props.get("highway") or not props.get("name"):
            continue
        geom = feature.get("geometry") or {}
        if geom.get("type") != "LineString":
            continue
        for lon, lat in geom.get("coordinates") or []:
            if abs(lat - home["lat"]) <= reach and abs(lon - home["lon"]) <= reach:
                named += 1
                break
        if named >= 40:
            break
    if named < 40:
        fail(f"{pack_id} home {home} has only {named} named streets within {reach}deg — opens on empty terrain")
    print(f"OK   {pack_id} home {home['lat']:.3f},{home['lon']:.3f} opens on named streets")


def assert_walkable_osm(pack_id: str) -> None:
    """The streets have to survive the trip into the tile archive.

    This used to weigh `osm.geojson` and count its features. The streets now
    ship as vector tiles, so weighing the file no longer says anything about
    what a phone can draw — an archive can be the right size and still decode
    to nothing. Open the archive the app opens, pull the tiles over the spot
    the app opens on, and count the streets that come back out.
    """
    pack = ROOT / "Resources" / "Packs" / pack_id
    archive = pack / "osm.pmtiles"
    if not archive.is_file():
        fail(f"{pack_id} missing osm.pmtiles")
    mb = archive.stat().st_size / (1024 * 1024)
    if mb < 2.0:
        fail(f"{pack_id} tiles {mb:.1f} MB looks like a sticker — do not replace walkable data")

    manifest = json.loads((pack / "manifest.json").read_text())
    home = manifest["home"]
    with open(archive, "rb") as fh:
        reader = Reader(MmapSource(fh))
        header = reader.header()
        if TileType(header["tile_type"]) is not TileType.MVT:
            fail(f"{pack_id} archive is not vector tiles: {TileType(header['tile_type']).name}")
        if header["max_zoom"] < 14:
            fail(f"{pack_id} archive stops at z{header['max_zoom']} — too coarse to walk by")
        if header["min_zoom"] > MIN_ZOOM:
            fail(f"{pack_id} archive starts at z{header['min_zoom']} — zooming out goes blank")
        bounds_cover(pack_id, header, manifest["bbox"])

        # The nine tiles around where the canvas opens, which is the ground the
        # phone is guaranteed to draw first.
        z = 14
        cx, cy = lonlat_to_tile(home["lon"], home["lat"], z)
        streets, named = 0, set()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                blob = reader.get(z, int(cx) + dx, int(cy) + dy)
                if not blob:
                    continue
                road = mapbox_vector_tile.decode(gzip.decompress(blob)).get("road")
                if not road:
                    continue
                streets += len(road["features"])
                for feature in road["features"]:
                    label = feature["properties"].get("name") or feature["properties"].get("ref")
                    if label:
                        named.add(label)
    if streets < 1000 or len(named) < 200:
        fail(f"{pack_id} walking streets too thin at home: hwy={streets} named={len(named)}")
    print(f"OK   {pack_id} tiles {mb:.1f} MB z{header['min_zoom']}-{header['max_zoom']} "
          f"hwy={streets} named={len(named)} around home")


def bounds_cover(pack_id: str, header: dict, bbox: dict) -> None:
    """An archive that quietly covers less ground than the pack claims is a lie."""
    slack = 1e-3
    got = {
        "south": header["min_lat_e7"] / 1e7,
        "north": header["max_lat_e7"] / 1e7,
        "west": header["min_lon_e7"] / 1e7,
        "east": header["max_lon_e7"] / 1e7,
    }
    short = [
        edge
        for edge, inside in (
            ("south", got["south"] <= bbox["south"] + slack),
            ("north", got["north"] >= bbox["north"] - slack),
            ("west", got["west"] <= bbox["west"] + slack),
            ("east", got["east"] >= bbox["east"] - slack),
        )
        if not inside
    ]
    if short:
        fail(f"{pack_id} tile archive falls short of the pack bbox on {', '.join(short)}: {got} vs {bbox}")


def assert_every_tile_layer_names_its_slice(pack_id: str) -> None:
    """A vector layer with no `source-layer` draws nothing, and says nothing.

    This is the quietest way to break the map: the style still parses, the
    source still loads, the layer is still there, and the streets are simply
    gone. Check both the style on disk and the layers the app injects at run
    time, because the second set is what appears when a style is missing one.
    """
    style = json.loads((ROOT / "Resources" / "Packs" / pack_id / "style.json").read_text())
    vector = {
        name
        for name, src in (style.get("sources") or {}).items()
        if (src or {}).get("type") == "vector"
    }
    for layer in style.get("layers") or []:
        if layer.get("source") in vector and not layer.get("source-layer"):
            fail(f"{pack_id} style layer {layer['id']!r} reads a vector source with no source-layer — it draws nothing")

    swift = (
        ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift"
    ).read_text()
    injected = re.findall(r'"source": "osm",\n(\s*)"source-layer"', swift)
    declared = swift.count('"source": "osm",')
    if len(injected) != declared:
        fail(
            f"{declared - len(injected)} runtime-injected layer(s) read the osm source without a "
            "source-layer; they would draw nothing on the phone"
        )


def assert_source_geojson_stays_off_the_phone(pack_id: str) -> None:
    """`osm.geojson` is build input now, not cargo. Keep it out of the bundle."""
    manifest = json.loads((ROOT / "Resources" / "Packs" / pack_id / "manifest.json").read_text())
    files = manifest.get("files") or []
    if "osm.geojson" in files:
        fail(f"{pack_id} manifest still ships osm.geojson — that is ~50 MB the phone never reads")
    if "osm.pmtiles" not in files:
        fail(f"{pack_id} manifest does not list osm.pmtiles")
    script = (ROOT / "Blackout.xcodeproj" / "project.pbxproj").read_text()
    if "--exclude 'Packs/*/osm.geojson'" not in script:
        fail("the resource copy step no longer excludes osm.geojson; the IPA would carry it again")


def main() -> None:
    if PRIMARY_PACK_ID != "tx-west":
        fail(f"default open pack drifted to {PRIMARY_PACK_ID}")
    if walkable_ids() != {"tx-west", "nm", "tx-east"}:
        fail(f"walkable set {walkable_ids()} — keep nm + tx-east packs and tx-west default open")

    catalog = json.loads((ROOT / "Resources" / "Packs" / "catalog.json").read_text())
    if catalog.get("defaultPack") != "tx-west":
        fail("catalog defaultPack must stay tx-west")
    if (catalog.get("packs") or [{}])[0].get("id") != "tx-west":
        fail("catalog first pack must stay tx-west")
    nm = next((p for p in catalog.get("packs") or [] if p.get("id") == "nm"), None)
    if not nm:
        fail("nm pack missing from catalog")
    east = next((p for p in catalog.get("packs") or [] if p.get("id") == "tx-east"), None)
    if not east:
        fail("tx-east pack missing from catalog")
    if set(catalog.get("states") or []) != {"TX", "NM"}:
        fail(f"catalog states must be TX/NM only, got {catalog.get('states')}")

    style_path = ROOT / "Resources" / "Packs" / "tx-west" / "style.json"
    style = json.loads(style_path.read_text())
    assert_readable_style(style, "tx-west/style.json")

    # NM shipped before the readability pass and kept 10pt labels with no casing.
    # Every walkable pack now answers to the same contract.
    for pack_id in sorted(walkable_ids() - {"tx-west"}):
        sibling = ROOT / "Resources" / "Packs" / pack_id / "style.json"
        assert_readable_style(json.loads(sibling.read_text()), f"{pack_id}/style.json")

    existing = json.loads(style_path.read_text())
    hill = existing.get("sources", {}).get("hillshade")
    hillshade = None
    if hill:
        hillshade = {
            "present": True,
            "file": hill.get("url"),
            "coordinates": hill.get("coordinates"),
        }
    generated = maplibre_style("tx-west", hillshade)
    assert_readable_style(generated, "maplibre_style(tx-west)")
    for pack_id in sorted(walkable_ids()):
        disk = json.loads((ROOT / "Resources" / "Packs" / pack_id / "style.json").read_text())
        hill_src = (disk.get("sources") or {}).get("hillshade")
        hill_meta = None
        if hill_src:
            hill_meta = {
                "present": True,
                "file": hill_src.get("url"),
                "coordinates": hill_src.get("coordinates"),
            }
        made = maplibre_style(pack_id, hill_meta)
        disk_land = layer(disk, "land-fill").get("paint")
        made_land = layer(made, "land-fill").get("paint")
        if disk_land != made_land:
            fail(f"{pack_id} style.json land-fill is not maplibre_style")
        disk_water = layer(disk, "water-fill").get("paint")
        made_water = layer(made, "water-fill").get("paint")
        if disk_water != made_water:
            fail(f"{pack_id} style.json water-fill is not maplibre_style")

    refs = next((item for item in style.get("layers") or [] if item.get("id") == "road-refs"), None)
    if not refs:
        fail("tx-west needs a road-refs layer so highway numbers read at walking zoom")
    if float(refs.get("minzoom") or 99) > 12:
        fail("road-refs must appear by walking approach zoom")
    if (refs.get("paint") or {}).get("text-color") != SILVER:
        fail(f"road-refs must be {SILVER}, not leftover accent")
    if (refs.get("paint") or {}).get("text-halo-color") != VOID:
        fail("road-refs need a void halo so silver reads on the pack")
    if interpolate_at((refs.get("layout") or {}).get("text-size"), 16) < 18:
        fail("road-refs too small at walking zoom")
    ref_key = (refs.get("layout") or {}).get("symbol-sort-key")
    if not isinstance(ref_key, (int, float)) or float(ref_key) > 1:
        fail("road-refs must sort ahead of local names (symbol-sort-key <= 1)")

    casing = next((item for item in style.get("layers") or [] if item.get("id") == "roads-casing"), None)
    if not casing:
        fail("tx-west needs roads-casing so silver streets pop off void")
    arterial = next((item for item in style.get("layers") or [] if item.get("id") == "roads-arterial-casing"), None)
    major = next((item for item in style.get("layers") or [] if item.get("id") == "roads-major"), None)
    if not arterial or not major:
        fail("tx-west needs arterial red casing and major silver fill")
    for z in (13, 15, 17):
        red = interpolate_at((arterial.get("paint") or {}).get("line-width"), z)
        fill = interpolate_at((major.get("paint") or {}).get("line-width"), z)
        if red - fill < 1.8:
            fail(f"arterial red casing invisible under major fill at z{z}: red={red} fill={fill}")

    for pack_id in ("tx-west", "nm", "tx-east"):
        assert_walkable_osm(pack_id)
        assert_every_tile_layer_names_its_slice(pack_id)
        assert_source_geojson_stays_off_the_phone(pack_id)

    zoom = open_zoom()
    for pack_id in sorted(walkable_ids()):
        assert_opens_on_street_names(pack_id, zoom)
        assert_home_is_on_streets(pack_id)

    tokens = (ROOT / "Packages" / "Tokens" / "Sources" / "Tokens" / "Tokens.swift").read_text()
    if 'voidHex = "#000000"' not in tokens:
        fail("Tokens.MapInk.voidHex missing")
    if 'silverHex = "#B8BDC2"' not in tokens:
        fail("Tokens.MapInk.silverHex missing")
    if 'accentHex = "#E10600"' not in tokens:
        fail("Tokens.MapInk.accentHex missing")

    fallback = (
        ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift"
    ).read_text()
    if SILVER not in fallback or ACCENT not in fallback or VOID not in fallback:
        fail("PackStyle fallback layers must use Blackout map ink")
    if '"text-size": 11' in fallback or "text-size\": 11" in fallback:
        fail("PackStyle fallback road labels still 11pt")

    pbx = (ROOT / "Blackout.xcodeproj" / "project.pbxproj").read_text()
    if "CURRENT_PROJECT_VERSION = 1;" not in pbx:
        fail("CPV must stay 1")

    print("OK   TX WEST style uses Blackout ink; walking-zoom names read")


if __name__ == "__main__":
    main()
