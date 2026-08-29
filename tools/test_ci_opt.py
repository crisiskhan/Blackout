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
    if "python3 -m pip install" in text:
        fail("ios-testflight.yml still pip-installs into system Python")
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
    if "CURRENT_PROJECT_VERSION = 18" not in pbx:
        fail("CURRENT_PROJECT_VERSION is no longer 18")
    if pbx.count("CURRENT_PROJECT_VERSION = 18") < 2:
        fail("expected CURRENT_PROJECT_VERSION = 18 on Debug and Release")
    if "MARKETING_VERSION = 0.1.0" not in pbx:
        fail("MARKETING_VERSION is no longer 0.1.0")
    ok("pbxproj is ditto-only, version 18, no alwaysOutOfDate")


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
    if '"CURRENT_PROJECT_VERSION": "18",' not in src:
        fail("generate_project.py would bump CURRENT_PROJECT_VERSION")
    if "generated-sample" in src:
        fail("generate_project.py would restore synthetic DefaultPack stubs")
    ok("generate_project.py regen stays ditto-only at version 18")


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
    if "fieldPacksSheetBinding" not in root or "FieldPacksView" not in root:
        fail("Field Packs sheet missing from RootView")
    if "Heading-up" in radar or "Sweep audio" in radar or "0 peers · self only" in radar:
        fail("RadarHUDView still floats heading/audio/peer chrome")
    if "MKMapView(" in maps:
        fail("MapsRootView must not construct MKMapView")
    if "URLSession" in maps:
        fail("MapsRootView must not use URLSession")
    ok("Map chrome is HUD + Recenter/Layers/Packs, Field Packs sheet")


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
    ok("asc_assign_internal.sh fails closed without secrets")


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
    if "private var peers: [RadarBlip] { [] }" not in maps:
        fail("Radar peers path changed — do not invent a social layer")
    for src, label in ((pbx, "pbxproj"), (gen, "generate_project.py")):
        if "NSLocalNetworkUsageDescription" not in src:
            fail(f"{label} missing Local Network usage string")
        if "NSBonjourServices" not in src or "blckout-mesh" not in src:
            fail(f"{label} missing Bonjour mesh service")
    if "CURRENT_PROJECT_VERSION = 18" not in pbx:
        fail("version was bumped")
    if "MARKETING_VERSION = 0.1.0" not in pbx:
        fail("MARKETING_VERSION changed")
    ok("live mesh 1/N is Multipeer, no WAN, radar still empty, version 18")


def test_pack_relay_1n() -> None:
    pipe = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MultipeerPipe.swift").read_text()
    facade = (ROOT / "Packages/Mesh/Sources/BlackoutMesh/MeshFacade.swift").read_text()
    store = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackStore.swift").read_text()
    zip_src = (ROOT / "Packages/Packs/Sources/BlackoutPacks/PackZip.swift").read_text()
    catalog = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPackCatalog.swift").read_text()
    sheet = (ROOT / "Packages/Packs/Sources/BlackoutPacks/FieldPacksView.swift").read_text()
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
    if "Send to nearby phone" not in sheet:
        fail("Field Packs sheet missing Send to nearby phone")
    if "import BlackoutMesh" in packs_pkg or "import BlackoutMesh" in store:
        fail("Packs must not import Mesh")
    if "relayPack" not in app or "installRelayedZip" not in app:
        fail("AppContainer does not glue pack relay")
    if "session.download" in store.split("installRelayedZip")[-1][:2000]:
        fail("installRelayedZip must not download")
    if "CURRENT_PROJECT_VERSION = 18" not in pbx:
        fail("version was bumped")
    if "MARKETING_VERSION = 0.1.0" not in pbx:
        fail("MARKETING_VERSION changed")
    ok("city pack relay uses sendResource, Packs owns zip/hash, version 18")


def main() -> None:
    test_compile_workflow_drops_feature_branch_push()
    test_testflight_paths_and_assign()
    test_pbx_single_copy()
    test_generator_does_not_restore_double_copy()
    test_assign_script_requires_secrets()
    test_map_chrome_lock()
    test_map_pack_resolver()
    test_usgs_defaultpack()
    test_live_mesh_1n()
    test_pack_relay_1n()
    print("all ci-opt checks passed")


if __name__ == "__main__":
    main()
