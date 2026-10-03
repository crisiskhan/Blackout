#!/usr/bin/env python3
"""Every pack camera is a red/blue disc. EXPEDITION TV is SNAP stills.

Packs populate on open. Hop cameras use the same disc and the same SNAP
rules. TV is TRAFFIC / BRIDGE / AIRPORT / VENUE / HOP, nearest to farthest
inside each section. Empty sections omit. Open sections never a live
stream — JPEG SNAP only. N/A is a 10s hold, then adult HTTPS HLS.
Tap a still to pinch-zoom the packed JPEG.
"""
from __future__ import annotations

import json
import math
import re
import sys
import unittest
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

KINDS = ("TRAFFIC", "BRIDGE", "AIRPORT", "VENUE", "N/A", "HOP")
NA_HOLD_SECONDS = 10


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


def _finite(value: object) -> bool:
    return isinstance(value, (int, float)) and math.isfinite(value)


def haversine_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lon1 = map(math.radians, a)
    lat2, lon2 = map(math.radians, b)
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371000.0 * 2 * math.asin(math.sqrt(h))


def tv_rows(
    pack: list[dict], hops: list[dict], lat: float, lon: float
) -> list[dict]:
    """Every reachable camera, pack first on a shared id, nearest to farthest."""
    by_id: dict[str, dict] = {}
    for cam in pack:
        cid = str(cam.get("id") or "").strip()
        if not cid or not _finite(cam.get("lat")) or not _finite(cam.get("lon")):
            continue
        by_id[cid] = cam
    packed = set(by_id)
    seen: set[str] = set()
    for cam in hops:
        cid = str(cam.get("id") or "").strip()
        if not cid or cid in packed or cid in seen:
            continue
        if not _finite(cam.get("lat")) or not _finite(cam.get("lon")):
            continue
        seen.add(cid)
        row = dict(cam)
        if not str(row.get("provider") or "").strip():
            row["provider"] = "HOP"
        by_id[cid] = row
    return sorted(
        by_id.values(),
        key=lambda cam: haversine_m((lat, lon), (float(cam["lat"]), float(cam["lon"]))),
    )


def section(cam: dict) -> str:
    """HOP first. BOTA / PASO DEL NORTE are BRIDGE. AIRPORT is AIRPORT.

    Zaragoza street cams and Paseo Del Norte stay TRAFFIC. VENUE is reserved.
    N/A is provider N/A only — never a street name. Open sections omit N/A.
    """
    provider = str(cam.get("provider") or "").strip().upper()
    if provider == "HOP":
        return "HOP"
    if provider in ("N/A", "NA"):
        return "N/A"
    name = str(cam.get("name") or "").strip().upper()
    if not name:
        name = str(cam.get("id") or "").strip().upper()
    if "BOTA" in name or "PASO DEL NORTE" in name:
        return "BRIDGE"
    if "AIRPORT" in name:
        return "AIRPORT"
    return "TRAFFIC"


def sectioned(
    pack: list[dict], hops: list[dict], lat: float, lon: float
) -> list[tuple[str, list[dict]]]:
    buckets: dict[str, list[dict]] = {kind: [] for kind in KINDS}
    for row in tv_rows(pack, hops, lat, lon):
        buckets[section(row)].append(row)
    return [
        (kind, buckets[kind])
        for kind in KINDS
        if kind != "N/A" and buckets[kind]
    ]


def na_rows(pack: list[dict], hops: list[dict], lat: float, lon: float) -> list[dict]:
    return [row for row in tv_rows(pack, hops, lat, lon) if section(row) == "N/A"]


def na_unlocks(elapsed: float) -> bool:
    return elapsed >= NA_HOLD_SECONDS


ADULT_CAP = 800
ADULT_SCREEN = 8
ADULT_BLOCKED = (
    "teen",
    "underage",
    "child",
    "loli",
    "shota",
    "jailbait",
    "preteen",
    "pedo",
    "minor",
    "under18",
    "younggirl",
    "trans",
    "shemale",
    "ladyboy",
    "tgirl",
)
ADULT_KIND_WORDS = (
    ("new", "NEW"),
    ("dance", "DANCE"),
    ("blonde", "BLONDE"),
    ("brunette", "BRUNETTE"),
    ("redhead", "REDHEAD"),
    ("asian", "ASIAN"),
    ("latina", "LATINA"),
    ("ebony", "EBONY"),
    ("milf", "MILF"),
    ("petite", "PETITE"),
    ("curvy", "CURVY"),
    ("outdoor", "OUTDOOR"),
    ("toys", "TOYS"),
    ("squirt", "SQUIRT"),
    ("anal", "ANAL"),
    ("lesbian", "LESBIAN"),
    ("couple", "COUPLE"),
    ("orgy", "ORGY"),
    ("gangbang", "ORGY"),
    ("threesome", "ORGY"),
    ("fff", "ORGY"),
    ("ffm", "ORGY"),
    ("group sex", "ORGY"),
    ("roleplay", "ROLEPLAY"),
    ("role-play", "ROLEPLAY"),
    ("role play", "ROLEPLAY"),
    ("roleplaying", "ROLEPLAY"),
    ("cosplay", "ROLEPLAY"),
    ("bdsm", "BDSM"),
    ("fetish", "FETISH"),
    ("bondage", "BDSM"),
    ("femdom", "BDSM"),
    ("oral", "ORAL"),
    ("blowjob", "ORAL"),
    ("deepthroat", "ORAL"),
    ("cuckold", "CUCKOLD"),
    ("shower", "SHOWER"),
    ("feet", "FEET"),
    ("smoking", "SMOKE"),
    ("lovense", "TOYS"),
    ("dildo", "TOYS"),
    ("masturbat", "SOLO"),
    ("braid", "BRAIDS"),
    ("cornrow", "BRAIDS"),
    ("sleep", "SLEEP"),
    ("asleep", "SLEEP"),
    ("somno", "SLEEP"),
    ("robbery", "ROBBERY"),
    ("robber", "ROBBERY"),
    ("burglar", "ROBBERY"),
    ("forced", "FORCED"),
    ("cnc", "FORCED"),
    ("noncon", "FORCED"),
    ("non-con", "FORCED"),
    ("pawn", "PAWN"),
    ("thief", "THIEF"),
    ("caught", "THIEF"),
    ("freeuse", "FREEUSE"),
    ("kidnap", "KIDNAP"),
    ("cop", "COP"),
    ("police", "COP"),
    ("maid", "MAID"),
    ("nurse", "NURSE"),
    ("hypno", "HYPNO"),
    ("cheating", "CHEAT"),
    ("hotwife", "CHEAT"),
    ("teacher", "TEACHER"),
    ("favor", "FAVORS"),
    ("favour", "FAVORS"),
    ("hostage", "HOSTAGE"),
    ("blackmail", "BLACKMAIL"),
    ("burglary", "ROBBERY"),
    ("invasion", "INVASION"),
    ("fulani", "BRAIDS"),
    ("knotless", "BRAIDS"),
    ("free use", "FREEUSE"),
    ("somnophilia", "SLEEP"),
)
ADULT_PIN = (
    "COUPLE",
    "ORGY",
    "ROLEPLAY",
    "BRAIDS",
    "SLEEP",
    "ROBBERY",
    "FORCED",
    "PAWN",
    "THIEF",
    "FAVORS",
)
ADULT_STEPH = (
    "itsstephhoneyxo21",
    "itsstephhoney xo21",
    "itsstephhoneyxo",
    "itsstephhoney xo",
    "stephhoneyxo21",
    "itsstephhoney21",
    "itsstephhoney",
    "stephhoney21",
    "stephhoney",
    "its steph honey",
    "steph honey 21",
    "stephaniehvip",
    "itsstephhoney21free",
)
ADULT_MULAN = (
    "mulanvuitton",
    "mulan_vuitton",
    "mulan-vuitton",
    "mulan vuitton",
    "mulanvuittontv",
    "mulan vuittontv",
    "mulan vuitton tv",
    "mulan.vuitton",
    "vuitton mulan",
)
ADULT_MIKEILA = (
    "mikeilaj",
    "mikeila j",
    "mikeila_j",
    "mikeila-j",
    "mikeila.j",
    "mikeila j.",
    "mikeilajbaee",
    "mikeilajduhh",
    "theemikeilaj",
    "mikeilaj duhh",
    "mikeilaj baee",
)
ADULT_BEILA = (
    "nerdybeila",
    "nerdy beila",
    "nerdy_beila",
    "nerdy-beila",
    "nerdy.beila",
    "beila nerdy",
    "beila b",
    "vip.nerdyb",
    "vip nerdyb",
    "vipnerdyb",
    "beila_cosplay",
    "beila cosplay",
)
ADULT_JUICY = (
    "juicyjastv",
    "juicyjas.tv",
    "juicy jas tv",
    "juicyjas tv",
    "juicyjas",
)
ADULT_HONEYTEA = (
    "honeyteassee",
    "honey teassee",
)
ADULT_TANIA = (
    "taniaaaramos",
    "taniaaa ramos",
    "taniaa ramos",
)
ADULT_BRITTANYA = (
    "brittanya razavi",
    "brittanyarazavi",
    "brittanya_razavi",
    "brittanya-razavi",
    "seebrittanya",
    "brittanya2horny",
    "britt2legitt",
    "brittanya187187",
)
ADULT_LEXI = (
    "hot4lexi",
    "hot 4 lexi",
    "hott4lexi",
    "hotforlexi",
    "lexi2legit",
)
ADULT_LILI = (
    "lilivictoria32",
    "lili victoria 32",
    "lilivictoria",
    "lili victoria",
)
ADULT_ZURI = (
    "zuribellarose",
    "zuri bella rose",
    "zuri_bella_rose",
    "zuri-bella-rose",
)
ADULT_SARII = (
    "officialsariixo",
    "sariixo",
    "sarii xo",
    "sarii.xo",
    "official sariixo",
)
ADULT_MONA = (
    "monaacutee",
    "mona acutee",
    "monaacute",
)
ADULT_HIZ = (
    "imhizbaeexx",
    "imhizbaeexx_",
    "hizbaeexx",
)
ADULT_YESS = (
    "yess_enia69",
    "yessenia69",
    "yess enia69",
)
ADULT_VAL = (
    "val2yummi",
    "val 2 yummi",
    "val2yummy",
)
ADULT_KIRA = (
    "kirawrrra",
    "kirawrrra2",
    "kirawrrra2.0",
    "kirawrrra 2",
)
ADULT_JACQIE = (
    "jacqievains",
    "jacqie vains",
    "jackie vains",
)
ADULT_LILIANA = (
    "lilianaspage",
    "lilianas page",
)
ADULT_FREAKYY = (
    "freakyystackss",
    "freakyy stackss",
    "freakyystacks",
)
ADULT_ASAIA = (
    "asaia_hernandez",
    "asaia hernandez",
    "asaiahernandez",
)
ADULT_JASMINEGTV = (
    "jasminegtv1",
    "jasminegtv",
    "jasmine gtv",
)
ADULT_JESSY = (
    "imangeljessyy",
    "imangeljessy",
    "angeljessyy",
)
ADULT_GRACIE = (
    "itsgraciebonn",
    "gracie bonn",
    "graciebonn",
)
ADULT_DEB = (
    "debvarela",
    "deb varela",
    "debvarela_",
)
ADULT_DOSE = (
    "doubledosetwins",
    "double dose twins",
    "doubledose twins",
)
ADULT_PAMELA = (
    "pamelayamz",
    "pamela yamz",
)
ADULT_ANNABELLE = (
    "annabelleriossss",
    "annabelle rios",
    "annabellerios",
)
ADULT_NICOLE = (
    "nicoleee1329",
    "_nicoleee_1329",
    "nicoleee 1329",
)
ADULT_EUNICE = (
    "euniceg",
    "euniceg___",
)
ADULT_SANDRA = (
    "strawberrysandra20",
    "strawberry sandra",
    "strawberrysandra",
)
ADULT_FACES = (
    ("ITSSTEPHHONEY21", ADULT_STEPH),
    ("ITSSTEPHHONEYXO21", ADULT_STEPH),
    ("MULAN VUITTON", ADULT_MULAN),
    ("MIKEILA J", ADULT_MIKEILA),
    ("NERDY BEILA", ADULT_BEILA),
    ("JUICYJAS TV", ADULT_JUICY),
    ("HONEYTEASSEE", ADULT_HONEYTEA),
    ("TANIA RAMOS", ADULT_TANIA),
    ("BRITTANYA RAZAVI", ADULT_BRITTANYA),
    ("HOT4LEXI", ADULT_LEXI),
    ("LILI VICTORIA", ADULT_LILI),
    ("ZURI BELLA ROSE", ADULT_ZURI),
    ("SARIIXO", ADULT_SARII),
    ("MONA ACUTEE", ADULT_MONA),
    ("IMHIZBAEEXX", ADULT_HIZ),
    ("YESS ENIA69", ADULT_YESS),
    ("VAL2YUMMI", ADULT_VAL),
    ("KIRAWWRRRA", ADULT_KIRA),
    ("JACQIE VAINS", ADULT_JACQIE),
    ("LILIANAS PAGE", ADULT_LILIANA),
    ("FREAKYYSTACKSS", ADULT_FREAKYY),
    ("ASAIA HERNANDEZ", ADULT_ASAIA),
    ("JASMINEGTV", ADULT_JASMINEGTV),
    ("IMANGELJESSYY", ADULT_JESSY),
    ("GRACIE BONN", ADULT_GRACIE),
    ("DEBVARELA", ADULT_DEB),
    ("DOUBLE DOSE TWINS", ADULT_DOSE),
    ("PAMELA YAMZ", ADULT_PAMELA),
    ("ANNABELLE RIOS", ADULT_ANNABELLE),
    ("NICOLEEE 1329", ADULT_NICOLE),
    ("EUNICEG", ADULT_EUNICE),
    ("STRAWBERRY SANDRA", ADULT_SANDRA),
)
ADULT_LOVE_CHIP = "LOVESCAPE"
ADULT_LOVE_ORIGIN = "https://lovescape.cam"
ADULT_LOVE_TAGS = ("girls", "couples")
ADULT_RAIL_EXTRA = 8
ADULT_HUNT_AT_ONCE = 4
ADULT_HUNT_PAGES = 2
ADULT_HUNT_CAP = 48
ADULT_COUNT_CAP = 1_000_000_000
ADULT_TOPIC = {
    "BRAIDS": ("braids", "braid", "cornrows"),
    "SLEEP": ("sleeping", "sleep", "somno"),
    "ROBBERY": ("robbery", "robber"),
    "FORCED": ("cnc", "forced", "noncon"),
    "PAWN": ("pawn", "pawnshop"),
    "THIEF": ("thief", "caught"),
    "FAVORS": ("favors", "favour"),
    "FREEUSE": ("freeuse",),
    "KIDNAP": ("kidnap",),
    "COP": ("cop", "police"),
    "MAID": ("maid",),
    "NURSE": ("nurse",),
    "HYPNO": ("hypno",),
    "CHEAT": ("cheating", "hotwife"),
    "TEACHER": ("teacher",),
    "HOSTAGE": ("hostage",),
    "BLACKMAIL": ("blackmail",),
    "INVASION": ("invasion",),
    "ROLEPLAY": ("roleplay", "cosplay"),
    "ORGY": ("orgy", "gangbang", "threesome"),
    "COUPLE": ("couple",),
}
ADULT_MALE = {
    "m",
    "male",
    "s",
    "trans",
    "shemale",
    "tgirl",
    "transgender",
    "transsexual",
    "ts",
}
ADULT_COUPLE = {"c", "couple", "couples"}
ADULT_WOMAN = {
    "f",
    "female",
    "females",
    "w",
    "woman",
    "women",
    "malefemale",
    "girl",
    "girls",
} | ADULT_COUPLE


def adult_playlist(raw: str) -> str | None:
    """HTTPS HLS only. Refuse guest advert / preview clips."""
    text = str(raw or "").strip()
    if not text.lower().startswith("https://"):
        return None
    low = text.lower()
    if "/cpa/" in low or "mouflon-advert" in low:
        return None
    if ".m3u8" not in low and ".mp4" not in low:
        return None
    return text


def adult_file_play(raw: str) -> bool:
    low = str(raw or "").strip().lower()
    return ".mp4" in low and ".m3u8" not in low


def adult_live_play(source: str, text: str) -> str | None:
    """Guest live media playlist only. Refuse advert VOD and dummy media.mp4."""
    play = adult_playlist(source)
    if not play:
        return None
    low = str(text or "").lower()
    if "mouflon-advert" in low or "/cpa/" in low:
        return None
    if "#ext-x-stream-inf" in low:
        return None
    if "media.mp4" in low:
        return None
    if "#extinf" not in low:
        return None
    return play


def adult_love_variant(source: str, text: str) -> str | None:
    """Master variant with the psch/pkey the file already advertises."""
    if adult_playlist(source) is None:
        return None
    blob = str(text or "")
    low = blob.lower()
    if "mouflon-advert" in low or "/cpa/" in low:
        return None
    if "#ext-x-stream-inf" not in low:
        return None
    psch = ""
    pkey = ""
    variants: list[str] = []
    for line in blob.splitlines():
        row = line.strip()
        if row.startswith("#EXT-X-MOUFLON:PSCH:"):
            parts = row.split(":")
            if len(parts) >= 4:
                psch = parts[2]
                pkey = parts[3]
        if row.lower().startswith("https://"):
            play = adult_playlist(row)
            if play:
                variants.append(play)
    pick = _adult_love_pick(variants)
    if not pick:
        return None
    if not psch or not pkey:
        return pick
    sep = "&" if "?" in pick else "?"
    return f"{pick}{sep}psch={psch}&pkey={pkey}"


