#!/usr/bin/env python3
"""Tip 68 — Linux stand-in for the finished Speak banner and the clean MAP field.

Device tip 67 came back PARTIAL: the Speak row read `INSTRUME… LOCK-ON`, the field
stacked `OFF GRAPH` twice plus a bare `TRUE`, and street names never drew. These are
the contracts that keep all three fixed without touching Walk cyan or the PERF work.
"""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

OFF_GRAPH = "OFF GRAPH"
OFF_PACK = "OFF PACK"
SEPARATOR = " · "
MAX_LINE_CHARACTERS = 46
MAX_FIELD_LINES = 2
VOID = "#000000"
SILVER = "#B8BDC2"
WALKABLE_PACKS = ("tx-west", "nm", "tx-east")


def sentences(text: str) -> list[str]:
    out: list[str] = []
    current = ""
    for character in text:
        current += character
        if character in ".!?":
            piece = current.strip()
            if piece:
                out.append(piece)
            current = ""
    tail = current.strip()
    if tail:
        out.append(tail)
    return out


def wrapped(sentence: str, max_characters: int = MAX_LINE_CHARACTERS) -> list[str]:
    limit = max(1, max_characters)
    words = [w for w in sentence.split(" ") if w]
    rows: list[str] = []
    row = ""
    for word in words:
        if not row:
            row = word
        elif len(row) + 1 + len(word) <= limit:
            row += " " + word
        else:
            rows.append(row)
            row = word
    if row:
        rows.append(row)
    return rows


def banner_lines(text: str, max_characters: int = MAX_LINE_CHARACTERS) -> list[str]:
    rows: list[str] = []
    for sentence in sentences(text):
        rows.extend(wrapped(sentence, max_characters))
    return rows


def joined(parts: list[str]) -> str:
    seen: set[str] = set()
    kept: list[str] = []
    for raw in parts:
        piece = raw.strip()
        if not piece or piece in seen:
            continue
        seen.add(piece)
        kept.append(piece)
    return SEPARATOR.join(kept)


def field_lines(
    lock: str,
    route: str,
    tool: str,
    dest: tuple[float, float] | None,
    bearing: float | None,
) -> list[str]:
    status = joined([lock, route, tool])
    fix: list[str] = []
    if dest is not None:
        fix.append(f"DEST {dest[0]:.4f}, {dest[1]:.4f}")
    if bearing is not None:
        fix.append(f"BEARING {bearing:.0f}°")
    return [line for line in (status, joined(fix)) if line]


def route_chrome(has_graph: bool, has_dest: bool, plan_chrome: str) -> str:
    if not has_graph:
        return OFF_GRAPH
    if not has_dest:
        return ""
    return plan_chrome


def interpolate_at(expr: object, zoom: float) -> float:
    assert isinstance(expr, list) and expr and expr[0] == "interpolate", expr
    stops = [(float(expr[i]), float(expr[i + 1])) for i in range(3, len(expr) - 1, 2)]
    if zoom <= stops[0][0]:
        return stops[0][1]
    if zoom >= stops[-1][0]:
        return stops[-1][1]
    for (z0, v0), (z1, v1) in zip(stops, stops[1:]):
        if z0 <= zoom <= z1:
            return v0 + (zoom - z0) / (z1 - z0) * (v1 - v0)
    return stops[-1][1]


def layer(style: dict, layer_id: str) -> dict | None:
    return next((item for item in style.get("layers") or [] if item.get("id") == layer_id), None)


def read(*parts: str) -> str:
    return (ROOT.joinpath(*parts)).read_text()


