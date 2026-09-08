#!/usr/bin/env python3
"""Lock the next walkable region pack: NM, not TX EAST, default stays tx-west."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from v3.fetch_packs import PACKS, PRIMARY_PACK_ID, walkable_ids
from v3.slim_packs import should_slim


def fail(msg: str) -> None:
    print("FAIL", msg)
    raise SystemExit(1)


def main() -> None:
    if PRIMARY_PACK_ID != "tx-west":
        fail(f"default open pack drifted to {PRIMARY_PACK_ID}")
    if not PACKS["nm"].get("walkable"):
        fail("nm must use the walkable regenerate path")
    if PACKS["tx-east"].get("walkable"):
        fail("tx-east must stay a sticker until Crisis switches default")
    if PACKS["tx-west"].get("walkable") is not True:
        fail("tx-west must remain walkable")
    ids = walkable_ids()
    if ids != {"tx-west", "nm"}:
        fail(f"walkable ids {ids} — expected tx-west + nm only")
    if should_slim(ROOT / "Resources" / "Packs" / "nm"):
        fail("slim_packs must not cut NM back to a sticker")
    if should_slim(ROOT / "Resources" / "Packs" / "tx-west"):
        fail("slim_packs must not cut tx-west")
    if not should_slim(ROOT / "Resources" / "Packs" / "tx-east"):
        fail("tx-east sticker should still slim")
    print("OK   next walkable pack is NM; default stays tx-west")


if __name__ == "__main__":
    main()