def _adult_love_pick(variants: list[str]) -> str | None:
    ranked = [
        row
        for row in variants
        if "blur" not in row.lower() and "160p" not in row.lower()
    ]
    for row in ranked:
        if "_480p" in row.lower():
            return row
    for row in ranked:
        low = row.lower()
        if "_auto" in low or "_240p" not in low:
            return row
    if ranked:
        return ranked[0]
    return variants[0] if variants else None


def adult_allows(name: str) -> bool:
    blob = str(name or "").lower()
    if not blob.strip():
        return False
    return not any(token in blob for token in ADULT_BLOCKED)


def adult_clean(blob: str) -> bool:
    text = str(blob or "").lower()
    if not text.strip():
        return True
    return not any(token in text for token in ADULT_BLOCKED)


def adult_stream(payload: object) -> str | None:
    """Public room HLS only. Private or empty is no stream."""
    if not isinstance(payload, dict):
        return None
    status = str(payload.get("room_status") or "").strip().lower()
    if status != "public":
        return None
    raw = payload.get("hls_source")
    if raw is None or str(raw).strip() == "":
        raw = payload.get("url")
    return adult_playlist(str(raw or ""))


def adult_woman(model: object) -> bool:
    """Women and couples. Refuse male-lead and trans gender tags."""
    if not isinstance(model, dict):
        return False
    gender = str(model.get("gender") or "").strip().lower()
    if not gender:
        gender = str(model.get("broadcaster_gender") or "").strip().lower()
    if not gender:
        return True
    if gender in ADULT_MALE:
        return False
    return gender in ADULT_WOMAN


def adult_still(raw: str) -> str | None:
    """HTTPS JPEG still only. Never a playlist or advert clip."""
    text = str(raw or "").strip()
    if not text.lower().startswith("https://"):
        return None
    low = text.lower()
    if "/cpa/" in low or ".m3u8" in low:
        return None
    return text


def adult_image(model: object) -> str:
    if not isinstance(model, dict):
        return ""
    for key in ("image_url_360p", "image_url"):
        hit = adult_still(str(model.get(key) or ""))
        if hit:
            return hit
    return ""


def adult_room_kinds(model: object) -> list[str]:
    if not isinstance(model, dict):
        return []
    tags = model.get("tags") or []
    if isinstance(tags, list):
        tag_blob = " ".join(str(tag) for tag in tags)
    else:
        tag_blob = str(tags)
    blob = f"{tag_blob} {model.get('room_subject') or ''}".lower()
    tokens = set(blob.split())
    found: list[str] = []
    seen: set[str] = set()
    if model.get("is_new") or "new" in tokens:
        seen.add("NEW")
        found.append("NEW")
    gender = str(model.get("gender") or "").strip().lower()
    if gender in ADULT_COUPLE or "couple" in tokens or "couples" in tokens:
        seen.add("COUPLE")
        found.append("COUPLE")
    for needle, chip in ADULT_KIND_WORDS:
        if needle == "new":
            continue
        if needle in blob and chip not in seen and adult_clean(chip):
            seen.add(chip)
            found.append(chip)
    return found


def adult_seek(model: object) -> str:
    if not isinstance(model, dict):
        return ""
    tags = model.get("tags") or []
    if isinstance(tags, list):
        tag_blob = " ".join(str(tag) for tag in tags)
    else:
        tag_blob = str(tags)
    return f"{tag_blob} {model.get('room_subject') or ''}".strip().lower()


def adult_kinds(rooms: list[dict]) -> list[str]:
    seen: set[str] = set()
    for room in rooms:
        for kind in room.get("kinds") or []:
            chip = str(kind).strip().upper()
            if chip:
                seen.add(chip)
    pinned = [chip for chip in ADULT_PIN if chip in seen]
    rest = sorted(seen.difference(ADULT_PIN))
    return pinned + rest


def adult_face_needles(kind: str) -> list[str] | None:
    chip = str(kind or "").strip().upper()
    for name, needles in ADULT_FACES:
        if name == chip:
            return list(needles)
    return None


def adult_love_needles(kind: str) -> bool:
    return str(kind or "").strip().upper() == ADULT_LOVE_CHIP


def adult_love_directory(tag: str, offset: int = 0) -> str:
    start = max(0, int(offset))
    raw = str(tag or "").strip().lower()
    token = raw if raw in ADULT_LOVE_TAGS else ADULT_LOVE_TAGS[0]
    return (
        f"{ADULT_LOVE_ORIGIN}/api/front/models"
        f"?limit=100&offset={start}&primaryTag={token}"
    )


def adult_love_still(raw: str) -> str | None:
    text = str(raw or "").strip()
    if text.lower().endswith("-thumb-small"):
        stem = text[: -len("-thumb-small")]
        return adult_still(stem) or adult_still(stem + "-thumb-big") or adult_still(text)
    return adult_still(text)


def adult_parse_love(payload: object) -> list[dict]:
    """Live public women and couple rooms from the love desk."""
    models: list[object] = []
    if isinstance(payload, list):
        models = payload
    elif isinstance(payload, dict):
        raw = payload.get("models")
        if raw is None:
            raw = payload.get("results")
        if isinstance(raw, list):
            models = raw
    rooms: list[dict] = []
    seen: set[str] = set()
    for model in models:
        if not isinstance(model, dict):
            continue
        if not model.get("isLive"):
            continue
        if str(model.get("status") or "").strip().lower() != "public":
            continue
        group = str(model.get("genderGroup") or "").strip().lower()
        if group in {"m", "male", "t", "trans"}:
            continue
        broadcast = str(model.get("broadcastGender") or "").strip().lower()
        if broadcast in {"male", "men", "trans", "tranny"}:
            continue
        if not adult_woman(model):
            continue
        try:
            years = model.get("age")
            if years is not None and int(years) < 18:
                continue
        except (TypeError, ValueError):
            continue
        handle = str(model.get("username") or model.get("slug") or "").strip()
        name = str(model.get("displayName") or handle).strip()
        if not handle or not adult_allows(handle) or not adult_allows(name):
            continue
        topic = str(model.get("groupShowTopic") or "")
        if not adult_clean(topic):
            continue
        rid = f"adult-love-{handle.lower()}"
        if rid in seen:
            continue
        seen.add(rid)
        play = adult_playlist(str(model.get("hlsPlaylist") or "")) or ""
        if play:
            play = play.replace("_240p.m3u8", "_auto.m3u8")
        image = adult_love_still(str(model.get("previewUrlThumbSmall") or "")) or ""
        if not image:
            image = adult_still(str(model.get("avatarUrl") or "")) or ""
        kinds = [ADULT_LOVE_CHIP]
        gender = str(model.get("gender") or "").strip().lower()
        if gender in {"c", "couple", "couples", "malefemale", "females"} or broadcast == "group":
            kinds.append("COUPLE")
        if model.get("isNew"):
            kinds.append("NEW")
        blob = f"{topic} {handle}".lower()
        seen_kinds = set(kinds)
        for needle, chip in ADULT_KIND_WORDS:
            if needle == "new":
                continue
            if needle in blob and chip not in seen_kinds and adult_clean(chip):
                seen_kinds.add(chip)
                kinds.append(chip)
        try:
            viewers = int(model.get("viewersCount") or model.get("viewers") or 0)
        except (TypeError, ValueError):
            viewers = 0
        rooms.append(
            {
                "id": rid,
                "name": name.upper(),
                "handle": handle,
                "url": play,
                "viewers": viewers,
                "image": image,
                "kinds": kinds,
                "seek": " ".join(
                    part
                    for part in (
                        handle,
                        name,
                        gender,
                        topic,
                        str(model.get("country") or ""),
                    )
                    if part
                ).lower(),
                "seconds": 0,
            }
        )
    return rooms


def adult_topics(kind: str) -> list[str]:
    if adult_face_needles(kind) is not None or adult_love_needles(kind):
        return []
    chip = str(kind or "").strip().upper()
    if chip in ("", "ALL"):
        return []
    if chip in ADULT_TOPIC:
        return list(ADULT_TOPIC[chip])
    tag = str(kind or "").strip().lower()
    return [tag] if tag else []


def adult_directory(tag: str, offset: int = 0, topic: str = "") -> str:
    start = max(0, int(offset))
    url = (
        "https://chaturbate.com/api/public/affiliates/onlinerooms/"
        f"?format=json&limit=100&offset={start}&client_ip=8.8.8.8&wm=DkfRj&gender={tag}"
    )
    hashtag = str(topic or "").strip().lower()
    if hashtag:
        url += f"&tag={hashtag}"
    return url


def adult_count(value: object) -> int:
    if isinstance(value, bool):
        return 0
    if isinstance(value, int):
        if value < 0 or value > ADULT_COUNT_CAP:
            return 0
        return value
    if isinstance(value, float):
        if not math.isfinite(value) or value < 0 or value > ADULT_COUNT_CAP:
            return 0
        return int(value)
    text = str(value or "").strip()
    if not text:
        return 0
    try:
        return adult_count(int(text))
    except ValueError:
        try:
            return adult_count(float(text))
        except ValueError:
            return 0


