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

import test_tf_archive_signing
import test_tf_asc_reuse
import test_tf_ipa_inspect

ROOT = Path(__file__).resolve().parents[1]

COMPILE_YML = ROOT / ".github/workflows/xcodebuild.yml"
TF_YML = ROOT / ".github/workflows/testflight-internal.yml"
PBX = ROOT / "Blackout.xcodeproj/project.pbxproj"
GENERATOR = ROOT / "tools/v3/generate_project.py"
TF_ARCHIVE = ROOT / ".github/ci/tf-archive.sh"
TF_ARCHIVE_SIGNING = ROOT / "tools/tf_archive_signing.py"
TF_SIGN = ROOT / "tools/tf_asc_signing.py"
TF_REUSE = ROOT / "tools/tf_asc_reuse.py"
TF_IPA_INSPECT = ROOT / "tools/tf_ipa_inspect.py"
WIDGET_PLIST = ROOT / "BlackoutWidgets/Info.plist"
WATCH_PLIST = ROOT / "BlackoutWatch/Info.plist"
GATE_INVOKE = "python3 tools/test_ci_opt.py"
TREE_CPV = "1"
KEEP_DIST_ID = "45YLWHL6UP"


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
    if "macos-14" not in text:
        fail("unsigned xcodebuild.yml must stay macos-14")
    if "Xcode_26" in text or "26.*" in text:
        fail("unsigned compile must stay Xcode 16 — do not move xcodebuild.yml to 26")
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
    # 33931992681: Xcode 16.2 / iOS 18.2 SDK is rejected. Keep unsigned
    # compile on macos-14 + Xcode 16. TF archive needs Xcode 26.
    if re.search(r"runs-on:\s*macos-14", text):
        fail("33931992681: TF macos-14 is iOS 18.2 SDK; Apple requires iOS 26 SDK")
    if re.search(r"runs-on:\s*macos-latest", text):
        fail("do not use macos-latest — pin macos-15 and select Xcode 26")
    if not re.search(r"runs-on:\s*macos-15", text):
        fail("TF must run on macos-15 so Xcode 26 is installed")
    if "Xcode_26" not in text:
        fail("TF must xcode-select Xcode 26 for the iOS 26 SDK")
    if "26.*" not in text:
        fail("TF must accept only Xcode 26.x")
    ok("testflight-internal.yml is dispatch-only and runs test_ci_opt.py first")


def test_altool_binds_primary_app() -> None:
    """33929367958: altool without --apple-id picked nested FMWK BID (−19000)."""
    text = TF_YML.read_text()
    parts = text.split("Upload IPA", 1)
    if len(parts) < 2:
        fail("Upload IPA step missing")
    step = parts[1].split("\n      - name:", 1)[0]
    if "--apple-id" not in step:
        fail("altool must pass --apple-id so it does not pick a nested FMWK BID")
    if '"$ASC_APP_ID"' not in step and "${ASC_APP_ID}" not in step:
        fail("altool --apple-id must bind ASC_APP_ID 6806388963")
    if "--bundle-id com.crisiskhan.blackout" not in step:
        fail("altool must bind --bundle-id com.crisiskhan.blackout")
    if "--bundle-version" not in step:
        fail("altool must pass --bundle-version")
    if "--bundle-short-version-string" not in step:
        fail("altool must pass --bundle-short-version-string")
    if "ASC_APP_ID empty" not in step and 'ASC_APP_ID:-}' not in step:
        fail("upload must fail closed when ASC_APP_ID is empty")
    if "--upload-app" not in step and "--upload-package" not in step:
        fail("must use xcrun altool --upload-app or --upload-package")
    if "--type ios" not in step:
        fail("altool must keep --type ios")
    if "--apiKey" not in step or "--apiIssuer" not in step:
        fail("altool must keep API key auth")
    if "com.crisiskhan.blackout.maplibre" in step or "com.maplibre.mapbox" in step:
        fail("do not invent an ASC app / apple-id for MapLibre")
    ok("altool binds primary app via --apple-id + --bundle-id")


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
    if pbx.count("INFOPLIST_KEY_CFBundleIdentifier") < 6:
        fail(
            "INFOPLIST_KEY_CFBundleIdentifier must stay on app/watch/widget "
            "Debug+Release so GENERATE_INFOPLIST emits a BID"
        )
    try:
        watch = plistlib.loads(WATCH_PLIST.read_bytes())
    except Exception as exc:
        fail(f"BlackoutWatch/Info.plist parse: {exc}")
    if watch.get("CFBundleIdentifier") != "$(PRODUCT_BUNDLE_IDENTIFIER)":
        fail("Watch Info.plist missing CFBundleIdentifier — archive ApplicationProperties")
    ok("one widget Info.plist, excluded from sync copy, identifier present")


