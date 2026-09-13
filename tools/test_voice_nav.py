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


METERS_PER_MILE = 1609.344
FEET_PER_METER = 3.280839895


def distance_hud(meters: float) -> str:
    """Mirror of BlackoutTokens.Distance.hud."""
    if meters >= METERS_PER_MILE:
        return f"{meters / METERS_PER_MILE:.1f} MI"
    return f"{round(round(meters) * FEET_PER_METER):.0f} FT"


def distance_spoken(meters: float) -> str:
    """Mirror of BlackoutTokens.Distance.spoken."""
    if meters >= METERS_PER_MILE:
        return f"{meters / METERS_PER_MILE:.1f} miles"
    return f"{round(round(meters) * FEET_PER_METER):.0f} feet"


def meters_phrase(m: float) -> str:
    return distance_spoken(m)


def verb(mode: str) -> str:
    return "Drive" if mode == "drive" else "Walk"


def off_graph_path(mode: str) -> str:
    kind = "drivable" if mode == "drive" else "walkable"
    return f"No {kind} street path from YOU."


START_HINT = "Set a destination, then WALK or DRIVE, then SPEAK for turn by turn."
DEST_HINT = "Tap WALK or DRIVE for the street path, then SPEAK."


def street_at(streets: list[str | None], index: int) -> str | None:
    if index < 0 or index >= len(streets):
        return None
    name = streets[index]
    if not name:
        return None
    trimmed = name.strip()
    return trimmed or None


def spoken_leg(mode: str, meters: float, street: str | None) -> str:
    if street:
        return f"{verb(mode)} {meters_phrase(meters)} on {street}."
    return f"{verb(mode)} {meters_phrase(meters)}."


def spoken_turn(kind: str, onto: str | None) -> str:
    if kind == "uturn":
        return f"Turn around onto {onto}." if onto else "Turn around."
    word = "left" if kind == "left" else "right"
    if onto:
        return f"Turn {word} onto {onto}."
    return f"Turn {word}."


def hud_turn_word(kind: str) -> str:
    if kind == "left":
        return "LEFT"
    if kind == "right":
        return "RIGHT"
    return "AROUND"


def hud_leg(mode: str, meters: float, street: str | None) -> str:
    word = "DRIVE" if mode == "drive" else "WALK"
    parts = [word, distance_hud(meters)]
    if street:
        parts.append(street.upper())
    return " · ".join(parts)


def hud_turn(kind: str, onto: str | None) -> str:
    parts = [hud_turn_word(kind)]
    if onto:
        parts.append(onto.upper())
    return " · ".join(parts)


def steps(
    coords: list[tuple[float, float]],
    mode: str = "walk",
    streets: list[str | None] | None = None,
) -> list[str]:
    if len(coords) < 2:
        return []
    names = streets or []
    lines: list[str] = []
    acc = 0.0
    prev_bearing: float | None = None
    leg_street: str | None = street_at(names, 0)
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
            lines.append(spoken_leg(mode, acc, leg_street))
        onto = street_at(names, i)
        lines.append(spoken_turn(kind, onto))
        acc = m
        prev_bearing = brg
        leg_street = onto
    if acc >= 8:
        lines.append(spoken_leg(mode, acc, leg_street))
    lines.append("Arrive at destination.")
    return lines


def hud_turns(
    coords: list[tuple[float, float]],
    mode: str = "walk",
    streets: list[str | None] | None = None,
) -> list[str]:
    if len(coords) < 2:
        return []
    names = streets or []
    lines: list[str] = []
    acc = 0.0
    prev_bearing: float | None = None
    leg_street: str | None = street_at(names, 0)
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
            lines.append(hud_leg(mode, acc, leg_street))
        onto = street_at(names, i)
        lines.append(hud_turn(kind, onto))
        acc = m
        prev_bearing = brg
        leg_street = onto
    if acc >= 8:
        lines.append(hud_leg(mode, acc, leg_street))
    lines.append("ARRIVE")
    return lines


def next_turn_hud(
    coords: list[tuple[float, float]],
    streets: list[str | None] | None = None,
) -> str:
    for line in hud_turns(coords, streets=streets):
        if line.startswith("LEFT") or line.startswith("RIGHT") or line.startswith("AROUND"):
            return line
    return ""