def adult_rail(rooms: list[dict]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    always = (
        ["ALL", ADULT_LOVE_CHIP]
        + [name for name, _ in ADULT_FACES]
        + list(ADULT_PIN)
    )
    for chip in always:
        if chip not in seen:
            seen.add(chip)
            out.append(chip)
    extra = 0
    for chip in adult_kinds(rooms):
        if chip in seen:
            continue
        seen.add(chip)
        out.append(chip)
        extra += 1
        if extra >= ADULT_RAIL_EXTRA:
            break
    return out


def adult_pick(rooms: list[dict], kind: str = "", query: str = "") -> list[dict]:
    chip = str(kind or "").strip().upper()
    needle = str(query or "").strip().lower()
    faces = adult_face_needles(chip)
    love = adult_love_needles(chip)
    out: list[dict] = []
    for room in rooms:
        kinds = [str(item).strip().upper() for item in (room.get("kinds") or [])]
        if faces:
            blob = " ".join(
                [
                    str(room.get("name") or ""),
                    str(room.get("handle") or ""),
                    str(room.get("seek") or ""),
                    " ".join(kinds),
                ]
            ).lower()
            if not any(token in blob for token in faces):
                continue
        elif love:
            if ADULT_LOVE_CHIP not in kinds:
                continue
        elif chip and chip != "ALL" and chip not in kinds:
            continue
        if needle:
            blob = " ".join(
                [
                    str(room.get("name") or ""),
                    str(room.get("handle") or ""),
                    str(room.get("seek") or ""),
                    " ".join(kinds),
                ]
            ).lower()
            if needle not in blob:
                continue
        out.append(room)
    if faces:
        out.sort(
            key=lambda room: (
                -int(room.get("seconds") or 0),
                -int(room.get("viewers") or 0),
                str(room.get("name") or ""),
            )
        )
    return out


def adult_face_room(handle: str, payload: object) -> dict | None:
    play = adult_stream(payload)
    if not play or not isinstance(payload, dict):
        return None
    if not adult_woman(payload):
        return None
    try:
        years = payload.get("age")
        if years is not None and int(years) < 18:
            return None
    except (TypeError, ValueError):
        return None
    named = str(payload.get("broadcaster_username") or handle).strip() or handle
    title = str(payload.get("room_title") or payload.get("room_subject") or "").strip()
    if not adult_allows(handle) or not adult_allows(named) or not adult_clean(title):
        return None
    return {
        "id": f"adult-{handle.lower()}",
        "name": named.upper(),
        "handle": handle,
        "url": play,
        "viewers": int(payload.get("num_users") or payload.get("num_viewers") or payload.get("viewers") or 0),
        "image": adult_image(payload),
        "kinds": adult_room_kinds(payload),
        "seek": f"{handle} {title}".strip().lower(),
        "seconds": 0,
    }


def adult_face_queries(kind: str) -> list[str]:
    needles = adult_face_needles(kind) or []
    out: list[str] = []
    seen: set[str] = set()
    chip = str(kind or "").strip().lower()
    for raw in list(needles) + [chip]:
        query = str(raw or "").strip().lower()
        if len(query) < 6 or query in seen:
            continue
        seen.add(query)
        out.append(query)
    return out


def adult_star_search(query: str, page: int = 1) -> str | None:
    q = str(query or "").strip()
    if not q:
        return None
    start = max(1, int(page))
    encoded = urllib.parse.quote(q, safe="-")
    return f"https://bornstar.co/api/search?q={encoded}&page={start}"


ADULT_FACE_PINS = (
    ("ITSSTEPHHONEY21", ("P283XrKRjsV",)),
    ("ITSSTEPHHONEYXO21", ("P283XrKRjsV",)),
    ("MULAN VUITTON", ("L3HLNRZy6sk", "pYaoSJlMR79")),
    ("NERDY BEILA", ("33TgD6OeUfp", "iaBJWcUXDqR", "XYqGeufLjxo", "3Okd36yQXGq")),
    ("HOT4LEXI", ("I9eggkAajv5",)),
    ("BRITTANYA RAZAVI", ("ZxMHa5OsXqH", "hdIUeKyK0Ux", "GvbBRAGihAQ", "mXbvfQ0ly1D")),
    ("DOUBLE DOSE TWINS", ("7bg2FgwidLS", "NtQUcCtcTj0", "iXWnuAL4FnV")),
)
ADULT_FACE_STARS = (
    ("MULAN VUITTON", ("mulan-vuitton",)),
    ("HOT4LEXI", ("hot4lexi",)),
    ("ZURI BELLA ROSE", ("zuri-bella-rose",)),
    ("SARIIXO", ("sariixo",)),
    ("KIRAWWRRRA", ("kirawrrra2-0",)),
)
ADULT_FACE_HOLDS = (
    ("ITSSTEPHHONEY21", (("pin", "P283XrKRjsV", 158, "stephaniehvip twerks and jiggles"),)),
    ("ITSSTEPHHONEYXO21", (("pin", "P283XrKRjsV", 158, "stephaniehvip twerks and jiggles"),)),
    ("MULAN VUITTON", (
        ("star", "mulan-vuitton-gets-pounded-while-in-a-skirt", 984, "Mulan Vuitton Gets Pounded While In A Skirt"),
        ("star", "mulan-vuitton-has-sex-with-a-thief", 712, "Mulan Vuitton Has Sex With A Thief"),
        ("pin", "L3HLNRZy6sk", 184, "Mulan Vuitton"),
        ("pin", "pYaoSJlMR79", 362, "Mulanvuitton Oiled Up Fucking Doggy Style By Black Cock"),
    )),
    ("NERDY BEILA", (("pin", "33TgD6OeUfp", 1472, "Beila B/Nerdy B Big Tits Cosplay PMV (Pt. 2)"),)),
    ("HOT4LEXI", (
        ("star", "hot4lexi-missionary-sextape-video-leaked", 517, "Hot4lexi Missionary Sextape Video Leaked"),
        ("pin", "I9eggkAajv5", 409, "Hot4lexi Reverse Cowgirl Sex Tape"),
    )),
    ("BRITTANYA RAZAVI", (("pin", "ZxMHa5OsXqH", 503, "Brittanya Razavi"),)),
    ("ZURI BELLA ROSE", (("star", "zuri-bella-rose-takes-a-dick-in-multiple-positions", 792, "Zuri Bella Rose Takes A Dick In Multiple Positions"),)),
    ("SARIIXO", (("star", "sariixo-fucks-her-pussy-with-a-bbc-dildo-in-bed", 602, "Sariixo Fucks Her Pussy With A BBC Dildo In Bed"),)),
    ("KIRAWWRRRA", (("star", "kirawrrra2-0-fills-her-ass-for-the-first-time", 211, "Kirawrrra2.0 Fills Her Ass For The First Time"),)),
    ("DOUBLE DOSE TWINS", (
        ("pin", "7bg2FgwidLS", 660, "Double Dose Twins Fanvan They Porno Tubes"),
        ("pin", "NtQUcCtcTj0", 199, "Doubledose Twins Blowjob GAWD DAMN I NEED DAT"),
        ("pin", "iXWnuAL4FnV", 140, "Doubledose Twins Blowjob"),
    )),
)
ADULT_FACE_STILLS = (
    ("P283XrKRjsV", "https://static-ca-cdn.eporner.com/thumbs/static4/1/17/172/17213787/14_360.jpg"),
    ("pYaoSJlMR79", "https://static-ca-cdn.eporner.com/thumbs/static4/1/17/175/17518776/4_360.jpg"),
    ("L3HLNRZy6sk", "https://static-ca-cdn.eporner.com/thumbs/static4/1/17/179/17953657/5_360.jpg"),
    ("33TgD6OeUfp", "https://static-ca-cdn.eporner.com/thumbs/static4/1/18/182/18280571/8_360.jpg"),
    ("XYqGeufLjxo", "https://static-ca-cdn.eporner.com/thumbs/static4/1/17/173/17342912/9_360.jpg"),
    ("iaBJWcUXDqR", "https://static-ca-cdn.eporner.com/thumbs/static4/1/17/176/17654141/2_360.jpg"),
    ("3Okd36yQXGq", "https://static-ca-cdn.eporner.com/thumbs/static4/1/16/168/16806371/9_360.jpg"),
    ("I9eggkAajv5", "https://static-ca-cdn.eporner.com/thumbs/static4/1/18/183/18307343/8_360.jpg"),
    ("ZxMHa5OsXqH", "https://static-ca-cdn.eporner.com/thumbs/static4/1/17/171/17112398/14_360.jpg"),
    ("hdIUeKyK0Ux", "https://static-ca-cdn.eporner.com/thumbs/static4/1/16/166/16629256/12_360.jpg"),
    ("GvbBRAGihAQ", "https://static-ca-cdn.eporner.com/thumbs/static4/1/17/170/17011500/4_360.jpg"),
    ("mXbvfQ0ly1D", "https://static-ca-cdn.eporner.com/thumbs/static4/1/17/173/17378695/4_360.jpg"),
    ("7bg2FgwidLS", "https://static-ca-cdn.eporner.com/thumbs/static4/1/17/171/17109075/14_360.jpg"),
    ("NtQUcCtcTj0", "https://static-ca-cdn.eporner.com/thumbs/static4/1/17/173/17399374/14_360.jpg"),
    ("iXWnuAL4FnV", "https://static-ca-cdn.eporner.com/thumbs/static4/1/15/157/15712160/13_360.jpg"),
)
ADULT_FACE_GIFTS = (
    ("ITSSTEPHHONEY21", ("itsstephhoneyxo21", "itsstephhoney21", "stephaniehvip")),
    ("ITSSTEPHHONEYXO21", ("itsstephhoneyxo21", "itsstephhoney21", "stephaniehvip")),
    ("MULAN VUITTON", ("mulanvuitton", "mulanvuittontv")),
    ("MIKEILA J", ("mikeilaj", "mikeilajbaee", "mikeilajduhh", "theemikeilaj")),
    ("NERDY BEILA", ("nerdybeila", "vipnerdyb", "beilacosplay")),
    ("JUICYJAS TV", ("juicyjastv", "juicyjas")),
    ("HONEYTEASSEE", ("honeyteassee",)),
    ("TANIA RAMOS", ("taniaaaramos",)),
    ("BRITTANYA RAZAVI", ("brittanyarazavi", "seebrittanya", "brittanya2horny")),
    ("HOT4LEXI", ("hot4lexi", "hott4lexi", "lexi2legit")),
    ("LILI VICTORIA", ("lilivictoria32", "lilivictoria")),
    ("ZURI BELLA ROSE", ("zuribellarose",)),
    ("SARIIXO", ("officialsariixo", "sariixo")),
    ("MONA ACUTEE", ("monaacutee", "monaacute")),
    ("IMHIZBAEEXX", ("imhizbaeexx", "hizbaeexx")),
    ("YESS ENIA69", ("yessenia69",)),
    ("VAL2YUMMI", ("val2yummi", "val2yummy")),
    ("KIRAWWRRRA", ("kirawrrra", "kirawrrra2")),
    ("JACQIE VAINS", ("jacqievains",)),
    ("LILIANAS PAGE", ("lilianaspage",)),
    ("FREAKYYSTACKSS", ("freakyystackss", "freakyystacks")),
    ("ASAIA HERNANDEZ", ("asaiahernandez",)),
    ("JASMINEGTV", ("jasminegtv1", "jasminegtv")),
    ("IMANGELJESSYY", ("imangeljessyy", "imangeljessy", "angeljessyy")),
    ("GRACIE BONN", ("itsgraciebonn", "graciebonn")),
    ("DEBVARELA", ("debvarela",)),
    ("DOUBLE DOSE TWINS", ("doubledosetwins",)),
    ("PAMELA YAMZ", ("pamelayamz",)),
    ("ANNABELLE RIOS", ("annabelleriossss", "annabellerios")),
    ("NICOLEEE 1329", ("nicoleee1329",)),
    ("EUNICEG", ("euniceg",)),
    ("STRAWBERRY SANDRA", ("strawberrysandra20", "strawberrysandra")),
)
ADULT_FACE_KILL = (
    "loli",
    "shota",
    "child",
    "preteen",
    "jailbait",
    "pedo",
    "minor",
    "underage",
    "under18",
    "younggirl",
    "little girl",
)
ADULT_GIFT_AUTH = "https://api.redgifs.com/v2/auth/temporary"
ADULT_GIFT_ORIGIN = "https://www.redgifs.com"


def adult_face_id(token: str) -> str | None:
    ident = str(token or "").strip()
    if not ident or not all(ch.isalnum() for ch in ident):
        return None
    return f"https://www.eporner.com/api/v2/video/id/?id={ident}&format=json"


def _adult_face_tokens(table: tuple, kind: str) -> list[str]:
    chip = str(kind or "").strip().upper()
    for name, tokens in table:
        if name == chip:
            return [str(token) for token in tokens]
    return []


def adult_face_pin_tokens(kind: str) -> list[str]:
    return _adult_face_tokens(ADULT_FACE_PINS, kind)


def adult_face_star_tokens(kind: str) -> list[str]:
    return _adult_face_tokens(ADULT_FACE_STARS, kind)


def adult_face_gift_tokens(kind: str) -> list[str]:
    return _adult_face_tokens(ADULT_FACE_GIFTS, kind)


def adult_gift_key(raw: str) -> str | None:
    compact = "".join(ch for ch in str(raw or "").lower() if ch.isalnum())
    if len(compact) < 6:
        return None
    return compact


def adult_face_hunt(kind: str) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()

    def add(path: str | None) -> None:
        if path and path not in seen:
            seen.add(path)
            out.append(path)

    for token in adult_face_pin_tokens(kind):
        add(adult_face_id(token))
    for slug in adult_face_star_tokens(kind):
        for page in range(1, ADULT_HUNT_PAGES + 1):
            add(adult_star_search(slug, page=page))
    gifts: list[str] = []
    gift_seen: set[str] = set()
    for raw in adult_face_gift_tokens(kind) + adult_face_queries(kind):
        key = adult_gift_key(raw)
        if key and key not in gift_seen:
            gift_seen.add(key)
            gifts.append(key)
    for query in gifts:
        for page in range(1, ADULT_HUNT_PAGES + 1):
            add(adult_gift_search(query, page=page))
        add(adult_gift_user(query, page=1))
    for query in adult_face_queries(kind):
        for page in range(1, ADULT_HUNT_PAGES + 1):
            add(adult_face_search(query, page=page))
        for page in range(1, ADULT_HUNT_PAGES + 1):
            add(adult_star_search(query, page=page))
    return out[:ADULT_HUNT_CAP]


def adult_face_keep(ident: str) -> bool:
    return str(ident or "").startswith("adult-face-")


def adult_face_still(desk: str, token: str) -> str | None:
    if desk == "star":
        slug = str(token or "").strip().lower()
        if slug and all(ch.isalnum() or ch == "-" for ch in slug):
            return adult_still(f"https://cdn.bornstar.co/preview-batch/{slug}/thumb.webp")
        return None
    ident = str(token or "").strip()
    for name, src in ADULT_FACE_STILLS:
        if name.lower() == ident.lower():
            return adult_still(src)
    return None


def adult_face_hold_rooms(kind: str) -> list[dict]:
    chip = str(kind or "").strip().upper()
    if chip in ("", "ALL"):
        chips = [name for name, _needles in ADULT_FACES]
    elif adult_face_needles(chip):
        chips = [chip]
    else:
        return []
    rows: list[dict] = []
    seen: set[str] = set()
    for name in chips:
        needles = adult_face_needles(name) or []
        for hold_name, holds in ADULT_FACE_HOLDS:
            if hold_name != name:
                continue
            for desk, token, seconds, title in holds:
                if seconds <= 0 or not str(title).strip() or not _adult_face_ok(title):
                    continue
                if desk == "star":
                    play = adult_playlist(adult_star_file(token) or "")
                    rid = f"adult-face-star-{token.lower()}"
                else:
                    play = adult_playlist(adult_face_file(token) or "")
                    rid = f"adult-face-{token.lower()}"
                if not play or rid in seen:
                    continue
                seen.add(rid)
                rows.append(
                    {
                        "id": rid,
                        "name": title.upper(),
                        "handle": token,
                        "url": play,
                        "viewers": 0,
                        "image": adult_face_still(desk, token) or "",
                        "kinds": [name],
                        "seek": f"{title} {' '.join(needles)}".strip().lower(),
                        "seconds": int(seconds),
                    }
                )
    rows.sort(key=lambda row: (-int(row["seconds"]), str(row["name"])))
    return rows


def adult_merge(batches: list[list[dict]]) -> list[dict]:
    by_id: dict[str, dict] = {}
    for room in (row for batch in batches for row in batch):
        rid = str(room.get("id") or "")
        if not rid:
            continue
        old = by_id.get(rid)
        if old is None:
            by_id[rid] = dict(room)
            continue
        if int(room.get("viewers") or 0) > int(old.get("viewers") or 0):
            next_room = dict(room)
            if not str(next_room.get("image") or "").strip():
                next_room["image"] = old.get("image") or ""
            by_id[rid] = next_room
        elif not str(old.get("image") or "").strip() and str(room.get("image") or "").strip():
            old = dict(old)
            old["image"] = room["image"]
            by_id[rid] = old
    all_rows = list(by_id.values())
    files = [row for row in all_rows if adult_face_keep(str(row.get("id") or ""))]
    rest = [row for row in all_rows if not adult_face_keep(str(row.get("id") or ""))]
    files.sort(key=lambda row: (-int(row.get("seconds") or 0), str(row.get("name") or "")))
    rest.sort(key=lambda row: (-int(row.get("viewers") or 0), str(row.get("name") or "")))
    keep = max(0, ADULT_CAP - len(files))
    return rest[:keep] + files


def adult_gift_search(query: str, page: int = 1) -> str | None:
    q = str(query or "").strip()
    if not q:
        return None
    start = max(1, int(page))
    encoded = urllib.parse.quote(q, safe="-")
    return f"https://api.redgifs.com/v2/gifs/search?search_text={encoded}&count=40&page={start}"


def adult_gift_user(query: str, page: int = 1) -> str | None:
    q = adult_gift_key(query)
    if not q:
        return None
    start = max(1, int(page))
    return f"https://api.redgifs.com/v2/users/{q}/search?count=40&page={start}"


def adult_gift_token(payload: object) -> str | None:
    if not isinstance(payload, dict):
        return None
    token = str(payload.get("token") or "").strip()
    return token or None


def adult_gift_session(payload: object) -> str | None:
    if not isinstance(payload, dict):
        return None
    raw = payload.get("session")
    if isinstance(raw, str) and raw.strip():
        return raw.strip()
    if isinstance(raw, int):
        return str(raw)
    if isinstance(raw, float) and raw == raw:
        return str(int(raw))
    return None


def adult_gift_headers(raw: str, token: str, session: str = "") -> dict[str, str]:
    host = urllib.parse.urlparse(str(raw or "")).hostname or ""
    host = host.lower()
    if "redgifs" not in host or not str(token or "").strip():
        return {}
    headers = {"Authorization": f"Bearer {token}"}
    if str(session or "").strip():
        headers["X-Session-Id"] = str(session).strip()
    return headers


def adult_gift_file(model: dict) -> str | None:
    urls = model.get("urls") if isinstance(model.get("urls"), dict) else {}
    play = adult_playlist(str(urls.get("hd") or urls.get("sd") or ""))
    return play


def adult_face_search(query: str, page: int = 1) -> str | None:
    q = str(query or "").strip()
    if not q:
        return None
    start = max(1, int(page))
    encoded = urllib.parse.quote(q, safe="-")
    return (
        "https://www.eporner.com/api/v2/video/search/"
        f"?query={encoded}&per_page=80&page={start}&order=longest&format=json&gay=0&thumbsize=big"
    )


def adult_face_file(token: str) -> str | None:
    ident = str(token or "").strip()
    if not ident or not all(ch.isalnum() for ch in ident):
        return None
    return f"https://www.eporner.com/dload/{ident}/720/video.mp4"


def adult_star_file(slug: str) -> str | None:
    ident = str(slug or "").strip().lower()
    if not ident or not all(ch.isalnum() or ch == "-" for ch in ident):
        return None
    return f"https://cdn.bornstar.co/videos/{ident}/master.m3u8"


def adult_clock(seconds: int) -> str:
    total = max(0, int(seconds))
    hours, rem = divmod(total, 3600)
    minutes, rest = divmod(rem, 60)
    if hours:
        return f"{hours}:{minutes:02d}:{rest:02d}"
    return f"{minutes}:{rest:02d}"


def _adult_face_plain(blob: str) -> str:
    return "".join(ch for ch in str(blob or "").lower() if ch.isascii() and (ch.isalnum() or ch == " "))


def _adult_face_hit(blob: str, needles: list[str]) -> bool:
    text = _adult_face_plain(blob)
    compact = text.replace(" ", "")
    for needle in needles:
        token = _adult_face_plain(needle)
        if " " in token:
            if token in text:
                return True
        elif token in text or token in compact:
            return True
    return False


def _adult_face_clip(model: dict, needles: list[str], kind: str = "") -> dict | None:
    token = str(model.get("id") or "").strip()
    raw_title = str(model.get("title") or "").replace("\u200b", " ")
    play = adult_playlist(adult_face_file(token) or "")
    title = raw_title.strip()
    keys = str(model.get("keywords") or "").replace("\u200b", " ")
    if not play or not title or not _adult_face_ok(title) or not _adult_face_ok(keys):
        return None
    held = any(pin.lower() == token.lower() for pin in adult_face_pin_tokens(kind))
    if not held and not _adult_face_hit(f"{title} {keys}", needles):
        return None
    thumb = ""
    default = model.get("default_thumb")
    if isinstance(default, dict):
        thumb = adult_still(str(default.get("src") or "")) or ""
    seconds = adult_count(model.get("length_sec"))
    if seconds <= 0:
        return None
    views = adult_count(model.get("views"))
    return {
        "id": f"adult-face-{token.lower()}",
        "name": title.upper(),
        "handle": token,
        "url": play,
        "viewers": views,
        "image": thumb,
        "kinds": [str(kind).strip().upper()] if str(kind).strip() else [],
        "seek": f"{title} {' '.join(needles)}".strip().lower(),
        "seconds": seconds,
    }


def _adult_star_clip(model: dict, needles: list[str], kind: str = "") -> dict | None:
    slug = str(model.get("slug") or model.get("id") or "").strip()
    play = adult_playlist(adult_star_file(slug) or "")
    raw_title = str(model.get("title") or "").replace("\u200b", " ")
    if not play:
        return None
    title = raw_title.strip()
    creator = str(model.get("creator") or "").replace("\u200b", " ").strip()
    if not title or not _adult_face_ok(title):
        return None
    if creator and not _adult_face_ok(creator):
        return None
    blob = f"{title} {creator} {slug}"
    stars = adult_face_star_tokens(kind)
    held = any(
        _adult_face_plain(star) in (_adult_face_plain(slug), _adult_face_plain(creator))
        for star in stars
    )
    for row in model.get("performers") or []:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or "").replace("\u200b", " ")
        star = str(row.get("slug") or "").replace("\u200b", " ")
        if not _adult_face_ok(name) or not _adult_face_ok(star):
            return None
        blob += f" {name} {star}"
        if any(
            _adult_face_plain(token) in (_adult_face_plain(star), _adult_face_plain(name))
            for token in stars
        ):
            held = True
    if not held and not _adult_face_hit(blob, needles):
        return None
    seconds = adult_count(model.get("durationSeconds"))
    if seconds <= 0:
        return None
    views = adult_count(model.get("views"))
    return {
        "id": f"adult-face-star-{slug.lower()}",
        "name": title.upper(),
        "handle": slug,
        "url": play,
        "viewers": views,
        "image": adult_still(str(model.get("thumbnailUrl") or "")) or "",
        "kinds": [str(kind).strip().upper()] if str(kind).strip() else [],
        "seek": f"{title} {creator} {' '.join(needles)}".strip().lower(),
        "seconds": seconds,
    }


def _adult_face_ok(blob: str) -> bool:
    text = _adult_face_plain(blob)
    if not text:
        return True
    return not any(token in text for token in ADULT_FACE_KILL)


def _adult_gift_clip(model: dict, needles: list[str], kind: str = "") -> dict | None:
    token = str(model.get("id") or model.get("gifId") or "").strip()
    play = adult_gift_file(model)
    user = str(model.get("userName") or model.get("username") or "").strip()
    title = str(model.get("description") or user).replace("\u200b", " ").strip()
    tags = " ".join(str(tag) for tag in model.get("tags") or [] if str(tag).strip())
    if not play or not title or not _adult_face_ok(title) or not _adult_face_ok(user) or not _adult_face_ok(tags):
        return None
    if not _adult_face_hit(f"{title} {user} {tags} {token}", needles):
        return None
    seconds = max(1, adult_count(model.get("duration")))
    urls = model.get("urls") if isinstance(model.get("urls"), dict) else {}
    return {
        "id": f"adult-face-gift-{token.lower()}",
        "name": title.upper(),
        "handle": token,
        "url": play,
        "viewers": adult_count(model.get("views")),
        "image": adult_still(str(urls.get("thumbnail") or urls.get("poster") or "")) or "",
        "kinds": [str(kind).strip().upper()] if str(kind).strip() else [],
        "seek": f"{title} {user} {' '.join(needles)}".strip().lower(),
        "seconds": seconds,
    }


def _adult_face_models(payload: object) -> list[dict]:
    if isinstance(payload, list):
        return [row for row in payload if isinstance(row, dict)]
    if not isinstance(payload, dict):
        return []
    for key in ("videos", "results", "items", "gifs"):
        raw = payload.get(key)
        if isinstance(raw, list) and raw:
            return [row for row in raw if isinstance(row, dict)]
    if payload.get("title") and (payload.get("id") or payload.get("slug")):
        return [payload]
    return []


