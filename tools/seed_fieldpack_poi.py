#!/usr/bin/env python3
"""Fetch compact OSM amenity/address JSON for Field Packs. No PBF in git.

Writes tools/fieldpack_poi/<id>/{poi,address}.json for later zip publish.
Does not copy into the IPA. Update maps still replaces the pack zip.

Kind set is civic + shop + field — not restaurant-only. Addresses are
city-only; statewide packs stay amenity-only (no housenumber dump).
"""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tools" / "fieldpack_poi"
OVERPASS = "https://overpass-api.de/api/interpreter"

# Catalog bboxes (center ± span/2) from FieldPackCatalog.
# (south, west, north, east, include_addresses)
PACKS = {
    "el-paso": (31.3619, -106.885, 32.1619, -106.085, True),
    "las-cruces": (31.9699, -107.1137, 32.6699, -106.4137, True),
    "albuquerque": (34.7344, -107.0004, 35.4344, -106.3004, True),
}

STATEWIDE = {
    "us-fl": (27.6986 - 6.6047 / 2, -83.8046 - 7.6606 / 2, 27.6986 + 6.6047 / 2, -83.8046 + 7.6606 / 2),
    "us-nm": (34.17 - 5.6681 / 2, -106.03 - 6.0483 / 2, 34.17 + 5.6681 / 2, -106.03 + 6.0483 / 2),
    "us-tx": (31.17 - 10.6636 / 2, -100.08 - 13.1378 / 2, 31.17 + 10.6636 / 2, -100.08 + 13.1378 / 2),
}

AMENITY = (
    "fuel|pharmacy|hospital|clinic|dentist|police|fire_station|post_office|"
    "school|bank|atm|cafe|fast_food|restaurant|bar|pub|toilets|parking|charging_station"
)
TOURISM = "hotel|motel|camp_site|information"
FOOD_KINDS = {"restaurant", "fast_food", "cafe"}
FALLBACK_NAME = {
    "atm": "ATM",
    "toilets": "Toilets",
    "parking": "Parking",
    "charging_station": "Charging station",
    "fuel": "Fuel",
    "spring": "Spring",
    "water": "Drinking water",
    "pharmacy": "Pharmacy",
    "hospital": "Hospital",
    "clinic": "Clinic",
    "police": "Police",
    "fire_station": "Fire station",
    "post_office": "Post office",
    "school": "School",
    "bank": "Bank",
}

SHOP_KIND = {
    "supermarket": "supermarket",
    "convenience": "convenience",
    "mall": "mall",
    "department_store": "mall",
    "hardware": "hardware",
    "doityourself": "hardware",
    "clothes": "clothes",
    "fashion": "clothes",
    "greengrocer": "grocery",
    "grocery": "grocery",
}


def overpass(query: str, timeout: int = 90) -> dict:
    body = urllib.parse.urlencode({"data": query}).encode()
    req = urllib.request.Request(
        OVERPASS,
        data=body,
        method="POST",
        headers={"User-Agent": "BlackoutFieldPackSeed/1.1 (offline pack amenities; ODbL)"},
    )
    last: Exception | None = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode())
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last = exc
            time.sleep(8 * (attempt + 1))
    raise RuntimeError(f"Overpass failed: {last}") from last


def coord(el: dict) -> tuple[float, float] | None:
    if "lat" in el and "lon" in el:
        return float(el["lat"]), float(el["lon"])
    c = el.get("center") or {}
    if "lat" in c and "lon" in c:
        return float(c["lat"]), float(c["lon"])
    return None


def kind_of(tags: dict) -> str | None:
    amenity = tags.get("amenity")
    if amenity == "drinking_water":
        return "water"
    if amenity == "ranger_station":
        return "ranger"
    if amenity in {
        "fuel", "pharmacy", "hospital", "clinic", "dentist", "police", "fire_station",
        "post_office", "school", "bank", "atm", "cafe", "fast_food", "restaurant",
        "bar", "pub", "toilets", "parking", "charging_station",
    }:
        return amenity
    shop = tags.get("shop")
    if shop:
        return SHOP_KIND.get(shop, "shop")
    tourism = tags.get("tourism")
    if tourism in {"hotel", "motel", "camp_site", "information", "guest_house", "hostel"}:
        return "hotel" if tourism in {"guest_house", "hostel"} else tourism
    if tags.get("office"):
        return "office"
    if tags.get("craft"):
        return "craft"
    if tags.get("natural") == "spring":
        return "spring"
    if tags.get("place") == "city":
        return "city"
    if tags.get("place") in {"town", "village"}:
        return "town"
    if tags.get("emergency") == "ranger_station":
        return "ranger"
    if tags.get("man_made") == "watermill" or tags.get("historic") == "mill":
        return "mill"
    if tags.get("railway") in {"station", "halt"}:
        return "rail"
    if tags.get("highway") == "motorway_junction":
        return "road"
    return None


def display_name(tags: dict, kind: str) -> str | None:
    name = (tags.get("name") or tags.get("operator") or tags.get("brand") or "").strip()
    if name:
        return name
    if kind in {"office", "craft", "shop", "restaurant", "cafe", "fast_food", "bar", "pub", "hotel", "motel"}:
        return None
    return FALLBACK_NAME.get(kind)