class SpeakBannerTests(unittest.TestCase):
    def test_full_turn_by_turn_wraps_into_readable_rows(self):
        text = (
            "Walk 200 meters. Turn left. Walk 100 meters. Arrive at destination. "
            "Total 300 meters. Heading 90 degrees."
        )
        rows = banner_lines(text)
        self.assertEqual(rows[0], "Walk 200 meters.")
        self.assertIn("Turn left.", rows)
        self.assertIn("Arrive at destination.", rows)
        self.assertEqual(" ".join(rows), text)
        for row in rows:
            self.assertNotIn("…", row)
            self.assertLessEqual(len(row), MAX_LINE_CHARACTERS)

    def test_rows_break_on_spaces_and_never_mid_word(self):
        sentence = "Tap WALK for the street path, then SPEAK."
        rows = wrapped(sentence, 18)
        self.assertEqual(rows, ["Tap WALK for the", "street path, then", "SPEAK."])
        self.assertEqual(" ".join(rows), sentence)
        # The tip-67 failure: a word wider than the row must keep its tail.
        self.assertEqual(wrapped("INSTRUMENTS", 4), ["INSTRUMENTS"])

    def test_off_graph_and_speech_failed_stay_whole(self):
        self.assertEqual(
            banner_lines("OFF GRAPH. No walkable street path from YOU. TX WEST."),
            ["OFF GRAPH.", "No walkable street path from YOU.", "TX WEST."],
        )
        self.assertEqual(banner_lines("SPEECH FAILED"), ["SPEECH FAILED"])
        self.assertEqual(banner_lines(""), [])


class FieldChromeTests(unittest.TestCase):
    def test_dest_true_spray_collapses_to_two_lines(self):
        lines = field_lines(OFF_GRAPH, OFF_GRAPH, "TRUE NORTH", (31.7619, -106.4850), 45)
        self.assertEqual(lines, ["OFF GRAPH · TRUE NORTH", "DEST 31.7619, -106.4850 · BEARING 45°"])
        self.assertLessEqual(len(lines), MAX_FIELD_LINES)

    def test_quiet_field_shows_nothing(self):
        self.assertEqual(field_lines("", "", "", None, None), [])
        self.assertEqual(field_lines("", "", "", None, 12), ["BEARING 12°"])

    def test_off_graph_is_a_routing_failure_not_a_missing_dest(self):
        self.assertEqual(route_chrome(has_graph=True, has_dest=False, plan_chrome=""), "")
        self.assertEqual(route_chrome(has_graph=False, has_dest=False, plan_chrome=""), OFF_GRAPH)
        self.assertEqual(route_chrome(has_graph=False, has_dest=True, plan_chrome=""), OFF_GRAPH)
        self.assertEqual(
            route_chrome(has_graph=True, has_dest=True, plan_chrome=OFF_GRAPH), OFF_GRAPH
        )


class SpeakChromeSourceContracts(unittest.TestCase):
    def setUp(self):
        self.map_tab = read("Blackout", "MapTab.swift")
        self.tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        self.voice = read("Packages", "Router", "Sources", "Router", "VoiceNav.swift")

    def test_header_controls_cannot_be_tail_truncated(self):
        # tip-67 shipped a plain Button("INSTRUMENTS") in a fixed HStack; at the xxxLarge
        # cap SwiftUI truncated the widest label to INSTRUME… next to LOCK-ON.
        self.assertIn("ChromeRail", self.map_tab)
        self.assertIn("MapActionChipButtonStyle", self.map_tab)
        header = self.map_tab.split("private var actionRail")[1].split("private var")[0]
        for title in ('Button("SPEAK")', 'Button("INSTRUMENTS")', '"LOCKED" : "LOCK-ON"'):
            self.assertIn(title, header)
            self.assertIn("MapActionChipButtonStyle", header)
        chip = self.map_tab.split("private struct MapActionChipButtonStyle")[1]
        self.assertIn("fixedSize(horizontal: true, vertical: false)", chip)
        self.assertIn("mapActionChipTextPoints", chip)
        self.assertNotIn("truncationMode", chip)

    def test_speak_banner_wraps_or_scrolls_the_whole_prompt(self):
        self.assertIn("SpeakBanner.lines(runtime.speechChrome)", self.map_tab)
        banner = self.map_tab.split("private var speakBanner")[1].split("private var instrumentRow")[0]
        self.assertIn("ScrollView(.vertical)", banner)
        self.assertIn("fixedSize(horizontal: false, vertical: true)", banner)
        self.assertIn("speakBannerHeight", banner)
        self.assertNotIn("lineLimit(1)", banner)
        self.assertNotIn("truncationMode", banner)
        self.assertIn("enum SpeakBanner", self.voice)
        self.assertIn("func wrapped(", self.voice)
        self.assertIn("func speakBannerHeight(", self.tokens)

    def test_speak_chip_survives(self):
        self.assertIn('Button("SPEAK")', self.map_tab)
        self.assertIn("runtime.speakMap()", self.map_tab)
        self.assertIn("VoiceNav.prompt", read("Blackout", "AppRuntime.swift"))


