#!/usr/bin/env python3
"""CI opt + single-copy pack invariants. No network."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(msg: str) -> None:
    print(f"FAIL {msg}", file=sys.stderr)
    raise SystemExit(1)


def ok(msg: str) -> None:
    print(f"OK   {msg}")


def test_compile_workflow_drops_feature_branch_push() -> None:
    text = (ROOT / ".github/workflows/ios-compile.yml").read_text()
    if "cursor/blackout-ios-foundation-7e54" in text:
        fail("ios-compile.yml still pushes on the feature branch")
    if "pull_request:" not in text:
        fail("ios-compile.yml missing pull_request trigger")
    if "push:" not in text or "- main" not in text:
        fail("ios-compile.yml must keep push to main")
    if "cancel-in-progress: true" not in text:
        fail("ios-compile.yml lost cancel-in-progress")
    ok("ios-compile.yml is pull_request + push main only")


def test_testflight_paths_and_assign() -> None:
    text = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    if "workflow_dispatch:" not in text:
        fail("ios-testflight.yml missing workflow_dispatch")
    if "cursor/blackout-ios-foundation-7e54" not in text:
        fail("ios-testflight.yml missing feature-branch push")
    for path in ("Blackout/**", "Packages/**", "Blackout.xcodeproj/**", "tools/**"):
        if path not in text:
            fail(f"ios-testflight.yml missing path filter {path}")
    if "cancel-in-progress: true" not in text:
        fail("ios-testflight.yml lost cancel-in-progress")
    if "tools/asc_assign_internal.sh" not in text:
        fail("ios-testflight.yml does not call tools/asc_assign_internal.sh")
    if "6806388963" not in text:
        fail("ios-testflight.yml missing app id 6806388963")
    if "28035586-fce6-474f-9bc2-ef0f1f65306e" not in text:
        fail("ios-testflight.yml missing Internal group id")
    ok("ios-testflight.yml path-filters archive + assigns Internal")


def test_pbx_single_copy() -> None:
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    if "DefaultPack in Resources" in pbx:
        fail("pbxproj still copies DefaultPack via Resources")
    if "GuidePack in Resources" in pbx:
        fail("pbxproj still copies GuidePack via Resources")
    if "alwaysOutOfDate = 1" in pbx:
        fail("pbxproj still has alwaysOutOfDate = 1")
    if "Copy DefaultPack into app bundle" not in pbx:
        fail("pbxproj lost DefaultPack ditto phase")
    if "Copy GuidePack into app bundle" not in pbx:
        fail("pbxproj lost GuidePack ditto phase")
    if "CURRENT_PROJECT_VERSION = 11" not in pbx:
        fail("CURRENT_PROJECT_VERSION is no longer 11")
    if pbx.count("CURRENT_PROJECT_VERSION = 11") < 2:
        fail("expected CURRENT_PROJECT_VERSION = 11 on Debug and Release")
    if "MARKETING_VERSION = 0.1.0" not in pbx:
        fail("MARKETING_VERSION is no longer 0.1.0")
    ok("pbxproj is ditto-only, version 11, no alwaysOutOfDate")


def test_generator_does_not_restore_double_copy() -> None:
    src = (ROOT / "tools/generate_project.py").read_text()
    if "alwaysOutOfDate = 1" in src:
        fail("generate_project.py would restore alwaysOutOfDate")
    if "DefaultPack in Resources" in src or "GuidePack in Resources" in src:
        fail("generate_project.py would put packs back into Resources")
    if "Copy DefaultPack into app bundle" not in src:
        fail("generate_project.py lost DefaultPack ditto phase")
    if "Copy GuidePack into app bundle" not in src:
        fail("generate_project.py lost GuidePack ditto phase")
    if '"CURRENT_PROJECT_VERSION": "11"' not in src:
        fail("generate_project.py would bump CURRENT_PROJECT_VERSION")
    ok("generate_project.py regen stays ditto-only at version 11")


def test_assign_script_requires_secrets() -> None:
    script = ROOT / "tools/asc_assign_internal.sh"
    if not script.is_file():
        fail("tools/asc_assign_internal.sh missing")
    env = os.environ.copy()
    for name in (
        "APP_STORE_CONNECT_API_KEY",
        "APP_STORE_CONNECT_KEY_ID",
        "APP_STORE_CONNECT_ISSUER_ID",
    ):
        env.pop(name, None)
    proc = subprocess.run(
        ["bash", str(script)],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        fail("asc_assign_internal.sh succeeded without secrets")
    combined = (proc.stdout + proc.stderr).lower()
    if "missing" not in combined:
        fail("asc_assign_internal.sh did not report missing secrets")
    ok("asc_assign_internal.sh fails closed without secrets")


def main() -> None:
    test_compile_workflow_drops_feature_branch_push()
    test_testflight_paths_and_assign()
    test_pbx_single_copy()
    test_generator_does_not_restore_double_copy()
    test_assign_script_requires_secrets()
    print("all ci-opt checks passed")


if __name__ == "__main__":
    main()