def _blackout_native_target(pbx: str) -> str:
    marker = "/* Blackout */ = {\n\t\t\tisa = PBXNativeTarget;"
    start = pbx.find(marker)
    if start < 0:
        fail("Blackout PBXNativeTarget missing")
    nxt = pbx.find("isa = PBXNativeTarget;", start + len(marker))
    end = pbx.find("/* End PBXNativeTarget section */", start)
    if nxt >= 0:
        end = nxt if end < 0 else min(end, nxt)
    if end < 0:
        fail("Blackout PBXNativeTarget section truncated")
    return pbx[start:end]


def test_watch_omitted_from_app_store_archive() -> None:
    """Phone Internal IPA must not embed Watch — no ASC watchkitapp record."""
    pbx = PBX.read_text()
    gen = GENERATOR.read_text()
    archive = TF_ARCHIVE.read_text()
    tf_yml = TF_YML.read_text()
    scheme = (ROOT / "Blackout.xcodeproj/xcshareddata/xcschemes/Blackout.xcscheme").read_text()

    if "Embed Watch Content" in pbx:
        fail("Blackout still has Embed Watch Content — App Store IPA would carry Watch/")
    if "BlackoutWatch.app in Embed Watch Content" in pbx:
        fail("Blackout still copies BlackoutWatch.app into the iOS product")
    if "$(CONTENTS_FOLDER_PATH)/Watch" in pbx:
        fail("Blackout still has a Watch/ copy-files destination")

    app_tgt = _blackout_native_target(pbx)
    phases = app_tgt.split("buildPhases = (", 1)
    if len(phases) < 2:
        fail("Blackout target missing buildPhases")
    phase_body = phases[1].split(");", 1)[0]
    deps = app_tgt.split("dependencies = (", 1)
    if len(deps) < 2:
        fail("Blackout target missing dependencies")
    dep_body = deps[1].split(");", 1)[0]
    if "Watch" in phase_body or "Watch" in dep_body:
        fail("Blackout target still depends on or embeds BlackoutWatch")
    if "Embed Foundation Extensions" not in phase_body:
        fail("Widget Embed Foundation Extensions must stay on Blackout")
    if "BlackoutWidgets.appex in Embed Foundation Extensions" not in pbx:
        fail("Widget must stay embedded in the iOS archive")

    if 'name = BlackoutWatch;' not in pbx:
        fail("Keep the BlackoutWatch target — omit embed only, do not delete the target")
    if "PRODUCT_BUNDLE_IDENTIFIER = com.crisiskhan.blackout.watchkitapp;" not in pbx:
        fail("Watch bundle id must stay on the Watch target for later re-enable")

    if 'name = "Embed Watch Content"' in gen or "BlackoutWatch.app in Embed Watch Content" in gen:
        fail("generate_project.py would re-embed Watch on regen")
    if 'dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"' in gen:
        fail("generate_project.py would restore a Watch/ copy-files destination")
    if "{ids['dep_watch']}" in gen or "{ids['proxy_watch']}" in gen:
        fail("generate_project.py would restore Blackout → Watch embed or dependency")
    if 'name = BlackoutWatch;' not in gen:
        fail("generate_project.py must keep the BlackoutWatch target")
    if "Embed Foundation Extensions" not in gen:
        fail("generate_project.py must keep Widget embed")

    if "BlackoutWatch" in scheme or "watchkitapp" in scheme:
        fail("Blackout.xcscheme must archive Blackout.app only — no Watch blueprint")

    if "com.crisiskhan.blackout.watchkitapp" in tf_yml:
        fail("testflight-internal.yml must not create a Watch App Store profile")
    sign = TF_SIGN.read_text() if TF_SIGN.is_file() else ""
    reuse = TF_REUSE.read_text() if TF_REUSE.is_file() else ""
    if "com.crisiskhan.blackout.watchkitapp" in sign or "com.crisiskhan.blackout.watchkitapp" in reuse:
        fail("TF ASC signing helpers must not create a Watch App Store profile")
    if "com.crisiskhan.blackout.watchkitapp" in archive:
        fail("tf-archive.sh must not patch Watch signing — Watch is not in the IPA")
    if "com.crisiskhan.blackout.widgets" not in archive:
        fail("tf-archive.sh must still sign the Widget appex")
    if not re.search(r"Watch/|watchkitapp|BlackoutWatch\.app", archive):
        fail("tf-archive.sh must fail closed if the IPA still embeds Watch")
    ok("Watch omitted from App Store archive; Widget stays; target kept for later")


