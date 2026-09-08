#!/usr/bin/env python3
"""Lock walkable catalog packs: NM + TX EAST. Default stays tx-west. No FL/NY packs."""
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
    if not PACKS["tx-east"].get("walkable"):
        fail("tx-east must use the walkable regenerate path")
    if PACKS["tx-west"].get("walkable") is not True:
        fail("tx-west must remain walkable")
    if any(pid.startswith(("fl-", "ny-")) for pid in PACKS):
        fail(f"FL/NY packs still defined: {sorted(PACKS)}")
    ids = walkable_ids()
    if ids != {"tx-west", "nm", "tx-east"}:
        fail(f"walkable ids {ids} — expected tx-west + nm + tx-east")
    if should_slim(ROOT / "Resources" / "Packs" / "nm"):
        fail("slim_packs must not cut NM back to a sticker")
    if should_slim(ROOT / "Resources" / "Packs" / "tx-west"):
        fail("slim_packs must not cut tx-west")
    if should_slim(ROOT / "Resources" / "Packs" / "tx-east"):
        fail("slim_packs must not cut TX EAST back to a sticker")
    union = PACKS["tx-east"]["slices"]["union"]
    if union["south"] != 30.08 or union["west"] != -97.78 or union["north"] != 30.32 or union["east"] != -97.2:
        fail(f"tx-east union bbox drifted: {union}")
    print("OK   walkable packs are NM + TX EAST; default stays tx-west; FL/NY dropped")


if __name__ == "__main__":
    main()
