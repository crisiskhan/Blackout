#!/usr/bin/env python3
"""What the copy phase does to Resources/ after rsync, on the phone tree."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "third_party"))
sys.path.insert(0, str(ROOT / "tools"))

from v3 import aerial  # noqa: E402


def strip_style_aerial(style_path: Path) -> None:
    """NM photo stays in git. The phone copy must not name a missing archive."""
    if not style_path.is_file():
        return
    style = json.loads(style_path.read_text())
    sources = style.get("sources") or {}
    for key in list(sources):
        if key.startswith("aerial"):
            del sources[key]
    style["sources"] = sources
    style["layers"] = [
        item
        for item in (style.get("layers") or [])
        if not str(item.get("id") or "").startswith("aerial")
    ]
    style_path.write_text(json.dumps(style, ensure_ascii=False, indent=2) + "\n")


def collapse_style_aerial(style_path: Path) -> None:
    if not style_path.is_file():
        return
    style = json.loads(style_path.read_text())
    sources = style.get("sources") or {}
    for key in list(sources):
        if key.startswith("aerial"):
            del sources[key]
    sources["aerial"] = aerial.style_source(aerial.AERIAL_FILE)
    style["sources"] = sources
    layers = [
        item
        for item in (style.get("layers") or [])
        if not str(item.get("id") or "").startswith("aerial")
    ]
    aerial.insert_aerial_layer(layers, [aerial.AERIAL_FILE])
    style["layers"] = layers
    style_path.write_text(json.dumps(style, ensure_ascii=False, indent=2) + "\n")


def pack_phone(dst: Path) -> None:
    dst = dst.resolve()
    git_resources = (ROOT / "Resources").resolve()
    if dst == git_resources:
        raise SystemExit("pack_phone.py writes the bundle copy, not Resources/")
    packs = dst / "Packs"
    if not packs.is_dir():
        return
    for dest in sorted(p for p in packs.iterdir() if p.is_dir()):
        merged = aerial.merge_phone_archives(dest)
        style = dest / "style.json"
        if merged is None and not (dest / aerial.AERIAL_FILE).is_file():
            strip_style_aerial(style)
            continue
        collapse_style_aerial(style)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: pack_phone.py DST")
    pack_phone(Path(sys.argv[1]))


if __name__ == "__main__":
    main()
