"""TIGER/Line ADDRFEAT ranges for MAP SEARCH.

Named OSM docs stay in `search.json` as they are. Addresses are ranges, not
every door. A house number plus a street interpolates along the census
segment that owns that parity.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
import zipfile
from math import asin, cos, isfinite, radians, sin, sqrt
from pathlib import Path
from typing import Any, Iterable

from shapely.geometry import LineString, box

from .common import ROOT

TIGER_YEAR = 2024
TIGER_URL = "https://www2.census.gov/geo/tiger/TIGER{year}/ADDRFEAT/tl_{year}_{fips}_addrfeat.zip"
CACHE = Path("/tmp/cursor/tiger-addrfeat")
SCALE = 100_000

ORDINAL_SUFFIXES = {"th", "st", "nd", "rd"}

ALIASES: dict[str, set[str]] = {
    "ave": {"ave", "avenue", "av", "avenida"},
    "avenue": {"ave", "avenue", "av", "avenida"},
    "av": {"ave", "avenue", "av", "avenida"},
    "avenida": {"ave", "avenue", "av", "avenida"},
    "st": {"st", "street"},
    "street": {"st", "street"},
    "rd": {"rd", "road"},
    "road": {"rd", "road"},
    "blvd": {"blvd", "boulevard"},
    "boulevard": {"blvd", "boulevard"},
    "dr": {"dr", "drive"},
    "drive": {"dr", "drive"},
    "ln": {"ln", "lane"},
    "lane": {"ln", "lane"},
    "hwy": {"hwy", "highway"},
    "highway": {"hwy", "highway"},
    "pkwy": {"pkwy", "parkway"},
    "parkway": {"pkwy", "parkway"},
    "ct": {"ct", "court"},
    "court": {"ct", "court"},
    "cir": {"cir", "circle"},
    "circle": {"cir", "circle"},
    "pl": {"pl", "place"},
    "place": {"pl", "place"},
    "n": {"n", "north"},
    "north": {"n", "north"},
    "s": {"s", "south"},
    "south": {"s", "south"},
    "e": {"e", "east"},
    "east": {"e", "east"},
    "w": {"w", "west"},
    "west": {"w", "west"},
}

ZIP3_CITY = {
    "765": "Temple",
    "786": "Austin",
    "787": "Austin",
    "789": "Giddings",
    "798": "Sierra Blanca",
    "799": "El Paso",
    "870": "Bernalillo",
    "871": "Albuquerque",
    "873": "Gallup",
    "875": "Santa Fe",
    "877": "Las Vegas",
    "878": "Socorro",
    "879": "Truth or Consequences",
    "880": "Las Cruces",
    "881": "Clovis",
    "883": "Alamogordo",
}

PACK_FIPS: dict[str, tuple[str, ...]] = {
    "tx-west": (
        "48141",
        "48229",
        "48109",
        "35013",
        "35035",
        "35029",
        "35051",
    ),
    "tx-east": (
        "48453",
        "48491",
        "48021",
        "48209",
        "48055",
    ),
    "nm": (
        "35001",
        "35043",
        "35049",
        "35061",
        "35006",
        "35057",
        "35028",
        "35039",
        "35053",
        "35019",
        "35047",
    ),
}


def tokens(raw: str) -> list[str]:
    folded = raw.casefold()
    words: list[str] = []
    current: list[str] = []
    for ch in folded:
        if ch.isalnum():
            current.append(ch)
        elif current:
            words.append("".join(current))
            current = []
    if current:
        words.append("".join(current))
    return words


def house_query(raw: str) -> tuple[int, list[str]] | None:
    toks = tokens(raw)
    if not toks:
        return None
    first = toks[0]
    i = 0
    while i < len(first) and first[i].isdigit():
        i += 1
    if i == 0:
        return None
    rest = first[i:]
    if rest in ORDINAL_SUFFIXES:
        return None
    if rest and not rest.isalpha():
        return None
    street = toks[1:]
    if not street:
        return None
    return int(first[:i]), street


def hn_on_range(hn: int, from_hn: int, to_hn: int) -> bool:
    lo, hi = (from_hn, to_hn) if from_hn <= to_hn else (to_hn, from_hn)
    if hn < lo or hn > hi:
        return False
    if from_hn % 2 == to_hn % 2:
        return hn % 2 == from_hn % 2
    return True


def interpolate(
    hn: int,
    from_hn: int,
    to_hn: int,
    lat0: float,
    lon0: float,
    lat1: float,
    lon1: float,
) -> tuple[float, float]:
    span = to_hn - from_hn
    if span == 0:
        return lat0, lon0
    frac = (hn - from_hn) / span
    return lat0 + frac * (lat1 - lat0), lon0 + frac * (lon1 - lon0)


def city_for_zip(zipcode: str) -> str:
    digits = "".join(ch for ch in str(zipcode) if ch.isdigit())
    if len(digits) < 3:
        return ""
    return ZIP3_CITY.get(digits[:3], "")


def aliases_of(token: str) -> set[str]:
    return set(ALIASES.get(token, {token}))


def token_hits(query: str, street_tokens: list[str]) -> bool:
    want = aliases_of(query)
    for tok in street_tokens:
        if tok in want or query in aliases_of(tok):
            return True
    if len(query) >= 3:
        for tok in street_tokens:
            if tok.startswith(query):
                return True
    return False


def street_matches(query_tokens: list[str], street: str) -> bool:
    street_tokens = tokens(street)
    return all(token_hits(q, street_tokens) for q in query_tokens)


def _e5(value: float) -> int:
    return int(round(value * SCALE))


def _from_e5(value: float) -> float:
    if abs(value) > 1000:
        return value / SCALE
    return float(value)


def parse_hn(raw: Any) -> int | None:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text or text in {"0", "None", "none"}:
        return None
    i = 0
    while i < len(text) and text[i].isdigit():
        i += 1
    if i == 0:
        return None
    return int(text[:i])


_TYPE_TOKENS: set[str] = set()
for _group in ALIASES.values():
    _TYPE_TOKENS |= set(_group)


def content_penalty(street: str, query_tokens: list[str]) -> int:
    leftover = 0
    for tok in tokens(street):
        if tok in _TYPE_TOKENS:
            continue
        if any(token_hits(q, [tok]) for q in query_tokens):
            continue
        leftover += 1
    return leftover


class AddressBook:
    def __init__(self, rows: list[dict[str, Any]]):
        self.rows = rows
        self.freq: dict[str, int] = {}
        lat_sum: dict[str, float] = {}
        lon_sum: dict[str, float] = {}
        for row in rows:
            street = str(row.get("street") or "")
            self.freq[street] = self.freq.get(street, 0) + 1
            lat_sum[street] = lat_sum.get(street, 0.0) + (float(row["lat0"]) + float(row["lat1"])) / 2
            lon_sum[street] = lon_sum.get(street, 0.0) + (float(row["lon0"]) + float(row["lon1"])) / 2
        self.center = {
            street: (lat_sum[street] / n, lon_sum[street] / n)
            for street, n in self.freq.items()
            if n
        }

    @classmethod
    def from_ranges(cls, rows: Iterable[dict[str, Any]]) -> AddressBook:
        return cls(list(rows))

    @classmethod
    def from_packed(cls, blob: dict[str, Any]) -> AddressBook:
        addr = blob.get("addr") or {}
        streets = list(addr.get("streets") or [])
        zips = list(addr.get("zips") or [])
        rows: list[dict[str, Any]] = []
        for raw in addr.get("ranges") or []:
            if not isinstance(raw, list) or len(raw) < 8:
                continue
            si, from_hn, to_hn, zi = int(raw[0]), int(raw[1]), int(raw[2]), int(raw[3])
            if si < 0 or si >= len(streets):
                continue
            zipcode = zips[zi] if 0 <= zi < len(zips) else ""
            rows.append(
                {
                    "street": streets[si],
                    "from_hn": from_hn,
                    "to_hn": to_hn,
                    "zipcode": zipcode,
                    "lat0": _from_e5(float(raw[4])),
                    "lon0": _from_e5(float(raw[5])),
                    "lat1": _from_e5(float(raw[6])),
                    "lon1": _from_e5(float(raw[7])),
                }
            )
        return cls(rows)

    def geocode(
        self,
        query: str,
        you: tuple[float, float] | None = None,
    ) -> dict[str, Any] | None:
        asked = house_query(query)
        if asked is None:
            return None
        hn, street_tokens = asked
        if street_tokens and all(tok in _TYPE_TOKENS for tok in street_tokens):
            return None
        hits: list[dict[str, Any]] = []
        for row in self.rows:
            street = str(row.get("street") or "")
            if not street_matches(street_tokens, street):
                continue
            from_hn = int(row["from_hn"])
            to_hn = int(row["to_hn"])
            if not hn_on_range(hn, from_hn, to_hn):
                continue
            lat, lon = interpolate(
                hn,
                from_hn,
                to_hn,
                float(row["lat0"]),
                float(row["lon0"]),
                float(row["lat1"]),
                float(row["lon1"]),
            )
            if not isfinite(lat) or not isfinite(lon):
                continue
            zipcode = str(row.get("zipcode") or "")
            span = abs(to_hn - from_hn)
            meters = 0.0
            if you is not None:
                meters = _haversine(you[0], you[1], lat, lon)
            center = self.center.get(street, (lat, lon))
            center_m = _haversine(center[0], center[1], lat, lon)
            hits.append(
                {
                    "name": f"{hn} {street}",
                    "kind": "address",
                    "lat": lat,
                    "lon": lon,
                    "post": zipcode,
                    "city": city_for_zip(zipcode),
                    "sure": 72,
                    "why": f"census range {from_hn}–{to_hn}",
                    "what": f"door on {street}",
                    "span": span,
                    "meters": meters,
                    "penalty": content_penalty(street, street_tokens),
                    "freq": -self.freq.get(street, 0),
                    "center_m": center_m,
                }
            )
        if not hits:
            return None
        if you is not None:
            hits.sort(key=lambda h: (h["meters"], h["penalty"], h["span"], h["name"]))
        else:
            hits.sort(key=lambda h: (h["penalty"], h["freq"], h["center_m"], h["span"], h["name"]))
        return hits[0]


def _haversine(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    r = 6_371_000.0
    p1, p2 = radians(a_lat), radians(b_lat)
    dp = radians(b_lat - a_lat)
    dl = radians(b_lon - a_lon)
    h = sin(dp / 2) ** 2 + cos(p1) * cos(p2) * sin(dl / 2) ** 2
    return 2 * r * asin(min(1.0, sqrt(h)))


def pack_bbox(pack_id: str) -> tuple[float, float, float, float]:
    manifest = json.loads(
        (ROOT / "Resources" / "Packs" / pack_id / "manifest.json").read_text()
    )
    bbox = manifest["bbox"]
    return (
        float(bbox["south"]),
        float(bbox["west"]),
        float(bbox["north"]),
        float(bbox["east"]),
    )


def _download(url: str, dest: Path, tries: int = 5) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    delay = 4.0
    last_error: Exception | None = None
    for attempt in range(tries):
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "BlackoutPackBuilder/0.1 (offline map addresses)"},
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                dest.write_bytes(resp.read())
            if dest.stat().st_size > 64:
                return
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last_error = exc
            time.sleep(delay)
            delay *= 2
            continue
    raise RuntimeError(f"download failed {url}: {last_error}")


def tiger_zip(fips: str) -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    zpath = CACHE / f"tl_{TIGER_YEAR}_{fips}_addrfeat.zip"
    if zpath.exists() and zpath.stat().st_size > 64:
        return zpath
    url = TIGER_URL.format(year=TIGER_YEAR, fips=fips)
    _download(url, zpath)
    return zpath


def _extract_shp(zpath: Path, fips: str) -> Path:
    folder = CACHE / f"tl_{TIGER_YEAR}_{fips}_addrfeat"
    shp = folder / f"tl_{TIGER_YEAR}_{fips}_addrfeat.shp"
    if shp.exists():
        return shp
    folder.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zpath) as zf:
        zf.extractall(folder)
    if not shp.exists():
        raise FileNotFoundError(shp)
    return shp


def _line_ends(points: list[tuple[float, float]], bbox: tuple[float, float, float, float]):
    south, west, north, east = bbox
    if len(points) < 2:
        return None
    pack = box(west, south, east, north)
    line = LineString(points)
    if line.is_empty or not line.intersects(pack):
        return None
    clipped = line.intersection(pack)
    pieces: list[LineString] = []
    if clipped.geom_type == "LineString":
        pieces = [clipped]
    elif clipped.geom_type == "MultiLineString":
        pieces = [g for g in clipped.geoms if g.geom_type == "LineString"]
    elif clipped.geom_type == "GeometryCollection":
        pieces = [g for g in clipped.geoms if g.geom_type == "LineString"]
    if not pieces:
        return None
    longest = max(pieces, key=lambda g: g.length)
    coords = list(longest.coords)
    if len(coords) < 2:
        return None
    return (coords[0][0], coords[0][1]), (coords[-1][0], coords[-1][1])


def _envelope_overlaps(shape_bbox: list[float], pack: tuple[float, float, float, float]) -> bool:
    minx, miny, maxx, maxy = shape_bbox
    south, west, north, east = pack
    return not (maxx < west or minx > east or maxy < south or miny > north)


def ranges_from_shapefile(
    shp: Path, pack: tuple[float, float, float, float]
) -> list[tuple[str, int, int, str, float, float, float, float]]:
    import shapefile

    out: list[tuple[str, int, int, str, float, float, float, float]] = []
    with shapefile.Reader(str(shp)) as reader:
        fields = [f[0] for f in reader.fields[1:]]
        for sr in reader.iterShapeRecords():
            shape = sr.shape
            if not shape.points or not shape.bbox:
                continue
            if not _envelope_overlaps(list(shape.bbox), pack):
                continue
            rec = dict(zip(fields, sr.record))
            name = str(rec.get("FULLNAME") or "").strip()
            if not name:
                continue
            ends = _line_ends([(float(x), float(y)) for x, y in shape.points], pack)
            if ends is None:
                continue
            (lon0, lat0), (lon1, lat1) = ends
            for from_key, to_key, zip_key in (
                ("LFROMHN", "LTOHN", "ZIPL"),
                ("RFROMHN", "RTOHN", "ZIPR"),
            ):
                from_hn = parse_hn(rec.get(from_key))
                to_hn = parse_hn(rec.get(to_key))
                if from_hn is None or to_hn is None:
                    continue
                zipcode = "".join(ch for ch in str(rec.get(zip_key) or "") if ch.isdigit())
                if len(zipcode) > 5:
                    zipcode = zipcode[:5]
                out.append((name, from_hn, to_hn, zipcode, lat0, lon0, lat1, lon1))
    return out


def build_addr(bbox: tuple[float, float, float, float], fips_list: Iterable[str]) -> dict[str, Any]:
    streets: list[str] = []
    street_index: dict[str, int] = {}
    zips: list[str] = []
    zip_index: dict[str, int] = {}
    packed: list[list[int]] = []
    seen: set[tuple[int, int, int, int, int, int, int, int]] = set()

    def intern(table: list[str], index: dict[str, int], value: str) -> int:
        if value in index:
            return index[value]
        idx = len(table)
        index[value] = idx
        table.append(value)
        return idx

    for fips in fips_list:
        zpath = tiger_zip(fips)
        shp = _extract_shp(zpath, fips)
        for street, from_hn, to_hn, zipcode, lat0, lon0, lat1, lon1 in ranges_from_shapefile(shp, bbox):
            si = intern(streets, street_index, street)
            zi = intern(zips, zip_index, zipcode)
            row = [
                si,
                from_hn,
                to_hn,
                zi,
                _e5(lat0),
                _e5(lon0),
                _e5(lat1),
                _e5(lon1),
            ]
            key = tuple(row)
            if key in seen:
                continue
            seen.add(key)
            packed.append(row)
    return {"streets": streets, "zips": zips, "ranges": packed}


def merge_into_search(path: Path, bbox: tuple[float, float, float, float], fips_list: Iterable[str]) -> Path:
    blob = json.loads(path.read_text(encoding="utf-8"))
    blob["addr"] = build_addr(bbox, fips_list)
    path.write_text(json.dumps(blob, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    return path


def attach_addr(dest: Path) -> Path:
    pack_id = dest.name
    fips = PACK_FIPS.get(pack_id)
    if not fips:
        return dest / "search.json"
    path = dest / "search.json"
    if not path.exists():
        return path
    return merge_into_search(path, pack_bbox(pack_id), fips)


def rebuild_all() -> None:
    for pack_id in PACK_FIPS:
        dest = ROOT / "Resources" / "Packs" / pack_id
        print(f"addrfeat {pack_id}", flush=True)
        attach_addr(dest)
        blob = json.loads((dest / "search.json").read_text())
        ranges = (blob.get("addr") or {}).get("ranges") or []
        streets = (blob.get("addr") or {}).get("streets") or []
        print(f"  ranges={len(ranges)} streets={len(streets)}", flush=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", choices=sorted(PACK_FIPS), action="append")
    args = parser.parse_args(argv)
    packs = args.pack or list(PACK_FIPS)
    for pack_id in packs:
        print(f"addrfeat {pack_id}", flush=True)
        attach_addr(ROOT / "Resources" / "Packs" / pack_id)
        blob = json.loads((ROOT / "Resources" / "Packs" / pack_id / "search.json").read_text())
        ranges = (blob.get("addr") or {}).get("ranges") or []
        streets = (blob.get("addr") or {}).get("streets") or []
        print(f"  ranges={len(ranges)} streets={len(streets)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
