#!/usr/bin/env python3
"""Rebuild Logo / dark / tinted alpha from the opaque storefront mark.

Metal RGB is copied 1:1. Only the black plate and the inner well go clear.
"""
from __future__ import annotations

import math
import sys
from collections import deque
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
from test_hud_quality import png_rgba
from v3.common import write_png

ROOT = TOOLS.parent
STORE = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
DARK = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-dark.png"
TINTED = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-tinted.png"
LOGO = ROOT / "Blackout" / "Assets.xcassets" / "Logo.imageset" / "Logo.png"

SOLID = 28
SIGHT_OPAQUE = 96
CLOSE_R = 3
R_HOLE = 240
R_BLOOM = 236
RING_IN = 244
RING_OUT = 338


def _dilate(src: bytearray, width: int, height: int, radius: int) -> bytearray:
    n = width * height
    dist = bytearray([255]) * n
    out = bytearray(n)
    q: deque[int] = deque()
    for i, bit in enumerate(src):
        if bit:
            dist[i] = 0
            out[i] = 1
            q.append(i)
    while q:
        i = q.popleft()
        d = dist[i]
        if d >= radius:
            continue
        x = i % width
        y = i // width
        for dx, dy in (
            (1, 0),
            (-1, 0),
            (0, 1),
            (0, -1),
            (1, 1),
            (1, -1),
            (-1, 1),
            (-1, -1),
        ):
            nx, ny = x + dx, y + dy
            if 0 <= nx < width and 0 <= ny < height:
                j = ny * width + nx
                nd = d + 1
                if nd < dist[j]:
                    dist[j] = nd
                    if nd <= radius:
                        out[j] = 1
                        q.append(j)
    return out


def _erode(src: bytearray, width: int, height: int, radius: int) -> bytearray:
    inv = bytearray(1 - bit for bit in src)
    return bytearray(1 - bit for bit in _dilate(inv, width, height, radius))


def _close(src: bytearray, width: int, height: int, radius: int) -> bytearray:
    return _erode(_dilate(src, width, height, radius), width, height, radius)


def _metal_keep(orig: bytes, width: int, height: int) -> bytearray:
    n = width * height
    cx = (width - 1) / 2
    cy = (height - 1) / 2
    seed = bytearray(n)
    for i in range(n):
        o = i * 4
        if max(orig[o], orig[o + 1], orig[o + 2]) >= SOLID:
            seed[i] = 1
    closed = _close(seed, width, height, CLOSE_R)
    keep = bytearray(closed)
    vis = bytearray(n)
    q: deque[int] = deque()

    def push(i: int) -> None:
        if not vis[i] and not closed[i]:
            vis[i] = 1
            q.append(i)

    for x in range(width):
        push(x)
        push((height - 1) * width + x)
    for y in range(height):
        push(y * width)
        push(y * width + width - 1)
    for i in range(n):
        x = i % width
        y = i // width
        if math.hypot(x - cx, y - cy) < R_HOLE:
            push(i)
    while q:
        i = q.popleft()
        x = i % width
        y = i // width
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < width and 0 <= ny < height:
                j = ny * width + nx
                if not vis[j] and not closed[j]:
                    vis[j] = 1
                    q.append(j)
    for i in range(n):
        if not vis[i] and not closed[i]:
            keep[i] = 1
    for i in range(n):
        x = i % width
        y = i // width
        rad = math.hypot(x - cx, y - cy)
        if RING_IN <= rad <= RING_OUT:
            keep[i] = 1
    return keep


def _bt709(r: int, g: int, b: int) -> int:
    return max(0, min(255, int(round(0.2126 * r + 0.7152 * g + 0.0722 * b))))


def knock_plate(orig: bytes, width: int, height: int, *, tinted: bool) -> bytes:
    keep = _metal_keep(orig, width, height)
    cx = (width - 1) / 2
    cy = (height - 1) / 2
    out = bytearray(len(orig))
    n = width * height
    for i in range(n):
        o = i * 4
        r, g, b = orig[o], orig[o + 1], orig[o + 2]
        m = max(r, g, b)
        x = i % width
        y = i // width
        rad = math.hypot(x - cx, y - cy)
        solid_metal = keep[i] and not (rad < R_BLOOM and m < SIGHT_OPAQUE)
        solid_sight = rad < R_HOLE and m >= SIGHT_OPAQUE
        if solid_metal or solid_sight:
            a = 255
            nr, ng, nb = r, g, b
        else:
            nr, ng, nb, a = 0, 0, 0, 0
        if tinted:
            if a == 0:
                nr, ng, nb = 0, 0, 0
            else:
                yv = _bt709(r, g, b)
                nr, ng, nb = yv, yv, yv
        out[o : o + 4] = bytes((nr, ng, nb, a))
    return bytes(out)


def main() -> None:
    width, height, orig = png_rgba(STORE)
    color = knock_plate(orig, width, height, tinted=False)
    tint = knock_plate(orig, width, height, tinted=True)
    write_png(DARK, width, height, color)
    write_png(LOGO, width, height, color)
    write_png(TINTED, width, height, tint)


if __name__ == "__main__":
    main()
