#!/usr/bin/env python3
"""CI opt + CPV inject-54 locks for bible v3. No network.

Restored from foundation `tools/test_ci_opt.py` (PR #2 / 555513f) and
adapted to this vessel: tree CURRENT_PROJECT_VERSION stays 1; TestFlight
injects ASC next on the xcodebuild command line. Fail closed before Xcode
on NFC NDEF, a duplicate widget Info.plist, or CPV / workflow drift.
"""
from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

COMPILE_YML = ROOT / ".github/workflows/xcodebuild.yml"
TF_YML = ROOT / ".github/workflows/testflight-internal.yml"
PBX = ROOT / "Blackout.xcodeproj/project.pbxproj"
GENERATOR = ROOT / "tools/v3/generate_project.py"
TF_ARCHIVE = ROOT / ".github/ci/tf-archive.sh"
WIDGET_PLIST = ROOT / "BlackoutWidgets/Info.plist"
WATCH_PLIST = ROOT / "BlackoutWatch/Info.plist"
GATE_INVOKE = "python3 tools/test_ci_opt.py"
TREE_CPV = "1"


def fail(msg: str) -> None:
    print(f"FAIL {msg}", file=sys.stderr)
    raise SystemExit(1)


def ok(msg: str) -> None:
    print(f"OK   {msg}")


def _before_build(text: str, label: str, marker: str) -> None:
    invoke_at = text.find(GATE_INVOKE)
    build_at = text.find(marker)
    if invoke_at < 0:
        fail(f"{label} must run {GATE_INVOKE} before Xcode")
    if build_at < 0:
        fail(f"{label} lost {marker}")
    if invoke_at > build_at:
        fail(f"{label} runs {GATE_INVOKE} after {marker}")


def test_compile_workflow_invokes_gate() -> None:
    text = COMPILE_YML.read_text()
    if GATE_INVOKE not in text:
        fail("xcodebuild.yml must run tools/test_ci_opt.py before xcodebuild")
    _before_build(text, "xcodebuild.yml", "-project Blackout.xcodeproj")
    if "pull_request:" not in text:
        fail("xcodebuild.yml missing pull_request trigger")
    if "push:" not in text:
        fail("xcodebuild.yml missing push trigger")
    if "CURRENT_PROJECT_VERSION=" in text:
        fail("unsigned compile must use tree CPV=1 — do not inject on xcodebuild.yml")
    ok("xcodebuild.yml runs test_ci_opt.py before xcodebuild")


def test_testflight_workflow_invokes_gate() -> None:
    text = TF_YML.read_text()
    if "workflow_dispatch:" not in text:
        fail("testflight-internal.yml missing workflow_dispatch")
    on_block = text.split("jobs:", 1)[0]
    if re.search(r"^  push:", on_block, re.M) or re.search(
        r"^  pull_request:", on_block, re.M
    ):
        fail("testflight-internal.yml must stay dispatch-only")
    if GATE_INVOKE not in text:
        fail("testflight-internal.yml must run tools/test_ci_opt.py before archive")
    _before_build(text, "testflight-internal.yml", "tf-archive.sh")
    if "NEXT_CPV:" not in text:
        fail("testflight-internal.yml must pass NEXT_CPV into archive")
    if "6806388963" not in text:
        fail("testflight-internal.yml missing app id 6806388963")
    if "28035586-fce6-474f-9bc2-ef0f1f65306e" not in text:
        fail("testflight-internal.yml missing Internal group id")
    ok("testflight-internal.yml is dispatch-only and runs test_ci_opt.py first")


def test_cpv_inject_model() -> None:
    pbx = PBX.read_text()
    gen = GENERATOR.read_text()
    archive = TF_ARCHIVE.read_text()

    tree_hits = pbx.count(f"CURRENT_PROJECT_VERSION = {TREE_CPV};")
    if tree_hits != 6:
        fail(
            f"pbx must lock CURRENT_PROJECT_VERSION = {TREE_CPV} on 6 configs "
            f"(3 targets × Debug/Release); found {tree_hits}"
        )
    other = re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", pbx)
    drifted = [v for v in other if v != TREE_CPV]
    if drifted:
        fail(f"pbx CPV drifted off tree {TREE_CPV}: {drifted}")
    if f'CURRENT_PROJECT_VERSION = 54;' in pbx:
        fail("do not bump tree CPV to 54 — TF injects ASC next on the CLI")

    gen_hits = gen.count(f'"CURRENT_PROJECT_VERSION": "{TREE_CPV}"')
    if gen_hits != 3:
        fail(
            f"generate_project.py must emit CPV {TREE_CPV} for app/watch/widget; "
            f"found {gen_hits}"
        )
    if re.search(r'"CURRENT_PROJECT_VERSION": "(?!1")', gen):
        fail("generate_project.py would bump CURRENT_PROJECT_VERSION")

    if 'CURRENT_PROJECT_VERSION="$NEXT"' not in archive:
        fail("tf-archive.sh must inject CURRENT_PROJECT_VERSION on the CLI only")
    if "NEXT_CPV:?NEXT_CPV not set" not in archive:
        fail("tf-archive.sh must refuse archive without NEXT_CPV")
    if "not committed" not in archive:
        fail("tf-archive.sh must keep the CPV inject uncommitted")
    ok("CPV inject-54: tree=1 ×6 + generator ×3; TF CLI inject")