def adult_parse_face(payload: object, kind: str) -> list[dict]:
    needles = adult_face_needles(kind) or []
    if not needles:
        return []
    rows: list[dict] = []
    seen: set[str] = set()
    for model in _adult_face_models(payload):
        room = (
            _adult_gift_clip(model, needles, kind)
            or _adult_star_clip(model, needles, kind)
            or _adult_face_clip(model, needles, kind)
        )
        if not room or room["id"] in seen:
            continue
        seen.add(room["id"])
        rows.append(room)
    rows.sort(key=lambda row: (-int(row["seconds"]), str(row["name"])))
    return rows


def adult_rooms(payload: object) -> list[dict]:
    """Live public women rooms, highest viewers first, cap ADULT_CAP. HLS later."""
    models: list[object] = []
    if isinstance(payload, list):
        models = payload
    elif isinstance(payload, dict):
        raw = payload.get("results")
        if raw is None:
            raw = payload.get("models")
        if raw is None:
            raw = payload.get("items")
        if isinstance(raw, dict):
            raw = raw.get("results") or raw.get("models") or raw.get("items") or []
        if isinstance(raw, list):
            models = raw
    rooms: list[dict] = []
    seen: set[str] = set()
    for model in models:
        if not isinstance(model, dict):
            continue
        show = str(model.get("current_show") or model.get("status") or "").strip().lower()
        if show != "public":
            continue
        try:
            years = int(model.get("age"))
        except (TypeError, ValueError):
            continue
        if years < 18:
            continue
        if not adult_woman(model):
            continue
        handle = str(model.get("username") or model.get("slug") or "").strip()
        name = str(model.get("display_name") or handle).strip()
        if not handle or not adult_allows(handle) or not adult_allows(name):
            continue
        tags = model.get("tags") or []
        if isinstance(tags, list):
            tag_blob = " ".join(str(tag) for tag in tags)
        else:
            tag_blob = str(tags)
        subject = str(model.get("room_subject") or "")
        if not adult_clean(tag_blob) or not adult_clean(subject):
            continue
        rid = f"adult-{handle.lower()}"
        if rid in seen:
            continue
        viewers = model.get("num_users")
        if viewers is None:
            viewers = model.get("viewersCount")
        if viewers is None:
            viewers = model.get("viewers")
        try:
            count = int(viewers)
        except (TypeError, ValueError):
            count = 0
        seen.add(rid)
        rooms.append(
            {
                "id": rid,
                "name": name.upper(),
                "handle": handle,
                "url": "",
                "viewers": count,
                "image": adult_image(model),
                "kinds": adult_room_kinds(model),
                "seek": adult_seek(model),
                "seconds": 0,
            }
        )
    rooms.sort(key=lambda row: (-int(row["viewers"]), str(row["name"])))
    return rooms[:ADULT_CAP]


def adult_page(
    rooms: list[dict],
    offset: int = 0,
    limit: int = ADULT_SCREEN,
    kind: str = "",
    query: str = "",
) -> list[dict]:
    """One screen of picked live rooms. TV never mounts the whole directory."""
    picked = adult_pick(rooms, kind=kind, query=query)
    start = max(0, int(offset))
    if limit <= 0:
        return []
    return picked[start : start + limit]


YOU = (31.87050, -106.59732)


class TvOrderTests(unittest.TestCase):
    def test_nearest_camera_is_first(self):
        pack = [
            {
                "id": "far-pack",
                "lat": 32.3,
                "lon": -107.2,
                "name": "Far",
                "url": "https://its.txdot.gov/far.jpg",
            },
            {
                "id": "near-pack",
                "lat": 31.8706,
                "lon": -106.5974,
                "name": "Near",
                "url": "https://its.txdot.gov/near.jpg",
            },
        ]
        hops = [
            {
                "id": "mid-hop",
                "lat": 31.90,
                "lon": -106.62,
                "name": "Mid",
                "url": "https://peer.example/cam.jpg",
            },
            {
                "id": "near-pack",
                "lat": 31.99,
                "lon": -106.80,
                "name": "Dup",
                "url": "https://peer.example/dup.jpg",
            },
            {
                "id": "broken",
                "lat": float("nan"),
                "lon": -106.1,
                "name": "No",
                "url": "https://peer.example/no.jpg",
            },
        ]
        got = tv_rows(pack, hops, YOU[0], YOU[1])
        self.assertEqual([row["id"] for row in got], ["near-pack", "mid-hop", "far-pack"])
        self.assertEqual(got[0]["name"], "Near")

    def test_empty_pack_and_silence_is_empty(self):
        self.assertEqual(tv_rows([], [], YOU[0], YOU[1]), [])


