#!/usr/bin/env python3
"""CI-only pbx Dist signing for Blackout + BlackoutWidgets.

33927056130: do not put CODE_SIGN_IDENTITY on the global xcodebuild
archive / exportArchive CLI. That override hits Automatic SPM packages
(VisionCoreML, MapLibreMap, …) and exits 65. Manual Dist belongs on the
app and widget buildSettings only. SPM packages stay Automatic.
"""
from __future__ import annotations

import datetime
import json
import os
import plistlib
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
DIST_ALIAS_ORDER = (
    "iPhone Distribution",
    "Apple Distribution",
    "iOS Distribution",
)
_MISSING_BUNDLE_IDS = frozenset({"", "$(PRODUCT_BUNDLE_IDENTIFIER)", "(null)"})

_LOCAL_DEFAULTS = {ident: name for ident, name, _plat in reuse.BUNDLES}


def default_profile_map() -> dict[str, str]:
    return dict(_LOCAL_DEFAULTS)


def dist_certificate_alias(identity_line: str) -> str | None:
    """ExportOptions signingCertificate from a `security find-identity` line."""
    text = (identity_line or "").strip()
    if not text:
        return None
    if text in DIST_IDENTITY_ALIASES:
        return text
    quoted = re.search(r'"([^"]+)"', text)
    name = quoted.group(1) if quoted else text
    for alias in DIST_ALIAS_ORDER:
        if name == alias or name.startswith(f"{alias}:") or name.startswith(f"{alias} "):
            return alias
        if alias in name:
            return alias
    return None


def dist_identity_common_name(identity_line: str) -> str:
    quoted = re.search(r'"([^"]+)"', identity_line or "")
    return quoted.group(1) if quoted else ""


def export_options_plist(
    *,
    team_id: str,
    has_local_dist_key: bool,
    profiles: dict[str, str] | None,
    signing_certificate: str | None,
) -> dict[str, object]:
    """iOS App Store ExportOptions. signingCertificate from find-identity."""
    body: dict[str, object] = {
        "method": "app-store",
        "destination": "export",
        "teamID": team_id,
        "uploadSymbols": True,
        "manageAppVersionAndBuildNumber": False,
        "stripSwiftSymbols": True,
    }
    if profiles and has_local_dist_key:
        alias = dist_certificate_alias(signing_certificate or "")
        if not alias:
            raise ValueError(
                "ExportOptions signingCertificate requires a Dist find-identity "
                "alias (iPhone Distribution / Apple Distribution / iOS Distribution)"
            )
        body["signingStyle"] = "manual"
        body["signingCertificate"] = alias
        body["provisioningProfiles"] = dict(profiles)
    else:
        body["signingStyle"] = "automatic"
    return body


def xcarchive_application_properties(
    *,
    bid: str,
    version: str,
    short_version: str,
    team: str,
    signing_identity: str = "",
    default_version: str = "",
    default_short: str = "0.1.0",
) -> dict[str, object]:
    """Non-empty ApplicationProperties so exportArchive is not 'BID missing'."""
    ident = (bid or "").strip()
    if ident in _MISSING_BUNDLE_IDS or ident.startswith("$("):
        ident = APP_BUNDLE
    ver = (version or "").strip() or (default_version or "").strip()
    short = (short_version or "").strip() or default_short
    team_id = (team or "").strip()
    if not ident:
        raise ValueError("xcarchive ApplicationProperties CFBundleIdentifier is empty")
    if not ver:
        raise ValueError("xcarchive ApplicationProperties CFBundleVersion is empty")
    if not team_id:
        raise ValueError("xcarchive ApplicationProperties Team is empty")
    props: dict[str, object] = {
        "ApplicationPath": "Applications/Blackout.app",
        "Architectures": ["arm64"],
        "CFBundleIdentifier": ident,
        "CFBundleShortVersionString": short,
        "CFBundleVersion": ver,
        "Team": team_id,
    }
    identity = (signing_identity or "").strip()
    if identity:
        props["SigningIdentity"] = identity
    return props


def submission_authority_ok(codesign_display: str) -> bool:
    """True when codesign -d output has an Apple submission Dist Authority."""
    authorities = re.findall(r"^Authority=(.+)$", codesign_display or "", re.M)
    if not authorities:
        authorities = re.findall(r"Authority=([^\n]+)", codesign_display or "")
    for auth in authorities:
        for alias in DIST_ALIAS_ORDER:
            if alias in auth:
                return True
    return False


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


def _cmd_write_export_options(identity_line: str) -> None:
    try:
        body = export_options_plist(
            team_id=os.environ["APPLE_TEAM_ID"],
            has_local_dist_key=os.environ.get("HAS_LOCAL_DIST_KEY") == "1",
            profiles=_load_profiles() or None,
            signing_certificate=identity_line,
        )
    except ValueError as exc:
        print(exc)
        raise SystemExit(1) from exc
    path = Path(os.environ["RUNNER_TEMP"]) / "ExportOptions.plist"
    with path.open("wb") as fh:
        plistlib.dump(body, fh)
    print(
        "wrote",
        path,
        "signingStyle",
        body["signingStyle"],
        "signingCertificate",
        body.get("signingCertificate", ""),
    )


def _cmd_write_xcarchive_plist(
    path: str,
    bid: str,
    version: str,
    short_version: str,
    team: str,
    identity: str,
    default_version: str,
) -> None:
    try:
        props = xcarchive_application_properties(
            bid=bid,
            version=version,
            short_version=short_version,
            team=team,
            signing_identity=identity or dist_identity_common_name(identity),
            default_version=default_version,
        )
    except ValueError as exc:
        print(exc)
        raise SystemExit(1) from exc
    body = {
        "ApplicationProperties": props,
        "ArchiveVersion": 2,
        "CreationDate": datetime.datetime.utcnow(),
        "Name": "Blackout",
        "SchemeName": "Blackout",
    }
    dest = Path(path)
    with dest.open("wb") as fh:
        plistlib.dump(body, fh)
    print(
        "wrote xcarchive Info.plist",
        props["CFBundleIdentifier"],
        props["CFBundleVersion"],
        props.get("SigningIdentity", ""),
    )


def _cmd_check_submission_authority(path: str) -> int:
    text = Path(path).read_text(errors="replace")
    if not submission_authority_ok(text):
        print("FAIL not a submission Dist Authority")
        return 1
    print("OK submission Dist Authority")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        print(
            "usage: tf_archive_signing.py patch|rewrite-hash HASH|"
            "write-export-options IDLINE|write-xcarchive-plist ...|"
            "check-submission-authority FILE",
            file=sys.stderr,
        )
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
    if cmd == "write-export-options":
        _cmd_write_export_options(" ".join(args[1:]))
        return 0
    if cmd == "write-xcarchive-plist":
        if len(args) < 6:
            print(
                "write-xcarchive-plist PATH BID VER SHORT TEAM [IDENTITY] [DEFAULT_VER]",
                file=sys.stderr,
            )
            return 2
        _cmd_write_xcarchive_plist(
            args[1],
            args[2],
            args[3],
            args[4],
            args[5],
            args[6] if len(args) > 6 else "",
            args[7] if len(args) > 7 else "",
        )
        return 0
    if cmd == "check-submission-authority":
        if len(args) < 2 or not args[1]:
            print("check-submission-authority requires a codesign -d dump", file=sys.stderr)
            return 2
        return _cmd_check_submission_authority(args[1])
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
