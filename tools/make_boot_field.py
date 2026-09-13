#!/usr/bin/env python3
"""Knock black out of the ACTIVATE field poster so the pack map shows through."""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "boot_field_src.jpg"
DEST = ROOT / "Blackout" / "Assets.xcassets" / "BootField.imageset" / "BootField.png"


def knock_black(rgb: np.ndarray) -> np.ndarray:
    r = rgb[:, :, 0].astype(np.int16)
    g = rgb[:, :, 1].astype(np.int16)
    b = rgb[:, :, 2].astype(np.int16)
    mx = np.maximum(np.maximum(r, g), b)
    is_red = (r >= g + 20) & (r >= b + 20)
    scaled = np.clip(((mx.astype(np.float32) / 255.0) ** 0.82) * 255.0, 0, 255).astype(np.int16)
    alpha = np.where(mx > 16, scaled, 0)
    alpha = np.where((mx >= 132) & ~is_red, 255, alpha)
    alpha = np.where(is_red & (r >= 72), np.clip(90 + r, 0, 255), alpha)
    alpha = np.where(is_red & (r >= 160), 255, alpha)
    alpha = np.where(mx <= 16, 0, alpha)
    return np.dstack((rgb, alpha.astype(np.uint8)))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", type=Path, default=SRC)
    parser.add_argument("--dest", type=Path, default=DEST)
    args = parser.parse_args()
    rgb = np.asarray(Image.open(args.src).convert("RGB"), dtype=np.uint8)
    rgba = knock_black(rgb)
    args.dest.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, mode="RGBA").save(args.dest, format="PNG", optimize=True)
    print(f"wrote {args.dest} {rgba.shape[1]}x{rgba.shape[0]}")


if __name__ == "__main__":
    main()