class OneDiscTests(unittest.TestCase):
    def test_pack_and_hop_cameras_are_the_same_red_blue_disc(self):
        cctv = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "CctvArt.swift")
        hop = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MeshCamArt.swift")
        marks = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        tab = read("Blackout", "MapTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        desk = read("Blackout", "CamDesk.swift")
        self.assertIn("enum CctvArt", cctv)
        self.assertIn("225.0 / 255.0", cctv)
        self.assertIn("61.0 / 255.0", cctv)
        self.assertIn("CctvArt.dot()", hop)
        self.assertNotIn("64.0 / 255.0", hop)
        self.assertNotIn("160.0 / 255.0", hop)
        self.assertNotIn("128.0 / 255.0", hop)
        self.assertIn("enum CamDesk", desk)
        self.assertIn("static func marks(", desk)
        self.assertIn("static func feeds(", desk)
        self.assertIn("MeshCamPaint.visible", desk)
        self.assertIn("GraphRouter.haversine", desk)
        self.assertIn("sorted", desk)
        self.assertIn("CamDesk.marks", tab)
        self.assertIn("meshCams: []", tab)
        extra = app.split("func tapUpdate")[1].split("func fitPack")[0]
        self.assertNotIn('ink: "pink"', extra)
        hold = app.split("func holdCam")[1].split("func holdAddress")[0]
        self.assertNotIn('"pink"', hold)
        self.assertIn('?? "blue"', hold)
        self.assertIn("Same red/blue disc", marks)
        switch = app.split("func switchPack")[1].split("func applyMapKeepAwake")[0]
        self.assertIn("loadPackCams()", switch)
        self.assertIn("pullMapSnap()", switch)

    def test_pack_open_and_tv_use_the_same_snap(self):
        app = read("Blackout", "AppRuntime.swift")
        exped = read("Blackout", "ExpeditionTab.swift")
        tv = read("Blackout", "TvPlate.swift")
        sock = read("Blackout", "UpdateSocket.swift")
        self.assertIn("case .tv", exped)
        self.assertIn('return "TV"', exped)
        self.assertIn("TvPlate", exped)
        self.assertIn("pullMapSnap()", exped)
        self.assertIn("struct TvPlate", tv)
        self.assertIn("CamDesk.feeds", tv)
        self.assertIn("TAP UPDATE", tv)
        self.assertIn("NO STILL", tv)
        self.assertIn("NO PIPE", tv)
        self.assertIn("NO CAMERAS", tv)
        self.assertIn("cam-", tv)
        self.assertIn("watchSeconds", tv + desk_text())
        self.assertIn("pullMapSnap()", tv)
        self.assertIn("BlackoutTokens.Distance.hud", tv + desk_text())
        self.assertNotIn("AVPlayer", tv)
        self.assertNotIn("WKWebView", tv)
        self.assertNotIn("rtmp", tv.lower())
        self.assertNotIn("AVPlayer", sock)
        self.assertNotIn("WKWebView", sock)
        self.assertIn("NaLive", tv)
        self.assertIn("openStill", tv)
        self.assertIn("func pullMapSnap(", app)
        self.assertIn("tapUpdate()", app.split("func pullMapSnap")[1].split("func tapUpdate")[0])
        self.assertIn("CamDesk.sections", tv)
        self.assertIn("kind.rawValue", tv)
        desk = desk_text()
        self.assertIn("enum Kind", desk)
        self.assertIn("static func kind(", desk)
        self.assertIn("static func sections(", desk)
        self.assertIn('"TRAFFIC"', desk)
        self.assertIn('"BRIDGE"', desk)
        self.assertIn('"AIRPORT"', desk)
        self.assertIn('"VENUE"', desk)
        self.assertIn('"N/A"', desk)
        self.assertIn('"HOP"', desk)
        self.assertIn("BOTA", desk)
        self.assertIn("PASO DEL NORTE", desk)
        self.assertIn("naHoldSeconds", desk)
        self.assertIn("HOLD 10", tv)
        self.assertIn("naHoldSeconds", tv)
        self.assertIn("naUnlocks", tv + desk)


class SectionTests(unittest.TestCase):
    def test_kind_tokens_are_honest(self):
        self.assertEqual(section({"name": "US-62/Paisano East @ BOTA", "provider": "TxDOT"}), "BRIDGE")
        self.assertEqual(section({"name": "Paso del Norte", "provider": "TxDOT"}), "BRIDGE")
        self.assertEqual(section({"name": "Airway Blvd @ Airport", "provider": "TxDOT"}), "AIRPORT")
        self.assertEqual(section({"name": "Airport @ Founders", "provider": "TxDOT"}), "AIRPORT")
        self.assertEqual(section({"name": "SP-601 @ Airport", "provider": "TxDOT"}), "AIRPORT")
        self.assertEqual(section({"name": "LP-375 @ Paseo Del Norte", "provider": "TxDOT"}), "TRAFFIC")
        self.assertEqual(section({"name": "LP-375 @ Zaragoza", "provider": "TxDOT"}), "TRAFFIC")
        self.assertEqual(section({"name": "FM-659/Zaragoza @ Pellicano", "provider": "TxDOT"}), "TRAFFIC")
        self.assertEqual(section({"name": "IH-10 @ Zaragoza", "provider": "TxDOT"}), "TRAFFIC")
        self.assertEqual(section({"name": "IH-10 @ Airway", "provider": "TxDOT"}), "TRAFFIC")
        self.assertEqual(section({"name": "Airport @ Founders", "provider": "HOP"}), "HOP")
        self.assertEqual(section({"name": "US-62/Paisano East @ BOTA", "provider": "hop"}), "HOP")
        self.assertEqual(section({"name": "Club", "provider": "N/A"}), "N/A")
        self.assertEqual(section({"name": "Club", "provider": "NA"}), "N/A")
        self.assertEqual(section({"name": "Doniphan @ Club", "provider": "TxDOT"}), "TRAFFIC")

    def test_sections_omit_empty_and_sort_inside(self):
        pack = [
            {
                "id": "near",
                "lat": 31.8706,
                "lon": -106.5974,
                "name": "IH-10 @ Artcraft",
                "provider": "TxDOT",
            },
            {
                "id": "paseo",
                "lat": 31.90,
                "lon": -106.58,
                "name": "LP-375 @ Paseo Del Norte",
                "provider": "TxDOT",
            },
            {
                "id": "z-street",
                "lat": 31.75,
                "lon": -106.32,
                "name": "FM-659/Zaragoza @ Pellicano",
                "provider": "TxDOT",
            },
            {
                "id": "bota",
                "lat": 31.764,
                "lon": -106.451,
                "name": "US-62/Paisano East @ BOTA",
                "provider": "TxDOT",
            },
            {
                "id": "pdn",
                "lat": 31.76,
                "lon": -106.48,
                "name": "Paso del Norte",
                "provider": "TxDOT",
            },
            {
                "id": "air-near",
                "lat": 31.80,
                "lon": -106.40,
                "name": "Airway Blvd @ Airport",
                "provider": "TxDOT",
            },
            {
                "id": "air-far",
                "lat": 32.0,
                "lon": -106.3,
                "name": "SP-601 @ Airport",
                "provider": "TxDOT",
            },
            {
                "id": "airway",
                "lat": 31.78,
                "lon": -106.42,
                "name": "IH-10 @ Airway",
                "provider": "TxDOT",
            },
        ]
        hops = [
            {
                "id": "hop-mid",
                "lat": 31.88,
                "lon": -106.60,
                "name": "Peer",
                "url": "https://peer.example/a.jpg",
            },
            {
                "id": "hop-air",
                "lat": 31.81,
                "lon": -106.41,
                "name": "Airport @ Founders",
                "provider": "HOP",
            },
        ]
        got = sectioned(pack, hops, YOU[0], YOU[1])
        self.assertEqual([kind for kind, _ in got], ["TRAFFIC", "BRIDGE", "AIRPORT", "HOP"])
        by_kind = {kind: [row["id"] for row in rows] for kind, rows in got}
        self.assertEqual(by_kind["TRAFFIC"][0], "near")
        self.assertLess(
            haversine_m(YOU, (31.80, -106.40)),
            haversine_m(YOU, (32.0, -106.3)),
        )
        self.assertEqual(by_kind["AIRPORT"], ["air-near", "air-far"])
        self.assertEqual(by_kind["BRIDGE"], ["pdn", "bota"])
        self.assertEqual(by_kind["HOP"][0], "hop-mid")
        self.assertIn("hop-air", by_kind["HOP"])
        self.assertNotIn("VENUE", [kind for kind, _ in got])
        self.assertNotIn("N/A", [kind for kind, _ in got])
        for _kind, rows in got:
            meters = [
                haversine_m(YOU, (float(row["lat"]), float(row["lon"])))
                for row in rows
            ]
            self.assertEqual(meters, sorted(meters))

    def test_tx_west_el_paso_names_section_honestly(self):
        cams = json.loads(read("Resources", "Packs", "tx-west", "cameras.json"))
        by_name = {row["name"]: row for row in cams}
        self.assertEqual(section(by_name["US-62/Paisano East @ BOTA"]), "BRIDGE")
        self.assertEqual(section(by_name["Airway Blvd @ Airport"]), "AIRPORT")
        self.assertEqual(section(by_name["Airport @ Founders"]), "AIRPORT")
        self.assertEqual(section(by_name["SP-601 @ Airport"]), "AIRPORT")
        self.assertEqual(section(by_name["LP-375 @ Paseo Del Norte"]), "TRAFFIC")
        self.assertEqual(section(by_name["LP-375 @ Zaragoza"]), "TRAFFIC")
        self.assertEqual(section(by_name["FM-659/Zaragoza @ Pellicano"]), "TRAFFIC")
        self.assertEqual(section(by_name["IH-10 @ Airway"]), "TRAFFIC")
        self.assertEqual(section(by_name["IH-10 @ Zaragoza"]), "TRAFFIC")
        for row in cams:
            self.assertNotEqual(section(row), "N/A")


class NaHoldTests(unittest.TestCase):
    def test_na_is_gated_and_ten_seconds(self):
        self.assertFalse(na_unlocks(0))
        self.assertFalse(na_unlocks(9.99))
        self.assertTrue(na_unlocks(10))
        self.assertTrue(na_unlocks(12))
        pack = [
            {
                "id": "na-near",
                "lat": 31.871,
                "lon": -106.597,
                "name": "Club",
                "provider": "N/A",
            },
            {
                "id": "near",
                "lat": 31.8706,
                "lon": -106.5974,
                "name": "IH-10 @ Artcraft",
                "provider": "TxDOT",
            },
        ]
        open_kinds = [kind for kind, _ in sectioned(pack, [], YOU[0], YOU[1])]
        self.assertEqual(open_kinds, ["TRAFFIC"])
        self.assertEqual([row["id"] for row in na_rows(pack, [], YOU[0], YOU[1])], ["na-near"])
        desk = desk_text()
        self.assertIn("static let naHoldSeconds", desk)
        self.assertIn("= 10", desk.split("naHoldSeconds")[1].split("\n")[0])
        self.assertIn("static func naUnlocks", desk)
        tv = read("Blackout", "TvPlate.swift")
        self.assertIn("HOLD 10", tv)
        self.assertIn("N/A", tv)
        self.assertNotIn("AVPlayer", tv)
        self.assertNotIn("WKWebView", tv)


class OpenStillTests(unittest.TestCase):
    def test_open_sections_are_snap_stills_only(self):
        tv = read("Blackout", "TvPlate.swift")
        live = read("Blackout", "NaLive.swift")
        sock = read("Blackout", "UpdateSocket.swift")
        self.assertFalse((ROOT / "Blackout" / "DeskLive.swift").exists())
        open_tv = open_body(tv)
        self.assertNotIn("DeskLive", tv)
        self.assertNotIn("NaLiveWell", open_tv)
        self.assertNotIn("TAP PLAY", open_tv)
        self.assertNotIn("AVPlayer", tv)
        self.assertNotIn("WKWebView", tv)
        self.assertNotIn("rtmp", tv.lower())
        self.assertNotIn("zoocams.elpasozoo.org", tv.lower())
        self.assertNotIn("zoocams.elpasozoo.org", live.lower())
        self.assertNotIn("zoocams.elpasozoo.org", sock.lower())
        self.assertIn("TAP UPDATE", tv)
        self.assertIn("NO STILL", tv)
        self.assertIn("CamDesk.sections", tv)
        self.assertIn("openStill", tv)
        self.assertIn("AVPlayer", live)
        self.assertIn("TAP PLAY", live)
        self.assertIn("NO STREAM", live)
        self.assertIn("NO PIPE", live)


class AdultDeskTests(unittest.TestCase):
    def test_directory_keeps_live_public_rooms_and_resolves_hls(self):
        payload = {
            "results": [
                {
                    "username": "alpha",
                    "display_name": "alpha",
                    "age": 24,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 900,
                    "tags": ["dance", "blonde"],
                    "room_subject": "live",
                    "image_url": "https://img.example/alpha.jpg",
                    "image_url_360p": "https://img.example/alpha-360.jpg",
                },
                {
                    "username": "teenstar",
                    "display_name": "teenstar",
                    "age": 22,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 5000,
                    "tags": [],
                    "room_subject": "",
                },
                {
                    "username": "beta",
                    "display_name": "beta",
                    "age": 28,
                    "gender": "f",
                    "current_show": "private",
                    "num_users": 800,
                    "tags": [],
                    "room_subject": "",
                },
                {
                    "username": "gamma",
                    "display_name": "gamma",
                    "age": 17,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 10,
                    "tags": [],
                    "room_subject": "",
                },
                {
                    "username": "delta",
                    "display_name": "delta",
                    "age": 30,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 100,
                    "tags": ["teen"],
                    "room_subject": "",
                },
                {
                    "username": "echo",
                    "display_name": "echo",
                    "age": 26,
                    "current_show": "public",
                    "num_users": 400,
                    "tags": [],
                    "room_subject": "live",
                },
                {
                    "username": "omega",
                    "display_name": "omega",
                    "age": 29,
                    "gender": "m",
                    "current_show": "public",
                    "num_users": 8000,
                    "tags": ["dance"],
                    "room_subject": "live",
                    "image_url": "https://img.example/omega.jpg",
                },
                {
                    "username": "sigma",
                    "display_name": "sigma",
                    "age": 31,
                    "gender": "c",
                    "current_show": "public",
                    "num_users": 7000,
                    "tags": ["lesbian", "orgy", "roleplay"],
                    "room_subject": "live",
                },
                {
                    "username": "tau",
                    "display_name": "tau",
                    "age": 27,
                    "gender": "s",
                    "current_show": "public",
                    "num_users": 6500,
                    "tags": ["dance"],
                    "room_subject": "live",
                },
                {
                    "username": "upsilon",
                    "display_name": "upsilon",
                    "age": 25,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 6000,
                    "tags": ["trans"],
                    "room_subject": "live",
                },
                {
                    "username": "phi",
                    "display_name": "phi",
                    "age": 28,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 5500,
                    "tags": ["shemale"],
                    "room_subject": "live",
                },
                {
                    "username": "rho",
                    "display_name": "rho",
                    "age": 26,
                    "gender": "f",
                    "current_show": "public",
                    "num_users": 50,
                    "tags": ["oil", "bdsm", "threesome", "cosplay"],
                    "room_subject": "nurse fetish",
                },
            ]
        }
        got = adult_rooms(payload)
        self.assertEqual(
            [row["id"] for row in got],
            ["adult-sigma", "adult-alpha", "adult-echo", "adult-rho"],
        )
        self.assertEqual(got[0]["name"], "SIGMA")
        self.assertEqual(got[0]["handle"], "sigma")
        self.assertEqual(got[0]["kinds"], ["COUPLE", "LESBIAN", "ORGY", "ROLEPLAY"])
        self.assertEqual(got[1]["name"], "ALPHA")
        self.assertEqual(got[1]["handle"], "alpha")
        self.assertEqual(got[1]["url"], "")
        self.assertEqual(got[1]["image"], "https://img.example/alpha-360.jpg")
        self.assertEqual(got[1]["kinds"], ["DANCE", "BLONDE"])
        self.assertEqual(got[2]["handle"], "echo")
        self.assertEqual(got[2]["image"], "")
        self.assertEqual(got[2]["kinds"], [])
        self.assertEqual(got[3]["handle"], "rho")
        self.assertEqual(got[3]["seek"], "oil bdsm threesome cosplay nurse fetish")
        self.assertEqual(got[3]["kinds"], ["ORGY", "ROLEPLAY", "BDSM", "FETISH", "NURSE"])
        self.assertTrue(adult_woman({"gender": "f"}))
        self.assertTrue(adult_woman({}))
        self.assertTrue(adult_woman({"gender": "c"}))
        self.assertTrue(adult_woman({"gender": "couple"}))
        self.assertTrue(adult_woman({"gender": "female"}))
        self.assertTrue(adult_woman({"gender": "females"}))
        self.assertTrue(adult_woman({"gender": "maleFemale"}))
        self.assertTrue(adult_clean("orgy roleplay couple"))
        self.assertFalse(adult_woman({"gender": "m"}))
        self.assertFalse(adult_woman({"gender": "male"}))
        self.assertFalse(adult_woman({"gender": "s"}))
        self.assertFalse(adult_woman({"gender": "trans"}))
        self.assertFalse(adult_woman({"gender": "shemale"}))
        self.assertFalse(adult_woman({"gender": "tgirl"}))
        self.assertFalse(adult_allows("transgirl"))
        self.assertFalse(adult_clean("shemale"))
        self.assertFalse(adult_clean("ladyboy live"))
        self.assertEqual(
            adult_image({"image_url": "https://img.example/a.jpg"}),
            "https://img.example/a.jpg",
        )
        self.assertEqual(
            adult_still("https://img.example/a.jpg"),
            "https://img.example/a.jpg",
        )
        self.assertIsNone(adult_still("http://img.example/a.jpg"))
        self.assertIsNone(adult_still("https://edge.example/live.m3u8"))
        self.assertEqual(
            adult_kinds(got),
            [
                "COUPLE",
                "ORGY",
                "ROLEPLAY",
                "BDSM",
                "BLONDE",
                "DANCE",
                "FETISH",
                "LESBIAN",
                "NURSE",
            ],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(got, kind="DANCE")],
            ["adult-alpha"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(got, kind="COUPLE")],
            ["adult-sigma"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(got, kind="ORGY")],
            ["adult-sigma", "adult-rho"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(got, query="echo")],
            ["adult-echo"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(got, query="oil")],
            ["adult-rho"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(got, query="nurse")],
            ["adult-rho"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(got, kind="BDSM")],
            ["adult-rho"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(got, kind="ALL")],
            ["adult-sigma", "adult-alpha", "adult-echo", "adult-rho"],
        )
        extra = adult_rooms(
            {
                "results": [
                    {
                        "username": "itsstephhoney21",
                        "display_name": "itsstephhoney21",
                        "age": 24,
                        "gender": "f",
                        "current_show": "public",
                        "num_users": 180,
                        "tags": ["braids", "roleplay"],
                        "room_subject": "sleeping robbery",
                    },
                    {
                        "username": "mulanvuitton",
                        "display_name": "Mulan Vuitton",
                        "age": 26,
                        "gender": "f",
                        "current_show": "public",
                        "num_users": 90,
                        "tags": ["pawn", "thief"],
                        "room_subject": "caught favors cnc",
                    },
                    {
                        "username": "zeta",
                        "display_name": "zeta",
                        "age": 29,
                        "gender": "f",
                        "current_show": "public",
                        "num_users": 40,
                        "tags": ["hostage"],
                        "room_subject": "thief caught sexual favors",
                    },
                ]
            }
        )
        self.assertEqual(
            extra[0]["kinds"],
            ["ROLEPLAY", "BRAIDS", "SLEEP", "ROBBERY"],
        )
        self.assertEqual(
            extra[1]["kinds"],
            ["FORCED", "PAWN", "THIEF", "FAVORS"],
        )
        self.assertEqual(extra[2]["kinds"], ["THIEF", "FAVORS", "HOSTAGE"])
        self.assertEqual(
            [row["id"] for row in adult_pick(extra, kind="BRAIDS")],
            ["adult-itsstephhoney21"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(extra, kind="SLEEP")],
            ["adult-itsstephhoney21"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(extra, kind="ROBBERY")],
            ["adult-itsstephhoney21"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(extra, kind="FORCED")],
            ["adult-mulanvuitton"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(extra, kind="PAWN")],
            ["adult-mulanvuitton"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(extra, kind="THIEF")],
            ["adult-mulanvuitton", "adult-zeta"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(extra, kind="FAVORS")],
            ["adult-mulanvuitton", "adult-zeta"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(extra, kind="ITSSTEPHHONEY21")],
            ["adult-itsstephhoney21"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(extra, kind="ITSSTEPHHONEYXO21")],
            ["adult-itsstephhoney21"],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(extra, kind="MULAN VUITTON")],
            ["adult-mulanvuitton"],
        )
        self.assertEqual(adult_pick(extra, kind="ITSSTEPHHONEY21", query="mulan"), [])
        self.assertEqual(
            adult_rail([]),
            [
                "ALL",
                "LOVESCAPE",
                "ITSSTEPHHONEY21",
                "ITSSTEPHHONEYXO21",
                "MULAN VUITTON",
                "MIKEILA J",
                "NERDY BEILA",
                "JUICYJAS TV",
                "HONEYTEASSEE",
                "TANIA RAMOS",
                "BRITTANYA RAZAVI",
                "HOT4LEXI",
                "LILI VICTORIA",
                "ZURI BELLA ROSE",
                "SARIIXO",
                "MONA ACUTEE",
                "IMHIZBAEEXX",
                "YESS ENIA69",
                "VAL2YUMMI",
                "KIRAWWRRRA",
                "JACQIE VAINS",
                "LILIANAS PAGE",
                "FREAKYYSTACKSS",
                "ASAIA HERNANDEZ",
                "JASMINEGTV",
                "IMANGELJESSYY",
                "GRACIE BONN",
                "DEBVARELA",
                "DOUBLE DOSE TWINS",
                "PAMELA YAMZ",
                "ANNABELLE RIOS",
                "NICOLEEE 1329",
                "EUNICEG",
                "STRAWBERRY SANDRA",
                "COUPLE",
                "ORGY",
                "ROLEPLAY",
                "BRAIDS",
                "SLEEP",
                "ROBBERY",
                "FORCED",
                "PAWN",
                "THIEF",
                "FAVORS",
            ],
        )
        fat_kinds = [f"KIND{index:02d}" for index in range(40)]
        fat = [
            {
                "id": "adult-fat",
                "name": "FAT",
                "handle": "fat",
                "url": "",
                "viewers": 1,
                "kinds": fat_kinds,
                "seek": "",
                "seconds": 0,
            }
        ]
        rail = adult_rail(fat)
        empty = adult_rail([])
        self.assertEqual(rail[:len(empty)], empty)
        self.assertLessEqual(len(rail), len(empty) + ADULT_RAIL_EXTRA)
        self.assertTrue(any(chip.startswith("KIND") for chip in rail))
        self.assertLess(len(rail), 14 + len(fat_kinds))
        love = adult_parse_love(
            {
                "models": [
                    {
                        "username": "enya-",
                        "gender": "female",
                        "genderGroup": "F",
                        "broadcastGender": "female",
                        "status": "public",
                        "isLive": True,
                        "viewersCount": 970,
                        "hlsPlaylist": "https://edge-hls.example/hls/1/master/1_240p.m3u8",
                        "previewUrlThumbSmall": "https://img.example/previews/a-thumb-small",
                        "groupShowTopic": "braids roleplay",
                    },
                    {
                        "username": "pair-live",
                        "gender": "maleFemale",
                        "genderGroup": "F",
                        "broadcastGender": "group",
                        "status": "public",
                        "isLive": True,
                        "viewersCount": 2200,
                        "hlsPlaylist": "https://edge-hls.example/hls/2/master/2_240p.m3u8",
                        "previewUrlThumbSmall": "https://img.example/previews/b-thumb-small",
                    },
                    {
                        "username": "man-lead",
                        "gender": "male",
                        "genderGroup": "M",
                        "broadcastGender": "male",
                        "status": "public",
                        "isLive": True,
                        "viewersCount": 9000,
                        "hlsPlaylist": "https://edge-hls.example/hls/3/master/3_240p.m3u8",
                    },
                    {
                        "username": "off-air",
                        "gender": "female",
                        "genderGroup": "F",
                        "status": "public",
                        "isLive": False,
                        "viewersCount": 10,
                    },
                    {
                        "username": "teenstar",
                        "gender": "female",
                        "genderGroup": "F",
                        "status": "public",
                        "isLive": True,
                        "viewersCount": 50,
                    },
                ]
            }
        )
        self.assertEqual([row["id"] for row in love], ["adult-love-enya-", "adult-love-pair-live"])
        self.assertEqual(love[0]["handle"], "enya-")
        self.assertTrue(love[0]["url"].endswith("_auto.m3u8"))
        self.assertEqual(love[0]["image"], "https://img.example/previews/a")
        self.assertEqual(love[0]["kinds"][0], "LOVESCAPE")
        self.assertIn("BRAIDS", love[0]["kinds"])
        self.assertIn("ROLEPLAY", love[0]["kinds"])
        self.assertEqual(love[1]["kinds"][:2], ["LOVESCAPE", "COUPLE"])
        self.assertEqual(
            [row["id"] for row in adult_pick(love + extra, kind="LOVESCAPE")],
            ["adult-love-enya-", "adult-love-pair-live"],
        )
        self.assertEqual(adult_topics("LOVESCAPE"), [])
        self.assertTrue(adult_love_needles("LOVESCAPE"))
        self.assertIn("primaryTag=girls", adult_love_directory("girls"))
        self.assertIn("lovescape.cam", adult_love_directory("girls"))
        self.assertTrue(adult_file_play("https://cdn.example/dload/abc/720/video.mp4"))
        self.assertIsNone(
            adult_live_play(
                "https://edge.example/live.m3u8",
                "#EXTM3U\n#EXT-X-MOUFLON-ADVERT\n#EXT-X-ENDLIST\n",
            )
        )
        self.assertIsNone(
            adult_live_play(
                "https://media.example/b-hls-1/1/1.m3u8",
                "#EXTM3U\n#EXTINF:2.000\nhttps://media.example/b-hls-1/media.mp4\n",
            )
        )
        self.assertEqual(
            adult_live_play(
                "https://edge.example/live.m3u8",
                "#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2.000\nhttps://edge.example/seg0.ts\n",
            ),
            "https://edge.example/live.m3u8",
        )
        self.assertIsNone(
            adult_live_play(
                "https://edge.example/master.m3u8",
                "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nhttps://edge.example/480p.m3u8\n",
            )
        )
        self.assertEqual(
            adult_love_variant(
                "https://edge.example/master.m3u8",
                "\n".join(
                    [
                        "#EXTM3U",
                        "#EXT-X-MOUFLON:PSCH:v2:Ook7quaiNgiyuhai",
                        "#EXT-X-STREAM-INF:BANDWIDTH=1,NAME=\"480p\"",
                        "https://media.example/1_480p.m3u8?playlistType=standard",
                        "#EXT-X-STREAM-INF:BANDWIDTH=2,NAME=\"240p\"",
                        "https://media.example/1_240p.m3u8?playlistType=standard",
                    ]
                ),
            ),
            "https://media.example/1_480p.m3u8?playlistType=standard&psch=v2&pkey=Ook7quaiNgiyuhai",
        )
        self.assertEqual(adult_count(712.0), 712)
        self.assertEqual(adult_count(1e20), 0)
        self.assertEqual(adult_count(float("nan")), 0)
        self.assertEqual(adult_count(float("inf")), 0)
        self.assertEqual(adult_count(-4), 0)
        self.assertIsNone(
            _adult_star_clip(
                {
                    "slug": "overflow-clip",
                    "title": "Mulan Vuitton overflow",
                    "creator": "mulanvuitton",
                    "durationSeconds": 1e20,
                    "views": 12,
                    "thumbnailUrl": "https://cdn.example/x.webp",
                },
                ["mulanvuitton"],
            )
        )
        self.assertEqual(adult_topics("BRAIDS"), ["braids", "braid", "cornrows"])
        self.assertEqual(adult_topics("ITSSTEPHHONEY21"), [])
        self.assertEqual(adult_topics("ALL"), [])
        self.assertIn("itsstephhoney21", adult_face_needles("ITSSTEPHHONEY21") or [])
        self.assertIn("&tag=braids", adult_directory("f", topic="braids"))
        self.assertEqual(
            adult_face_room(
                "itsstephhoney21",
                {
                    "room_status": "public",
                    "hls_source": "https://edge.example/live-hls/amlst:steph/playlist.m3u8",
                    "broadcaster_username": "itsstephhoney21",
                    "gender": "f",
                    "age": 24,
                    "num_viewers": 12,
                    "room_title": "live",
                },
            )["id"],
            "adult-itsstephhoney21",
        )
        self.assertIsNone(
            adult_face_room(
                "itsstephhoney21",
                {
                    "room_status": "private",
                    "hls_source": "https://edge.example/x.m3u8",
                    "gender": "f",
                    "age": 24,
                },
            )
        )
        self.assertIn("mulan vuitton", adult_face_queries("MULAN VUITTON"))
        self.assertIn("mulan-vuitton", adult_face_queries("MULAN VUITTON"))
        self.assertIn("vuitton mulan", adult_face_queries("MULAN VUITTON"))
        self.assertIn("mulan vuitton tv", adult_face_queries("MULAN VUITTON"))
        self.assertNotIn("erika vuitton", adult_face_queries("MULAN VUITTON"))
        self.assertEqual(adult_face_queries("MIKEILA J")[0], "mikeilaj")
        self.assertIn("mikeila j", adult_face_queries("MIKEILA J"))
        self.assertIn("theemikeilaj", adult_face_queries("MIKEILA J"))
        self.assertIn("mikeilajbaee", adult_face_queries("MIKEILA J"))
        self.assertIn("mikeilajduhh", adult_face_gift_tokens("MIKEILA J"))
        self.assertNotIn("mikeila", adult_face_needles("MIKEILA J") or [])
        self.assertEqual(adult_topics("MIKEILA J"), [])
        self.assertEqual(adult_face_star_tokens("MIKEILA J"), [])
        self.assertEqual(adult_face_pin_tokens("MIKEILA J"), [])
        self.assertEqual(adult_gift_key("mulan vuitton"), "mulanvuitton")
        self.assertEqual(adult_gift_key("mulan-vuitton"), "mulanvuitton")
        self.assertIn("mulan-vuitton", adult_face_star_tokens("MULAN VUITTON"))
        self.assertIn("mulanvuittontv", adult_face_gift_tokens("MULAN VUITTON"))
        self.assertIn("itsstephhoney21", adult_face_queries("ITSSTEPHHONEY21"))
        self.assertIn("query=mulan%20vuitton", adult_face_search("mulan vuitton") or "")
        self.assertEqual(
            adult_face_file("L3HLNRZy6sk"),
            "https://www.eporner.com/dload/L3HLNRZy6sk/720/video.mp4",
        )
        self.assertIsNone(adult_face_file("mulan vuitton"))
        self.assertEqual(adult_clock(184), "3:04")
        self.assertEqual(adult_clock(3661), "1:01:01")
        clips = adult_parse_face(
            {
                "videos": [
                    {
                        "id": "JpvjXbC6Ehu",
                        "title": "Mulan \u200bvuitton \u200bComplete \u200bLibrary \u200bAt \u200b",
                        "length_sec": 488,
                        "views": 10,
                        "keywords": "amateur",
                        "default_thumb": {"src": "https://img.example/leak.jpg"},
                    },
                    {
                        "id": "L3HLNRZy6sk",
                        "title": "Mulan Vuitton",
                        "length_sec": 184,
                        "views": 17514,
                        "keywords": "big ass, ebony, Mulan Vuitton",
                        "default_thumb": {"src": "https://img.example/mulan.jpg"},
                    },
                    {
                        "id": "shortclip1",
                        "title": "Mulan Vuitton night",
                        "length_sec": 90,
                        "views": 9,
                        "keywords": "Mulan Vuitton",
                        "default_thumb": {"src": "https://img.example/night.jpg"},
                    },
                    {
                        "id": "erika1",
                        "title": "Erika Vuitton Couch",
                        "length_sec": 2109,
                        "views": 99,
                        "keywords": "erika vuitton",
                    },
                    {
                        "id": "teen1",
                        "title": "Mulan Vuitton teen",
                        "length_sec": 600,
                        "views": 5,
                        "keywords": "Mulan Vuitton",
                    },
                ]
            },
            "MULAN VUITTON",
        )
        self.assertEqual(
            [row["id"] for row in clips],
            [
                "adult-face-teen1",
                "adult-face-jpvjxbc6ehu",
                "adult-face-l3hlnrzy6sk",
                "adult-face-shortclip1",
            ],
        )
        self.assertEqual(clips[2]["seconds"], 184)
        self.assertEqual(clips[2]["url"], "https://www.eporner.com/dload/L3HLNRZy6sk/720/video.mp4")
        self.assertEqual(clips[2]["kinds"], ["MULAN VUITTON"])
        pin = adult_parse_face(
            {
                "id": "L3HLNRZy6sk",
                "title": "Mulan Vuitton",
                "length_sec": 184,
                "views": 17514,
                "keywords": "Mulan Vuitton",
                "default_thumb": {"src": "https://img.example/mulan.jpg"},
            },
            "MULAN VUITTON",
        )
        self.assertEqual([row["id"] for row in pin], ["adult-face-l3hlnrzy6sk"])
        self.assertEqual(
            adult_parse_face(
                {
                    "discoverVideos": [
                        {
                            "slug": "wrong-person",
                            "title": "Wrong Person",
                            "creator": "Other",
                            "durationSeconds": 900,
                        }
                    ]
                },
                "MULAN VUITTON",
            ),
            [],
        )
        self.assertEqual(
            [row["id"] for row in adult_pick(clips, kind="MULAN VUITTON")],
            [
                "adult-face-teen1",
                "adult-face-jpvjxbc6ehu",
                "adult-face-l3hlnrzy6sk",
                "adult-face-shortclip1",
            ],
        )
        self.assertEqual(adult_parse_face({"videos": []}, "ITSSTEPHHONEY21"), [])
        self.assertIn("its steph honey", adult_face_queries("ITSSTEPHHONEY21"))
        self.assertIn("itsstephhoneyxo21", adult_face_needles("ITSSTEPHHONEY21") or [])
        self.assertIn("itsstephhoneyxo21", adult_face_needles("ITSSTEPHHONEYXO21") or [])
        self.assertEqual(adult_face_queries("ITSSTEPHHONEY21")[0], "itsstephhoneyxo21")
        self.assertEqual(adult_face_queries("ITSSTEPHHONEYXO21")[0], "itsstephhoneyxo21")
        self.assertIn("stephaniehvip", adult_face_queries("ITSSTEPHHONEY21"))
        self.assertTrue(any("api.redgifs.com/v2/users/itsstephhoneyxo21/search" in path for path in adult_face_hunt("ITSSTEPHHONEYXO21")))
        self.assertTrue(any("bornstar.co/api/search" in path for path in adult_face_hunt("MULAN VUITTON")))
        self.assertTrue(any("eporner.com/api/v2/video/search" in path for path in adult_face_hunt("MULAN VUITTON")))
        self.assertTrue(any("eporner.com/api/v2/video/id/?id=L3HLNRZy6sk" in path for path in adult_face_hunt("MULAN VUITTON")))
        self.assertTrue(any("eporner.com/api/v2/video/id/?id=P283XrKRjsV" in path for path in adult_face_hunt("ITSSTEPHHONEY21")))
        self.assertTrue(any("api.redgifs.com/v2/gifs/search" in path for path in adult_face_hunt("ITSSTEPHHONEY21")))
        self.assertTrue(any("api.redgifs.com/v2/users/itsstephhoney21/search" in path for path in adult_face_hunt("ITSSTEPHHONEY21")))
        mulan_hunt = adult_face_hunt("MULAN VUITTON")
        self.assertTrue(mulan_hunt[0].endswith("id=L3HLNRZy6sk&format=json"))
        self.assertTrue(any("api/v2/video/id/?id=pYaoSJlMR79" in path for path in mulan_hunt))
        self.assertTrue(any("bornstar.co/api/search?q=mulan-vuitton" in path for path in mulan_hunt))
        self.assertTrue(any("gifs/search?search_text=mulanvuitton" in path for path in mulan_hunt))
        self.assertTrue(any("users/mulanvuitton/search" in path for path in mulan_hunt))
        self.assertTrue(any("users/mulanvuittontv/search" in path for path in mulan_hunt))
        self.assertGreaterEqual(len(mulan_hunt), 8)
        mikeila_hunt = adult_face_hunt("MIKEILA J")
        self.assertTrue(any("eporner.com/api/v2/video/search/?query=mikeilaj" in path for path in mikeila_hunt))
        self.assertTrue(any("bornstar.co/api/search?q=mikeilaj" in path for path in mikeila_hunt))
        self.assertTrue(any("gifs/search?search_text=mikeilaj" in path for path in mikeila_hunt))
        self.assertTrue(any("users/mikeilaj/search" in path for path in mikeila_hunt))
        self.assertTrue(any("users/theemikeilaj/search" in path for path in mikeila_hunt))
        self.assertTrue(any("users/mikeilajbaee/search" in path for path in mikeila_hunt))
        self.assertFalse(any("video/id/" in path for path in mikeila_hunt))
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "id": "mikekeep1",
                            "title": "mikeilaj guest file",
                            "length_sec": 640,
                            "views": 4,
                            "keywords": "mikeilaj",
                            "default_thumb": {"src": "https://img.example/mikeila.jpg"},
                        },
                        {
                            "id": "mikewrong1",
                            "title": "Olive Evans Gets Her Ass Plowed By Mike Williams",
                            "length_sec": 3156,
                            "views": 9,
                            "keywords": "mike williams",
                        },
                        {
                            "id": "mikaelawrong",
                            "title": "Mikaela Testa Sucks Cock Then Gets Plowed In The Kitchen",
                            "length_sec": 323,
                            "views": 3,
                            "keywords": "mikaela testa",
                        },
                    ]
                },
                "MIKEILA J",
            )],
            ["adult-face-mikekeep1"],
        )
        self.assertIn("nerdy beila", adult_face_queries("NERDY BEILA"))
        self.assertIn("vip.nerdyb", adult_face_queries("NERDY BEILA"))
        self.assertNotIn("nerdy b", adult_face_needles("NERDY BEILA") or [])
        self.assertTrue(any("id=33TgD6OeUfp" in path for path in adult_face_hunt("NERDY BEILA")))
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "id": "33TgD6OeUfp",
                            "title": "Beila B/Nerdy B Big Tits Cosplay PMV (Pt. 2)",
                            "length_sec": 1472,
                            "views": 8,
                            "keywords": "beila",
                        },
                        {
                            "id": "nerdywrong",
                            "title": "Nerdy Alina Lopez Gets Fucked Hard By A BWC",
                            "length_sec": 2275,
                            "views": 9,
                            "keywords": "alina lopez",
                        },
                    ]
                },
                "NERDY BEILA",
            )],
            ["adult-face-33tgd6oeufp"],
        )
        self.assertIn("hot4lexi", adult_face_star_tokens("HOT4LEXI"))
        self.assertTrue(any("bornstar.co/api/search?q=hot4lexi" in path for path in adult_face_hunt("HOT4LEXI")))
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "slug": "hot4lexi-missionary-sextape-video-leaked",
                            "title": "Hot4lexi Missionary Sextape Video Leaked",
                            "creator": "Hot4lexi",
                            "durationSeconds": 517,
                        },
                        {
                            "slug": "lexi-marvel-teases-in-her-lingerie",
                            "title": "Lexi Marvel Teases In Her Lingerie",
                            "creator": "Lexi Marvel",
                            "durationSeconds": 381,
                        },
                    ]
                },
                "HOT4LEXI",
            )],
            ["adult-face-star-hot4lexi-missionary-sextape-video-leaked"],
        )
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "id": "ZxMHa5OsXqH",
                            "title": "Brittanya Razavi",
                            "length_sec": 503,
                            "views": 12,
                            "keywords": "brittanya razavi",
                        },
                        {
                            "id": "brittwrong",
                            "title": "Brittany Elizabeth Welsh Flaunts Her Huge Tits",
                            "length_sec": 458,
                            "views": 7,
                            "keywords": "brittany elizabeth",
                        },
                    ]
                },
                "BRITTANYA RAZAVI",
            )],
            ["adult-face-zxmha5osxqh"],
        )
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "slug": "zuri-bella-rose-takes-a-dick-in-multiple-positions",
                            "title": "Zuri Bella Rose Takes A Dick In Multiple Positions",
                            "creator": "Zuri Bella Rose",
                            "durationSeconds": 792,
                            "performers": [{"slug": "zuri-bella-rose", "name": "Zuri Bella Rose"}],
                        },
                        {
                            "slug": "hailey-rose-joins-her-friends",
                            "title": "Hailey Rose Joins Her Friends Grind On Two BBCs",
                            "creator": "Abella Danger",
                            "durationSeconds": 2639,
                        },
                    ]
                },
                "ZURI BELLA ROSE",
            )],
            ["adult-face-star-zuri-bella-rose-takes-a-dick-in-multiple-positions"],
        )
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "slug": "sariixo-fucks-her-pussy-with-a-bbc-dildo-in-bed",
                            "title": "Sariixo Fucks Her Pussy With A BBC Dildo In Bed",
                            "creator": "Sariixo",
                            "durationSeconds": 602,
                        },
                        {
                            "slug": "bustyema-official-teases",
                            "title": "BustyEma_Official Teases And Gives A Titjob",
                            "creator": "BustyEma_Official",
                            "durationSeconds": 334,
                        },
                    ]
                },
                "SARIIXO",
            )],
            ["adult-face-star-sariixo-fucks-her-pussy-with-a-bbc-dildo-in-bed"],
        )
        self.assertIn("kirawrrra2-0", adult_face_star_tokens("KIRAWWRRRA"))
        self.assertTrue(any("bornstar.co/api/search?q=kirawrrra2.0" in path for path in adult_face_hunt("KIRAWWRRRA")))
        self.assertTrue(any("bornstar.co/api/search?q=kirawrrra2-0" in path for path in adult_face_hunt("KIRAWWRRRA")))
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "slug": "kirawrrra2-0-fills-her-ass-for-the-first-time",
                            "title": "Kirawrrra2.0 Fills Her Ass For The First Time",
                            "creator": "Kirawrrra2.0",
                            "durationSeconds": 211,
                        },
                        {
                            "slug": "kira-pregiato-teases",
                            "title": "Kira Pregiato Teases",
                            "creator": "Kira Pregiato",
                            "durationSeconds": 400,
                        },
                        {
                            "slug": "your-kira-plays-with-a-dildo",
                            "title": "Your Kira Plays With A Dildo Until She Cums",
                            "creator": "Your Kira",
                            "durationSeconds": 506,
                        },
                    ]
                },
                "KIRAWWRRRA",
            )],
            ["adult-face-star-kirawrrra2-0-fills-her-ass-for-the-first-time"],
        )
        self.assertEqual(adult_parse_face(
            {
                "videos": [
                    {
                        "slug": "a-little-girl-is-taking-a-bubble-bath-in-the-shower",
                        "title": "Your Kira - A Little Girl Is Taking A Bubble Bath In The Shower",
                        "creator": "Kirawrrra2.0",
                        "durationSeconds": 362,
                    }
                ]
            },
            "KIRAWWRRRA",
        ), [])
        self.assertTrue(any("id=iXWnuAL4FnV" in path for path in adult_face_hunt("DOUBLE DOSE TWINS")))
        self.assertTrue(any("id=NtQUcCtcTj0" in path for path in adult_face_hunt("DOUBLE DOSE TWINS")))
        self.assertTrue(any("id=7bg2FgwidLS" in path for path in adult_face_hunt("DOUBLE DOSE TWINS")))
        self.assertEqual(
            [row["id"] for row in adult_face_hold_rooms("KIRAWWRRRA")],
            ["adult-face-star-kirawrrra2-0-fills-her-ass-for-the-first-time"],
        )
        self.assertEqual(adult_face_hold_rooms("KIRAWWRRRA")[0]["seconds"], 211)
        self.assertEqual(
            [row["id"] for row in adult_pick(adult_face_hold_rooms("KIRAWWRRRA"), kind="KIRAWWRRRA")],
            ["adult-face-star-kirawrrra2-0-fills-her-ass-for-the-first-time"],
        )
        self.assertEqual(adult_face_hold_rooms("IMHIZBAEEXX"), [])
        self.assertGreaterEqual(len(adult_face_hold_rooms("ALL")), 10)
        self.assertGreaterEqual(len(adult_face_hold_rooms("")), 10)
        self.assertEqual(
            adult_face_hold_rooms("KIRAWWRRRA")[0]["image"],
            "https://cdn.bornstar.co/preview-batch/kirawrrra2-0-fills-her-ass-for-the-first-time/thumb.webp",
        )
        self.assertTrue(
            all(str(row.get("image") or "").startswith("https://") for row in adult_face_hold_rooms("ALL"))
        )
        self.assertTrue(
            all(str(row.get("image") or "").startswith("https://") for row in adult_face_hold_rooms("DOUBLE DOSE TWINS"))
        )
        held = adult_face_hold_rooms("KIRAWWRRRA")
        lives = [
            {
                "id": f"adult-{index}",
                "name": f"L{index}",
                "handle": f"l{index}",
                "url": "https://example.com/live.m3u8",
                "viewers": 1000 - index,
                "image": "",
                "kinds": [],
                "seek": "",
                "seconds": 0,
            }
            for index in range(ADULT_CAP)
        ]
        merged = adult_merge([held, lives])
        ids = [row["id"] for row in merged]
        self.assertEqual(len(merged), ADULT_CAP)
        self.assertIn(held[0]["id"], ids)
        self.assertEqual(ids[0], "adult-0")
        self.assertNotIn(f"adult-{ADULT_CAP - 1}", ids)
        self.assertEqual(
            adult_merge(
                [
                    [{"id": "adult-face-pin", "name": "A", "viewers": 0, "image": "https://img.example/a.jpg", "seconds": 10}],
                    [{"id": "adult-face-pin", "name": "A", "viewers": 9, "image": "", "seconds": 10}],
                ]
            )[0]["image"],
            "https://img.example/a.jpg",
        )
        self.assertLessEqual(len(adult_face_hunt("MULAN VUITTON")), ADULT_HUNT_CAP)
        self.assertLessEqual(len(adult_face_hunt("KIRAWWRRRA")), ADULT_HUNT_CAP)
        self.assertTrue(any("thumbsize=big" in path for path in adult_face_hunt("MULAN VUITTON")))
        self.assertTrue(any("per_page=80" in path for path in adult_face_hunt("MULAN VUITTON")))
        self.assertGreaterEqual(len(adult_face_hold_rooms("MULAN VUITTON")), 4)
        self.assertGreaterEqual(len(adult_face_hold_rooms("DOUBLE DOSE TWINS")), 3)
        self.assertNotIn("double dose", adult_face_needles("DOUBLE DOSE TWINS") or [])
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "id": "iXWnuAL4FnV",
                            "title": "Untitled guest file",
                            "length_sec": 140,
                            "views": 4,
                            "keywords": "",
                        },
                        {
                            "id": "NtQUcCtcTj0",
                            "title": "Doubledose Twins Blowjob GAWD DAMN I NEED DAT",
                            "length_sec": 199,
                            "views": 6,
                            "keywords": "Doubledose Twins",
                        },
                        {
                            "id": "dosedosewrong",
                            "title": "Double Dose Of Cum For This Slut",
                            "length_sec": 900,
                            "views": 9,
                            "keywords": "double dose",
                        },
                    ]
                },
                "DOUBLE DOSE TWINS",
            )],
            ["adult-face-ntqucctctj0", "adult-face-ixwnual4fnv"],
        )
        self.assertNotIn("yessenia", adult_face_needles("YESS ENIA69") or [])
        self.assertNotIn("yess_enia", adult_face_needles("YESS ENIA69") or [])
        self.assertNotIn("yessenia", [adult_gift_key(query) for query in adult_face_queries("YESS ENIA69")])
        self.assertFalse(any("users/yessenia/search" in path for path in adult_face_hunt("YESS ENIA69")))
        self.assertTrue(any("users/yessenia69/search" in path for path in adult_face_hunt("YESS ENIA69")))
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "id": "yesswrong",
                            "title": "Yessenia Shows Her Pretty Feet",
                            "length_sec": 300,
                            "views": 5,
                            "keywords": "yessenia feet",
                        }
                    ]
                },
                "YESS ENIA69",
            )],
            [],
        )
        self.assertNotIn("graciebon", adult_face_needles("GRACIE BONN") or [])
        self.assertFalse(any("users/graciebon/search" in path for path in adult_face_hunt("GRACIE BONN")))
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "slug": "graciebon-teases-with-a-huge-dildo",
                            "title": "Graciebon Teases With A Huge Dildo",
                            "creator": "Graciebon",
                            "durationSeconds": 4532,
                        }
                    ]
                },
                "GRACIE BONN",
            )],
            [],
        )
        self.assertNotIn("jasmine", adult_face_needles("JASMINEGTV") or [])
        self.assertNotIn("nicole", adult_face_needles("NICOLEEE 1329") or [])
        self.assertNotIn("kira", adult_face_needles("KIRAWWRRRA") or [])
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "slug": "nina-lee-jasmine-teaa-share-mike-williams-bbc",
                            "title": "Nina Lee & Jasmine Teaa Share Mike Williams BBC",
                            "creator": "Jasmine Teaa",
                            "durationSeconds": 1807,
                        }
                    ]
                },
                "JASMINEGTV",
            )],
            [],
        )
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "slug": "nicole-doshi-dresses-as-ada-wong",
                            "title": "Nicole Doshi Dresses As Ada Wong",
                            "creator": "Nicole Doshi",
                            "durationSeconds": 1785,
                        }
                    ]
                },
                "NICOLEEE 1329",
            )],
            [],
        )
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "slug": "anna-ralphs-the-best-blowjob-ever",
                            "title": "Anna Ralphs The Best Blowjob Ever",
                            "creator": "Anna Ralphs",
                            "durationSeconds": 2005,
                        }
                    ]
                },
                "ANNABELLE RIOS",
            )],
            [],
        )
        self.assertIn("imhizbaeexx", adult_face_queries("IMHIZBAEEXX"))
        self.assertIn("val2yummi", adult_face_queries("VAL2YUMMI"))
        self.assertIn("jacqievains", adult_face_queries("JACQIE VAINS"))
        self.assertIn("lilianaspage", adult_face_queries("LILIANAS PAGE"))
        self.assertIn("freakyystackss", adult_face_queries("FREAKYYSTACKSS"))
        self.assertIn("asaiahernandez", adult_face_queries("ASAIA HERNANDEZ"))
        self.assertIn("imangeljessyy", adult_face_queries("IMANGELJESSYY"))
        self.assertIn("debvarela", adult_face_queries("DEBVARELA"))
        self.assertIn("pamelayamz", adult_face_queries("PAMELA YAMZ"))
        self.assertIn("euniceg", adult_face_queries("EUNICEG"))
        self.assertIn("strawberrysandra20", adult_face_queries("STRAWBERRY SANDRA"))
        self.assertTrue(any("users/imhizbaeexx/search" in path for path in adult_face_hunt("IMHIZBAEEXX")))
        self.assertEqual(adult_face_queries("HONEYTEASSEE")[0], "honeyteassee")
        self.assertNotIn("honey tea", adult_face_needles("HONEYTEASSEE") or [])
        self.assertIn("taniaaaramos", adult_face_queries("TANIA RAMOS"))
        self.assertNotIn("tania ramos", adult_face_needles("TANIA RAMOS") or [])
        self.assertIn("juicyjastv", adult_face_queries("JUICYJAS TV"))
        self.assertIn("lilivictoria32", adult_face_queries("LILI VICTORIA"))
        self.assertIn("monaacutee", adult_face_queries("MONA ACUTEE"))
        self.assertTrue(any("users/honeyteassee/search" in path for path in adult_face_hunt("HONEYTEASSEE")))
        self.assertTrue(any("users/taniaaaramos/search" in path for path in adult_face_hunt("TANIA RAMOS")))
        self.assertTrue(any("users/juicyjastv/search" in path for path in adult_face_hunt("JUICYJAS TV")))
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "id": "L3HLNRZy6sk",
                    "title": "Untitled guest file",
                    "length_sec": 184,
                    "views": 4,
                    "keywords": "",
                    "default_thumb": {"src": "https://img.example/pin.jpg"},
                },
                "MULAN VUITTON",
            )],
            ["adult-face-l3hlnrzy6sk"],
        )
        self.assertEqual(
            [row["id"] for row in adult_parse_face(
                {
                    "videos": [
                        {
                            "slug": "scene-three",
                            "title": "Scene 3",
                            "creator": "",
                            "durationSeconds": 940,
                            "thumbnailUrl": "https://cdn.example/scene.webp",
                            "performers": [{"name": "", "slug": "mulan-vuitton"}],
                        }
                    ]
                },
                "MULAN VUITTON",
            )],
            ["adult-face-star-scene-three"],
        )
        steph = adult_parse_face(
            {
                "videos": [
                    {
                        "id": "P283XrKRjsV",
                        "title": "stephaniehvip \u200btwerks \u200band \u200bjiggles Explore Full Videos At chatnow.cam",
                        "length_sec": 158,
                        "views": 20,
                        "keywords": "stephaniehvip, students",
                        "default_thumb": {"src": "https://img.example/steph.jpg"},
                    },
                    {
                        "id": "xo21file",
                        "title": "itsstephhoneyxo21 teen night",
                        "length_sec": 940,
                        "views": 8,
                        "keywords": "itsstephhoneyxo21",
                        "default_thumb": {"src": "https://img.example/xo.jpg"},
                    },
                    {
                        "id": "loli1",
                        "title": "itsstephhoney21 loli",
                        "length_sec": 1200,
                        "views": 1,
                        "keywords": "itsstephhoney21",
                    },
                    {
                        "id": "honey1",
                        "title": "Honey Sasha Ride",
                        "length_sec": 433,
                        "views": 9,
                        "keywords": "honey sasha",
                    },
                ]
            },
            "ITSSTEPHHONEY21",
        )
        self.assertEqual(
            [row["id"] for row in steph],
            ["adult-face-xo21file", "adult-face-p283xrkrjsv"],
        )
        self.assertEqual(steph[0]["seconds"], 940)
        gifts = adult_parse_face(
            {
                "gifs": [
                    {
                        "id": "stephgif1",
                        "userName": "itsstephhoney21",
                        "description": "itsstephhoney21 shower",
                        "duration": 46.2,
                        "views": 11,
                        "tags": ["itsstephhoney21"],
                        "urls": {
                            "hd": "https://media.example/steph.gif.mp4",
                            "thumbnail": "https://img.example/steph.gif.jpg",
                        },
                    },
                    {
                        "id": "wronggif",
                        "userName": "lllunna",
                        "description": "other girl",
                        "duration": 14.9,
                        "urls": {"hd": "https://media.example/wrong.mp4"},
                    },
                ]
            },
            "ITSSTEPHHONEY21",
        )
        self.assertEqual([row["id"] for row in gifts], ["adult-face-gift-stephgif1"])
        self.assertEqual(gifts[0]["seconds"], 46)
        self.assertTrue(gifts[0]["url"].endswith(".mp4"))
        self.assertEqual(adult_gift_token({"token": "abc"}), "abc")
        self.assertEqual(adult_gift_session({"session": 462764204617768036}), "462764204617768036")
        self.assertEqual(
            adult_gift_headers("https://api.redgifs.com/v2/gifs/search?search_text=x", "abc", "9")["Authorization"],
            "Bearer abc",
        )
        self.assertEqual(adult_gift_headers("https://www.eporner.com/api/v2/video/search/?query=x", "abc"), {})
        self.assertEqual(
            adult_star_file("mulan-vuitton-has-sex-with-a-thief"),
            "https://cdn.bornstar.co/videos/mulan-vuitton-has-sex-with-a-thief/master.m3u8",
        )
        self.assertIsNone(adult_star_file("mulan vuitton"))
        stars = adult_parse_face(
            {
                "videos": [
                    {
                        "id": "mulan-vuitton-has-sex-with-a-thief",
                        "slug": "mulan-vuitton-has-sex-with-a-thief",
                        "title": "Mulan Vuitton Has Sex With A Thief",
                        "creator": "Mulan Vuitton",
                        "durationSeconds": 712,
                        "thumbnailUrl": "https://cdn.example/mulan.webp",
                    },
                    {
                        "id": "honey-sasha-wrong-person",
                        "slug": "honey-sasha-wrong-person",
                        "title": "Honey Sasha Ride",
                        "creator": "Honey Sasha",
                        "durationSeconds": 433,
                    },
                    {
                        "id": "erika-vuitton-couch",
                        "slug": "erika-vuitton-couch",
                        "title": "Erika Vuitton Couch",
                        "creator": "Erika Vuitton",
                        "durationSeconds": 2109,
                    },
                ]
            },
            "MULAN VUITTON",
        )
        self.assertEqual([row["id"] for row in stars], ["adult-face-star-mulan-vuitton-has-sex-with-a-thief"])
        self.assertEqual(stars[0]["seconds"], 712)
        self.assertEqual(stars[0]["kinds"], ["MULAN VUITTON"])
        self.assertTrue(stars[0]["url"].endswith("/master.m3u8"))
        self.assertEqual(
            adult_live_play(
                "https://cdn.example/videos/x/master.m3u8",
                "#EXTM3U\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:10.000\nseg_000.ts\n#EXT-X-ENDLIST\n",
            ),
            "https://cdn.example/videos/x/master.m3u8",
        )
        self.assertTrue(adult_allows("alpha"))
        self.assertFalse(adult_allows("teenstar"))
        self.assertEqual(
            adult_playlist("https://www.eporner.com/dload/L3HLNRZy6sk/720/video.mp4"),
            "https://www.eporner.com/dload/L3HLNRZy6sk/720/video.mp4",
        )
        self.assertIsNone(adult_playlist("http://insecure.example/x.m3u8"))
        self.assertIsNone(
            adult_playlist("https://media-hls.example/b-hls-1/cpa/v2/stream.m3u8")
        )
        self.assertEqual(
            adult_stream(
                {
                    "room_status": "public",
                    "hls_source": "https://edge.example/live-hls/amlst:alpha/playlist.m3u8",
                }
            ),
            "https://edge.example/live-hls/amlst:alpha/playlist.m3u8",
        )
        self.assertIsNone(
            adult_stream(
                {
                    "room_status": "public",
                    "hls_source": "https://media-hls.example/b-hls-1/cpa/v2/stream.m3u8",
                }
            )
        )
        self.assertIsNone(
            adult_stream({"room_status": "private", "hls_source": "https://edge.example/x.m3u8"})
        )
        desk = read("Blackout", "AdultDesk.swift")
        sock = read("Blackout", "UpdateSocket.swift")
        live = read("Blackout", "NaLive.swift")
        tv = read("Blackout", "TvPlate.swift")
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn("enum AdultDesk", desk)
        self.assertIn("static let cap", desk)
        self.assertIn("= 800", desk)
        self.assertIn("static let pageSize", desk)
        self.assertIn("static let pages", desk)
        self.assertIn("static func parse(", desk)
        self.assertIn("static func playlist(", desk)
        self.assertIn("static func directory(", desk)
        self.assertIn("static func context(", desk)
        self.assertIn("static func edge(", desk)
        self.assertIn("static func stream(", desk)
        self.assertIn("get_edge_hls_url_ajax", desk)
        self.assertIn("offset", desk)
        self.assertIn("chaturbate.com", desk.lower())
        self.assertIn("affiliates/onlinerooms", desk)
        self.assertIn('static let tags = ["f", "c"]', desk)
        self.assertNotIn('["f", "c", "m", "s"]', desk)
        self.assertIn("COUPLE", desk)
        self.assertIn("ORGY", desk)
        self.assertIn("ROLEPLAY", desk)
        self.assertIn("BDSM", desk)
        self.assertIn("threesome", desk)
        self.assertIn("cosplay", desk)
        self.assertIn("static let pin", desk)
        self.assertIn("BRAIDS", desk)
        self.assertIn("SLEEP", desk)
        self.assertIn("ROBBERY", desk)
        self.assertIn("FORCED", desk)
        self.assertIn("PAWN", desk)
        self.assertIn("THIEF", desk)
        self.assertIn("FAVORS", desk)
        self.assertIn("ITSSTEPHHONEY21", desk)
        self.assertIn("ITSSTEPHHONEYXO21", desk)
        self.assertIn("itsstephhoneyxo21", desk)
        self.assertIn("stephaniehvip", desk)
        self.assertIn("P283XrKRjsV", desk)
        self.assertIn("MULAN VUITTON", desk)
        self.assertIn("MIKEILA J", desk)
        self.assertIn("NERDY BEILA", desk)
        self.assertIn("JUICYJAS TV", desk)
        self.assertIn("HONEYTEASSEE", desk)
        self.assertIn("TANIA RAMOS", desk)
        self.assertIn("BRITTANYA RAZAVI", desk)
        self.assertIn("HOT4LEXI", desk)
        self.assertIn("LILI VICTORIA", desk)
        self.assertIn("ZURI BELLA ROSE", desk)
        self.assertIn("SARIIXO", desk)
        self.assertIn("MONA ACUTEE", desk)
        self.assertIn("IMHIZBAEEXX", desk)
        self.assertIn("YESS ENIA69", desk)
        self.assertIn("VAL2YUMMI", desk)
        self.assertIn("KIRAWWRRRA", desk)
        self.assertIn("JACQIE VAINS", desk)
        self.assertIn("LILIANAS PAGE", desk)
        self.assertIn("FREAKYYSTACKSS", desk)
        self.assertIn("ASAIA HERNANDEZ", desk)
        self.assertIn("JASMINEGTV", desk)
        self.assertIn("IMANGELJESSYY", desk)
        self.assertIn("GRACIE BONN", desk)
        self.assertIn("DEBVARELA", desk)
        self.assertIn("DOUBLE DOSE TWINS", desk)
        self.assertIn("PAMELA YAMZ", desk)
        self.assertIn("ANNABELLE RIOS", desk)
        self.assertIn("NICOLEEE 1329", desk)
        self.assertIn("EUNICEG", desk)
        self.assertIn("STRAWBERRY SANDRA", desk)
        self.assertIn("iXWnuAL4FnV", desk)
        self.assertIn("NtQUcCtcTj0", desk)
        self.assertIn("7bg2FgwidLS", desk)
        self.assertIn("kirawrrra2-0", desk)
        self.assertIn("static let faceHolds", desk)
        self.assertIn("static let faceStills", desk)
        self.assertIn("static func faceStill(", desk)
        self.assertIn("static func faceKeep(", desk)
        self.assertIn("preview-batch", desk)
        self.assertIn("static-ca-cdn.eporner.com", desk)
        self.assertIn("static let huntCap", desk)
        self.assertIn("static let huntPages", desk)
        self.assertIn("static func faceHoldRooms(", desk)
        self.assertIn("kirawrrra2-0-fills-her-ass-for-the-first-time", desk)
        self.assertIn("mulan-vuitton-has-sex-with-a-thief", desk)
        self.assertIn("thumbsize=big", desk)
        self.assertIn("per_page=80", desk)
        self.assertIn("yessenia69", desk)
        self.assertNotIn('"yessenia"', desk)
        self.assertNotIn("yess_enia\"", desk.replace("yess_enia69", ""))
        self.assertIn("beilaNeedles", desk)
        self.assertIn("vip.nerdyb", desk)
        self.assertIn("lexi2legit", desk)
        self.assertIn("seebrittanya", desk)
        self.assertIn("zuri-bella-rose", desk)
        self.assertIn("mikeilaNeedles", desk)
        self.assertIn("mikeilajbaee", desk)
        self.assertIn("theemikeilaj", desk)
        self.assertIn("mulanNeedles", desk)
        self.assertIn("mulan-vuitton", desk)
        self.assertIn("vuitton mulan", desk)
        self.assertIn("static let faceStars", desk)
        self.assertIn("static let faceGifts", desk)
        self.assertIn("static func giftKey(", desk)
        self.assertIn("static func facePinTokens(", desk)
        self.assertIn("static func faceStarTokens(", desk)
        self.assertIn("static func faceGiftTokens(", desk)
        self.assertNotIn("erika vuitton", desk.lower())
        self.assertIn("LOVESCAPE", desk)
        self.assertIn("giftAuth", desk)
        self.assertIn("giftSearch", desk)
        self.assertIn("giftUser", desk)
        self.assertIn("giftHeaders", desk)
        self.assertIn("playHeaders", desk)
        self.assertIn("giftClip", desk)
        self.assertIn("faceOk", desk)
        self.assertIn("faceKill", desk)
        self.assertIn("redgifs.com", desk.lower())
        self.assertIn("lovescape.cam", desk.lower())
        self.assertIn("static let loveChip", desk)
        self.assertIn("static let loveOrigin", desk)
        self.assertIn("static let faces", desk)
        self.assertIn("static func topics(", desk)
        self.assertIn("static func faceNeedles(", desk)
        self.assertIn("static func loveNeedles(", desk)
        self.assertIn("static func loveDirectory(", desk)
        self.assertIn("static func parseLove(", desk)
        self.assertIn("static func livePlay(", desk)
        self.assertIn("static func loveVariant(", desk)
        self.assertIn("static func filePlay(", desk)
        self.assertIn("static func userAgent(", desk)
        self.assertIn("static func referer(", desk)
        self.assertIn("static func faceRoom(", desk)
        self.assertIn("static func faceQueries(", desk)
        self.assertIn("static func faceSearch(", desk)
        self.assertIn("static func starSearch(", desk)
        self.assertIn("static func faceHunt(", desk)
        self.assertIn("static func faceId(", desk)
        self.assertIn("static let facePins", desk)
        self.assertIn("video/id/", desk)
        self.assertIn("L3HLNRZy6sk", desk)
        self.assertIn("static func faceHunt(", desk)
        self.assertIn("static func faceFile(", desk)
        self.assertIn("static func starFile(", desk)
        self.assertIn("static func parseFace(", desk)
        self.assertIn("bornstar.co", desk.lower())
        self.assertIn("its steph honey", desk.lower())
        self.assertIn("static func clock(", desk)
        self.assertIn("var seconds:", desk)
        self.assertIn("eporner.com", desk.lower())
        self.assertIn(".mp4", desk)
        self.assertIn("static func rail(", desk)
        self.assertIn("static let railExtra", desk)
        self.assertIn("static let huntAtOnce", desk)
        self.assertIn("n.isFinite", desk)
        self.assertIn("fetchFacePages", sock)
        self.assertIn("adultWanted", sock)
        self.assertIn("fetchGiftAuth", sock)
        self.assertIn("giftHeaders", sock)
        self.assertIn("Authorization", desk)
        self.assertIn("Bearer", desk)
        face_load = sock.split("private func fetchFacePages")[1].split("private func fetchAdultPages")[0]
        self.assertIn("faceHoldRooms", face_load)
        self.assertIn('faceHoldRooms("ALL")', face_load)
        self.assertIn("parseFace", face_load)
        self.assertIn("fetchAdultFaces", face_load)
        self.assertIn("adultRooms = AdultDesk.merge", face_load)
        self.assertIn("fetchGiftAuth", face_load)
        self.assertIn("huntAtOnce", sock)
        self.assertIn("adultReady = false", sock)
        load = sock.split("private func loadAdult(topic")[1].split("private func fetchLovePages")[0]
        self.assertIn('faceHoldRooms("ALL")', load)
        self.assertNotIn("adultRooms = []", load)
        self.assertIn("timeoutIntervalForResource = AdultDesk.faceNeedles(topic) != nil ? 180 : 40", sock)
        self.assertIn("inflight", sock)
        self.assertNotIn("CGImageSourceCreateImageAtIndex", sock)
        self.assertIn("&tag=", desk)
        self.assertIn("var seek:", desk)
        self.assertIn("room.seek", desk)
        self.assertIn("static func still(", desk)
        self.assertIn("static func pick(", desk)
        self.assertIn("static func kinds(", desk)
        self.assertIn("static func woman(", desk)
        self.assertIn("nonisolated static func stillJPEG", sock)
        self.assertIn("image_url_360p", desk)
        self.assertIn("image_url", desk)
        self.assertIn("var image:", desk)
        self.assertIn("var kinds:", desk)
        self.assertIn("gender", desk)
        self.assertIn("\"trans\"", desk)
        self.assertIn("\"shemale\"", desk)
        self.assertIn("\"ladyboy\"", desk)
        self.assertIn("\"tgirl\"", desk)
        self.assertIn("hls_source", desk)
        self.assertIn("current_show", desk)
        self.assertIn("num_users", desk)
        self.assertIn("hlsPlaylist", desk)
        self.assertNotIn("onlyfans", desk.lower())
        self.assertNotIn("fansly", desk.lower())
        self.assertNotIn("fanbase", desk.lower())
        self.assertNotIn("iframe_embed", desk)
        self.assertIn("func pullAdult(", sock)
        self.assertIn("pullAdult(topic:", sock)
        self.assertIn("AdultDesk.topics", sock)
        self.assertIn("AdultDesk.faceNeedles", sock)
        self.assertIn("AdultDesk.loveNeedles", sock)
        self.assertIn("AdultDesk.loveDirectory", sock)
        self.assertIn("AdultDesk.parseLove", sock)
        self.assertIn("AdultDesk.livePlay", sock)
        self.assertIn("AdultDesk.loveVariant", sock)
        self.assertIn("AdultDesk.filePlay", sock)
        self.assertIn("fetchLovePages", sock)
        self.assertIn("resolveAdult", sock)
        self.assertIn("AdultDesk.userAgent", sock)
        self.assertIn("AdultDesk.referer", sock)
        self.assertIn("AdultDesk.faceRoom", sock)
        self.assertIn("fetchAdultFaces", sock)
        self.assertIn("fetchAdultFaceFiles", sock)
        self.assertIn("AdultDesk.parseFace", sock)
        self.assertIn("AdultDesk.faceHunt", sock)
        self.assertIn("imageJPEG", sock)
        self.assertIn("0x50", sock)
        self.assertIn("func pullAdultStills(", sock)
        self.assertIn("nonisolated static func stillPreview", sock)
        self.assertIn("kCGImageSourceThumbnailMaxPixelSize", sock)
        self.assertIn("func liveAdult(", sock)
        self.assertIn("fetchAdult", sock)
        self.assertIn("adultRooms", sock)
        self.assertIn("AdultDesk.parse", sock)
        self.assertIn("AdultDesk.stream", sock)
        self.assertIn("AdultDesk.context", sock)
        self.assertIn("AdultDesk.edge", sock)
        self.assertIn("fetchAdultPost", sock)
        self.assertIn("AdultDesk.pages", sock)
        self.assertIn("offset:", sock)
        self.assertIn("User-Agent", sock)
        self.assertIn("X-Requested-With", sock)
        self.assertNotIn("lovescape", sock.lower())
        self.assertNotIn("WKWebView", desk)
        self.assertNotIn("WKWebView", sock)
        self.assertNotIn("URLSession", desk)
        self.assertNotIn("AVPlayer", sock)
        self.assertNotIn("AVPlayer", desk)
        self.assertIn("NaLive.rows", tv)
        self.assertIn("adultRooms", tv)
        self.assertIn("pullAdult", tv)
        self.assertIn("pullAdultStills", tv)
        self.assertIn('HUDField("SEARCH"', tv)
        self.assertIn("HUDWrapRail", tv)
        self.assertIn("AdultDesk.rail", tv)
        self.assertIn("naStillCache", tv)
        self.assertIn("naKind", tv)
        self.assertIn("naQuery", tv)
        self.assertIn("AdultDesk.pick", tv)
        self.assertIn("pullAdult(topic:", tv)
        self.assertIn("pullAdult(topic: naKind)", tv)
        self.assertIn("NO MATCH", tv)
        self.assertIn("onPlay", tv)
        self.assertIn("liveAdult", tv)
        self.assertIn("liveAdult", app)
        gate = na_gate_body(tv)
        self.assertIn("NaLiveWell", gate)
        self.assertIn("naLiveRows", gate)
        self.assertNotIn("pullAdultStills", gate)
        self.assertNotIn("NaLiveWell", open_body(tv))
        self.assertIn("LIVE", live)
        self.assertIn("AdultDesk.clock", live)
        self.assertIn("AdultDesk.Room", live)
        self.assertIn("AVURLAssetHTTPHeaderFieldsKey", live)
        self.assertIn("AdultDesk.playHeaders", live)
        self.assertIn("onPlay", live)
        self.assertIn("handle", live)
        self.assertIn("var image:", live)
        self.assertIn("var kinds:", live)
        self.assertIn("let still: UIImage?", live)
        self.assertIn("static let screen", live)
        self.assertIn("static func page(", live)
        self.assertIn("static let screen = 8", live)
        self.assertIn("preferredForwardBufferDuration", live)
        self.assertNotIn("zoocams.elpasozoo.org", live.lower())
        self.assertIn("ForEach(naPageRows)", tv)
        self.assertNotIn("ForEach(naLiveRows)", tv)
        self.assertIn("MORE", gate)
        self.assertIn("BACK", gate)
        self.assertIn("adultReady", tv)
        self.assertIn("if naUnlocked { naGate }", tv)
        self.assertLess(tv.find("if naUnlocked { naGate }"), tv.find("ForEach(openBlocks)"))
        self.assertIn("adultReady", sock)
        self.assertIn("fetchAdultPages", sock)
        self.assertIn("Task.detached", sock)
        watch = tv.split(".task")[1].split("private var you")[0]
        self.assertNotIn("pullAdult", watch)
        count = tv.split("onChange(of: runtime.updateSocket.adultRooms.count)")[1].split("onChange(of: naPageKey)")[0]
        self.assertNotIn("pullAdultStills", count)
        page = tv.split("onChange(of: naPageKey)")[1].split(".task")[0]
        self.assertIn("pullAdultStills", page)
        self.assertIn("Task {", page)
        rooms = [
            {"id": f"adult-{index}", "name": f"R{index}", "handle": f"r{index}", "url": "", "viewers": 100 - index}
            for index in range(30)
        ]
        self.assertEqual([row["id"] for row in adult_page(rooms)], [f"adult-{index}" for index in range(8)])
        self.assertEqual(len(adult_page(rooms, offset=8)), 8)
        self.assertEqual([row["id"] for row in adult_page(rooms, offset=24)], ["adult-24", "adult-25", "adult-26", "adult-27", "adult-28", "adult-29"])
        self.assertEqual(adult_page(rooms, offset=30), [])
        self.assertEqual(adult_page(rooms, offset=-4)[0]["id"], "adult-0")
        for word in ("truelook", "earthcam", "insecam", "stripchat"):
            self.assertNotIn(word, desk.lower())
            self.assertNotIn(word, live.lower())
            self.assertNotIn(word, sock.lower())
        for word in ("chaturbate",):
            self.assertNotIn(word, live.lower())
            self.assertNotIn(word, sock.lower())