def queries(bbox: str, nodes_only: bool) -> list[str]:
    nwr = "node" if nodes_only else "nwr"
    out = "out;" if nodes_only else "out center;"
    timeout = 40 if nodes_only else 60
    return [
        f"""
[out:json][timeout:{timeout}];
(
  {nwr}["amenity"~"{AMENITY}"]({bbox});
);
{out}
""",
        f"""
[out:json][timeout:{timeout}];
(
  {nwr}["shop"]({bbox});
  {nwr}["tourism"~"{TOURISM}"]({bbox});
  {nwr}["office"]["name"]({bbox});
  {nwr}["craft"]["name"]({bbox});
);
{out}
""",
        f"""
[out:json][timeout:{timeout}];
(
  {nwr}["natural"="spring"]({bbox});
  {nwr}["amenity"="drinking_water"]({bbox});
  {nwr}["place"~"city|town|village"]({bbox});
  {nwr}["amenity"="ranger_station"]({bbox});
  {nwr}["emergency"="ranger_station"]({bbox});
  {nwr}["man_made"="watermill"]({bbox});
  {nwr}["historic"="mill"]({bbox});
  {nwr}["railway"~"station|halt"]["name"]({bbox});
  {nwr}["highway"="motorway_junction"]["name"]({bbox});
);
{out}
""",
    ]


def collect_pois(
    south: float,
    west: float,
    north: float,
    east: float,
    *,
    nodes_only: bool,
    per_kind: int,
    food_cap: int,
    overall: int,
) -> list[dict]:
    bbox = f"{south},{west},{north},{east}"
    pois: list[dict] = []
    seen: set[str] = set()
    counts: Counter[str] = Counter()
    food = 0
    for query in queries(bbox, nodes_only):
        data = overpass(query)
        time.sleep(2)
        for el in data.get("elements", []):
            tags = el.get("tags") or {}
            kind = kind_of(tags)
            xy = coord(el)
            if not kind or xy is None:
                continue
            name = display_name(tags, kind)
            if not name:
                continue
            pid = f"osm:{el.get('type', 'n')[0]}{el.get('id')}"
            if pid in seen:
                continue
            if kind in FOOD_KINDS:
                if food >= food_cap:
                    continue
            elif counts[kind] >= per_kind:
                continue
            seen.add(pid)
            if kind in FOOD_KINDS:
                food += 1
            counts[kind] += 1
            pois.append(
                {
                    "id": pid,
                    "name": name,
                    "kind": kind,
                    "lat": round(xy[0], 6),
                    "lon": round(xy[1], 6),
                }
            )
            if len(pois) >= overall:
                return pois
    return pois


def write_poi(dest: Path, pois: list[dict]) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "poi.json").write_text(
        json.dumps(
            {
                "schema": 1,
                "attribution": "© OpenStreetMap contributors",
                "pois": pois,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )


def fetch_addresses(south: float, west: float, north: float, east: float) -> list[dict]:
    bbox = f"{south},{west},{north},{east}"
    data = overpass(
        f"""
[out:json][timeout:60];
nwr["addr:housenumber"]["addr:street"]({bbox});
out center 500;
"""
    )
    addrs: list[dict] = []
    seen: set[str] = set()
    for el in data.get("elements", []):
        tags = el.get("tags") or {}
        house = (tags.get("addr:housenumber") or "").strip()
        street = (tags.get("addr:street") or "").strip()
        xy = coord(el)
        if not house or not street or xy is None:
            continue
        aid = f"osm:{el.get('type', 'n')[0]}{el.get('id')}"
        if aid in seen:
            continue
        seen.add(aid)
        addrs.append(
            {
                "id": aid,
                "house": house,
                "street": street,
                "lat": round(xy[0], 6),
                "lon": round(xy[1], 6),
            }
        )
        if len(addrs) >= 500:
            break
    return addrs


def fetch_pack(pack_id: str, south: float, west: float, north: float, east: float, addresses: bool) -> None:
    dest = OUT / pack_id
    pois = collect_pois(
        south, west, north, east,
        nodes_only=False,
        per_kind=40,
        food_cap=90,
        overall=1400,
    )
    write_poi(dest, pois)
    addrs: list[dict] = []
    if addresses:
        addrs = fetch_addresses(south, west, north, east)
        (dest / "address.json").write_text(
            json.dumps(
                {
                    "schema": 1,
                    "attribution": "© OpenStreetMap contributors",
                    "addresses": addrs,
                },
                indent=2,
                ensure_ascii=False,
            )
            + "\n",
            encoding="utf-8",
        )
    kinds = Counter(row["kind"] for row in pois)
    print(f"{pack_id}: {len(pois)} pois, {len(addrs)} addresses, kinds={dict(kinds)}")


def fetch_statewide(pack_id: str, south: float, west: float, north: float, east: float) -> None:
    dest = OUT / pack_id
    pois = collect_pois(
        south, west, north, east,
        nodes_only=True,
        per_kind=20,
        food_cap=50,
        overall=700,
    )
    write_poi(dest, pois)
    kinds = Counter(row["kind"] for row in pois)
    print(f"{pack_id}: {len(pois)} amenity-only, kinds={dict(kinds)}")


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--statewide", action="store_true", help="Also seed FL/TX/NM amenity-only")
    parser.add_argument("packs", nargs="*", help="Pack ids to seed (default: the three cities)")
    args = parser.parse_args()
    if args.statewide and not args.packs:
        wanted = list(STATEWIDE)
    else:
        wanted = args.packs or list(PACKS)
    for pack_id in wanted:
        if pack_id in PACKS:
            south, west, north, east, addrs = PACKS[pack_id]
            fetch_pack(pack_id, south, west, north, east, addrs)
        elif pack_id in STATEWIDE:
            fetch_statewide(pack_id, *STATEWIDE[pack_id])
        else:
            raise SystemExit(f"unknown pack {pack_id}")


if __name__ == "__main__":
    main()
