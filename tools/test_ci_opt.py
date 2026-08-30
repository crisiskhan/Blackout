#!/usr/bin/env python3
"""CI opt + single-copy pack invariants. No network."""
from __future__ import annotations

import json
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


STATEWIDE_PACKS = (
    (
        "us-tx",
        "texas.pack.zip",
        "220512882",
        "6ff6c9a191fe5df8d3bf48abb360ad361990bc672c1c59bd0cf2e3a3d5d55ade",
    ),
    (
        "us-nm",
        "new-mexico.pack.zip",
        "77478829",
        "2e605b0a386c6fbfa1288e5bea4ef96f42ddd5c60633f954b42c8c0e7665a4a8",
    ),
    (
        "us-fl",
        "florida.pack.zip",
        "79093063",
        "49d27c808c49fc894a1ba1021f951966560408c1ebe808f4c0d158e0c238b62d",
    ),
    (
        "us-ny",
        "new-york.pack.zip",
        "130327390",
        "928034851277ab8628521f5bfd7f2f06e6bfed5b588d58f9b46033bae5e64500",
    ),
)


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
    if "push:" in text or "pull_request:" in text:
        fail("ios-testflight.yml must stay dispatch-only")
    if "cursor/blackout-ios-foundation-7e54" in text:
        fail("ios-testflight.yml must not auto-run on the feature branch")
    if "cancel-in-progress: true" not in text:
        fail("ios-testflight.yml lost cancel-in-progress")
    if "tools/asc_assign_internal.sh" not in text:
        fail("ios-testflight.yml does not call tools/asc_assign_internal.sh")
    if "tools/asc_prune_development_certs.sh" not in text:
        fail("ios-testflight.yml does not prune leftover Development certs")
    if "CODE_SIGN_IDENTITY=" in text:
        fail("ios-testflight.yml must not pass CODE_SIGN_IDENTITY on the CLI")
    if "python3 -m pip install" in text:
        fail("ios-testflight.yml still pip-installs into system Python")
    if "6806388963" not in text:
        fail("ios-testflight.yml missing app id 6806388963")
    if "28035586-fce6-474f-9bc2-ef0f1f65306e" not in text:
        fail("ios-testflight.yml missing Internal group id")
    if "ASC_NOT_BEFORE=" not in text:
        fail("ios-testflight.yml does not stamp ASC_NOT_BEFORE before archive")
    if 'if [ -z "${ASC_NOT_BEFORE:-}" ]' not in text:
        fail("ios-testflight.yml does not refuse assign without ASC_NOT_BEFORE")
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
    if "Copy FieldPacks into app bundle" not in pbx:
        fail("pbxproj lost FieldPacks ditto phase")
    if "FieldPacks in Resources" in pbx:
        fail("pbxproj copies FieldPacks via Resources (tile collision)")
    if "GENERATE_INFOPLIST_FILE = YES;\n\t\t\t\t\tINFOPLIST_FILE = Supporting/BlackoutWidgets-Info.plist" in pbx:
        fail("BlackoutWidgets GENERATE_INFOPLIST_FILE + INFOPLIST_FILE collide on Xcode 16")
    if pbx.count("INFOPLIST_FILE = Supporting/BlackoutWidgets-Info.plist") < 2:
        fail("BlackoutWidgets lost INFOPLIST_FILE on Debug or Release")
    if "INFOPLIST_FILE = BlackoutWidgets/Info.plist" in pbx:
        fail("widget Info.plist must stay outside the synced BlackoutWidgets folder")
    if pbx.count("GENERATE_INFOPLIST_FILE = NO;") < 2:
        fail("BlackoutWidgets GENERATE_INFOPLIST_FILE must stay NO")
    if (ROOT / "BlackoutWidgets" / "Info.plist").is_file():
        fail("BlackoutWidgets/Info.plist in the sync root is copied onto the appex Info.plist")
    widget_plist = (ROOT / "Supporting" / "BlackoutWidgets-Info.plist").read_text()
    if "CFBundleIdentifier" not in widget_plist:
        fail("widget Info.plist missing CFBundleIdentifier — ValidateEmbeddedBinary sees (null)")
    if "$(PRODUCT_BUNDLE_IDENTIFIER)" not in widget_plist:
        fail("widget Info.plist must expand PRODUCT_BUNDLE_IDENTIFIER (parent prefix check)")
    if pbx.count("PRODUCT_BUNDLE_IDENTIFIER = com.crisiskhan.blackout.widget") < 2:
        fail("widget bundle id must stay com.crisiskhan.blackout.widget on Debug and Release")
    if "CURRENT_PROJECT_VERSION = 19" not in pbx:
        fail("CURRENT_PROJECT_VERSION is no longer 19")
    if pbx.count("CURRENT_PROJECT_VERSION = 19") < 2:
        fail("expected CURRENT_PROJECT_VERSION = 19 on Debug and Release")
    if "MARKETING_VERSION = 0.1.0" not in pbx:
        fail("MARKETING_VERSION is no longer 0.1.0")
    if "Apple Distribution" in pbx:
        fail("pbxproj must not set Apple Distribution (Automatic conflict)")
    ok("pbxproj is ditto-only, version 19, no alwaysOutOfDate")


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
    if "Copy FieldPacks into app bundle" not in src:
        fail("generate_project.py lost FieldPacks ditto phase")
    if "copy_fieldpacks.sh" not in src:
        fail("generate_project.py lost copy_fieldpacks.sh")
    if '"CURRENT_PROJECT_VERSION": "19",' not in src:
        fail("generate_project.py would bump CURRENT_PROJECT_VERSION")
    if "Apple Distribution" in src:
        fail("generate_project.py must not set Apple Distribution")
    if "generated-sample" in src:
        fail("generate_project.py would restore synthetic DefaultPack stubs")
    if "SOS red core" in src or "if r < 280" in src:
        fail("generate_project.py would restore the synthetic red-disc AppIcon")
    if "brand/emblem.jpeg" not in src and 'brand" / "emblem.jpeg' not in src:
        fail("generate_project.py does not render AppIcon from brand/emblem.jpeg")
    ok("generate_project.py regen stays ditto-only at version 19")


