#!/usr/bin/env python3
"""Tip 68 — Linux stand-in for Speak-as-voice-and-route and the clean MAP field.

Device tip 67 came back PARTIAL, then the stills showed a second failure: the Speak row
read `INSTRUME… LOCK-ON`, the field stacked `OFF GRAPH` twice plus a bare `TRUE`, street
names never drew, and SPEAK painted the whole walk script over the canvas as an orange
text wall. Speak is voice plus the cyan route line plus one short status line — the
script never reaches the field. These contracts hold that without touching Walk or PERF.
"""
from __future__ import annotations

import json
import math
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

OFF_GRAPH = "OFF GRAPH"
OFF_PACK = "OFF PACK"
SEPARATOR = " · "
SPEAK_MAX_CHARACTERS = 32
FIELD_MAX_CHARACTERS = 44
MAX_FIELD_LINES = 3
VOID = "#000000"
SILVER = "#B8BDC2"
WALKABLE_PACKS = ("tx-west", "nm", "tx-east")
SCRIPT_PHRASES = ("Walk ", "Turn left.", "Turn right.", "Arrive at destination.", "Total ")


def haversine(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp, dl = math.radians(b_lat - a_lat), math.radians(b_lon - a_lon)
    x = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(x)))


def bearing(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    y = math.sin(math.radians(b_lon - a_lon)) * math.cos(math.radians(b_lat))
    x = math.cos(math.radians(a_lat)) * math.sin(math.radians(b_lat)) - math.sin(
        math.radians(a_lat)
    ) * math.cos(math.radians(b_lat)) * math.cos(math.radians(b_lon - a_lon))
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


def turns(coords: list[tuple[float, float]]) -> int:
    count = 0
    previous: float | None = None
    for a, b in zip(coords, coords[1:]):
        brg = bearing(a[0], a[1], b[0], b[1])
        if previous is not None:
            delta = (brg - previous + 540.0) % 360.0 - 180.0
            if abs(delta) >= 35:
                count += 1
        previous = brg
    return count


def speak_status(
    spoke: bool,
    route_coords: list[tuple[float, float]],
    plan_chrome: str,
    dest: tuple[float, float] | None,
    you: tuple[float, float] | None,
) -> str:
    if not spoke:
        return "SPEECH FAILED"
    if len(route_coords) >= 2:
        meters = sum(
            haversine(a[0], a[1], b[0], b[1]) for a, b in zip(route_coords, route_coords[1:])
        )
        count = turns(route_coords)
        turn_phrase = "1 TURN" if count == 1 else f"{count} TURNS"
        return SEPARATOR.join(["SPEAK", turn_phrase, f"{round(meters):.0f} M"])
    if plan_chrome == OFF_GRAPH:
        return SEPARATOR.join(["SPEAK", OFF_GRAPH])
    if dest is not None and you is not None:
        span = haversine(you[0], you[1], dest[0], dest[1])
        return SEPARATOR.join(["SPEAK", "DEST", f"{round(span):.0f} M"])
    return SEPARATOR.join(["SPEAK", "SET DEST"])


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
    bearing_deg: float | None,
    speak: str = "",
) -> list[str]:
    """Mirror of MapFieldChrome.lines. The destination is a pin on the canvas, so the
    middle row carries the heading rather than a latitude nobody can steer by."""
    status = joined([lock, route, tool])
    fix = "" if bearing_deg is None else f"BEARING {bearing_deg:.0f}°"
    return [line for line in (status, fix, speak.strip()) if line]


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


class SpeakStatusTests(unittest.TestCase):
    def test_speak_reports_one_short_line_not_the_walk_script(self):
        coords = [(0.0, 0.0), (0.0, 0.0017966), (0.0008993, 0.0017966)]
        status = speak_status(True, coords, "", (0.0008993, 0.0017966), (0.0, 0.0))
        self.assertEqual(status, "SPEAK · 1 TURN · 300 M")
        for phrase in SCRIPT_PHRASES:
            self.assertNotIn(phrase, status)
        self.assertNotIn("\n", status)
        self.assertNotIn("…", status)
        self.assertLessEqual(len(status), SPEAK_MAX_CHARACTERS)

    def test_every_speak_outcome_stays_short_and_whole(self):
        outcomes = [
            speak_status(False, [], "", None, None),
            speak_status(True, [], OFF_GRAPH, (31.8, -106.5), (31.76, -106.49)),
            speak_status(True, [], "", (31.8, -106.5), (31.76, -106.49)),
            speak_status(True, [], "", None, None),
        ]
        self.assertEqual(outcomes[0], "SPEECH FAILED")
        self.assertEqual(outcomes[1], "SPEAK · OFF GRAPH")
        self.assertTrue(outcomes[2].startswith("SPEAK · DEST "))
        self.assertEqual(outcomes[3], "SPEAK · SET DEST")
        for outcome in outcomes:
            self.assertTrue(outcome)
            self.assertNotIn("…", outcome)
            self.assertLessEqual(len(outcome), SPEAK_MAX_CHARACTERS)


