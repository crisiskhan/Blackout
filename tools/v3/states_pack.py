"""Write the STATES overview chart. No OSM fetch. No statewide NAIP."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "Resources" / "Packs" / "states"
CATALOG = ROOT / "Resources" / "Packs" / "catalog.json"
GLYPHS = ROOT / "Resources" / "Packs" / "tx-west" / "glyphs"

VOID = "#000000"
SILVER = "#B8BDC2"
ACCENT = "#E10600"
LAND = "#101214"

# Padded so both outlines sit in the glass, not on the chrome.
BBOX = {"south": 25.50, "west": -109.45, "north": 37.35, "east": -93.15}
CENTER = {"lat": 31.425, "lon": -101.3}

# Clockwise from the NM/OK/TX corner. Chart-grade, not a survey.
TEXAS = [
    [-103.042, 36.500],
    [-100.000, 36.500],
    [-100.000, 34.562],
    [-99.230, 34.382],
    [-98.000, 34.160],
    [-97.140, 33.870],
    [-96.350, 33.870],
    [-95.150, 33.960],
    [-94.480, 33.640],
    [-94.043, 33.550],
    [-94.043, 32.000],
    [-94.043, 31.140],
    [-93.530, 31.140],
    [-93.838, 29.787],
    [-94.690, 29.394],
    [-95.364, 28.796],
    [-96.407, 28.355],
    [-97.145, 26.070],
    [-97.400, 25.840],
    [-97.525, 25.838],
    [-98.208, 26.143],
    [-99.514, 27.543],
    [-100.396, 28.229],
    [-100.900, 29.370],
    [-102.000, 29.780],
    [-103.000, 29.100],
    [-103.800, 29.270],
    [-104.526, 29.632],
    [-104.696, 29.900],
    [-105.500, 30.650],
    [-106.200, 31.400],
    [-106.528, 31.750],
    [-106.528, 31.784],
    [-106.616, 32.000],
    [-103.042, 32.000],
    [-103.042, 36.500],
]

NEW_MEXICO = [
    [-109.050, 37.000],
    [-103.002, 37.000],
    [-103.002, 32.000],
    [-106.616, 32.000],
    [-106.528, 31.784],
    [-108.208, 31.332],
    [-109.050, 31.332],
    [-109.050, 37.000],
]

METRO_BOXES = {
    "tx-west": {
        "name": "TX WEST",
        "south": 30.95,
        "west": -107.6,
        "north": 33.15,
        "east": -105.35,
    },
    "tx-east": {
        "name": "TX EAST",
        "south": 30.05,
        "west": -97.95,
        "north": 30.5,
        "east": -97.2,
    },
    "nm": {
        "name": "NM",
        "south": 34.35,
        "west": -107.45,
        "north": 35.95,
        "east": -105.65,
    },
}

CITIES = [
    ("El Paso", 31.7619, -106.4850),
    ("Las Cruces", 32.3199, -106.7637),
    ("Albuquerque", 35.0844, -106.6504),
    ("Santa Fe", 35.6870, -105.9378),
    ("Farmington", 36.7281, -108.2187),
    ("Roswell", 33.3943, -104.5230),
    ("Austin", 30.2672, -97.7431),
    ("San Antonio", 29.4241, -98.4936),
    ("Houston", 29.7604, -95.3698),
    ("Dallas", 32.7767, -96.7970),
    ("Fort Worth", 32.7555, -97.3308),
    ("Amarillo", 35.2220, -101.8313),
    ("Lubbock", 33.5779, -101.8552),
    ("Midland", 31.9973, -102.0779),
    ("Corpus Christi", 27.8006, -97.3964),
    ("Brownsville", 25.9017, -97.4975),
    ("Laredo", 27.5064, -99.5075),
]

HIGHWAYS = [
    (
        "I-10",
        [
            [-93.85, 30.10],
            [-95.37, 29.76],
            [-96.35, 29.70],
            [-97.40, 29.55],
            [-98.49, 29.42],
            [-99.80, 29.70],
            [-100.90, 30.20],
            [-102.88, 30.89],
            [-104.50, 31.40],
            [-106.49, 31.76],
            [-106.78, 32.32],
            [-107.80, 32.25],
            [-109.05, 32.22],
        ],
    ),
    (
        "I-20",
        [
            [-93.90, 32.52],
            [-94.80, 32.50],
            [-96.80, 32.78],
            [-98.50, 32.45],
            [-100.00, 32.25],
            [-101.50, 32.00],
            [-102.08, 31.99],
            [-102.88, 30.89],
        ],
    ),
    (
        "I-35",
        [
            [-99.51, 27.51],
            [-98.49, 29.42],
            [-97.74, 30.27],
            [-97.15, 31.55],
            [-97.13, 32.75],
            [-96.80, 32.78],
            [-97.15, 33.90],
        ],
    ),
    (
        "I-40",
        [
            [-103.00, 35.22],
            [-103.73, 35.17],
            [-106.65, 35.11],
            [-108.74, 35.53],
            [-109.05, 35.53],
        ],
    ),
    (
        "I-25",
        [
            [-106.49, 31.76],
            [-106.78, 32.32],
            [-106.78, 33.20],
            [-106.65, 35.11],
            [-105.94, 35.69],
            [-104.90, 37.00],
        ],
    ),
    ("I-27", [[-101.85, 33.58], [-101.83, 35.22]]),
    ("I-45", [[-94.80, 29.30], [-95.37, 29.76], [-96.80, 32.78]]),
    ("I-37", [[-97.40, 27.80], [-98.49, 29.42]]),
]


def fc(feats: list) -> dict:
    return {"type": "FeatureCollection", "features": feats}


def polygon(name: str, ring: list, **props: object) -> dict:
    return {
        "type": "Feature",
        "properties": {"name": name, **props},
        "geometry": {"type": "Polygon", "coordinates": [ring]},
    }


def box_poly(pack_id: str, box: dict) -> dict:
    ring = [
        [box["west"], box["south"]],
        [box["east"], box["south"]],
        [box["east"], box["north"]],
        [box["west"], box["north"]],
        [box["west"], box["south"]],
    ]
    return polygon(box["name"], ring, pack=pack_id)


def point(name: str, lat: float, lon: float, kind: str = "place") -> dict:
    return {
        "type": "Feature",
        "properties": {"name": name, "kind": kind},
        "geometry": {"type": "Point", "coordinates": [lon, lat]},
    }


def line(ref: str, coords: list) -> dict:
    return {
        "type": "Feature",
        "properties": {"ref": ref, "highway": "motorway"},
        "geometry": {"type": "LineString", "coordinates": coords},
    }


def style() -> dict:
    return {
        "version": 8,
        "name": "Blackout STATES",
        "glyphs": "glyphs/{fontstack}/{range}.pbf",
        "sources": {
            "states": {"type": "geojson", "data": "states.geojson"},
            "highways": {"type": "geojson", "data": "highways.geojson"},
            "packs": {"type": "geojson", "data": "packs.geojson"},
            "cities": {"type": "geojson", "data": "cities.geojson"},
        },
        "layers": [
            {
                "id": "background",
                "type": "background",
                "paint": {"background-color": VOID},
            },
            {
                "id": "state-fill",
                "type": "fill",
                "source": "states",
                "paint": {"fill-color": LAND, "fill-opacity": 1},
            },
            {
                "id": "state-line",
                "type": "line",
                "source": "states",
                "paint": {"line-color": SILVER, "line-width": 1.6},
            },
            {
                "id": "highways",
                "type": "line",
                "source": "highways",
                "paint": {
                    "line-color": SILVER,
                    "line-width": 1.15,
                    "line-opacity": 0.85,
                },
            },
            {
                "id": "pack-fill",
                "type": "fill",
                "source": "packs",
                "paint": {"fill-color": ACCENT, "fill-opacity": 0.14},
            },
            {
                "id": "pack-line",
                "type": "line",
                "source": "packs",
                "paint": {"line-color": ACCENT, "line-width": 2},
            },
            {
                "id": "city-dot",
                "type": "circle",
                "source": "cities",
                "paint": {
                    "circle-color": SILVER,
                    "circle-radius": 2.4,
                    "circle-stroke-color": VOID,
                    "circle-stroke-width": 0.8,
                },
            },
            {
                "id": "state-label",
                "type": "symbol",
                "source": "states",
                "layout": {
                    "text-field": ["get", "name"],
                    "text-size": 18,
                    "text-font": ["Open Sans Regular"],
                    "text-transform": "uppercase",
                    "text-letter-spacing": 0.12,
                },
                "paint": {
                    "text-color": SILVER,
                    "text-halo-color": VOID,
                    "text-halo-width": 1.4,
                },
            },
            {
                "id": "pack-label",
                "type": "symbol",
                "source": "packs",
                "layout": {
                    "text-field": ["get", "name"],
                    "text-size": 13,
                    "text-font": ["Open Sans Regular"],
                    "text-allow-overlap": True,
                },
                "paint": {
                    "text-color": ACCENT,
                    "text-halo-color": VOID,
                    "text-halo-width": 1.2,
                },
            },
            {
                "id": "city-label",
                "type": "symbol",
                "source": "cities",
                "layout": {
                    "text-field": ["get", "name"],
                    "text-size": 12,
                    "text-font": ["Open Sans Regular"],
                    "text-offset": [0, 1.1],
                    "text-optional": True,
                },
                "paint": {
                    "text-color": SILVER,
                    "text-halo-color": VOID,
                    "text-halo-width": 1.1,
                },
            },
        ],
    }


def search_docs() -> list:
    docs = []
    for pack_id, box in METRO_BOXES.items():
        lat = (box["south"] + box["north"]) / 2
        lon = (box["west"] + box["east"]) / 2
        docs.append([box["name"], "pack", lat, lon])
    for name, lat, lon in CITIES:
        docs.append([name, "place", lat, lon])
    return docs


def dump(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def dir_bytes(root: Path) -> int:
    total = 0
    for path in root.rglob("*"):
        if path.is_file():
            total += path.stat().st_size
    return total


def write_pack() -> dict:
    PACK.mkdir(parents=True, exist_ok=True)
    dump(
        PACK / "states.geojson",
        fc(
            [
                polygon("TEXAS", TEXAS, kind="state"),
                polygon("NEW MEXICO", NEW_MEXICO, kind="state"),
            ]
        ),
    )
    dump(PACK / "packs.geojson", fc([box_poly(pid, box) for pid, box in METRO_BOXES.items()]))
    dump(PACK / "cities.geojson", fc([point(name, lat, lon) for name, lat, lon in CITIES]))
    dump(PACK / "highways.geojson", fc([line(ref, coords) for ref, coords in HIGHWAYS]))
    dump(PACK / "search.json", {"docs": search_docs()})
    dump(PACK / "style.json", style())
    dump(PACK / "cameras.json", [])
    dest_glyphs = PACK / "glyphs"
    if dest_glyphs.exists():
        shutil.rmtree(dest_glyphs)
    shutil.copytree(GLYPHS, dest_glyphs)
    files = sorted(
        str(p.relative_to(PACK))
        for p in PACK.rglob("*")
        if p.is_file() and p.name != "manifest.json"
    )
    manifest = {
        "id": "states",
        "name": "STATES",
        "state": "TX",
        "kind": "overview-chart",
        "engine": "maplibre",
        "defaultOpen": False,
        "walkable": False,
        "overview": True,
        "bbox": BBOX,
        "banners": [],
        "center": CENTER,
        "home": CENTER,
        "attribution": (
            "Simplified TX+NM chart. No statewide aerial. Yard NAIP and street "
            "graphs stay on TX WEST, TX EAST, and NM."
        ),
        "stats": {
            "features": 2 + len(METRO_BOXES) + len(CITIES) + len(HIGHWAYS),
            "highwayLines": len(HIGHWAYS),
            "namedStreets": 0,
            "graphEdges": 0,
            "graphNodes": 0,
            "streetsVisibleAtWalkingZoom": False,
        },
        "files": files,
        "bytes": 0,
    }
    dump(PACK / "manifest.json", manifest)
    files = sorted(str(p.relative_to(PACK)) for p in PACK.rglob("*") if p.is_file())
    manifest["files"] = files
    manifest["bytes"] = dir_bytes(PACK)
    dump(PACK / "manifest.json", manifest)
    return manifest


def sync_catalog(manifest: dict) -> None:
    catalog = json.loads(CATALOG.read_text())
    for pack in catalog.get("packs") or []:
        pack.setdefault("overview", False)
    entry = {
        "id": "states",
        "name": "STATES",
        "state": "TX",
        "kind": "overview-chart",
        "engine": "maplibre",
        "defaultOpen": False,
        "walkable": False,
        "overview": True,
        "bbox": manifest["bbox"],
        "banners": [],
        "center": manifest["center"],
        "home": manifest["home"],
        "attribution": manifest["attribution"],
        "stats": manifest["stats"],
        "files": manifest["files"],
        "bytes": manifest["bytes"],
    }
    packs = [p for p in catalog["packs"] if p.get("id") != "states"]
    packs.append(entry)
    catalog["packs"] = packs
    dump(CATALOG, catalog)


def main() -> None:
    manifest = write_pack()
    sync_catalog(manifest)
    print(f"OK   STATES bytes={manifest['bytes']} files={len(manifest['files'])}")


if __name__ == "__main__":
    main()
