"""Shared helpers for BLACKOUT BUILD BIBLE v3 generation."""
from __future__ import annotations

import hashlib
import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def oid(name: str) -> str:
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def png_chunk(tag: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)


def write_png(path: Path, width: int, height: int, pixels: bytes) -> None:
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(pixels[y * stride : (y + 1) * stride])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + png_chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def diagram_png(path: Path, kind: str, caption: str) -> None:
    """Small instructional diagram used by Field stepper pictures."""
    w = h = 256
    pix = bytearray(w * h * 4)
    bg = {
        "medical": (18, 22, 28),
        "trauma": (28, 16, 16),
        "water": (12, 22, 32),
        "fire": (32, 18, 12),
        "shelter": (20, 22, 16),
        "nav": (16, 20, 24),
        "plants": (16, 26, 16),
        "animals": (24, 20, 14),
        "fungi": (22, 18, 24),
        "food": (22, 22, 14),
        "signaling": (26, 22, 12),
        "tactics": (18, 18, 22),
        "environment": (14, 20, 22),
    }.get(kind, (14, 16, 18))
    for i in range(0, len(pix), 4):
        pix[i : i + 4] = bytes((bg[0], bg[1], bg[2], 255))
    # silver frame
    for y in range(h):
        for x in range(w):
            if x < 6 or y < 6 or x >= w - 6 or y >= h - 6:
                i = (y * w + x) * 4
                pix[i : i + 4] = bytes((180, 188, 196, 255))
    # center glyph
    cx = cy = 128
    for y in range(h):
        for x in range(w):
            dx, dy = x - cx, y - cy
            r = math.hypot(dx, dy)
            i = (y * w + x) * 4
            if kind in {"medical", "trauma"} and r < 36:
                pix[i : i + 4] = bytes((200, 40, 40, 255))
            if kind == "water" and 40 < r < 70 and abs(dy) < 18:
                pix[i : i + 4] = bytes((80, 160, 200, 255))
            if kind == "fire" and dy < 20 and abs(dx) < 18 - dy // 4:
                pix[i : i + 4] = bytes((220, 120, 40, 255))
            if kind == "nav" and abs(dx) < 4 and -50 < dy < 50:
                pix[i : i + 4] = bytes((200, 205, 210, 255))
            if kind == "fungi" and r < 28:
                pix[i : i + 4] = bytes((90, 70, 110, 255))
    write_png(path, w, h, bytes(pix))


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))