def test_maplibre_framework_not_owned_bundle_id() -> None:
    """33929367958: do not rewrite FMWK onto owned BIDs that create ASC collisions."""
    slices = [
        ROOT / "Vendor/MapLibre/MapLibre.xcframework/ios-arm64/MapLibre.framework/Info.plist",
        ROOT
        / "Vendor/MapLibre/MapLibre.xcframework/ios-arm64_x86_64-simulator/MapLibre.framework/Info.plist",
    ]
    owned = {
        "com.crisiskhan.blackout",
        "com.crisiskhan.blackout.maplibre",
    }
    for path in slices:
        if not path.is_file():
            fail(f"missing {path.relative_to(ROOT)}")
        pl = plistlib.loads(path.read_bytes())
        bid = pl.get("CFBundleIdentifier")
        pkg = pl.get("CFBundlePackageType")
        if bid in owned or (
            isinstance(bid, str) and bid.startswith("com.crisiskhan.blackout")
        ):
            fail(
                f"{path.relative_to(ROOT)} owned FMWK BID {bid} — "
                "altool −19000; strip or leave foreign, do not rewrite onto owned"
            )
        if bid != "com.maplibre.mapbox":
            fail(
                f"{path.relative_to(ROOT)} FMWK CFBundleIdentifier={bid!r} — "
                "33931992681: empty BID is invalid; keep vendor com.maplibre.mapbox"
            )
        if pkg != "FMWK":
            fail(f"{path.relative_to(ROOT)} must stay FMWK, got {pkg}")
    archive = TF_ARCHIVE.read_text()
    helper = TF_IPA_INSPECT.read_text() if TF_IPA_INSPECT.is_file() else ""
    if not TF_IPA_INSPECT.is_file():
        fail("tools/tf_ipa_inspect.py missing — IPA MapLibre inspect has no helper")
    if "com.maplibre.mapbox" not in helper:
        fail("tf_ipa_inspect.py must name com.maplibre.mapbox so the −19000 stays documented")
    if "strip_framework_identifier" in helper:
        fail("33931992681: do not strip FMWK BID to empty — Apple rejects ''")
    if "validate_framework_identifier" not in helper:
        fail("tf_ipa_inspect.py must require nested FMWK CFBundleIdentifier=com.maplibre.mapbox")
    if "owned_framework_identifier" in helper:
        fail("tf_ipa_inspect.py must not rewrite FMWK onto an owned BID")
    if "return APP_BID" in helper:
        fail("tf_ipa_inspect.py must not rewrite FMWK onto com.crisiskhan.blackout")
    if "tf_ipa_inspect.py" not in archive:
        fail("tf-archive.sh must run tools/tf_ipa_inspect.py after the IPA exists")
    inspect_at = archive.find("tf_ipa_inspect.py --ipa")
    ready_at = archive.find('echo "IPA ready:')
    if inspect_at < 0 or ready_at < 0 or inspect_at > ready_at:
        fail("tf-archive.sh must inspect the IPA before declaring IPA ready")
    if "com.maplibre.mapbox" not in archive:
        fail("tf-archive.sh must keep the com.maplibre.mapbox −19000 note")
    test_tf_ipa_inspect.main()
    ok("MapLibre.framework keeps vendor BID; IPA inspect does not strip it")


