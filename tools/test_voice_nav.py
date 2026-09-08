#!/usr/bin/env python3
"""Linux stand-in for VoiceNav turn-by-turn Speak (no Swift on this agent)."""
from __future__ import annotations

import math
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

OFF_GRAPH = "OFF GRAPH"


def haversine(a: float, b: float, c: float, d: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(a), math.radians(c)
    dp, dl = math.radians(c - a), math.radians(d - b)
    x = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(x)))


def bearing(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    y = math.sin(math.radians(b_lon - a_lon)) * math.cos(math.radians(b_lat))
    x = math.cos(math.radians(a_lat)) * math.sin(math.radians(b_lat)) - math.sin(
        math.radians(a_lat)
    ) * math.cos(math.radians(b_lat)) * math.cos(math.radians(b_lon - a_lon))
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


def turn_name(from_b: float, to_b: float) -> str:
    delta = (to_b - from_b + 540.0) % 360.0 - 180.0
    if abs(delta) < 35:
        return "straight"
    if abs(delta) > 135:
        return "uturn"
    return "left" if delta < 0 else "right"


def meters_phrase(m: float) -> str:
    return f"{int(round(m))} meters"


def steps(coords: list[tuple[float, float]]) -> list[str]:
    if len(coords) < 2:
        return []
    lines: list[str] = []
    acc = 0.0
    prev_bearing: float | None = None
    for i in range(len(coords) - 1):
        a, b = coords[i], coords[i + 1]
        m = haversine(a[0], a[1], b[0], b[1])
        brg = bearing(a[0], a[1], b[0], b[1])
        if prev_bearing is None:
            acc += m
            prev_bearing = brg
            continue
        kind = turn_name(prev_bearing, brg)
        if kind == "straight":
            acc += m
            prev_bearing = brg
            continue
        if acc >= 8:
            lines.append(f"Walk {meters_phrase(acc)}.")
        if kind == "uturn":
            lines.append("Turn around.")
        elif kind == "left":
            lines.append("Turn left.")
        else:
            lines.append("Turn right.")
        acc = m
        prev_bearing = brg
    if acc >= 8:
        lines.append(f"Walk {meters_phrase(acc)}.")
    lines.append("Arrive at destination.")
    return lines


def prompt(
    pack_name: str,
    heading: float | None,
    route_coords: list[tuple[float, float]],
    plan_chrome: str,
    dest: tuple[float, float] | None,
    you: tuple[float, float] | None,
    locale: str = "en",
) -> str:
    _ = locale
    heading_bit = (
        f"Heading {int(round(heading))} degrees." if heading is not None else "Heading unavailable."
    )
    if len(route_coords) >= 2:
        total = 0.0
        for i in range(len(route_coords) - 1):
            a, b = route_coords[i], route_coords[i + 1]
            total += haversine(a[0], a[1], b[0], b[1])
        body = " ".join(steps(route_coords))
        return f"{body} Total {meters_phrase(total)}. {heading_bit}"
    if plan_chrome == OFF_GRAPH:
        return f"OFF GRAPH. No walkable street path from YOU. {pack_name}. {heading_bit}"
    if dest is not None and you is not None:
        span = haversine(you[0], you[1], dest[0], dest[1])
        return (
            f"Destination set. {meters_phrase(span)}. "
            f"{pack_name}. {heading_bit} Tap WALK for the street path, then SPEAK."
        )
    return (
        f"{pack_name}. {heading_bit} "
        "Set a destination, then WALK, then SPEAK for turn by turn."
    )


class VoiceNavTests(unittest.TestCase):
    def test_on_graph_left_turn_is_complete_not_truncated(self):
        # East 200m, then north 100m.
        coords = [(0.0, 0.0), (0.0, 0.0017966), (0.0008993, 0.0017966)]
        text = prompt("TX WEST", 90, coords, "", None, None)
        self.assertIn("Walk 200 meters.", text)
        self.assertIn("Turn left.", text)
        self.assertIn("Walk 100 meters.", text)
        self.assertIn("Arrive at destination.", text)
        self.assertIn("Total 300 meters.", text)
        self.assertIn("Heading 90 degrees.", text)
        self.assertFalse(text.endswith("Walk"))
        self.assertNotEqual(text, "TX WEST 90 degrees")
        self.assertGreater(len(text), 40)

    def test_off_graph_is_a_full_honest_sentence(self):
        text = prompt("TX WEST", 45, [], OFF_GRAPH, (31.8, -106.5), (31.76, -106.49))
        self.assertTrue(text.startswith("OFF GRAPH."))
        self.assertIn("No walkable street path from YOU.", text)
        self.assertIn("TX WEST.", text)
        self.assertIn("Heading 45 degrees.", text)
        self.assertGreater(len(text), 24)

    def test_no_route_explains_how_to_start_voice_nav(self):
        text = prompt("TX WEST", None, [], "", None, None)
        self.assertIn("TX WEST.", text)
        self.assertIn("Heading unavailable.", text)
        self.assertIn("Set a destination, then WALK, then SPEAK for turn by turn.", text)
        self.assertNotEqual(text.strip(), "TX WEST no heading")

    def test_dest_without_line_does_not_invent_streets(self):
        text = prompt(
            "TX WEST",
            12,
            [],
            "",
            (31.80, -106.50),
            (31.76, -106.49),
        )
        self.assertIn("Destination set.", text)
        self.assertIn("Tap WALK for the street path, then SPEAK.", text)
        self.assertNotIn("Turn left.", text)
        self.assertNotIn("Arrive at destination.", text)


class VoiceNavSourceContracts(unittest.TestCase):
    def test_swift_voice_nav_is_not_the_truncated_stub(self):
        router = (ROOT / "Packages" / "Router" / "Sources" / "Router" / "Router.swift").read_text()
        voice = ROOT / "Packages" / "Router" / "Sources" / "Router" / "VoiceNav.swift"
        voice_text = voice.read_text() if voice.is_file() else ""
        blob = router + "\n" + voice_text
        self.assertIn("enum VoiceNav", blob)
        self.assertIn("func prompt(", blob)
        self.assertIn("Arrive at destination.", blob)
        self.assertIn("Turn left.", blob)
        self.assertIn("Turn right.", blob)
        self.assertIn("No walkable street path from YOU.", blob)
        self.assertIn("Set a destination, then WALK, then SPEAK for turn by turn.", blob)

    def test_speak_chip_stays_and_voice_gets_the_full_prompt(self):
        # tip-68 supersedes the tip-65 banner: the complete prompt is spoken, and the
        # field shows one short status line instead of the walk script.
        app = (ROOT / "Blackout" / "AppRuntime.swift").read_text()
        map_tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
        self.assertIn('Button("SPEAK")', map_tab)
        self.assertIn("runtime.speakMap()", map_tab)
        self.assertIn("VoiceNav.prompt", app)
        self.assertIn("speech.speak(text, locale: locale)", app)
        self.assertIn("SpeakStatus.chrome(", app)
        self.assertNotIn('speech.speak("\\(pack) \\(bearing)"', app)
        self.assertIn("fixedSize(horizontal: false, vertical: true)", map_tab)
        self.assertNotIn("lineLimit(1)", map_tab.split("MapFieldChrome.lines(")[1])

    def test_speech_engine_finishes_the_full_utterance(self):
        speech = (
            ROOT / "Packages" / "OfflineSpeech" / "Sources" / "OfflineSpeech" / "OfflineSpeech.swift"
        ).read_text()
        self.assertIn("stopSpeaking", speech)
        self.assertIn("preUtteranceDelay", speech)
        self.assertNotIn("prefix(", speech)

    def test_router_unit_tests_lock_complete_prompts(self):
        tests = (ROOT / "Packages" / "Router" / "Tests" / "RouterTests" / "RouterTests.swift").read_text()
        self.assertIn("testVoiceNavOnGraphLeftTurnIsCompleteNotTruncated", tests)
        self.assertIn("testVoiceNavOffGraphIsFullHonestSentence", tests)
        self.assertIn("Arrive at destination.", tests)


if __name__ == "__main__":
    unittest.main()
