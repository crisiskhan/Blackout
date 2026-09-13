#!/usr/bin/env python3
"""ACTIVATE field is the square mark, centered. No BLACKOUT wordmark."""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LOGO = ROOT / "Blackout" / "Assets.xcassets" / "Logo.imageset" / "Logo.png"
DEST = ROOT / "Blackout" / "Assets.xcassets" / "BootField.imageset" / "BootField.png"
FIELD_W = 1152
FIELD_H = 1712


def compose_from_logo(logo: Image.Image) -> Image.Image:
    mark = logo.convert("RGBA")
    if mark.size != (FIELD_W, FIELD_W):
        mark = mark.resize((FIELD_W, FIELD_W), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (FIELD_W, FIELD_H), (0, 0, 0, 0))
    canvas.paste(mark, (0, (FIELD_H - FIELD_W) // 2), mark)
    return canvas


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", type=Path, default=LOGO)
    parser.add_argument("--dest", type=Path, default=DEST)
    args = parser.parse_args()
    logo = Image.open(args.src)
    field = compose_from_logo(logo)
    args.dest.parent.mkdir(parents=True, exist_ok=True)
    field.save(args.dest, format="PNG", optimize=True)
    print(f"wrote {args.dest} {field.size[0]}x{field.size[1]}")


if __name__ == "__main__":
    main()
