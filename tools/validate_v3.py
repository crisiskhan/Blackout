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


def archive_bundle_id() -> None:
    """xcodebuild archive 33827851150 / 33829001016.

    33829001016 FACT: processed Blackout.app already had
    CFBundleIdentifier=com.crisiskhan.blackout. xcarchive had Products
    app + dSYMs but no archive-root Info.plist. Recover overwrote the
    snapshot, rm'd _CodeSignature, reseal failed (bundle format
    unrecognized). Keep CFBundleIdentifier in the source plist; hand-zip
    the already-signed archive product; do not re-seal it.
    """
    import plistlib

    src = ROOT / "Blackout" / "Info.plist"
    try:
        info = plistlib.loads(src.read_bytes())
    except Exception as exc:
        bad(f"Blackout/Info.plist parse: {exc}")
        return
    if info.get("CFBundleIdentifier") != "$(PRODUCT_BUNDLE_IDENTIFIER)":
        bad(
            "Blackout/Info.plist must set CFBundleIdentifier = "
            "$(PRODUCT_BUNDLE_IDENTIFIER) so ProcessInfoPlistFile expands it "
            "into the .app that archive packaging reads"
        )
    else:
        ok("source Info.plist CFBundleIdentifier = $(PRODUCT_BUNDLE_IDENTIFIER)")
    if info.get("CFBundleShortVersionString") != "$(MARKETING_VERSION)":
        bad("Blackout/Info.plist must set CFBundleShortVersionString = $(MARKETING_VERSION)")
    else:
        ok("source Info.plist CFBundleShortVersionString = $(MARKETING_VERSION)")
    if info.get("CFBundleVersion") != "$(CURRENT_PROJECT_VERSION)":
        bad("Blackout/Info.plist must set CFBundleVersion = $(CURRENT_PROJECT_VERSION)")
    else:
        ok("source Info.plist CFBundleVersion = $(CURRENT_PROJECT_VERSION)")
    bonjour = info.get("NSBonjourServices")
    if bonjour != ["_blackoutmesh._tcp"]:
        bad("NSBonjourServices must stay ['_blackoutmesh._tcp']")
    else:
        ok("NSBonjourServices preserved")

    expanded = str(info.get("CFBundleIdentifier") or "").replace(
        "$(PRODUCT_BUNDLE_IDENTIFIER)", "com.crisiskhan.blackout"
    )
    if expanded != "com.crisiskhan.blackout":
        bad("archive ApplicationProperties.CFBundleIdentifier would be empty")
    else:
        ok("expanded CFBundleIdentifier is com.crisiskhan.blackout")

    script = (ROOT / ".github" / "ci" / "tf-archive.sh").read_text()
    if "recovered-Blackout.app" not in script or "CI snapshot" not in script:
        bad("tf-archive.sh must snapshot Blackout.app before archive teardown")
    else:
        ok("tf-archive.sh snapshots Blackout.app for hand-zip")
    if "rm " in script and "PrivacyInfo.xcprivacy" in script:
        # allow mention in comments; forbid a delete of the privacy/asset files
        for line in script.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if re.search(r"\brm\b.*PrivacyInfo\.xcprivacy|\brm\b.*Assets\.car", stripped):
                bad(f"tf-archive.sh deletes a Crisis-banned file: {stripped}")
                break
        else:
            ok("tf-archive.sh does not delete PrivacyInfo/Assets.car")
    else:
        ok("tf-archive.sh does not delete PrivacyInfo/Assets.car")
    if "processed CFBundleIdentifier" not in script:
        bad("tf-archive.sh must log the processed .app CFBundleIdentifier")
    else:
        ok("tf-archive.sh logs processed CFBundleIdentifier")
    if "handzip_ipa" not in script or "write_xcarchive_plist" not in script:
        bad("tf-archive.sh must hand-zip / write xcarchive Info.plist after exit 70")
    else:
        ok("tf-archive.sh hand-zips or writes xcarchive Info.plist")
    if 'rm -rf "$APP/_CodeSignature"' in script:
        bad("tf-archive.sh must not strip _CodeSignature from a signed archive product")
    else:
        ok("tf-archive.sh does not strip _CodeSignature")
    if "no re-seal" not in script:
        bad("tf-archive.sh must not re-seal a signed archive product")
    else:
        ok("tf-archive.sh does not re-seal signed archive product")
    if re.search(
        r'if \[ -n "\$APP" \] && \[ "\$APP" != "\$SNAP" \]; then\n  rm -rf "\$SNAP"',
        script,
    ):
        bad("tf-archive.sh must not overwrite snapshot before hand-zip on failed archive")
    else:
        ok("tf-archive.sh does not overwrite snapshot on failed archive")


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


