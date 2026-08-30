#!/usr/bin/env python3
"""Fetch compact OSM amenity/address JSON for Field Packs. No PBF in git.

Writes tools/fieldpack_poi/<id>/{poi,address}.json for later zip publish.
Does not copy into the IPA. Update maps still replaces the pack zip.
"""
from __future__ import annotations

import json
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tools" / "fieldpack_poi"
OVERPASS = "https://overpass-api.de/api/interpreter"

# Catalog bboxes (center ± span/2) from FieldPackCatalog.
PACKS = {
    "el-paso": (31.3619, -106.885, 32.1619, -106.085, True),
    "las-cruces": (31.9699, -107.1137, 32.6699, -106.4137, True),
    "albuquerque": (34.7344, -107.0004, 35.4344, -106.3004, True),
}

AMENITY = "restaurant|cafe|fuel|hospital|bar"
SHOP = "supermarket|convenience|bakery"
TOURISM = "hotel|motel"
KIND = {
    "restaurant": "restaurant",
    "cafe": "cafe",
    "fuel": "fuel",
    "hospital": "hospital",
    "bar": "bar",
    "supermarket": "grocery",
    "convenience": "shop",
    "bakery": "shop",
    "hotel": "lodging",
    "motel": "lodging",
}


def overpass(query: str) -> dict:
    body = urllib.parse.urlencode({"data": query}).encode()
    req = urllib.request.Request(
        OVERPASS,
        data=body,
        method="POST",
        headers={"User-Agent": "BlackoutFieldPackSeed/1.0 (offline pack amenities)"},
    )
    with urllib.request.urlopen(req, timeout=90) as resp:
        return json.loads(resp.read().decode())


def coord(el: dict) -> tuple[float, float] | None:
    if "lat" in el and "lon" in el:
        return float(el["lat"]), float(el["lon"])
    c = el.get("center") or {}
    if "lat" in c and "lon" in c:
        return float(c["lat"]), float(c["lon"])
    return None


def kind_of(tags: dict) -> str | None:
    for key in ("amenity", "shop", "tourism"):
        raw = tags.get(key)
        if raw in KIND:
            return KIND[raw]
    return None


def fetch_pack(pack_id: str, south: float, west: float, north: float, east: float, addresses: bool) -> None:
    bbox = f"{south},{west},{north},{east}"
    amenity_q = f"""
[out:json][timeout:60];
(
  nwr["amenity"~"{AMENITY}"]({bbox});
  nwr["shop"~"{SHOP}"]({bbox});
  nwr["tourism"~"{TOURISM}"]({bbox});
);
out center 400;
"""
    dest = OUT / pack_id
    dest.mkdir(parents=True, exist_ok=True)
    pois = []
    seen = set()
    data = overpass(amenity_q)
    for el in data.get("elements", []):
        tags = el.get("tags") or {}
        name = (tags.get("name") or "").strip()
        kind = kind_of(tags)
        xy = coord(el)
        if not name or not kind or xy is None:
            continue
        pid = f"osm:{el.get('type', 'n')[0]}{el.get('id')}"
        if pid in seen:
            continue
        seen.add(pid)
        pois.append({"id": pid, "name": name, "kind": kind, "lat": round(xy[0], 6), "lon": round(xy[1], 6)})
        if len(pois) >= 400:
            break
    (dest / "poi.json").write_text(
        json.dumps(
            {
                "schema": 1,
                "attribution": "© OpenStreetMap contributors",
                "pois": pois,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    addrs = []
    if addresses:
        addr_q = f"""
[out:json][timeout:60];
nwr["addr:housenumber"]["addr:street"]({bbox});
out center 500;
"""
        adata = overpass(addr_q)
        aseen = set()
        for el in adata.get("elements", []):
            tags = el.get("tags") or {}
            house = (tags.get("addr:housenumber") or "").strip()
            street = (tags.get("addr:street") or "").strip()
            xy = coord(el)
            if not house or not street or xy is None:
                continue
            aid = f"osm:{el.get('type', 'n')[0]}{el.get('id')}"
            if aid in aseen:
                continue
            aseen.add(aid)
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
        (dest / "address.json").write_text(
            json.dumps(
                {
                    "schema": 1,
                    "attribution": "© OpenStreetMap contributors",
                    "addresses": addrs,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
    print(f"{pack_id}: {len(pois)} amenities, {len(addrs)} addresses")


def main() -> None:
    for pack_id, (south, west, north, east, addrs) in PACKS.items():
        fetch_pack(pack_id, south, west, north, east, addrs)


if __name__ == "__main__":
    main()
