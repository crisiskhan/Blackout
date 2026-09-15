#!/usr/bin/env python3
"""Rebuild Logo / dark / tinted from the square compass. Black and rays stay."""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
DARK = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-dark.png"
TINTED = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-tinted.png"
LOGO = ROOT / "Blackout" / "Assets.xcassets" / "Logo.imageset" / "Logo.png"
ICON = 1024


def _opaque_rgba(im: Image.Image) -> Image.Image:
    rgb = im.convert("RGB")
    return rgb.convert("RGBA")


def _tinted_rgba(im: Image.Image) -> Image.Image:
    gray = im.convert("L")
    rgb = Image.merge("RGB", (gray, gray, gray))
    return rgb.convert("RGBA")


def _icon_rgb(im: Image.Image) -> Image.Image:
    rgb = im.convert("RGB")
    if rgb.size != (ICON, ICON):
        rgb = rgb.resize((ICON, ICON), Image.Resampling.LANCZOS)
    return rgb


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", type=Path, default=None)
    args = parser.parse_args()
    src = Image.open(args.src) if args.src is not None else Image.open(STORE)
    icon = _icon_rgb(src)
    logo = _opaque_rgba(src)
    dark = _opaque_rgba(icon)
    tint = _tinted_rgba(icon)
    STORE.parent.mkdir(parents=True, exist_ok=True)
    LOGO.parent.mkdir(parents=True, exist_ok=True)
    icon.save(STORE, format="PNG", optimize=True)
    logo.save(LOGO, format="PNG", optimize=True)
    dark.save(DARK, format="PNG", optimize=True)
    tint.save(TINTED, format="PNG", optimize=True)
    print(f"wrote {STORE} {icon.size[0]}x{icon.size[1]} RGB")
    print(f"wrote {LOGO} {logo.size[0]}x{logo.size[1]} RGBA")
    print(f"wrote {DARK} {dark.size[0]}x{dark.size[1]} RGBA")
    print(f"wrote {TINTED} {tint.size[0]}x{tint.size[1]} RGBA")


if __name__ == "__main__":
    main()
