#!/usr/bin/env python3
"""Quality bar — Linux stand-in for the HUD on every tab, not just MAP.

Crisis: if there is a better method, aesthetic, or way to do a feature, do that.
INST existed because INSTRUMENTS truncated. Bearing printed with nowhere to walk.
FIELD tore the hold card down in-stack (ASC 72). Leaving MAP destroyed MapLibre.
COMMS dumped Whisper meters. Those are not the best way — these contracts are.
"""
from __future__ import annotations

import re
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


def field_search_bar(src: str) -> str:
    """The SEARCH/SAY HStack on FIELD. Chips belong on this row, not under it."""
    search = src.split("private var searchField")[1].split("private func say")[0]
    return search.split("HStack", 1)[1].split("if sayFailed", 1)[0]


def person_compass_const(name: str) -> float:
    src = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "PersonEmblem.swift")
    match = re.search(
        rf"static let {re.escape(name)}: Double = ([0-9.]+)",
        src,
    )
    if match is None:
        raise AssertionError(f"PersonCompass.{name} missing")
    return float(match.group(1))


def dest_rail_visible(
    has_destination: bool,
    lock_on: bool,
    has_route: bool,
    has_you_fix: bool = False,
) -> bool:
    """Mirror of MapFieldChrome.destRailVisible. Dest pin, or YOU when idle."""
    del lock_on, has_route
    return has_destination or has_you_fix


def active_bearing(
    heading: float | None,
    has_destination: bool,
    lock_on: bool,
    has_route: bool,
) -> float | None:
    """Mirror of MapFieldChrome.activeBearing. Profile course, not MAP dest."""
    del lock_on, has_route
    if not has_destination:
        return None
    if heading is None or heading < 0:
        return None
    return heading


def _vision_has_phrase(hay: str, needle: str) -> bool:
    """Mirror of VisionCoreML.hasPhrase. Unspaced needles are whole words."""
    if " " in needle:
        return needle in hay
    words: list[str] = []
    current = ""
    for ch in hay:
        if ch.isalnum():
            current += ch
        elif current:
            words.append(current)
            current = ""
    if current:
        words.append(current)
    return needle in words


def _vision_kind_needles(src: str) -> list[tuple[str, list[str]]]:
    block = src.split("kindNeedles:", 1)[1]
    pairs: list[tuple[str, list[str]]] = []
    for match in re.finditer(
        r"\(\.(\w+),\s*\[(.*?)\]\s*\)",
        block,
        re.S,
    ):
        kind = match.group(1)
        needles = re.findall(r'"([^"]+)"', match.group(2))
        pairs.append((kind, needles))
    fungi_block = src.split("fungiNeedles = [", 1)[1].split("]", 1)[0]
    fungi = re.findall(r'"([^"]+)"', fungi_block)
    return [("fungi", fungi), *pairs]


def _vision_kind(needles: list[tuple[str, list[str]]], identifier: str) -> str | None:
    ident = identifier.lower().replace("_", " ").replace("-", " ")
    for kind, words in needles:
        if any(_vision_has_phrase(ident, word) for word in words):
            return kind
    return None


_VISION_RANK = {
    "fungi": 50,
    "snake": 40,
    "wound": 39,
    "sting": 38,
    "fire": 37,
    "gator": 36,
    "cactus": 35,
    "cactiYucca": 35,
    "flood": 34,
    "lightning": 33,
    "water": 32,
    "smoke": 31,
    "mammal": 30,
    "ice": 29,
    "shelter": 28,
    "tree": 10,
}


def _vision_best(
    needles: list[tuple[str, list[str]]],
    observations: list[tuple[str, float]],
) -> str | None:
    best: tuple[str, int] | None = None
    for ident, conf in observations:
        if conf < 0.2:
            continue
        kind = _vision_kind(needles, ident)
        if kind is None:
            continue
        rank = _VISION_RANK.get(kind, 30)
        if best is None or rank > best[1]:
            best = (kind, rank)
    return None if best is None else best[0]


class QuietBearingTests(unittest.TestCase):
    def test_heading_alone_is_not_a_mission(self):
        self.assertFalse(dest_rail_visible(False, False, False))
        self.assertTrue(dest_rail_visible(True, False, False))
        self.assertFalse(dest_rail_visible(False, True, False))
        self.assertFalse(dest_rail_visible(False, False, True))
        self.assertTrue(dest_rail_visible(False, False, False, True))
        self.assertTrue(dest_rail_visible(True, False, False, True))
        self.assertFalse(dest_rail_visible(False, True, False, False))
        self.assertIsNone(active_bearing(12, False, False, False))
        self.assertEqual(active_bearing(45, True, False, False), 45)
        self.assertIsNone(active_bearing(10, False, True, False))
        self.assertIsNone(active_bearing(8, False, False, True))
        self.assertIsNone(active_bearing(None, True, False, False))
        self.assertIsNone(active_bearing(-1, True, True, True))
        self.assertEqual(active_bearing(0, True, False, False), 0)

    def test_map_dest_rail_does_not_print_bearing(self):
        route = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift")
        tab = read("Blackout", "MapTab.swift")
        chrome = tab.split("private var fieldChrome")[1].split("private var hudReserve")[0]
        self.assertIn("func activeBearing(", route)
        self.assertNotIn("MapFieldChrome.activeBearing(", tab)
        self.assertNotIn("bearingDeg: runtime.headingDeg", tab)
        vis = route.split("func destRailVisible(")[1].split("func destLine")[0]
        self.assertIn("hasDestination", vis)
        self.assertIn("hasYouFix", vis)
        self.assertIn("hasDestination || hasYouFix", vis)
        self.assertNotIn("|| lockOn", vis)
        self.assertNotIn("|| hasRoute", vis)
        self.assertNotIn("MapFieldDestMode.bearing", tab)
        self.assertNotIn("case bearing", route)
        self.assertNotIn("@State private var destMode", tab)

    def test_dest_line_prints_dest_while_navigating_and_you_when_idle(self):
        route = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift")
        tab = read("Blackout", "MapTab.swift")
        chrome = tab.split("private var fieldChrome")[1].split("private var hudReserve")[0]
        self.assertIn("runtime.routeTarget", chrome)
        self.assertIn("runtime.gnssYou", chrome)
        self.assertNotIn("youCoordinate()", chrome)
        self.assertNotIn("lastKnownFix", chrome)
        self.assertNotIn("youCoordinate()", tab)
        dest_src = route.split("func destLine(")[1].split("func destValue")[0]
        self.assertIn("destValue", dest_src)
        self.assertIn("you", dest_src)
        self.assertNotIn("NO HEADING", dest_src)
        self.assertNotIn("BEARING", dest_src)
        self.assertIn("func destRailVisible(", route)
        self.assertIn("destRailVisible(", chrome)
        self.assertIn("func destValue(", route)
        self.assertIn("enum MapFieldDestMode", route)
        self.assertIn("case turns", route)
        self.assertIn("%.5f, %.5f", route)
        self.assertNotIn("DEST %.4f", route)
        self.assertNotIn("packs?.active?.center", chrome)
        self.assertIn("MapFieldDestRail", tab)
        self.assertIn("MapFieldDestMode.coordinates", tab)
        self.assertIn("MapFieldDestMode.turns", tab)
        self.assertNotIn("Theme.accent", chrome)
        self.assertIn("Theme.fix", chrome)
        self.assertIn("Theme.Motion.beat", chrome)
        self.assertIn("@State private var beat", chrome)
        self.assertIn("MapFieldChrome.destValue", chrome)
        self.assertIn("Text(field)", chrome)
        rail = chrome.split("struct MapFieldDestRail")[1]
        self.assertNotIn("chip(MapFieldDestMode.coordinates)", rail)
        self.assertIn("chip(MapFieldDestMode.turns)", rail)
        chip = rail.split("func chip(")[1]
        self.assertNotIn("destValue", chip)
        self.assertIn("chipMode.title", chip)
        self.assertNotIn("MapFieldDestMode.bearing", rail)
        self.assertIn("MapFieldDestMode.turns", tab)
        self.assertIn("layoutPriority", chrome)
        self.assertNotIn("Theme.glass", chrome)
        self.assertNotIn("ultraThinMaterial", chrome)
        theme = read("Blackout", "Theme.swift")
        chip_style = theme.split("struct MapFieldDestChipStyle")[1].split("enum HUDStatusTone")[0]
        self.assertIn("var expanded: Bool", chip_style)
        self.assertIn("var beat: Double", chip_style)
        self.assertIn(".shadow(", chip_style)
        self.assertIn("repeatForever", theme)
        self.assertNotIn("Theme.raised", chip_style)
        self.assertNotIn("ultraThinMaterial", chip_style)
        self.assertNotIn("Color.green", chip_style)
        self.assertNotIn("Color.orange", chip_style)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("no grey plate", qa.lower())
        self.assertIn("no `COORDINATES` word", qa)
        self.assertNotIn("44pt `COORDINATES` chip", qa)
        device = read("docs", "DEVICE.md")
        self.assertIn("no grey plate", device.lower())
        self.assertIn("no `COORDINATES` word", device)
        agents = read("AGENTS.md")
        self.assertIn("no grey plate", agents.lower())
        self.assertIn("no COORDINATES word", agents)
        app = read("Blackout", "AppRuntime.swift")
        you = app.split("var gnssYou")[1].split("var fieldYou")[0]
        self.assertIn("fix.last", you)
        self.assertNotIn("lastKnownFix", you)
        self.assertNotIn("center", you)
        party = read("Blackout", "PartyHoldCard.swift")
        address = read("Blackout", "AddressHoldCard.swift")
        self.assertIn("BEARING", party)
        self.assertIn("COORDINATES", party)
        self.assertIn("BEARING", address)
        self.assertIn("COORDINATES", address)


class KeepMapMountedTests(unittest.TestCase):
    def test_map_stays_in_the_tree_on_every_tab(self):
        root = read("Blackout", "RootChrome.swift")
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("MapTab(runtime: runtime)", root)
        self.assertIn("allowsHitTesting(runtime.tab == .map)", root)
        self.assertNotIn("case .map: MapTab(runtime: runtime)", root)
        self.assertIn("runtime.tab == .map", tab)
        # Padding the ZStack that holds MapTab resized MapLibre and snapped
        # the camera back to YOU. Overlay pages take the tab-strip inset.
        self.assertIn("private func overlayPage", root)
        self.assertNotIn(
            "tabBody\n                .padding(.bottom, overlayBottomPad)",
            root,
        )
        self.assertIn("MapCanvasHit.enabled(", tab)
        self.assertIn("OfflineMapView(", tab)
        self.assertNotIn("GlobeView(", tab)
        self.assertIn("isUserInteractionEnabled = interactive", read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        ))
        self.assertIn("HUDPage", read("Blackout", "CommsTab.swift"))
        self.assertIn("HUDPage", read("Blackout", "FieldTab.swift"))
        self.assertIn("HUDPage", read("Blackout", "ExpeditionTab.swift"))