def test_maplibre_single_embed_via_maplibremap() -> None:
    """App must not also link Vendor/MapLibre — that XFWK has no CFBundleIdentifier."""
    pbx = PBX.read_text()
    gen = GENERATOR.read_text()
    app_tgt = _blackout_native_target(pbx)
    if "MapLibre in Frameworks" in pbx:
        fail("Blackout still links MapLibre as a direct product — archive XFWK has no BID")
    if "productName = MapLibre;" in pbx:
        fail("Blackout still has an XCSwiftPackageProductDependency named MapLibre")
    if 'XCLocalSwiftPackageReference "Vendor/MapLibre"' in pbx:
        fail("project must not also reference Vendor/MapLibre — MapLibreMap already depends on it")
    if "MapLibreMap in Frameworks" not in app_tgt and "MapLibreMap" not in app_tgt:
        fail("Blackout must keep the MapLibreMap product (one embed path)")
    if "productName = MapLibreMap;" not in pbx:
        fail("MapLibreMap package product missing")
    if 'pkg_paths.append(("Vendor/MapLibre"' in gen or "Vendor/MapLibre" in gen:
        fail("generate_project.py would re-add a direct Vendor/MapLibre app product")
    if '"MapLibreMap", "MapLibreMap"' not in gen and '("MapLibreMap", "MapLibreMap")' not in gen:
        fail("generate_project.py must keep MapLibreMap as an app package")
    ok("MapLibre embeds once via MapLibreMap; Vendor/MapLibre is not an app product")