class NaLiveTests(unittest.TestCase):
    def test_na_is_adult_only_after_hold(self):
        live = read("Blackout", "NaLive.swift")
        tv = read("Blackout", "TvPlate.swift")
        self.assertIn("enum NaLive", live)
        self.assertIn("AVPlayer", live)
        self.assertNotIn("WKWebView", live)
        self.assertNotIn("rtmp", live.lower())
        self.assertNotIn("zoocams.elpasozoo.org", live)
        self.assertIn("NaLive.rows", tv)
        self.assertIn("NaLiveWell", tv)
        self.assertIn("HOLD 10", tv)
        gate = na_gate_body(tv)
        self.assertIn("naLiveRows", gate)
        self.assertIn('HUDField("SEARCH"', gate)
        self.assertIn("HUDWrapRail", gate)
        self.assertIn("still:", gate)
        self.assertNotIn("pullAdultStills", gate)
        self.assertNotIn("DeskLive", gate)


class StillZoomTests(unittest.TestCase):
    def test_still_tap_opens_native_pinch_zoom(self):
        zoom = read("Blackout", "StillZoom.swift")
        tv = read("Blackout", "TvPlate.swift")
        card = read("Blackout", "CamHoldCard.swift")
        root = read("Blackout", "RootChrome.swift")
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn("struct StillZoom", zoom)
        self.assertIn("UIScrollView", zoom)
        self.assertIn("maximumZoomScale", zoom)
        self.assertIn("CLOSE", zoom)
        self.assertIn("contentsOfFile", zoom)
        self.assertNotIn("fullScreenCover", zoom)
        self.assertNotIn(".spring(", zoom)
        self.assertNotIn("WKWebView", zoom)
        self.assertIn("openStill", tv)
        self.assertIn("openStill", card)
        self.assertIn("zoomStillName", app)
        self.assertIn("func openStill(", app)
        self.assertIn("func closeStill(", app)
        self.assertIn("StillZoom", root)
        self.assertIn("closeStill", root)
        self.assertNotIn("fullScreenCover", root)