class PageOpenCloseFadeTests(unittest.TestCase):
    """Pages open, close, and fade with HUD motion. No iOS sheet bounce."""

    def test_overlay_pages_fade_and_the_map_stays_mounted(self):
        root = read("Blackout", "RootChrome.swift")
        overlay = root.split("private func overlayPage")[1].split("private var tabBody")[0]
        self.assertIn(".transition(.opacity)", overlay)
        self.assertIn("animation(Theme.Motion.heavy, value: runtime.tab)", root)
        self.assertIn("animation(Theme.Motion.heavy, value: runtime.armed)", root)
        self.assertIn(".transition(.opacity)", root.split("if !runtime.armed")[1].split("tabChrome")[0])
        self.assertIn("MapTab(runtime: runtime)", root)
        self.assertNotIn(".spring(", root)
        self.assertNotIn("fullScreenCover", root)
        self.assertNotIn("best in class", root.lower())

    def test_instruments_fades_as_hud_glass_not_a_system_sheet(self):
        root = read("Blackout", "RootChrome.swift")
        self.assertIn("InstrumentsView(runtime: runtime)", root)
        self.assertIn("animation(Theme.Motion.heavy, value: runtime.showInstruments)", root)
        inst = root.split("if runtime.armed")[-1]
        self.assertIn("showInstruments", inst)
        self.assertIn(".transition(.opacity)", inst)
        self.assertNotIn(".sheet(isPresented: $runtime.showInstruments)", root)
        self.assertNotIn("presentationBackground", root)
        self.assertNotIn(".spring(", root)
        qa = read("docs", "SOLO_QA.md")
        inst_line = next(
            line
            for line in qa.splitlines()
            if "COMPASS CAL" in line and "GNSS PUCK" in line
        )
        self.assertIn("fade", inst_line.lower())
        self.assertIn("no bounce", inst_line.lower())
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)
        self.assertNotIn("Google", qa)

    def test_incoming_typewriter_vision_scan_and_turns_fade(self):
        root = read("Blackout", "RootChrome.swift")
        plate = read("Blackout", "IncomingLinePlate.swift")
        field = read("Blackout", "FieldTab.swift")
        comms = read("Blackout", "CommsTab.swift")
        turns = read("Blackout", "SpeakTurnCard.swift")
        tab = read("Blackout", "MapTab.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn(".transition(.opacity)", plate)
        self.assertIn("animation(Theme.Motion.heavy, value: runtime.incoming)", root)
        self.assertIn(".transition(.opacity)", root.split("private var hudTypewriter")[1])
        self.assertNotIn(".sheet(isPresented: $showVision)", field)
        self.assertNotIn("presentationBackground", field)
        self.assertIn("if showVision", field)
        self.assertIn(".transition(.opacity)", field)
        self.assertIn("animation(Theme.Motion.heavy, value: showVision)", field)
        self.assertNotIn(".sheet(isPresented: $scanQR)", comms)
        self.assertNotIn("presentationBackground", comms)
        self.assertIn("if scanQR", comms)
        self.assertIn(".transition(.opacity)", comms)
        self.assertIn("animation(Theme.Motion.heavy, value: scanQR)", comms)
        self.assertNotIn("HoldGlassShell(", turns)
        self.assertIn("prefix(2)", turns)
        shell = read("Blackout", "HoldCard.swift").split("struct HoldGlassShell")[1].split("struct HoldCardView")[0]
        self.assertIn(".transition(.opacity)", shell)
        self.assertIn("animation(Theme.Motion.heavy, value: runtime.showSpeakTurns)", tab)
        pages = next(
            line
            for line in qa.splitlines()
            if "glass HUD pages over the still-mounted map" in line
        )
        self.assertIn("fade", pages.lower())
        self.assertIn("no bounce", pages.lower())
        incoming = next(
            line for line in qa.splitlines() if "Incoming CALL (PTT chip)" in line
        )
        self.assertIn("fade", incoming.lower())
        self.assertNotIn("best in class", field.lower())
        self.assertNotIn("best in class", comms.lower())
        self.assertNotIn(".spring(", field)
        self.assertNotIn(".spring(", comms)
        self.assertNotIn(".spring(", turns)


class FieldHandoffDefersTeardownTests(unittest.TestCase):
    def test_field_on_the_hold_card_does_not_tear_the_card_in_stack(self):
        runtime = read("Blackout", "AppRuntime.swift")
        start = runtime.index("func openFieldFromHold()")
        body = runtime[start : runtime.index("func toggleLockOn()", start)]
        self.assertIn("Task { @MainActor in", body)
        self.assertIn("tab = .field", body)
        self.assertIn("closeHold()", body)
        sync = body.split("Task { @MainActor in", 1)[0]
        self.assertNotIn("tab = .field", sync)
        self.assertNotIn("closeHold()", sync)
        self.assertNotIn("held = nil", sync)


class WholeWordHUDTests(unittest.TestCase):
    def test_overlay_chips_are_the_whole_words(self):
        tab = read("Blackout", "MapTab.swift")
        theme = read("Blackout", "Theme.swift")
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        self.assertIn("BlackoutTokens.MapOverlay.instrumentsTitle", tab)
        self.assertIn("BlackoutTokens.MapOverlay.lockTitle", tab)
        self.assertIn("BlackoutTokens.MapOverlay.godsEyeTitle", tab)
        self.assertIn("BlackoutTokens.MapOverlay.updateTitle", tab)
        self.assertNotIn('Button("INST")', tab)
        self.assertNotIn('"LOCKED" : "LOCK"', tab)
        self.assertNotIn('Button("FIT PACK")', tab)
        self.assertIn("HUDWrapRail", tab)
        self.assertIn("struct HUDWrapRail", theme)
        self.assertIn('instrumentsTitle = "INSTRUMENTS"', tokens)
        self.assertIn('lockOnTitle = "LOCK-ON"', tokens)
        self.assertIn('godsEyeTitle = "KHAN EYE"', tokens)
        self.assertIn('updateTitle = "UPDATE"', tokens)
        self.assertIn(".minimumScaleFactor(1)", read("Blackout", "RootChrome.swift"))
        self.assertNotIn(".minimumScaleFactor(0.55)", read("Blackout", "RootChrome.swift"))

    def test_tab_strip_says_expedition(self):
        runtime = read("Blackout", "AppRuntime.swift")
        self.assertIn('case .expedition: return "EXPEDITION"', runtime)
        self.assertNotIn('case .expedition: return "EXPED"', runtime)


class OtherTabsSpeakHUDTests(unittest.TestCase):
    def test_comms_does_not_dump_whisper_meters(self):
        comms = read("Blackout", "CommsTab.swift")
        self.assertNotIn("Whisper <10 m", comms)
        self.assertNotIn("whisperOK", comms)
        self.assertIn("HUDPage", comms)
        self.assertIn("HOLD PTT", comms)
        self.assertIn("JOIN LOCAL NET", comms)

    def test_field_and_exped_are_glass_pages_not_form_dumps(self):
        field = read("Blackout", "FieldTab.swift")
        exped = read("Blackout", "ExpeditionTab.swift")
        self.assertIn("HUDPage", field)
        self.assertIn("HUDPage", exped)
        self.assertIn('title: "EXPEDITION"', exped)
        self.assertNotIn("No on-device CoreML model ships in this build", field)
        self.assertIn('L10n.t("vision.none"', field)
        self.assertIn("NO VISION MODEL", read("Blackout", "L10n.swift"))

    def test_agents_md_is_the_standing_order_not_a_slogan(self):
        agents = read("AGENTS.md")
        self.assertIn("The quality bar is always on", agents)
        self.assertIn("better method", agents)
        self.assertNotIn("best in class", agents.lower())
        self.assertIn("tf:", agents)
        self.assertIn("CURRENT_PROJECT_VERSION", agents)

    def test_device_script_scores_dest_coords_not_map_bearing(self):
        device = read("docs", "DEVICE.md")
        qa = read("docs", "SOLO_QA.md")
        agents = read("AGENTS.md")
        self.assertNotIn("DEST … · BEARING", device)
        self.assertNotIn("DEST ... · BEARING", device)
        self.assertIn("pin being walked to", device)
        self.assertIn("dest pin coords while navigating", qa)
        self.assertIn("31.76190", device)
        self.assertIn("COORDINATES", device)
        self.assertIn("COORDINATES", qa)
        self.assertIn("31.76190", qa)
        self.assertIn("no `DEST 31.7619, -106.4850`", qa)
        self.assertNotIn("two 44pt chips", device)
        self.assertNotIn("two 44pt chips", qa)
        self.assertNotIn("Dest chips (`BEARING` / `COORDINATES`)", qa)
        self.assertIn("live YOU when idle", qa)
        self.assertIn("Idle MAP with live GNSS prints YOU", device)
        self.assertIn("BEARING", qa)
        self.assertIn("MAP COORDINATES rail prints live YOU", agents)
        self.assertNotIn("MAP dest rail prints dest coordinates", agents)
        self.assertNotIn("BEARING is quiet unless there is somewhere to walk", agents)


class OffGridNoDisclaimerTests(unittest.TestCase):
    """Airplane-mode instrument. Lawyer copy does not belong on the glass."""

    PRODUCT_ROOTS = ("Blackout", "Resources/Field")
    CYA = (
        "does not replace",
        "no reemplaza",
        "what we cannot do",
        "i understand",
        "no 911 auto-dial",
        "eat-from-photo",
        "comer-de-foto",
        "edible unlock",
        "desbloqueo comestible",
        "confidence in the record, not in the water",
        "— not sos",
    )

    def _hits(self, phrase: str) -> list[str]:
        found: list[str] = []
        needle = phrase.lower()
        for rel in self.PRODUCT_ROOTS:
            root = ROOT / rel
            for path in root.rglob("*"):
                if not path.is_file() or path.suffix.lower() not in {".swift", ".json", ".md"}:
                    continue
                if needle in path.read_text(errors="replace").lower():
                    found.append(str(path.relative_to(ROOT)))
        return found

    def test_glass_has_no_cya_copy(self):
        for phrase in self.CYA:
            hits = self._hits(phrase)
            self.assertEqual(hits, [], f"{phrase!r} still in {hits}")
        self.assertFalse((ROOT / "Blackout" / "CannotDoView.swift").exists())
        field = read("Blackout", "FieldTab.swift")
        self.assertNotIn("sos.offer", field)
        self.assertNotIn('L10n.t("sos.call"', field)
        l10n = read("Blackout", "L10n.swift")
        self.assertNotIn("sos.offer", l10n)
        self.assertNotIn("fullScreenCover", read("Blackout", "RootChrome.swift"))
        self.assertNotIn("sawCannotDo", read("Blackout", "AppRuntime.swift"))
        self.assertNotIn("acknowledgeCannotDo", read("Blackout", "AppRuntime.swift"))
        self.assertNotIn("net.physics", read("Blackout", "CommsTab.swift"))
        self.assertIn("NO VISION MODEL", l10n)
        self.assertIn("NET · NONE", l10n)

    def test_agents_says_off_grid_no_disclaimers_take_methods(self):
        agents = read("AGENTS.md")
        lowered = agents.lower()
        self.assertIn("off-grid", lowered)
        self.assertIn("lawyer copy", lowered)
        self.assertIn("from anywhere", lowered)

    def test_solo_qa_activate_goes_to_map(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertNotIn("WHAT WE CANNOT DO", qa)
        self.assertNotIn("I UNDERSTAND", qa)
        self.assertNotIn("Does not replace 911", qa)
        self.assertIn("ACTIVATE", qa)
        self.assertIn("NO VISION MODEL", qa)
        self.assertIn("compass mark", qa.lower())
        self.assertIn("No BLACKOUT as HUD type", qa)
        self.assertIn("covers the page", qa.lower())
        self.assertIn("black stays", qa.lower())
        self.assertNotIn("no black plate", qa.lower())
        self.assertNotIn("streets show through", qa.lower())
        self.assertIn("field poster", qa.lower())


class WaterClassifyOnHoldTests(unittest.TestCase):
    """Hold names the water the packs already carry — not a generic treat line."""

    def test_every_pack_ships_the_water_index(self):
        for pack in ("tx-west", "tx-east", "nm"):
            bin_path = ROOT / "Resources" / "Packs" / pack / "layers" / "water.bin"
            geo = ROOT / "Resources" / "Packs" / pack / "layers" / "water.geojson"
            self.assertTrue(bin_path.is_file(), pack)
            self.assertTrue(geo.is_file(), pack)
            self.assertGreater(bin_path.stat().st_size, 1024, pack)

    def test_hold_reads_the_index_and_speaks_in_classes(self):
        water = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "WaterInspect.swift")
        inspect = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "Inspect.swift")
        runtime = read("Blackout", "AppRuntime.swift")
        hold = read("Blackout", "HoldCard.swift")
        style = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("enum WaterClass", water)
        self.assertIn("TINAJA", water)
        self.assertIn("STOCK TANK", water)
        self.assertIn("ACEQUIA", water)
        self.assertIn("struct WaterIndex", water)
        self.assertIn("func resolve(", inspect + water)
        self.assertIn("doDetail", inspect)
        self.assertIn("streetWaterOverrideMeters", water)
        self.assertIn("WaterIndex", runtime)
        self.assertIn("warmupActiveWater", runtime)
        self.assertIn("func holdInspect(", runtime)
        self.assertIn("zoom: Double", runtime)
        self.assertIn("attachWaterLayers", style)
        self.assertIn("InspectField.label", hold)
        notes = hold.split("if let note")[1].split("Spacer")[0]
        self.assertIn(".lineLimit(6)", notes)
        self.assertNotIn(
            ".lineLimit(4)",
            notes,
            "four lines clips woodland deadfall and wildlife cook-through",
        )
        self.assertIn("FIELD · WATER", water)
        self.assertNotIn("WaterSure.disclaimer", hold)
        self.assertIn("zoom", tab.lower())
        self.assertIn("Dip clear of the churned edge", water)

    def test_solo_qa_scores_the_class_not_a_generic_treat(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("STOCK TANK", qa)
        self.assertIn("TINAJA", qa)
        self.assertIn("nearest water", qa.lower())
        self.assertIn("FIELD · WATER", qa)
        self.assertIn("FIELD · PLANT", qa)
        self.assertIn("FIELD · BITE", qa)
        self.assertIn("FIELD · CAVE", qa)

    def test_hold_overlay_bbox_rejects_before_copying_rings(self):
        """Far sheets must not copy 13k overlay verts onto the HUD per hold."""
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        worked = offline.split("func packWorkedGround(")[1].split(
            "private static func covers(_ feature"
        )[0]
        self.assertIn("groundWorkedSourceID", worked)
        self.assertIn("features(matching: nil)", worked)
        self.assertIn("overlayBounds", worked)
        self.assertIn("MLNCoordinateInCoordinateBounds", worked)
        self.assertNotIn("holdProbePoints", worked)
        covers = offline.split("private static func covers(_ feature")[1].split(
            "func packPoints"
        )[0]
        self.assertIn("getCoordinates", covers)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("bbox-rejects", qa.lower())


def png_ihdr(path: Path) -> tuple[int, int, int]:
    """Return width, height, color type (2 = RGB, 6 = RGBA)."""
    with path.open("rb") as fh:
        if fh.read(8) != b"\x89PNG\r\n\x1a\n":
            raise AssertionError(f"{path} is not a PNG")
        length = int.from_bytes(fh.read(4), "big")
        if fh.read(4) != b"IHDR" or length != 13:
            raise AssertionError(f"{path} missing IHDR")
        data = fh.read(13)
    width = int.from_bytes(data[0:4], "big")
    height = int.from_bytes(data[4:8], "big")
    color = data[9]
    return width, height, color


def _png_paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def png_rgba(path: Path) -> tuple[int, int, bytes]:
    """Decode an 8-bit RGB/RGBA PNG into packed RGBA bytes."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError(f"{path} is not a PNG")
    width = height = bit = color = interlace = None
    idat = bytearray()
    i = 8
    while i + 8 <= len(data):
        length = int.from_bytes(data[i : i + 4], "big")
        ctype = data[i + 4 : i + 8]
        chunk = data[i + 8 : i + 8 + length]
        i += 12 + length
        if ctype == b"IHDR":
            width = int.from_bytes(chunk[0:4], "big")
            height = int.from_bytes(chunk[4:8], "big")
            bit = chunk[8]
            color = chunk[9]
            interlace = chunk[12]
        elif ctype == b"IDAT":
            idat.extend(chunk)
        elif ctype == b"IEND":
            break
    if width is None or height is None or bit != 8 or interlace != 0 or color not in (2, 6):
        raise AssertionError(f"{path} is not an 8-bit RGB/RGBA PNG")
    bpp = 3 if color == 2 else 4
    raw = zlib.decompress(bytes(idat))
    stride = width * bpp
    out = bytearray(width * height * 4)
    prev = bytearray(stride)
    src = 0
    for y in range(height):
        filt = raw[src]
        src += 1
        row = bytearray(raw[src : src + stride])
        src += stride
        if filt == 1:
            for x in range(stride):
                row[x] = (row[x] + (row[x - bpp] if x >= bpp else 0)) & 255
        elif filt == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 255
        elif filt == 3:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
        elif filt == 4:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                up = prev[x]
                ul = prev[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + _png_paeth(left, up, ul)) & 255
        elif filt != 0:
            raise AssertionError(f"{path} has PNG filter {filt}")
        prev = row
        dst = y * width * 4
        if color == 6:
            out[dst : dst + width * 4] = row
        else:
            for x in range(width):
                o = dst + x * 4
                p = x * 3
                out[o : o + 3] = row[p : p + 3]
                out[o + 3] = 255
    return width, height, bytes(out)


def png_px(px: bytes, width: int, x: int, y: int) -> tuple[int, int, int, int]:
    o = (y * width + x) * 4
    return px[o], px[o + 1], px[o + 2], px[o + 3]


def jpeg_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:2] != b"\xff\xd8":
        raise AssertionError(f"{path} is not a JPEG")
    i = 2
    while i + 4 <= len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        while i < len(data) and data[i] == 0xFF:
            i += 1
        marker = data[i]
        i += 1
        if marker in (0xD8, 0xD9, 0x01) or 0xD0 <= marker <= 0xD7:
            continue
        length = int.from_bytes(data[i : i + 2], "big")
        if marker in (0xC0, 0xC1, 0xC2):
            return int.from_bytes(data[i + 5 : i + 7], "big"), int.from_bytes(
                data[i + 3 : i + 5], "big"
            )
        i += length
    raise AssertionError(f"{path} has no SOF")


class CompassMarkTests(unittest.TestCase):
    """Home screen and HUD share the square compass. Black and rays stay."""

    def test_app_icon_is_opaque_1024(self):
        icon = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
        width, height, color = png_ihdr(icon)
        self.assertEqual((width, height), (1024, 1024))
        self.assertEqual(color, 2, "App Store icon must be RGB, no alpha")

    def _assert_mark_keeps_black_and_rays(self, path: Path, *, match_store_rgb: bool) -> None:
        """Leave the black outside. Do not punch rays or metal to alpha."""
        width, height, color = png_ihdr(path)
        self.assertIn(color, (2, 6), f"{path.name} color {color}")
        self.assertEqual(width, height)
        _, _, px = png_rgba(path)
        store = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
        _, _, store_px = png_rgba(store)
        for x, y in (
            (0, 0),
            (width - 1, 0),
            (0, height - 1),
            (width - 1, height - 1),
        ):
            r, g, b, a = png_px(px, width, x, y)
            self.assertEqual(a, 255, f"{path.name} corner {x},{y} punched")
            self.assertLess(max(r, g, b), 12, f"{path.name} corner {x},{y} not black")
        core = png_px(px, width, width // 2, height // 2)
        self.assertGreaterEqual(core[0], 160, f"{path.name} red sight stays")
        self.assertEqual(core[3], 255, f"{path.name} red sight is fully opaque")
        north = png_px(px, width, width // 2, int(height * 80 / 1408))
        self.assertEqual(north[3], 255, f"{path.name} north metal punched")
        self.assertGreaterEqual(max(north[:3]), 140, f"{path.name} north metal gone")
        black_margin = 0
        metal_punched = 0
        outer_lit = 0
        margin = int(48 * width / 1024)
        cx = (width - 1) / 2
        cy = (height - 1) / 2
        ray_r = 430 * width / 1024
        body_r = 400 * width / 1024
        for y in range(0, height, 2):
            for x in range(0, width, 2):
                r, g, b, a = png_px(px, width, x, y)
                rad = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                if a > 200 and max(r, g, b) < 12:
                    if x < margin or y < margin or x >= width - margin or y >= height - margin:
                        black_margin += 1
                if max(r, g, b) >= 40 and rad < body_r and a == 0:
                    metal_punched += 1
                if max(r, g, b) >= 40 and rad > ray_r:
                    outer_lit += 1
        self.assertGreater(black_margin, 0, f"{path.name} black outside was cropped")
        self.assertEqual(metal_punched, 0, f"{path.name} punched metal")
        self.assertGreater(outer_lit, 0, f"{path.name} rays/arrows cropped")
        if match_store_rgb and width == 1024:
            rewritten = 0
            for y in range(0, height, 4):
                for x in range(0, width, 4):
                    r, g, b, a = png_px(px, width, x, y)
                    sr, sg, sb, _ = png_px(store_px, width, x, y)
                    if a == 255 and max(r, g, b) >= 40 and (r, g, b) != (sr, sg, sb):
                        rewritten += 1
            self.assertEqual(rewritten, 0, f"{path.name} rewrote metal")

    def test_home_screen_dark_and_tinted_keep_the_black_plate(self):
        iconset = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset"
        manifest = read("Blackout", "Assets.xcassets", "AppIcon.appiconset", "Contents.json")
        dark = iconset / "AppIcon-dark.png"
        tinted = iconset / "AppIcon-tinted.png"
        width, height, color = png_ihdr(dark)
        self.assertEqual((width, height), (1024, 1024))
        self.assertEqual(color, 6, "dark Home Screen mark has alpha")
        width, height, color = png_ihdr(tinted)
        self.assertEqual((width, height), (1024, 1024))
        self.assertEqual(color, 6, "tinted Home Screen mark has alpha")
        packed = manifest.replace(" ", "")
        self.assertIn('"value":"dark"', packed)
        self.assertIn('"value":"tinted"', manifest.replace(" ", ""))
        self.assertIn("AppIcon-dark.png", manifest)
        self.assertIn("AppIcon-tinted.png", manifest)
        self.assertIn("AppIcon.png", manifest)
        self._assert_mark_keeps_black_and_rays(dark, match_store_rgb=True)
        self._assert_mark_keeps_black_and_rays(tinted, match_store_rgb=False)
        restore = read("tools", "restore_compass_mark.py")
        self.assertNotIn("def knock_plate", restore)

    def test_hud_logo_is_the_square_mark_with_black_outside(self):
        logo_dir = ROOT / "Blackout" / "Assets.xcassets" / "Logo.imageset"
        logo = logo_dir / "Logo.png"
        width, height, color = png_ihdr(logo)
        self.assertEqual(width, height)
        self.assertGreaterEqual(width, 1024)
        self.assertEqual(color, 6, "HUD logo is PNG")
        self.assertFalse((logo_dir / "Logo.jpg").exists())
        manifest = read("Blackout", "Assets.xcassets", "Logo.imageset", "Contents.json")
        self.assertIn("Logo.png", manifest)
        self.assertNotIn("Logo.jpg", manifest)
        theme = read("Blackout", "Theme.swift")
        mark = theme.split("struct HUDMark")[1].split("struct HUDReticle")[0]
        self.assertIn('Image("Logo")', mark)
        self.assertIn("HUDRing(", mark)
        arming = read("Blackout", "ARMINGView.swift")
        self.assertNotIn("1712.0 / 1152.0", arming)
        self.assertNotIn('Text("BLACKOUT")', arming)
        self.assertNotIn("bootLogoSide", arming)
        self.assertNotIn("bootLogoRingDiameter", arming)
        app = read("Blackout", "AppRuntime.swift")
        gnss = app.split("didUpdateLocations")[1].split("didUpdateHeading")[0]
        self.assertIn("CLLocationCoordinate2DIsValid", gnss)
        self._assert_mark_keeps_black_and_rays(logo, match_store_rgb=False)
        qa = read("docs", "SOLO_QA.md")
        self.assertNotIn("outer rays are gone", qa.lower())
        self.assertIn("black stays", qa.lower())
        self.assertNotIn("best in class", qa.lower())


class BootFieldTests(unittest.TestCase):
    """ACTIVATE overlay is the full poster. Black stays. No crop well."""

    def test_boot_field_covers_the_page_and_keeps_black(self):
        field_dir = ROOT / "Blackout" / "Assets.xcassets" / "BootField.imageset"
        field = field_dir / "BootField.png"
        self.assertTrue(field.is_file(), "BootField.png missing")
        width, height, color = png_ihdr(field)
        self.assertIn(color, (2, 6), "field poster is PNG")
        self.assertGreater(height, width)
        self.assertGreaterEqual(width, 1024)
        self.assertFalse((field_dir / "BootField.jpg").exists())
        manifest = read("Blackout", "Assets.xcassets", "BootField.imageset", "Contents.json")
        self.assertIn("BootField.png", manifest)
        self.assertNotIn("BootField.jpg", manifest)
        _, _, px = png_rgba(field)
        for x, y in (
            (0, 0),
            (width - 1, 0),
            (0, height - 1),
            (width - 1, height - 1),
            (48, 48),
        ):
            r, g, b, a = png_px(px, width, x, y)
            self.assertEqual(a, 255, f"field corner {x},{y} punched")
            self.assertLess(max(r, g, b), 12, f"field corner {x},{y} not black")
        sight = png_px(px, width, int(width * 610 / 1152), int(height * 714 / 1712))
        self.assertGreaterEqual(sight[0], 160, "field red sight stays")
        self.assertEqual(sight[3], 255, "field red sight punched")
        metal_count = 0
        punched = 0
        for y in range(0, height, 4):
            for x in range(0, width, 4):
                r, g, b, a = png_px(px, width, x, y)
                if a < 250:
                    punched += 1
                if a >= 230 and max(r, g, b) >= 140:
                    metal_count += 1
        self.assertEqual(punched, 0, "field still knocks black to alpha")
        self.assertGreater(metal_count, 0, "field metal disappeared")
        arming = read("Blackout", "ARMINGView.swift")
        self.assertIn('Image("BootField")', arming)
        self.assertNotIn("1712.0 / 1152.0", arming)
        self.assertNotIn('Text("BLACKOUT")', arming)
        self.assertNotIn("OfflineMapView", arming)
        self.assertNotIn("private var mark", arming)
        self.assertNotIn("private var vignette", arming)
        self.assertNotIn("HUDRing(", arming)
        field_view = arming.split("private var field:")[1].split("private var chrome")[0]
        self.assertIn(".scaledToFit()", field_view)
        self.assertIn(".ignoresSafeArea()", field_view)
        self.assertIn("maxWidth: .infinity", field_view)
        self.assertIn("maxHeight: .infinity", field_view)
        self.assertNotIn(".clipped()", field_view)
        self.assertNotIn("bootLogoSide", field_view)
        self.assertIn("Theme.Motion.heavy", arming)
        self.assertNotIn(".spring(", arming)
        maker = read("tools", "make_boot_field.py")
        self.assertNotIn("boot_field_src.jpg", maker)
        self.assertNotIn("(0, 0, 0, 0)", maker)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("covers the page", qa.lower())
        self.assertIn("black stays", qa.lower())
        self.assertNotIn("streets show through", qa.lower())
        self.assertIn("No BLACKOUT as HUD type", qa)
        self.assertNotIn("fills the well", qa.lower())
        self.assertNotIn("best in class", qa.lower())
        device = read("docs", "DEVICE.md")
        self.assertIn("covers the page", device.lower())
        self.assertNotIn("streets show through", device.lower())
        self.assertNotIn("fills the well", device.lower())


class BootLaunchScreenTests(unittest.TestCase):
    """Cold splash is the same poster on void. No crop well."""

    def test_launch_storyboard_is_the_poster_on_void(self):
        story_path = ROOT / "Blackout" / "LaunchScreen.storyboard"
        self.assertTrue(story_path.is_file(), "LaunchScreen.storyboard missing")
        story = story_path.read_text()
        self.assertIn('image="BootField"', story)
        self.assertIn("scaleAspectFit", story)
        self.assertNotIn("multiplier=", story)
        self.assertIn('red="0"', story)
        self.assertIn('green="0"', story)
        self.assertIn('blue="0"', story)
        self.assertNotIn("systemBlue", story)
        self.assertNotIn("systemBackgroundColor", story)
        self.assertNotIn("UILabel", story)
        self.assertNotIn("BLACKOUT", story)
        self.assertNotIn("best in class", story.lower())
        gen = read("tools", "v3", "generate_project.py")
        pbx = read("Blackout.xcodeproj", "project.pbxproj")
        self.assertIn('"INFOPLIST_KEY_UILaunchStoryboardName": "LaunchScreen"', gen)
        self.assertNotIn("UILaunchScreen_Generation", gen)
        self.assertIn("INFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen;", pbx)
        self.assertNotIn("INFOPLIST_KEY_UILaunchScreen_Generation", pbx)
        arming = read("Blackout", "ARMINGView.swift")
        chrome = arming.split("private var chrome:")[1]
        self.assertIn("ZStack", chrome)
        self.assertIn("alignment: .center", chrome)
        self.assertNotIn("bootLogoSide", arming)


class BootGlassTests(unittest.TestCase):
    """Cold launch is ACTIVATE. No fingerprint lock."""

    def test_cold_launch_is_activate_not_fingerprint(self):
        root = read("Blackout", "RootChrome.swift")
        app = read("Blackout", "AppRuntime.swift")
        pbx = read("Blackout.xcodeproj", "project.pbxproj")
        gen = read("tools", "v3", "generate_project.py")
        qa = read("docs", "SOLO_QA.md")
        self.assertNotIn("UnlockView", root)
        self.assertIn("ARMINGView", root)
        self.assertLess(root.find("ARMINGView"), root.find("tabChrome"))
        self.assertNotIn("runtime.unlocked", root)
        self.assertNotIn("var unlocked", app)
        self.assertNotIn("func requestUnlock", app)
        self.assertNotIn("import LocalAuthentication", app)
        self.assertNotIn("LAContext", app)
        self.assertNotIn("deviceOwnerAuthentication", app)
        self.assertNotIn("UNLOCK FAILED", app)
        self.assertNotIn("func wipeVessel", app)
        self.assertFalse((ROOT / "Blackout" / "UnlockView.swift").is_file())
        self.assertNotIn("NSFaceIDUsageDescription", pbx)
        self.assertNotIn("NSFaceIDUsageDescription", gen)
        self.assertIn("Cold launch is ACTIVATE", qa)
        self.assertIn("No fingerprint", qa)
        self.assertNotIn("UNLOCK FAILED", qa)
        self.assertNotIn("ARE YOU SURE", qa)
        self.assertNotIn("Cold launch is UNLOCK", qa)
        self.assertNotIn("Fingerprint mark", qa)
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("tel://", root.lower())
        self.assertNotIn("Color.green", root)
        self.assertNotIn("Color.orange", root)
        self.assertNotIn(".spring(", root)


class HUDSyncTests(unittest.TestCase):
    """The mark is the instrument — boot, overlay pages, tabs, SOS, instruments."""

    def test_pages_and_instruments_carry_the_mark(self):
        theme = read("Blackout", "Theme.swift")
        self.assertIn("struct HUDMark", theme)
        self.assertIn("struct HUDReticle", theme)
        self.assertIn('Image("Logo")', theme)
        self.assertIn("HUDMark()", theme)
        root = read("Blackout", "RootChrome.swift")
        self.assertIn("HUDReticle(lit:", root)
        self.assertNotIn("frame(width: 18, height: 2)", root)
        inst = read("Blackout", "InstrumentsView.swift")
        self.assertIn("HUDMark()", inst)
        self.assertIn("INSTRUMENTS", inst)
        self.assertIn('Button("CLOSE")', inst)
        self.assertNotIn("NavigationStack", inst)
        self.assertNotIn("pickerStyle", inst)
        self.assertNotIn("Toggle(title, isOn", inst)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("compass mark", qa.lower())
        self.assertIn("reticle", qa.lower())
        self.assertIn("QUIET", qa)

    def test_selected_tab_reticle_glows_red_without_growing(self):
        theme = read("Blackout", "Theme.swift")
        root = read("Blackout", "RootChrome.swift")
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        qa = read("docs", "SOLO_QA.md")
        reticle = theme.split("struct HUDReticle")[1].split("struct HUDDockStyle")[0]
        self.assertIn("hudReticlePoints", reticle)
        self.assertIn("Theme.accent", reticle)
        self.assertIn(".shadow(", reticle)
        self.assertIn("Theme.Motion.beat", reticle)
        self.assertNotIn("crisis ? Theme.accent : Theme.silver", reticle)
        self.assertNotIn("Theme.silver", reticle)
        self.assertNotIn(".spring(", reticle)
        self.assertNotIn("hudMarkPoints", reticle)
        self.assertIn("hudReticlePoints: Double = 10", tokens)
        self.assertIn("hudTabReservePoints: Double = 52", tokens)
        self.assertIn("VStack(spacing: 3)", root)
        self.assertIn("HUDReticle(lit: runtime.tab == t", root)
        tabs = next(
            line for line in qa.splitlines() if "Selected tab is the reticle tick" in line
        )
        self.assertIn("glowing red", tabs)
        self.assertIn("same size", tabs)
        self.assertNotIn("best in class", qa.lower())

    def test_warn_ink_is_one_token(self):
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        self.assertIn("static let warn", tokens)
        for name in (
            "MapTab.swift",
            "CommsTab.swift",
            "FieldTab.swift",
            "ExpeditionTab.swift",
            "Theme.swift",
            "HoldCard.swift",
            "PartyHoldCard.swift",
            "EmblemPickCard.swift",
            "AddressHoldCard.swift",
            "CamHoldCard.swift",
            "NearHoldCard.swift",
            "SOSHold.swift",
            "InstrumentsView.swift",
            "RootChrome.swift",
        ):
            text = read("Blackout", name)
            self.assertNotIn("Color.orange", text, name)
            self.assertNotIn(".foregroundStyle(.red)", text, name)

    def test_sos_iamok_and_hold_are_plates_not_capsules(self):
        sos = read("Blackout", "SOSHold.swift")
        self.assertNotIn("Capsule()", sos)
        self.assertIn("Theme.silver", sos)
        hold = read("Blackout", "HoldCard.swift")
        self.assertNotIn("Capsule()", hold)

    def test_vendor_logo_stays_off_the_canvas(self):
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        tab = read("Blackout", "MapTab.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("logoView.isHidden = true", offline)
        self.assertNotIn("logoView.isHidden = false", offline)
        self.assertIn("attributionButton.isHidden = true", offline)
        self.assertNotIn("OSMCredit.line", tab)
        self.assertNotIn("OpenStreetMap", tab)
        self.assertNotIn("©", tab)
        self.assertIn("No OSM credit", qa)
        self.assertIn("No © OpenStreetMap on the glass", qa)
        self.assertNotIn("`© OpenStreetMap contributors` is visible", qa)

    def test_dock_is_the_token_rail(self):
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("BlackoutTokens.MapDock.allCases", tab)
        self.assertIn("case .mark:", tab)
        self.assertIn("case .walk:", tab)
        self.assertIn("case .drive:", tab)
        self.assertIn("case .speak:", tab)
        self.assertIn("HUDDockStyle(filled:", tab)
        self.assertIn("func dockLive", tab)


YELLOW_AT = 0.45
ORANGE_AT = 0.65
RED_AT = 0.8
BLACK_AT = 1.0
STACK_YELLOW_TO_ORANGE = 2
STACK_YELLOW_TO_RED = 3
STACK_ORANGE_TO_RED = 2
YELLOW_LOAD = 1
ORANGE_LOAD = 2
RED_LOAD = 3
BLACK_LOAD = 4
RAIL_STEPS = (0.0, 0.2, 0.45, 0.65, 0.8, 1.0)
COLOR_STEPS = (0.2, 0.45, 0.65, 0.8, 1.0)


def snap_rail(raw: float) -> float:
    """Mirror of PartyVitals.snap — midpoint and above belongs to the worse tick."""
    clamped = min(1.0, max(0.0, raw))
    for i in range(len(RAIL_STEPS) - 1):
        mid = (RAIL_STEPS[i] + RAIL_STEPS[i + 1]) / 2
        if clamped < mid:
            return RAIL_STEPS[i]
    return RAIL_STEPS[-1]


def band_of(value: float) -> str:
    """Mirror of PartyVitals.band(of:)."""
    if value >= BLACK_AT:
        return "black"
    if value >= RED_AT:
        return "red"
    if value >= ORANGE_AT:
        return "orange"
    if value >= YELLOW_AT:
        return "yellow"
    return "green"


def load_of(value: float) -> int:
    """Mirror of PartyVitals.load(of:)."""
    band = band_of(value)
    if band == "black":
        return BLACK_LOAD
    if band == "red":
        return RED_LOAD
    if band == "orange":
        return ORANGE_LOAD
    if band == "yellow":
        return YELLOW_LOAD
    return 0


def band_from_rails(rails: tuple[float, ...], flags: tuple[str, ...] = ()) -> str:
    """Mirror of PartyVitals.band(rails:flags:). BLACK is the SOS tick, not stacked RED."""
    if any(band_of(value) == "black" for value in rails):
        return "black"
    if "RED" in flags:
        return "red"
    total = 0
    for value in rails:
        piece = load_of(value)
        if piece >= RED_LOAD:
            return "red"
        total += piece
    if total >= STACK_YELLOW_TO_RED:
        return "red"
    if total >= STACK_YELLOW_TO_ORANGE:
        return "orange"
    if total:
        return "yellow"
    return "green"


class ExpeditionHUDTests(unittest.TestCase):
    """EXPEDITION is a HUD, not a Settings energy dump."""

    def test_rail_math_matches_band_edges(self):
        self.assertEqual(snap_rail(-1), 0.0)
        self.assertEqual(snap_rail(0.1), 0.2)
        self.assertEqual(snap_rail(0.32), 0.2)
        self.assertEqual(snap_rail(0.325), 0.45)
        self.assertEqual(snap_rail(0.5), 0.45)
        self.assertEqual(snap_rail(0.625), 0.65)
        self.assertEqual(snap_rail(0.73), 0.8)
        self.assertEqual(snap_rail(0.89), 0.8)
        self.assertEqual(snap_rail(0.9), 1.0)
        self.assertEqual(snap_rail(1.2), 1.0)
        self.assertEqual(band_of(0.2), "green")
        self.assertEqual(band_of(0.449), "green")
        self.assertEqual(band_of(0.45), "yellow")
        self.assertEqual(band_of(0.649), "yellow")
        self.assertEqual(band_of(0.65), "orange")
        self.assertEqual(band_of(0.799), "orange")
        self.assertEqual(band_of(0.8), "red")
        self.assertEqual(band_of(0.999), "red")
        self.assertEqual(band_of(1.0), "black")
        self.assertEqual(load_of(0.45), 1)
        self.assertEqual(load_of(0.65), 2)
        self.assertEqual(load_of(1.0), 4)
        self.assertEqual(band_from_rails((0.2,) * 5), "green")
        self.assertEqual(band_from_rails((0.45, 0.2, 0.2, 0.2, 0.2)), "yellow")
        self.assertEqual(band_from_rails((0.45, 0.45, 0.2, 0.2, 0.2)), "orange")
        self.assertEqual(band_from_rails((0.45, 0.45, 0.45, 0.2, 0.2)), "red")
        self.assertEqual(band_from_rails((0.45,) * 5), "red")
        self.assertEqual(band_from_rails((0.65, 0.2, 0.2, 0.2, 0.2)), "orange")
        self.assertEqual(band_from_rails((0.65, 0.65, 0.2, 0.2, 0.2)), "red")
        self.assertEqual(band_from_rails((0.65, 0.45, 0.2, 0.2, 0.2)), "red")
        self.assertEqual(band_from_rails((0.2, 0.2, 0.2, 0.2, 0.8)), "red")
        self.assertEqual(band_from_rails((0.8, 0.8, 0.2, 0.2, 0.2)), "red")
        self.assertEqual(band_from_rails((0.2, 0.2, 0.2, 0.2, 1.0)), "black")
        self.assertEqual(band_from_rails((1.0,) * 5, ("RED",)), "black")
        self.assertEqual(band_from_rails((0.2,) * 5, ("RED",)), "red")

    def test_condition_rails_not_system_sliders(self):
        exped = read("Blackout", "ExpeditionTab.swift")
        vitals = read("Packages", "Vitals", "Sources", "Vitals", "Vitals.swift")
        for label in ("HUNGER", "THIRST", "PAIN", "FATIGUE", "EXPOSURE"):
            self.assertIn(f'slider("{label}"', exped, label)
        self.assertNotIn('slider("WATER"', exped)
        self.assertNotIn("Slider(", exped)
        self.assertIn("PartyVitals.snap", exped)
        self.assertIn("struct HUDVitalsRail", exped)
        self.assertIn("static let yellowAt", vitals)
        self.assertIn("static let orangeAt", vitals)
        self.assertIn("static let redAt", vitals)
        self.assertIn("static let blackAt", vitals)
        self.assertIn("static let blackLoad", vitals)
        self.assertIn("static let railSteps", vitals)
        self.assertIn("static let colorSteps", vitals)
        self.assertIn("static let railTitles", vitals)
        self.assertIn("func partyAlertLine", vitals)
        self.assertIn("0.45", vitals)
        self.assertIn("0.65", vitals)
        self.assertIn("0.8", vitals)
        self.assertIn("[0,0.2,0.45,0.65,0.8,1.0]", vitals.replace(" ", ""))
        self.assertIn("[0.2,0.45,0.65,0.8,1.0]", vitals.replace(" ", ""))
        self.assertIn("yellow, orange, red, black", vitals)
        self.assertIn("HUNGER", vitals)
        self.assertIn("THIRST", vitals)
        self.assertIn("PAIN", vitals)
        self.assertNotIn('"WATER"', vitals)
        self.assertIn("var water", vitals)
        compact = vitals.replace(" ", "").replace("\n", "")
        self.assertIn("[hunger,thirst,pain,fatigue,weatherExposure]", compact)
        self.assertIn("[hunger,thirst,pain,water,fatigue,weatherExposure]", compact)
        self.assertIn("FATIGUE", vitals)
        self.assertIn("EXPOSURE", vitals)
        self.assertIn("stackYellowToOrange", vitals)
        self.assertIn("stackYellowToRed", vitals)
        self.assertIn("stackOrangeToRed", vitals)
        self.assertIn("= 3", vitals)
        self.assertIn("func load(of", vitals)
        self.assertIn("band(rails:", vitals)
        self.assertIn("band(of:", vitals)
        self.assertNotIn("band(worst:", vitals)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("`HUNGER` / `THIRST` / `PAIN` / `FATIGUE` / `EXPOSURE`", qa)
        self.assertNotIn("`HUNGER` / `THIRST` / `PAIN` / `WATER`", qa)

    def test_red_plate_uses_thirst_not_hidden_water(self):
        red = read("Packages", "RedAlert", "Tests", "RedAlertTests", "RedAlertTests.swift")
        cancel = red.split("func testCancel()")[1].split("func ")[0]
        self.assertIn("thirst: 0.9", cancel)
        self.assertNotIn("water: 0.9", cancel)

    def test_condition_yellow_is_caution_ink_not_silver(self):
        exped = read("Blackout", "ExpeditionTab.swift")
        theme = read("Blackout", "Theme.swift")
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        emit_vitals = read("tools", "v3", "emit_swift.py")
        self.assertIn("case caution", theme)
        self.assertIn("case heat", theme)
        self.assertIn("case go", theme)
        self.assertIn("Theme.caution", theme)
        self.assertIn("Theme.heat", theme)
        self.assertIn("Theme.caution", exped)
        self.assertIn("Theme.heat", exped)
        self.assertIn("Theme.fix", exped)
        self.assertIn("case.go:returnTheme.fix", theme.replace(" ", ""))
        self.assertIn("case.heat:returnTheme.heat", theme.replace(" ", ""))
        self.assertIn("PartyVitals.band(of:", exped)
        self.assertIn("case.green:return.go", exped.replace(" ", ""))
        self.assertIn("case.yellow:return.caution", exped.replace(" ", ""))
        self.assertIn("case.orange:return.heat", exped.replace(" ", ""))
        self.assertIn("case.black:return.sos", exped.replace(" ", ""))
        self.assertIn("case.black:returnTheme.accent", exped.replace(" ", ""))
        self.assertIn('Text("SOS")', exped)
        self.assertIn("PartyVitals.colorSteps", exped)
        self.assertIn("Theme.void", exped)
        self.assertNotIn("value >= PartyVitals.yellowAt { return Theme.warn }", exped)
        self.assertIn("static let caution", tokens)
        self.assertIn("static let heat", tokens)
        self.assertIn("heatHex", tokens)
        self.assertIn("#ED510A", tokens)
        self.assertIn("warn=silver", tokens.replace(" ", ""))
        caution = _rgba(tokens, "caution")
        heat = _rgba(tokens, "heat")
        silver = (0.77, 0.80, 0.84)
        accent = (225.0 / 255.0, 6.0 / 255.0, 0.0)
        self.assertGreater(caution[1], 0.45)
        self.assertGreater(caution[1] - accent[1], 0.4)
        self.assertLess(caution[2], silver[2] / 2)
        self.assertNotEqual(caution[:3], silver)
        self.assertGreater(heat[0], 0.85)
        self.assertLess(heat[1], caution[1])
        self.assertGreater(heat[1], accent[1])
        self.assertNotEqual(heat[:3], caution[:3])
        self.assertNotEqual(heat[:3], accent)
        self.assertNotIn("Color.orange", exped)
        self.assertNotIn("Color.green", exped)
        self.assertNotIn("best in class", exped.lower())
        vitalsSrc = read("Packages", "Vitals", "Sources", "Vitals", "Vitals.swift")
        self.assertNotIn("best in class", vitalsSrc.lower())
        self.assertIn("case .orange", vitalsSrc)
        self.assertIn("yellow, orange, red, black", vitalsSrc)
        self.assertIn("static let blackAt", emit_vitals)
        self.assertIn("func partyAlertLine", emit_vitals)
        self.assertIn("stackYellowToRed", emit_vitals)
        self.assertIn("stackYellowToOrange", emit_vitals)
        self.assertIn("orangeAt", emit_vitals)
        self.assertIn("band(rails:", emit_vitals)
        self.assertIn("func load(of", emit_vitals)
        self.assertIn("twoYellow.band, .orange", emit_vitals)
        self.assertNotIn("twoYellow.band, .yellow", emit_vitals)

    def test_page_sections_and_red_plate(self):
        exped = read("Blackout", "ExpeditionTab.swift")
        theme = read("Blackout", "Theme.swift")
        comms = read("Blackout", "CommsTab.swift")
        self.assertIn("enum HUDStatusTone", theme)
        self.assertIn("case crisis", theme)
        self.assertIn("case caution", theme)
        self.assertIn("case sos", theme)
        self.assertIn("statusTone:", exped)
        self.assertIn("statusTone:", comms)
        self.assertIn("redPlate", exped)
        self.assertNotIn(".title.weight(.bold)", exped)
        self.assertIn("HUDDockStyle()", exped)
        self.assertNotIn('Button("1 MIN TIMER SET")', exped)
        self.assertNotIn('Button("2H WATER TIMER SET")', exped)
        self.assertNotIn('Button("APPLY RED BAND")', exped)
        self.assertNotIn('sectionLabel("RED")', exped)
        self.assertIn("cancelSelfRed", exped)
        self.assertIn('Button("JOIN NAV")', exped)
        self.assertIn('Button("EXPORT PAPER")', exped)
        for section in ("CONDITION", "ROSTER", "TIMERS", "PAPER"):
            self.assertIn(f'sectionLabel("{section}")', exped, section)
        self.assertIn('L10n.t("overdue"', exped)
        self.assertNotIn("not SOS", exped)
        self.assertNotIn("not sos", exped.lower())

    def test_solo_qa_scores_rails_and_hud_red(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("condition rails", qa.lower())
        self.assertIn("HUD RED plate", qa)
        self.assertIn("No APPLY RED BAND under CONDITION", qa)
        self.assertNotIn("APPLY RED BAND with red-band vitals", qa)
        self.assertIn("CANCEL RED", qa)
        self.assertIn("stacked", qa.lower())
        self.assertIn("CONDITION RED", qa)
        self.assertIn("CONDITION ORANGE", qa)
        self.assertIn("CONDITION BLACK", qa)
        self.assertIn("caution ink", qa.lower())
        self.assertIn("heat ink", qa.lower())
        self.assertIn("ORANGE", qa)
        self.assertIn("BLACK", qa)
        self.assertIn("SOS", qa)
        self.assertIn("coordinates", qa.lower())
        self.assertIn("bearing", qa.lower())
        self.assertNotIn("Exposure sliders change CONDITION", qa)
        self.assertNotIn("best in class", qa.lower())


class FieldInstrumentTests(unittest.TestCase):
    """FIELD is the book, not a title list with a STOP-IF caption."""

    def test_open_card_is_the_whole_instrument(self):
        field = read("Blackout", "FieldTab.swift")
        speech = read("Packages", "FieldSpeech", "Sources", "FieldSpeech", "FieldSpeech.swift")
        self.assertIn("s.card.stop_if", field)
        self.assertIn("s.card.situation", field)
        self.assertIn("get_to_care", field)
        self.assertIn("s.step.why", field)
        self.assertIn("s.step.stop", field)
        self.assertIn("tickSeconds", field)
        self.assertIn('L10n.t("stop.if"', field)
        self.assertIn('Button("ALL CARDS")', field)
        open_fn = field.split("private func open(")[1].split("private func sectionLabel")[0]
        self.assertIn("loc(s.card.title)", open_fn)
        self.assertIn("HStack(alignment: .firstTextBaseline)", open_fn)
        self.assertLess(
            open_fn.find("loc(s.card.title)"),
            open_fn.find('Button("ALL CARDS")'),
        )
        self.assertIn("leaveCard()", field)
        self.assertIn("fieldTrail", field)
        self.assertIn("InspectField.nextAction", field)
        self.assertIn('Button("SPEAK")', field)
        self.assertIn('Button("SEND TO PARTY")', field)
        self.assertIn('L10n.t("vision.none"', field)
        self.assertIn("step: s.index", field)
        self.assertIn("step: Int", speech)
        self.assertIn("child.en", speech)
        self.assertIn("child.es", speech)
        self.assertNotIn("ForEach(listCards)", field)
        self.assertIn("openAnswer()", field)
        self.assertIn("onSubmit: openAnswer", field)
        self.assertIn("FieldCorpus.ask(", field)
        self.assertIn("FieldCorpus.asking(", field)
        self.assertIn('HUDField("SEARCH"', field)
        self.assertNotIn("TextField(", field)
        self.assertIn("NO MATCH", field)
        self.assertNotIn("mapSearchHitCap", field)
        search = field.split("private var searchField")[1].split("private func say")[0]
        self.assertIn('Button("SEARCH")', search)
        self.assertIn("openAnswer()", search)
        self.assertIn('submit: "SEARCH"', search)
        self.assertIn('Button("SAY")', field)
        self.assertIn("SAY FAILED", field)
        self.assertIn('sectionLabel("SITUATION")', field)
        self.assertIn('sectionLabel("DO")', field)
        self.assertIn('sectionLabel("GET-TO-CARE")', field)
        self.assertIn('sectionLabel("CAUSE")', field)
        self.assertIn('Button("BACK")', field)
        self.assertIn("FieldTree.decorate(", field)
        self.assertIn("openLink(", field)
        self.assertIn("forkStack", field)
        self.assertNotIn('sectionLabel("CARE")', field)
        self.assertIn("s.step.image", field)
        self.assertIn("Field/images", field)
        self.assertIn("openRoute([first.id]", field)
        self.assertIn("openLive(", field)
        self.assertIn("FieldAsk.answer", field)
        self.assertIn("import FieldAsk", field)
        self.assertIn("ASK · LIVE", field)
        self.assertIn("Task.detached", field)
        self.assertIn("FieldCorpus.doLines", field)
        self.assertIn("s.step.child", open_fn)
        self.assertIn('sectionLabel("HANDS")', open_fn)
        self.assertIn("speakFirst: true", field)
        self.assertIn("TYPE OR SAY", field)
        self.assertNotIn("best in class", field.lower())
        self.assertLess(
            open_fn.find('sectionLabel("DO")'),
            open_fn.find('L10n.t("stop.if"'),
        )
        self.assertLess(open_fn.find("s.step.image"), open_fn.find("FieldCorpus.doLines"))
        self.assertLess(open_fn.find("FieldCorpus.doLines"), open_fn.find("s.step.child"))
        self.assertLess(
            open_fn.find("stepTitle"),
            open_fn.find('L10n.t("stop.if"'),
            "NEXT after DO, not under GET-TO-CARE",
        )
        self.assertLess(
            open_fn.find('Button("SPEAK")'),
            open_fn.find('L10n.t("stop.if"'),
        )
        self.assertGreater(
            open_fn.find("SEND TO PARTY"),
            open_fn.find('sectionLabel("GET-TO-CARE")'),
        )
        self.assertRegex(
            open_fn,
            r"maxHeight:\s*1[0-6]\d",
            "open-card picture must stay short so DO and NEXT fit",
        )
        self.assertNotIn("visionHUD", open_fn)
        body = field.split("var body:")[1].split("private var fieldStatus")[0]
        self.assertNotRegex(
            body,
            r"maxHeight: \.infinity\)\s+visionHUD",
            "VISION is SEARCH-only",
        )

    def test_search_and_say_sit_at_the_end_of_the_bar(self):
        field = read("Blackout", "FieldTab.swift")
        qa = read("docs", "SOLO_QA.md")
        bar = field_search_bar(field)
        self.assertIn('HUDField("SEARCH"', bar)
        self.assertIn('Button("SEARCH")', bar)
        self.assertIn('Button("SAY")', bar)
        self.assertLess(bar.find('HUDField("SEARCH"'), bar.find('Button("SEARCH")'))
        self.assertLess(bar.find('Button("SEARCH")'), bar.find('Button("SAY")'))
        self.assertIn("HUDOverlayChipStyle()", bar)
        search = field.split("private var searchField")[1].split("private func say")[0]
        self.assertLess(search.find("HStack"), search.find('HUDField("SEARCH"'))
        self.assertIn("end of the SEARCH bar", qa)
        self.assertIn("not a second row", qa)
        self.assertNotIn("best in class", qa.lower())

    def test_solo_qa_scores_stop_if_and_step_speak(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("STOP-IF", qa)
        self.assertIn("open step", qa.lower())
        self.assertIn("VISION captures one still", qa)
        self.assertIn("VISION stays on SEARCH", qa)
        self.assertIn("NEXT sits after DO", qa)
        self.assertIn("NO MATCH", qa)
        self.assertIn("FIELD SEARCH", qa)
        self.assertIn("GET-TO-CARE", qa)
        self.assertIn("SAY", qa)


class CommsInstrumentTests(unittest.TestCase):
    """Party chips that already exist in L10n belong on the rail."""

    def test_party_chip_rail_is_complete(self):
        comms = read("Blackout", "CommsTab.swift")
        state = read("Packages", "CommsUI", "Sources", "CommsUI", "CommsUI.swift")
        self.assertIn('L10n.t("form.up"', comms)
        self.assertIn('L10n.t("lost.kid"', comms)
        self.assertIn('L10n.t("chip.wait"', comms)
        self.assertIn('L10n.t("chip.water"', comms)
        self.assertIn('L10n.t("chip.rally"', comms)
        self.assertIn('L10n.t("chip.down"', comms)
        self.assertIn("func wait()", state)
        self.assertIn("func water()", state)
        self.assertIn("HOLD PTT", comms)
        self.assertIn("JOIN LOCAL NET", comms)
        self.assertIn("LISTEN", comms)
        self.assertIn("QUIET", comms)
        self.assertIn('Button("SCAN")', comms)
        self.assertNotIn('Button("SCA")', comms)
        self.assertNotIn("Whisper <10 m", comms)

    def test_call_is_a_hold_and_the_net_can_leave(self):
        comms = read("Blackout", "CommsTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        ptt = read("Packages", "PTTAudio", "Sources", "PTTAudio", "PTTAudio.swift")
        mic = read("Blackout", "PTTMic.swift")
        scan = read("Blackout", "PartyJoin.swift")
        self.assertIn("LEAVE NET", comms)
        self.assertIn("DragGesture", comms)
        self.assertIn("endPTTSolo()", comms)
        self.assertIn("beginPTTSolo()", comms)
        self.assertIn("captureClip()", comms)
        self.assertIn("radioCheckParty()", comms)
        self.assertIn("RADIO CHECK", comms)
        self.assertIn('sectionLabel("CALL")', comms)
        self.assertIn('sectionLabel("CHIPS")', comms)
        self.assertIn("MIC DENIED", app)
        self.assertIn("sendVoice", app)
        self.assertIn('chip: "ptt"', app)
        self.assertIn("recordClip", app)
        self.assertIn("listening", mesh)
        self.assertIn("sendVoice", mesh)
        self.assertNotIn("Data(repeating: 0", comms)
        self.assertNotIn("Data(repeating: 0", app)
        self.assertNotIn("AVAudioEngine", ptt)
        self.assertNotIn("import AVFoundation", ptt)
        self.assertIn("AVAudioRecorder", mic)
        self.assertIn("CLOSE", scan)
        self.assertNotIn("NET JOINED", comms)
        pcm = mic.split("private func pcm(")[1].split("private static func wav")[0]
        self.assertIn("channelCount >= 1", pcm)
        self.assertIn("int16ChannelData", pcm)

    def test_solo_qa_scores_form_up_and_lost_kid(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("WRITE NOTE", qa)
        self.assertIn("FORM UP", qa)
        self.assertIn("LOST KID", qa)
        self.assertIn("LEAVE NET", qa)
        self.assertIn("MIC DENIED", qa)
        self.assertIn("hold, not a tap", qa.lower())


class InstrumentsSunTorchTests(unittest.TestCase):
    """BODY and SUN are instruments, not a settings dump."""

    def test_sun_and_torch_are_on_the_sheet(self):
        inst = read("Blackout", "InstrumentsView.swift")
        runtime = read("Blackout", "AppRuntime.swift")
        almanac = read("Packages", "Almanac", "Sources", "Almanac", "Almanac.swift")
        self.assertIn("Almanac.sun", inst)
        self.assertIn("RISE", inst)
        self.assertIn("SET", inst)
        sun = inst.split("private var sunPlate")[1].split("private func sectionLabel")[0]
        self.assertIn("fieldYou", sun)
        self.assertIn("home", sun)
        self.assertIn('Button("SOS FLASHLIGHT")', inst)
        self.assertIn("tapSOSFlashlight()", inst)
        self.assertIn("func tapSOSFlashlight()", runtime)
        self.assertIn("setTorchModeOn", runtime)
        self.assertIn("func clock(", almanac)
        self.assertNotIn('Button("TORCH 3×")', inst)
        self.assertNotIn("Screen buffer OFF default", inst)

    def test_sos_flashlight_is_itu_morse_not_a_dimmer(self):
        on_units = [u for on, u in sos_flash_cycle() if on]
        self.assertEqual(on_units, [1, 1, 1, 3, 3, 3, 1, 1, 1])
        self.assertEqual(sos_flash_cycle()[-1], (False, 7))
        self.assertEqual(sum(u for on, u in sos_flash_cycle() if on), 15)
        board = read(
            "Packages", "Instruments", "Sources", "Instruments", "Instruments.swift"
        )
        app = read("Blackout", "AppRuntime.swift")
        inst = read("Blackout", "InstrumentsView.swift")
        root = read("Blackout", "RootChrome.swift")
        self.assertIn("enum SOSFlash", board)
        self.assertIn("static let unitMs: Double = 250", board)
        self.assertIn("static let cycleUnits", board)
        for on, units in sos_flash_cycle():
            self.assertIn(f"({str(on).lower()}, {units})", board)
        self.assertIn("var sosFlash: Bool", board)
        self.assertIn("func sosFlashTap()", board)
        self.assertIn("state.sosFlash.toggle()", board)
        tap = app.split("func tapSOSFlashlight()")[1].split("func ", 1)[0]
        self.assertIn("instruments.sosFlashTap()", tap)
        self.assertNotIn("offerSOS()", tap)
        self.assertNotIn("torchClicks", tap)
        self.assertIn("setTorchModeOn(level: 1)", app)
        self.assertIn("signaling:", app.split("func applyMapKeepAwake()")[1].split("func ", 1)[0])
        self.assertIn("var sosFlashLit", app)
        self.assertIn("sosFlashLit", root)
        self.assertIn("SOS FLASHLIGHT", root)
        self.assertIn("LAMP · NONE", inst)
        self.assertIn("SOS · SCREEN", inst)
        self.assertNotIn("best in class", board.lower())
        self.assertNotIn("best in class", app.lower())
        self.assertNotIn("Waze", app)
        keep = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        ).split("enum MapKeepAwake")[1].split("enum MapCanvasHit")[0]
        self.assertIn("signaling: Bool", keep)
        self.assertIn("if signaling { return true }", keep)

    def test_solo_qa_scores_sun_and_torch(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("RISE", qa)
        self.assertIn("SOS FLASHLIGHT", qa)
        self.assertIn("Morse", qa)
        self.assertIn("POCKET", qa)
        self.assertNotIn("TORCH 3×", qa)
        self.assertNotIn("best in class", qa.lower())


class MapMarksGlassTests(unittest.TestCase):
    """Persisted marks are a DEST list on the canvas, 44pt, no scroll."""

    def test_marks_and_hits_are_44pt(self):
        tab = read("Blackout", "MapTab.swift")
        sos = read("Blackout", "SOSHold.swift")
        self.assertIn("runtime.marks", tab)
        self.assertIn("pickDestination(lat: m.lat, lon: m.lon)", tab)
        self.assertIn("mapChipHitPoints", tab)
        self.assertNotIn("minHeight: 36", tab)
        self.assertNotIn('Button("FIT PACK")', tab)
        self.assertIn("HUDOverlayChipStyle()", tab)
        self.assertIn("mapChipHitPoints", sos)
        self.assertIn("PlaceMarkCard(", tab)
        self.assertIn("runtime.eyeCanvasPips()", tab)
        self.assertIn("PlaceMark.body", read("Blackout", "AppRuntime.swift"))


class PartyPlaceMarkTests(unittest.TestCase):
    """MARK names a party place, writes a note, and plants a FACE emblem."""

    def test_mark_composer_names_notes_and_plants_face(self):
        marks = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        app = read("Blackout", "AppRuntime.swift")
        tab = read("Blackout", "MapTab.swift")
        card = read("Blackout", "PlaceMarkCard.swift")
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        emblem = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "PersonEmblem.swift"
        )
        qa = read("docs", "SOLO_QA.md")
        tests = ROOT.joinpath("Packages", "MapLibreMap", "Tests")
        count = 0
        for path in tests.rglob("*.swift"):
            count += len(re.findall(r"func test[A-Z]\w+\(", path.read_text()))
        self.assertEqual(count, 177)
        self.assertIn("var name: String", marks)
        self.assertIn("var note: String", marks)
        self.assertIn("var emblem: String", marks)
        self.assertIn("decodeIfPresent", marks)
        self.assertIn("enum PlaceMark", marks)
        self.assertIn('idPrefix = "MARK·"', marks)
        self.assertIn("static func upsert(", marks)
        self.assertIn("func merging(", marks)
        self.assertIn("func openMark(", app)
        self.assertIn("func commitMark(", app)
        self.assertIn("func holdPlaceMark(", app)
        self.assertIn("var markDraft", app)
        self.assertIn("var heldMark", app)
        self.assertIn("mesh.sendMark(", app)
        self.assertIn("case \"mark\":", app)
        self.assertIn("dropMark()", app)
        self.assertIn("PlaceMarkCard(", tab)
        self.assertIn("runtime.eyeCanvasPips()", tab)
        self.assertIn("PlaceMark.body", app)
        self.assertIn("EmblemFaceGrid(", card)
        self.assertIn('HUDField("NAME"', card)
        self.assertIn('HUDField("NOTE"', card)
        self.assertIn('Button("DROP")', card)
        self.assertIn("COORDINATES", card)
        self.assertIn("locked: true", card)
        self.assertNotIn("TextField(", card)
        self.assertNotIn(".spring(", card)
        self.assertNotIn("Color.orange", card)
        self.assertNotIn("best in class", card.lower())
        self.assertIn("PersonEmblem.allCases", emblem)
        self.assertIn("case hawk", emblem)
        self.assertIn("kind: \"mark\"", mesh)
        self.assertIn("enum MeshMarkBody", mesh)
        self.assertIn("func sendMark(", mesh)
        mark_line = next(
            line
            for line in qa.splitlines()
            if "NAME, NOTE, FACE" in line or ("MARK" in line and "FACE" in line)
        )
        self.assertIn("NAME", mark_line)
        self.assertIn("NOTE", mark_line)
        self.assertIn("FACE", mark_line)
        self.assertIn("DROP", mark_line)
        self.assertIn("emblem", mark_line.lower())
        self.assertIn("party", mark_line.lower())
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)
        self.assertIn("PlaceMark.parse", app)

    def test_mark_names_a_dest_for_the_party_not_the_fix_or_a_hold(self):
        app = read("Blackout", "AppRuntime.swift")
        tab = read("Blackout", "MapTab.swift")
        hold = read("Blackout", "HoldCard.swift")
        marks = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        qa = read("docs", "SOLO_QA.md")
        drop = app.split("func dropMark()")[1].split("func ", 1)[0]
        self.assertIn("routeTarget", drop)
        self.assertIn("PlaceMark.setDest", drop)
        self.assertNotIn("fix.last", drop)
        self.assertNotIn("lastKnownFix", drop)
        self.assertNotIn("center.lat", drop)
        self.assertNotIn("fix.arm()", drop)
        self.assertIn("runtime.dropMark()", tab)
        self.assertIn("pickDestination(lat: lat, lon: lon)", tab)
        self.assertIn("static let setDest", marks)
        self.assertIn('setDest = "SET DEST"', marks)
        view = hold.split("struct HoldCardView")[1]
        self.assertIn("InspectField.label", view)
        self.assertIn("if held.marked", view)
        self.assertIn("onMark", view)
        self.assertIn('Button("MARK")', view)
        self.assertNotIn("dropMark", view)
        self.assertNotIn("openMark", view)
        self.assertNotIn("MARKED", hold)
        self.assertIn("holdCardMaxActions: Int = 1", tokens)
        self.assertIn("func markHeldAddress(", app)
        mark_line = next(
            line
            for line in qa.splitlines()
            if "NAME, NOTE, FACE" in line or ("MARK" in line and "FACE" in line)
        )
        self.assertIn("one mark = one row", mark_line.lower())
        self.assertIn("party", mark_line.lower())
        self.assertIn("DEST", mark_line)
        self.assertIn("long-press", mark_line.lower())
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)
        self.assertNotIn("Google", drop)


    def test_kit_trip_and_paper_are_on_glass(self):
        exped = read("Blackout", "ExpeditionTab.swift")
        self.assertIn('sectionLabel("INVENTORY")', exped)
        self.assertNotIn('sectionLabel("KIT")', exped)
        self.assertIn('sectionLabel("DIARY")', exped)
        self.assertNotIn('sectionLabel("TRIP")', exped)
        self.assertIn("runtime.kit", exped)
        self.assertIn("runtime.diary", exped)
        self.assertIn('Button("EXPORT PAPER")', exped)
        self.assertIn("paperText", exped)
        self.assertIn("PaperGen.export", exped)

    def test_kit_names_counts_and_assigns_to_profile(self):
        kit = read("Packages", "KitStore", "Sources", "KitStore", "KitStore.swift")
        exped = read("Blackout", "ExpeditionTab.swift")
        card = read("Blackout", "PartyHoldCard.swift")
        app = read("Blackout", "AppRuntime.swift")
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("var count: Int", kit)
        self.assertIn("var assignedTo: String?", kit)
        self.assertIn("func bump(", kit)
        self.assertIn("func assign(", kit)
        self.assertIn("func addNamed(", kit)
        self.assertIn("func assigned(", kit)
        self.assertIn('HUDField("ITEM"', exped)
        self.assertNotIn("TextField(", exped)
        self.assertIn('Button("ADD")', exped)
        inv = exped.split('sectionLabel("INVENTORY")')[1].split('sectionLabel("DIARY")')[0]
        self.assertIn("NAME ITEM", inv)
        self.assertIn("kitChrome", inv)
        item = inv.split('HUDField("ITEM"')[1].split(")")[0]
        self.assertIn("submit:", item)
        self.assertIn("locked:", item)
        self.assertLess(
            item.find("submit:"),
            item.find("locked:"),
            "HUDField init requires submit before locked",
        )
        self.assertIn('Button("+1")', exped)
        self.assertIn('Button("−1")', exped)
        self.assertIn("runtime.bumpKit(", exped)
        self.assertIn("Inspect.holdSeconds", exped)
        self.assertIn("LongPressGesture", exped)
        self.assertIn("assignKitItem", exped)
        self.assertIn("INVENTORY", card)
        self.assertIn("kitItems", card)
        self.assertIn("kitSeq", card)
        self.assertIn("onKitBump", card)
        self.assertIn('Button("+1")', card)
        self.assertIn('Button("−1")', card)
        self.assertIn('Text("NONE")', card)
        self.assertIn("func assignKitItem(", app)
        self.assertIn("func bumpKit(", app)
        self.assertIn("func addKitItem(", app)
        self.assertIn("var kitSeq", app)
        bump = app.split("func bumpKit(")[1].split("func syncKit(")[0]
        self.assertIn("kitSeq += 1", bump)
        self.assertIn("kitSeq += 1", app.split('case "kit":')[1].split("case ")[0])
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("onKitBump:", tab)
        self.assertIn("kitSeq: runtime.kitSeq", tab)
        self.assertIn('Button("NONE")', exped)
        self.assertIn("func sendKit(", mesh)
        self.assertIn('kind: "kit"', mesh)
        self.assertIn('case "kit":', app)
        self.assertIn("INVENTORY", qa)
        self.assertIn("NAME ITEM", qa)
        self.assertNotIn("KIT names", qa)
        self.assertIn("ASSIGN", qa)
        self.assertIn("+1", qa)
        self.assertIn("profile glass", qa)
        self.assertIn("using equipment", qa)
        self.assertNotIn("best in class", kit.lower())
        self.assertNotIn("best in class", exped.lower())
        self.assertNotIn("tel://", exped.lower())
        self.assertNotIn("Color.orange", exped)
        self.assertNotIn("Color.green", exped)

    def test_default_inventory_is_water_at_zero(self):
        app = read("Blackout", "AppRuntime.swift")
        qa = read("docs", "SOLO_QA.md")
        bag = app.split("var kit = KitBag")[1].split("var power")[0]
        self.assertEqual(bag.count("GearItem("), 1)
        self.assertIn('id: "water"', bag)
        self.assertIn('name: "Water"', bag)
        self.assertIn("count: 0", bag)
        self.assertNotIn("Water filter", bag)
        self.assertNotIn("Headlamp", bag)
        self.assertNotIn("Water filter", app)
        self.assertNotIn("Headlamp", app)
        self.assertIn("Default inventory is Water at 0", qa)
        self.assertNotIn("Water filter", qa)
        self.assertNotIn("Headlamp", qa)


class HoldRenderHarnessReuseTests(unittest.TestCase):
    """Simulator CI aborted MapLibreMapTests at ~160/175 after packing more
    Holds into one XCTest process. Each hold booted a fresh MLNMapView.
    Reuse the renderer per style URL so the 175 tests can finish.
    """

    def test_render_harness_reuses_the_map_per_style(self):
        harness = read(
            "Packages", "MapLibreMap", "Tests", "MapLibreMapTests", "RenderHarness.swift"
        )
        glass = read(
            "Packages",
            "MapLibreMap",
            "Tests",
            "MapLibreMapTests",
            "HoldOnTheGlassTests.swift",
        )
        self.assertIn("static var boots", harness)
        self.assertIn("boots[style]", harness)
        self.assertIn("func reset()", harness)
        self.assertIn("watcher.reset()", harness)
        self.assertNotIn(
            "window.isHidden = true",
            harness,
            "tearing the window down after every hold is the 160/175 abort",
        )
        self.assertIn("override var executionTimeAllowance", glass)


class ExpeditionNamedTimerTests(unittest.TestCase):
    def test_named_group_timers_show_progress_on_profile(self):
        timers = read("Packages", "TimerSync", "Sources", "TimerSync", "TimerSync.swift")
        exped = read("Blackout", "ExpeditionTab.swift")
        card = read("Blackout", "PartyHoldCard.swift")
        app = read("Blackout", "AppRuntime.swift")
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("func remaining(", timers)
        self.assertIn("func remainingFraction(", timers)
        self.assertIn("func onProfile(", timers)
        self.assertIn('HUDField("NAME"', exped)
        self.assertIn('HUDField("TIME"', exped)
        self.assertIn('Button("SET")', exped)
        self.assertIn('Button("30 MIN")', exped)
        self.assertIn('Button("1 HR")', exped)
        self.assertIn('Button("2 HRS")', exped)
        self.assertNotIn('Button("1 MIN")', exped)
        self.assertNotIn('Button("5 MIN")', exped)
        self.assertNotIn('Button("2H")', exped)
        self.assertNotIn('Button("1 MIN TIMER SET")', exped)
        self.assertNotIn('Button("2H WATER TIMER SET")', exped)
        block = exped.split('sectionLabel("TIMERS")')[1].split('sectionLabel("INVENTORY")')[0]
        self.assertLess(block.find('HUDField("NAME"'), block.find('HUDField("TIME"'))
        self.assertLess(block.find('HUDField("TIME"'), block.find('Button("30 MIN")'))
        self.assertLess(block.find('Button("30 MIN")'), block.find('Button("1 HR")'))
        self.assertLess(block.find('Button("1 HR")'), block.find('Button("2 HRS")'))
        self.assertLess(block.find('Button("2 HRS")'), block.find('Button("SET")'))
        self.assertIn('timerTime = "30"', block)
        self.assertIn('timerTime = "1H"', block)
        self.assertIn('timerTime = "2H"', block)
        self.assertIn("digits: true", block)
        self.assertIn("TimerDuration.parse", exped)
        self.assertIn("timerTime", exped)
        self.assertIn("SET TIME", block)
        self.assertIn("timerChrome", block)
        self.assertIn("timerSeq", exped)
        self.assertIn("timerWho(", exped)
        self.assertIn("remainingFraction", exped)
        self.assertIn("onProfile(", card)
        self.assertIn("profileTimers", card)
        self.assertIn("timerSeq", card)
        self.assertIn("func addPartyTimer(", app)
        self.assertIn("var timerSeq", app)
        self.assertIn("sendTimer", app)
        self.assertIn("finishPartyTimer", exped)
        self.assertIn("owner:", app.split("func addPartyTimer(")[1].split("func bumpKit(")[0])
        self.assertIn("var owner: String", timers)
        self.assertIn("enum TimerDuration", timers)
        self.assertIn("static func parse(", timers)
        parse = timers.split("enum TimerDuration")[1].split("public final class TimerBoard")[0]
        self.assertIn("* 60", parse)
        self.assertIn("* 3600", parse)
        self.assertIn("MeshTimerBody", mesh)
        self.assertIn("duration:", app.split("case \"timer.set\"")[1].split("case ")[0])
        self.assertIn("NAME + TIME + SET", qa)
        self.assertIn("SET TIME", qa)
        self.assertIn("30 MIN", qa)
        self.assertIn("1 HR", qa)
        self.assertIn("2 HRS", qa)
        self.assertIn("remaining bar", qa)
        self.assertIn("TIME", qa)
        self.assertIn("under the name", qa.lower())
        self.assertNotIn("1 MIN TIMER SET", qa)
        self.assertNotIn("2H WATER TIMER SET", qa)
        self.assertNotIn("NAME + 1 MIN / 5 MIN / 2H + SET", qa)
        self.assertNotIn("best in class", timers.lower())
        self.assertNotIn("best in class", exped.lower())
        self.assertNotIn("best in class", card.lower())
        self.assertNotIn(".spring(", exped)
        self.assertNotIn("tel://", exped.lower())


class VisionInstrumentTests(unittest.TestCase):
    """One still. Pack-book name or UNKNOWN. Never hash-to-label. Never edible."""

    def test_field_has_hud_capture_not_a_fake_id(self):
        field = read("Blackout", "FieldTab.swift")
        vis = read("Packages", "VisionCoreML", "Sources", "VisionCoreML", "VisionCoreML.swift")
        still = read("Blackout", "VisionStill.swift")
        self.assertIn('Button("VISION")', field)
        self.assertIn("VisionStill", field)
        self.assertIn('L10n.t("vision.none"', field)
        self.assertIn('L10n.t("vision.leave"', field)
        self.assertNotIn("VISION ADD FRAME", field)
        self.assertNotIn("g.percent", field)
        self.assertNotIn("edible=", field)
        self.assertNotIn("honesty", field)
        self.assertIn("classify(observations:", vis)
        self.assertIn("onDeviceModelPresent = false", vis)
        self.assertIn("NO VISION MODEL", vis)
        self.assertNotIn("hashValue", vis)
        self.assertIn("unknownGuess", vis)
        self.assertIn("noModelGuess", field)
        self.assertIn("LEAVE IT", vis + field + read("Blackout", "L10n.swift"))
        self.assertIn("VNClassifyImageRequest", still)
        self.assertNotIn("import VisionCoreML", still)
        self.assertNotIn("VisionCoreML.VisionObservation", still)
        self.assertIn("struct SystemVisionHit", still)
        self.assertIn("VisionObservation(identifier:", field)
        self.assertIn("AVCapturePhotoOutput", still)
        self.assertIn("CAPTURE", still)
        self.assertIn("requestAccess", still)
        self.assertIn("Vision/labels.tx.json", read("tools", "copy_resources.sh"))
        classify = vis.split("func classify(observations:")[1].split("func lookalikeWord")[0]
        self.assertNotIn("return sealed(hit)", classify)
        self.assertIn("specificity(", classify)
        self.assertNotIn("prefix(8)", still)
        shoot = still.split("func shoot()")[1].split("func photoOutput")[0]
        self.assertNotIn("failClosed()", shoot)
        self.assertIn("session.isRunning", shoot)
        self.assertIn("sessionQueue", still)
        self.assertIn("beginConfiguration", still)
        self.assertIn("commitConfiguration", still)
        start = still.split("func startSession")[1].split("func installChrome")[0]
        self.assertIn("canAddOutput", start)
        self.assertIn("failClosed()", start)

    def test_matcher_needles_are_in_the_package(self):
        vis = read("Packages", "VisionCoreML", "Sources", "VisionCoreML", "VisionCoreML.swift").lower()
        for needle in (
            "mushroom",
            "cactus",
            "rattlesnake",
            "coyote",
            "yucca",
            "unknown",
            "succulent",
            "saguaro",
            "peccary",
            "boar",
            "scorpion",
            "wasp",
            "bee",
            "alligator",
            "lake",
            "fox",
            "bobcat",
            "wildfire",
            "flood",
            "lightning",
            "smoke",
            "tent",
            "laceration",
        ):
            self.assertIn(needle, vis, needle)
        self.assertIn("func hasphrase", vis)
        self.assertIn("kind:sting", vis)
        self.assertIn("kind:gator", vis)
        self.assertIn("kind:water", vis)

    def test_matcher_ranks_sting_gator_water_and_refuses_substring_traps(self):
        vis = read("Packages", "VisionCoreML", "Sources", "VisionCoreML", "VisionCoreML.swift")
        needles = _vision_kind_needles(vis)
        kinds = {kind for kind, _ in needles}
        self.assertIn("sting", kinds)
        self.assertIn("gator", kinds)
        self.assertIn("water", kinds)
        self.assertIn("mammal", kinds)
        self.assertEqual(_vision_kind(needles, "Scorpion"), "sting")
        self.assertEqual(_vision_kind(needles, "Wasp"), "sting")
        self.assertEqual(_vision_kind(needles, "American alligator"), "gator")
        self.assertEqual(_vision_kind(needles, "Lake"), "water")
        self.assertEqual(_vision_kind(needles, "Body of water"), "water")
        self.assertEqual(_vision_kind(needles, "Red fox"), "mammal")
        self.assertIsNone(_vision_kind(needles, "Hedgehog"))
        self.assertIsNone(_vision_kind(needles, "Porcupine"))
        self.assertIsNone(_vision_kind(needles, "Street"))
        self.assertIsNone(_vision_kind(needles, "Springfield"))
        self.assertIsNone(_vision_kind(needles, "Campfire"))
        self.assertEqual(_vision_kind(needles, "Laceration"), "wound")
        self.assertEqual(_vision_kind(needles, "Wildfire"), "fire")
        self.assertEqual(
            _vision_best(needles, [("Tree", 0.9), ("Wasp", 0.3)]),
            "sting",
        )
        self.assertEqual(
            _vision_best(needles, [("Tree", 0.85), ("Lake", 0.4)]),
            "water",
        )
        self.assertEqual(
            _vision_best(needles, [("Tree", 0.7), ("American alligator", 0.4)]),
            "gator",
        )
        tests = read(
            "Packages",
            "VisionCoreML",
            "Tests",
            "VisionCoreMLTests",
            "VisionCoreMLTests.swift",
        )
        for name in (
            "testScorpionIsStingLeaveIt",
            "testWaspBeatsATreeOnTheSameStill",
            "testAlligatorIsGatorLeaveIt",
            "testLakeIsWaterNotLeaveIt",
            "testWildfireIsFireLeaveIt",
            "testFloodBeatsATreeOnTheSameStill",
            "testLightningIsLeaveIt",
            "testCampfireIsNotFire",
            "testLacerationIsWoundLeaveIt",
            "testHedgehogIsNotAMammal",
            "testPorcupineIsNotAPineOrATree",
            "testStreetIsNotATree",
        ):
            self.assertIn(name, tests, name)

    def test_vision_speaks_the_guess_and_the_walk(self):
        field = read("Blackout", "FieldTab.swift")
        vis_btn = field.split("func visionFieldButton", 1)[1].split("func applyVision", 1)[0]
        self.assertIn("speakFirst: true", vis_btn)
        apply = field.split("func applyVision", 1)[1].split("private func loc", 1)[0]
        self.assertIn("runtime.speech.speak", apply)
        self.assertIn("SPEECH FAILED", apply)
        self.assertIn('L10n.t("vision.leave"', apply)
        self.assertIn('L10n.t("vision.none"', apply)
        status = field.split("private var fieldStatus", 1)[1].split("private var fieldTone", 1)[0]
        self.assertIn('speechChrome == "SPEECH FAILED"', status)

    def test_generic_wood_is_not_a_tree_name(self):
        vis = read("Packages", "VisionCoreML", "Sources", "VisionCoreML", "VisionCoreML.swift")
        self.assertIn("genericIdents", vis)
        self.assertIn('"wood"', vis)

    def test_qr_scan_does_not_set_missing_metadata_types(self):
        scan = read("Blackout", "PartyJoin.swift")
        self.assertIn("availableMetadataObjectTypes", scan)
        self.assertIn("sessionQueue", scan)

    def test_solo_qa_scores_a_still_not_a_percent(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("VISION captures one still", qa)
        self.assertIn("UNKNOWN", qa)
        self.assertIn("LEAVE IT", qa)
        self.assertIn("NO VISION MODEL", qa)
        self.assertIn("No percent", qa)
        self.assertIn("VISION speaks the name", qa)
        self.assertIn("scorpion still is bite", qa)
        self.assertIn("lake still is water", qa)
        self.assertIn("alligator still is animal", qa)
        self.assertIn("FIELD · WATER", qa)
        self.assertIn("Hedgehog is not hog", qa)


class HonestyOnTheGlassTests(unittest.TestCase):
    """A tap draws, or it says why not. Vendor chrome stays off the canvas."""

    def test_call_fail_closed_clip_armed_and_one_to_one_needs_a_peer(self):
        comms = read("Blackout", "CommsTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        scan = read("Blackout", "PartyJoin.swift")
        start = app.index("func beginPTTSolo()")
        body = app[start : app.index("func endPTTSolo()")]
        self.assertGreater(body.index("ptt.beginLive()"), body.index("PTTMic.shared.arm"))
        self.assertIn('chip: "ptt"', body)
        self.assertIn("var clipLive", app)
        self.assertIn("RECORDING", comms)
        self.assertIn("CAMERA DENIED", comms)
        self.assertIn("onFail", scan)
        self.assertIn("failClosed", scan)
        self.assertIn("NO PEERS", comms)
        self.assertNotIn(".prefix(6)", comms)
        send = app.split("func sendPartyNote")[1].split("func partyCourse")[0]
        self.assertIn("WRITE NOTE", send)
        self.assertIn("commsChrome", send)
        self.assertIn("if runtime.sendPartyNote", comms)

    def test_field_empty_and_join_nav_say_why(self):
        field = read("Blackout", "FieldTab.swift")
        exped = read("Blackout", "ExpeditionTab.swift")
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        still = read("Blackout", "VisionStill.swift")
        self.assertIn("FIELD BOOK · NONE", field)
        self.assertIn("guess = nil", field)
        self.assertIn("NAV · SEATED", exped)
        self.assertIn("func clearInboundChip", mesh)
        self.assertIn("greaterThanOrEqualToConstant: 44", still)

    def test_instruments_and_rails_are_stamps(self):
        inst = read("Blackout", "InstrumentsView.swift")
        exped = read("Blackout", "ExpeditionTab.swift")
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        for stamp in (
            "LEFT HAND",
            "SOS FLASHLIGHT",
            "COMPASS CAL",
            "TRUE NORTH",
            "USB-C PTT",
            "GNSS PUCK",
        ):
            self.assertIn(stamp, inst, stamp)
        self.assertIn('sectionLabel("VOICE")', inst)
        self.assertIn("NavVoice.allCases", inst)
        self.assertIn("voice.title", inst)
        voices = read("Packages", "Instruments", "Sources", "Instruments", "Instruments.swift")
        for stamp in ("STEEL", "NIGHT", "RANGE", "MESH", "DESERT"):
            self.assertIn(f'return "{stamp}"', voices, stamp)
        self.assertNotIn("blackout-hotspare:", inst)
        for label in ("HUNGER", "THIRST", "PAIN", "FATIGUE", "EXPOSURE"):
            self.assertIn(f'slider("{label}"', exped, label)
        self.assertNotIn('slider("WATER"', exped)
        self.assertIn("attributionButton.isHidden = true", offline)
        self.assertIn("compassView.isHidden = true", offline)
        self.assertIn("scaleBar.isHidden = true", offline)
        self.assertNotIn("OSMCredit.line", read("Blackout", "MapTab.swift"))
        self.assertNotIn("OpenStreetMap", read("Blackout", "MapTab.swift"))

    def test_solo_qa_scores_the_honest_taps(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("CAMERA DENIED", qa)
        self.assertIn("RECORDING", qa)
        self.assertIn("NO PEERS", qa)
        self.assertIn("NAV · SEATED", qa)
        self.assertIn("SOS FLASHLIGHT", qa)
        self.assertIn("HUNGER", qa)
        self.assertIn("STEEL", qa)
        self.assertIn("DESERT", qa)
        self.assertIn("onto", qa)
        self.assertIn("TURNS", qa)
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)


ROSTER_ROLES = ("lead", "medic", "nav", "tail", "guest")
ROSTER_TITLES = {
    "lead": "LEAD",
    "medic": "MEDIC",
    "nav": "NAV",
    "tail": "TAIL",
    "guest": "GUEST",
}
UNIQUE_SEATS = frozenset({"lead", "medic", "nav", "tail"})


def roster_title(role: str) -> str:
    return ROSTER_TITLES[role]


def roster_unique(role: str) -> bool:
    return role in UNIQUE_SEATS


def roster_next(role: str) -> str:
    return ROSTER_ROLES[(ROSTER_ROLES.index(role) + 1) % len(ROSTER_ROLES)]


def roster_next_open(current: str, taken: set[str]) -> str:
    role = roster_next(current)
    for _ in ROSTER_ROLES:
        if not roster_unique(role) or role not in taken:
            return role
        role = roster_next(role)
    return "guest"


def roster_seating(
    members: list[dict[str, str]],
    person_id: str,
    role: str,
    name: str | None = None,
) -> list[dict[str, str]]:
    for member in members:
        if member["id"] == person_id and member["role"] == role:
            return members
    if roster_unique(role):
        for member in members:
            if member["role"] == role and member["id"] != person_id:
                return members
    out = [dict(member) for member in members]
    for member in out:
        if member["id"] == person_id:
            member["role"] = role
            if name:
                member["name"] = name
            return out
    out.append({"id": person_id, "name": name or person_id, "role": role})
    return out


def roster_live(
    members: list[dict[str, str]],
    you_id: str,
    you_name: str,
    peers: list[dict[str, str]],
) -> list[dict[str, str]]:
    by_id = {member["id"]: member for member in members}
    you_role = by_id.get(you_id, {}).get("role", "lead")
    label = you_name.strip() if you_name.strip() else "YOU"
    rows = [{"id": you_id, "name": label, "role": you_role}]
    seen = {you_id}
    for peer in peers:
        pid = peer["id"]
        if pid == you_id or pid in seen:
            continue
        seen.add(pid)
        stored = by_id.get(pid)
        role = stored["role"] if stored else "guest"
        name = peer.get("name") or pid
        rows.append({"id": pid, "name": name, "role": role})
    return rows


def roster_seated_chrome(role: str) -> str:
    return f"{roster_title(role)} · SEATED"


class LiveRosterOnTheGlassTests(unittest.TestCase):
    """The roster is the live party. One person is one row. JOIN NAV seats YOU."""

    def test_live_you_is_first_even_solo_and_peers_are_guests(self):
        planted = [{"id": "lead", "name": "Lead", "role": "lead"}]
        solo = roster_live(planted, "local-1", "", [])
        self.assertEqual(len(solo), 1)
        self.assertEqual(solo[0]["id"], "local-1")
        self.assertEqual(solo[0]["name"], "YOU")
        self.assertEqual(solo[0]["role"], "lead")
        named = roster_live(planted, "local-1", "KHAN", [])
        self.assertEqual(named[0]["name"], "KHAN")
        seated = roster_seating(planted, "local-1", "nav", "KHAN")
        seated = roster_seating(seated, "peer-1", "medic", "RUI")
        rows = roster_live(
            seated,
            "local-1",
            "KHAN",
            [
                {"id": "peer-1", "name": "RUI"},
                {"id": "peer-2", "name": "SAM"},
                {"id": "local-1", "name": "echo"},
            ],
        )
        self.assertEqual([row["id"] for row in rows], ["local-1", "peer-1", "peer-2"])
        self.assertEqual([row["role"] for row in rows], ["nav", "medic", "guest"])
        self.assertEqual(len(rows), 3)
        self.assertNotIn("lead", [row["id"] for row in rows])

    def test_seating_nav_is_sticky_and_unique_seats_do_not_stack(self):
        members = [{"id": "you", "name": "YOU", "role": "lead"}]
        nav = roster_seating(members, "you", "nav")
        self.assertEqual(nav[0]["role"], "nav")
        again = roster_seating(nav, "you", "nav")
        self.assertIs(again, nav)
        self.assertEqual(roster_seated_chrome("nav"), "NAV · SEATED")
        self.assertEqual(roster_seated_chrome("lead"), "LEAD · SEATED")
        taken = roster_seating(nav, "peer", "nav", "RUI")
        self.assertIs(taken, nav)
        guests = roster_seating(nav, "a", "guest", "A")
        guests = roster_seating(guests, "b", "guest", "B")
        self.assertEqual([m["role"] for m in guests if m["role"] == "guest"], ["guest", "guest"])
        taken_unique = {"nav"}
        self.assertEqual(roster_next_open("lead", taken_unique), "medic")
        self.assertEqual(roster_next_open("medic", {"lead", "medic", "nav", "tail"}), "guest")
        for role, title in ROSTER_TITLES.items():
            self.assertEqual(roster_title(role), title)
            self.assertEqual(roster_unique(role), role in UNIQUE_SEATS)

    def test_expedition_seats_you_as_nav_and_paints_live_rows(self):
        exped = read("Blackout", "ExpeditionTab.swift")
        roles = read("Packages", "RosterRoles", "Sources", "RosterRoles", "RosterRoles.swift")
        app = read("Blackout", "AppRuntime.swift")
        paper = read("Packages", "PaperGen", "Sources", "PaperGen", "PaperGen.swift")
        paper_tests = read(
            "Packages", "PaperGen", "Tests", "PaperGenTests", "PaperGenTests.swift"
        )
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        roster_tests = read(
            "Packages", "RosterRoles", "Tests", "RosterRolesTests", "RosterRolesTests.swift"
        )
        qa = read("docs", "SOLO_QA.md")
        self.assertIn('Button("JOIN NAV")', exped)
        self.assertIn("NAV · SEATED", exped)
        self.assertNotIn('joining("Nav"', exped)
        self.assertNotIn("m.role.rawValue", exped)
        self.assertIn("runtime.liveRoster", exped)
        self.assertIn("row.role.title", exped)
        self.assertIn("row.statusTitle", exped)
        self.assertIn("runtime.seatNav()", exped)
        row = exped.split("private func rosterRow")[1].split("private func rosterFace")[0]
        self.assertIn("mapChipHitPoints", row)
        face = exped.split("private func rosterFace")[1].split("private func rosterStatusInk")[0]
        self.assertIn("PersonEmblem.image", face)
        self.assertIn("func live(", roles)
        self.assertIn("func seating(", roles)
        self.assertIn("func rebindingLead(", roles)
        self.assertIn("var uniqueSeat", roles)
        self.assertIn("func nextOpen(", roles)
        self.assertIn('return "LEAD"', roles)
        self.assertIn('return "MEDIC"', roles)
        self.assertIn('return "NAV"', roles)
        self.assertIn('return "TAIL"', roles)
        self.assertIn('return "GUEST"', roles)
        title = roles.split("var title")[1].split("var uniqueSeat")[0]
        self.assertIn("Never", title)
        unique = roles.split("var uniqueSeat")[1].split("func nextOpen")[0]
        self.assertIn("Never", unique)
        self.assertIn("struct LiveRosterRow", roles)
        self.assertIn("struct RosterPeer", roles)
        self.assertIn("var liveRoster", app)
        self.assertIn("func seatNav()", app)
        self.assertIn("func paperRoster()", app)
        self.assertIn("func sendRosterSeat()", app)
        self.assertIn("rebindingLead(to:", app)
        self.assertIn('"you.role"', app)
        peers = app.split("mesh.onPeersChanged")[1].split("mesh.startLocal()")[0]
        self.assertIn("sendRosterSeat()", peers)
        inbound = app.split("func applyInbound")[1].split("func raiseIncoming")[0]
        self.assertIn('case "roster":', inbound)
        self.assertIn("MeshRosterBody.parse", inbound)
        self.assertIn("upserting(", inbound)
        self.assertIn("enum MeshRosterBody", mesh)
        self.assertIn("func sendRoster(", mesh)
        self.assertIn('kind: "roster"', mesh)
        self.assertIn('vitals.count == 6', mesh)
        self.assertIn("role.title", paper)
        self.assertIn('"LEAD A"', paper_tests)
        self.assertNotIn('"lead A"', paper_tests)
        self.assertIn("func testLiveYouIsFirstEvenSolo", roster_tests)
        self.assertIn("func testSeatingNavIsStickyAndUnique", roster_tests)
        self.assertIn("JOIN NAV seats YOU as NAV", qa)
        self.assertIn("YOU is the first row", qa)
        self.assertIn("NAME, FACE, ROLE, STATUS", qa)
        self.assertIn("One person is one row", qa)
        self.assertIn("LEAD / MEDIC / NAV / TAIL / GUEST", qa)
        self.assertIn("guests can repeat", qa.lower())
        self.assertNotIn("`nav Nav`", qa)
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)
        self.assertNotIn("Google", qa)
        assign = exped.split("private var assignPeople")[1].split("private func timerWho")[0]
        self.assertIn("liveRoster", assign)
        export = exped.split('Button("EXPORT PAPER")')[1].split("if !paperText.isEmpty")[0]
        self.assertIn("paperRoster()", export)
        self.assertIn("func cycling(", roles)
        self.assertIn("runtime.cycleSeat", exped)


def tap_lamp(current: str, tap: str) -> str:
    """NIGHT and SUN are exclusive. Tap the live one to return to void."""
    if tap == "off":
        return "off"
    if tap not in ("night", "sun"):
        raise AssertionError(tap)
    return "off" if current == tap else tap


def sos_flash_cycle():
    """ITU Morse SOS as (on, units). Dit=1, dah=3, letter=3, word=7."""
    return [
        (True, 1),
        (False, 1),
        (True, 1),
        (False, 1),
        (True, 1),
        (False, 3),
        (True, 3),
        (False, 1),
        (True, 3),
        (False, 1),
        (True, 3),
        (False, 3),
        (True, 1),
        (False, 1),
        (True, 1),
        (False, 1),
        (True, 1),
        (False, 7),
    ]


ASLEEP = 0.08
DIM = 0.28


def chrome_opacity(*, awake: bool, crisis: bool, arranging: bool) -> float:
    """MAP chrome sleeps. SOS / RED / LAYOUT do not."""
    if crisis or arranging:
        return 1.0
    return 1.0 if awake else ASLEEP


def piece_opacity(*, focus: str, piece: str) -> float:
    """One control is alive. SOS is never the one that goes dim."""
    if piece == "sos":
        return 1.0
    if not focus or focus == piece:
        return 1.0
    return DIM


def reset_layout(placed: dict[str, tuple[float, float]]) -> dict[str, tuple[float, float]]:
    return {key: (0.0, 0.0) for key in placed}


class HUDSeductionTests(unittest.TestCase):
    """Visual pull without lying about water, SOS, or the net."""

    def test_idle_chrome_sleeps_and_crisis_does_not(self):
        self.assertEqual(chrome_opacity(awake=True, crisis=False, arranging=False), 1.0)
        self.assertEqual(chrome_opacity(awake=False, crisis=False, arranging=False), ASLEEP)
        self.assertEqual(chrome_opacity(awake=False, crisis=True, arranging=False), 1.0)
        self.assertEqual(chrome_opacity(awake=False, crisis=False, arranging=True), 1.0)

    def test_one_control_alive_and_sos_never_dims(self):
        self.assertEqual(piece_opacity(focus="search", piece="search"), 1.0)
        self.assertEqual(piece_opacity(focus="search", piece="dock"), DIM)
        self.assertEqual(piece_opacity(focus="", piece="dock"), 1.0)
        self.assertEqual(piece_opacity(focus="dock", piece="sos"), 1.0)

    def test_reset_hud_returns_every_piece_to_origin(self):
        placed = {"search": (12.0, -8.0), "dock": (0.0, 40.0), "sos": (4.0, 10.0)}
        self.assertEqual(reset_layout(placed), {k: (0.0, 0.0) for k in placed})

    def test_source_has_the_hooks(self):
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        app = read("Blackout", "AppRuntime.swift")
        tab = read("Blackout", "MapTab.swift")
        root = read("Blackout", "RootChrome.swift")
        inst = read("Blackout", "InstrumentsView.swift")
        hold = read("Blackout", "HoldCard.swift")
        theme = read("Blackout", "Theme.swift")
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        inspect = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "Inspect.swift")
        route = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift")
        layout_path = ROOT.joinpath("Blackout", "HUDLayout.swift")
        self.assertTrue(layout_path.is_file(), "HUDLayout.swift")
        layout = layout_path.read_text()
        puck = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift")
        self.assertIn("chromeIdleSeconds", tokens)
        self.assertIn("3.2", tokens)
        self.assertIn("chromeAsleepOpacity", tokens)
        self.assertIn("0.08", tokens)
        self.assertIn("chromeSleepSeconds", tokens)
        self.assertIn("chromeDimOpacity", tokens)
        self.assertIn("func pulse()", app)
        self.assertIn("var chromeAwake", app)
        self.assertIn("var hudLayoutMode", app)
        self.assertIn("func resetHUD()", app)
        self.assertIn("RESET HUD", inst)
        self.assertIn("LAYOUT", inst)
        self.assertIn("hudLayout", layout)
        self.assertIn("hud.layout", layout)
        self.assertNotIn(".spring(", tab)
        self.assertNotIn(".spring(", hold)
        self.assertIn("easeInOut", theme)
        self.assertIn("enum PartyPips", route)
        self.assertIn("runtime.eyeCanvasPips()", tab)
        self.assertIn("mesh.pips", app.split("func eyeCanvasPips")[1].split("func eyeTrails")[0])
        self.assertIn("PartyPips.haloLayerID", inspect)
        self.assertIn("regionIsChangingWith reason:", offline)
        self.assertIn("mapViewRegionIsChanging", offline)
        self.assertNotIn("regionIsChangingWithReason", offline)
        self.assertNotIn("shapeCollection(withShapes:", offline)
        self.assertIn("MLNShape(data:", offline)
        self.assertIn("onPulse", offline)
        self.assertIn("arranging:", tab)
        self.assertNotIn("149.0 / 255.0", tokens)
        self.assertIn("warn=silver", tokens.replace(" ", ""))
        self.assertNotIn("label.text = UserPuck.title", puck)
        self.assertIn('static let title = "YOU"', read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        ))
        self.assertNotIn("OSMCredit.line", tab)
        self.assertNotIn("OpenStreetMap", tab)
        self.assertIn("0.77, green: 0.80, blue: 0.84", offline)
        self.assertNotIn("0.12, green: 0.82, blue: 0.94", offline)
        self.assertNotIn("UIColor(white:", offline)
        self.assertIn("from != mesh.localID", app.split("func eyeCanvasPips")[1].split("func eyeTrails")[0])
        self.assertIn("chromeVeil * runtime.alive(.search)", tab)
        self.assertIn(".tint(Theme.silver)", root)
        self.assertNotIn(".tint(Theme.accent)", root)
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        self.assertIn("NET · NONE", mesh)
        self.assertIn("from != localID", mesh)
        self.assertIn("pips.removeAll", mesh)
        pulse = app.split("func pulse()")[1].split("func resetHUD")[0]
        self.assertIn("hudFocus = .none", pulse.split("pulseTask")[0])
        touch = app.split("func touch(_ piece: HUDFocus)")[1].split("func pulse()")[0]
        self.assertLess(touch.find("pulse()"), touch.find("hudFocus = piece"))
        self.assertIn("return arranging", tokens)
        comms = read("Blackout", "CommsTab.swift")
        self.assertNotIn("runtime.ptt.live ? Theme.accent", comms)
        self.assertIn("runtime.ptt.live ? Theme.silver", comms)
        self.assertNotIn("WaterSure.disclaimer", hold)
        self.assertNotIn("tel://911", tab + root + hold)
        for name in (
            "MapTab.swift",
            "RootChrome.swift",
            "HoldCard.swift",
            "PartyHoldCard.swift",
            "EmblemPickCard.swift",
            "AddressHoldCard.swift",
            "CamHoldCard.swift",
            "NearHoldCard.swift",
            "CommsTab.swift",
            "FieldTab.swift",
            "ExpeditionTab.swift",
            "InstrumentsView.swift",
            "ARMINGView.swift",
            "Theme.swift",
            "HUDLayout.swift",
        ):
            body = read("Blackout", name)
            self.assertNotIn("Color(white:", body, name)
            self.assertNotIn(".foregroundStyle(.red)", body, name)
            self.assertNotIn("Color.blue", body, name)
            self.assertNotIn(".spring(", body, name)

    def test_solo_qa_scores_the_hook(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("chrome fades", qa.lower())
        self.assertIn("RESET HUD", qa)
        self.assertIn("LAYOUT", qa)
        self.assertIn("party dots", qa.lower())
        self.assertIn("compass ring", qa.lower())
        self.assertIn("FACE", qa)
        self.assertIn("tick dark", qa.lower())
        self.assertIn("359", qa)
        self.assertIn("no bounce", qa.lower())
        self.assertIn("NET · NONE", qa)
        self.assertIn("silver route", qa.lower())
        self.assertNotIn("cyan route", qa.lower())
        self.assertNotIn("does not replace 911", qa)
        self.assertNotIn("I UNDERSTAND", qa)


class PersonMarkOnTheMapTests(unittest.TestCase):
    """YOU and party are faces with a live north-up compass, not silver dots."""

    def test_face_picker_and_live_ring_are_on_the_glass(self):
        comms = read("Blackout", "CommsTab.swift")
        tab = read("Blackout", "MapTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        emblem = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "PersonEmblem.swift"
        )
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        route = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift")
        folder = ROOT.joinpath(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "Emblems"
        )
        self.assertIn('sectionLabel("FACE")', comms)
        self.assertIn("EmblemFaceGrid(", comms)
        self.assertIn("pickEmblem", comms)
        self.assertIn("youHeading: runtime.headingDeg", tab)
        self.assertIn("youEmblem: runtime.youEmblem.rawValue", tab)
        self.assertIn("runtime.eyeCanvasPips()", tab)
        self.assertIn("PartyBody(", app)
        self.assertIn("var youEmblem", app)
        self.assertIn("func pickEmblem", app)
        self.assertIn("sendPOSIfPossible()", app.split("func pullFix()")[1].split("static func resourceRoot")[0])
        self.assertIn("enum PersonEmblem", emblem)
        self.assertIn("enum PersonCompass", emblem)
        self.assertIn("tickRadians", emblem)
        self.assertIn("liveHeading", emblem)
        self.assertIn("magNorth: Bool", emblem)
        self.assertIn("PersonCompass.liveHeading", app)
        self.assertIn("magNorth: magNorth", app)
        self.assertIn("headingAccuracy", app)
        self.assertIn("headingDeg >= 0", offline)
        self.assertIn("headingDeg >= 0", route)
        self.assertIn("value >= 0", mesh)
        self.assertIn("headingDeg >= 0", mesh)
        self.assertNotIn("best in class", emblem.lower())
        self.assertNotIn("best in class", comms.lower())
        self.assertNotIn("best in class", offline.lower())
        self.assertIn("PersonCompassArt", offline)
        self.assertIn("static func mark(", offline)
        self.assertIn("you-puck-core", offline)
        self.assertIn("UserPuck.markLayerID", offline)
        self.assertIn("PartyPips.markLayerID", offline)
        puck = person_compass_const("puckPoints")
        well = person_compass_const("wellPoints")
        self.assertLessEqual(puck, 48)
        self.assertGreater(puck, well)
        self.assertGreaterEqual(well / puck, 0.70)
        self.assertNotIn("view.add(haloPoly)", offline)
        self.assertNotIn("abs(ann.coordinate.latitude - spec.puckLat) < 1e-9", offline)
        self.assertNotIn(
            "Dictionary(uniqueKeysWithValues: partyMarks.map",
            offline,
        )
        self.assertNotIn("MLNPolyline(coordinates: &empty, count: 0)", offline)
        self.assertNotIn("count: 0", offline)
        self.assertIn("emptyOverlayShape", offline)
        self.assertNotIn(
            "a.lat != b.lat || a.lon != b.lon || a.emblem != b.emblem",
            route,
        )
        self.assertIn("a.id != b.id || a.emblem != b.emblem", route)
        self.assertIn("HiddenUserLocationView", offline)
        self.assertIn("circleStrokeOpacity", offline)
        self.assertGreaterEqual(offline.count("circleStrokeOpacity"), 2)
        self.assertNotIn('("N", 0, accent)', offline)
        self.assertNotIn(
            "storedPack != pack || storedPuck != puck",
            read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"),
        )
        self.assertIn("enum MeshPOS", mesh)
        self.assertIn("headingDeg", mesh)
        self.assertIn("struct PartyBody", route)
        self.assertEqual(len(list(folder.glob("*.jpg"))), 26)
        for name in (
            "wolf",
            "owl",
            "bear",
            "heron",
            "raven",
            "eagle",
            "turtle",
            "raccoon",
            "horse",
            "mule",
            "beaver",
            "ibex",
            "roadrunner",
            "mule-deer",
            "husky",
            "pronghorn",
            "labrador",
            "deer",
            "falcon",
            "otter",
            "fox",
            "boar",
            "bighorn",
            "bison",
            "bat",
            "hawk",
        ):
            self.assertTrue((folder / f"{name}.jpg").is_file(), name)

    def test_emblem_compass_and_status_ring_are_metal_sprites(self):
        """YOU/party are a baked rose + face + condition ring, not the red pin."""
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        emblem = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "PersonEmblem.swift"
        )
        puck = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        )
        route = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift"
        )
        inspect = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "Inspect.swift"
        )
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("enum PersonCompassArt", offline)
        self.assertIn("static func mark(", offline)
        self.assertIn("static let statusRingPoints", emblem)
        art = offline.split("enum PersonCompassArt")[1]
        mark = art.split("static func mark(")[1].split("static func pin(")[0]
        view_for = offline.split("func mapView(_ mapView: MLNMapView, viewFor")[1].split(
            "func mapView(_ mapView: MLNMapView, annotationCanShowCallout"
        )[0]
        spec = offline.split("struct OverlaySpec")[1].split("var spec:")[0]
        you_sync = offline.split("func syncPersonMarks")[1].split("func syncPartyMarks")[0]
        party_sync = offline.split("func syncPartyMarks")[1].split("func stamp(")[0]
        sun = offline.split("private static func paintSun")[1].split(
            "private static func keepsLine"
        )[0]
        nvg = offline.split("private static func paintNVG")[1].split("enum EyeLook")[0]
        ring = person_compass_const("statusRingPoints")
        well = person_compass_const("wellPoints")
        size = person_compass_const("puckPoints")
        self.assertEqual(ring, 3)
        self.assertGreaterEqual(ring, 2.5)
        self.assertLess(ring, well / 4)
        self.assertGreaterEqual(size, 44)
        self.assertIn("emblemID:", mark)
        self.assertIn("headingDeg:", mark)
        self.assertIn("tint:", mark)
        self.assertIn("place: Bool", mark)
        self.assertIn("PersonCompassArt.rose", mark)
        self.assertIn("PersonEmblem.image", mark)
        self.assertIn("PersonCompass.statusRingPoints", mark)
        self.assertIn("chevronPath", mark)
        self.assertIn("headingDeg >= 0", mark)
        self.assertIn("cg.clip()", mark)
        self.assertNotIn("addClip", mark)
        self.assertNotIn("rotatesToMatchCamera", mark)
        self.assertNotIn("CGAffineTransform", mark)
        self.assertIn("var youCondition: String", spec)
        self.assertIn(
            "self.youCondition = youCondition",
            offline.split("self.youEmblem = youEmblem")[1].split("self.onPulse")[0],
        )
        self.assertIn("youCondition: youCondition", offline)
        self.assertIn(
            "youCondition: EyeDesk.condition(status: runtime.youStatus.rawValue).rawValue",
            tab,
        )
        self.assertIn("you.condition = spec.youCondition", you_sync)
        self.assertIn("style.setImage", offline)
        self.assertIn('static let markLayerID = "you-mark"', puck)
        self.assertIn('static let markImageName = "you-mark"', puck)
        self.assertIn('static let markLayerID = "party-mark"', route)
        self.assertIn("MLNSymbolStyleLayer(identifier: UserPuck.markLayerID", offline)
        self.assertIn("MLNSymbolStyleLayer(identifier: PartyPips.markLayerID", offline)
        self.assertIn("iconAllowsOverlap", offline)
        self.assertIn("iconIgnoresPlacement", offline)
        self.assertIn('iconPitchAlignment = NSExpression(forConstantValue: "viewport")', offline)
        self.assertIn('iconRotationAlignment = NSExpression(forConstantValue: "map")', offline)
        self.assertNotIn("view.addAnnotation(you)", offline)
        self.assertNotIn("view.addAnnotation(mark)", party_sync)
        self.assertNotIn("ann.title == UserPuck.title", offline)
        self.assertIn("let mapHasPuck = puck != nil", offline)
        self.assertIn("HiddenUserLocationView", view_for)
        self.assertNotIn("YouPuckAnnotationView", view_for)
        self.assertIn("return nil", view_for)
        self.assertNotIn("final class YouPuckAnnotationView", offline)
        self.assertIn("UserPuck.markLayerID", inspect.split("overlayLayerIDs")[1].split("waterCard")[0])
        self.assertIn("PartyPips.markLayerID", inspect.split("overlayLayerIDs")[1].split("waterCard")[0])
        self.assertIn("keepsSymbol", sun)
        self.assertIn("UserPuck.markLayerID", sun)
        self.assertIn("PartyPips.markLayerID", nvg)
        self.assertIn("func personMark(at:", offline)
        self.assertIn("func paintPersonMarks", offline)
        self.assertIn("PersonCompass.puckPoints", offline)


class PartyHoldCardTests(unittest.TestCase):
    """Hold a person emblem: glass profile, status, course, party call, note."""

    def test_hold_on_emblem_opens_glass_not_ground(self):
        tab = read("Blackout", "MapTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        hold = read("Blackout", "HoldCard.swift")
        card = read("Blackout", "PartyHoldCard.swift")
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        comms = read("Blackout", "CommsTab.swift")
        tests = ROOT.joinpath("Packages", "MapLibreMap", "Tests")
        count = 0
        for path in tests.rglob("*.swift"):
            count += len(re.findall(r"func test[A-Z]\w+\(", path.read_text()))
        self.assertEqual(count, 177)
        self.assertIn("var onPersonHold", offline)
        self.assertIn("onPersonHold:", tab)
        self.assertIn("func personMark(at:", offline)
        self.assertIn("toPointTo:", offline)
        self.assertIn("isUserInteractionEnabled = false", offline.split("final class HiddenUserLocationView")[1])
        hold_fn = offline.split("func handleHold")[1].split("func liftIntoView")[0]
        self.assertLess(hold_fn.find("personMark(at:"), hold_fn.find("onMapHold"))
        self.assertIn("onPersonHold?", hold_fn)
        self.assertIn("func holdParty(", app)
        self.assertIn("var heldParty", app)
        self.assertIn("struct HeldPerson", hold)
        self.assertIn("struct PartyHoldCard", card)
        self.assertIn('Button("CALL")', card)
        self.assertIn('Button("MESSAGE")', card)
        self.assertIn("STATUS", card)
        self.assertIn("BEARING", card)
        self.assertIn("COORDINATES", card)
        self.assertIn("PartyStatus.allCases", card)
        self.assertIn("CONDITION", card)
        for label in ("HUNGER", "THIRST", "PAIN", "FATIGUE", "EXPOSURE"):
            self.assertIn(f'HUDVitalsRail(title: "{label}"', card, label)
        self.assertNotIn('HUDVitalsRail(title: "WATER"', card)
        self.assertIn("editable: person.isYou", card)
        exped = read("Blackout", "ExpeditionTab.swift")
        self.assertIn("struct HUDVitalsRail", exped)
        self.assertIn("var editable: Bool", exped)
        self.assertIn("ScrollView", card)
        self.assertIn("func setYouStatus(", app)
        self.assertIn("func setYouVitals(", app)
        set_vitals = app.split("func setYouVitals(")[1].split("func ", 1)[0]
        self.assertIn("sendPOSIfPossible()", set_vitals)
        self.assertIn("offerConditionSOS()", set_vitals)
        self.assertIn("blackTitles", set_vitals)
        self.assertIn("func setYouName(", app)
        self.assertIn("func offerConditionSOS()", app)
        sos = app.split("func offerConditionSOS()")[1].split("func ", 1)[0]
        self.assertIn("offerSOS()", sos)
        self.assertIn("partyAlertLine", sos)
        self.assertIn('to: "*"', sos)
        self.assertIn("lastConditionSOS", sos)
        self.assertIn("NO HEADING", sos)
        self.assertIn("destValue", sos)
        self.assertNotIn("tel://", sos.lower())
        iamok = app.split("func iamOK()")[1].split("func ", 1)[0]
        self.assertIn("lastConditionSOS", iamok)
        self.assertIn("lastConditionSOS", comms)
        self.assertIn("case .black", card)
        self.assertIn("func callHeldParty(", app)
        self.assertIn("func messageHeldParty(", app)
        self.assertIn("func sendPartyNote(", app)
        call = app.split("func callHeldParty(")[1].split("func messageHeldParty(")[0]
        self.assertIn("pickPeer", call)
        self.assertIn("beginPTTSolo()", call)
        self.assertIn("tab = .comms", call)
        self.assertIn("Task { @MainActor in", call)
        message = app.split("func messageHeldParty(")[1].split("func sendPartyNote(")[0]
        self.assertIn("pickPeer", message)
        self.assertIn("tab = .comms", message)
        self.assertIn("Task { @MainActor in", message)
        self.assertNotIn("tel://", card.lower())
        self.assertNotIn("tel://", app.lower())
        self.assertNotIn("Color.orange", card)
        self.assertNotIn("Color.green", card)
        self.assertNotIn("best in class", card.lower())
        self.assertNotIn(".spring(", card)
        self.assertIn("enum PartyStatus", mesh)
        self.assertIn("case good, okay, bad, emergency", mesh)
        self.assertIn('return "GOOD"', mesh)
        self.assertIn('return "OKAY"', mesh)
        self.assertIn('return "BAD"', mesh)
        self.assertIn('return "EMERGENCY!"', mesh)
        self.assertIn('"ok"', mesh)
        self.assertIn('"wait"', mesh)
        tests = read("Packages", "MeshDTN", "Tests", "MeshDTNTests", "MeshDTNTests.swift")
        self.assertIn('XCTAssertEqual(railsParsed?.status, "okay")', tests)
        self.assertIn('XCTAssertEqual(net.pips.first?.status, "okay")', tests)
        self.assertNotIn(
            'withRails.split(",")',
            tests,
            "String.split(\",\") does not compile; use split(separator:)",
        )
        self.assertIn("withRails.split(separator:", tests)
        self.assertIn('"water"', mesh)
        self.assertIn('"down"', mesh)
        self.assertIn("case .good", card)
        self.assertIn("case .okay", card)
        self.assertIn("case .bad", card)
        self.assertIn("case .emergency", card)
        self.assertNotIn("case ok, wait, water, down", mesh)
        pos = mesh.split("enum MeshPOS")[1].split("struct MeshTimerEvent")[0]
        self.assertIn("name", pos)
        self.assertIn("status", pos)
        self.assertIn("vitals", pos)
        self.assertIn("%.2f", pos)
        self.assertIn("func nameToken", pos)
        send = app.split("func sendPOSIfPossible()")[1].split("func applyInbound")[0]
        self.assertIn("vitals:", send)
        self.assertIn("heldParty?.vitals", app)
        self.assertIn("func sendNote(", mesh)
        self.assertIn('kind: "note"', mesh)
        self.assertIn("VoiceNav.bearing", app)
        self.assertIn("PartyHoldCard(", tab)
        self.assertIn("runtime.heldParty", tab)
        self.assertIn("heldParty!=nil", tab.replace(" ", ""))
        self.assertIn('sectionLabel("NOTE")', comms)
        self.assertIn('Button("SEND")', comms)
        self.assertIn("sendPartyNote", comms)
        self.assertNotIn("emblem: $0.emblem, name:", tab.replace(" ", ""))
        self.assertIn("HoldGlassShell(", card)

    def test_profile_call_and_message_open_comms_for_you_and_party(self):
        card = read("Blackout", "PartyHoldCard.swift")
        app = read("Blackout", "AppRuntime.swift")
        comms = read("Blackout", "CommsTab.swift")
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        ui = read("Packages", "CommsUI", "Sources", "CommsUI", "CommsUI.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("HoldGlassShell(", card)
        self.assertIn("actions", card)
        self.assertNotIn("if !person.isYou", card.split("private var actions")[1])
        actions = card.split("private var actions")[1].split("private func statusInk")[0]
        self.assertIn('Button("CALL")', actions)
        self.assertIn('Button("MESSAGE")', actions)
        self.assertIn("HUDActionStyle", actions)
        self.assertIn("filled: false", actions)
        self.assertNotIn("tel://", actions.lower())
        self.assertNotIn("best in class", card.lower())
        call = app.split("func callHeldParty(")[1].split("func messageHeldParty(")[0]
        self.assertNotIn("!person.isYou else { return }", call)
        self.assertIn("person.isYou", call)
        self.assertIn('pickPeer("YOU")', call)
        self.assertIn("beginPTTSolo()", call)
        self.assertIn("tab = .comms", call)
        self.assertNotIn("tel://", call.lower())
        message = app.split("func messageHeldParty(")[1].split("func sendPartyNote(")[0]
        self.assertNotIn("!person.isYou else { return }", message)
        self.assertIn("person.isYou", message)
        self.assertIn('pickPeer("YOU")', message)
        self.assertIn("pendingNoteFocus", message)
        self.assertIn("tab = .comms", message)
        send = app.split("func sendPartyNote(")[1].split("func partyCourse(")[0]
        self.assertNotIn("appendPartyNote", send)
        self.assertIn("meshDest", send)
        self.assertIn("sendNote", send)
        self.assertNotIn("var partyNotes", app)
        self.assertIn("var pendingNoteFocus", app)
        self.assertNotIn("func appendPartyNote(", app)
        self.assertNotIn("func persistPartyNotes(", app)
        self.assertNotIn("func loadPartyNotes(", app)
        self.assertNotIn("loadPartyNotes()", app)
        self.assertIn("struct PartyThreadLine", mesh)
        self.assertIn("peer == \"YOU\"", ui)
        self.assertIn('return "YOU"', ui)
        self.assertNotIn('sectionLabel("THREAD")', comms)
        self.assertNotIn("partyNotes", comms)
        self.assertNotIn("threadLines", comms)
        self.assertIn("pendingNoteFocus", comms)
        self.assertIn("comms.note", comms)
        self.assertIn('sectionLabel("NOTE")', comms)
        self.assertIn('Button("SEND")', comms)
        person = next(
            line for line in qa.splitlines() if "Hold YOU or a party emblem" in line
        )
        self.assertIn("YOU and party", person)
        self.assertNotIn("THREAD", person)
        self.assertIn("HUD typewriter", person)
        self.assertIn("Incoming notes land on COMMS LOG", person)
        self.assertIn("Incoming CALL and MESSAGE pop a HUD line", person)
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("tel://", app.lower())

    def test_solo_qa_scores_the_person_card(self):
        qa = read("docs", "SOLO_QA.md")
        person = next(
            line for line in qa.splitlines() if "Hold YOU or a party emblem" in line
        )
        self.assertIn("STATUS", person)
        self.assertIn("`GOOD` / `OKAY` / `BAD` / `EMERGENCY!`", person)
        self.assertIn("CONDITION", person)
        self.assertIn("TIMER", person)
        self.assertIn("INVENTORY", person)
        self.assertIn("remaining bar", person)
        self.assertIn("HUNGER", person)
        self.assertIn("THIRST", person)
        self.assertIn("others read", person)
        self.assertIn("CALL starts a 1:1 party call", person)
        self.assertIn("MESSAGE opens COMMS", person)
        self.assertIn("YOU and party", person)
        self.assertIn("Incoming notes land on COMMS LOG", person)
        self.assertIn("Incoming CALL and MESSAGE pop a HUD line", person)
        self.assertNotIn("THREAD", person)
        self.assertIn("PTT mesh", person)
        self.assertIn("never `tel://`", qa)
        self.assertIn("Names stay off the canvas", person)
        self.assertIn("Hold the face", person)
        self.assertIn("FACE", person)
        self.assertIn("26", person)
        self.assertIn("second glass", person)
        self.assertIn("party card's face does not open FACE", person)
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)

    def test_hold_you_face_opens_emblem_glass(self):
        tab = read("Blackout", "MapTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        card = read("Blackout", "PartyHoldCard.swift")
        pick = read("Blackout", "EmblemPickCard.swift")
        grid = read("Blackout", "EmblemFaceGrid.swift")
        device = read("docs", "DEVICE.md")
        face = card.split("private var face")[1].split("private var displayName")[0]
        self.assertIn("struct EmblemPickCard", pick)
        self.assertIn("EmblemFaceGrid(", pick)
        self.assertIn("emblem.title", grid)
        self.assertIn('"FACE"', pick)
        self.assertIn("onPick", pick)
        self.assertIn("HoldGlassShell(", pick)
        shell = read("Blackout", "HoldCard.swift").split("struct HoldGlassShell")[1].split("struct HoldCardView")[0]
        self.assertIn("Theme.Motion.heavy", shell)
        self.assertIn("BlackoutTokens.Chrome.mapChipHitPoints", grid)
        self.assertNotIn("closeHold", pick)
        self.assertNotIn(".spring(", pick)
        self.assertNotIn("tel://", pick.lower())
        self.assertNotIn("Color.orange", pick)
        self.assertNotIn("Color.green", pick)
        self.assertNotIn("best in class", pick.lower())
        self.assertIn("person.isYou", face)
        self.assertIn("Inspect.holdSeconds", face)
        self.assertIn("LongPressGesture", face)
        self.assertIn("highPriorityGesture", face)
        self.assertIn("onFaceHold", face)
        self.assertIn("accessibilityLabel(\"FACE\")", face)
        self.assertIn("onFaceHold:", tab)
        self.assertIn("openEmblemPick()", tab)
        self.assertIn("EmblemPickCard(", tab)
        self.assertIn("runtime.pickingEmblem", tab)
        self.assertIn("closeEmblemPick()", tab)
        self.assertIn("pickEmblem", tab)
        self.assertIn("var pickingEmblem", app)
        self.assertIn("func openEmblemPick(", app)
        self.assertIn("func closeEmblemPick(", app)
        open_pick = app.split("func openEmblemPick(")[1].split("func ", 1)[0]
        self.assertIn("isYou", open_pick)
        self.assertIn("pickingEmblem = true", open_pick)
        close_pick = app.split("func closeEmblemPick(")[1].split("func ", 1)[0]
        self.assertIn("pickingEmblem = false", close_pick)
        self.assertNotIn("heldParty = nil", close_pick)
        for fn in (
            "func holdInspect(",
            "func holdAddress(",
            "func holdParty(",
            "func closeHold()",
        ):
            body = app.split(fn)[1].split("func ", 1)[0]
            self.assertIn("pickingEmblem = false", body, fn)
        self.assertIn("Hold the face", device)
        self.assertIn("FACE", device)
        self.assertNotIn("best in class", device.lower())
        self.assertNotIn("best in class", card.lower())


class IncomingLineTests(unittest.TestCase):
    """Inbound CALL / MESSAGE pop one themed HUD line: emblem, name, location."""

    def test_root_chrome_hosts_a_glass_incoming_line(self):
        plate_path = ROOT.joinpath("Blackout", "IncomingLinePlate.swift")
        self.assertTrue(plate_path.is_file(), "IncomingLinePlate.swift")
        plate = plate_path.read_text()
        root = read("Blackout", "RootChrome.swift")
        app = read("Blackout", "AppRuntime.swift")
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        self.assertIn("struct IncomingLinePlate", plate)
        self.assertIn("IncomingLinePlate(", root)
        self.assertIn("var incoming", app)
        self.assertIn("struct IncomingLine", app)
        self.assertIn("enum IncomingKind", app)
        self.assertIn("case call", app)
        self.assertIn("case message", app)
        self.assertIn("incomingLineSeconds", tokens)
        self.assertIn("8", tokens.split("incomingLineSeconds")[1].split("\n")[0])
        armed = root.split("if !runtime.armed")[1]
        self.assertLess(armed.find("IncomingLinePlate"), armed.find("hudTypewriter"))
        self.assertGreater(armed.find("IncomingLinePlate"), armed.find("tabChrome"))
        host = root.split("IncomingLinePlate")[0]
        self.assertNotIn("chromeVeil", host[-400:])
        self.assertIn("PersonEmblem.image", plate)
        self.assertIn("PersonEmblem.resolved", plate)
        self.assertIn("Theme.glass", plate)
        self.assertIn("mapChipHitPoints", plate)
        self.assertIn("line.name", plate)
        self.assertIn("line.location", plate)
        self.assertIn('Text("CALL")', plate)
        self.assertIn('Text("MESSAGE")', plate)
        self.assertIn("answerIncoming", plate)
        self.assertIn("clearIncoming", plate)
        self.assertIn("DragGesture", plate)
        self.assertIn("case .call", plate)
        self.assertIn("case .message", plate)
        self.assertNotIn("tel://", plate.lower())
        self.assertNotIn(".spring(", plate)
        self.assertNotIn("best in class", plate.lower())
        self.assertNotIn("ultraThinMaterial", plate)
        self.assertNotIn("UNUserNotification", plate)
        self.assertNotIn("CallKit", plate)
        self.assertNotIn("Waze", plate)
        kind = plate.split("func kindTitle")[1].split("func ", 1)[0]
        self.assertIn("case .call", kind)
        self.assertIn("case .message", kind)
        self.assertIn("Never", kind)

    def test_inbound_note_and_ptt_raise_the_line_voice_does_not(self):
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn("func raiseIncoming(", app)
        self.assertIn("func answerIncoming(", app)
        self.assertIn("func clearIncoming(", app)
        self.assertIn("func incomingIsForLocal(", app)
        inbound = app.split("func applyInbound(")[1].split("func switchPack(")[0]
        chip = inbound.split('case "chip":')[1].split("case ", 1)[0]
        self.assertIn('raw == "ptt"', chip)
        self.assertEqual(chip.count("raiseIncoming"), 1)
        self.assertIn(".call", chip)
        self.assertNotIn(".message", chip)
        self.assertNotIn("Chip.rally", chip)
        voice = inbound.split('case "voice":')[1].split("case ", 1)[0]
        self.assertNotIn("raiseIncoming", voice)
        note = inbound.split('case "note":')[1].split("default:")[0]
        self.assertIn('hasPrefix("SOS ")', note)
        self.assertIn("raiseIncoming", note)
        self.assertIn(".message", note)
        self.assertLess(note.find('hasPrefix("SOS ")'), note.find("raiseIncoming"))
        filt = app.split("func incomingIsForLocal(")[1].split("func ", 1)[0]
        self.assertIn('"*"', filt)
        self.assertIn('"YOU"', filt)
        self.assertIn("mesh.localID", filt)
        raise_fn = app.split("func raiseIncoming(")[1].split("func ", 1)[0]
        self.assertIn("incomingIsForLocal", raise_fn)
        self.assertIn("localID", raise_fn)
        self.assertIn("destValue", raise_fn)
        self.assertIn("isFinite", raise_fn)
        self.assertIn("pulse()", raise_fn)
        self.assertIn("incomingLineSeconds", raise_fn)
        self.assertIn("incomingTask", raise_fn)
        self.assertIn("NO FIX", raise_fn)
        self.assertNotIn("guard env.from != mesh.localID", raise_fn)
        self.assertIn("displayYouName", raise_fn)
        self.assertIn("youEmblem", raise_fn)
        self.assertIn("fieldYou", raise_fn)
        self.assertNotIn("gnssYou", raise_fn)
        answer = app.split("func answerIncoming(")[1].split("func ", 1)[0]
        self.assertIn("pickPeer", answer)
        self.assertIn('pickPeer("YOU")', answer)
        self.assertIn("tab = .comms", answer)
        self.assertIn("beginPTTSolo()", answer)
        self.assertIn("pendingNoteFocus", answer)
        self.assertIn("clearIncoming", answer)
        self.assertIn("case .call", answer)
        self.assertIn("case .message", answer)
        self.assertIn("nearby", answer)
        self.assertIn('"YOU"', answer)
        self.assertIn("Task { @MainActor in", answer)
        self.assertNotIn("tel://", answer.lower())
        clear = app.split("func clearIncoming(")[1].split("func ", 1)[0]
        self.assertIn("incoming = nil", clear)
        self.assertIn("incomingTask?.cancel()", clear)
        leave = app.split("func leaveNet()")[1].split("func persistPartyCode")[0]
        self.assertIn("clearIncoming", leave)
        pulse = app.split("func pulse()")[1].split("func resetHUD")[0]
        self.assertIn("incoming != nil", pulse)
        self.assertNotIn("best in class", app.lower())
        self.assertNotIn("tel://", app.lower())

    def test_solo_qa_scores_the_incoming_line(self):
        qa = read("docs", "SOLO_QA.md")
        person = next(
            line for line in qa.splitlines() if "Hold YOU or a party emblem" in line
        )
        self.assertIn("Incoming notes land on COMMS LOG", person)
        self.assertIn("Incoming CALL and MESSAGE pop a HUD line", person)
        self.assertIn("emblem", person.lower())
        self.assertIn("location", person.lower())
        incoming = next(
            line for line in qa.splitlines() if "Incoming CALL (PTT chip)" in line
        )
        self.assertIn("emblem", incoming.lower())
        self.assertIn("NO FIX", incoming)
        self.assertIn("live or last known", incoming.lower())
        self.assertIn("Tap opens COMMS", incoming)
        self.assertIn("Auto-clears", incoming)
        self.assertIn("Voice packets do not pop", incoming)
        self.assertNotIn("THREAD", incoming)
        self.assertIn("COMMS LOG", incoming)
        self.assertIn("never `tel://`", incoming)
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)

    def test_call_message_radio_to_you_notify_even_without_a_party(self):
        app = read("Blackout", "AppRuntime.swift")
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        comms = read("Blackout", "CommsTab.swift")
        qa = read("docs", "SOLO_QA.md")
        mesh_tests = read(
            "Packages", "MeshDTN", "Tests", "MeshDTNTests", "MeshDTNTests.swift"
        )
        self.assertTrue(mesh_is_self_addressed("local-1", "YOU", "local-1"))
        self.assertTrue(mesh_is_self_addressed("local-1", "local-1", "local-1"))
        self.assertFalse(mesh_is_self_addressed("local-1", "*", "local-1"))
        self.assertFalse(mesh_is_self_addressed("peer-1", "YOU", "local-1"))
        self.assertIn("func isSelfAddressed", mesh)
        enqueue = mesh.split("public func enqueue(")[1].split("public func sendPOS(")[0]
        self.assertIn("isSelfAddressed", enqueue)
        self.assertIn("receive(", enqueue)
        recv = mesh.split("private func receive(")[1].split("private func upsertPip")[0]
        self.assertIn("isSelfAddressed", recv)
        self.assertNotIn("if env.from == localID { return }", recv)
        self.assertIn("inbox.contains", recv)
        call = app.split("func callHeldParty(")[1].split("func messageHeldParty(")[0]
        self.assertNotIn("if person.isYou { return }", call)
        self.assertIn("person.isYou || mesh.nearby.isEmpty", call)
        self.assertIn("sendChip", call)
        self.assertIn('chip: "ptt"', call)
        send = app.split("func sendPartyNote(")[1].split("func partyCourse(")[0]
        self.assertIn("sendNote", send)
        self.assertNotIn('if dest == "YOU"', send)
        radio = app.split("func radioCheckParty(")[1].split("func ", 1)[0]
        self.assertIn('chip: "radio"', radio)
        self.assertIn('"YOU"', radio)
        self.assertIn("nearby.isEmpty", radio)
        inbound = app.split("func applyInbound(")[1].split("func raiseIncoming(")[0]
        chip = inbound.split('case "chip":')[1].split("case ", 1)[0]
        self.assertIn('raw == "ptt"', chip)
        self.assertIn('raw == "radio"', chip)
        self.assertEqual(chip.count("raiseIncoming"), 1)
        self.assertIn(".call", chip)
        self.assertIn("peer != \"YOU\"", comms)
        self.assertIn('pickPeer("YOU")', comms)
        self.assertIn('sectionLabel("PEERS")', comms)
        peers = comms.split('sectionLabel("PEERS")')[1].split("sectionLabel(", 1)[0]
        self.assertIn('pickPeer("YOU")', peers)
        self.assertNotIn("if !runtime.mesh.nearby.isEmpty", peers)
        self.assertIn("func testSelfAddressedYouLoopsBackWithNoPeer", mesh_tests)
        person = next(
            line for line in qa.splitlines() if "Hold YOU or a party emblem" in line
        )
        self.assertIn("even with no party", person)
        self.assertIn("Incoming CALL and MESSAGE pop a HUD line", person)
        self.assertNotIn("YOU does not auto-arm", person)
        incoming = next(
            line for line in qa.splitlines() if "Incoming CALL (PTT chip)" in line
        )
        self.assertIn("CALL, MESSAGE, or RADIO to YOU", incoming)
        self.assertIn("no party", incoming)
        self.assertIn("NET · NONE", incoming)
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)
        self.assertNotIn("Google", qa)


class EmblemFaceGridTests(unittest.TestCase):
    """FACE lists stay short, scroll, and sit in look-alike order."""

    def test_face_lists_scroll_in_look_order_and_stay_compact(self):
        emblem = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "PersonEmblem.swift"
        )
        grid_path = ROOT.joinpath("Blackout", "EmblemFaceGrid.swift")
        self.assertTrue(grid_path.is_file(), "EmblemFaceGrid.swift")
        grid = grid_path.read_text()
        comms = read("Blackout", "CommsTab.swift")
        pick = read("Blackout", "EmblemPickCard.swift")
        mark = read("Blackout", "PlaceMarkCard.swift")
        qa = read("docs", "SOLO_QA.md")
        tests = read(
            "Packages", "MapLibreMap", "Tests", "MapLibreMapTests", "MapLibreMapTests.swift"
        )
        faces = person_emblem_faces(emblem)
        cases = re.findall(r"case (\w+)", emblem.split("enum PersonEmblem")[1].split("public static let fallback")[0])
        self.assertEqual(len(faces), 26)
        self.assertEqual(len(cases), 26)
        self.assertEqual(set(faces), set(cases))
        self.assertLessEqual(_cluster_span(faces, ["falcon", "eagle", "hawk"]), 3)
        self.assertLessEqual(_cluster_span(faces, ["raven", "bat"]), 2)
        self.assertLessEqual(_cluster_span(faces, ["heron", "roadrunner"]), 2)
        self.assertLessEqual(_cluster_span(faces, ["wolf", "husky", "fox"]), 3)
        self.assertLessEqual(_cluster_span(faces, ["raccoon", "labrador"]), 3)
        self.assertLessEqual(_cluster_span(faces, ["horse", "mule"]), 2)
        self.assertLessEqual(_cluster_span(faces, ["muleDeer", "deer", "pronghorn"]), 3)
        self.assertLessEqual(_cluster_span(faces, ["ibex", "bighorn", "bison"]), 3)
        self.assertLessEqual(_cluster_span(faces, ["bear", "beaver", "otter", "turtle"]), 4)
        self.assertIn("static let faces", emblem)
        self.assertIn("PersonEmblem.faces", grid)
        self.assertIn("ScrollView", grid)
        self.assertIn("mapChipHitPoints", grid)
        self.assertIn("*4", grid.replace(" ", ""))
        self.assertIn("var compact", grid)
        self.assertIn("emblem.title", grid)
        self.assertIn("PersonEmblem.image", grid)
        self.assertNotIn("PersonEmblem.allCases", grid)
        self.assertNotIn(".spring(", grid)
        self.assertNotIn("tel://", grid.lower())
        self.assertNotIn("best in class", grid.lower())
        self.assertNotIn("Waze", grid)
        self.assertNotIn("Google", grid)
        face_card = comms.split("private var faceCard")[1].split("private func faceThumb")[0]
        self.assertIn("EmblemFaceGrid(", face_card)
        self.assertIn("compact: true", face_card)
        self.assertNotIn("LazyVGrid", face_card)
        self.assertIn("EmblemFaceGrid(", pick)
        self.assertIn("compact: false", pick)
        self.assertNotIn("LazyVGrid", pick)
        self.assertIn("EmblemFaceGrid(", mark)
        self.assertIn("compact: true", mark)
        self.assertNotIn("LazyVGrid", mark)
        self.assertIn("PersonEmblem.faces", tests)
        self.assertIn("Set(PersonEmblem.faces)", tests.replace(" ", ""))
        comms_qa = next(
            line for line in qa.splitlines() if "FACE picks the person mark" in line
        )
        self.assertIn("scroll", comms_qa.lower())
        self.assertIn("look", comms_qa.lower())
        mark_qa = next(
            line
            for line in qa.splitlines()
            if "NAME, NOTE, FACE" in line or ("MARK" in line and "FACE" in line)
        )
        self.assertIn("scroll", mark_qa.lower())
        you_qa = next(
            line for line in qa.splitlines() if "Hold YOU or a party emblem" in line
        )
        self.assertIn("scroll", you_qa.lower())
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)
        self.assertNotIn("Google", qa)


def person_emblem_faces(src: str) -> list[str]:
    block = src.split("static let faces")[1].split("= [", 1)[1].split("]", 1)[0]
    return re.findall(r"\.(\w+)", block)


def _cluster_span(order: list[str], group: list[str]) -> int:
    idx = [order.index(name) for name in group]
    return max(idx) - min(idx)


def mesh_is_self_addressed(from_id: str, to: str, local_id: str) -> bool:
    dest = to.strip()
    return from_id == local_id and dest in ("YOU", local_id)


def _rgba(src: str, name: str) -> tuple[float, float, float, float]:
    match = re.search(
        rf"static let {re.escape(name)} = RGBA\(r: ([0-9.]+), g: ([0-9.]+), b: ([0-9.]+), a: ([0-9.]+)\)",
        src,
    )
    if match is None:
        raise AssertionError(f"RGBA {name} missing")
    return tuple(float(match.group(i)) for i in range(1, 5))


def _multiply(
    pixel: tuple[float, float, float], lamp: tuple[float, float, float]
) -> tuple[float, float, float]:
    return (pixel[0] * lamp[0], pixel[1] * lamp[1], pixel[2] * lamp[2])


def _wash(
    pixel: tuple[float, float, float],
    overlay: tuple[float, float, float],
    alpha: float = 0.28,
) -> tuple[float, float, float]:
    return tuple(p * (1 - alpha) + o * alpha for p, o in zip(pixel, overlay))


class NightRedLampTests(unittest.TestCase):
    """Night red is a lamp, not a pink wash. Void stays void. MapLibre stays mounted."""

    def test_lamp_keeps_void_void_and_leaves_accent_on_red(self):
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        night = read("Packages", "NightRed", "Sources", "NightRed", "NightRed.swift")
        lamp = _rgba(tokens, "nightRed")
        self.assertGreaterEqual(lamp[0], 0.95)
        self.assertLess(lamp[1], 0.12)
        self.assertLess(lamp[2], 0.05)
        void = (0.0, 0.0, 0.0)
        silver = (0.77, 0.80, 0.84)
        accent = (225.0 / 255.0, 6.0 / 255.0, 0.0)
        lit_void = _multiply(void, lamp[:3])
        lit_silver = _multiply(silver, lamp[:3])
        lit_accent = _multiply(accent, lamp[:3])
        self.assertEqual(lit_void, void)
        self.assertGreater(lit_silver[0], 0.7)
        self.assertLess(lit_silver[1], 0.1)
        self.assertGreater(lit_accent[0], lit_silver[0])
        caution = _rgba(tokens, "caution")[:3]
        lit_caution = _multiply(caution, lamp[:3])
        self.assertGreater(lit_caution[0], lit_silver[0])
        self.assertGreater(lit_accent[0], lit_caution[0])
        heat = _rgba(tokens, "heat")[:3]
        lit_heat = _multiply(heat, lamp[:3])
        self.assertGreater(lit_heat[0], lit_silver[0])
        self.assertLess(lit_heat[1], lit_caution[1])
        self.assertNotEqual(lit_heat, lit_caution)
        washed = _wash(void, (0.55, 0.05, 0.05))
        self.assertGreater(washed[0], 0.1)
        self.assertIn("static let identity", night)
        self.assertIn("var multiply", night)
        self.assertIn("static let dim", night)
        self.assertIn("enabled ? BlackoutTokens.Color.nightRed : Self.identity", night)

    def test_glass_multiplies_and_never_washes(self):
        root = read("Blackout", "RootChrome.swift")
        inst = read("Blackout", "InstrumentsView.swift")
        theme = read("Blackout", "Theme.swift")
        app = read("Blackout", "AppRuntime.swift")
        emit_night = read("tools", "v3", "emit_swift.py")
        for body in (root, inst, theme, app, emit_night):
            self.assertNotIn("best in class", body.lower())
        self.assertIn("nightRedLamp", theme)
        self.assertIn(".colorMultiply", theme)
        self.assertIn("NightRedState.dim", theme)
        self.assertIn(".nightRedLamp(runtime.night)", root)
        self.assertIn(".nightRedLamp(runtime.night)", inst)
        self.assertNotIn("Theme.nightRed.opacity(0.28)", root)
        self.assertNotIn("opacity(0.28).ignoresSafeArea()", root)
        self.assertIn("MapTab(runtime: runtime)", root)
        self.assertNotIn("if runtime.night.enabled { MapTab", root)
        self.assertNotIn(".spring(", theme)
        self.assertNotIn(".spring(", root)


class SunLampTests(unittest.TestCase):
    """Outdoor glare. Pale field, near-black type. Not Smart Invert."""

    def test_night_and_sun_are_one_row_and_one_at_a_time(self):
        self.assertEqual(tap_lamp("off", "night"), "night")
        self.assertEqual(tap_lamp("night", "sun"), "sun")
        self.assertEqual(tap_lamp("sun", "night"), "night")
        self.assertEqual(tap_lamp("sun", "sun"), "off")
        self.assertEqual(tap_lamp("night", "night"), "off")
        night = read("Packages", "NightRed", "Sources", "NightRed", "NightRed.swift")
        self.assertIn("enum HUDLamp", night)
        self.assertIn("case sun", night)
        self.assertIn("current == tap ? .off : tap", night)
        inst = read("Blackout", "InstrumentsView.swift")
        hud = inst.split('sectionLabel("HUD")')[1].split('sectionLabel("MAP")')[0]
        self.assertIn('Button("NIGHT")', hud)
        self.assertIn('Button("SUN")', hud)
        self.assertIn("HStack(spacing: 1)", hud)
        self.assertIn("HUDActionStyle(filled:", hud)
        self.assertIn("runtime.tapLamp(.night)", hud)
        self.assertIn("runtime.tapLamp(.sun)", hud)
        self.assertNotIn('hudToggle("NIGHT RED"', inst)
        self.assertIn('sectionLabel("SUN")', inst)
        self.assertIn("sunPlate", inst)

    def test_sun_is_a_real_palette_not_smart_invert(self):
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        theme = read("Blackout", "Theme.swift")
        app = read("Blackout", "AppRuntime.swift")
        root = read("Blackout", "RootChrome.swift")
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        pack = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        )
        field = _rgba(tokens, "sunField")
        ink = _rgba(tokens, "sunInk")
        void = _rgba(tokens, "void")
        self.assertGreater(field[0], 0.82)
        self.assertGreater(field[1], 0.82)
        self.assertGreater(field[2], 0.78)
        self.assertLess(ink[0], 0.12)
        self.assertLess(ink[1], 0.12)
        self.assertLess(ink[2], 0.12)
        self.assertEqual(void[:3], (0.0, 0.0, 0.0))
        self.assertIn('sunFieldHex = "#E6E3D9"', tokens)
        self.assertIn('sunInkHex = "#141414"', tokens)
        self.assertIn('accentHex = "#E10600"', tokens)
        self.assertIn("static var lamp: HUDLamp", theme)
        self.assertIn("static func bind(", theme)
        self.assertIn("static func strokeWidth(", theme)
        self.assertIn("lamp == .sun ? points + 1 : points", theme)
        self.assertIn("case .sun:", theme)
        self.assertIn("sunField", theme)
        self.assertIn("sunInk", theme)
        glass = theme.split("static func glass(")[1].split("struct HUDMark")[0]
        self.assertIn("case .sun:", glass)
        self.assertNotIn("ultraThinMaterial", glass)
        self.assertNotIn(".colorInvert(", theme)
        self.assertNotIn("smartInvert", theme.lower())
        self.assertNotIn("Smart Invert", app)
        self.assertNotIn("UIAccessibilityIsInvertColorsEnabled", app)
        self.assertNotIn(".colorInvert(", root)
        self.assertIn("Theme.bind(runtime.lamp)", root)
        self.assertIn(".nightRedLamp(runtime.night)", root)
        self.assertIn("UIScreen.main.brightness = 1", app)
        self.assertIn("brightnessDidChangeNotification", app)
        self.assertIn('forKey: "hud.lamp"', app)
        self.assertIn("func tapLamp(", app)
        self.assertIn("sun: runtime.lamp == .sun", read("Blackout", "MapTab.swift"))
        self.assertIn("var sun: Bool", offline)
        self.assertIn("applyHUDLamp", offline)
        self.assertIn("sunInkHex", pack)
        self.assertIn("sunFieldHex", pack)
        self.assertNotIn("if runtime.lamp == .sun { MapTab", root)
        self.assertNotIn(".spring(", theme)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("NIGHT · SUN", qa)
        self.assertIn("pale field", qa.lower())
        self.assertIn("brightness", qa.lower())
        self.assertIn("Not Smart Invert", qa)
        self.assertNotIn("Use Smart Invert", qa)
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)


class InstrumentNorthAndBodyTests(unittest.TestCase):
    """BODY instruments have to drive the heading, the lamp, and the radio."""

    def test_mag_true_selects_heading_and_true_north_updates_chrome(self):
        emblem = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "PersonEmblem.swift"
        )
        app = read("Blackout", "AppRuntime.swift")
        inst = read("Blackout", "InstrumentsView.swift")
        board = read("Packages", "Instruments", "Sources", "Instruments", "Instruments.swift")
        self.assertIn("magNorth: Bool", emblem)
        self.assertIn("func setTrueNorth()", app)
        self.assertIn("toolChrome = MagTrueChip.chrome", app.split("func setTrueNorth()")[1])
        self.assertIn("magNorth: magNorth", app)
        self.assertIn("runtime.setTrueNorth()", inst)
        self.assertNotIn("runtime.instruments.setTrueNorth()", inst)
        self.assertIn("func toggleMagTrue()", board)
        self.assertIn("locationManagerShouldDisplayHeadingCalibration", app)
        self.assertIn("kCLLocationAccuracyBestForNavigation", app)
        self.assertIn("preferWiredPTT", app)
        self.assertIn("LAMP · NONE", inst)
        self.assertIn("runtime.calibrateCompass()", inst)
        self.assertIn("runtime.attachUSB_C_PTT", inst)
        self.assertIn("runtime.attachGNSSPuck", inst)
        self.assertIn("import Observation", board)
        self.assertIn("@Observable", board)
        auction = read(
            "Packages", "BatteryAuction", "Sources", "BatteryAuction", "BatteryAuction.swift"
        )
        self.assertIn("import Observation", auction)
        self.assertIn("@Observable", auction)
        self.assertIn("func setPocket(", app)
        self.assertIn("runtime.setPocket", inst)
        self.assertNotIn("runtime.power.setPocket", inst)
        pocket = app.split("func setPocket(")[1].split("func ", 1)[0]
        self.assertIn("applyMapKeepAwake()", pocket)
        keep = app.split("func applyMapKeepAwake()")[1].split("func ", 1)[0]
        self.assertIn("pocket:", keep)
        cal = app.split("func requestHeadingCalibration()")[1].split("func ", 1)[0]
        self.assertIn("stopUpdatingHeading()", cal)
        self.assertIn("startHeading()", cal)
        mic = read("Blackout", "PTTMic.swift")
        begin = mic.split("private func beginRecorder()")[1].split("private func pcm(")[0]
        self.assertIn("applyPreferredInput()", begin)
        self.assertGreater(begin.index("applyPreferredInput()"), begin.index("setActive(true)"))
        usng = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        ).split("enum USNG")[1].split("enum PackGeometry")[0]
        self.assertIn("lat.isFinite", usng)
        keep_src = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        ).split("enum MapKeepAwake")[1].split("enum MapCanvasHit")[0]
        self.assertIn("pocket: Bool", keep_src)

    def test_instruments_use_live_you_and_a_real_usng(self):
        app = read("Blackout", "AppRuntime.swift")
        usng = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        ).split("enum USNG")[1].split("enum PackGeometry")[0]
        tests = read(
            "Packages", "MapLibreMap", "Tests", "MapLibreMapTests", "MapLibreMapTests.swift"
        )
        qa = read("docs", "SOLO_QA.md")
        ruler = app.split("func tapRuler()")[1].split("func ", 1)[0]
        usng_tap = app.split("func tapUSNG()")[1].split("func ", 1)[0]
        mag = app.split("func tapMagTrue()")[1].split("func ", 1)[0]
        true_n = app.split("func setTrueNorth()")[1].split("func ", 1)[0]
        cal = app.split("func calibrateCompass()")[1].split("func ", 1)[0]
        gnss = app.split("func attachGNSSPuck(")[1].split("func ", 1)[0]
        activate = app.split("func arm()")[1].split("func joinNet")[0]
        boot = app.split("func arm(")[0]
        self.assertIn("gnssYou", ruler)
        self.assertIn("routeTarget", ruler)
        self.assertNotIn("youCoordinate()", ruler)
        self.assertNotIn("destination()", ruler)
        self.assertIn("fix.arm()", ruler)
        self.assertIn("gnssYou", usng_tap)
        self.assertNotIn("youCoordinate()", usng_tap)
        self.assertIn("fix.arm()", usng_tap)
        self.assertIn("fix.arm()", mag)
        self.assertIn("fix.arm()", true_n)
        self.assertIn("fix.arm()", cal)
        self.assertIn("fix.arm()", gnss)
        self.assertIn("fix.arm()", activate)
        self.assertNotIn("fix.arm()", boot)
        self.assertIn("CDEFGHJKLMNPQRSTUVWX", usng)
        self.assertIn("ABCDEFGHJKLMNPQRSTUV", usng)
        self.assertNotIn("USNG %d / %.4f %.4f", usng)
        self.assertIn("USNG 17T NE 8536 2823", tests)
        self.assertIn("USNG 13R CR 5889 1501", tests)
        inst_line = next(
            line
            for line in qa.splitlines()
            if "COMPASS CAL" in line and "GNSS PUCK" in line
        )
        self.assertIn("RULER —", inst_line)
        self.assertIn("USNG —", inst_line)
        self.assertIn("13R", inst_line)
        self.assertIn("live YOU", inst_line)
        self.assertIn("pack home", inst_line.lower())
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)
        self.assertNotIn("Google", qa)


class MapSearchTests(unittest.TestCase):
    """MAP SEARCH is a local index. Type or SAY. Empty waits. Miss is NO MATCH."""

    def test_lookup_is_prefix_folded_and_near_you(self):
        search = read("Packages", "Search", "Sources", "Search", "Search.swift")
        tests = read("Packages", "Search", "Tests", "SearchTests", "SearchTests.swift")
        self.assertIn("func lookup(", search)
        self.assertIn("func asking(", search)
        self.assertIn("func coordinates(in", search)
        self.assertIn("diacriticInsensitive", search)
        self.assertIn("haversine", search)
        self.assertIn("enum SearchHUDWord", search)
        self.assertIn('return "WATER"', search)
        self.assertIn('return "STREET"', search)
        self.assertIn('return "PEAK"', search)
        self.assertIn('return "ADDRESS"', search)
        self.assertIn('return "COORDINATES"', search)
        self.assertIn("case .mark:", search)
        self.assertIn("testPrefixFindsHospital", tests)
        self.assertIn("testDiacriticFoldsNinos", tests)
        self.assertIn("testProximityRanksNearer", tests)
        self.assertIn("testCoordinatePasteIsAHit", tests)
        self.assertIn("testEmptyQueryIsNotADump", tests)
        self.assertIn("testAvenueAliasAndNamePrefix", tests)
        self.assertIn("1115 FT", tests)
        self.assertIn("7.7 MI", tests)
        self.assertIn("testTypoFindsGardner", tests)
        self.assertIn("testLookupCapsAndStillFindsAPrefix", tests)
        self.assertIn("testHouseNumberFindsMontanaAddress", tests)
        self.assertIn("editDistanceOne", search)
        self.assertIn("tokenIndex", search)
        self.assertIn("struct SearchExtra", search)
        self.assertIn("func editsOne(", search)
        self.assertIn("func houseQuery", search)
        self.assertIn("func streetName(near", search)
        self.assertIn("func streetNames(along:", search)
        self.assertIn("streetName(near: a.lat, lon: a.lon)", search)
        self.assertIn("struct AddrRange", search)
        self.assertIn("avenida", search)
        self.assertNotIn("best in class", search.lower())
        self.assertNotIn("best in class", tests.lower())
        self.assertNotIn("Waze", search)
        self.assertNotIn("Waze", tests)

    def test_map_types_and_says_and_does_not_invent(self):
        tab = read("Blackout", "MapTab.swift")
        search = tab.split("private func search()")[1]
        chrome = tab.split("private var searchField")[1].split("private var overlayRail")[0]
        hits = tab.split("private var hitList")[1].split("private var markList")[0]
        marks = tab.split("private var markList")[1].split("private var fieldChrome")[0]
        self.assertIn('packURL("search.json")', tab)
        self.assertIn("onChange(of: query)", tab)
        self.assertIn('HUDField("SEARCH"', chrome)
        self.assertNotIn("TextField(", tab)
        self.assertNotIn(".submitLabel(.search)", tab)
        self.assertIn('Button("SAY")', chrome)
        self.assertIn("SAY FAILED", chrome)
        self.assertIn("NO MATCH", tab)
        self.assertIn("SearchIndex.asking(", tab)
        self.assertIn("runtime.gnssYou", search)
        self.assertIn(".lookup(", search)
        self.assertIn("Task.detached(priority: .userInitiated)", search)
        self.assertIn("SearchExtra(name:", search)
        self.assertIn("looking = true", search)
        self.assertIn("applySearch(", search)
        self.assertNotIn('["name": query', tab)
        self.assertNotIn("youCoordinate()", search)
        self.assertNotIn("lastKnownFix", search)
        self.assertNotIn('"\\(h.name) · \\(h.kind)"', hits)
        self.assertIn("SearchHUDWord.from", hits)
        self.assertIn("SearchIndex.rangeLabel", hits)
        search_src = read("Packages", "Search", "Sources", "Search", "Search.swift")
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        voice = read("Packages", "Router", "Sources", "Router", "VoiceNav.swift")
        self.assertIn("BlackoutTokens.Distance.hud", search_src)
        self.assertIn("func hud(", tokens)
        self.assertIn("func spoken(", tokens)
        self.assertIn("Distance.hud", voice)
        self.assertIn("Distance.spoken", voice)
        self.assertNotIn("%.0f M", search_src)
        self.assertNotIn("%.1f KM", search_src)
        self.assertIn("SearchIndex.asking(", marks)
        self.assertIn("!looking, hits.isEmpty", tab)
        load = tab.split("private func loadIndex()")[1].split("private func applyLoadedIndex")[0]
        self.assertIn("Task.detached(priority: .userInitiated)", load)
        self.assertIn("Data(contentsOf:", load)
        self.assertNotIn("@MainActor", load)
        self.assertNotIn("OpenStreetMap", tab)
        self.assertNotIn("best in class", tab.lower())
        self.assertNotIn(".spring(", tab)

    def test_solo_qa_and_device_score_map_search(self):
        qa = read("docs", "SOLO_QA.md")
        device = read("docs", "DEVICE.md")
        self.assertIn("as you type", qa.lower())
        self.assertIn("NO MATCH", qa)
        self.assertIn("MAP SEARCH", qa)
        self.assertIn("Hits cap at five", qa)
        self.assertIn("Montana Avenue", qa)
        self.assertIn("Gardner Peak", qa)
        self.assertIn("MAP SEARCH", device)
        self.assertIn("NO MATCH", device)
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("best in class", device.lower())
        self.assertNotIn("Search FTS returns pack POI names", qa)


class LiveStreetGuideTests(unittest.TestCase):
    """WALK/DRIVE keep speaking as YOU move. The field stays one short line."""

    def test_live_guide_wires_gnss_to_remaining_chrome_and_voice(self):
        app = read("Blackout", "AppRuntime.swift")
        qa = read("docs", "SOLO_QA.md")
        device = read("docs", "DEVICE.md")
        live = ROOT.joinpath(
            "Packages", "Router", "Sources", "Router", "LiveNav.swift"
        )
        self.assertTrue(live.is_file())
        live_text = live.read_text()
        voice = read("Packages", "Router", "Sources", "Router", "VoiceNav.swift")
        self.assertIn("enum LiveNav", live_text)
        self.assertIn("func progress(", live_text)
        self.assertIn("func applyLiveGuide()", app)
        pull = app.split("func pullFix()")[1].split("static func resourceRoot")[0]
        self.assertIn("applyLiveGuide()", pull)
        guide = app.split("func applyLiveGuide()")[1].split("static func resourceRoot")[0]
        self.assertIn("LiveNav.progress", guide)
        self.assertIn("VoiceNav.arrive", guide)
        self.assertIn("SpeakStatus.offRouteLine", guide)
        self.assertIn("SpeakStatus.chrome(", guide)
        self.assertIn("remainingCoords", guide)
        self.assertIn("navigate(mode: travelMode)", guide)
        self.assertIn("liveSpokenTurn", app)
        nav = app.split("func navigate(mode: TravelMode)")[1].split("func tapRuler")[0]
        self.assertIn("speakMap()", nav)
        self.assertNotIn("guard let dest else { return }", nav)
        self.assertNotIn("guard let from = fieldYou else { return }", nav)
        dest = app.split("private func destination()")[1].split("private func runBoot")[0]
        self.assertNotIn("marks.last", dest)
        pick = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift"
        ).split("public enum RouteTarget", 1)[1]
        self.assertNotIn("if let lastMark { return lastMark }", pick)
        guide = app.split("func applyLiveGuide()")[1].split("static func resourceRoot")[0]
        self.assertIn("gnssYou", guide)
        self.assertIn("YOU move", qa)
        self.assertIn("OFF ROUTE", qa)
        self.assertIn("SPEAK replays", qa)
        self.assertIn("YOU move", device)
        self.assertIn("OFF ROUTE", device)
        self.assertIn("static let offRoute = \"OFF ROUTE\"", voice)
        self.assertLessEqual(len("SPEAK · OFF ROUTE"), 32)
        for slogan in ("best in class", "Waze", "Google Maps", "Apple Maps"):
            self.assertNotIn(slogan, live_text)
            self.assertNotIn(slogan, app)
            self.assertNotIn(slogan, qa)
            self.assertNotIn(slogan, device)
            self.assertNotIn(slogan, voice)


class AddressHoldCardTests(unittest.TestCase):
    """Type a house number. The glass card is the address, not a DEST dump."""

    def test_address_hit_opens_glass_with_walk_and_mark(self):
        tab = read("Blackout", "MapTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        hold = read("Blackout", "HoldCard.swift")
        card = read("Blackout", "AddressHoldCard.swift")
        search = read("Packages", "Search", "Sources", "Search", "Search.swift")
        tests = ROOT.joinpath("Packages", "MapLibreMap", "Tests")
        count = 0
        for path in tests.rglob("*.swift"):
            count += len(re.findall(r"func test[A-Z]\w+\(", path.read_text()))
        self.assertEqual(count, 177)
        self.assertIn("struct HeldAddress", hold)
        self.assertIn("struct AddressHoldCard", card)
        self.assertIn("var heldAddress", app)
        self.assertIn("func holdAddress(", app)
        self.assertIn("func walkHeldAddress(", app)
        self.assertIn("func markHeldAddress(", app)
        self.assertIn("AddressHoldCard(", tab)
        self.assertIn("runtime.heldAddress", tab)
        self.assertIn("heldAddress!=nil", tab.replace(" ", ""))
        self.assertIn('Button("WALK")', card)
        self.assertIn('Button("MARK")', card)
        self.assertIn("ADDRESS", card)
        self.assertIn("CITY", card)
        self.assertIn("POST", card)
        self.assertIn("COORDINATES", card)
        self.assertIn("SURE", card)
        self.assertIn("WHAT", card)
        self.assertIn("BEARING", card)
        walk = app.split("func walkHeldAddress(")[1].split("func markHeldAddress(")[0]
        self.assertIn("pickDestination", walk)
        self.assertIn("navigate(mode: .walk)", walk)
        self.assertIn("Task { @MainActor in", walk)
        self.assertIn('kind=="address"', tab.replace(" ", "") + search.replace(" ", ""))
        self.assertNotIn("tel://", card.lower())
        self.assertNotIn("Color.orange", card)
        self.assertNotIn("Color.green", card)
        self.assertNotIn("best in class", card.lower())
        self.assertNotIn(".spring(", card)
        self.assertNotIn("Waze", card)
        self.assertIn("case address", search)
        self.assertIn("HoldGlassShell(", card)

    def test_search_skips_a_broken_coordinate_instead_of_crashing(self):
        search = read("Packages", "Search", "Sources", "Search", "Search.swift")
        self.assertIn("isFinite", search)
        self.assertIn("rangesByStreet", search)

    def test_hold_address_refuses_a_broken_coordinate(self):
        app = read("Blackout", "AppRuntime.swift")
        hold = app.split("func holdAddress", 1)[1].split("func walkHeldAddress", 1)[0]
        self.assertIn("isFinite", hold)

    def test_hold_inspect_refuses_a_broken_coordinate(self):
        app = read("Blackout", "AppRuntime.swift")
        hold = app.split("func holdInspect", 1)[1].split("func closeHold", 1)[0]
        self.assertIn("isFinite", hold)

    def test_hold_party_and_pos_refuse_broken_coordinates(self):
        app = read("Blackout", "AppRuntime.swift")
        hold = app.split("func holdParty", 1)[1].split("func setYouName", 1)[0]
        self.assertIn("isFinite", hold)
        refresh = app.split("func refreshHeldParty", 1)[1].split("func toggleLockOn", 1)[0]
        self.assertIn("isFinite", refresh)
        send = app.split("func sendPOSIfPossible()", 1)[1].split("func applyInbound", 1)[0]
        self.assertIn("isFinite", send)
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        parse = mesh.split("public static func parse", 1)[1].split("public struct MeshTimerEvent", 1)[0]
        self.assertIn("isFinite", parse)
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("runtime.eyeCanvasPips()", tab)
        pips = app.split("func eyeCanvasPips")[1].split("func eyeTrails")[0]
        self.assertIn("isFinite", pips)
        you = app.split("var gnssYou")[1].split("private func destination")[0]
        self.assertIn("isFinite", you)
        self.assertIn("fieldYou", you)
        offline = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift")
        hold_fn = offline.split("func handleHold", 1)[1].split("func personMark", 1)[0]
        self.assertIn("CLLocationCoordinate2DIsValid", hold_fn)
        sync = offline.split("func syncPartyMarks", 1)[1].split("func syncRoute", 1)[0]
        self.assertIn("CLLocationCoordinate2DIsValid", sync)
        make = offline.split("func makeUIView")[1].split("func updateUIView")[0]
        self.assertIn("CLLocationCoordinate2DIsValid", make)
        cam = offline.split("func applyCamera")[1].split("func fitPack")[0]
        self.assertIn("CLLocationCoordinate2DIsValid", cam)
        exped = read("Blackout", "ExpeditionTab.swift")
        self.assertNotIn("ForEach(runtime.timers.doneLines(), id: \\.self)", exped)
        self.assertNotIn("ForEach(runtime.kit.hazards, id: \\.self)", exped)
        comms = read("Blackout", "CommsTab.swift")
        self.assertNotIn("ForEach(runtime.mesh.nearby, id: \\.self)", comms)
        field = read("Blackout", "FieldTab.swift")
        self.assertNotIn("ForEach(g.lookalikes, id: \\.self)", field)

    def test_solo_qa_scores_address_search(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("221 Montana", qa)
        self.assertIn("ADDRESS", qa)
        self.assertIn("address card", qa.lower())
        self.assertIn("WALK", qa)
        self.assertIn("CITY", qa)
        self.assertIn("POST", qa)
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)


class YouIdentitySyncTests(unittest.TestCase):
    """YOU is one GNSS place. Pack center is the pack, never YOU."""

    def test_field_you_is_gnss_not_the_pack(self):
        app = read("Blackout", "AppRuntime.swift")
        you = app.split("var fieldYou")[1].split("private func destination")[0]
        self.assertIn("gnssYou", you)
        self.assertIn("lastKnownFix", you)
        self.assertNotIn("pack?.lat", you)
        self.assertNotIn("packCenter", you)
        self.assertNotIn("UserPuck.coordinate", you)

    def test_pos_and_condition_sos_do_not_broadcast_the_pack(self):
        app = read("Blackout", "AppRuntime.swift")
        send = app.split("func sendPOSIfPossible()", 1)[1].split("func applyInbound", 1)[0]
        self.assertIn("fieldYou", send)
        self.assertNotIn("pack?.lat", send)
        self.assertNotIn("pack?.lon", send)
        self.assertNotIn("pack?.center", send)
        sos = app.split("func offerConditionSOS", 1)[1].split("func iamOK", 1)[0]
        self.assertIn("fieldYou", sos)
        self.assertNotIn("pack?.lat", sos)
        self.assertNotIn("pack?.lon", sos)

    def test_profile_walk_and_bearing_use_the_same_you(self):
        app = read("Blackout", "AppRuntime.swift")
        hold = app.split("func holdParty", 1)[1].split("func setYouName", 1)[0]
        self.assertIn("fieldYou", hold)
        refresh = app.split("func refreshHeldParty", 1)[1].split("func toggleLockOn", 1)[0]
        self.assertIn("fieldYou", refresh)
        course = app.split("func partyCourse", 1)[1].split("func partyFix", 1)[0]
        self.assertIn("fieldYou", course)
        self.assertIn("NO FIX", course)
        address = app.split("func addressCourse", 1)[1].split("func addressFix", 1)[0]
        self.assertIn("fieldYou", address)
        self.assertIn("NO FIX", address)
        nav = app.split("func navigate(mode:", 1)[1].split("func fitPack", 1)[0]
        self.assertIn("hasYouFix:", nav)
        self.assertIn("fieldYou", nav)
        speak = app.split("func speakMap()", 1)[1].split("func closeSpeakTurns", 1)[0]
        self.assertIn("fieldYou", speak)
        self.assertNotIn("youCoordinate()", speak)

    def test_canvas_hides_you_until_a_fix_exists(self):
        tab = read("Blackout", "MapTab.swift")
        canvas = tab.split("func canvas(pack:", 1)[1].split("private var hudReserve", 1)[0]
        self.assertIn("runtime.fieldYou", canvas)
        self.assertIn("showYou:", canvas)
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        self.assertIn("var showYou: Bool", offline)
        apply = offline.split("func apply(_ spec: OverlaySpec", 1)[1].split(
            "func syncPersonMarks", 1
        )[0]
        self.assertIn("spec.showYou", apply)

    def test_walk_names_no_fix_when_you_is_missing(self):
        route = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift")
        self.assertIn("case noYou", route)
        self.assertIn("NO FIX", route)
        self.assertIn("hasYouFix", route)
        voice = read("Packages", "Router", "Sources", "Router", "VoiceNav.swift")
        status = voice.split("enum SpeakStatus", 1)[1]
        self.assertIn('noFix = "NO FIX"', status)
        self.assertIn("SPEAK · NO FIX", read("docs", "SOLO_QA.md"))
        tests = read(
            "Packages",
            "MapLibreMap",
            "Tests",
            "MapLibreMapTests",
            "MapLibreMapTests.swift",
        )
        self.assertIn("testUserPuckStaysAtLastKnownWhenFixIsOutsideBBox", tests)
        self.assertNotIn("testUserPuckFallsBackToPackCenterWhenFixIsOutsideBBox", tests)

    def test_solo_qa_scores_one_you(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("Pack center is the pack, never YOU", qa)
        self.assertIn("WALK — NO FIX", qa)
        self.assertNotIn("best in class", qa.lower())


class MapCanvasHonestyTests(unittest.TestCase):
    """MAP camera stays on packed tiles, YOU, or DEST — never a void world."""

    def test_pinch_stays_on_packed_tiles(self):
        cam = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        self.assertIn("static let minZoom: Double = 6", cam)
        self.assertIn("static let maxZoom: Double = 16", cam)
        self.assertIn("static let godsEyeMaxZoom: Double = 17.5", cam)
        tiles = read("tools", "v3", "tiles.py")
        self.assertIn("MIN_ZOOM = 6", tiles)
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        interact = offline.split("private func applyInteraction")[1].split(
            "public final class Coordinator"
        )[0]
        self.assertIn("minimumZoomLevel = PackCamera.holdMinZoom(godsEye: godsEye)", interact)
        self.assertNotIn("minimumZoomLevel = PackCamera.minZoom", interact)
        self.assertIn("maximumZoomLevel = PackCamera.holdMaxZoom(godsEye: godsEye)", interact)
        self.assertIn("godsEye ? godsEyeMaxZoom : maxZoom", cam)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("Pinch stays on packed tiles", qa)
        self.assertNotIn("best in class", qa.lower())

    def test_off_glass_dest_is_framed_without_stealing_lock_on(self):
        cam = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        self.assertIn("static func shouldFrameDest(", cam)
        self.assertIn("static func destIsOnGlass(", cam)
        self.assertIn("static func shouldOpenOnYou(", cam)
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        camera = offline.split("func applyCamera")[1].split("func fitPack")[0]
        self.assertIn("PackCamera.shouldFrameDest", camera)
        self.assertIn("PackCamera.destIsOnGlass", camera)
        self.assertIn("PackCamera.shouldOpenOnYou", camera)
        self.assertIn("storedShowYou", camera)
        tests = read(
            "Packages",
            "MapLibreMap",
            "Tests",
            "MapLibreMapTests",
            "MapLibreMapTests.swift",
        )
        self.assertIn("testPackCameraFramesDestAndOpensOnYou", tests)

    def test_lock_on_arms_at_walking_zoom(self):
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        camera = offline.split("func applyCamera")[1].split("func fitPack")[0]
        follow = camera.split("PackCamera.shouldFollow")[1].split("storedLockOn = spec.lockOn")[0]
        self.assertIn("!storedLockOn", follow)
        self.assertIn("zoomLevel: PackCamera.openZoom", follow)

    def test_gods_eye_fits_the_pack_and_drops_lock_on(self):
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        tab = read("Blackout", "MapTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        theme = read("Blackout", "Theme.swift")
        cam = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        tests = read(
            "Packages",
            "MapLibreMap",
            "Tests",
            "MapLibreMapTests",
            "MapLibreMapTests.swift",
        )
        qa = read("docs", "SOLO_QA.md")
        device = read("docs", "DEVICE.md")
        self.assertIn('godsEyeTitle = "KHAN EYE"', tokens)
        self.assertIn("BlackoutTokens.MapOverlay.godsEyeTitle", tab)
        self.assertIn("BlackoutTokens.MapOverlay.godsEyeTitle", read("Blackout", "InstrumentsView.swift"))
        self.assertIn("toggleGodsEye()", tab)
        self.assertIn("HUDOverlayChipStyle(filled: runtime.godsEye)", tab)
        self.assertIn("PackCamera.liveLockOn", tab)
        self.assertIn("HUDOverlayChipStyle(filled: PackCamera.liveLockOn", tab)
        self.assertNotIn('Button("FIT PACK")', tab)
        self.assertNotIn("best in class", tab.lower())
        overlay = theme.split("struct HUDOverlayChipStyle")[1].split("struct MapFieldDestChipStyle")[0]
        self.assertIn("var filled: Bool", overlay)
        self.assertIn("Theme.glass", overlay)
        self.assertIn("Color.white", overlay)
        self.assertNotIn("Rectangle().fill(Theme.silver)", overlay)
        rail = tab.split("private var overlayRail")[1].split("private var hitList")[0]
        self.assertIn("value: runtime.godsEye", rail)
        self.assertIn("value: runtime.lockOn", rail)
        canvas = tab.split("private func canvas")[1].split("private var coverUp")[0]
        self.assertNotIn("value: runtime.godsEye", canvas)
        self.assertIn("var godsEye", app)
        eye = app.split("func toggleGodsEye(")[1].split("func ", 1)[0]
        self.assertIn("godsEye = true", eye)
        self.assertIn("lockOn = false", eye)
        self.assertIn("fitPack()", eye)
        self.assertIn("EyeDesk.save(true)", eye)
        lock = app.split("func toggleLockOn(")[1].split("func ", 1)[0]
        self.assertIn("godsEye = false", lock)
        self.assertIn("EyeDesk.load()", app)
        self.assertIn('persistKey = "hud.eye"', read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "EyeDesk.swift"))
        desk = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "EyeDesk.swift")
        self.assertIn("enum EyeDesk", desk)
        self.assertIn("func framePoints(", desk)
        self.assertIn("OFF AERIAL", desk)
        self.assertIn("PACK IR", desk)
        self.assertIn("NO CARD · DON'T GUESS", desk)
        self.assertIn('sceneNames = ["CAMP", "RIDGE", "TRUCK"]', desk)
        self.assertIn("liveDeskLayers", desk)
        self.assertIn("static func shouldHoldPack(", cam)
        self.assertIn("static func shouldLeavePack(", cam)
        self.assertIn("static func liveLockOn(", cam)
        self.assertIn("static func liveGodsEye(", cam)
        self.assertIn("static let packPaddingPoints", cam)
        self.assertIn("static let packSidePaddingPoints", cam)
        self.assertIn("static let godsEyePitch: Double = 45", cam)
        self.assertIn("static let walkPitch: Double = 55", cam)
        self.assertIn("static func followHeading(", cam)
        self.assertIn("static let godsEyeRangeFactor: Double = 1.15", cam)
        self.assertIn("static let godsEyeFlySeconds", cam)
        self.assertIn("static func packCenter(", cam)
        self.assertIn("static func packRadiusMeters(", cam)
        self.assertIn("static func godsEyeDistance(", cam)
        self.assertIn("static func godsEyeCameraDistance(", cam)
        self.assertIn("static func godsEyeFlyPeakAltitude(", cam)
        self.assertIn("static let godsEyeFlyPeakFactor", cam)
        self.assertIn("static func holdPitch(", cam)
        self.assertIn("static func allowsOrbit(", cam)
        orbit = cam.split("static func allowsOrbit(")[1].split("static func allowsPan(")[0]
        self.assertIn("true", orbit)
        self.assertNotIn("return false", orbit)
        self.assertIn("static func allowsPan(", cam)
        self.assertIn("static func allowsTilt(", cam)
        self.assertIn("static func cameraStaysOnPack(", cam)
        self.assertIn("static let godsEyeMaxPitch: Double = 60", cam)
        self.assertIn("static func holdMinPitch(", cam)
        self.assertIn("static func holdMaxPitch(", cam)
        self.assertIn("godsEye: Bool", cam.split("static func shouldFrameDest(")[1].split("static func destIsOnGlass(")[0])
        self.assertIn("godsEye: Bool", cam.split("static func shouldOpenOnYou(")[1].split("static func shouldFrameDest(")[0])
        self.assertIn("godsEye: Bool", cam.split("static func shouldFollow(")[1].split("static func shouldFitRoute(")[0])
        self.assertIn("godsEye: Bool", cam.split("static func shouldFitRoute(")[1].split("public enum PackStyle")[0])
        camera = offline.split("func applyCamera")[1].split("func fitPack")[0]
        self.assertIn("PackCamera.shouldHoldPack", camera)
        self.assertIn("PackCamera.shouldLeavePack", camera)
        self.assertIn("PackCamera.liveLockOn", camera)
        self.assertIn("PackCamera.followHeading", camera)
        self.assertIn("godsEye: spec.godsEye", camera)
        fit_token = camera.split("if spec.fitToken != fittedFitToken")[1].split("return")[0]
        self.assertIn("PackCamera.shouldHoldPack", fit_token)
        self.assertIn("fitPack", fit_token)
        self.assertIn("godsEye: spec.godsEye", fit_token)
        fit = offline.split("func fitPack")[1].split("func fitRoute")[0]
        self.assertNotIn("PackCamera.packPaddingPoints", fit)
        self.assertNotIn("PackCamera.packSidePaddingPoints", fit)
        self.assertNotIn("PackCamera.edgePaddingPoints", fit)
        self.assertNotIn("view.fly(", fit)
        self.assertNotIn("flyToCamera", fit)
        self.assertNotIn("fitting:", fit)
        self.assertNotIn("fittingCoordinateBounds", fit)
        self.assertIn("PackCamera.godsEyePitch", fit)
        self.assertIn("PackCamera.godsEyeHeading", fit)
        self.assertIn("PackCamera.godsEyeDistance", fit)
        self.assertNotIn("PackCamera.godsEyeCameraDistance", fit)
        self.assertIn("acrossDistance: gev", fit)
        self.assertIn("lookingAtCenter", fit)
        self.assertIn("view.setCamera", fit)
        self.assertIn("PackCamera.packCenter", fit)
        self.assertNotIn("PackCamera.godsEyeFlySeconds", fit)
        self.assertNotIn("peakAltitude", fit)
        self.assertNotIn("PackCamera.godsEyeFlyPeakAltitude", fit)
        self.assertNotIn("EyeDesk.framePoints", fit)
        self.assertNotIn("EyeDesk.clampToPack", fit)
        self.assertIn("south: packBox.south", fit)
        self.assertIn("west: packBox.west", fit)
        self.assertIn("handleDoubleTap", offline)
        self.assertIn("OSMCredit.line", offline)
        self.assertNotIn("setVisibleCoordinateBounds", fit)
        self.assertIn("allowsRotating = PackCamera.allowsOrbit", offline)
        self.assertIn("isScrollEnabled = PackCamera.allowsPan", offline)
        self.assertIn("allowsTilting = PackCamera.allowsTilt", offline)
        self.assertNotIn("allowsTilting = true", offline)
        self.assertNotIn("allowsRotating = true", offline)
        self.assertIn("shouldChangeFrom", offline)
        self.assertIn("PackCamera.cameraStaysOnPack", offline)
        self.assertIn("minimumPitch", offline)
        self.assertIn("maximumPitch", offline)
        self.assertIn("PackCamera.holdMinPitch", offline)
        self.assertIn("PackCamera.holdMaxPitch", offline)
        self.assertIn("PackCamera.holdMaxZoom", offline)
        self.assertIn("PackCamera.holdPitch", offline)
        leave = camera.split("PackCamera.shouldLeavePack")[1].split("if PackCamera.shouldFitRoute")[0]
        self.assertIn("holdPitch(godsEye: false)", leave)
        spec = offline.split("struct OverlaySpec")[1].split("var spec:")[0]
        self.assertIn("homeLat", spec)
        self.assertIn("var godsEye: Bool", spec)
        self.assertIn("godsEye: runtime.godsEye", tab)
        count = 0
        for path in ROOT.joinpath("Packages", "MapLibreMap", "Tests").rglob("*.swift"):
            count += len(re.findall(r"func test[A-Z]\w+\(", path.read_text()))
        self.assertEqual(count, 177)
        self.assertIn("testPackCameraHoldsGodsEyeOverDestAndYou", tests)
        self.assertIn("if !runtime.godsEye", tab)
        self.assertIn("khanShadeOpacity", desk)
        self.assertIn("khanShadeOpacity", offline)
        self.assertIn("khanShadeContrast", desk)
        self.assertIn("khanLandOpacity", offline)
        self.assertIn("lineOpacity", offline.split("private struct LampPaint")[1].split("private static var capturedStyle")[0])
        self.assertIn("maximumRasterBrightness", offline.split("private struct LampPaint")[1].split("private static var capturedStyle")[0])
        eye_layers = offline.split("public static func applyEyeLayers")[1].split("public static func applyEyePalette")[0]
        self.assertIn("paintKhanShade", eye_layers)
        self.assertIn("holdsKhanDetail", eye_layers)
        self.assertIn("minimumZoomLevel = Float(PackCamera.minZoom)", eye_layers)
        self.assertIn('id.hasPrefix("khan-")', eye_layers)
        self.assertIn("!coversPhoto(id)", eye_layers)
        self.assertIn("layer.isVisible = true", eye_layers)
        covers = eye_layers.split("func coversPhoto")[1].split("func holdsKhanDetail")[0]
        self.assertIn("khanTreesLayerID", covers)
        self.assertIn("water-fill", covers)
        self.assertIn("groundWorkedFillLayerID", covers)
        self.assertIn("!godsEye || EyeDesk.layerOn(.aerial, in: layers)", eye_layers)
        self.assertIn("layer.isVisible = !aerial", eye_layers)
        self.assertNotIn("layer.isVisible = !(godsEye && aerial)", eye_layers)
        self.assertIn(
            "let shade = !godsEye || EyeDesk.layerOn(.shade, in: layers) || aerialWanted",
            eye_layers,
        )
        self.assertNotIn("&& !aerial", eye_layers)
        self.assertNotIn("satelliteRoadOpacity", eye_layers)
        inst = read("Blackout", "InstrumentsView.swift")
        self.assertIn("HUDGlassCard", inst.split("private var eyeDeskPlate")[1].split("private func eyeDeskCaption")[0])
        self.assertIn("LAYERS", inst)
        self.assertIn("LOOK", inst)
        self.assertNotIn("private var eyeDeskRail", tab)
        self.assertNotIn("HUDGlassCard", tab)
        self.assertNotIn("padding(.top, 52)", tab)
        self.assertIn("func attachKhanLayers", cam)
        self.assertIn("func attachAerialLayers", cam)
        self.assertIn("khan.pmtiles", cam)
        self.assertIn("aerial.pmtiles", cam)
        self.assertIn('"type": "fill-extrusion"', cam)
        self.assertIn("resolverVersion = 15", cam)
        khan_attach = cam.split("func attachKhanLayers")[1].split("func attachWaterLayers")[0]
        self.assertIn("removeAll", khan_attach)
        self.assertNotIn('"id": khanBuildingsLayerID', khan_attach)
        interact = offline.split("private func applyInteraction")[1].split("private var overlaySpec")[0]
        self.assertNotIn("setDirection(PackCamera.godsEyeHeading", interact)
        self.assertIn("`KHAN EYE`", qa)
        self.assertIn("No grey 3D house or tree masses on the photo", qa)
        self.assertIn("packed USGS NAIP", qa)
        self.assertIn("LAYERS / LOOK / MARK / SCENE live in INSTRUMENTS", qa)
        self.assertIn("khan eye on", desk)
        self.assertIn("frames the packed extract", qa)
        self.assertIn("north-up", qa)
        self.assertIn("standalone 3D", qa)
        self.assertIn("packed area", qa)
        self.assertIn("EYE drops LOCK-ON", qa)
        self.assertIn("never both live", qa)
        self.assertIn("clear of the HUD", qa)
        self.assertIn("leaves to the puck", qa)
        self.assertIn("holds satellite range", qa)
        self.assertIn("entire packed extract", qa)
        self.assertIn("schematic road casings hide on packed photo", qa)
        self.assertIn("hillshade stays the floor", qa)
        self.assertIn("NIGHT / SUN live in INSTRUMENTS", qa)
        self.assertIn("Marks are pins, not a second YOU", qa)
        self.assertIn("MAP footer is the pack name", qa)
        self.assertIn("sits on the overlay with LOCK-ON", qa)
        self.assertIn("pan stays on the pack", qa)
        self.assertIn("tilt stays on the pack", qa)
        self.assertIn("holds satellite range", device)
        self.assertIn("entire packed extract", device)
        self.assertIn("schematic road casings hide on packed photo", device)
        self.assertIn("hillshade stays the floor", device)
        self.assertIn("NIGHT / SUN live in INSTRUMENTS", device)
        self.assertIn("Marks are pins, not a second YOU", device)
        self.assertIn("MAP footer is the pack name", device)
        self.assertIn("sits on the overlay with LOCK-ON", device)
        self.assertIn("pan stays on the pack", device)
        self.assertIn("tilt stays on the pack", device)
        self.assertIn("frames the packed extract", device)
        self.assertIn("standalone 3D", device)
        self.assertIn("`KHAN EYE`", device)
        self.assertIn("No grey 3D house or tree masses on the photo", device)
        self.assertIn("packed USGS NAIP", device)
        self.assertIn("LAYERS / LOOK / MARK / SCENE live in INSTRUMENTS", device)
        self.assertIn("runtime.eyeCanvasPips()", tab)
        self.assertIn("PlaceMark.body", app)
        self.assertIn("PartyBody(", app)
        body = cam.split("public static func body(_ mark: MapMark)")[1].split("public enum MarkStore")[0]
        self.assertIn("kid:", body)
        self.assertIn("markKind:", body)
        self.assertLess(body.find("kid:"), body.find("markKind:"))
        self.assertIn("tap.delegate is Coordinator", offline)
        self.assertIn("tap.isEnabled = godsEye", offline)
        self.assertIn("tap.isEnabled = !godsEye", offline)
        self.assertIn("EyeDesk.noCard", read("Blackout", "HoldCard.swift"))
        self.assertNotIn("chromeNet", tab)
        self.assertIn("func applyEyeVoice", app)
        self.assertIn("func shows(", desk)
        self.assertIn("EyeDesk.offAerial", offline)
        self.assertIn("OFF AERIAL", desk)
        self.assertIn("EyeDesk.netChrome", app)
        self.assertIn("onEmptyDoubleTap", tab)
        self.assertIn("onPersonDoubleTap", tab)
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", qa)
        self.assertNotIn("Google", qa)


class GlassCardHonestyTests(unittest.TestCase):
    """Every overlay card is the same glass. A filled MARK still opens."""

    CARDS = (
        "HoldCard.swift",
        "PartyHoldCard.swift",
        "AddressHoldCard.swift",
        "PlaceMarkCard.swift",
        "EmblemPickCard.swift",
        "CamHoldCard.swift",
        "NearHoldCard.swift",
    )

    def test_overlay_cards_share_hold_glass(self):
        hold = read("Blackout", "HoldCard.swift")
        shell = hold.split("struct HoldGlassShell")[1].split("struct HoldCardView")[0]
        self.assertIn("holdCardScrimTopOpacity", shell)
        self.assertIn("holdCardScrimOpacity", shell)
        self.assertIn("holdCardDismissDragPoints", shell)
        self.assertIn("holdCardCornerPoints", shell)
        self.assertIn('accessibilityLabel("Close card")', shell)
        self.assertIn(".accessibilityAddTraits(.isButton)", shell)
        self.assertIn("Theme.accent", shell)
        self.assertIn("frame(height: 2)", shell)
        self.assertIn("Theme.glass()", shell)
        self.assertIn("Theme.Motion.heavy", shell)
        self.assertNotIn(".spring(", shell)
        self.assertNotIn("private static let", shell)
        self.assertIn("smallestUsableCard", shell)
        self.assertNotIn("Self.smallestUsableCard", shell)
        for name in self.CARDS:
            src = read("Blackout", name)
            if name == "HoldCard.swift":
                self.assertIn("struct HoldGlassShell", src, name)
                self.assertIn("HoldGlassShell(", src, name)
            else:
                self.assertIn("HoldGlassShell(", src, name)
            self.assertNotIn(".spring(", src, name)
            self.assertNotIn("best in class", src.lower(), name)
            self.assertNotIn("tel://", src.lower(), name)
        turns = read("Blackout", "SpeakTurnCard.swift")
        self.assertIn('Button("CLOSE")', turns)
        self.assertNotIn("ignoresSafeArea()", turns)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("same hold glass", qa)
        self.assertNotIn("best in class", qa.lower())

    def test_marked_address_mark_opens_the_planted_pin(self):
        app = read("Blackout", "AppRuntime.swift")
        mark = app.split("func markHeldAddress(")[1].split("func addressCourse(")[0]
        self.assertNotIn("!address.marked", mark)
        self.assertIn("openHeldMark()", mark)
        open_mark = app.split("func openHeldMark(")[1].split("func ", 1)[0]
        self.assertIn("holdPlaceMark", open_mark)
        self.assertIn("MarkDrop.sameCoord", open_mark)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("already marked MARK opens the planted pin", qa)

    def test_ground_hold_mark_opens_the_planted_pin(self):
        hold = read("Blackout", "HoldCard.swift")
        card = hold.split("struct HoldCardView")[1]
        self.assertIn("held.marked", card)
        self.assertIn('Button("MARK")', card)
        self.assertIn("onMark", card)
        tab = read("Blackout", "MapTab.swift")
        ground = tab.split("HoldCardView(")[1].split(".padding(hudReserve)")[0]
        self.assertIn("onMark:", ground)
        self.assertIn("openHeldMark()", ground)


class FacetedMetalHUDTests(unittest.TestCase):
    """Void, faceted silver metal, HUD red lamp. No iOS blur mush."""

    HUD_FILES = (
        "Theme.swift",
        "RootChrome.swift",
        "ARMINGView.swift",
        "MapTab.swift",
        "CommsTab.swift",
        "FieldTab.swift",
        "ExpeditionTab.swift",
        "HoldCard.swift",
        "PartyHoldCard.swift",
        "AddressHoldCard.swift",
        "EmblemPickCard.swift",
        "CamHoldCard.swift",
        "NearHoldCard.swift",
        "SpeakTurnCard.swift",
        "SOSHold.swift",
        "InstrumentsView.swift",
        "HUDKeyboard.swift",
        "PlaceMarkCard.swift",
        "IncomingLinePlate.swift",
    )

    def test_facet_tokens_are_highlight_and_shade_not_flat_grey(self):
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        silver = _rgba(tokens, "metal")
        high = _rgba(tokens, "metalHighlight")
        shade = _rgba(tokens, "metalShade")
        self.assertGreater(high[0], silver[0])
        self.assertGreater(high[1], silver[1])
        self.assertGreater(high[2], silver[2])
        self.assertLess(high[0], 1.0)
        self.assertLess(shade[0], silver[0])
        self.assertGreater(shade[0], 0.05)
        self.assertGreater(silver[0], shade[0])
        self.assertIn("hudPlateCornerPoints", tokens)
        self.assertIn("static let metalHighlight", tokens)
        self.assertIn("static let metalShade", tokens)

    def test_glass_is_a_metal_plate_not_ios_blur(self):
        theme = read("Blackout", "Theme.swift")
        glass = theme.split("static func glass(")[1].split("struct HUDMark")[0]
        self.assertNotIn("ultraThinMaterial", glass)
        self.assertIn("LinearGradient", glass)
        self.assertIn("metalHigh", glass)
        self.assertIn("metalLow", glass)
        self.assertIn("static var metalHigh", theme)
        self.assertIn("static var metalLow", theme)
        self.assertIn("static var metalStroke", theme)
        self.assertIn("static func plateRect", theme)
        self.assertIn("hudPlateCornerPoints", theme)
        self.assertIn("struct HUDRing", theme)
        ring = theme.split("struct HUDRing")[1].split("struct HUDMark")[0]
        self.assertIn("Circle()", ring)
        self.assertIn("strokeBorder", ring)
        self.assertIn("metalStroke", ring)
        self.assertNotIn("Circle().fill", ring.replace(" ", ""))
        self.assertNotIn(".spring(", theme)
        self.assertNotIn("Color.orange", theme)
        self.assertNotIn("Color.green", theme)
        self.assertNotIn("best in class", theme.lower())

    def test_mark_boot_and_tabs_carry_the_metal_ring(self):
        theme = read("Blackout", "Theme.swift")
        mark = theme.split("struct HUDMark")[1].split("struct HUDReticle")[0]
        self.assertIn("HUDRing(", mark)
        self.assertIn('Image("Logo")', mark)
        arming = read("Blackout", "ARMINGView.swift")
        self.assertIn('Image("BootField")', arming)
        self.assertNotIn(".spring(", arming)
        self.assertNotIn("HUDRing(", arming)
        root = read("Blackout", "RootChrome.swift")
        self.assertIn("metalHigh", root)
        self.assertIn("metalStroke", root)
        self.assertNotIn(".spring(", root)

    def test_hud_controls_are_faceted_metal_not_flat_raised(self):
        theme = read("Blackout", "Theme.swift")
        dock = theme.split("struct HUDDockStyle")[1].split("struct HUDOverlayChipStyle")[0]
        self.assertIn("var filled: Bool", dock)
        self.assertIn("Theme.glass", dock)
        self.assertIn("metalStroke", dock)
        self.assertNotIn("Theme.raised", dock)
        overlay = theme.split("struct HUDOverlayChipStyle")[1].split("struct MapFieldDestChipStyle")[0]
        self.assertIn("Theme.glass", overlay)
        self.assertIn("metalStroke", overlay)
        self.assertIn("Theme.accent", overlay)
        self.assertIn("if filled {", overlay)
        self.assertNotIn("filled ? Theme.accent : Theme.metalStroke", overlay)
        self.assertNotIn("ultraThinMaterial", overlay)
        action = theme.split("struct HUDActionStyle")[1].split("struct HUDWrapRail")[0]
        self.assertIn("Theme.glass", action)
        self.assertIn("metalStroke", action)
        page = theme.split("struct HUDPage")[1].split("struct HUDGlassCard")[0]
        self.assertIn("HUDRing(", page)
        self.assertIn("Theme.glass", page)
        card = theme.split("struct HUDGlassCard")[1].split("struct HUDActionStyle")[0]
        self.assertIn("Theme.glass", card)
        self.assertIn("metalStroke", card)
        dest = theme.split("struct MapFieldDestChipStyle")[1].split("enum HUDStatusTone")[0]
        self.assertNotIn("Theme.raised", dest)
        self.assertNotIn("ultraThinMaterial", dest)

    def test_every_hud_surface_drops_ios_blur_and_magic_ten_corners(self):
        for name in self.HUD_FILES:
            text = read("Blackout", name)
            self.assertNotIn("ultraThinMaterial", text, name)
            self.assertNotIn("cornerRadius: 10", text, name)
            self.assertNotIn("Color.orange", text, name)
            self.assertNotIn("best in class", text.lower(), name)
            self.assertNotIn(".spring(", text, name)
        hold = read("Blackout", "HoldCard.swift")
        self.assertIn("Theme.glass", hold)
        self.assertIn("struct HoldGlassShell", hold)
        party = read("Blackout", "PartyHoldCard.swift")
        self.assertIn("HoldGlassShell(", party)
        address = read("Blackout", "AddressHoldCard.swift")
        self.assertIn("HoldGlassShell(", address)
        cam = read("Blackout", "CamHoldCard.swift")
        self.assertIn("HoldGlassShell(", cam)
        near = read("Blackout", "NearHoldCard.swift")
        self.assertIn("HoldGlassShell(", near)
        self.assertIn("WALK", near)
        self.assertNotIn("tel://", near)
        pick = read("Blackout", "EmblemPickCard.swift")
        self.assertIn("HoldGlassShell(", pick)
        turns = read("Blackout", "SpeakTurnCard.swift")
        self.assertIn("Theme.glass", turns)
        self.assertNotIn("HoldGlassShell(", turns)
        inst = read("Blackout", "InstrumentsView.swift")
        self.assertIn("Theme.glass", inst)
        self.assertIn("Theme.plateRect", inst)
        comms = read("Blackout", "CommsTab.swift")
        self.assertIn("Theme.glass", comms)
        exped = read("Blackout", "ExpeditionTab.swift")
        self.assertIn("Theme.plateRect", exped)
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("Theme.plateRect", tab)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("faceted metal", qa.lower())
        self.assertIn("no ios blur", qa.lower())
        self.assertNotIn("best in class", qa.lower())


class HUDKeyboardTests(unittest.TestCase):
    """The vessel types on its own glass. The iPhone keyboard stays off."""

    FIELDS = (
        "MapTab.swift",
        "FieldTab.swift",
        "ExpeditionTab.swift",
        "CommsTab.swift",
        "PartyHoldCard.swift",
        "PlaceMarkCard.swift",
    )

    def test_every_field_is_hud_glass_not_uitextfield(self):
        keys = ROOT / "Blackout" / "HUDKeyboard.swift"
        self.assertTrue(keys.is_file(), "HUDKeyboard.swift missing")
        board = keys.read_text()
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "HUDKeyboard.swift")
        root = read("Blackout", "RootChrome.swift")
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn("struct HUDKeyboardState", tokens)
        self.assertIn("enum Key", tokens)
        self.assertIn("case glyph", tokens)
        self.assertIn("case space", tokens)
        self.assertIn("case back", tokens)
        self.assertIn("case shift", tokens)
        self.assertIn("case letters", tokens)
        self.assertIn("case digits", tokens)
        self.assertIn("case done", tokens)
        self.assertIn("mutating func tap(", tokens)
        self.assertIn("keyHeight: Double = 44", tokens)
        self.assertIn('["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]', tokens)
        self.assertIn('["1", "2", "3"]', tokens)
        self.assertIn('["-", "0", "."]', tokens)
        self.assertIn('","', tokens)
        self.assertIn("struct HUDField", board)
        self.assertIn("var digits: Bool", board)
        self.assertIn("face: digits", board)
        self.assertIn("struct HUDKeyboard", board)
        self.assertIn("final class HUDKeyboardGate", board)
        self.assertIn("Button(\"SPACE\")", board)
        self.assertIn("Button(\"BACK\")", board)
        self.assertIn("Button(\"123\")", board)
        self.assertIn("Button(\"ABC\")", board)
        self.assertIn("Button(\"SHIFT\")", board)
        self.assertIn("keys.submitTitle", board)
        self.assertIn("Theme.accent", board)
        self.assertIn("Theme.glass", board)
        self.assertIn("Theme.Motion.heavy", board)
        self.assertIn("Theme.metalStroke", board)
        self.assertNotRegex(
            board,
            r"\? Theme\.accent : Theme\.metalStroke",
            "Xcode 26 archive rejects Color vs LinearGradient in one ternary; stroke live with accent, idle with metal",
        )
        self.assertNotRegex(
            board,
            r"\? Theme\.metalStroke : Theme\.accent",
            "Xcode 26 archive rejects Color vs LinearGradient in one ternary",
        )
        self.assertNotIn(".spring(", board)
        self.assertNotIn("TextField(", board)
        self.assertNotIn("UIKeyboardType", board)
        self.assertNotIn("inputAccessoryView", board)
        self.assertNotIn("best in class", board.lower())
        self.assertNotIn("Color.orange", board)
        self.assertNotIn("Color.green", board)
        self.assertIn("HUDKeyboard(", root)
        self.assertIn("hudKeys", app)
        self.assertIn("environment(runtime.hudKeys)", root)
        for name in self.FIELDS:
            body = read("Blackout", name)
            self.assertNotIn("TextField(", body, name)
            self.assertNotIn("textInputAutocapitalization", body, name)
            self.assertNotIn(".submitLabel(", body, name)
            self.assertNotIn(".keyboardType(", body, name)
            self.assertIn("HUDField(", body, name)
            self.assertNotIn("best in class", body.lower(), name)
            self.assertNotIn(".spring(", body, name)
        map_tab = read("Blackout", "MapTab.swift")
        self.assertIn('HUDField("SEARCH"', map_tab)
        field = read("Blackout", "FieldTab.swift")
        self.assertIn('HUDField("SEARCH"', field)
        self.assertIn('submit: "SEARCH"', field)
        exped = read("Blackout", "ExpeditionTab.swift")
        self.assertIn('HUDField("NAME"', exped)
        self.assertIn('HUDField("TIME"', exped)
        self.assertIn("digits: true", exped)
        self.assertIn('HUDField("ITEM"', exped)
        self.assertIn('HUDField("TODAY"', exped)
        comms = read("Blackout", "CommsTab.swift")
        self.assertIn('HUDField("NOTE"', comms)
        self.assertIn('submit: "SEND"', comms)
        self.assertIn('HUDField("PARTY CODE"', comms)
        party = read("Blackout", "PartyHoldCard.swift")
        self.assertIn('HUDField("NAME"', party)
        self.assertIn("locked: true", exped)
        self.assertIn("locked: true", party)
        self.assertIn("locked: true", comms)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("HUD keyboard", qa)
        self.assertIn("SPACE", qa)
        self.assertIn("BACK", qa)
        self.assertIn("Tap SEARCH, NOTE, NAME, TIME", qa)
        self.assertIn("no iphone keyboard", qa.lower())
        self.assertNotIn("best in class", qa.lower())

    def test_engine_types_coordinates_and_respects_lock(self):
        state = {"text": "", "shift": False, "locked": False, "face": "letters"}
        for ch in "31":
            hud_tap(state, ("glyph", ch))
        hud_tap(state, ("glyph", "."))
        hud_tap(state, ("glyph", "7"))
        hud_tap(state, ("glyph", ","))
        hud_tap(state, "space")
        hud_tap(state, ("glyph", "-"))
        hud_tap(state, ("glyph", "1"))
        self.assertEqual(state["text"], "31.7, -1")
        hud_tap(state, "back")
        self.assertEqual(state["text"], "31.7, -")
        locked = {"text": "", "shift": True, "locked": True, "face": "letters"}
        hud_tap(locked, ("glyph", "a"))
        hud_tap(locked, ("glyph", "b"))
        self.assertEqual(locked["text"], "AB")
        self.assertTrue(locked["shift"])
        mixed = {"text": "", "shift": True, "locked": False, "face": "letters"}
        hud_tap(mixed, ("glyph", "m"))
        hud_tap(mixed, ("glyph", "o"))
        self.assertEqual(mixed["text"], "Mo")
        self.assertFalse(mixed["shift"])
        hud_tap(mixed, "space")
        hud_tap(mixed, ("glyph", "a"))
        self.assertEqual(mixed["text"], "Mo A")
        self.assertFalse(mixed["shift"])


def hud_tap(state: dict, key) -> None:
    """Mirror of HUDKeyboardState.tap. Keep in lockstep with Tokens."""
    if key == "space":
        state["text"] += " "
        if not state["locked"]:
            state["shift"] = True
        return
    if key == "back":
        state["text"] = state["text"][:-1]
        return
    if key == "shift":
        state["shift"] = not state["shift"]
        return
    if key == "letters":
        state["face"] = "letters"
        return
    if key == "digits":
        state["face"] = "digits"
        return
    if key == "done":
        return
    kind, glyph = key
    if kind != "glyph":
        raise AssertionError(key)
    letter = len(glyph) == 1 and glyph.isalpha()
    if letter:
        if state["locked"] or state["shift"]:
            state["text"] += glyph.upper()
        else:
            state["text"] += glyph.lower()
        if not state["locked"]:
            state["shift"] = False
        return
    state["text"] += glyph


class MapHoldScrollAndPlateRailTests(unittest.TestCase):
    """Hold cards scroll. INSTRUMENTS / COMMS / EXPEDITION are one plate, not a dump."""

    def test_hold_dismiss_does_not_steal_the_card_scroll(self):
        hold = read("Blackout", "HoldCard.swift")
        shell = hold.split("struct HoldGlassShell")[1].split("struct HoldCardView")[0]
        stack = shell.split("ZStack(alignment: .bottom)")[1].split("private var scrim")[0]
        self.assertNotIn(".gesture(", stack)
        self.assertIn("private var dismissDrag", shell)
        grabber = shell.split("private var grabber")[1]
        self.assertIn("dismissDrag", grabber)
        self.assertIn("mapChipHitPoints", grabber)
        scrim = shell.split("private var scrim")[1].split("private var dismissDrag")[0]
        self.assertIn("dismissDrag", scrim)
        ground = hold.split("struct HoldCardView")[1]
        self.assertIn("ScrollView", ground)
        self.assertIn("scrollBounceBehavior", ground)
        self.assertLess(ground.find("actions"), ground.find("ScrollView"))
        address = read("Blackout", "AddressHoldCard.swift")
        self.assertIn("ScrollView", address)
        self.assertLess(address.find("actions"), address.find("ScrollView"))
        cam = read("Blackout", "CamHoldCard.swift")
        self.assertIn("ScrollView", cam)
        self.assertLess(cam.find("actions"), cam.find("ScrollView"))
        near = read("Blackout", "NearHoldCard.swift")
        self.assertIn("ScrollView", near)
        self.assertLess(near.find("actions"), near.find("ScrollView"))
        party = read("Blackout", "PartyHoldCard.swift")
        self.assertIn("scrollBounceBehavior", party)
        mark = read("Blackout", "PlaceMarkCard.swift")
        self.assertIn("scrollBounceBehavior", mark)
        self.assertLess(mark.find('Button("DROP")'), mark.find("ScrollView"))

    def test_instruments_is_a_plate_rail_not_one_long_dump(self):
        inst = read("Blackout", "InstrumentsView.swift")
        self.assertIn("enum InstrumentPlate", inst)
        self.assertIn("HUDWrapRail", inst)
        self.assertIn("@State private var plate", inst)
        for title in ("PACKS", "HUD", "MAP", "SUN", "BODY", "VOICE", "POWER"):
            self.assertIn(f'case .{title.lower()}: return "{title}"', inst, title)
        self.assertIn("BlackoutTokens.MapOverlay.godsEyeTitle", inst)
        hud = inst.split('sectionLabel("HUD")')[1].split('sectionLabel("MAP")')[0]
        self.assertIn('Button("NIGHT")', hud)
        self.assertIn('Button("SUN")', hud)
        self.assertNotIn("godsEyeTitle", hud)
        eye = inst.split("private var eyeDeskPlate")[1].split("private func eyeDeskCaption")[0]
        self.assertIn("EyeDesk.noFix", eye)
        self.assertIn("fieldYou == nil", eye)
        self.assertIn("saveEyeScene", eye)
        root = read("Blackout", "RootChrome.swift")
        overlay = root.split("if runtime.armed, runtime.showInstruments")[1].split(".overlay {")[0]
        self.assertNotIn(".ignoresSafeArea()", overlay)
        comms = read("Blackout", "CommsTab.swift")
        self.assertIn("enum CommsPlate", comms)
        self.assertIn("pendingNoteFocus { plate = .note }", comms)
        exped = read("Blackout", "ExpeditionTab.swift")
        self.assertIn("enum ExpeditionPlate", exped)
        tab = read("Blackout", "MapTab.swift")
        search = tab.split("private var searchField")[1].split("private var overlayRail")[0]
        self.assertIn("markList", search)
        hud_fn = tab.split("private func hud")[1].split("private var searchField")[0]
        self.assertNotIn("markList", hud_fn)
        self.assertIn("HUDWrapRail", tab.split("private struct EyeTapStrip")[1])
        qa = read("docs", "SOLO_QA.md")
        inst_line = next(
            line
            for line in qa.splitlines()
            if "COMPASS CAL" in line and "GNSS PUCK" in line
        )
        self.assertIn("plate rail", inst_line.lower())
        hold_line = next(
            line for line in qa.splitlines() if "same hold glass" in line
        )
        self.assertIn("scroll", hold_line.lower())
        self.assertIn("grabber", hold_line.lower())
        pages = next(
            line
            for line in qa.splitlines()
            if "glass HUD pages over the still-mounted map" in line
        )
        self.assertIn("plate", pages.lower())
        self.assertNotIn("best in class", inst.lower())
        self.assertNotIn(".spring(", inst)


class MeshNearHUDTests(unittest.TestCase):
    """Heard radios are green/black NEAR dots. Discovery is not a peer."""

    def test_near_card_and_chrome_are_on_the_glass(self):
        card = read("Blackout", "NearHoldCard.swift")
        tab = read("Blackout", "MapTab.swift")
        comms = read("Blackout", "CommsTab.swift")
        app = read("Blackout", "AppRuntime.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("struct NearHoldCard", card)
        self.assertIn("NEAR", card)
        self.assertIn("DEVICE", card)
        self.assertIn("WALK", card)
        self.assertIn("NAME", card)
        self.assertIn("RSSI", card)
        self.assertIn("REACH", card)
        self.assertIn("RADIO", card)
        self.assertIn("UNNAMED", card)
        self.assertNotIn("tel://", card)
        self.assertNotIn("Whisper", card)
        art = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        presence_art = art.split("static func presence(count: Int)")[1].split(
            "static func pin("
        )[0]
        self.assertIn("let disc: CGFloat = 10", presence_art)
        self.assertNotIn("let size: CGFloat = 22", presence_art)
        self.assertIn("NearHoldCard", tab)
        self.assertIn("heldNear", tab)
        self.assertIn("chromeNear", comms)
        self.assertIn("LISTEN", comms)
        self.assertIn("QUIET", comms)
        self.assertIn('Button("SCAN")', comms)
        self.assertIn("scanMesh", app)
        self.assertIn("SCAN — NO FIX", app)
        self.assertIn("presence", app.split("func eyeCanvasPips")[1].split("func eyeTrails")[0])
        self.assertIn("NEAR ·", qa)
        self.assertIn("LOUDER", qa)
        self.assertIn("green", qa.lower())
        self.assertIn("house", qa.lower())
        self.assertIn("SCAN or JOIN LOCAL NET", qa)
        self.assertIn("SCAN — NO FIX", qa)
        self.assertIn("WALK — NO PLACE", qa)


if __name__ == "__main__":
    unittest.main()

