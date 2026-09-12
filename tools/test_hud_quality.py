#!/usr/bin/env python3
"""Quality bar — Linux stand-in for the HUD on every tab, not just MAP.

Crisis: if there is a better method, aesthetic, or way to do a feature, do that.
INST existed because INSTRUMENTS truncated. Bearing printed with nowhere to walk.
FIELD tore the hold card down in-stack (ASC 72). Leaving MAP destroyed MapLibre.
COMMS dumped Whisper meters. Those are not the best way — these contracts are.
"""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


def active_bearing(
    heading: float | None,
    has_destination: bool,
    lock_on: bool,
    has_route: bool,
) -> float | None:
    """Mirror of MapFieldChrome.activeBearing."""
    if not (has_destination or lock_on or has_route):
        return None
    return heading


class QuietBearingTests(unittest.TestCase):
    def test_heading_alone_is_not_a_mission(self):
        self.assertIsNone(active_bearing(12, False, False, False))
        self.assertEqual(active_bearing(45, True, False, False), 45)
        self.assertEqual(active_bearing(10, False, True, False), 10)
        self.assertEqual(active_bearing(8, False, False, True), 8)
        self.assertIsNone(active_bearing(None, True, False, False))

    def test_map_filters_bearing_through_active_bearing(self):
        route = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift")
        tab = read("Blackout", "MapTab.swift")
        self.assertIn("func activeBearing(", route)
        self.assertIn("MapFieldChrome.activeBearing(", tab)
        self.assertNotIn("bearingDeg: runtime.headingDeg", tab)


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
        self.assertIn("isUserInteractionEnabled = interactive", read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        ))
        self.assertIn("HUDPage", read("Blackout", "CommsTab.swift"))
        self.assertIn("HUDPage", read("Blackout", "FieldTab.swift"))
        self.assertIn("HUDPage", read("Blackout", "ExpeditionTab.swift"))


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
        self.assertNotIn('Button("INST")', tab)
        self.assertNotIn('"LOCKED" : "LOCK"', tab)
        self.assertIn("HUDWrapRail", tab)
        self.assertIn("struct HUDWrapRail", theme)
        self.assertIn('instrumentsTitle = "INSTRUMENTS"', tokens)
        self.assertIn('lockOnTitle = "LOCK-ON"', tokens)
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

    def test_device_script_scores_bearing_not_dest_coords(self):
        device = read("docs", "DEVICE.md")
        self.assertNotIn("DEST … · BEARING", device)
        self.assertNotIn("DEST ... · BEARING", device)
        self.assertIn("BEARING", device)


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
        self.assertIn("No BLACKOUT wordmark", qa)



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
    """Home screen and boot share the square compass. No wordmark poster."""

    def test_app_icon_is_opaque_1024(self):
        icon = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
        width, height, color = png_ihdr(icon)
        self.assertEqual((width, height), (1024, 1024))
        self.assertEqual(color, 2, "App Store icon must be RGB, no alpha")

    def test_boot_logo_is_the_square_mark(self):
        logo = ROOT / "Blackout" / "Assets.xcassets" / "Logo.imageset" / "Logo.jpg"
        width, height = jpeg_size(logo)
        self.assertEqual(width, height)
        self.assertGreaterEqual(width, 1024)
        arming = read("Blackout", "ARMINGView.swift")
        self.assertIn("Image(\"Logo\")", arming)
        self.assertNotIn("1712.0 / 1152.0", arming)
        self.assertNotIn('Text("BLACKOUT")', arming)
        self.assertIn(
            "height: BlackoutTokens.Chrome.bootLogoPoints",
            arming,
        )


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


YELLOW_AT = 0.45
RED_AT = 0.8
RAIL_STEPS = (0.0, 0.2, 0.45, 0.8, 1.0)


def snap_rail(raw: float) -> float:
    """Mirror of PartyVitals.snap — midpoint and above belongs to the worse tick."""
    clamped = min(1.0, max(0.0, raw))
    for i in range(len(RAIL_STEPS) - 1):
        mid = (RAIL_STEPS[i] + RAIL_STEPS[i + 1]) / 2
        if clamped < mid:
            return RAIL_STEPS[i]
    return RAIL_STEPS[-1]


