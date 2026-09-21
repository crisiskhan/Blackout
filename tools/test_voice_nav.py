#!/usr/bin/env python3
"""Linux stand-in for VoiceNav turn-by-turn Speak (no Swift on this agent)."""
from __future__ import annotations

import math
import unittest
from dataclasses import dataclass
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


START_HINT = "Set a destination, then WALK or DRIVE."
DEST_HINT = "Tap WALK or DRIVE for the street path."
NO_FIX_HINT = "No GNSS fix."


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
    if dest is None:
        return f"{pack_name}. {heading_bit} {START_HINT}"
    if you is None:
        return f"{pack_name}. {heading_bit} {NO_FIX_HINT}"
    span = haversine(you[0], you[1], dest[0], dest[1])
    return (
        f"Destination set. {meters_phrase(span)}. "
        f"{pack_name}. {heading_bit} {DEST_HINT}"
    )


LIVE_NAV_ARRIVE = 25.0
LIVE_NAV_TURN = 50.0
LIVE_NAV_OFF = 80.0


@dataclass(frozen=True)
class LiveCue:
    remaining_meters: float
    remaining_coords: list[tuple[float, float]]
    nearest_index: int
    meters_to_line: float
    meters_to_turn: float
    arrived: bool
    off_route: bool
    speak_turn: str
    next_hud: str


def _project_on_segment(
    point: tuple[float, float],
    start: tuple[float, float],
    end: tuple[float, float],
) -> tuple[tuple[float, float], float]:
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    length2 = dx * dx + dy * dy
    if length2 < 1e-18:
        return start, 0.0
    t = ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / length2
    t = max(0.0, min(1.0, t))
    return (start[0] + t * dx, start[1] + t * dy), t


def vertex_kind(coords: list[tuple[float, float]], index: int) -> str:
    if index <= 0 or index >= len(coords) - 1:
        return ""
    from_b = bearing(
        coords[index - 1][0],
        coords[index - 1][1],
        coords[index][0],
        coords[index][1],
    )
    to_b = bearing(
        coords[index][0],
        coords[index][1],
        coords[index + 1][0],
        coords[index + 1][1],
    )
    kind = turn_name(from_b, to_b)
    return "" if kind == "straight" else kind


def _polyline_meters(coords: list[tuple[float, float]]) -> float:
    total = 0.0
    for i in range(len(coords) - 1):
        total += haversine(coords[i][0], coords[i][1], coords[i + 1][0], coords[i + 1][1])
    return total


def live_nav_progress(
    you: tuple[float, float],
    dest: tuple[float, float] | None,
    coords: list[tuple[float, float]],
    streets: list[str | None] | None = None,
    mode: str = "walk",
) -> LiveCue:
    names = list(streets or [])
    if len(coords) < 2:
        dest_pt = dest or (coords[-1] if coords else you)
        span = haversine(you[0], you[1], dest_pt[0], dest_pt[1])
        return LiveCue(0.0, list(coords), 0, 0.0, 0.0, span < LIVE_NAV_ARRIVE, False, "", "")
    best_d = float("inf")
    best_i = 0
    best_pt = coords[0]
    for i in range(len(coords) - 1):
        pt, _ = _project_on_segment(you, coords[i], coords[i + 1])
        d = haversine(you[0], you[1], pt[0], pt[1])
        if d < best_d:
            best_d = d
            best_i = i
            best_pt = pt
    remaining = [best_pt] + list(coords[best_i + 1 :])
    sliced = list(names[best_i:]) if names else []
    if len(remaining) >= 2:
        first_leg = haversine(
            remaining[0][0], remaining[0][1], remaining[1][0], remaining[1][1]
        )
        turn_here = bool(vertex_kind(coords, best_i + 1))
        if first_leg < 1.0 and not turn_here:
            remaining = remaining[1:]
            if sliced:
                sliced = sliced[1:]
    remaining_m = _polyline_meters(remaining)
    dest_pt = dest or coords[-1]
    to_dest = haversine(you[0], you[1], dest_pt[0], dest_pt[1])
    on_line = best_d <= LIVE_NAV_OFF
    arrived = to_dest < LIVE_NAV_ARRIVE or (on_line and remaining_m < LIVE_NAV_ARRIVE)
    off_route = (not arrived) and best_d > LIVE_NAV_OFF
    meters_to_turn = remaining_m
    for i in range(1, len(remaining) - 1):
        if vertex_kind(remaining, i):
            meters_to_turn = _polyline_meters(remaining[: i + 1])
            break
    speak_turn = ""
    if not arrived and not off_route and meters_to_turn <= LIVE_NAV_TURN:
        for line in steps(remaining, mode, sliced):
            if line.startswith("Turn"):
                speak_turn = line
                break
    return LiveCue(
        remaining_meters=remaining_m,
        remaining_coords=remaining,
        nearest_index=best_i,
        meters_to_line=best_d,
        meters_to_turn=meters_to_turn,
        arrived=arrived,
        off_route=off_route,
        speak_turn=speak_turn,
        next_hud=next_turn_hud(remaining, sliced),
    )