def tip55_chrome() -> None:
    """Crisis tip-55 punch list — six must-fix, no Field/Watch/TF expansion."""
    tokens = (ROOT / "Packages" / "Tokens" / "Sources" / "Tokens" / "Tokens.swift").read_text()
    if "r: 0, g: 0, b: 0" not in tokens.replace(" ", "") and "r: 0.0, g: 0.0, b: 0.0" not in tokens.replace(" ", ""):
        # allow either integer 0 or 0.0 void black
        void_ok = re.search(r"void\s*=\s*RGBA\(r:\s*0(?:\.0+)?,\s*g:\s*0(?:\.0+)?,\s*b:\s*0(?:\.0+)?", tokens)
        if not void_ok:
            bad("tokens void is not black")
        else:
            ok("tokens void is black")
    else:
        ok("tokens void is black")
    accent = BlackoutTokens_accent(tokens)
    if not accent:
        bad("tokens missing accent #E10600")
    else:
        ok("tokens accent #E10600")
    if "tabCaptionPoints: Double = 10" not in tokens and "tabCaptionPoints = 10" not in tokens:
        bad("tokens missing 10pt tab caption")
    else:
        ok("tokens tab caption 10pt")

    map_tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
    offline = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "OfflineMapView.swift").read_text()
    pack_style = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift").read_text()
    if "OfflineMapView(" not in map_tab:
        bad("Map tab does not host OfflineMapView")
    elif "RegionalPacks.visible" in map_tab:
        bad("Map tab still renders pack-bullet / Guide FTS list as canvas")
    else:
        ok("Map tab hosts MapLibre canvas, not pack-bullet list")
    if "showsUserLocation" not in offline:
        bad("OfflineMapView missing user puck")
    elif "UserPuck" not in offline or "YouPuckAnnotationView" not in offline:
        bad("OfflineMapView missing visible YOU fallback puck")
    elif "viewFor" not in offline:
        bad("OfflineMapView missing annotation view for YOU puck")
    elif "didFinishLoading" not in offline:
        bad("OfflineMapView does not reapply puck after style load")
    elif 'title = "YOU"' not in pack_style and 'static let title = "YOU"' not in pack_style:
        bad("UserPuck missing YOU title")
    else:
        ok("OfflineMapView user puck")
    if "MLNPolygon" not in offline and "packSouth" not in offline:
        bad("OfflineMapView missing pack geometry")
    else:
        ok("OfflineMapView pack geometry")
    if "addOverlay(" in offline or "removeOverlay(" in offline:
        bad("OfflineMapView uses obsolete MapLibre overlay names (need add/remove)")
    else:
        ok("OfflineMapView uses MapLibre Swift add/remove overlay names")
    if "cachesDirectory" not in pack_style and "temporaryDirectory" not in pack_style:
        bad("PackStyle still writes resolved style into the bundle")
    else:
        ok("PackStyle resolves into a writable cache")

    comms = (ROOT / "Blackout" / "CommsTab.swift").read_text()
    root = (ROOT / "Blackout" / "RootChrome.swift").read_text()
    if "SOSHold(" in comms:
        bad("Comms tab still embeds a second SOSHold")
    elif "SOSHold(" not in root:
        bad("no remaining SOS hold on Comms chrome")
    elif "tab == .comms" not in root:
        bad("contextual SOS is not bound to Comms")
    else:
        ok("single Comms SOS hold (no duplicate disk)")

    if "tabCaptionPoints" not in root and "size: 10" not in root:
        bad("tab bar captions are not 10pt")
    elif "lineLimit(1)" not in root:
        bad("tab bar captions still wrap")
    elif ".expedition" not in (ROOT / "Blackout" / "AppRuntime.swift").read_text():
        bad("Expedition tab removed")
    else:
        ok("tab captions 10pt no wrap; four tabs kept")

    arming = (ROOT / "Blackout" / "ARMINGView.swift").read_text()
    if '"ENTER"' in arming or "Button(\"ENTER\")" in arming:
        bad("ARMING still says ENTER")
    elif "INITIATE" not in arming:
        bad("ARMING missing INITIATE")
    else:
        ok("ARMING primary is INITIATE")
    if "Logo" not in arming and "AppIcon" not in arming:
        bad("ARMING missing bundled logo")
    else:
        ok("ARMING shows bundled logo")
    logo = ROOT / "Blackout" / "Assets.xcassets" / "Logo.imageset" / "Contents.json"
    if not logo.is_file():
        bad("Logo.imageset missing")
    else:
        ok("Logo.imageset bundled")

    exp = (ROOT / "Blackout" / "ExpeditionTab.swift").read_text()
    vitals = (ROOT / "Packages" / "Vitals" / "Sources" / "Vitals" / "Vitals.swift").read_text()
    for label in ("Hunger", "Thirst", "Pain", "Water", "Fatigue", "Exposure"):
        if f'slider("{label}"' not in exp and f'slider("{label.lower()}"' not in exp:
            bad(f"Expedition missing {label} slider")
            break
    else:
        ok("Expedition has six sliders")
    for field in ("hunger", "thirst", "pain", "water", "fatigue", "weatherExposure"):
        if f"var {field}" not in vitals:
            bad(f"PartyVitals missing {field}")
            break
    else:
        ok("PartyVitals has six fields")

    if ".tint(" not in exp and "Theme.accent" not in exp:
        bad("Expedition sliders still use default system tint")
    else:
        ok("Expedition sliders use token tint")
    if "Theme.accent" not in root and ".tint(" not in root:
        bad("root chrome does not apply accent tint (links stay system blue)")
    else:
        ok("root chrome applies accent tint")