class LiveZoomTests(unittest.TestCase):
    def test_live_tap_opens_full_field_pinch(self):
        zoom = read("Blackout", "LiveZoom.swift")
        live = read("Blackout", "NaLive.swift")
        tv = read("Blackout", "TvPlate.swift")
        root = read("Blackout", "RootChrome.swift")
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn("struct LiveZoom", zoom)
        self.assertIn("AVPlayer", zoom)
        self.assertIn("AVURLAssetHTTPHeaderFieldsKey", zoom)
        self.assertIn("AdultDesk.playHeaders", zoom)
        self.assertIn("UIScrollView", zoom)
        self.assertIn("maximumZoomScale", zoom)
        self.assertIn("CLOSE", zoom)
        self.assertIn("TAP FULL", live)
        self.assertIn("onFull", live)
        self.assertIn("openLive", tv)
        self.assertIn("zoomLive", app)
        self.assertIn("func openLive(", app)
        self.assertIn("func closeLive(", app)
        self.assertIn("LiveZoom", root)
        self.assertIn("closeLive", root)
        self.assertNotIn("fullScreenCover", zoom)
        self.assertNotIn("WKWebView", zoom)
        self.assertNotIn(".spring(", zoom)
        self.assertNotIn("rtmp", zoom.lower())


class ClosedSourcesTests(unittest.TestCase):
    def test_tv_and_harvest_refuse_unsecured_alpr_and_streams(self):
        paths = (
            ("tools", "v3", "cams.py"),
            ("Blackout", "CamDesk.swift"),
            ("Blackout", "TvPlate.swift"),
            ("Blackout", "UpdateSocket.swift"),
            ("Resources", "Packs", "tx-west", "cameras.json"),
        )
        banned = (
            "insecam",
            "deflock",
            "flocksafety",
            "earthcam",
            "truelook",
            "chaturbate",
            "stripchat",
            "cam4",
            "onlyfans",
            "fansly",
            "fanbase",
            ".m3u8",
            "rtmp://",
        )
        for parts in paths:
            blob = read(*parts).lower()
            for word in banned:
                self.assertNotIn(word, blob, parts)