class FieldChromeSourceContracts(unittest.TestCase):
    def setUp(self):
        self.map_tab = read("Blackout", "MapTab.swift")
        self.route_line = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift"
        )

    def test_field_renders_one_deduped_stack(self):
        self.assertIn("MapFieldChrome.lines(", self.map_tab)
        self.assertIn("enum MapFieldChrome", self.route_line)
        self.assertIn("maxLines = 2", self.route_line)
        for stale in (
            'Text(runtime.lockChrome)',
            'Text(runtime.routeChrome)',
            'Text(runtime.toolChrome)',
            'String(format: "DEST %.4f, %.4f", dest.lat, dest.lon)',
            'String(format: "BEARING %.0f°", h)',
        ):
            self.assertNotIn(stale, self.map_tab, f"{stale} still sprays its own row")

    def test_mag_true_says_which_north(self):
        self.assertIn('magNorth ? "MAG NORTH" : "TRUE NORTH"', self.route_line)

    def test_new_dest_drops_stale_tool_chrome(self):
        app = read("Blackout", "AppRuntime.swift")
        pick = app.split("func pickDestination")[1].split("func ")[0]
        self.assertIn('toolChrome = ""', pick)

    def test_walk_cyan_route_hooks_are_untouched(self):
        offline = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift")
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn("RouteLine.sourceID", offline)
        self.assertIn("RouteLine.layerID", offline)
        self.assertIn("red: 0.12, green: 0.82, blue: 0.94", offline)
        self.assertIn("GraphPlan.line", app)
        self.assertIn("warmupActiveGraph", app)
        self.assertIn("graphWarmup", app)
        self.assertIn("applyMapKeepAwake", app)
        self.assertIn("isIdleTimerDisabled", app)