def test_asc_reuse_not_delete_create() -> None:
    """GHA 33924134240 / 33924251037: delete+create hit ASC 500; archive never ran."""
    yml = TF_YML.read_text()
    sign = TF_SIGN.read_text() if TF_SIGN.is_file() else ""
    reuse = TF_REUSE.read_text() if TF_REUSE.is_file() else ""
    archive = TF_ARCHIVE.read_text()
    signing_helper = TF_ARCHIVE_SIGNING.read_text() if TF_ARCHIVE_SIGNING.is_file() else ""
    if "tools/tf_asc_signing.py" not in yml:
        fail("testflight-internal.yml must run tools/tf_asc_signing.py (reuse helper)")
    if "PROFILE delete stale" in yml or "PROFILE delete stale" in sign:
        fail("TF must not delete GHA App Store profiles on the happy path")
    if "REVOKE orphan Dist" in yml or "REVOKE orphan Dist" in sign:
        fail("TF must not revoke Dist certs on the happy path")
    if KEEP_DIST_ID not in reuse:
        fail(f"tf_asc_reuse.py must pin KEEP Dist cert {KEEP_DIST_ID}")
    if "resolve_profile" not in reuse or "Not deleting" not in reuse:
        fail("tf_asc_reuse.py must get-or-create / reuse ACTIVE profiles by name")
    if "GHA Local" not in reuse:
        fail("tf_asc_reuse.py must sign with Local-named App Store profiles")
    if "should_revoke_development_orphan" not in reuse:
        fail("tf_asc_reuse.py must offer a Development orphan revoke helper")
    if "revoke_stale_local_dist" not in reuse or "revoke_stale_local_dist" not in sign:
        fail("TF must revoke stale non-KEEP Dist leftovers before the next mint")
    if "LOCAL_PROFILE_NAMES" not in reuse:
        fail("tf_asc_reuse.py must replace only Local-named profiles")
    if "select_profile_any_state" not in reuse:
        fail("tf_asc_reuse.py must replace INVALID Local leftovers after Dist prune")
    if "profile_list_query" not in reuse or "INVALID" not in reuse:
        fail("TF profile list must include INVALID leftovers after Dist prune")
    if "profile_list_query" not in sign:
        fail("tf_asc_signing.py must list profiles via profile_list_query")
    if "PROFILE_CREATE_RETRY_SLEEPS" not in reuse or "PROFILE_CREATE_ATTEMPTS" not in reuse:
        fail("tf_asc_reuse.py must retry Local profile CREATE on ASC 500 with bounded backoff")
    if "local_profile_inter_create_delay" not in reuse:
        fail("tf_asc_reuse.py must cool down between Local profile writes")
    if "local_profile_inter_create_delay" not in sign:
        fail("tf_asc_signing.py must cool down after iOS Local write before Widgets Local")
    if "HAS_LOCAL_DIST_KEY" not in archive:
        fail("tf-archive.sh must switch on HAS_LOCAL_DIST_KEY")
    if (
        'signingStyle"] = "manual"' not in archive
        and "signingStyle'] = 'manual'" not in archive
        and '["signingStyle"] = "manual"' not in signing_helper
        and '"signingStyle": "manual"' not in signing_helper
    ):
        fail("tf-archive.sh must use Manual signing when HAS_LOCAL_DIST_KEY=1")
    if "GHA Local" not in archive:
        fail("tf-archive.sh Manual path must default to Local profile names")
    # 33927056130: CLI CODE_SIGN_IDENTITY hits SPM packages and exits 65.
    start = archive.find('echo "xcodebuild archive..."')
    end = archive.find("archive 2>&1", start)
    if start < 0 or end < 0:
        fail("tf-archive.sh must invoke xcodebuild archive")
    if "CODE_SIGN_IDENTITY=" in archive[start:end]:
        fail("do not pass CODE_SIGN_IDENTITY on the xcodebuild archive CLI")
    if "tf_archive_signing.py" not in archive:
        fail("tf-archive.sh must apply Manual Dist via tools/tf_archive_signing.py")
    # 33931034850: ExportOptions hardcoded Apple Distribution while the
    # keychain identity was iPhone Distribution; exportArchive looked for
    # 3rd Party Mac Developer Installer; hand-zip uploaded a non-submission IPA.
    if "write-export-options" not in archive:
        fail("tf-archive.sh must write ExportOptions from the Dist find-identity alias")
    if 'signingCertificate"] = "Apple Distribution"' in archive:
        fail("do not hard-code ExportOptions signingCertificate to Apple Distribution")
    if "dist_certificate_alias" not in signing_helper:
        fail("tf_archive_signing.py must map find-identity CN to a Dist alias")
    if "submission_authority_ok" not in signing_helper:
        fail("tf_archive_signing.py must recognize Apple submission Dist Authority")
    if "check-submission-authority" not in archive:
        fail("hand-zip must verify codesign Authority before declaring the IPA ready")
    if "Fail closed" not in archive:
        fail("hand-zip must fail closed when Authority is not a submission Dist identity")
    if "re-sign nested" not in archive:
        fail("incomplete archive-product signature must re-sign nested frameworks/appex")
    if "SigningIdentity" not in archive and "SigningIdentity" not in signing_helper:
        fail("xcarchive Info.plist must include SigningIdentity for exportArchive")
    if '"app-store"' not in signing_helper and "app-store-connect" not in signing_helper:
        fail("ExportOptions method must stay app-store / app-store-connect (iOS)")
    if "3rd Party Mac Developer Installer" in signing_helper:
        fail("do not export with 3rd Party Mac Developer Installer")
    if "zip -r" in archive or "zip -y" in archive:
        fail("do not hand-zip the IPA with info-zip — that breaks submission signing")
    if "ditto -c -k" not in archive:
        fail("hand-zip must use ditto -c -k so the Dist signature stays intact")
    if "--sequesterRsrc" in archive:
        fail("33931992681: ditto --sequesterRsrc created reserved Blackout.app/Resources")
    if "--norsrc" not in archive:
        fail("hand-zip must ditto --norsrc so the iOS IPA has no resource-fork Resources")
    if "Blackout.app/Resources" not in archive:
        fail("tf-archive.sh must fail closed if the IPA contains reserved Blackout.app/Resources")
    if "Xcode_16.2.app/Contents/Developer/Toolchains" in archive:
        fail("App Intents no-op must use the selected Xcode 26 toolchain, not hard-coded 16.2")
    if "xcode-select -p" not in archive:
        fail("App Intents no-op path must follow xcode-select -p")
    if "--identifier com.crisiskhan.blackout" not in archive:
        fail("re-sign must pass --identifier com.crisiskhan.blackout")
    if "--identifier com.crisiskhan.blackout.widgets" not in archive:
        fail("re-sign widget must pass --identifier com.crisiskhan.blackout.widgets")
    if "--identifier com.maplibre.mapbox" not in archive:
        fail("re-sign MapLibre must pass --identifier com.maplibre.mapbox")
    if "check-identifier" not in archive:
        fail("tf-archive.sh must require codesign Identifier to match CFBundleIdentifier")
    if "codesign --verify --deep --strict" not in archive:
        fail("tf-archive.sh must codesign --verify the IPA app before upload")
    if 'rm -rf "$APP/_CodeSignature"' in archive:
        fail("do not rm _CodeSignature and leave the archive product unsigned")
    test_tf_archive_signing.main()
    if "watchkitapp" in reuse:
        fail("tf_asc_reuse BUNDLES must stay iOS + widgets only")
    test_tf_asc_reuse.main()
    ok("ASC local Dist + Local profiles; KEEP Dist is reference-only")


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
    test_watch_omitted_from_app_store_archive()
    test_altool_binds_primary_app()
    test_maplibre_framework_not_owned_bundle_id()
    test_maplibre_single_embed_via_maplibremap()
    test_asc_reuse_not_delete_create()
    test_crisis_opt_locks()


if __name__ == "__main__":
    main()