class DeviceScriptTests(unittest.TestCase):
    def test_solo_qa_and_audit_score_one_disc_and_tv(self):
        qa = read("docs", "SOLO_QA.md")
        agents = read("AGENTS.md")
        validate = read("tools", "validate_v3.py")
        hop = next(line for line in qa.splitlines() if "Hop cameras" in line)
        self.assertIn("red/blue", hop)
        self.assertNotIn("pink", hop.lower())
        self.assertNotIn("orange", hop.lower())
        tv = next(line for line in qa.splitlines() if "EXPEDITION `TV`" in line)
        self.assertIn("TV", tv)
        self.assertIn("SNAP", tv)
        self.assertIn("nearest", tv.lower())
        self.assertIn("never a live stream", tv.lower())
        self.assertIn("TRAFFIC", tv)
        self.assertIn("BRIDGE", tv)
        self.assertIn("AIRPORT", tv)
        self.assertIn("VENUE", tv)
        self.assertIn("`N/A`", tv)
        self.assertIn("HOLD 10", tv)
        self.assertIn("10s hold", tv)
        self.assertIn("adult", tv.lower())
        self.assertIn("TAP FULL", tv)
        self.assertIn("zoom", tv.lower())
        self.assertIn("section", tv.lower())
        self.assertIn("not a preview clip", tv.lower())
        self.assertIn("women", tv.lower())
        self.assertIn("couple", tv.lower())
        self.assertIn("orgies", tv.lower())
        self.assertIn("role play", tv.lower())
        self.assertIn("everything else", tv.lower())
        self.assertIn("no trans", tv.lower())
        self.assertIn("eight at a time", tv)
        self.assertIn("SEARCH", tv)
        self.assertIn("BRAIDS", tv)
        self.assertIn("ITSSTEPHHONEY21", tv)
        self.assertIn("ITSSTEPHHONEYXO21", tv)
        self.assertIn("MULAN VUITTON", tv)
        self.assertIn("MIKEILA J", tv)
        self.assertIn("NERDY BEILA", tv)
        self.assertIn("HOT4LEXI", tv)
        self.assertIn("ZURI BELLA ROSE", tv)
        self.assertIn("SARIIXO", tv)
        self.assertIn("BRITTANYA RAZAVI", tv)
        self.assertIn("JUICYJAS TV", tv)
        self.assertIn("HONEYTEASSEE", tv)
        self.assertIn("TANIA RAMOS", tv)
        self.assertIn("LILI VICTORIA", tv)
        self.assertIn("MONA ACUTEE", tv)
        self.assertIn("IMHIZBAEEXX", tv)
        self.assertIn("YESS ENIA69", tv)
        self.assertIn("KIRAWWRRRA", tv)
        self.assertIn("DOUBLE DOSE TWINS", tv)
        self.assertIn("GRACIE BONN", tv)
        self.assertIn("JASMINEGTV", tv)
        self.assertIn("STRAWBERRY SANDRA", tv)
        self.assertIn("LOVESCAPE", tv)
        self.assertIn("lovescape.cam", tv.lower())
        self.assertIn("cannot jet", tv)
        self.assertIn("cannot flash an empty plate", tv)
        self.assertIn("guest stills", tv)
        self.assertIn("VENUE` stays reserved", tv)
        self.assertIn("FAVORS", tv)
        self.assertIn("still", tv.lower())
        self.assertNotIn("insecam", tv.lower())
        self.assertNotIn("best in class", tv.lower())
        self.assertIn("test_expedition_tv.py", agents)
        self.assertIn("test_expedition_tv.py", validate)
        self.assertIn("expedition_tv()", validate)


def desk_text() -> str:
    return read("Blackout", "CamDesk.swift")


def na_gate_body(tv: str) -> str:
    start = tv.index("private var naGate")
    end = tv.index("private var naHoldRow", start)
    return tv[start:end]


def open_body(tv: str) -> str:
    return tv.split("private var naGate")[0]


if __name__ == "__main__":
    unittest.main()