def test_map_chrome_lock() -> None:
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    radar = (ROOT / "Packages/Maps/Sources/Maps/RadarHUDView.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    for banned in (
        "packPaintLog",
        "file tiles",
        "NoPackCanvas",
        "CompassRose",
        "MeshPill",
        "PermissionDenied",
        "GPSChip",
    ):
        if banned in maps:
            fail(f"MapsRootView still paints {banned}")
    if "MapLockHUD" not in maps or "NO FIX" not in maps:
        fail("MapsRootView lost the 56h GPS lock HUD")
    if 'MetalButton("Recenter"' not in maps or 'MetalButton("Layers"' not in maps:
        fail("MapsRootView lost Recenter / Layers metal chips")
    if 'MetalButton("Packs"' not in maps:
        fail("MapsRootView lost Packs metal chip")
    if "MapEmptyCard" not in maps:
        fail("MapsRootView lost the single empty card")
    if "showFieldPacksOverlay" in root:
        fail("Field Packs is still a ZStack overlay")
    if "fieldPacksSheetBinding" in root or "FieldPacksView" in root:
        fail("first-run Field Packs sheet must stay dead")
    if "fieldPacksIntroCompleted" in root:
        fail("RootView still auto-presents the pack intro")
    if (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPacksView.swift").exists():
        fail("FieldPacksView skip sheet must stay deleted")
    catalog_list = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalogList.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    if "func skipIntro" in store or "Skip uses" in store or 'case skip' in (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalog.swift").read_text():
        fail("Skip-as-gate still lives in the pack catalog")
    for label in ('"No wifi"', '"Downloading"', '"Ready"', '"Failed"'):
        if label not in catalog_list:
            fail(f"Expedition catalog lost state {label}")
    if 'case .available' in catalog_list or 'case .skip' in catalog_list:
        fail("catalog still paints available/skip")
    if "destination = .expedition" not in root:
        fail("Packs must open the Expedition plate, not a modal")
    if "Heading-up" in radar or "Sweep audio" in radar or "0 peers · self only" in radar:
        fail("RadarHUDView still floats heading/audio/peer chrome")
    if "MKMapView(" in maps:
        fail("MapsRootView must not construct MKMapView")
    if "URLSession" in maps:
        fail("MapsRootView must not use URLSession")
    ok("Map chrome is HUD + Recenter/Layers/Packs, catalog on Expedition")


def test_map_pack_resolver() -> None:
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    pack = (ROOT / "Packages/Maps/Sources/Maps/FileMapPack.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    if "replaceInstalledRoots" not in pack or "pinToBundled" not in pack:
        fail("FileMapPack lost the installed-pack resolver")
    if "installedPackRoots" not in store:
        fail("PackStore lost installedPackRoots")
    if "installedPackRoots" not in root or "bundledRegion" not in root:
        fail("RootView does not pass installed pack roots / bundled region")
    if "resolvePaintPack" not in maps:
        fail("MapsRootView lost resolvePaintPack")
    if "lastKnown" not in maps:
        fail("MapsRootView resolve must fall back to last-known on NO FIX")
    if "MKMapView(" in pack or "URLSession" in pack:
        fail("FileMapPack must not use MapKit or URLSession")
    routing_loader = (ROOT / "Packages/Maps/Sources/MapsRouting/RoutingPack.swift").read_text()
    if "func coveringRoot" not in routing_loader or "func loadCovering" not in routing_loader:
        fail("RoutingPackLoader must resolve covering Field Pack routing/")
    if "RoutingPackLoader.load(packRoot: snapshot" in pack:
        fail("FileMapPack still loads routing only from DefaultPack at init")
    if "reloadRouting" not in pack or "coveringRoot" not in pack:
        fail("FileMapPack must load routing/ from the covering pack, not the painted tile root")
    if "MKDirections" in pack or "URLSession" in routing_loader:
        fail("routing loader must not use MKDirections or URLSession")
    ok("Map paints one covering installed pack; Recenter stays bundled")


def test_usgs_defaultpack() -> None:
    pack = ROOT / "Blackout" / "DefaultPack"
    man = json.loads((pack / "manifest.json").read_text())
    if man.get("kind") != "field-pack":
        fail("DefaultPack kind is not field-pack")
    if man.get("kind") == "generated-sample":
        fail("DefaultPack is still generated-sample stubs")
    pngs = list((pack / "tiles").rglob("*.png"))
    need = int(man.get("tileCount") or 0)
    if len(pngs) < need:
        fail(f"DefaultPack has {len(pngs)} PNGs, tileCount {need}")
    for rel in ("tiles/10/211/387.png", "tiles/12/848/1553.png"):
        path = pack / rel
        if not path.is_file():
            fail(f"DefaultPack missing probe {rel}")
        raw = path.read_bytes()
        if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
            fail(f"{rel} is not a PNG")
        if path.stat().st_size < 8000:
            fail(f"{rel} is still a stub ({path.stat().st_size} bytes)")
    copy = (ROOT / "tools/copy_defaultpack.sh").read_text()
    probe = (ROOT / "tools/probe_defaultpack_app.sh").read_text()
    if "tiles/10/211/387.png" not in copy or "tiles/12/848/1553.png" not in copy:
        fail("copy_defaultpack.sh lost probe paths")
    if "tiles/10/211/387.png" not in probe or "tiles/12/848/1553.png" not in probe:
        fail("probe_defaultpack_app.sh lost probe paths")
    if (pack / "routing").exists() or (pack / "routing" / "graph.bin").exists():
        fail("DefaultPack must not ship routing/")
    if "routing" in man:
        fail("DefaultPack manifest must not declare a routing graph")
    if "must not ship routing" not in copy or "must not ship routing" not in probe:
        fail("DefaultPack copy/probe must refuse routing/")
    ok("DefaultPack is USGS field-pack topo, probes exist")


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
    src = script.read_text()
    if "python3 -m venv" not in src:
        fail("asc_assign_internal.sh must install PyJWT in a venv")
    if "python3 -m pip install -q PyJWT" in src:
        fail("asc_assign_internal.sh still pip-installs into system Python")
    if "ASC_NOT_BEFORE is required in GitHub Actions" not in src:
        fail("asc_assign_internal.sh must require ASC_NOT_BEFORE in Actions")
    if "SKIP stale" not in src:
        fail("asc_assign_internal.sh must skip builds uploaded before this archive")
    if 'params["filter[version]"]' not in src and "filter[version]" not in src:
        fail("asc_assign_internal.sh must filter ASC builds by CFBundleVersion")
    if "FALLBACK assign existing VALID missing-compliance" in src and "refusing FALLBACK" not in src:
        fail("asc_assign_internal.sh must not assign a stale same-number build")
    if "def pick_assign_match" not in src:
        fail("asc_assign_internal.sh must expose pick_assign_match")
    if 'raise SystemExit(2)' not in src or "FAILED_STATE" not in src:
        fail("asc_assign_internal.sh must still fail closed on FAILED/INVALID")
    ok("asc_assign_internal.sh fails closed without secrets")


def _assign_helpers():
    src = (ROOT / "tools/asc_assign_internal.sh").read_text()
    start = src.index("def parse_iso")
    end = src.index("\nnot_before = parse_iso(not_before_raw)")
    ns: dict = {}
    exec("from datetime import datetime, timezone\n" + src[start:end], ns)
    return ns


def test_assign_pick_prefers_fresh_then_fallback() -> None:
    helpers = _assign_helpers()
    parse_iso = helpers["parse_iso"]
    pick = helpers["pick_assign_match"]
    not_before = parse_iso("2026-08-29T18:46:45Z")
    stale_valid = {
        "id": "0ae23432-d3af-4c91-9b36-55cf5f6baf00",
        "version": "19",
        "processingState": "VALID",
        "usesNonExemptEncryption": None,
        "uploadedDate": "2026-08-29T10:17:14-07:00",
        "internalBuildState": "MISSING_EXPORT_COMPLIANCE",
    }
    fresh_processing = {
        "id": "fresh-19",
        "version": "19",
        "processingState": "PROCESSING",
        "usesNonExemptEncryption": None,
        "uploadedDate": "2026-08-29T18:50:00Z",
        "internalBuildState": None,
    }
    kind, rec = pick([stale_valid], not_before)
    if kind != "none" or rec is not None:
        fail(f"stale VALID missing-compliance must not be assigned, got {kind} {rec}")
    kind, rec = pick([fresh_processing, stale_valid], not_before)
    if kind != "fresh" or rec is not fresh_processing:
        fail(f"expected fresh preference, got {kind} {rec}")
    failed = dict(stale_valid, processingState="FAILED", id="failed-19")
    kind, rec = pick([failed], not_before)
    if kind != "none" or rec is not None:
        fail(f"FAILED must not be assigned, got {kind} {rec}")
    ok("pick_assign_match assigns only builds uploaded after ASC_NOT_BEFORE")


def test_assign_existing_workflow() -> None:
    path = ROOT / ".github/workflows/asc-assign-existing.yml"
    if not path.is_file():
        fail("missing .github/workflows/asc-assign-existing.yml")
    text = path.read_text()
    if "workflow_dispatch:" not in text:
        fail("asc-assign-existing.yml must be workflow_dispatch")
    for banned in ("push:", "pull_request:", "schedule:"):
        if banned in text:
            fail(f"asc-assign-existing.yml must not trigger on {banned}")
    if "want_build" not in text:
        fail("asc-assign-existing.yml missing optional want_build input")
    if "2000-01-01T00:00:00Z" not in text:
        fail("asc-assign-existing.yml must set ASC_NOT_BEFORE=2000-01-01T00:00:00Z")
    if "tools/asc_assign_internal.sh" not in text:
        fail("asc-assign-existing.yml must call tools/asc_assign_internal.sh")
    if "python3 -m venv" not in text:
        fail("asc-assign-existing.yml must use a venv like ios-testflight.yml")
    if "6806388963" not in text:
        fail("asc-assign-existing.yml missing ASC_APP_ID 6806388963")
    if "28035586-fce6-474f-9bc2-ef0f1f65306e" not in text:
        fail("asc-assign-existing.yml missing Internal group id")
    for secret in (
        "APP_STORE_CONNECT_API_KEY",
        "APP_STORE_CONNECT_KEY_ID",
        "APP_STORE_CONNECT_ISSUER_ID",
    ):
        if secret not in text:
            fail(f"asc-assign-existing.yml missing secret {secret}")
    if "CURRENT_PROJECT_VERSION" in text and "bump" in text.lower():
        fail("asc-assign-existing.yml must not bump CURRENT_PROJECT_VERSION")
    ok("asc-assign-existing.yml is dispatch-only assign of an existing build")


def test_prune_script_requires_secrets() -> None:
    script = ROOT / "tools/asc_prune_development_certs.sh"
    if not script.is_file():
        fail("tools/asc_prune_development_certs.sh missing")
    src = script.read_text()
    if "IOS_DISTRIBUTION" in src and "REVOKE_TYPES" in src and "IOS_DISTRIBUTION" in src.split("REVOKE_TYPES")[1][:400]:
        fail("prune script must not revoke Distribution certs")
    if "DEVELOPMENT" not in src or "IOS_DEVELOPMENT" not in src:
        fail("prune script must target Apple Development / iOS Development")
    if "DISTRIBUTION" not in src or "KEEP" not in src:
        fail("prune script must keep Distribution certs")
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
        fail("asc_prune_development_certs.sh succeeded without secrets")
    combined = (proc.stdout + proc.stderr).lower()
    if "missing" not in combined:
        fail("asc_prune_development_certs.sh did not report missing secrets")
    ok("asc_prune_development_certs.sh fails closed without secrets")


def test_live_mesh_1n() -> None:
    mesh = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MeshFacade.swift").read_text()
    pipe = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MultipeerPipe.swift").read_text()
    wire = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MeshWire.swift").read_text()
    crypto = (ROOT / "Packages/Crypto/Sources/BlackoutCrypto/LoopbackCrypto.swift").read_text()
    proto = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/Protocols.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    gen = (ROOT / "tools/generate_project.py").read_text()
    if "MultipeerConnectivity" not in mesh or "MultipeerConnectivity" not in pipe:
        fail("Mesh is not using MultipeerConnectivity")
    if "func start() {}" in mesh:
        fail("MeshFacade start is still a no-op")
    if "URLSession" in mesh or "URLSession" in pipe or "URLSession" in wire:
        fail("Mesh must not use URLSession")
    if "localAdvertisement" not in proto or "registerPeerAdvertisement" not in proto:
        fail("CryptoServing missing peer advertisement hooks")
    if "preferredRecipient" not in proto:
        fail("CryptoServing missing preferredRecipient")
    if "sharedSecretFromKeyAgreement" not in crypto:
        fail("LoopbackCrypto missing ECDH peer seal")
    if "roster.radarBlips" not in maps:
        fail("Radar peers must come from the party roster")
    if "kind: .stranger" in maps:
        fail("do not invent stranger radar blips")
    for src, label in ((pbx, "pbxproj"), (gen, "generate_project.py")):
        if "NSLocalNetworkUsageDescription" not in src:
            fail(f"{label} missing Local Network usage string")
        if "NSBonjourServices" not in src or "blckout-mesh" not in src:
            fail(f"{label} missing Bonjour mesh service")
    if "CURRENT_PROJECT_VERSION = 19" not in pbx:
        fail("version was bumped off 19")
    if "MARKETING_VERSION = 0.1.0" not in pbx:
        fail("MARKETING_VERSION changed")
    tools = (ROOT / "Packages/Maps/Sources/Maps/MapTools.swift").read_text()
    if "MeshPill(nearbyCount: roster.peerCount)" in tools:
        fail("tools Radar MeshPill must use radio nearbyPeerCount, not roster.peerCount")
    if "MeshPill(nearbyCount: nearbyPeerCount)" not in tools:
        fail("tools Radar lost the radio MeshPill")
    ok("live mesh 1/N is Multipeer, no WAN, radar peers from roster, version 19")


def test_pack_relay_1n() -> None:
    pipe = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MultipeerPipe.swift").read_text()
    facade = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MeshFacade.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    zip_src = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackZip.swift").read_text()
    catalog = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalog.swift").read_text()
    catalog_list = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalogList.swift").read_text()
    packs_pkg = (ROOT / "Packages/Packs/Package.swift").read_text()
    app = (ROOT / "Blackout/AppContainer.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    if "sendResource" not in pipe:
        fail("MultipeerPipe is not using sendResource")
    if "func sendFile" not in facade:
        fail("MeshFacade missing sendFile")
    if "URLSession" in pipe or "URLSession" in facade:
        fail("Mesh relay must not use URLSession")
    if "prepareRelayZip" not in store or "installRelayedZip" not in store:
        fail("PackStore missing relay zip prepare/install")
    if "func archive" not in zip_src:
        fail("PackZip cannot archive a folder for relay")
    if "cityRelayIDs" not in catalog or "el-paso" not in catalog:
        fail("city relay allowlist missing")
    if "Send to nearby phone" not in catalog_list:
        fail("Expedition pack catalog missing Send to nearby phone")
    if "import BlackoutMesh" in packs_pkg or "import BlackoutMesh" in store:
        fail("Packs must not import Mesh")
    if "relayPack" not in app or "installRelayedZip" not in app:
        fail("AppContainer does not glue pack relay")
    if "session.download" in store.split("installRelayedZip")[-1][:2000]:
        fail("installRelayedZip must not download")
    if "CURRENT_PROJECT_VERSION = 19" not in pbx:
        fail("version was bumped off 19")
    if "MARKETING_VERSION = 0.1.0" not in pbx:
        fail("MARKETING_VERSION changed")
    ok("city pack relay uses sendResource, Packs owns zip/hash, version 19")


def test_bundled_statewide_archive_only() -> None:
    compile_yml = (ROOT / ".github/workflows/ios-compile.yml").read_text()
    flight = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    fetch = (ROOT / "tools/fetch_bundled_field_packs.sh").read_text()
    copy = (ROOT / "tools/copy_fieldpacks.sh").read_text()
    probe = (ROOT / "tools/probe_fieldpacks_app.sh").read_text()
    catalog = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalog.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    sos = (ROOT / "Packages/SOS/Sources/SOS/SOSFab.swift").read_text()
    guide = (ROOT / "Packages/Field/Sources/Field/FieldRootView.swift").read_text()
    gitignore = (ROOT / ".gitignore").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()

    if "fetch_bundled_field_packs" in compile_yml or "florida.pack.zip" in compile_yml:
        fail("ios-compile.yml must not fetch statewide pack zips")
    if "FIELD_PACKS_REQUIRED" in compile_yml:
        fail("ios-compile.yml must not require Field Packs in the unsigned app")
    if "tools/fetch_bundled_field_packs.sh" not in flight:
        fail("ios-testflight.yml does not fetch statewide packs before archive")
    if "FIELD_PACKS_REQUIRED" not in flight:
        fail("ios-testflight.yml archive does not require staged Field Packs")
    if "probe_fieldpacks_app.sh" not in flight:
        fail("ios-testflight.yml does not probe FieldPacks inside the xcarchive")
    for _id, filename, size, digest in STATEWIDE_PACKS:
        if filename not in fetch or digest not in fetch or size not in fetch:
            fail(f"fetch script missing {_id} {filename} {size} {digest}")
        if digest not in catalog:
            fail(f"catalog missing sha256 for {_id}")
        if f'id: "{_id}"' not in catalog:
            fail(f"catalog missing pack id {_id}")
        if _id not in copy or _id not in probe:
            fail(f"copy/probe missing {_id}")
    for city in ("el-paso.pack.zip", "las-cruces.pack.zip", "albuquerque.pack.zip"):
        if city in fetch:
            fail(f"fetch script must not download city pack {city}")
    if "isBundled: true" not in catalog or "bundledStatewide" not in catalog:
        fail("catalog lost bundledStatewide Ready flags")
    if "bundledPacksRoot" not in store or "httpSession" not in store:
        fail("PackStore must resolve bundled statewide without boot URLSession")
    if "let session: URLSession" in store:
        fail("PackStore still constructs URLSession on init")
    if "URLSession" in maps or "URLSession" in sos or "URLSession" in guide:
        fail("Map/SOS/Guide must not use URLSession")
    if "*.pack.zip" not in gitignore or "BundledFieldPacks/" not in gitignore:
        fail(".gitignore must exclude pack zips and BundledFieldPacks")
    if "routing/graph.bin" not in gitignore:
        fail(".gitignore must exclude routing binaries")
    if pbx.count("CURRENT_PROJECT_VERSION = 19") < 2:
        fail("CURRENT_PROJECT_VERSION was bumped off 19")
    ok("archive fetches FL/TX/NY/NM; compile does not; catalog is bundled Ready")


def test_copy_fieldpacks_compile_noop_and_archive_required() -> None:
    import tempfile

    copy = ROOT / "tools/copy_fieldpacks.sh"
    probe = ROOT / "tools/probe_fieldpacks_app.sh"
    with tempfile.TemporaryDirectory() as tmp:
        srcroot = Path(tmp) / "src"
        built = Path(tmp) / "built"
        resources = built / "Blackout.app"
        srcroot.mkdir()
        resources.mkdir(parents=True)
        env = {
            **os.environ,
            "SRCROOT": str(srcroot),
            "BUILT_PRODUCTS_DIR": str(built),
            "UNLOCALIZED_RESOURCES_FOLDER_PATH": "Blackout.app",
        }
        subprocess.check_call(["bash", str(copy)], env=env)
        if (resources / "FieldPacks").exists():
            fail("unsigned compile copied FieldPacks without staging")

        env["FIELD_PACKS_REQUIRED"] = "1"
        missing = subprocess.run(["bash", str(copy)], env=env, capture_output=True, text=True)
        if missing.returncode == 0:
            fail("archive copy must fail when staging is missing")

        staging = srcroot / "BundledFieldPacks"
        for pack_id in ("us-tx", "us-nm", "us-fl", "us-ny"):
            tiles = staging / pack_id / "tiles" / "8" / "1"
            tiles.mkdir(parents=True)
            manifest = {
                "id": pack_id,
                "tileCount": 1,
            }
            if pack_id == "us-tx":
                manifest["routing"] = "routing/routing.json"
                manifest["attribution"] = "© OpenStreetMap contributors"
                routing = staging / pack_id / "routing"
                routing.mkdir()
                (routing / "routing.json").write_text(
                    '{"format":"blackout-routing-v1","profiles":["walk","drive"]}',
                    encoding="utf-8",
                )
                (routing / "graph.bin").write_bytes(b"BLRG0001")
                (routing / "names.bin").write_bytes(b"BLNM0001")
                (routing / "geometry.bin").write_bytes(b"BLGM0001")
            (staging / pack_id / "manifest.json").write_text(
                json.dumps(manifest), encoding="utf-8"
            )
            (tiles / "1.png").write_bytes(b"\x89PNG")
        copied = subprocess.run(
            ["bash", str(copy)], env=env, capture_output=True, text=True, check=True
        )
        app = resources
        subprocess.check_call(["bash", str(probe), str(app)])
        if (app / "FieldPacks" / "tiles").exists():
            fail("copy flattened four states into FieldPacks/tiles")
        if (app / "FieldPacks" / "el-paso").exists():
            fail("copy staged a city pack")
        tx_routing = app / "FieldPacks" / "us-tx" / "routing"
        if not (tx_routing / "graph.bin").is_file() or not (tx_routing / "routing.json").is_file():
            fail("archive ditto dropped us-tx routing/")
        man = json.loads((app / "FieldPacks" / "us-tx" / "manifest.json").read_text())
        if man.get("routing") != "routing/routing.json":
            fail("copied us-tx manifest lost routing key")
        if man.get("attribution") != "© OpenStreetMap contributors":
            fail("copied us-tx manifest lost ODbL attribution")
        if (app / "FieldPacks" / "us-fl" / "routing").exists():
            fail("copy invented routing/ on a pack that had none")
        if "routing/" not in copied.stdout:
            fail("copy did not report routing/ when present")
        if "BLRG0001" not in probe.read_text():
            fail("probe_fieldpacks_app.sh does not check routing magic when present")

        (staging / "us-tx" / "routing" / "graph.bin").write_bytes(b"XXXX0001")
        bad = subprocess.run(["bash", str(copy)], env=env, capture_output=True, text=True)
        if bad.returncode == 0:
            fail("copy must fail when routing/ magic mismatches")
    ok("copy no-ops on compile and requires four separate statewide folders on archive")


def test_fieldpack_root_flatten_fixture() -> None:
    import tempfile
    import zipfile

    script = ROOT / "tools/fetch_bundled_field_packs.sh"
    with tempfile.TemporaryDirectory() as tmp:
        wrapped = Path(tmp) / "wrap"
        inner = wrapped / "us-fl"
        tiles = inner / "tiles" / "8" / "1"
        tiles.mkdir(parents=True)
        (inner / "manifest.json").write_text(
            '{"id":"us-tx","routing":"routing/routing.json","attribution":"© OpenStreetMap contributors"}',
            encoding="utf-8",
        )
        (tiles / "1.png").write_bytes(b"\x89PNG")
        routing = inner / "routing"
        routing.mkdir()
        (routing / "routing.json").write_text("{}", encoding="utf-8")
        (routing / "graph.bin").write_bytes(b"BLRG0001")
        (routing / "names.bin").write_bytes(b"BLNM0001")
        (routing / "geometry.bin").write_bytes(b"BLGM0001")
        zip_path = Path(tmp) / "texas-wrap.zip"
        with zipfile.ZipFile(zip_path, "w") as zf:
            for path in inner.rglob("*"):
                if path.is_file():
                    zf.write(path, path.relative_to(wrapped).as_posix())
        dest = Path(tmp) / "us-tx"
        staged = subprocess.run(
            ["bash", str(script), "--stage-zip", str(zip_path), str(dest)],
            capture_output=True,
            text=True,
            check=True,
        )
        if not (dest / "manifest.json").is_file():
            fail("ROOT-flatten did not promote manifest.json")
        if not (dest / "tiles" / "8" / "1" / "1.png").is_file():
            fail("ROOT-flatten did not promote tiles/")
        if (dest / "us-fl" / "manifest.json").exists() or (dest / "us-tx" / "manifest.json").exists():
            fail("ROOT-flatten left a nested wrapper")
        if not (dest / "routing" / "graph.bin").is_file():
            fail("ROOT-flatten dropped routing/graph.bin")
        man = json.loads((dest / "manifest.json").read_text())
        if man.get("attribution") != "© OpenStreetMap contributors":
            fail("ROOT-flatten dropped pack-manifest ODbL attribution")
        if "routing/" not in staged.stdout:
            fail("ROOT-flatten did not report staged routing/")
    ok("ROOT-flatten promotes a wrapped pack zip")


def test_party_vitals_red_loop() -> None:
    core = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/PartyVitals.swift").read_text()
    kind = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/PayloadKind.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    chip = (ROOT / "Packages/Maps/Sources/Maps/VitalsChip.swift").read_text()
    radar = (ROOT / "Packages/Maps/Sources/Maps/RadarHUDView.swift").read_text()
    sos = (ROOT / "Packages/SOS/Sources/SOS/SOSFab.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    app = (ROOT / "Blackout/AppContainer.swift").read_text()
    mesh = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MeshFacade.swift").read_text()
    pause = (ROOT / "Packages/Expeditions/Sources/Expeditions/ExpeditionsRootView.swift").read_text()
    plate = (ROOT / "Packages/Expeditions/Sources/Expeditions/PartyVitalsPlate.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    if "case partyStatus" not in kind:
        fail("PayloadKind missing partyStatus")
    ds = (ROOT / "Packages/DesignSystem/Sources/DesignSystem/BlackoutDS.swift").read_text()
    if "injury = true" not in core or "return .red" not in core:
        fail("I AM NOT OK must set injury and red")
    if "case .rested" not in core or "case .dizzy" not in core:
        fail("RESTED / DIZZY missing from vitals math")
    if "RESTED" in chip or "DIZZY" in chip or "RESTED" in maps or "DIZZY" in maps:
        fail("RESTED / DIZZY must stay in vitals math — no extra Map chips")
    if "RESTED" in plate or "DIZZY" in plate:
        fail("RESTED / DIZZY must not grow roster chips")
    if "redFiresSOS = false" not in core:
        fail("going red must stay not-an-SOS-fire")
    if "sosConfirmRequested" in maps or "sosAlert" in maps or "kind: .sosAlert" in core:
        fail("going red must not fire SOS")
    if "import HealthKit" in core or "import HealthKit" in plate or "import HealthKit" in chip or "import HealthKit" in maps or "import HealthKit" in root:
        fail("manual vitals must not import HealthKit")
    if "tel:911" in core or "tel:911" in plate or "tel:911" in app:
        fail("party red must not auto-dial 911")
    if "VitalsChip" not in maps or "vitalsRow" not in maps:
        fail("Map lost the bottom-leading §10.4 vitals chip")
    if "BlackoutDS.Hit.sos + BlackoutDS.Vitals.sosGap" not in maps:
        fail("vitals chip must stay 8pt clear of the 88pt SOS disk")
    if "padding(.bottom, BlackoutDS.Vitals.sosGap)" not in maps:
        fail("vitals chip must sit in the SOS band, not stacked above 120pt clearance")
    if "sosClearance + BlackoutDS.Vitals.sosGap" in maps:
        fail("vitals chip must not sit above the old 120pt SOS stack")
    if "BlackoutDS.Vitals.chip" not in chip:
        fail("I AM NOT chip is not 56h")
    if "BlackoutDS.Btn.metal" not in chip or "Btn.primary" in chip:
        fail("vitals chip must be Btn.metal, not Btn.primary")
    if "clipShape(Circle" in chip or "clipShape(Capsule" in chip:
        fail("vitals chip must not be a disk")
    if "SOSFab" in chip or "sosAlert" in chip or "sosConfirm" in chip:
        fail("vitals chip must not present or arm SOS")
    if "BlackoutDS.Vitals.pip" not in chip or "BlackoutDS.Semantic.warn" not in chip:
        fail("I AM NOT must use 6pt red.core pip + warn label on metal")
    if "§10.4" not in ds or "public static let pip: CGFloat = 6" not in ds:
        fail("DS §10.4 vitals metrics missing")
    if "Color(red: 1, green: 43 / 255, blue: 43 / 255)" not in ds:
        fail("Red.core hex changed")
    if "BlackoutDS.Hit.sos" not in sos:
        fail("SOS FAB lost 88pt hit")
    if "PartyVitalsPlate" not in pause:
        fail("Expedition roster lost two-tap vitals")
    if "DRANK" not in plate or "ATE" not in plate or "I AM NOT OK" not in plate:
        fail("roster missing DRANK / ATE / I AM NOT OK")
    comms = (ROOT / "Blackout/CommsRootView.swift").read_text()
    if "selfLabel.footnote" not in plate or "Silver.dim" not in plate:
        fail("roster lost YOU last-4 silver.dim footnote")
    if "blip.footnote" not in radar or "Silver.dim" not in radar:
        fail("Radar lost YOU last-4 silver.dim footnote")
    if "shown.footnote" not in comms or "Silver.dim" not in comms:
        fail("Comms lost live YOU last-4 silver.dim footnote")
    if "footnote" in sos:
        fail("YOU last-4 must not appear on SOS")
    if "Btn.metal" not in plate or "Vitals.chip" not in plate:
        fail("roster buttons must be Btn.metal 56")
    if "drankLatched" not in plate or "ateLatched" not in plate:
        fail("DRANK / ATE must keep independent ok pips")
    if "BlackoutDS.Red.core" in plate and ".background(BlackoutDS.Red.core)" in plate:
        fail("I AM NOT OK roster button must stay metal, not primary")
    if "Navigate-to" not in radar and 'PartyVitalsCopy.navigateTo' not in radar:
        fail("peer sheet missing Navigate-to")
    if "PartyVitalsCopy.message" not in radar:
        fail("tap pip must offer Message")
    if 'MetalButton("PTT"' in radar:
        fail("peer sheet must stay Message + Navigate-to")
    if "enum AppDestination" in root and root.count("case ") < 4:
        fail("4-tab chrome missing cases")
    if "becameRed" not in app:
        fail("AppContainer does not haptic on peer red")
    if "envelope.kind" in mesh:
        fail("MeshFacade must stay a dumb pipe")
    if "case expedition" not in root or "case field" not in root:
        fail("4-tab chrome missing")
    if root.count("tabItem") != 4:
        fail("do not add a fifth tab")
    if pbx.count("CURRENT_PROJECT_VERSION = 19") < 2:
        fail("CURRENT_PROJECT_VERSION was bumped off 19")
    ok("party vitals two-tap + red packet, SOS 88, chip 56, no 911")


def test_sos_confirm_panel() -> None:
    sos = (ROOT / "Packages/SOS/Sources/SOS/SOSFab.swift").read_text()
    support = (ROOT / "Packages/SOS/Sources/SOS/SOSConfirmSupport.swift").read_text()
    core = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/SOSConfirm.swift").read_text()
    root = (ROOT / "Blackout/RootView.swift").read_text()
    vitals = (ROOT / "Packages/DesignSystem/Sources/DesignSystem/BlackoutDS.swift").read_text()
    chrome = (ROOT / "Packages/Maps/Sources/MapsChrome/MapChromeRecede.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    if "SPEAK SOS" not in core or 'speakLocation = "SPEAK LOCATION"' not in core:
        fail("confirm panel missing SPEAK SOS / SPEAK LOCATION")
    if "SPEAK MY LOCATION" in core:
        fail("confirm label is SPEAK LOCATION, not SPEAK MY LOCATION")
    if 'sharePosition = "SHARE"' not in core or 'copyCoords = "COPY"' not in core:
        fail("confirm panel missing SHARE / COPY")
    if "SHARE POSITION" in core or "COPY COORDS" in core:
        fail("confirm labels are SHARE and COPY")
    if "CALL 911" not in core or 'visualStrobe = "STROBE"' not in core:
        fail("confirm panel missing CALL 911 / STROBE")
    if "VISUAL SOS STROBE" in core:
        fail("confirm label is STROBE")
    if '"BLACKOUT \\(coordsLine(fix))"' not in core and "BLACKOUT \\(coordsLine" not in core:
        fail("SHARE message must be BLACKOUT {coords}")
    if "BLACKOUT" not in core:
        fail("SHARE must start with BLACKOUT")
    if "tel:911" not in core or "autoDials911 = false" not in core:
        fail("CALL 911 must be tel:911 and must not auto-dial")
    if "strobePeriodMs = 330" not in core or "reduceMotionOpacity = 0.55" not in core:
        fail("visual strobe must be 330ms pulse / Reduce Motion 0.55")
    if "SOSConfirmActionList" not in sos or "SOSStrobeWash" not in sos:
        fail("confirm cover lost the six actions or visual strobe")
    if "Button(action: {})" not in sos:
        fail("SOS tap must never fire")
    if "SOSChrome.holdSeconds" not in sos:
        fail("hold 1.5s must present the unarmed cover")
    if "SlideToConfirm" not in sos:
        fail("slide still commits")
    if "Emergency SOS (system)" not in sos:
        fail("OS Emergency SOS must stay an explicit extra control")
    if "onAppear { showSystemSOS" in sos or ".onAppear { showSystemSOS = true" in sos:
        fail("must not auto-invoke OS Emergency SOS")
    if "openTel911" not in support or "signalDistress" not in support:
        fail("CALL / strobe must open tel:911 and send mesh sos")
    if "markInjured" not in support:
        fail("strobe / CALL must set local injury/red")
    if "Vitals.sosGap" not in root or "Vitals.tabBar" not in root:
        fail("SOS FAB must inset tabBar+8")
    if ".padding(.trailing, 16)" not in root:
        fail("SOS FAB must use 16pt trailing inset")
    if ".padding(.trailing, 18)" in root:
        fail("SOS trailing drifted off 16pt")
    maps_root = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    if ".padding(.trailing, 16)" not in maps_root:
        fail("vitals chip must share the 16pt trailing inset so the ≥8pt gap is real")
    if ".padding(.trailing, 18)" in maps_root:
        fail("vitals chip trailing drifted off 16pt")
    if "return 16 + tab + home" in root:
        fail("SOS FAB still uses the old 16pt-above-tab inset")
    if "sosClearance: CGFloat = 120" in vitals:
        fail("SOS clearance must be the 88pt disk band, not 120 stacked")
    if "sosClearance: CGFloat = 88" not in vitals or "sosGap: CGFloat = 8" not in vitals:
        fail("DS SOS tokens drifted")
    if "SOS FAB is not part of this flag" not in chrome:
        fail("Map recede must not include the SOS FAB")
    if root.count("tabItem") != 4:
        fail("do not make SOS a tab")
    if "sosOverlay" not in root or root.count("SOSFab") != 1:
        fail("SOS must be one RootView overlay on all four tabs")
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    comms = (ROOT / "Blackout/CommsRootView.swift").read_text()
    field = (ROOT / "Packages/Field/Sources/Field/FieldRootView.swift").read_text()
    expedition = (ROOT / "Packages/Expeditions/Sources/Expeditions/ExpeditionsRootView.swift").read_text()
    if "SOSFab" in maps or "SOSFab" in comms or "SOSFab" in field or "SOSFab" in expedition:
        fail("SOS must not be a per-tab or nav-bar control")
    if "isReceded && !reduceMotion" not in maps:
        fail("I AM OK chip must stay when Reduce Motion is on")
    if "CriticalSOSShell" not in root or "SOSFab" not in root:
        fail("last-2% must still show the 88pt SOS FAB")
    if "push:" in tf or "pull_request:" in tf:
        fail("do not dispatch TestFlight")
    if pbx.count("CURRENT_PROJECT_VERSION = 19") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    ok("SOS is bottom-trailing tabBar+8, confirm has six actions, no auto-911")


def test_locked_app_icon() -> None:
    import struct

    emblem = ROOT / "brand" / "emblem.jpeg"
    wordmark = ROOT / "brand" / "wordmark.jpeg"
    lockup = ROOT / "brand" / "lockup.jpeg"
    icon = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    catalog = (ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json").read_text()
    wordset = ROOT / "Blackout" / "Assets.xcassets" / "Wordmark.imageset"
    gen = (ROOT / "tools" / "generate_project.py").read_text()
    if not emblem.is_file() or emblem.stat().st_size < 100_000:
        fail("brand/emblem.jpeg missing or too small")
    if not wordmark.is_file() or not lockup.is_file():
        fail("brand wordmark/lockup missing")
    if not icon.is_file():
        fail("AppIcon.png missing")
    if icon.stat().st_size < 50_000:
        fail("AppIcon.png is still the synthetic red disc")
    raw = icon.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        fail("AppIcon.png is not a PNG")
    ln = struct.unpack(">I", raw[8:12])[0]
    tag = raw[12:16]
    data = raw[16 : 16 + ln]
    if tag != b"IHDR":
        fail("AppIcon.png missing IHDR")
    w, h, bit, ct = struct.unpack(">IIBB", data[:10])
    if (w, h) != (1024, 1024):
        fail(f"AppIcon.png is {w}x{h}, need 1024x1024")
    if ct != 2:
        fail(f"AppIcon.png color type {ct} is not opaque RGB (no alpha)")
    if "AppIcon.png" not in catalog or "1024x1024" not in catalog:
        fail("AppIcon Contents.json does not point at the single 1024")
    if not (wordset / "Wordmark.jpeg").is_file() and not (wordset / "Wordmark.png").is_file():
        fail("Wordmark is not in the asset catalog")
    if "Image(" in gen and "lockup" in gen:
        fail("lockup must not be wired into the app icon")
    if "CURRENT_PROJECT_VERSION" in (ROOT / "Blackout.xcodeproj" / "project.pbxproj").read_text():
        pbx = (ROOT / "Blackout.xcodeproj" / "project.pbxproj").read_text()
        if pbx.count("CURRENT_PROJECT_VERSION = 19") < 2:
            fail("version was bumped off 19 while landing the emblem")
    ok("AppIcon is the locked emblem PNG; wordmark is catalog-only")


def test_compass_lock_on() -> None:
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    session = (ROOT / "Packages/Maps/Sources/Maps/CompassLockSession.swift").read_text()
    chrome = (ROOT / "Packages/Maps/Sources/Maps/CompassLockChrome.swift").read_text()
    math = (ROOT / "Packages/Maps/Sources/MapsRouting/CompassLock.swift").read_text()
    speech = (ROOT / "Packages/Maps/Sources/Maps/OnDeviceSpeech.swift").read_text()
    tests = (ROOT / "Packages/Maps/Tests/MapsTests/CompassLockTests.swift").read_text()
    sos = (ROOT / "Packages/SOS/Sources/SOS/SOSFab.swift").read_text()
    vitals = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    catalog = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalog.swift").read_text()
    for path in (maps, session, chrome, math):
        if "MKDirections" in path or "URLSession" in path:
            fail("compass lock path must stay airplane: no MKDirections / URLSession")
    if "CompassLockBar" not in maps or "CompassLockSession" not in maps:
        fail("Map lost compass lock chrome")
    for label in ('SPEAK', 'STEER', 'MARK', 'LOCK'):
        if f'"{label}"' not in math:
            fail(f"compass lock lost button {label}")
    if "Nothing to lock. MARK a point or wait for a peer." not in math:
        fail("compass lock lost empty copy")
    if "Hold course" not in math or "Right " not in math or "Left " not in math:
        fail("compass lock lost turnPhrase")
    if "relBearing" not in math or "540" not in math:
        fail("compass lock lost relBearing formula")
    if "voiceInterval: TimeInterval = 2.2" not in math:
        fail("voice lock must stay 2.2s")
    if "speechRateMin: Float = 0.47" not in math or "speechRateMax: Float = 0.52" not in math:
        fail("voice lock rate must stay 0.47–0.52")
    if "id: \"th\"" not in math or "31.8924" not in math or "-106.4401" not in math:
        fail("standards list lost th Trailhead")
    if "id: \"wc\"" not in math or "Water cache" not in math:
        fail("standards list lost wc Water cache")
    if "startLoopIfNeeded" not in session or "guard voiceTask == nil" not in session:
        fail("2.2s timer must not restart on every render")
    if "AVSpeechSynthesizer" not in speech:
        fail("lock voice must stay on-device AVSpeechSynthesizer")
    if "NavigateSession" not in maps or "routing" not in maps:
        fail("street TBT must stay default when routing/ exists")
    if "fieldHeadingUp" not in maps or "-(location.headingDegrees" not in maps:
        fail("rose must rotate by -heading while heading-up")
    if "SAVE CURRENT" not in math or "LOCKED" not in math or "DELETE" not in math:
        fail("MARK sheet lost SAVE CURRENT / STEER / LOCKED / DELETE")
    if "BlackoutDS.Hit.sos" not in sos:
        fail("SOS 88 must never recede")
    if "vitalsRow" not in vitals or "RecedingMapChrome" not in vitals:
        fail("I AM OK must still recede with HUD")
    if "FieldPacksView" in (ROOT / "Blackout/RootView.swift").read_text():
        fail("do not restore the first-open Field Packs sheet")
    if (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPacksView.swift").exists():
        fail("do not restore FieldPacksView")
    if "6ff6c9a191fe5df8d3bf48abb360ad361990bc672c1c59bd0cf2e3a3d5d55ade" not in catalog:
        fail("texas.pack.zip pin drifted")
    if "220_512_882" not in catalog:
        fail("texas.pack.zip byte pin drifted")
    if "tabItem" in (ROOT / "Blackout/RootView.swift").read_text() and (
        ROOT / "Blackout/RootView.swift"
    ).read_text().count("tabItem") != 4:
        fail("do not restore 6 tabs")
    if "func coveringRoot" not in (ROOT / "Packages/Maps/Sources/MapsRouting/RoutingPack.swift").read_text():
        fail("do not revert Feature 1 routing loader")
    if "routing/graph.bin" not in (ROOT / ".gitignore").read_text():
        fail("do not put graph bins in git")
    if pbx.count("CURRENT_PROJECT_VERSION = 19") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    if "push:" in (ROOT / ".github/workflows/ios-testflight.yml").read_text():
        fail("do not dispatch TestFlight")
    if "31.8924" not in tests or "Hold course" not in tests:
        fail("compass lock tests lost the standards / turnPhrase locks")
    ok("compass lock is SPEAK/STEER/MARK/LOCK, 2.2s voice, one standards list")


def test_pack_find_civ_water() -> None:
    find = ROOT / "Packages/Maps/Sources/MapsRouting/PackFind.swift"
    tests = (ROOT / "Packages/Maps/Tests/MapsTests/PackFindTests.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    tools = (ROOT / "Packages/Maps/Sources/Maps/MapTools.swift").read_text()
    session = (ROOT / "Packages/Maps/Sources/Maps/NavigateSession.swift").read_text()
    lock = (ROOT / "Packages/Maps/Sources/MapsRouting/CompassLock.swift").read_text()
    poi = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/MapPack.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    tf = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    if not find.is_file():
        fail("PackFind.swift missing — Find civ/water must score pack POIs")
    src = find.read_text()
    for banned in ("MKLocalSearch", "MKMapView", "URLSession", "MKDirections"):
        if banned in src or banned in maps or banned in tools or banned in session:
            fail(f"Find civ/water must stay airplane: no {banned}")
    for kind in ('"road"', '"rail"', '"town"', '"mill"', '"spring"', '"tank"', '"water"'):
        if kind not in src:
            fail(f"PackFind lost pack kind {kind}")
    layout = (ROOT / "Packages/Maps/Sources/MapsRouting/RoutingLayout.swift").read_text()
    for copy in (
        "No pack for this area",
        "No turns for this area",
        "No civilization in this pack",
        "No water mapped here",
    ):
        if f'"{copy}"' not in layout:
            fail(f"Map empty lost locked copy: {copy}")
    if 'eyebrow = "MAP"' not in layout:
        fail("Map empty lost eyebrow MAP")
    if "No civilization in this pack" not in tests or "No water mapped here" not in tests:
        fail("Find civ/water tests lost the honest empty")
    if "NeverInvent" not in tests and "neverInvent" not in tests:
        fail("Find civ/water tests must refuse invented cities")
    if ".shadow(" in maps:
        fail("Map empty / chrome must not drop-shadow in sun mode")
    if "Skip" in (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text() and 'GhostButton("Skip"' in maps:
        fail("Map empty must not grow a Skip control")
    if "PackFindCopy.civilization" not in maps or "PackFindCopy.water" not in maps:
        fail("Layers lost Find civilization / Find water")
    if 'GhostButton("Towns"' in maps:
        fail("Towns must become Find civilization + Find water")
    if "pickFound" not in maps or "PackFind.action" not in maps:
        fail("tapping a pack POI must STEER / Feature 1 route or lock-on")
    if "navigate.empty != nil" not in maps:
        fail("Find empty cards must hold chrome")
    if "compass.end()" not in maps or "case .route:" not in maps:
        fail("Feature 1 route from a pack POI must end compass lock")
    if "case .poi" not in lock:
        fail("compass lock-on from a pack POI needs kind .poi")
    if "func findPack" not in session:
        fail("NavigateSession must find from pack POIs, not a geocoder")
    if "isWater" not in poi:
        fail("MapPOI lost isWater")
    if "logo" in maps.lower() and "watermark" in maps.lower():
        fail("do not put a logo on Map")
    if pbx.count("CURRENT_PROJECT_VERSION = 19") < 2:
        fail("do not bump CURRENT_PROJECT_VERSION")
    if "push:" in tf or "pull_request:" in tf:
        fail("do not dispatch TestFlight")
    if (ROOT / "Blackout/RootView.swift").read_text().count("tabItem") != 4:
        fail("do not restore 6 tabs")
    if "BlackoutDS.Hit.sos" not in (ROOT / "Packages/SOS/Sources/SOS/SOSFab.swift").read_text():
        fail("do not move SOS")
    ok("Map Find civilization / Find water scores pack POIs only")


def main() -> None:
    test_compile_workflow_drops_feature_branch_push()
    test_testflight_paths_and_assign()
    test_pbx_single_copy()
    test_generator_does_not_restore_double_copy()
    test_assign_script_requires_secrets()
    test_assign_pick_prefers_fresh_then_fallback()
    test_assign_existing_workflow()
    test_prune_script_requires_secrets()
    test_map_chrome_lock()
    test_map_pack_resolver()
    test_usgs_defaultpack()
    test_live_mesh_1n()
    test_pack_relay_1n()
    test_party_vitals_red_loop()
    test_sos_confirm_panel()
    test_locked_app_icon()
    test_bundled_statewide_archive_only()
    test_copy_fieldpacks_compile_noop_and_archive_required()
    test_fieldpack_root_flatten_fixture()
    test_compass_lock_on()
    test_pack_find_civ_water()
    test_hits_23()
    print("all ci-opt checks passed")


def test_hits_23() -> None:
    pbx = (ROOT / "Blackout.xcodeproj/project.pbxproj").read_text()
    core = (ROOT / "Packages/BlackoutCore/Sources/BlackoutCore/ConvenienceHits.swift").read_text()
    tests = (ROOT / "Packages/BlackoutCore/Tests/BlackoutCoreTests/ConvenienceHitsTests.swift").read_text()
    maps = (ROOT / "Packages/Maps/Sources/Maps/MapsRootView.swift").read_text()
    torch = (ROOT / "Packages/Maps/Sources/Maps/MapTorch.swift").read_text()
    nfc = (ROOT / "Packages/Expeditions/Sources/Expeditions/PartyNFCViews.swift").read_text()
    plate = (ROOT / "Packages/Expeditions/Sources/Expeditions/PartyVitalsPlate.swift").read_text()
    shell = (ROOT / "Blackout/RootView.swift").read_text()
    intents = (ROOT / "Blackout/PTTIntents.swift").read_text()
    widget = (ROOT / "Supporting/BlackoutWidgets-Info.plist").read_text()
    info = (ROOT / "Supporting/Blackout-Info.plist").read_text()
    if "NFCReaderUsageDescription" not in pbx or "NFCReaderUsageDescription" not in info:
        fail("NFC usage string missing")
    if "Hold to share" not in core or "Tap to join" not in core:
        fail("NFC roster copy missing")
    if "PartyNFC.tapToJoin" not in plate or "PartyNFC.holdToShare" not in plate:
        fail("NFC roster controls missing")
    if "showsControls(readingAvailable: false)" not in tests:
        fail("NFC missing-hardware hide test missing")
    if "webview" in nfc.lower() or "WKWebView" in nfc:
        fail("NFC must not use a webview")
    if "if let (text, _)" in nfc:
        fail("wellKnownTypeTextPayload returns (String?, Locale?), not Optional")
    if "emitsSOS = false" not in core:
        fail("Map torch policy must not emit SOS")
    if "testFlashlightDoesNotEmitSOS" not in tests:
        fail("flashlight SOS test missing")
    if "ConvenienceCopy.flashlight" not in maps or "BlackoutDS.Hit.md" not in maps:
        fail("Map flashlight 64 metal tool missing")
    if "torchMode" not in torch or "sosAlert" in torch:
        fail("Map torch must set AVCaptureDevice.torch and not emit sos")
    if "MapTorch" in shell.split("CriticalSOSShell", 1)[-1] or "flashlight" in shell.split("CriticalSOSShell", 1)[-1].lower():
        fail("do not add torch to CriticalSOSShell")
    if "Start PTT" not in intents or "Stop PTT" not in intents:
        fail("PTT App Intents missing")
    if "testPTTAppIntentRefusesZeroPeers" not in tests:
        fail("PTT App Intent zero-peer test missing")
    if "GENERATE_INFOPLIST_FILE = NO" not in pbx:
        fail("widget GENERATE_INFOPLIST_FILE must stay NO")
    if "$(PRODUCT_BUNDLE_IDENTIFIER)" not in widget:
        fail("widget CFBundleIdentifier must stay PRODUCT_BUNDLE_IDENTIFIER")
    if pbx.count("PRODUCT_BUNDLE_IDENTIFIER = com.crisiskhan.blackout.widget") < 2:
        fail("widget bundle id drifted")
    if pbx.count("CURRENT_PROJECT_VERSION = 19") < 2:
        fail("version bumped off 19")
    ok("hits 23: NFC + Map torch + PTT intent, widget id locked, version 19")


if __name__ == "__main__":
    main()
