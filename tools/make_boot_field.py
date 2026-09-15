#!/usr/bin/env python3
"""ACTIVATE overlay is the full poster. Black stays. No crop well."""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "Blackout" / "Assets.xcassets" / "BootField.imageset" / "BootField.png"


def compose_poster(src: Image.Image) -> Image.Image:
    """Keep the poster pixels, including black outside the compass."""
    return src.convert("RGB").convert("RGBA")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", type=Path, default=DEST)
    parser.add_argument("--dest", type=Path, default=DEST)
    args = parser.parse_args()
    poster = compose_poster(Image.open(args.src))
    args.dest.parent.mkdir(parents=True, exist_ok=True)
    poster.save(args.dest, format="PNG", optimize=True)
    print(f"wrote {args.dest} {poster.size[0]}x{poster.size[1]}")


if __name__ == "__main__":
    main()