def band_from_worst(worst: float, flags: tuple[str, ...] = ()) -> str:
    """Mirror of PartyVitals.band."""
    if "RED" in flags or worst >= RED_AT:
        return "red"
    if worst >= YELLOW_AT:
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
        self.assertEqual(snap_rail(0.625), 0.8)
        self.assertEqual(snap_rail(0.89), 0.8)
        self.assertEqual(snap_rail(0.9), 1.0)
        self.assertEqual(snap_rail(1.2), 1.0)
        self.assertEqual(band_from_worst(0.2), "green")
        self.assertEqual(band_from_worst(0.45), "yellow")
        self.assertEqual(band_from_worst(0.8), "red")
        self.assertEqual(band_from_worst(0.2, ("RED",)), "red")

    def test_condition_rails_not_system_sliders(self):
        exped = read("Blackout", "ExpeditionTab.swift")
        vitals = read("Packages", "Vitals", "Sources", "Vitals", "Vitals.swift")
        for label in ("HUNGER", "THIRST", "PAIN", "WATER", "FATIGUE", "EXPOSURE"):
            self.assertIn(f'slider("{label}"', exped, label)
        self.assertNotIn("Slider(", exped)
        self.assertIn("PartyVitals.snap", exped)
        self.assertIn("struct HUDVitalsRail", exped)
        self.assertIn("static let yellowAt", vitals)
        self.assertIn("static let redAt", vitals)
        self.assertIn("static let railSteps", vitals)
        self.assertIn("0.45", vitals)
        self.assertIn("0.8", vitals)
        self.assertIn("[0,0.2,0.45,0.8,1.0]", vitals.replace(" ", ""))

    def test_page_sections_and_red_plate(self):
        exped = read("Blackout", "ExpeditionTab.swift")
        theme = read("Blackout", "Theme.swift")
        comms = read("Blackout", "CommsTab.swift")
        self.assertIn("enum HUDStatusTone", theme)
        self.assertIn("case crisis", theme)
        self.assertIn("statusTone:", exped)
        self.assertIn("statusTone:", comms)
        self.assertIn("redPlate", exped)
        self.assertNotIn(".title.weight(.bold)", exped)
        self.assertIn("HUDDockStyle()", exped)
        self.assertIn('Button("1 MIN TIMER SET")', exped)
        self.assertIn('Button("2H WATER TIMER SET")', exped)
        self.assertIn('Button("APPLY RED BAND")', exped)
        self.assertIn('Button("JOIN NAV")', exped)
        self.assertIn('Button("EXPORT PAPER")', exped)
        for section in ("CONDITION", "RED", "ROSTER", "TIMERS", "PAPER"):
            self.assertIn(f'sectionLabel("{section}")', exped, section)
        self.assertIn('L10n.t("overdue"', exped)
        self.assertNotIn("not SOS", exped)
        self.assertNotIn("not sos", exped.lower())

    def test_solo_qa_scores_rails_and_hud_red(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("condition rails", qa.lower())
        self.assertIn("HUD RED plate", qa)
        self.assertNotIn("Exposure sliders change CONDITION", qa)


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
        self.assertNotIn("ForEach(listCards)", field)
        self.assertIn("openAnswer()", field)
        self.assertIn("onSubmit(openAnswer)", field)
        self.assertIn("FieldCorpus.ask(", field)
        self.assertIn("FieldCorpus.asking(", field)
        self.assertIn('TextField("SEARCH"', field)
        self.assertIn("NO MATCH", field)
        self.assertNotIn("mapSearchHitCap", field)
        self.assertIn('Button("SAY")', field)
        self.assertIn("SAY FAILED", field)
        self.assertIn('sectionLabel("SITUATION")', field)
        self.assertIn('sectionLabel("DO")', field)
        self.assertIn('sectionLabel("GET-TO-CARE")', field)
        self.assertNotIn('sectionLabel("CARE")', field)
        self.assertIn("s.step.image", field)
        self.assertIn("Field/images", field)
        self.assertIn("openRoute([first.id])", field)

    def test_solo_qa_scores_stop_if_and_step_speak(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("STOP-IF", qa)
        self.assertIn("open step", qa.lower())
        self.assertIn("VISION captures one still", qa)
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

    def test_solo_qa_scores_form_up_and_lost_kid(self):
        qa = read("docs", "SOLO_QA.md")
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
        self.assertIn('Button("TORCH 3×")', inst)
        self.assertIn("tapTorch()", inst)
        self.assertIn("func tapTorch()", runtime)
        self.assertIn("setTorchModeOn", runtime)
        self.assertIn("func clock(", almanac)
        self.assertNotIn("Screen buffer OFF default", inst)

    def test_solo_qa_scores_sun_and_torch(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("RISE", qa)
        self.assertIn("TORCH 3×", qa)


class MapMarksGlassTests(unittest.TestCase):
    """Persisted marks are a DEST list on the canvas, 44pt, no scroll."""

    def test_marks_and_hits_are_44pt(self):
        tab = read("Blackout", "MapTab.swift")
        sos = read("Blackout", "SOSHold.swift")
        self.assertIn("runtime.marks", tab)
        self.assertIn("pickDestination(lat: m.lat, lon: m.lon)", tab)
        self.assertIn("mapChipHitPoints", tab)
        self.assertNotIn("minHeight: 36", tab)
        self.assertIn('Button("FIT PACK")', tab)
        self.assertIn("HUDOverlayChipStyle()", tab)
        self.assertIn("mapChipHitPoints", sos)


class ExpeditionKitPaperTests(unittest.TestCase):
    def test_kit_trip_and_paper_are_on_glass(self):
        exped = read("Blackout", "ExpeditionTab.swift")
        self.assertIn('sectionLabel("KIT")', exped)
        self.assertIn('sectionLabel("TRIP")', exped)
        self.assertIn("runtime.kit", exped)
        self.assertIn("runtime.trip.brief", exped)
        self.assertIn('Button("EXPORT PAPER")', exped)
        self.assertIn("paperText", exped)
        self.assertIn("PaperGen.export", exped)


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
        self.assertIn("Vision/labels.tx.json", read("Blackout.xcodeproj", "project.pbxproj"))

    def test_matcher_needles_are_in_the_package(self):
        vis = read("Packages", "VisionCoreML", "Sources", "VisionCoreML", "VisionCoreML.swift").lower()
        for needle in (
            "mushroom",
            "cactus",
            "rattlesnake",
            "coyote",
            "yucca",
            "unknown",
        ):
            self.assertIn(needle, vis, needle)

    def test_solo_qa_scores_a_still_not_a_percent(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("VISION captures one still", qa)
        self.assertIn("UNKNOWN", qa)
        self.assertIn("LEAVE IT", qa)
        self.assertIn("NO VISION MODEL", qa)
        self.assertIn("No percent", qa)


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
        for stamp in ("LEFT HAND", "NIGHT RED", "TORCH 3×", "COMPASS CAL", "TRUE NORTH", "USB-C PTT", "GNSS PUCK"):
            self.assertIn(stamp, inst, stamp)
        self.assertNotIn("blackout-hotspare:", inst)
        for label in ("HUNGER", "THIRST", "PAIN", "WATER", "FATIGUE", "EXPOSURE"):
            self.assertIn(f'slider("{label}"', exped, label)
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
        self.assertIn("TORCH 3×", qa)
        self.assertIn("HUNGER", qa)


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
        self.assertIn("runtime.mesh.pips", tab)
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
        self.assertIn("from != runtime.mesh.localID", tab)
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
        self.assertIn("no bounce", qa.lower())
        self.assertIn("NET · NONE", qa)
        self.assertIn("silver route", qa.lower())
        self.assertNotIn("cyan route", qa.lower())
        self.assertNotIn("does not replace 911", qa)
        self.assertNotIn("I UNDERSTAND", qa)


if __name__ == "__main__":
    unittest.main()

