#!/usr/bin/env python3
"""Linux-side contract tests for bible v3. Not an Xcode archive."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from v3.generate_project import assert_openstep_plist

fail = 0


def ok(msg: str) -> None:
    print("OK  ", msg)


def bad(msg: str) -> None:
    global fail
    fail = 1
    print("FAIL", msg)


def modules() -> None:
    required = {
        "App": ROOT / "Blackout" / "BlackoutApp.swift",
        "Tokens": ROOT / "Packages" / "Tokens" / "Sources" / "Tokens" / "Tokens.swift",
        "PackIO": ROOT / "Packages" / "PackIO" / "Sources" / "PackIO" / "PackIO.swift",
        "MapLibreMap": ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift",
        "Search": ROOT / "Packages" / "Search" / "Sources" / "Search" / "Search.swift",
        "Router": ROOT / "Packages" / "Router" / "Sources" / "Router" / "Router.swift",
        "DeadReckoning": ROOT / "Packages" / "DeadReckoning" / "Sources" / "DeadReckoning" / "DeadReckoning.swift",
        "MeshDTN": ROOT / "Packages" / "MeshDTN" / "Sources" / "MeshDTN" / "MeshDTN.swift",
        "CryptoParty": ROOT / "Packages" / "CryptoParty" / "Sources" / "CryptoParty" / "CryptoParty.swift",
        "CommsUI": ROOT / "Packages" / "CommsUI" / "Sources" / "CommsUI" / "CommsUI.swift",
        "PTTAudio": ROOT / "Packages" / "PTTAudio" / "Sources" / "PTTAudio" / "PTTAudio.swift",
        "FieldCorpus": ROOT / "Packages" / "FieldCorpus" / "Sources" / "FieldCorpus" / "FieldCorpus.swift",
        "FieldStepper": ROOT / "Packages" / "FieldStepper" / "Sources" / "FieldStepper" / "FieldStepper.swift",
        "FieldSpeech": ROOT / "Packages" / "FieldSpeech" / "Sources" / "FieldSpeech" / "FieldSpeech.swift",
        "VisionCapture": ROOT / "Packages" / "VisionCapture" / "Sources" / "VisionCapture" / "VisionCapture.swift",
        "VisionCoreML": ROOT / "Packages" / "VisionCoreML" / "Sources" / "VisionCoreML" / "VisionCoreML.swift",
        "KitStore": ROOT / "Packages" / "KitStore" / "Sources" / "KitStore" / "KitStore.swift",
        "Vitals": ROOT / "Packages" / "Vitals" / "Sources" / "Vitals" / "Vitals.swift",
        "RedAlert": ROOT / "Packages" / "RedAlert" / "Sources" / "RedAlert" / "RedAlert.swift",
        "TimerSync": ROOT / "Packages" / "TimerSync" / "Sources" / "TimerSync" / "TimerSync.swift",
        "RosterRoles": ROOT / "Packages" / "RosterRoles" / "Sources" / "RosterRoles" / "RosterRoles.swift",
        "TripBrief": ROOT / "Packages" / "TripBrief" / "Sources" / "TripBrief" / "TripBrief.swift",
        "PaperGen": ROOT / "Packages" / "PaperGen" / "Sources" / "PaperGen" / "PaperGen.swift",
        "BlackBox": ROOT / "Packages" / "BlackBox" / "Sources" / "BlackBox" / "BlackBox.swift",
        "Instruments": ROOT / "Packages" / "Instruments" / "Sources" / "Instruments" / "Instruments.swift",
        "WatchApp": ROOT / "BlackoutWatch" / "BlackoutWatchApp.swift",
        "LiveActivity": ROOT / "BlackoutWidgets" / "BlackoutLiveActivity.swift",
        "ActionButton": ROOT / "Blackout" / "ActionButton" / "ActionIntents.swift",
        "RegionalPacks": ROOT / "Packages" / "RegionalPacks" / "Sources" / "RegionalPacks" / "RegionalPacks.swift",
        "Almanac": ROOT / "Packages" / "Almanac" / "Sources" / "Almanac" / "Almanac.swift",
        "NightRed": ROOT / "Packages" / "NightRed" / "Sources" / "NightRed" / "NightRed.swift",
        "BatteryAuction": ROOT / "Packages" / "BatteryAuction" / "Sources" / "BatteryAuction" / "BatteryAuction.swift",
        "OfflineSpeech": ROOT / "Packages" / "OfflineSpeech" / "Sources" / "OfflineSpeech" / "OfflineSpeech.swift",
    }
    for name, path in required.items():
        if path.is_file() and path.stat().st_size > 40:
            ok(f"module {name} {path.relative_to(ROOT)}")
        else:
            bad(f"module {name} missing {path}")


def no_stubs() -> None:
    pat = re.compile(r"coming soon|TODO implement|later stub|not implemented yet", re.I)
    for p in list((ROOT / "Packages").rglob("*.swift")) + list((ROOT / "Blackout").rglob("*.swift")):
        text = p.read_text(errors="ignore")
        if pat.search(text):
            bad(f"stub language {p}")
    ok("no later/coming-soon stub language")


def no_old_engine() -> None:
    hits = []
    for p in (ROOT / "Packages").rglob("*.swift"):
        t = p.read_text(errors="ignore")
        if "MKMapView(" in t or "import MapKit" in t:
            hits.append(p)
        if "URLSession" in t:
            hits.append(p)
    for p in (ROOT / "Blackout").rglob("*.swift"):
        t = p.read_text(errors="ignore")
        if "MKMapView(" in t or "URLSession" in t:
            hits.append(p)
    if hits:
        bad(f"forbidden API {hits}")
    else:
        ok("no MapKit engine / no URLSession in app+packages")


def field_schema() -> None:
    cats = set()
    root = ROOT / "Resources" / "Field"
    core = json.loads((root / "field.core.json").read_text())
    for c in core["cards"]:
        if c.get("schema") != "1.4":
            bad(f"core schema {c['id']}")
            return
        for key in ("situation", "stop_if", "get_to_care", "steps"):
            if key not in c:
                bad(f"core missing {key} {c['id']}")
                return
        for st in c["steps"]:
            for k in ("do", "why", "child", "stop", "image"):
                if k not in st:
                    bad(f"step missing {k} {c['id']}")
                    return
            if not (root / "images" / st["image"]).is_file():
                bad(f"missing image {st['image']}")
                return
        cats.add(c["category"])
    need = {"medical", "trauma", "environment", "water", "fire", "shelter", "nav", "plants", "animals", "fungi", "food", "signaling", "tactics"}
    if not need <= cats:
        bad(f"missing categories {need - cats}")
    else:
        ok(f"field.core {len(core['cards'])} cards categories={sorted(cats)}")
    core_ids = {c["id"] for c in core["cards"]}
    for need_id in ("med-bleed-pack", "trauma-fracture", "env-heat-collapse", "env-cold", "water-disinfect", "nav-lost", "shelter-tarp", "sig-mirror"):
        if need_id not in core_ids:
            bad(f"core missing thickness {need_id}")
        else:
            ok(f"core has {need_id}")
    for st in ("tx", "nm", "fl", "ny"):
        book = json.loads((root / f"field.{st}.json").read_text())
        if not book["cards"]:
            bad(f"empty field.{st}")
        else:
            ok(f"field.{st} {len(book['cards'])} cards")
        ids = {c["id"] for c in book["cards"]}
        if f"{st}-snake" not in ids:
            bad(f"field.{st} missing snake-of-that-state")
        if f"{st}-plant-danger" not in ids:
            bad(f"field.{st} missing plant-danger")
        else:
            ok(f"field.{st} snake+plant-danger")
    fl_ids = {c["id"] for c in json.loads((root / "field.fl.json").read_text())["cards"]}
    ny_ids = {c["id"] for c in json.loads((root / "field.ny.json").read_text())["cards"]}
    if "ny-ice-adk" in fl_ids:
        bad("FL has Adirondack ice")
    if "fl-gator-dusk" in ny_ids:
        bad("NY has gator")
    else:
        ok("FL/NY regional field cards do not leak")


def packs() -> None:
    cat = json.loads((ROOT / "Resources" / "Packs" / "catalog.json").read_text())
    need = {"tx-west", "tx-east", "nm", "fl-north", "fl-south", "ny-metro", "ny-upstate"}
    have = {p["id"] for p in cat["packs"]}
    if have != need:
        bad(f"pack set {have}")
        return
    for p in cat["packs"]:
        d = ROOT / "Resources" / "Packs" / p["id"]
        for req in ("manifest.json", "osm.geojson", "graph.json", "contours.geojson", "style.json", "dem.json"):
            if not (d / req).is_file():
                bad(f"{p['id']} missing {req}")
                return
        osm = json.loads((d / "osm.geojson").read_text())
        graph = json.loads((d / "graph.json").read_text())
        if len(osm.get("features") or []) < 10:
            bad(f"{p['id']} too few OSM features")
            return
        if len(graph.get("edges") or []) < 10:
            bad(f"{p['id']} too few graph edges")
            return
        slices = p.get("slices") or {}
        if "metro" not in slices or "wild" not in slices:
            bad(f"{p['id']} missing metro/wild")
            return
        ok(f"pack {p['id']} bytes={p['bytes']} osm={len(osm['features'])} edges={len(graph['edges'])}")
    tw = json.loads((ROOT / "Resources" / "Packs" / "tx-west" / "manifest.json").read_text())
    if "border" not in tw.get("slices", {}):
        bad("tx-west missing El Paso border union")
    else:
        ok("El Paso TX+NM border union present")


def vision() -> None:
    for st in ("tx", "nm", "fl", "ny"):
        book = json.loads((ROOT / "Resources" / "Vision" / f"labels.{st}.json").read_text())
        if not book.get("neverEdibleUnlock"):
            bad(f"vision {st} edible unlock")
        kinds = {l["kind"] for l in book["labels"]}
        if "fungi" not in kinds:
            bad(f"vision {st} no fungi")
        if st == "fl" and not any(l.get("marineOrGatorFL") for l in book["labels"]):
            bad("FL missing marine/gator")
        if st != "fl" and any(l.get("marineOrGatorFL") for l in book["labels"]):
            bad(f"{st} leaked FL marine")
        ok(f"vision {st} n={len(book['labels'])} kinds={sorted(kinds)}")
    vis = (ROOT / "Packages" / "VisionCoreML" / "Sources" / "VisionCoreML" / "VisionCoreML.swift").read_text()
    if "hashValue" in vis or "features.hashValue" in vis:
        bad("Vision classify still uses hash-to-label as ID")
    if "NO VISION MODEL" not in vis or "onDeviceModelPresent = false" not in vis:
        bad("Vision must be honest NO VISION MODEL")
    else:
        ok("Vision = NO VISION MODEL (no hash-to-label ID)")
    field_tab = (ROOT / "Blackout" / "FieldTab.swift").read_text()
    if "VISION ADD FRAME" in field_tab or "g.percent" in field_tab:
        bad("Field tab still presents a fake Vision ID")
    else:
        ok("Field tab does not present a fake Vision percent")


def vessel() -> None:
    pbx = (ROOT / "Blackout.xcodeproj" / "project.pbxproj").read_text()
    if "CURRENT_PROJECT_VERSION = 1;" not in pbx:
        bad("CURRENT_PROJECT_VERSION mutated")
    else:
        ok("CURRENT_PROJECT_VERSION = 1")
    if "PRODUCT_BUNDLE_IDENTIFIER = com.crisiskhan.blackout;" not in pbx:
        bad("bundle id")
    else:
        ok("bundle id com.crisiskhan.blackout")
    if "IPHONEOS_DEPLOYMENT_TARGET = 18.0;" not in pbx:
        bad("iOS 18")
    else:
        ok("iOS 18 Universal vessel")
    if 'TARGETED_DEVICE_FAMILY = "1,2";' not in pbx:
        bad("not universal (TARGETED_DEVICE_FAMILY must be quoted OpenStep \"1,2\")")
    else:
        ok("universal TARGETED_DEVICE_FAMILY = \"1,2\"")
    try:
        assert_openstep_plist(pbx)
        ok("project.pbxproj is valid OpenStep plist")
    except Exception as exc:
        bad(f"project.pbxproj OpenStep parse: {exc}")
    if not (ROOT / "Vendor" / "MapLibre" / "MapLibre.xcframework").is_dir():
        bad("MapLibre xcframework missing")
    else:
        ok("MapLibre Metal XCFramework vendored")
    if not (ROOT / "Vendor" / "Opus" / "src").is_dir():
        bad("Opus missing")
    else:
        ok("Opus 1.5.2 vendored")
    if not (ROOT / ".github" / "workflows" / "asc-assign.yml").is_file():
        bad("ASC workflow dropped")
    else:
        ok("kept dispatch-only ASC assign workflow")


def l10n() -> None:
    text = (ROOT / "Blackout" / "L10n.swift").read_text()
    for key in ("CALL SOS", "LLAMAR SOS", "ROJO", "PARA-SI", "VENCIDO", "ESTOY BIEN", "NET · NONE", "NO VISION MODEL"):
        if key not in text:
            bad(f"missing l10n {key}")
            return
    ok("Español SOS/RED/STOP-IF/OVERDUE/chips + NET NONE + NO VISION MODEL")


def mesh() -> None:
    src = (ROOT / "Packages" / "MeshDTN" / "Sources" / "MeshDTN" / "MeshDTN.swift").read_text()
    live = (ROOT / "Packages" / "MeshDTN" / "Sources" / "MeshDTN" / "LiveMeshRadio.swift").read_text()
    if "deny-all sockets" in src and "Bluetooth only" not in src:
        bad("mesh still treats airplane as no radio")
    if "NET · NONE" not in src:
        bad("mesh missing NET · NONE chrome")
    if "import MultipeerConnectivity" not in live or "import CoreBluetooth" not in live:
        bad("LiveMeshRadio missing MPC or BLE")
    else:
        ok("MeshDTN MPC+BLE paths exist; NET · NONE is local writes")
    app = (ROOT / "Blackout" / "AppRuntime.swift").read_text()
    if "mesh.meet(" in app:
        bad("join still uses store-and-meet-only")
    else:
        ok("joinNet starts LiveMeshRadio, not meet-only")


def main() -> None:
    modules()
    no_stubs()
    no_old_engine()
    field_schema()
    packs()
    vision()
    mesh()
    vessel()
    l10n()
    sys.exit(fail)


if __name__ == "__main__":
    main()
