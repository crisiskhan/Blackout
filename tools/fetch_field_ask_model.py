#!/usr/bin/env python3
"""Refuse an ASK model.

A 3B GGUF would drain the phone in an emergency. FIELD ASK is the packed
book walk. The HUD never downloads weights. Archive must not call this
to place a file under Resources/Field.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "Resources" / "Field" / "Dolphin3.0-Llama3.2-3B-Q4_K_M.gguf"


def main() -> int:
    if DEST.is_file():
        DEST.unlink()
        print(f"removed leftover ASK weights {DEST}")
    print("ASK model does not ship")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
