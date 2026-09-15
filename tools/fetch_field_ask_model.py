#!/usr/bin/env python3
"""Fetch Dolphin 3.0 Llama 3.2 3B Q4_K_M into Resources/Field.

Python/shell only. The HUD never downloads weights. Git does not store the
GGUF. TestFlight archive may run this; the unsigned compile must not.
"""
from __future__ import annotations

import hashlib
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "Resources" / "Field" / "Dolphin3.0-Llama3.2-3B-Q4_K_M.gguf"
URL = (
    "https://huggingface.co/bartowski/Dolphin3.0-Llama3.2-3B-GGUF/resolve/main/"
    "Dolphin3.0-Llama3.2-3B-Q4_K_M.gguf"
)
SHA = "5d6d02eeefa1ab5dbf23f97afdf5c2c95ad3d946dc3b6e9ab72e6c1637d54177"


def _digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    DEST.parent.mkdir(parents=True, exist_ok=True)
    if DEST.is_file():
        digest = _digest(DEST)
        if digest == SHA:
            print(f"ASK model present {DEST}")
            return 0
        print("ASK model hash mismatch, re-fetch")
        DEST.unlink()
    req = urllib.request.Request(URL, headers={"User-Agent": "Blackout-field-ask"})
    print(f"fetch {URL}")
    tmp = DEST.with_suffix(".part")
    try:
        with urllib.request.urlopen(req, timeout=600) as resp, tmp.open("wb") as out:
            while True:
                chunk = resp.read(1024 * 1024)
                if not chunk:
                    break
                out.write(chunk)
        digest = _digest(tmp)
        if digest != SHA:
            tmp.unlink(missing_ok=True)
            print(f"ASK model hash {digest} != {SHA}", file=sys.stderr)
            return 1
        tmp.replace(DEST)
    except Exception as exc:
        tmp.unlink(missing_ok=True)
        print(f"ASK model fetch failed: {exc}", file=sys.stderr)
        return 1
    print(f"ASK model wrote {DEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