class FieldChromeTests(unittest.TestCase):
    def test_dest_true_spray_collapses_to_three_short_lines(self):
        lines = field_lines(
            OFF_GRAPH,
            OFF_GRAPH,
            "TRUE NORTH",
            45,
            "SPEAK · 3 TURNS · 300 M",
        )
        self.assertEqual(
            lines,
            [
                "OFF GRAPH · TRUE NORTH",
                "BEARING 45°",
                "SPEAK · 3 TURNS · 300 M",
            ],
        )
        self.assertLessEqual(len(lines), MAX_FIELD_LINES)
        for line in lines:
            self.assertLessEqual(len(line), FIELD_MAX_CHARACTERS)
            self.assertNotIn("\n", line)
            self.assertNotIn("DEST 31.", line)

    def test_quiet_field_shows_nothing(self):
        self.assertEqual(field_lines("", "", "", None, ""), [])
        self.assertEqual(field_lines("", "", "", 12, "   "), ["BEARING 12°"])

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

    def test_no_walk_script_text_wall_is_painted_on_the_field(self):
        app = read("Blackout", "AppRuntime.swift")
        # The field gets a short status line; the script only ever reaches the voice.
        self.assertIn("SpeakStatus.chrome(", app)
        self.assertNotIn("speechChrome = text", app)
        self.assertNotIn("SpeakBanner", self.map_tab)
        self.assertNotIn("ScrollView", self.map_tab)
        self.assertIn("enum SpeakStatus", self.voice)
        self.assertIn("maxCharacters = 32", self.voice)
        self.assertNotIn("speakBannerHeight", self.tokens)
        status = self.voice.split("enum SpeakStatus")[1]
        for phrase in ("Turn left.", "Arrive at destination.", "Total "):
            self.assertNotIn(phrase, status)

    def test_speak_chip_still_speaks_the_whole_prompt(self):
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn('Button("SPEAK")', self.map_tab)
        self.assertIn("runtime.speakMap()", self.map_tab)
        self.assertIn("VoiceNav.prompt", app)
        self.assertIn("speech.speak(text, locale: locale)", app)
        speech = read("Packages", "OfflineSpeech", "Sources", "OfflineSpeech", "OfflineSpeech.swift")
        self.assertNotIn("prefix(", speech)
        self.assertIn("AVSpeechUtterance(string: trimmed)", speech)


class FieldChromeSourceContracts(unittest.TestCase):
    def setUp(self):
        self.map_tab = read("Blackout", "MapTab.swift")
        self.route_line = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift"
        )

    def test_field_renders_one_deduped_stack(self):
        self.assertIn("MapFieldChrome.lines(", self.map_tab)
        self.assertIn("speak: runtime.speechChrome", self.map_tab)
        self.assertIn("enum MapFieldChrome", self.route_line)
        self.assertIn("maxLines = MapFieldLine.Slot.allCases.count", self.route_line)
        self.assertIn("case status, dest, speak", self.route_line)
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

    def test_inactive_chrome_goes_quiet(self):
        app = read("Blackout", "AppRuntime.swift")
        pick = app.split("func pickDestination")[1].split("func ")[0]
        self.assertIn('toolChrome = ""', pick)
        self.assertIn('speechChrome = ""', pick)
        navigate = app.split("func navigate(mode: TravelMode)")[1].split("func tapRuler")[0]
        self.assertIn('speechChrome = ""', navigate)
        clear = app.split("private func clearRoute(")[1].split("\n    }")[0]
        self.assertIn('speechChrome = ""', clear)

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
