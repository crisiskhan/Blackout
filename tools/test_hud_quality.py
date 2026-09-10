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
        self.assertIn("FIELD · WATER", hold)
        self.assertNotIn("WaterSure.disclaimer", hold)
        self.assertIn("zoom", tab.lower())
        self.assertIn("Dip clear of the churned edge", water)

    def test_solo_qa_scores_the_class_not_a_generic_treat(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("STOCK TANK", qa)
        self.assertIn("TINAJA", qa)
        self.assertIn("nearest water", qa.lower())
        self.assertIn("FIELD · WATER", qa)


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


if __name__ == "__main__":
    unittest.main()