def test_nfc_tag_only() -> None:
    """ASC 90778: NDEF is disallowed in nfc.readersession.formats."""
    nfc_files: list[Path] = []
    for pattern in ("**/*.entitlements", "**/*.plist"):
        nfc_files.extend(
            p
            for p in ROOT.glob(pattern)
            if ".git" not in p.parts and "Vendor" not in p.parts
        )
    nfc_files.append(PBX)
    saw_nfc = False
    for path in nfc_files:
        text = path.read_text(errors="ignore")
        if "nfc.readersession" not in text and "NFCReader" not in text:
            if "<string>NDEF</string>" in text and path.suffix == ".entitlements":
                fail(f"ASC 90778: NDEF is disallowed ({path.relative_to(ROOT)})")
            continue
        saw_nfc = True
        if re.search(r"<string>NDEF</string>|nfc\.readersession\.formats.*NDEF", text):
            fail(f"ASC 90778: NDEF is disallowed ({path.relative_to(ROOT)})")
        if path.suffix == ".entitlements" and "<string>TAG</string>" not in text:
            fail(f"NFC entitlement must stay TAG-only ({path.relative_to(ROOT)})")
    if saw_nfc:
        ok("NFC formats are TAG-only (no NDEF)")
    else:
        ok("no NFC entitlement in this vessel; NDEF still forbidden")


def test_no_duplicate_widget_info_plist() -> None:
    pbx = PBX.read_text()
    gen = GENERATOR.read_text()
    supporting = ROOT / "Supporting" / "BlackoutWidgets-Info.plist"
    if supporting.is_file():
        fail(
            "duplicate widget Info.plist: Supporting/BlackoutWidgets-Info.plist "
            "must stay deleted (Xcode copies it onto the appex)"
        )
    extra = [
        p
        for p in ROOT.rglob("*Widgets*Info.plist")
        if ".git" not in p.parts and p.resolve() != WIDGET_PLIST.resolve()
    ]
    if extra:
        fail(f"duplicate widget Info.plist: {[str(p.relative_to(ROOT)) for p in extra]}")
    if not WIDGET_PLIST.is_file():
        fail("BlackoutWidgets/Info.plist missing")
    if pbx.count("INFOPLIST_FILE = BlackoutWidgets/Info.plist") < 2:
        fail("BlackoutWidgets lost INFOPLIST_FILE on Debug or Release")
    if "INFOPLIST_FILE = Supporting/BlackoutWidgets-Info.plist" in pbx:
        fail("widget Info.plist must not return to Supporting/")
    widget_ex = pbx.split('Exceptions for "BlackoutWidgets" */ = {', 1)
    if len(widget_ex) < 2:
        fail("BlackoutWidgets sync group lost Info.plist membershipExceptions")
    if "Info.plist," not in widget_ex[1].split("};", 1)[0]:
        fail(
            "BlackoutWidgets/Info.plist must stay a membershipException "
            "(sync-root copy onto the appex Info.plist)"
        )
    gen_ex = gen.split('Exceptions for "BlackoutWidgets" */ = {{', 1)
    if len(gen_ex) < 2 or "Info.plist," not in gen_ex[1].split("}};", 1)[0]:
        fail("generate_project.py would drop the widget Info.plist exception")
    try:
        info = plistlib.loads(WIDGET_PLIST.read_bytes())
    except Exception as exc:
        fail(f"BlackoutWidgets/Info.plist parse: {exc}")
    if info.get("CFBundleIdentifier") != "$(PRODUCT_BUNDLE_IDENTIFIER)":
        fail(
            "widget Info.plist missing CFBundleIdentifier — "
            "ValidateEmbeddedBinary / archive packaging sees (null)"
        )
    try:
        watch = plistlib.loads(WATCH_PLIST.read_bytes())
    except Exception as exc:
        fail(f"BlackoutWatch/Info.plist parse: {exc}")
    if watch.get("CFBundleIdentifier") != "$(PRODUCT_BUNDLE_IDENTIFIER)":
        fail("Watch Info.plist missing CFBundleIdentifier — archive ApplicationProperties")
    ok("one widget Info.plist, excluded from sync copy, identifier present")


def test_crisis_opt_locks() -> None:
    if (ROOT / "tools/strip-app-before-codesign.sh").is_file():
        fail("strip-app-before-codesign.sh must stay deleted")
    if (ROOT / ".github/ci/strip-app-before-codesign.sh").is_file():
        fail("CI strip script must stay deleted")
    loose = [
        p
        for p in ROOT.rglob("AppIcon*.png")
        if ".git" not in p.parts and not any("xcassets" in part for part in p.parts)
    ]
    if loose:
        fail(f"AppIcon PNGs must live only in Assets: {[str(p.relative_to(ROOT)) for p in loose]}")
    ok("no strip script; AppIcon only in Assets")


def main() -> None:
    test_compile_workflow_invokes_gate()
    test_testflight_workflow_invokes_gate()
    test_cpv_inject_model()
    test_nfc_tag_only()
    test_no_duplicate_widget_info_plist()
    test_crisis_opt_locks()


if __name__ == "__main__":
    main()