LEFT_TURN_ROUTE = [(0.0, 0.0), (0.0, 0.0017966), (0.0008993, 0.0017966)]
# About 40 m before the corner on the eastbound 200 m leg.
NEAR_LEFT_TURN = (0.0, 0.00143728)


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

    def test_dest_without_you_names_no_fix(self):
        text = prompt("TX WEST", None, [], "", (31.80, -106.50), None)
        self.assertIn(NO_FIX_HINT, text)
        self.assertNotIn(START_HINT, text)
        self.assertNotIn("Destination set.", text)
        self.assertNotIn("Turn left.", text)

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


class LiveNavTests(unittest.TestCase):
    def test_start_of_the_line_keeps_the_upcoming_turn_quiet(self):
        cue = live_nav_progress(LEFT_TURN_ROUTE[0], LEFT_TURN_ROUTE[-1], LEFT_TURN_ROUTE)
        self.assertFalse(cue.arrived)
        self.assertFalse(cue.off_route)
        self.assertEqual(cue.speak_turn, "")
        self.assertEqual(cue.next_hud, "LEFT")
        self.assertAlmostEqual(cue.remaining_meters, 300, delta=5)
        self.assertGreater(cue.meters_to_turn, LIVE_NAV_TURN)

    def test_upcoming_turn_is_spoken_once_you_are_close(self):
        cue = live_nav_progress(NEAR_LEFT_TURN, LEFT_TURN_ROUTE[-1], LEFT_TURN_ROUTE)
        self.assertFalse(cue.arrived)
        self.assertFalse(cue.off_route)
        self.assertEqual(cue.speak_turn, "Turn left.")
        self.assertLessEqual(cue.meters_to_turn, LIVE_NAV_TURN)
        self.assertGreater(cue.meters_to_turn, 0)
        self.assertLess(cue.remaining_meters, 300)
        self.assertEqual(cue.next_hud, "LEFT")

    def test_named_street_turn_keeps_the_onto_name(self):
        streets = ["Montana Avenue", "Piedras Street"]
        cue = live_nav_progress(
            NEAR_LEFT_TURN,
            LEFT_TURN_ROUTE[-1],
            LEFT_TURN_ROUTE,
            streets=streets,
        )
        self.assertEqual(cue.speak_turn, "Turn left onto Piedras Street.")
        self.assertEqual(cue.next_hud, "LEFT · PIEDRAS STREET")

    def test_remaining_chrome_shrinks_as_you_move(self):
        start = live_nav_progress(LEFT_TURN_ROUTE[0], LEFT_TURN_ROUTE[-1], LEFT_TURN_ROUTE)
        mid = live_nav_progress((0.0, 0.0008983), LEFT_TURN_ROUTE[-1], LEFT_TURN_ROUTE)
        self.assertLess(mid.remaining_meters, start.remaining_meters)
        self.assertAlmostEqual(mid.remaining_meters, 200, delta=8)
        self.assertEqual(mid.speak_turn, "")

    def test_arrival_is_when_you_are_there(self):
        cue = live_nav_progress(LEFT_TURN_ROUTE[-1], LEFT_TURN_ROUTE[-1], LEFT_TURN_ROUTE)
        self.assertTrue(cue.arrived)
        self.assertFalse(cue.off_route)
        self.assertEqual(cue.speak_turn, "")

    def test_off_the_line_is_off_route_not_a_turn(self):
        cue = live_nav_progress((0.0, -0.01), LEFT_TURN_ROUTE[-1], LEFT_TURN_ROUTE)
        self.assertTrue(cue.off_route)
        self.assertFalse(cue.arrived)
        self.assertEqual(cue.speak_turn, "")
        self.assertGreater(cue.meters_to_line, LIVE_NAV_OFF)


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
        self.assertIn(NO_FIX_HINT, blob)
        self.assertIn('return "Drive"', blob)
        self.assertIn('return "Walk"', blob)
        speak = (ROOT / "Blackout" / "AppRuntime.swift").read_text().split("func speakMap()")[1].split("func beginPTTSolo")[0]
        self.assertIn("travelMode:", speak)
        self.assertIn("VoiceNav.prompt", speak)

    def test_walk_and_drive_speak_with_the_live_voice(self):
        app = (ROOT / "Blackout" / "AppRuntime.swift").read_text()
        qa = (ROOT / "docs" / "SOLO_QA.md").read_text()
        nav = app.split("func navigate(mode:")[1].split("func tapRuler")[0]
        speak = app.split("func speakMap()")[1].split("func beginPTTSolo")[0]
        tone = app.split("func applySpeechTone()")[1].split("func ", 1)[0]
        blocked = nav.split("Task {", 1)[0]
        plotted = nav.split("GraphPlan.line")[1]
        self.assertIn("speakMap()", blocked)
        self.assertIn("speakMap()", plotted)
        self.assertIn("navSeq", nav)
        self.assertIn("applySpeechTone()", speak)
        self.assertIn("instruments.state.voice", tone)
        self.assertIn("speech.setTone", tone)
        self.assertIn("WALK and DRIVE speak", qa)
        self.assertIn("SPEAK replays", qa)
        self.assertIn("WALK, DRIVE, and SPEAK", qa)
        self.assertIn("as YOU move", qa)
        self.assertIn("OFF ROUTE", qa)
        self.assertNotIn("then SPEAK for turn by turn", qa)
        self.assertNotIn("best in class", qa.lower())
        self.assertNotIn("Waze", app)
        self.assertNotIn("Google Maps", speak)
        self.assertNotIn("Google", qa)
        pull = app.split("func pullFix()")[1].split("static func resourceRoot")[0]
        self.assertIn("applyLiveGuide()", pull)
        self.assertIn("func applyLiveGuide()", app)
        guide = app.split("func applyLiveGuide()")[1].split("static func resourceRoot")[0]
        self.assertIn("LiveNav.progress", guide)
        self.assertIn("VoiceNav.arrive", guide)
        self.assertIn("SpeakStatus.offRouteLine", guide)
        self.assertIn("navigate(mode: travelMode)", guide)
        self.assertIn("remainingCoords", guide)
        self.assertIn("liveSpokenTurn", guide)
        self.assertIn("cue.speakTurn", guide)
        self.assertNotIn("VoiceNav.prompt", guide)
        live = ROOT / "Packages" / "Router" / "Sources" / "Router" / "LiveNav.swift"
        self.assertTrue(live.is_file())
        live_text = live.read_text()
        self.assertIn("enum LiveNav", live_text)
        self.assertIn("func progress(", live_text)
        self.assertIn("arriveMeters", live_text)
        self.assertIn("turnCueMeters", live_text)
        self.assertIn("offRouteMeters", live_text)
        for slogan in ("best in class", "Waze", "Google Maps", "Apple Maps", "Google"):
            self.assertNotIn(slogan, live_text)
            self.assertNotIn(slogan, guide)

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
        self.assertIn("testVoiceNavDestWithoutYouNamesNoFix", tests)
        self.assertIn("testGraphPlanRefusesAFarSnapAndStitchesANearYou", tests)
        self.assertIn("testVoiceNavDriveTurnByTurnUsesDriveNotWalk", tests)
        self.assertIn("testDriveTakesTheFasterRoadNotTheShortestResidential", tests)
        self.assertIn("testVoiceNavNamesTheStreetsItTurnsOnto", tests)
        self.assertIn("testLiveNavSpeaksTheUpcomingTurnOnceYouAreClose", tests)
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
        self.assertIn("static let offRoute = \"OFF ROUTE\"", voice)
        self.assertIn("func offRouteLine(", voice)
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