class WalkingZoomNameContracts(unittest.TestCase):
    def test_resolved_style_keeps_the_local_glyph_template_literal(self):
        pack_style = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        # appendingPathComponent percent-escapes { and }, so MapLibre never substituted
        # the fontstack/range tokens and every glyph range 404'd — no names at any zoom.
        self.assertIn("func localGlyphURL(", pack_style)
        self.assertNotIn("packRoot.appendingPathComponent(glyphs)", pack_style)
        self.assertIn("resolverVersion", pack_style)
        self.assertIn("style.resolved.v", pack_style)
        resolve = pack_style.split("func localGlyphURL(")[1].split("\n    }")[0]
        self.assertIn("absoluteString", resolve)
        self.assertNotIn("appendingPathComponent", resolve)

    def test_packs_ship_the_glyph_ranges_the_template_asks_for(self):
        for pack_id in WALKABLE_PACKS:
            root = ROOT / "Resources" / "Packs" / pack_id
            style = json.loads((root / "style.json").read_text())
            self.assertEqual(style.get("glyphs"), "glyphs/{fontstack}/{range}.pbf", pack_id)
            fonts = {
                font
                for item in style.get("layers") or []
                for font in (item.get("layout") or {}).get("text-font") or []
            }
            self.assertTrue(fonts, pack_id)
            for font in fonts:
                stack = root / "glyphs" / font
                self.assertTrue(stack.is_dir(), f"{pack_id} missing glyph stack {font}")
                self.assertTrue(
                    (stack / "0-255.pbf").is_file(), f"{pack_id} missing latin glyph range"
                )

    def test_street_names_read_at_walking_zoom(self):
        for pack_id in WALKABLE_PACKS:
            style = json.loads((ROOT / "Resources" / "Packs" / pack_id / "style.json").read_text())
            labels = layer(style, "road-labels")
            self.assertIsNotNone(labels, pack_id)
            self.assertLessEqual(float(labels.get("minzoom") or 99), 12, pack_id)
            layout = labels.get("layout") or {}
            paint = labels.get("paint") or {}
            self.assertEqual(paint.get("text-color"), SILVER, pack_id)
            self.assertEqual(paint.get("text-halo-color"), VOID, pack_id)
            self.assertGreaterEqual(float(paint.get("text-halo-width") or 0), 1.8, pack_id)
            self.assertLessEqual(float(layout.get("symbol-spacing") or 999), 110, pack_id)
            size = layout.get("text-size")
            self.assertGreaterEqual(interpolate_at(size, 16), 19, pack_id)
            self.assertGreaterEqual(interpolate_at(size, 18), 22, pack_id)

    def test_place_labels_stop_stealing_walking_zoom_slots(self):
        for pack_id in WALKABLE_PACKS:
            style = json.loads((ROOT / "Resources" / "Packs" / pack_id / "style.json").read_text())
            places = layer(style, "place-labels")
            self.assertIsNotNone(places, pack_id)
            self.assertLessEqual(float(places.get("maxzoom") or 99), 16, pack_id)
            refs = layer(style, "road-refs")
            if refs:
                spacing = float((refs.get("layout") or {}).get("symbol-spacing") or 0)
                self.assertGreaterEqual(spacing, 300, pack_id)

    def test_generator_and_swift_fallback_match_the_shipped_ramp(self):
        generator = read("tools", "v3", "fetch_packs.py")
        self.assertIn("zoom_stops(12, 12, 14, 15, 16, 19, 18, 22)", generator)
        self.assertIn('"symbol-spacing": 100', generator)
        self.assertIn('"maxzoom": 16', generator)
        fallback = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift")
        self.assertIn('12, 12, 14, 15, 16, 19, 18, 22', fallback)
        self.assertIn('"symbol-spacing": 100', fallback)

    def test_label_ink_stays_blackout_silver_on_void(self):
        washed = {"#e8eef4", "#f0f4f8", "#0c0e10"}
        for pack_id in WALKABLE_PACKS:
            style = json.loads((ROOT / "Resources" / "Packs" / pack_id / "style.json").read_text())
            for layer_id in ("road-labels", "place-labels"):
                item = layer(style, layer_id)
                if item is None:
                    continue
                paint = item.get("paint") or {}
                self.assertEqual(paint.get("text-color"), SILVER, f"{pack_id}/{layer_id}")
                self.assertEqual(paint.get("text-halo-color"), VOID, f"{pack_id}/{layer_id}")
                self.assertNotIn(paint.get("text-color"), washed, f"{pack_id}/{layer_id}")


class NoRegressionContracts(unittest.TestCase):
    def test_instrument_chips_and_canvas_survive(self):
        map_tab = read("Blackout", "MapTab.swift")
        for title in ("MARK", "WALK", "DRIVE", "RULER", "USNG", "MAG/TRUE"):
            self.assertIn(f'Button("{title}")', map_tab)
        self.assertIn("frame(width: hit, height: hit)", map_tab)
        self.assertIn("layoutPriority(1)", map_tab)
        self.assertIn("OSMCredit.line", map_tab)

    def test_no_new_surface_and_cpv_stays_one(self):
        pbx = read("Blackout.xcodeproj", "project.pbxproj")
        self.assertIn("CURRENT_PROJECT_VERSION = 1;", pbx)
        for banned in ("googleapis", "apple.com/maps", "MapKit"):
            for pack_id in WALKABLE_PACKS:
                blob = (ROOT / "Resources" / "Packs" / pack_id / "style.json").read_text().lower()
                self.assertNotIn(banned.lower(), blob)


if __name__ == "__main__":
    unittest.main()
