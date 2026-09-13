#!/usr/bin/env python3
"""Rebuild Logo / dark / tinted from the storefront mark.

Original metal and inner well stay. Outer black plate and outer rays go.
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
METAL = 40
STEPS = 720
ENV_WIN = 40
ENV_PAD = 1
ARROW_MIN = 600
SHELL = 400


def _bt709(r: int, g: int, b: int) -> int:
    return max(0, min(255, int(round(0.2126 * r + 0.7152 * g + 0.0722 * b))))


def _seed(orig: bytes, width: int, height: int) -> bytearray:
    n = width * height
    seed = bytearray(n)
    for i in range(n):
        o = i * 4
        if max(orig[o], orig[o + 1], orig[o + 2]) >= SOLID:
            seed[i] = 1
    return seed


def _ring_envelope(seed: bytearray, width: int, height: int) -> list[int]:
    cx = (width - 1) / 2
    cy = (height - 1) / 2
    radii: list[int] = []
    for step in range(STEPS):
        ang = math.radians(step * 360 / STEPS)
        last = 0
        for rad in range(0, max(width, height)):
            x = int(round(cx + rad * math.cos(ang)))
            y = int(round(cy + rad * math.sin(ang)))
            if not (0 <= x < width and 0 <= y < height):
                break
            if seed[y * width + x]:
                last = rad
        radii.append(last)
    smooth: list[int] = []
    for step in range(STEPS):
        vals = [radii[(step + k) % STEPS] for k in range(-ENV_WIN, ENV_WIN + 1)]
        vals.sort()
        smooth.append(vals[len(vals) // 2])
    return smooth


def _env_at(x: int, y: int, width: int, height: int, envelope: list[int]) -> int:
    cx = (width - 1) / 2
    cy = (height - 1) / 2
    ang = math.atan2(y - cy, x - cx)
    if ang < 0:
        ang += 2 * math.pi
    step = int(ang * STEPS / (2 * math.pi)) % STEPS
    return envelope[step]


def _metal_keep(orig: bytes, width: int, height: int) -> bytearray:
    n = width * height
    seed = _seed(orig, width, height)
    envelope = _ring_envelope(seed, width, height)
    cx = (width - 1) / 2
    cy = (height - 1) / 2
    keep = bytearray(n)
    shell = SHELL * width / 1024
    for i in range(n):
        x = i % width
        y = i // width
        rad = math.hypot(x - cx, y - cy)
        o = i * 4
        if rad <= _env_at(x, y, width, height, envelope) + ENV_PAD:
            keep[i] = 1
        elif rad < shell and max(orig[o], orig[o + 1], orig[o + 2]) >= METAL:
            keep[i] = 1
    seen = bytearray(n)
    for i in range(n):
        if seen[i] or not seed[i] or keep[i]:
            continue
        q: deque[int] = deque([i])
        seen[i] = 1
        blob = [i]
        while q:
            j = q.popleft()
            x = j % width
            y = j // width
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height:
                    k = ny * width + nx
                    if seen[k] or not seed[k] or keep[k]:
                        continue
                    seen[k] = 1
                    q.append(k)
                    blob.append(k)
        if len(blob) >= ARROW_MIN:
            for k in blob:
                keep[k] = 1
    return keep


def knock_plate(orig: bytes, width: int, height: int, *, tinted: bool) -> bytes:
    keep = _metal_keep(orig, width, height)
    out = bytearray(len(orig))
    n = width * height
    for i in range(n):
        o = i * 4
        r, g, b = orig[o], orig[o + 1], orig[o + 2]
        if keep[i]:
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
