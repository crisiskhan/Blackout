#!/usr/bin/env python3
"""Inspect a TestFlight IPA and rewrite vendor FMWK bundle ids.

33925258357: altool −19000 on com.maplibre.mapbox inside MapLibre.framework.
33929367958: renaming that to com.crisiskhan.blackout.maplibre still −19000 —
altool wants an ASC application record for every unique CFBundleIdentifier.
Nested FMWK must use the parent app id com.crisiskhan.blackout.
Fail closed if Payload/*.app or PlugIns/*.appex is outside
{com.crisiskhan.blackout, com.crisiskhan.blackout.widgets}.
No ASC app for MapLibre. No network.
"""
from __future__ import annotations

import argparse
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any

APP_BID = "com.crisiskhan.blackout"
WIDGET_BID = "com.crisiskhan.blackout.widgets"
ALLOWED_EXECUTABLE_BIDS = frozenset({APP_BID, WIDGET_BID})
MAPBOX = "com.maplibre.mapbox"
CHILD_MAPLIBRE = "com.crisiskhan.blackout.maplibre"


class InspectError(RuntimeError):
    """IPA payload failed a fail-closed bundle-id check."""


def owned_framework_identifier(framework_dirname: str) -> str:
    """Nested FMWK must share the parent app id. altool looks up every BID."""
    del framework_dirname
    return APP_BID


def _load_plist(path: Path) -> dict[str, Any]:
    return plistlib.loads(path.read_bytes())


def _dump_plist(path: Path, body: dict[str, Any]) -> None:
    path.write_bytes(plistlib.dumps(body))


def _set_plist_string(path: Path, key: str, value: str) -> None:
    """Prefer plutil / PlistBuddy on macOS; plistlib everywhere else."""
    plutil = Path("/usr/bin/plutil")
    buddy = Path("/usr/libexec/PlistBuddy")
    if plutil.is_file():
        subprocess.run(
            [str(plutil), "-replace", key, "-string", value, str(path)],
            check=True,
        )
        return
    if buddy.is_file():
        result = subprocess.run(
            [str(buddy), "-c", f"Set :{key} {value}", str(path)],
            check=False,
        )
        if result.returncode == 0:
            return
        subprocess.run(
            [str(buddy), "-c", f"Add :{key} string {value}", str(path)],
            check=True,
        )
        return
    body = _load_plist(path)
    body[key] = value
    _dump_plist(path, body)


def _bid(path: Path) -> str:
    try:
        value = _load_plist(path).get("CFBundleIdentifier")
    except Exception as exc:
        raise InspectError(f"unreadable Info.plist {path}: {exc}") from exc
    return str(value or "")


def rewrite_framework_plist(path: Path) -> bool:
    """Rewrite a FMWK Info.plist off a foreign BID. Keep CFBundlePackageType."""
    body = _load_plist(path)
    pkg = str(body.get("CFBundlePackageType") or "")
    if pkg and pkg != "FMWK":
        return False
    bid = str(body.get("CFBundleIdentifier") or "")
    if bid == APP_BID:
        return False
    new_bid = owned_framework_identifier(path.parent.name)
    _set_plist_string(path, "CFBundleIdentifier", new_bid)
    after = _load_plist(path)
    after_pkg = str(after.get("CFBundlePackageType") or "")
    if after_pkg != "FMWK":
        _set_plist_string(path, "CFBundlePackageType", "FMWK")
    return True


def inspect_and_rewrite_payload(payload_dir: Path) -> bool:
    """Assert app/widget BIDs and rewrite foreign FMWK ids. True if rewritten."""
    if not payload_dir.is_dir():
        raise InspectError(f"missing payload directory {payload_dir}")
    apps = sorted(p for p in payload_dir.glob("*.app") if p.is_dir())
    if not apps:
        raise InspectError("no Payload/*.app")
    rewritten = False
    for app in apps:
        info = app / "Info.plist"
        if not info.is_file():
            raise InspectError(f"{app.name} missing Info.plist")
        bid = _bid(info)
        if bid != APP_BID:
            raise InspectError(
                f"{app.as_posix()} CFBundleIdentifier={bid or 'MISSING'} "
                f"outside {{{APP_BID}, {WIDGET_BID}}}"
            )
        plugins = app / "PlugIns"
        if plugins.is_dir():
            for appex in sorted(p for p in plugins.glob("*.appex") if p.is_dir()):
                appex_info = appex / "Info.plist"
                if not appex_info.is_file():
                    raise InspectError(f"{appex.name} missing Info.plist")
                wbid = _bid(appex_info)
                if wbid != WIDGET_BID:
                    raise InspectError(
                        f"{appex.as_posix()} CFBundleIdentifier={wbid or 'MISSING'} "
                        f"outside {{{APP_BID}, {WIDGET_BID}}}"
                    )
        for plist in app.rglob("Info.plist"):
            try:
                body = _load_plist(plist)
            except Exception:
                continue
            if str(body.get("CFBundlePackageType") or "") != "FMWK":
                continue
            if rewrite_framework_plist(plist):
                rewritten = True
                print(
                    f"rewrote {plist.as_posix()} "
                    f"CFBundleIdentifier -> {owned_framework_identifier(plist.parent.name)}"
                )
    leftover_foreign = [
        p
        for app in apps
        for p in app.rglob("Info.plist")
        if MAPBOX.encode() in p.read_bytes() or CHILD_MAPLIBRE.encode() in p.read_bytes()
    ]
    if leftover_foreign:
        raise InspectError(
            "IPA still contains a MapLibre-only bundle id after rewrite: "
            + ", ".join(p.as_posix() for p in leftover_foreign)
        )
    return rewritten


def inspect_ipa(ipa_path: Path) -> bool:
    """Unzip IPA, inspect/rewrite payload, re-zip if rewritten."""
    ipa_path = ipa_path.resolve()
    if not ipa_path.is_file():
        raise InspectError(f"missing IPA {ipa_path}")
    with tempfile.TemporaryDirectory(prefix="tf-ipa-inspect-") as tmp:
        work = Path(tmp)
        with zipfile.ZipFile(ipa_path) as zf:
            zf.extractall(work)
        payload = work / "Payload"
        rewritten = inspect_and_rewrite_payload(payload)
        if not rewritten:
            print(f"IPA inspect OK (no FMWK rewrite) {ipa_path}")
            return False
        tmp_ipa = work / "rewritten.ipa"
        with zipfile.ZipFile(tmp_ipa, "w") as zf:
            for path in work.rglob("*"):
                if path == tmp_ipa or not path.is_file():
                    continue
                zf.write(path, path.relative_to(work).as_posix())
        shutil.copy2(tmp_ipa, ipa_path)
        print(f"IPA rewritten {ipa_path}")
        return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, help="Blackout.ipa to inspect")
    parser.add_argument("--payload", type=Path, help="already-unzipped Payload/")
    args = parser.parse_args(argv)
    try:
        if args.ipa is not None:
            inspect_ipa(args.ipa)
        elif args.payload is not None:
            inspect_and_rewrite_payload(args.payload)
        else:
            raise InspectError("pass --ipa or --payload")
    except InspectError as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1
    print("IPA inspect OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
