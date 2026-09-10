#!/usr/bin/env python3
"""Lock walkable catalog packs: NM + TX EAST. Default stays tx-west. No FL/NY packs."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from v3.fetch_packs import PACKS, PRIMARY_PACK_ID, union_bbox, walkable_ids
from v3.slim_packs import should_slim

# Ground already on somebody's phone. Packs may grow past these boxes; they may
# never quietly retreat inside one.
COVERAGE_FLOOR = {
    "tx-west": {"south": 31.65, "west": -106.85, "north": 32.40, "east": -106.20},
    "tx-east": {"south": 30.08, "west": -97.90, "north": 30.42, "east": -97.20},
    "nm": {"south": 34.95, "west": -106.85, "north": 35.35, "east": -106.35},
}


def fail(msg: str) -> None:
    print("FAIL", msg)
    raise SystemExit(1)


def covers(outer: dict, inner: dict) -> bool:
    return (
        outer["south"] <= inner["south"]
        and outer["west"] <= inner["west"]
        and outer["north"] >= inner["north"]
        and outer["east"] >= inner["east"]
    )


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
    for pid, floor in COVERAGE_FLOOR.items():
        bb = union_bbox(PACKS[pid]["slices"])
        if not covers(bb, floor):
            fail(f"{pid} lost ground a phone already had: {bb} no longer covers {floor}")
        for key, sl in PACKS[pid]["slices"].items():
            if not covers(bb, sl):
                fail(f"{pid} slice {key} pokes outside the pack bbox: {sl}")
    print("OK   walkable packs are NM + TX EAST; default stays tx-west; FL/NY dropped")
    print("OK   every pack still covers the ground it shipped with")


if __name__ == "__main__":
    main()
