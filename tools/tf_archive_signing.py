#!/usr/bin/env python3
"""CI-only pbx Dist signing for Blackout + BlackoutWidgets.

33927056130: do not put CODE_SIGN_IDENTITY on the global xcodebuild
archive / exportArchive CLI. That override hits Automatic SPM packages
(VisionCoreML, MapLibreMap, …) and exits 65. Manual Dist belongs on the
app and widget buildSettings only. SPM packages stay Automatic.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

import tf_asc_reuse as reuse


APP_BUNDLE = "com.crisiskhan.blackout"
WIDGET_BUNDLE = "com.crisiskhan.blackout.widgets"
MANUAL_BUNDLES = tuple(ident for ident, _name, _plat in reuse.BUNDLES)

# One placeholder for the Manual patch and the keychain-hash rewrite.
# "iPhone Distribution" matches Apple's common Dist identity name.
DIST_IDENTITY_PLACEHOLDER = "iPhone Distribution"
DIST_IDENTITY_ALIASES = frozenset(
    {"iPhone Distribution", "iOS Distribution", "Apple Distribution"}
)

_LOCAL_DEFAULTS = {ident: name for ident, name, _plat in reuse.BUNDLES}


def default_profile_map() -> dict[str, str]:
    return dict(_LOCAL_DEFAULTS)


def xcodebuild_archive_cli_block(script_text: str) -> str:
    start = script_text.find('echo "xcodebuild archive..."')
    end = script_text.find("archive 2>&1", start)
    if start < 0 or end < 0:
        raise ValueError("tf-archive.sh must invoke xcodebuild archive")
    return script_text[start:end]


def xcodebuild_export_cli_block(script_text: str) -> str:
    start = script_text.find("xcodebuild \\\n    -exportArchive")
    if start < 0:
        start = script_text.find("-exportArchive")
    if start < 0:
        raise ValueError("tf-archive.sh must invoke xcodebuild exportArchive")
    end = script_text.find("2>&1", start)
    if end < 0:
        raise ValueError("tf-archive.sh exportArchive invocation is truncated")
    return script_text[start:end]


def _sub_setting(block: str, key: str, val: str) -> str:
    if re.search(rf"{key} = ", block):
        return re.sub(rf"{key} = [^;]*;", f"{key} = {val};", block, count=1)
    return block.replace(
        "buildSettings = {",
        "buildSettings = {\n\t\t\t\t" + f"{key} = {val};",
    )


def _patch_manual_block(block: str, profile_name: str, team_id: str) -> str:
    block = _sub_setting(block, "CODE_SIGN_STYLE", "Manual")
    block = _sub_setting(
        block, "CODE_SIGN_IDENTITY", f'"{DIST_IDENTITY_PLACEHOLDER}"'
    )
    block = _sub_setting(block, "DEVELOPMENT_TEAM", team_id)
    block = _sub_setting(block, "PROVISIONING_PROFILE_SPECIFIER", f'"{profile_name}"')
    return block


def _pin_automatic_block(block: str, team_id: str) -> str:
    block = _sub_setting(block, "CODE_SIGN_STYLE", "Automatic")
    block = _sub_setting(
        block, "CODE_SIGN_IDENTITY", f'"{DIST_IDENTITY_PLACEHOLDER}"'
    )
    block = _sub_setting(block, "DEVELOPMENT_TEAM", team_id)
    return block


def apply_ci_signing_patch(
    text: str,
    *,
    has_local_dist_key: bool,
    team_id: str,
    profiles: dict[str, str] | None = None,
) -> str:
    """Patch only MANUAL_BUNDLES (app + widget). Watch and SPM stay put."""
    spec = default_profile_map()
    if profiles:
        spec.update(profiles)
    out = text
    for bundle in MANUAL_BUNDLES:
        pattern = re.compile(
            r"(buildSettings = \{[^{}]*PRODUCT_BUNDLE_IDENTIFIER = "
            + re.escape(bundle)
            + r";[^{}]*\})",
            re.S,
        )
        if has_local_dist_key:
            name = spec.get(bundle, _LOCAL_DEFAULTS[bundle])

            def _manual(match: re.Match[str], profile: str = name) -> str:
                return _patch_manual_block(match.group(1), profile, team_id)

            out, n = pattern.subn(_manual, out)
            print(f"patched {bundle} blocks={n}")
        else:

            def _auto(match: re.Match[str]) -> str:
                return _pin_automatic_block(match.group(1), team_id)

            out, n = pattern.subn(_auto, out)
            print(f"pinned Distribution Automatic {bundle} blocks={n}")
    return out


def rewrite_dist_identity_hash(text: str, identity_hash: str) -> str:
    """Replace the placeholder (and aliases) so the rewrite cannot miss."""
    out = text
    for alias in DIST_IDENTITY_ALIASES:
        out = out.replace(
            f'CODE_SIGN_IDENTITY = "{alias}";',
            f'CODE_SIGN_IDENTITY = "{identity_hash}";',
        )
    return out


def _pbx_path() -> Path:
    return Path("Blackout.xcodeproj/project.pbxproj")


def _load_profiles() -> dict[str, str]:
    raw = Path(os.environ["RUNNER_TEMP"]) / "profile_map.json"
    if not raw.is_file():
        return {}
    data = json.loads(raw.read_text())
    if not isinstance(data, dict):
        return {}
    return {str(k): str(v) for k, v in data.items()}


def _cmd_patch() -> None:
    team = os.environ["APPLE_TEAM_ID"]
    has_local = os.environ.get("HAS_LOCAL_DIST_KEY") == "1"
    path = _pbx_path()
    out = apply_ci_signing_patch(
        path.read_text(),
        has_local_dist_key=has_local,
        team_id=team,
        profiles=_load_profiles(),
    )
    path.write_text(out)
    if has_local:
        print("CI-only pbxproj signing patch (not committed)")
    else:
        print("CI-only pbxproj Dist Automatic pin (KEEP cert reuse, not committed)")


def _cmd_rewrite_hash(identity_hash: str) -> None:
    path = _pbx_path()
    path.write_text(rewrite_dist_identity_hash(path.read_text(), identity_hash))
    print("rewrote CODE_SIGN_IDENTITY to exact keychain hash")


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        print("usage: tf_archive_signing.py patch|rewrite-hash HASH", file=sys.stderr)
        return 2
    cmd = args[0]
    if cmd == "patch":
        _cmd_patch()
        return 0
    if cmd == "rewrite-hash":
        if len(args) < 2 or not args[1]:
            print("rewrite-hash requires the keychain identity hash", file=sys.stderr)
            return 2
        _cmd_rewrite_hash(args[1])
        return 0
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