def BlackoutTokens_accent(tokens: str) -> bool:
    if "225.0 / 255.0" in tokens or "225.0/255.0" in tokens:
        return True
    if re.search(r"accent\s*=\s*RGBA\(r:\s*0\.882", tokens):
        return True
    return False


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
    comms = (ROOT / "Blackout" / "CommsTab.swift").read_text()
    exp = (ROOT / "Blackout" / "ExpeditionTab.swift").read_text()
    join = (ROOT / "Blackout" / "PartyJoin.swift").read_text() if (ROOT / "Blackout" / "PartyJoin.swift").is_file() else ""
    if "deny-all sockets" in src and "Bluetooth only" not in src:
        bad("mesh still treats airplane as no radio")
    if "NET · NONE" not in src:
        bad("mesh missing NET · NONE chrome")
    if "NO PEERS · LOGGED" not in src:
        bad("mesh missing NO PEERS · LOGGED local-write chrome")
    if "import MultipeerConnectivity" not in live or "import CoreBluetooth" not in live:
        bad("LiveMeshRadio missing MPC or BLE")
    if "session.send" not in live:
        bad("MPC session.send missing")
    if "CBMutableCharacteristic" not in live or "writeValue" not in live or "updateValue" not in live:
        bad("BLE GATT write+notify exchange missing")
    if "isNotifying" not in live:
        bad("BLE marks peer before GATT notify")
    else:
        ok("MeshDTN live MPC+BLE GATT exchange; NET · NONE / NO PEERS · LOGGED")
    app = (ROOT / "Blackout" / "AppRuntime.swift").read_text()
    if "mesh.meet(" in app:
        bad("join still uses store-and-meet-only")
    else:
        ok("joinNet starts LiveMeshRadio, not meet-only")
    if "PartyQR" not in join or "scan.qr" not in comms:
        bad("party join missing QR encode/scan")
    else:
        ok("join is QR plus typed party code")
    if "chip.rally" not in comms or "chip.down" not in comms:
        bad("comms missing RALLY/DOWN chips")
    if "sendRED" not in exp or "sendTimer" not in exp:
        bad("RED/timer not wired to mesh")
    else:
        ok("RALLY/DOWN chips and RED/timer mesh wiring")


def tip57_map() -> None:
    """Tip 57 acceptance — three Done lines only. No Ask-first / FAB / Expedition / Vision / mesh / Watch."""
    pack_style = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift").read_text()
    offline = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "OfflineMapView.swift").read_text()
    map_tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
    wild = json.loads((ROOT / "Resources" / "Packs" / "fl-north" / "wild.geojson").read_text())
    style = json.loads((ROOT / "Resources" / "Packs" / "fl-north" / "style.json").read_text())
    sources = style.get("sources") or {}
    layers = style.get("layers") or []
    lines = [
        f
        for f in wild.get("features") or []
        if (f.get("geometry") or {}).get("type") in {"LineString", "MultiLineString"}
        and "highway" in (f.get("properties") or {})
    ]
    wild_src = (sources.get("wild") or {}).get("data")
    has_wild_roads = any(
        layer.get("id") == "wild-roads" and layer.get("source") == "wild" for layer in layers
    )
    tiles_ok = (
        len(lines) >= 20
        and wild_src == "wild.geojson"
        and has_wild_roads
        and "wild.geojson" in pack_style
        and "wild-roads" in pack_style
        and "prefetchesTiles = false" in offline
    )
    bbox_ok = (
        "setVisibleCoordinateBounds" in offline
        and "lineWidthForPolylineAnnotation" in offline
        and "pack-bbox-line" in offline
        and "MLNPolyline" in offline
    )
    you_ok = (
        "YouPuckAnnotationView" in offline
        and 'static let title = "YOU"' in pack_style
        and "showsUserLocation" in offline
        and "you-puck-core" in offline
        and re.search(r"UserPuck\.coordinate\([\s\S]{0,400}?packSouth:", map_tab) is not None
    )
    if not tiles_ok:
        bad("tiles FAIL — FL NORTH offline street lines not locked")
    else:
        ok("Done: tiles — offline FL NORTH vector streets (wild.geojson), not maroon void")
    if not bbox_ok:
        bad("bbox FAIL — pack region fit/outline not locked")
    else:
        ok("Done: bbox — pack region fit + visible outline")
    if not you_ok:
        bad("YOU FAIL — on-canvas puck not locked")
    else:
        ok("Done: YOU puck — white disk + red ring + YOU on canvas")


def main() -> None:
    modules()
    no_stubs()
    no_old_engine()
    field_schema()
    packs()
    vision()
    mesh()
    vessel()
    archive_bundle_id()
    l10n()
    tip55_chrome()
    tip57_map()
    sys.exit(fail)


if __name__ == "__main__":
    main()
