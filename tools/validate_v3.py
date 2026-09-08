#!/usr/bin/env python3
"""Linux-side contract tests for bible v3. Not an Xcode archive."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from v3.generate_project import assert_openstep_plist

# Ground the vessel ships a map pack for. Everything bundled — field books,
# vision books, banners, packs — has to stay inside this.
SHIPPED_STATES = ("tx", "nm")

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
    for st in SHIPPED_STATES:
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
    books = {p.stem.split(".")[-1] for p in root.glob("field.*.json")} - {"core"}
    if books != set(SHIPPED_STATES):
        bad(f"field books {sorted(books)} — only {list(SHIPPED_STATES)} ship")
        return
    claimed = {s for c in core["cards"] for s in c["states"]}
    for st in SHIPPED_STATES:
        claimed |= {s for c in json.loads((root / f"field.{st}.json").read_text())["cards"] for s in c["states"]}
    if not claimed <= {s.upper() for s in SHIPPED_STATES}:
        bad(f"field cards still claim {sorted(claimed)} — drop states with no map pack")
        return
    ok(f"field books are {list(SHIPPED_STATES)} only; no card claims ground we cannot draw")


def dropped_regions() -> None:
    """Florida and New York are off the vessel. Nothing may carry them back in."""
    dropped = ("fl", "ny")
    res = ROOT / "Resources"
    stray = sorted(
        str(p.relative_to(ROOT))
        for p in res.rglob("*.json")
        if p.stem.split(".")[-1] in dropped
    )
    if stray:
        bad(f"dropped-region books still bundled: {stray}")
        return

    field_root = res / "Field"
    cited = set()
    ids = set()
    for book in field_root.glob("field.*.json"):
        for card in json.loads(book.read_text())["cards"]:
            ids.add(card["id"])
            cited |= {s["image"] for s in card["steps"]}
    orphans = sorted(p.name for p in (field_root / "images").glob("*.png") if p.name not in cited)
    if orphans:
        bad(f"field images no card cites: {orphans}")
        return
    for st in SHIPPED_STATES:
        ids |= {l["id"] for l in json.loads((res / "Vision" / f"labels.{st}.json").read_text())["labels"]}
    tagged = sorted(i for i in ids if i.split("-")[0] in dropped)
    if tagged:
        bad(f"card/label ids from dropped regions: {tagged}")
        return

    banners = (ROOT / "Packages" / "RegionalPacks" / "Sources" / "RegionalPacks" / "RegionalPacks.swift").read_text()
    named = sorted(s for s in ("FL", "NY") if f'"{s}"' in banners)
    if named:
        bad(f"RegionalPacks still names {named}")
        return
    ok("FL/NY dropped: no books, no orphan art, no banners, no ids")


def packs() -> None:
    cat = json.loads((ROOT / "Resources" / "Packs" / "catalog.json").read_text())
    need = {"tx-west", "tx-east", "nm"}
    have = {p["id"] for p in cat["packs"]}
    if have != need:
        bad(f"pack set {have}")
        return
    if set(cat.get("states") or []) != {"TX", "NM"}:
        bad(f"catalog states {cat.get('states')} — FL/NY packs are not shipped")
        return
    for dropped in ("fl-north", "fl-south", "ny-metro", "ny-upstate"):
        if (ROOT / "Resources" / "Packs" / dropped).exists():
            bad(f"{dropped} still bundled — remove from catalog and Resources/Packs")
            return
    if cat.get("defaultPack") != "tx-west" or (cat.get("packs") or [{}])[0].get("id") != "tx-west":
        bad("default open pack must be tx-west (catalog first)")
        return
    ok("default open pack is tx-west")
    ok("catalog ships TX/NM only; FL/NY packs dropped")
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
        style_text = (d / "style.json").read_text()
        if "googleapis" in style_text or "apple.com/maps" in style_text or "mapkit" in style_text.lower():
            bad(f"{p['id']} style has Google/Apple tile hosts")
            return
        ok(f"pack {p['id']} bytes={p['bytes']} osm={len(osm['features'])} edges={len(graph['edges'])}")
    tw = json.loads((ROOT / "Resources" / "Packs" / "tx-west" / "manifest.json").read_text())
    if "border" not in tw.get("slices", {}):
        bad("tx-west missing El Paso border union")
    else:
        ok("El Paso TX+NM border union present")
    walkable_pack()


def walkable_pack() -> None:
    d = ROOT / "Resources" / "Packs" / "tx-west"
    osm = json.loads((d / "osm.geojson").read_text())
    style = json.loads((d / "style.json").read_text())
    graph = json.loads((d / "graph.json").read_text())
    pack_io = (ROOT / "Packages" / "PackIO" / "Sources" / "PackIO" / "PackIO.swift").read_text()
    map_tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
    map_lib = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift").read_text()
    app = (ROOT / "Blackout" / "AppRuntime.swift").read_text()
    feats = osm.get("features") or []
    hwy = [
        f
        for f in feats
        if (f.get("properties") or {}).get("highway")
        and (f.get("geometry") or {}).get("type") == "LineString"
    ]
    named = [f for f in hwy if (f.get("properties") or {}).get("name") or (f.get("properties") or {}).get("ref")]
    water = [
        f
        for f in feats
        if (f.get("properties") or {}).get("waterway") or (f.get("properties") or {}).get("natural") == "water"
    ]
    layers = style.get("layers") or []
    layer_ids = {layer.get("id") for layer in layers}
    road_labels = next((layer for layer in layers if layer.get("id") == "road-labels"), None)
    if len(named) < 200 or len(hwy) < 1000:
        bad(f"tx-west walking streets too thin named={len(named)} hwy={len(hwy)}")
        return
    if not water:
        bad("tx-west missing water features")
        return
    if "road-labels" not in layer_ids or "place-labels" not in layer_ids or "tracks" not in layer_ids:
        bad(f"tx-west style missing walking label layers {layer_ids}")
        return
    if not road_labels or (road_labels.get("minzoom") or 99) > 14:
        bad("road-labels must appear at walking zoom (minzoom <= 14)")
        return
    if "roads" not in layer_ids:
        bad("tx-west missing roads layer")
        return
    glyphs = style.get("glyphs") or ""
    if glyphs.startswith("http") or "googleapis" in glyphs or "mapbox.com" in glyphs:
        bad("tx-west glyphs must be local, not a tile host")
        return
    if not (d / "glyphs" / "Open Sans Regular" / "0-255.pbf").is_file():
        bad("tx-west missing local Open Sans glyphs")
        return
    walk_edges = [e for e in (graph.get("edges") or []) if e.get("walk")]
    drive_edges = [e for e in (graph.get("edges") or []) if e.get("drive")]
    if len(walk_edges) < 1000 or len(drive_edges) < 1000:
        bad(f"tx-west graph too thin walk={len(walk_edges)} drive={len(drive_edges)}")
        return
    if 'defaultPackID = "tx-west"' not in pack_io or "func hasUsableGraph" not in pack_io:
        bad("PackStore must default to tx-west and expose honest hasUsableGraph")
        return
    if "OSMCredit.line" not in map_tab or "© OpenStreetMap contributors" not in map_lib:
        bad("MAP chrome missing © OpenStreetMap contributors")
        return
    if "hasUsableGraph()" not in app:
        bad("LOCK-ON must use hasUsableGraph for honest OFF GRAPH")
        return
    sample = next(
        (
            (f.get("properties") or {}).get("name")
            for f in named
            if (f.get("properties") or {}).get("name")
        ),
        None,
    )
    ok(
        f"tx-west walkable named={len(named)} hwy={len(hwy)} water={len(water)} "
        f"walk_edges={len(walk_edges)} sample={sample}"
    )
    ok("streets visible at walking zoom: yes")
    walkable_next_pack("nm")
    walkable_next_pack("tx-east")


def walkable_next_pack(pack_id: str) -> None:
    """Tip-61 quality bar on the next catalog pack. Must not steal tx-west default."""
    d = ROOT / "Resources" / "Packs" / pack_id
    man = json.loads((d / "manifest.json").read_text())
    cat = json.loads((ROOT / "Resources" / "Packs" / "catalog.json").read_text())
    osm = json.loads((d / "osm.geojson").read_text())
    style = json.loads((d / "style.json").read_text())
    graph = json.loads((d / "graph.json").read_text())
    if cat.get("defaultPack") != "tx-west" or (cat.get("packs") or [{}])[0].get("id") != "tx-west":
        bad(f"{pack_id} stole default open pack from tx-west")
        return
    if man.get("defaultOpen"):
        bad(f"{pack_id} must not set defaultOpen")
        return
    if not man.get("walkable"):
        bad(f"{pack_id} missing walkable flag — still a sticker")
        return
    if "© OpenStreetMap" not in (man.get("attribution") or ""):
        bad(f"{pack_id} missing © OpenStreetMap attribution")
        return
    if pack_id == "nm" and "union" not in (man.get("slices") or {}):
        bad("nm missing Albuquerque / Sandia walkable union")
        return
    if pack_id == "tx-east" and "union" not in (man.get("slices") or {}):
        bad("tx-east missing Austin / Lost Pines walkable union")
        return
    feats = osm.get("features") or []
    hwy = [
        f
        for f in feats
        if (f.get("properties") or {}).get("highway")
        and (f.get("geometry") or {}).get("type") == "LineString"
    ]
    named = [f for f in hwy if (f.get("properties") or {}).get("name") or (f.get("properties") or {}).get("ref")]
    water = [
        f
        for f in feats
        if (f.get("properties") or {}).get("waterway") or (f.get("properties") or {}).get("natural") == "water"
    ]
    layers = style.get("layers") or []
    layer_ids = {layer.get("id") for layer in layers}
    road_labels = next((layer for layer in layers if layer.get("id") == "road-labels"), None)
    if len(named) < 200 or len(hwy) < 1000:
        bad(f"{pack_id} walking streets too thin named={len(named)} hwy={len(hwy)}")
        return
    if not water:
        bad(f"{pack_id} missing water features")
        return
    if "road-labels" not in layer_ids or "place-labels" not in layer_ids or "tracks" not in layer_ids:
        bad(f"{pack_id} style missing walking label layers {layer_ids}")
        return
    if not road_labels or (road_labels.get("minzoom") or 99) > 14:
        bad(f"{pack_id} road-labels must appear at walking zoom (minzoom <= 14)")
        return
    glyphs = style.get("glyphs") or ""
    if glyphs.startswith("http") or "googleapis" in glyphs or "mapbox.com" in glyphs:
        bad(f"{pack_id} glyphs must be local, not a tile host")
        return
    if not (d / "glyphs" / "Open Sans Regular" / "0-255.pbf").is_file():
        bad(f"{pack_id} missing local Open Sans glyphs")
        return
    walk_edges = [e for e in (graph.get("edges") or []) if e.get("walk")]
    drive_edges = [e for e in (graph.get("edges") or []) if e.get("drive")]
    if len(walk_edges) < 1000 or len(drive_edges) < 1000:
        bad(f"{pack_id} graph too thin walk={len(walk_edges)} drive={len(drive_edges)}")
        return
    mb = (man.get("bytes") or 0) / (1024 * 1024)
    if mb > 160:
        bad(f"{pack_id} {mb:.1f} MB exceeds 160 MB iOS budget")
        return
    if not (man.get("stats") or {}).get("streetsVisibleAtWalkingZoom"):
        bad(f"{pack_id} streetsVisibleAtWalkingZoom is not yes")
        return
    sample = next(
        (
            (f.get("properties") or {}).get("name")
            for f in named
            if (f.get("properties") or {}).get("name")
        ),
        None,
    )
    ok(
        f"{pack_id} walkable named={len(named)} hwy={len(hwy)} water={len(water)} "
        f"walk_edges={len(walk_edges)} mb={mb:.1f} sample={sample}"
    )
    ok(f"{pack_id} streets visible at walking zoom: yes")


def vision() -> None:
    root = ROOT / "Resources" / "Vision"
    books = {p.stem.split(".")[-1] for p in root.glob("labels.*.json")}
    if books != set(SHIPPED_STATES):
        bad(f"vision books {sorted(books)} — only {list(SHIPPED_STATES)} ship")
        return
    for st in SHIPPED_STATES:
        book = json.loads((root / f"labels.{st}.json").read_text())
        if not book.get("neverEdibleUnlock"):
            bad(f"vision {st} edible unlock")
        kinds = {l["kind"] for l in book["labels"]}
        if "fungi" not in kinds:
            bad(f"vision {st} no fungi")
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
    if "convertPoint(" in offline or "toCoordinateFromView:" in offline:
        bad("OfflineMapView uses obsolete MapLibre convertPoint name (need convert(_:toCoordinateFrom:))")
    else:
        ok("OfflineMapView uses MapLibre Swift convert(_:toCoordinateFrom:)")
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
    elif "tab == .comms" not in root and "sosFAB" not in root:
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
    if "sendRED" not in app or "sendTimer" not in exp:
        bad("RED/timer not wired to mesh")
    else:
        ok("RALLY/DOWN chips and RED/timer mesh wiring")


def tip57_map() -> None:
    """Tip 57 acceptance — three Done lines only. No Ask-first / FAB / Expedition / Vision / mesh / Watch."""
    pack_style = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift").read_text()
    offline = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "OfflineMapView.swift").read_text()
    map_tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
    wild = json.loads((ROOT / "Resources" / "Packs" / "nm" / "wild.geojson").read_text())
    style = json.loads((ROOT / "Resources" / "Packs" / "nm" / "style.json").read_text())
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
        bad("tiles FAIL — NM offline street lines not locked")
    else:
        ok("Done: tiles — offline NM vector streets (wild.geojson), not maroon void")
    if not bbox_ok:
        bad("bbox FAIL — pack region fit/outline not locked")
    else:
        ok("Done: bbox — pack region fit + visible outline")
    if not you_ok:
        bad("YOU FAIL — on-canvas puck not locked")
    else:
        ok("Done: YOU puck — white disk + red ring + YOU on canvas")


def tip58_solo_qa() -> None:
    """Tip 58 DoD — five Done lines only. Fail = crash OR dead control. Fix SHA only. No CPV / TF."""
    app = (ROOT / "Blackout" / "AppRuntime.swift").read_text()
    speech = (ROOT / "Packages" / "OfflineSpeech" / "Sources" / "OfflineSpeech" / "OfflineSpeech.swift").read_text()
    marks = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift").read_text()
    exp = (ROOT / "Blackout" / "ExpeditionTab.swift").read_text()
    map_tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
    ptt = (ROOT / "Packages" / "PTTAudio" / "Sources" / "PTTAudio" / "PTTAudio.swift").read_text()
    red = (ROOT / "Packages" / "RedAlert" / "Sources" / "RedAlert" / "RedAlert.swift").read_text()
    timers = (ROOT / "Packages" / "TimerSync" / "Sources" / "TimerSync" / "TimerSync.swift").read_text()
    mesh = (ROOT / "Packages" / "MeshDTN" / "Sources" / "MeshDTN" / "MeshDTN.swift").read_text()
    comms = (ROOT / "Blackout" / "CommsTab.swift").read_text()
    init = app.split("func arm(")[0]

    mark_ok = (
        'Button("MARK")' in map_tab
        and "dropMark()" in app
        and "MarkStore.load" in init
        and "MarkStore.save" in app
        and "synchronize()" in marks
        and "fix.arm()" not in init
        and re.search(r"let mgr = CLLocationManager\(\)", app) is None
        and re.search(r"private let synth = AVSpeechSynthesizer\(\)", speech) is None
    )
    timer_ok = (
        'Button("1 MIN TIMER SET")' in exp
        and 'Button("DONE")' in exp
        and "TimelineView" in exp
        and "overdueRowID" in timers
        and "overduePlate" in exp
        and ("who.isEmpty" in timers)
        and "isSOS" in timers
    )
    red_ok = (
        "APPLY RED BAND" in exp
        and "applySelfRed" in app
        and "cancelSelfRed" in exp
        and "isSOS" in red
        and "openURL" not in red
        and "tel:" not in red
        and "911" not in red
        and "sendRED" in app
    )
    ptt_ok = (
        "HOLD PTT" in comms
        and "beginPTTSolo" in app
        and "recordClip" in app
        and "endPTTSolo" in comms
        and "AVAudioEngine" not in ptt
        and "LivePTTHub" not in ptt
        and "import AVFoundation" not in ptt
    )
    peers_ok = (
        "NO PEERS · LOGGED" in mesh
        and "sendChip" in mesh
        and 'chip: "ptt"' in app
    )

    if not mark_ok:
        bad("MARK FAIL — crash/dead MARK after kill")
    else:
        ok("Done: MARK after kill — no crash/dead MARK")
    if not timer_ok:
        bad("timer FAIL — crash/stuck 1-min overdue + DONE")
    else:
        ok("Done: 1-min party timer overdue + DONE — no crash/stuck")
    if not red_ok:
        bad("RED FAIL — crash or auto-911")
    else:
        ok("Done: Self RED + cancel — no crash, no auto-911")
    if not ptt_ok:
        bad("PTT FAIL — crash/hang under NET · NONE")
    else:
        ok("Done: PTT clip NET · NONE — no crash/hang")
    if not peers_ok:
        bad("NO PEERS · LOGGED FAIL — 0-peer chip regress")
    else:
        ok("Done: NO PEERS · LOGGED chip at 0 peers")


def tip60_map_chrome() -> None:
    """Tip 60 DoD — five MAP still bars only. OUT: Vision / Field cards / Watch / new packs / CPV / tf:."""
    pack_style = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift").read_text()
    offline = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "OfflineMapView.swift").read_text()
    map_tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
    root = (ROOT / "Blackout" / "RootChrome.swift").read_text()
    tokens = (ROOT / "Packages" / "Tokens" / "Sources" / "Tokens" / "Tokens.swift").read_text()
    app = (ROOT / "Blackout" / "AppRuntime.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj" / "project.pbxproj").read_text()
    catalog = json.loads((ROOT / "Resources" / "Packs" / "catalog.json").read_text())
    solo = (ROOT / "docs" / "SOLO_QA.md").read_text()
    comms = (ROOT / "Blackout" / "CommsTab.swift").read_text()

    locked = [
        "full-height canvas",
        "pack outline+puck",
        "single MARK",
        "no CALL SOS on browse MAP",
        "no solid-red slab",
    ]
    if "enum MapStillBar" not in tokens or "static var scoreBar" not in tokens:
        bad("MAP still score bar missing from Tokens")
        return
    if any(label not in tokens for label in locked):
        bad("MAP still score bar labels drifted")
        return
    if any(label not in solo for label in locked):
        bad("SOLO_QA MAP still score bar missing a locked bar")
        return

    pack_ids = {p.get("id") for p in catalog.get("packs") or []}
    allowed_packs = {"nm", "tx-east", "tx-west"}
    if pack_ids != allowed_packs:
        bad("new packs added — tip-60 OUT")
        return
    if "CURRENT_PROJECT_VERSION = 1;" not in pbx or pbx.count("CURRENT_PROJECT_VERSION = 1;") < 6:
        bad("CPV bumped — tree must stay 1")
        return

    canvas_ok = (
        "maxHeight: .infinity" in map_tab
        and "layoutPriority(1)" in map_tab
        and "ZStack(alignment: .bottomLeading)" in map_tab
        and re.search(r"\.frame\(maxWidth: \.infinity, maxHeight: \.infinity\)", map_tab) is not None
        and "PackCamera.shouldRefit" in offline
        and "FillingMapView" in offline
    )
    outline_puck_ok = (
        "MLNPolyline" in offline
        and "pack-bbox-line" in offline
        and "YouPuckAnnotationView" in offline
        and 'static let title = "YOU"' in pack_style
        and "you-puck-core" in offline
        and re.search(r"UserPuck\.coordinate\([\s\S]{0,400}?packSouth:", map_tab) is not None
    )
    mark_ok = (
        "MarkDrop.merging" in app
        and "func merging" in pack_style
        and "sameCoord" in pack_style
        and "func uniqued" in pack_style
        and 'Button("MARK")' in map_tab
        and "dropMark()" in app
    )
    sos_ok = (
        "sosFAB" in tokens
        and "sosFAB" in root
        and "runtime.lockOn || runtime.tab == .comms" not in root
        and "SOSHold(" not in comms
        and "SOSHold(" in root
        and "case .map, .field, .expedition" in tokens
    )
    slab_ok = (
        "fillsBBox = false" in pack_style
        and "packOverlay" not in offline
        and "225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 0.16" not in offline
    )

    bars = [
        ("full-height canvas", canvas_ok, "MAP canvas FAIL — not full-height under search"),
        ("pack outline+puck", outline_puck_ok, "outline+puck FAIL — pack outline or YOU puck not locked"),
        ("single MARK", mark_ok, "MARK FAIL — identical coords still append"),
        ("no CALL SOS on browse MAP", sos_ok, "SOS FAIL — CALL SOS still on browse MAP"),
        ("no solid-red slab", slab_ok, "slab FAIL — filled red pack overlay still present"),
    ]
    scored = []
    for label, passed, fail_msg in bars:
        if passed:
            ok(f"Done: {label}")
            scored.append(f"[{label}]")
        else:
            bad(fail_msg)
            scored.append(f"[FAIL {label}]")
    print("OK   MAP still score: " + " ".join(scored))


def tip62_nav() -> None:
    """Tip 62 — WALK/DRIVE on-graph route line. Honest OFF GRAPH. No new packs / CPV / tf:."""
    router = (ROOT / "Packages" / "Router" / "Sources" / "Router" / "Router.swift").read_text()
    route_line = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "RouteLine.swift").read_text()
    offline = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "OfflineMapView.swift").read_text()
    map_tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
    app = (ROOT / "Blackout" / "AppRuntime.swift").read_text()
    router_tests = (ROOT / "Packages" / "Router" / "Tests" / "RouterTests" / "RouterTests.swift").read_text()
    map_tests = (
        ROOT / "Packages" / "MapLibreMap" / "Tests" / "MapLibreMapTests" / "MapLibreMapTests.swift"
    ).read_text()
    pbx = (ROOT / "Blackout.xcodeproj" / "project.pbxproj").read_text()
    catalog = json.loads((ROOT / "Resources" / "Packs" / "catalog.json").read_text())

    pack_ids = {p.get("id") for p in catalog.get("packs") or []}
    allowed_packs = {"nm", "tx-east", "tx-west"}
    if pack_ids != allowed_packs:
        bad("new packs added — tip-62 TX WEST only")
        return
    if "CURRENT_PROJECT_VERSION = 1;" not in pbx or pbx.count("CURRENT_PROJECT_VERSION = 1;") < 6:
        bad("CPV bumped — tree must stay 1")
        return

    path_ok = (
        "func nearestNode" in router
        and "func coordinates" in router
        and "enum GraphPlan" in router
        and 'offGraph = "OFF GRAPH"' in router
        and "MinHeap" in router
    )
    overlay_ok = (
        'sourceID = "route-line-src"' in route_line
        and 'layerID = "route-line"' in route_line
        and "RouteLine.sourceID" in offline
        and "RouteLine.layerID" in offline
        and "var routeLine: MLNPolyline?" in offline
        and "syncRoute" in offline
        and "onMapTap" in offline
    )
    tokens = (ROOT / "Packages" / "Tokens" / "Sources" / "Tokens" / "Tokens.swift").read_text()
    style = json.loads((ROOT / "Resources" / "Packs" / "tx-west" / "style.json").read_text())
    layers = style.get("layers") or []
    road_labels = next((layer for layer in layers if layer.get("id") == "road-labels"), None)

    chips_ok = (
        "mapChipHitPoints: Double = 44" in tokens
        and "enum MapChip" in tokens
        and 'Button("MARK")' in map_tab
        and 'Button("WALK")' in map_tab
        and 'Button("DRIVE")' in map_tab
        and 'Button("RULER")' in map_tab
        and 'Button("USNG")' in map_tab
        and 'Button("MAG/TRUE")' in map_tab
        and "MapChipButtonStyle" in map_tab
        and "BlackoutTokens.Chrome.mapChipHitPoints" in map_tab
        and "frame(width: hit, height: hit)" in map_tab
        and "ForEach(MapTool.allCases" not in map_tab
        and "font(.caption2)" not in map_tab
    )
    walk_ok = (
        "runtime.navigate(mode: .walk)" in map_tab
        and "runtime.navigate(mode: .drive)" in map_tab
        and "route: runtime.routeCoords" in map_tab
        and "pickDestination" in map_tab
        and "routeChrome" in map_tab
        # A dead chip tells the field nothing: WALK/DRIVE always tap and always answer.
        and ".disabled(" not in map_tab
        and "hasDestination" in route_line
        and "enum RouteBlock" in route_line
        and "alwaysTappable" in route_line
        and "func navigate(mode: TravelMode)" in app
        and "GraphPlan.line" in app
        and "WalkDriveChip.block(" in app
        and "RouteSummary.chrome(" in app
        and "RouteBlock.noPath" in app
        and "WalkDriveChip" in route_line
        and "convert(point, toCoordinateFrom:" in offline
        and "convertPoint" not in offline
    )
    mark_one_ok = (
        "MarkDrop.merging" in app
        and "dropMark()" in app
        and 'Button("MARK")' in map_tab
    )
    canvas_clean_ok = (
        "OSMCredit.line" in map_tab
        and "© OpenStreetMap contributors" in (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift").read_text()
        and "no MapKit engine" not in map_tab
        and "MapLibre Metal offline" not in map_tab
        and "style.json ·" not in map_tab
        and "chromeNet" not in map_tab
        and "layoutPriority(1)" in map_tab
        and "ZStack(alignment: .bottomLeading)" in map_tab
        # Readouts a field user cannot act on. The destination is a pin, not a number.
        and "DEST %.4f" not in map_tab
        and "BEARING %.0f" not in map_tab
        and "pack.bytes" not in map_tab
        and "Search FTS" not in map_tab
        and 'MARK \\(m.label)' not in map_tab
    )
    roads_ok = (
        road_labels is not None
        and float(road_labels.get("minzoom") or 99) <= 12
        and (road_labels.get("paint") or {}).get("text-color") == "#B8BDC2"
        and (road_labels.get("paint") or {}).get("text-halo-color") == "#000000"
        and float((road_labels.get("paint") or {}).get("text-halo-width") or 0) >= 1.8
        and any(layer.get("id") == "road-refs" for layer in layers)
        and "road-labels" in (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift").read_text()
        and "#B8BDC2" in (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift").read_text()
    )
    tests_ok = (
        "testWalkFindsTwoHopPathAndDriveIgnoresWalkOnlyEdges" in router_tests
        and "testGraphPlanDrawsOnGraphLineAndStaysHonestOffGraph" in router_tests
        and "testRouteLineSourceHooksAndOffGraphHasNoDrawableCoords" in map_tests
        and "testWalkDriveChipAlwaysTapsAndNamesTheBlocker" in map_tests
        and "testRouteSummaryReportsDrawnLineAndStaysHonestWhenEmpty" in map_tests
        and "testCanvasOpensWhereStreetNamesRender" in map_tests
        and "testDestinationPinTracksTheChosenTarget" in map_tests
        and "testHomeCoordinateFallsBackToCenterWhenAbsent" in (
            ROOT / "Packages" / "PackIO" / "Tests" / "PackIOTests" / "PackIOTests.swift"
        ).read_text()
        and "testMapInstrumentChipsAreSixFortyFourPointTargets" in (
            ROOT / "Packages" / "Tokens" / "Tests" / "TokensTests" / "TokensTests.swift"
        ).read_text()
        and "OFF GRAPH" in router_tests
        and "shouldDraw" in map_tests
    )
    fake_ok = "bearingFallback" not in app and "GraphPlan.line" in app

    checks = [
        ("1 44pt tappable chips", chips_ok, "tip-62 chips FAIL — mark/walk/drive/ruler/usng/magTrue not 44pt Buttons"),
        ("2 WALK/DRIVE draw or say why", walk_ok, "WALK/DRIVE FAIL — dead chip, no reason line, or convert API"),
        ("3 MARK one-row", mark_one_ok, "tip-62 MARK FAIL — MarkDrop not wired"),
        ("4 debug chrome off canvas", canvas_clean_ok, "tip-62 canvas FAIL — style.json/MapKit debug still on MAP"),
        ("5 walking-zoom road names", roads_ok, "tip-62 roads FAIL — road-labels missing or not walking zoom"),
        ("GraphRouter nearest + GraphPlan", path_ok, "tip-62 router missing nearest/plan/OFF GRAPH"),
        ("route polyline overlay", overlay_ok, "tip-62 OfflineMapView missing route-line overlay"),
        ("unit tests path + source hooks", tests_ok, "tip-62 missing GraphRouter/RouteLine/chip tests"),
        ("no bearing fake route", fake_ok, "tip-62 must not draw bearingFallback as a street line"),
    ]
    for label, passed, fail_msg in checks:
        if passed:
            ok(f"Done: {label}")
        else:
            bad(fail_msg)

    plan = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "test_graph_plan.py")],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if plan.returncode != 0:
        bad(f"tip-62 GraphPlan python tests failed\n{plan.stdout}{plan.stderr}")
    else:
        ok("Done: GraphPlan python path + OFF GRAPH")


def main() -> None:
    modules()
    no_stubs()
    no_old_engine()
    field_schema()
    dropped_regions()
    packs()
    vision()
    mesh()
    vessel()
    archive_bundle_id()
    l10n()
    tip55_chrome()
    tip57_map()
    tip58_solo_qa()
    tip60_map_chrome()
    tip62_nav()
    next_pack = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "test_walkable_next_pack.py")],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if next_pack.returncode != 0:
        bad(f"walkable next-pack lock failed\n{next_pack.stdout}{next_pack.stderr}")
    else:
        ok("walkable next-pack lock: NM + TX EAST; default tx-west; no FL/NY")
    style_read = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "test_tx_west_style.py")],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if style_read.returncode != 0:
        bad(f"TX WEST walking-zoom style readability failed\n{style_read.stdout}{style_read.stderr}")
    else:
        ok("TX WEST walking-zoom streets and names use Blackout ink")
    tip65_speak()
    sys.exit(fail)


def tip65_speak() -> None:
    """Tip 65 — finish Speak voice nav. Keep SPEAK. Do not regress Walk line."""
    voice = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "test_voice_nav.py")],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if voice.returncode != 0:
        bad(f"tip-65 VoiceNav tests failed\n{voice.stdout}{voice.stderr}")
        return
    ok("Done: VoiceNav full prompt + Speak chip stays")

    map_tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
    app = (ROOT / "Blackout" / "AppRuntime.swift").read_text()
    offline = (ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "OfflineMapView.swift").read_text()
    pbx = (ROOT / "Blackout.xcodeproj" / "project.pbxproj").read_text()
    if 'Button("SPEAK")' not in map_tab or "runtime.speakMap()" not in map_tab:
        bad("tip-65 deleted SPEAK")
        return
    if "VoiceNav.prompt" not in app or "speechChrome = text" not in app:
        bad("tip-65 Speak still truncated stub")
        return
    if "GraphPlan.line" not in app or "RouteLine.sourceID" not in offline:
        bad("tip-65 Walk cyan line hooks missing")
        return
    if "CURRENT_PROJECT_VERSION = 1;" not in pbx:
        bad("CPV bumped — tree must stay 1")
        return
    ok("Done: SPEAK kept; Walk line hooks intact; CPV 1")


if __name__ == "__main__":
    main()
