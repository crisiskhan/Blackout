#!/usr/bin/env python3
"""Lock the STATES overview pack: both states on one glass, not a walkable metro."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "Resources" / "Packs" / "states"
CATALOG = ROOT / "Resources" / "Packs" / "catalog.json"

# Ground Crisis asked to see. The chart may grow past these pins; it may not
# leave one of them off the glass.
BOTH_STATES = {
    "El Paso": (31.7619, -106.4850),
    "Las Cruces": (32.3199, -106.7637),
    "Albuquerque": (35.0844, -106.6504),
    "Santa Fe": (35.6870, -105.9378),
    "Farmington": (36.7281, -108.2187),
    "Austin": (30.2672, -97.7431),
    "Houston": (29.7604, -95.3698),
    "Dallas": (32.7767, -96.7970),
    "Amarillo": (35.2220, -101.8313),
    "Brownsville": (25.9017, -97.4975),
    "Laredo": (27.5064, -99.5075),
}

METRO_PACKS = {
    "tx-west": (32.05, -106.475),
    "tx-east": (30.275, -97.575),
    "nm": (35.15, -106.55),
}

VOID = "#000000"
SILVER = "#B8BDC2"
ACCENT = "#E10600"


def fail(msg: str) -> None:
    print("FAIL", msg)
    raise SystemExit(1)


def covers(box: dict, lat: float, lon: float) -> bool:
    return box["south"] <= lat <= box["north"] and box["west"] <= lon <= box["east"]


def ring_covers(ring: list, lat: float, lon: float) -> bool:
    """Ray-cast a closed lon/lat ring. Chart-grade, not a survey."""
    inside = False
    if len(ring) < 4:
        return False
    for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
        cond = (y1 > lat) != (y2 > lat)
        if cond:
            x = (x2 - x1) * (lat - y1) / (y2 - y1 + 0.0) + x1
            if lon < x:
                inside = not inside
    return inside


def features(path: Path) -> list:
    blob = json.loads(path.read_text())
    return blob.get("features") or []


def main() -> None:
    catalog = json.loads(CATALOG.read_text())
    if catalog.get("defaultPack") != "tx-west":
        fail("STATES must not steal default open from tx-west")
    packs = catalog.get("packs") or []
    if not packs or packs[0].get("id") != "tx-west":
        fail("catalog first pack must stay tx-west")
    ids = [p.get("id") for p in packs]
    if ids != ["tx-west", "tx-east", "nm", "states"]:
        fail(f"catalog pack order {ids} — metros then STATES")
    states = next((p for p in packs if p.get("id") == "states"), None)
    if not states:
        fail("catalog missing states pack")
    if states.get("name") != "STATES":
        fail("states pack name must be STATES")
    if states.get("walkable") is not False:
        fail("STATES must not be walkable — WALK/DRIVE stay OFF GRAPH")
    if states.get("overview") is not True:
        fail("STATES must mark overview so the camera stays flat")
    if states.get("state") not in {"TX", "NM"}:
        fail("STATES state must stay on the shipped TX/NM list")
    if states.get("defaultOpen"):
        fail("STATES must not set defaultOpen")
    box = states.get("bbox") or {}
    for name, (lat, lon) in BOTH_STATES.items():
        if not covers(box, lat, lon):
            fail(f"STATES bbox dropped {name} at {lat}, {lon}")
    if (box.get("north") or 0) - (box.get("south") or 0) < 10:
        fail("STATES bbox is too short to hold both states")
    if (box.get("east") or 0) - (box.get("west") or 0) < 12:
        fail("STATES bbox is too narrow to hold both states")

    man_path = PACK / "manifest.json"
    if not man_path.is_file():
        fail("states/manifest.json missing")
    man = json.loads(man_path.read_text())
    if man.get("id") != "states" or man.get("walkable") is not False or man.get("overview") is not True:
        fail("states manifest is not an overview pack")
    if (PACK / "aerial.pmtiles").exists() or (PACK / "hillshade.png").exists():
        fail("STATES must not ship fake statewide aerial or hillshade")
    if (PACK / "overlay.pmtiles").exists() or (PACK / "osm.pmtiles").exists():
        fail("STATES is a chart, not a metro tile extract")
    if (PACK / "graph.bin").exists() or (PACK / "graph.json").exists():
        fail("STATES must ship no graph so WALK/DRIVE stay OFF GRAPH")
    if (PACK / "layers" / "water.bin").exists() or (PACK / "layers" / "water.geojson").exists():
        fail("STATES must not ship a water index — hold is LAND, not fake statewide water")
    if (PACK / "dem.json").exists():
        fail("STATES must not claim terrain")

    style_path = PACK / "style.json"
    if not style_path.is_file():
        fail("states/style.json missing")
    style = json.loads(style_path.read_text())
    blob = style_path.read_text()
    if "pmtiles://" in blob or "googleapis" in blob or "mapkit" in blob.lower():
        fail("STATES style must stay local GeoJSON — no tile hosts")
    if "aerial" in (style.get("sources") or {}):
        fail("STATES style must not name an aerial source")
    paint = (style.get("layers") or [{}])[0].get("paint") or {}
    if style.get("layers") and style["layers"][0].get("type") == "background":
        if paint.get("background-color") != VOID:
            fail("STATES background must be void")
    ink = blob.upper()
    if VOID.upper() not in ink or SILVER.upper() not in ink or ACCENT.upper() not in ink:
        fail("STATES style must use void / silver / accent")
    glyphs = style.get("glyphs") or ""
    if glyphs.startswith("http") or "{" not in glyphs:
        fail("STATES glyphs must be local")
    if not (PACK / "glyphs" / "Open Sans Regular" / "0-255.pbf").is_file():
        fail("STATES missing local Open Sans glyphs")

    outlines = features(PACK / "states.geojson")
    names = {(f.get("properties") or {}).get("name") for f in outlines}
    if names != {"TEXAS", "NEW MEXICO"}:
        fail(f"states.geojson must name TEXAS and NEW MEXICO, got {names}")
    rings = {}
    for feat in outlines:
        geom = feat.get("geometry") or {}
        if geom.get("type") != "Polygon":
            fail("state outlines must be polygons")
        name = (feat.get("properties") or {}).get("name")
        rings[name] = (geom.get("coordinates") or [[]])[0]
    if not ring_covers(rings["TEXAS"], 30.2672, -97.7431):
        fail("TEXAS outline dropped Austin")
    if not ring_covers(rings["TEXAS"], 31.7619, -106.4850):
        fail("TEXAS outline dropped El Paso")
    if not ring_covers(rings["TEXAS"], 25.9017, -97.4975):
        fail("TEXAS outline dropped Brownsville")
    if ring_covers(rings["TEXAS"], 35.0844, -106.6504):
        fail("TEXAS outline swallowed Albuquerque")
    if not ring_covers(rings["NEW MEXICO"], 35.0844, -106.6504):
        fail("NEW MEXICO outline dropped Albuquerque")
    if not ring_covers(rings["NEW MEXICO"], 32.3199, -106.7637):
        fail("NEW MEXICO outline dropped Las Cruces")
    if ring_covers(rings["NEW MEXICO"], 30.2672, -97.7431):
        fail("NEW MEXICO outline swallowed Austin")

    boxes = features(PACK / "packs.geojson")
    box_ids = {(f.get("properties") or {}).get("pack") for f in boxes}
    if box_ids != {"tx-west", "tx-east", "nm"}:
        fail(f"packs.geojson must outline the three metros, got {box_ids}")

    cities = features(PACK / "cities.geojson")
    city_names = {(f.get("properties") or {}).get("name") for f in cities}
    for need in ("El Paso", "Austin", "Albuquerque", "Santa Fe", "Houston"):
        if need not in city_names:
            fail(f"cities.geojson missing {need}")

    roads = features(PACK / "highways.geojson")
    refs = {(f.get("properties") or {}).get("ref") for f in roads}
    for need in ("I-10", "I-20", "I-25", "I-35", "I-40"):
        if need not in refs:
            fail(f"highways.geojson missing {need}")

    search = json.loads((PACK / "search.json").read_text())
    docs = search.get("docs") or []
    named = {row[0] for row in docs if isinstance(row, list) and row}
    for need in ("TX WEST", "TX EAST", "NM", "El Paso", "Austin", "Albuquerque"):
        if need not in named:
            fail(f"STATES search missing {need}")
    kinds = {row[1] for row in docs if isinstance(row, list) and len(row) > 1}
    if "pack" not in kinds:
        fail("STATES search must tag metro entries as pack")

    cam = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift").read_text()
    hold = cam.split("public enum PackCamera")[1].split("public enum PackStyle")[0]
    if "static let overviewMinZoom" not in hold:
        fail("PackCamera must name an overview zoom floor")
    if "overviewPitch" not in hold or "overview: Bool" not in hold:
        fail("PackCamera must branch on overview so STATES stays flat")
    if "photoMinZoom" not in hold:
        fail("walking photo floor must stay for metro packs")

    pack_io = (ROOT / "Packages" / "PackIO" / "Sources" / "PackIO" / "PackIO.swift").read_text()
    if "var overview: Bool" not in pack_io or "var walkable: Bool" not in pack_io:
        fail("PackManifest must decode overview and walkable")
    if "func walkablePack" not in pack_io:
        fail("PackStore must name the metro under a tap")

    water_tests = (
        ROOT / "Packages" / "MapLibreMap" / "Tests" / "MapLibreMapTests" / "WaterInspectTests.swift"
    ).read_text()
    every = water_tests.split("func testEveryShippedPackAnswersFromItsOwnWater")[1].split("func test")[0]
    if "overview" not in every:
        fail("testEveryShippedPackAnswersFromItsOwnWater must skip overview packs")
    if "func testOverviewPackHasNoWaterIndexAndHoldStillAnswers" not in water_tests:
        fail("STATES must lock that hold has no water index")

    app = (ROOT / "Blackout" / "AppRuntime.swift").read_text()
    if "func enterOverviewPack" not in app:
        fail("tap / SEARCH on STATES must enter the metro under the pin")
    if "enterOverviewPack" not in (ROOT / "Blackout" / "MapTab.swift").read_text():
        fail("MAP tap and SEARCH must call enterOverviewPack")
    if '"<1 MB"' not in (ROOT / "Blackout" / "InstrumentsView.swift").read_text():
        fail("PACKS must not round STATES up to a fake megabyte")

    offline = (
        ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "OfflineMapView.swift"
    ).read_text()
    if "overview: overview" not in offline and "overview: spec.overview" not in offline:
        fail("OfflineMapView must pass overview into PackCamera")
    if "setVisibleCoordinateBounds" not in offline:
        fail("overview fit must frame the bbox, not walk pitch")

    for name in ("field.tx.json", "field.nm.json"):
        book = json.loads((ROOT / "Resources" / "Field" / name).read_text())
        for card in book.get("cards") or []:
            if "states" in (card.get("packs") or []):
                fail(f"{card.get('id')} must not attach to the STATES pack")

    solo = (ROOT / "docs" / "SOLO_QA.md").read_text()
    device = (ROOT / "docs" / "DEVICE.md").read_text()
    for blob in (solo, device):
        if "INSTRUMENTS → PACKS → STATES" not in blob:
            fail("SOLO_QA / DEVICE must say how to open STATES")
        if "OFF GRAPH" not in blob:
            fail("STATES device line must keep OFF GRAPH honest")
    if "Hold is LAND" not in solo:
        fail("SOLO_QA must say STATES hold is LAND")

    print("OK   STATES shows Texas and New Mexico on one glass")
    print("OK   metros stay walkable; default stays tx-west; no statewide aerial")


if __name__ == "__main__":
    main()