def prompt(
    pack_name: str,
    heading: float | None,
    route_coords: list[tuple[float, float]],
    plan_chrome: str,
    dest: tuple[float, float] | None,
    you: tuple[float, float] | None,
    locale: str = "en",
    mode: str = "walk",
    streets: list[str | None] | None = None,
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
        body = " ".join(steps(route_coords, mode, streets))
        return f"{body} Total {meters_phrase(total)}. {heading_bit}"
    if plan_chrome == OFF_GRAPH:
        return f"OFF GRAPH. {off_graph_path(mode)} {pack_name}. {heading_bit}"
    if dest is not None and you is not None:
        span = haversine(you[0], you[1], dest[0], dest[1])
        return (
            f"Destination set. {meters_phrase(span)}. "
            f"{pack_name}. {heading_bit} {DEST_HINT}"
        )
    return f"{pack_name}. {heading_bit} {START_HINT}"


class VoiceNavTests(unittest.TestCase):
    def test_on_graph_left_turn_is_complete_not_truncated(self):
        # East 200m, then north 100m.
        coords = [(0.0, 0.0), (0.0, 0.0017966), (0.0008993, 0.0017966)]
        text = prompt("TX WEST", 90, coords, "", None, None)
        self.assertIn("Walk 656 feet.", text)
        self.assertIn("Turn left.", text)
        self.assertIn("Walk 328 feet.", text)
        self.assertIn("Arrive at destination.", text)
        self.assertIn("Total 984 feet.", text)
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
        self.assertIn(START_HINT, text)
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
        self.assertIn(DEST_HINT, text)
        self.assertNotIn("Turn left.", text)
        self.assertNotIn("Arrive at destination.", text)

    def test_drive_turn_by_turn_uses_drive_not_walk(self):
        coords = [(0.0, 0.0), (0.0, 0.0017966), (0.0008993, 0.0017966)]
        text = prompt("TX WEST", 90, coords, "", None, None, mode="drive")
        self.assertIn("Drive 656 feet.", text)
        self.assertIn("Turn left.", text)
        self.assertIn("Drive 328 feet.", text)
        self.assertIn("Arrive at destination.", text)
        self.assertIn("Total 984 feet.", text)
        self.assertNotIn("Walk 656 feet.", text)
        self.assertFalse(text.endswith("Drive"))

    def test_drive_off_graph_is_honest_about_cars(self):
        text = prompt("TX WEST", 45, [], OFF_GRAPH, (31.8, -106.5), (31.76, -106.49), mode="drive")
        self.assertTrue(text.startswith("OFF GRAPH."))
        self.assertIn("No drivable street path from YOU.", text)
        self.assertNotIn("walkable", text)

    def test_named_streets_are_spoken_on_each_leg_and_turn(self):
        coords = [(0.0, 0.0), (0.0, 0.0017966), (0.0008993, 0.0017966)]
        streets = ["Montana Avenue", "Piedras Street"]
        text = prompt("TX WEST", 90, coords, "", None, None, streets=streets)
        self.assertIn("Walk 656 feet on Montana Avenue.", text)
        self.assertIn("Turn left onto Piedras Street.", text)
        self.assertIn("Walk 328 feet on Piedras Street.", text)
        self.assertIn("Arrive at destination.", text)
        self.assertNotIn("Turn left. ", text)
        self.assertNotIn("Walk 656 feet.", text.replace("Walk 656 feet on Montana Avenue.", ""))

    def test_drive_names_the_streets_it_turns_onto(self):
        coords = [(0.0, 0.0), (0.0, 0.0017966), (0.0008993, 0.0017966)]
        streets = ["Montana Avenue", "Piedras Street"]
        text = prompt("TX WEST", 90, coords, "", None, None, mode="drive", streets=streets)
        self.assertIn("Drive 656 feet on Montana Avenue.", text)
        self.assertIn("Turn left onto Piedras Street.", text)
        self.assertIn("Drive 328 feet on Piedras Street.", text)
        self.assertNotIn("Walk ", text)

    def test_missing_street_names_do_not_invent_a_road(self):
        coords = [(0.0, 0.0), (0.0, 0.0017966), (0.0008993, 0.0017966)]
        text = prompt("TX WEST", 90, coords, "", None, None)
        self.assertIn("Turn left.", text)
        self.assertNotIn("onto", text)
        self.assertNotIn("Montana", text)

    def test_hud_turns_are_street_by_street_not_the_spoken_script(self):
        coords = [(0.0, 0.0), (0.0, 0.0017966), (0.0008993, 0.0017966)]
        streets = ["Montana Avenue", "Piedras Street"]
        lines = hud_turns(coords, mode="drive", streets=streets)
        self.assertEqual(
            lines,
            [
                "DRIVE · 656 FT · MONTANA AVENUE",
                "LEFT · PIEDRAS STREET",
                "DRIVE · 328 FT · PIEDRAS STREET",
                "ARRIVE",
            ],
        )
        self.assertEqual(next_turn_hud(coords, streets), "LEFT · PIEDRAS STREET")
        for line in lines:
            self.assertNotIn("Turn left", line)
            self.assertNotIn("feet.", line)
            self.assertLessEqual(len(line), 44)


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
        self.assertIn("No drivable street path from YOU.", blob)
        self.assertIn(START_HINT, blob)
        self.assertIn(DEST_HINT, blob)
        self.assertIn('return "Drive"', blob)
        self.assertIn('return "Walk"', blob)
        speak = (ROOT / "Blackout" / "AppRuntime.swift").read_text().split("func speakMap()")[1].split("func beginPTTSolo")[0]
        self.assertIn("travelMode:", speak)
        self.assertIn("VoiceNav.prompt", speak)

    def test_speak_chip_stays_and_voice_gets_the_full_prompt(self):
        # tip-68 supersedes the tip-65 banner: the complete prompt is spoken, and the
        # field shows one short status line instead of the walk script.
        app = (ROOT / "Blackout" / "AppRuntime.swift").read_text()
        map_tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
        self.assertIn("BlackoutTokens.MapDock.allCases", map_tab)
        self.assertIn("runtime.speakMap()", map_tab)
        self.assertIn("VoiceNav.prompt", app)
        self.assertIn("speech.speak(text, locale: locale)", app)
        self.assertIn("SpeakStatus.chrome(", app)
        self.assertNotIn('speech.speak("\\(pack) \\(bearing)"', app)
        self.assertIn("fixedSize(horizontal: false, vertical: true)", map_tab)
        field = map_tab.split("MapFieldChrome.lines(")[1].split("struct MapFieldDestRail")[0]
        self.assertNotIn("lineLimit(1)", field)

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
        self.assertIn("testVoiceNavDriveTurnByTurnUsesDriveNotWalk", tests)
        self.assertIn("testDriveTakesTheFasterRoadNotTheShortestResidential", tests)
        self.assertIn("testVoiceNavNamesTheStreetsItTurnsOnto", tests)
        self.assertIn("Arrive at destination.", tests)

    def test_swift_speaks_named_streets_and_keeps_five_voices(self):
        voice = (ROOT / "Packages" / "Router" / "Sources" / "Router" / "VoiceNav.swift").read_text()
        app = (ROOT / "Blackout" / "AppRuntime.swift").read_text()
        inst = (ROOT / "Packages" / "Instruments" / "Sources" / "Instruments" / "Instruments.swift").read_text()
        sheet = (ROOT / "Blackout" / "InstrumentsView.swift").read_text()
        speech = (
            ROOT / "Packages" / "OfflineSpeech" / "Sources" / "OfflineSpeech" / "OfflineSpeech.swift"
        ).read_text()
        search = (ROOT / "Packages" / "Search" / "Sources" / "Search" / "Search.swift").read_text()
        self.assertIn("Turn left onto", voice)
        self.assertIn("Turn right onto", voice)
        self.assertIn("streets:", voice)
        self.assertIn("func hudTurns(", voice)
        self.assertIn("func nextTurnHUD(", voice)
        self.assertIn("func streetName(near", search)
        self.assertIn("streets:", app.split("func speakMap()")[1].split("func beginPTTSolo")[0])
        self.assertIn("enum NavVoice", inst)
        for name in ("STEEL", "NIGHT", "RANGE", "MESH", "DESERT"):
            self.assertIn(f'return "{name}"', inst, name)
        self.assertIn("NavVoice.allCases", sheet)
        self.assertIn("voice.title", sheet)
        self.assertIn('sectionLabel("VOICE")', sheet)
        self.assertNotIn("pickerStyle", sheet)
        self.assertIn("setTone", speech)
        self.assertIn("pitchMultiplier", speech)
        for slogan in ("best in class", "Waze", "Google Maps", "Apple Maps"):
            self.assertNotIn(slogan, voice)
            self.assertNotIn(slogan, inst)
            self.assertNotIn(slogan, sheet)
            self.assertNotIn(slogan, speech)


if __name__ == "__main__":
    unittest.main()
