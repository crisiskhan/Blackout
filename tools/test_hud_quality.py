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
        self.assertIn("%.5f, %.5f", route)
        self.assertNotIn("DEST %.4f", route)
        self.assertNotIn("packs?.active?.center", chrome)
        self.assertIn("MapFieldDestRail", tab)
        self.assertIn("MapFieldDestMode.coordinates", tab)
        self.assertNotIn("Theme.accent", chrome)
        self.assertIn("Theme.fix", chrome)
        self.assertIn("Theme.Motion.beat", chrome)
        self.assertIn("@State private var beat", chrome)
        self.assertIn("MapFieldChrome.destValue", chrome)
        self.assertIn("Text(field)", chrome)
        rail = chrome.split("struct MapFieldDestRail")[1]
        chip = rail.split("func chip(")[1]
        self.assertNotIn("destValue", chip)
        self.assertIn("chipMode.title", chip)
        self.assertNotIn("MapFieldDestMode.bearing", rail)
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
        device = read("docs", "DEVICE.md")
        self.assertIn("no grey plate", device.lower())
        agents = read("AGENTS.md")
        self.assertIn("no grey plate", agents.lower())
        app = read("Blackout", "AppRuntime.swift")
        you = app.split("var gnssYou")[1].split("private func youCoordinate")[0]
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
        self.assertIn("No BLACKOUT wordmark", qa)
        self.assertIn("no black plate", qa.lower())


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
    """Home screen and boot share the square compass. No wordmark poster."""

    def test_app_icon_is_opaque_1024(self):
        icon = ROOT / "Blackout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
        width, height, color = png_ihdr(icon)
        self.assertEqual((width, height), (1024, 1024))
        self.assertEqual(color, 2, "App Store icon must be RGB, no alpha")

    def _assert_emblem_without_plate(self, path: Path, *, match_store_rgb: bool) -> None:
        """Outer black and outer rays are gone; original metal and well stay opaque."""
        width, height, color = png_ihdr(path)
        self.assertEqual(color, 6, f"{path.name} has alpha")
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
            self.assertEqual(png_px(px, width, x, y)[3], 0, f"{path.name} corner {x},{y}")
        well = png_px(px, width, width // 2 + 200, height // 2)
        self.assertEqual(well[3], 255, f"{path.name} inner well stays with the emblem")
        if match_store_rgb:
            sr, sg, sb, _ = png_px(store_px, width, width // 2 + 200, height // 2)
            self.assertEqual(
                well[:3],
                (sr, sg, sb),
                f"{path.name} inner well matches the storefront mark",
            )
        core = png_px(px, width, width // 2, height // 2)
        self.assertGreaterEqual(core[0], 160, f"{path.name} red sight stays")
        self.assertEqual(core[3], 255, f"{path.name} red sight is fully opaque")
        ring = png_px(px, width, width // 2, int(height * 200 / 1024))
        self.assertEqual(ring[3], 255, f"{path.name} ring is fully opaque")
        metal = (
            (width // 2, int(height * 200 / 1024)),
            (int(width * 792 / 1024), height // 2),
            (width // 2, int(height * 56 / 1024)),
        )
        for x, y in metal:
            r, g, b, a = png_px(px, width, x, y)
            self.assertEqual(a, 255, f"{path.name} metal {x},{y} is fully opaque")
            if match_store_rgb:
                sr, sg, sb, _ = png_px(store_px, width, x, y)
                self.assertEqual(
                    (r, g, b),
                    (sr, sg, sb),
                    f"{path.name} metal RGB {x},{y} matches the storefront mark",
                )
        keep_max = 0
        black_margin = 0
        metal_punched = 0
        metal_rewritten = 0
        outer_rays = 0
        margin = int(48 * width / 1024)
        cx = (width - 1) / 2
        cy = (height - 1) / 2
        ray_r = 465 * width / 1024
        body_r = 400 * width / 1024
        for y in range(height):
            for x in range(width):
                r, g, b, a = png_px(px, width, x, y)
                sr, sg, sb, _ = png_px(store_px, width, x, y)
                rad = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                if a > keep_max:
                    keep_max = a
                if a > 200 and max(r, g, b) < 12:
                    if x < margin or y < margin or x >= width - margin or y >= height - margin:
                        black_margin += 1
                if a == 255 and match_store_rgb and (r, g, b) != (sr, sg, sb):
                    metal_rewritten += 1
                if max(sr, sg, sb) >= 40 and rad < body_r and a == 0:
                    metal_punched += 1
                if a > 0 and rad > ray_r:
                    outer_rays += 1
        self.assertEqual(black_margin, 0, f"{path.name} black plate in the margin")
        self.assertEqual(keep_max, 255, f"{path.name} metal is fully opaque")
        self.assertEqual(metal_punched, 0, f"{path.name} punched metal")
        self.assertEqual(metal_rewritten, 0, f"{path.name} rewrote metal")
        self.assertEqual(outer_rays, 0, f"{path.name} outer rays remain")

    def test_home_screen_dark_and_tinted_drop_the_black_plate(self):
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
        self._assert_emblem_without_plate(dark, match_store_rgb=True)
        self._assert_emblem_without_plate(tinted, match_store_rgb=False)

    def test_boot_logo_is_the_square_mark(self):
        logo_dir = ROOT / "Blackout" / "Assets.xcassets" / "Logo.imageset"
        logo = logo_dir / "Logo.png"
        width, height, color = png_ihdr(logo)
        self.assertEqual(width, height)
        self.assertGreaterEqual(width, 1024)
        self.assertEqual(color, 6, "boot logo has alpha so the black plate is gone")
        self.assertFalse((logo_dir / "Logo.jpg").exists())
        manifest = read("Blackout", "Assets.xcassets", "Logo.imageset", "Contents.json")
        self.assertIn("Logo.png", manifest)
        self.assertNotIn("Logo.jpg", manifest)
        arming = read("Blackout", "ARMINGView.swift")
        self.assertIn("Image(\"Logo\")", arming)
        self.assertNotIn("1712.0 / 1152.0", arming)
        self.assertNotIn('Text("BLACKOUT")', arming)
        self.assertIn(
            "BlackoutTokens.Chrome.bootLogoPoints",
            arming,
        )
        app = read("Blackout", "AppRuntime.swift")
        gnss = app.split("didUpdateLocations")[1].split("didUpdateHeading")[0]
        self.assertIn("CLLocationCoordinate2DIsValid", gnss)
        self._assert_emblem_without_plate(logo, match_store_rgb=True)
        mark = arming.split("private var mark:")[1].split("private var status")[0]
        self.assertGreaterEqual(mark.count("Theme.accent"), 2)
        self.assertGreaterEqual(mark.count(".shadow("), 2)
        self.assertNotIn(".spring(", mark)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("outer rays are gone", qa.lower())
        self.assertIn("red glow", qa.lower())
        self.assertIn("metal on the mark is fully opaque", qa.lower())


class UnlockGlassTests(unittest.TestCase):
    """Fingerprint glass before ACTIVATE. Inverted print asks before a wipe."""

    def test_fingerprint_unlock_sits_before_activate(self):
        root = read("Blackout", "RootChrome.swift")
        unlock = read("Blackout", "UnlockView.swift")
        app = read("Blackout", "AppRuntime.swift")
        pbx = read("Blackout.xcodeproj", "project.pbxproj")
        gen = read("tools", "v3", "generate_project.py")
        qa = read("docs", "SOLO_QA.md")
        self.assertLess(root.find("UnlockView"), root.find("ARMINGView"))
        self.assertIn("runtime.unlocked", root)
        self.assertIn("var unlocked", app)
        self.assertIn("func requestUnlock", app)
        self.assertIn("import LocalAuthentication", app)
        self.assertIn("LAContext", app)
        self.assertIn("deviceOwnerAuthentication", app)
        self.assertIn("UNLOCK FAILED", app)
        self.assertIn("func wipeVessel", app)
        self.assertIn("exit(0)", app)
        self.assertIn("removePersistentDomain", app)
        self.assertIn("struct UnlockView", unlock)
        self.assertIn("UNLOCK", unlock)
        self.assertIn("ARE YOU SURE", unlock)
        self.assertIn('Button("YES")', unlock)
        self.assertIn('Button("NO")', unlock)
        self.assertIn("Theme.fix", unlock)
        self.assertIn("Theme.accent", unlock)
        self.assertIn("RotationGesture", unlock)
        self.assertIn('Button("INVERT")', unlock)
        self.assertIn("inverted", unlock)
        self.assertIn("180", unlock)
        self.assertNotIn("Color.green", unlock)
        self.assertNotIn("Color.orange", unlock)
        self.assertNotIn(".spring(", unlock)
        self.assertNotIn("tel://", unlock.lower())
        self.assertNotIn("best in class", unlock.lower())
        self.assertIn("NSFaceIDUsageDescription", pbx)
        self.assertIn("NSFaceIDUsageDescription", gen)
        self.assertIn("UNLOCK", qa)
        self.assertIn("ARE YOU SURE", qa)
        self.assertIn("INVERT", qa)
        self.assertNotIn("best in class", qa.lower())
        wipe = app.split("func wipeVessel", 1)[1].split("func joinNet", 1)[0]
        self.assertIn("temporaryDirectory", wipe)
        self.assertIn(".libraryDirectory", wipe)


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
ORANGE_AT = 0.65
RED_AT = 0.8
STACK_YELLOW_TO_ORANGE = 2
STACK_YELLOW_TO_RED = 3
STACK_ORANGE_TO_RED = 2
YELLOW_LOAD = 1
ORANGE_LOAD = 2
RED_LOAD = 3
RAIL_STEPS = (0.0, 0.2, 0.45, 0.65, 0.8, 1.0)


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
    if band == "red":
        return RED_LOAD
    if band == "orange":
        return ORANGE_LOAD
    if band == "yellow":
        return YELLOW_LOAD
    return 0


def band_from_rails(rails: tuple[float, ...], flags: tuple[str, ...] = ()) -> str:
    """Mirror of PartyVitals.band(rails:flags:). Load 2 is ORANGE. Load 3 is RED."""
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
        self.assertEqual(load_of(0.45), 1)
        self.assertEqual(load_of(0.65), 2)
        self.assertEqual(band_from_rails((0.2,) * 6), "green")
        self.assertEqual(band_from_rails((0.45, 0.2, 0.2, 0.2, 0.2, 0.2)), "yellow")
        self.assertEqual(band_from_rails((0.45, 0.45, 0.2, 0.2, 0.2, 0.2)), "orange")
        self.assertEqual(band_from_rails((0.45, 0.45, 0.45, 0.2, 0.2, 0.2)), "red")
        self.assertEqual(band_from_rails((0.45,) * 6), "red")
        self.assertEqual(band_from_rails((0.65, 0.2, 0.2, 0.2, 0.2, 0.2)), "orange")
        self.assertEqual(band_from_rails((0.65, 0.65, 0.2, 0.2, 0.2, 0.2)), "red")
        self.assertEqual(band_from_rails((0.65, 0.45, 0.2, 0.2, 0.2, 0.2)), "red")
        self.assertEqual(band_from_rails((0.2, 0.2, 0.2, 0.2, 0.2, 0.8)), "red")
        self.assertEqual(band_from_rails((0.2,) * 6, ("RED",)), "red")

    def test_condition_rails_not_system_sliders(self):
        exped = read("Blackout", "ExpeditionTab.swift")
        vitals = read("Packages", "Vitals", "Sources", "Vitals", "Vitals.swift")
        for label in ("HUNGER", "THIRST", "PAIN", "WATER", "FATIGUE", "EXPOSURE"):
            self.assertIn(f'slider("{label}"', exped, label)
        self.assertNotIn("Slider(", exped)
        self.assertIn("PartyVitals.snap", exped)
        self.assertIn("struct HUDVitalsRail", exped)
        self.assertIn("static let yellowAt", vitals)
        self.assertIn("static let orangeAt", vitals)
        self.assertIn("static let redAt", vitals)
        self.assertIn("static let railSteps", vitals)
        self.assertIn("0.45", vitals)
        self.assertIn("0.65", vitals)
        self.assertIn("0.8", vitals)
        self.assertIn("[0,0.2,0.45,0.65,0.8,1.0]", vitals.replace(" ", ""))
        self.assertIn("stackYellowToOrange", vitals)
        self.assertIn("stackYellowToRed", vitals)
        self.assertIn("stackOrangeToRed", vitals)
        self.assertIn("= 3", vitals)
        self.assertIn("func load(of", vitals)
        self.assertIn("band(rails:", vitals)
        self.assertIn("band(of:", vitals)
        self.assertNotIn("band(worst:", vitals)

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
        self.assertIn("yellow, orange, red", vitalsSrc)
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
        self.assertIn("stacked", qa.lower())
        self.assertIn("CONDITION RED", qa)
        self.assertIn("CONDITION ORANGE", qa)
        self.assertIn("caution ink", qa.lower())
        self.assertIn("heat ink", qa.lower())
        self.assertIn("ORANGE", qa)
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
        pcm = mic.split("private func pcm(")[1].split("private static func wav")[0]
        self.assertIn("channelCount >= 1", pcm)
        self.assertIn("int16ChannelData", pcm)

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
            "PartyHoldCard.swift",
            "EmblemPickCard.swift",
            "AddressHoldCard.swift",
            "CommsTab.swift",
            "FieldTab.swift",
            "ExpeditionTab.swift",
            "InstrumentsView.swift",
            "ARMINGView.swift",
            "UnlockView.swift",
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
        self.assertIn("PersonEmblem.allCases", comms)
        self.assertIn("pickEmblem", comms)
        self.assertIn("youHeading: runtime.headingDeg", tab)
        self.assertIn("youEmblem: runtime.youEmblem.rawValue", tab)
        self.assertIn("PartyBody(", tab)
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
        self.assertIn("headingView", offline)
        self.assertIn("YouPuckAnnotationView", offline)
        self.assertIn("you-puck-core", offline)
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
        self.assertEqual(count, 175)
        self.assertIn("var onPersonHold", offline)
        self.assertIn("onPersonHold:", tab)
        self.assertIn("func personMark(at:", offline)
        self.assertIn("toPointTo:", offline)
        self.assertIn("isUserInteractionEnabled = false", offline.split("final class YouPuckAnnotationView")[1])
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
        for label in ("HUNGER", "THIRST", "PAIN", "WATER", "FATIGUE", "EXPOSURE"):
            self.assertIn(f'HUDVitalsRail(title: "{label}"', card, label)
        self.assertIn("editable: person.isYou", card)
        exped = read("Blackout", "ExpeditionTab.swift")
        self.assertIn("struct HUDVitalsRail", exped)
        self.assertIn("var editable: Bool", exped)
        self.assertIn("ScrollView", card)
        self.assertIn("func setYouStatus(", app)
        self.assertIn("func setYouVitals(", app)
        set_vitals = app.split("func setYouVitals(")[1].split("func ", 1)[0]
        self.assertIn("sendPOSIfPossible()", set_vitals)
        self.assertIn("func setYouName(", app)
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
        self.assertIn("case ok, wait, water, down", mesh)
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
        self.assertIn("holdCardDismissDragPoints", card)

    def test_solo_qa_scores_the_person_card(self):
        qa = read("docs", "SOLO_QA.md")
        person = next(
            line for line in qa.splitlines() if "Hold YOU or a party emblem" in line
        )
        self.assertIn("STATUS", person)
        self.assertIn("`OK` / `WAIT` / `WATER` / `DOWN`", person)
        self.assertIn("CONDITION", person)
        self.assertIn("HUNGER", person)
        self.assertIn("THIRST", person)
        self.assertIn("others read", person)
        self.assertIn("CALL starts a 1:1 party call", person)
        self.assertIn("MESSAGE opens COMMS", person)
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
        device = read("docs", "DEVICE.md")
        face = card.split("private var face")[1].split("private var displayName")[0]
        self.assertIn("struct EmblemPickCard", pick)
        self.assertIn("PersonEmblem.allCases", pick)
        self.assertIn("emblem.title", pick)
        self.assertIn('"FACE"', pick)
        self.assertIn("onPick", pick)
        self.assertIn("holdCardDismissDragPoints", pick)
        self.assertIn("Theme.Motion.heavy", pick)
        self.assertIn("BlackoutTokens.Chrome.mapChipHitPoints", pick)
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
        self.assertIn(".submitLabel(.search)", tab)
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
        self.assertEqual(count, 175)
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
        self.assertIn("holdCardDismissDragPoints", card)

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
        pips = tab.split("pips:", 1)[1].split("youHeading", 1)[0]
        self.assertIn("isFinite", pips)
        offline = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift")
        hold_fn = offline.split("func handleHold", 1)[1].split("func personMark", 1)[0]
        self.assertIn("CLLocationCoordinate2DIsValid", hold_fn)
        sync = offline.split("func syncPartyMarks", 1)[1].split("func syncRoute", 1)[0]
        self.assertIn("CLLocationCoordinate2DIsValid", sync)

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


if __name__ == "__main__":
    unittest.main()

