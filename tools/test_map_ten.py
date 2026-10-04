#!/usr/bin/env python3
"""Night-walk map/nav invariants. The instrument stays honest on the pack."""
from __future__ import annotations

import math
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


def haversine(a: float, b: float, c: float, d: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(a), math.radians(c)
    dp, dl = math.radians(c - a), math.radians(d - b)
    x = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(x)))


def project_degrees(
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


def project_metres(
    lat: float,
    lon: float,
    a_lat: float,
    a_lon: float,
    b_lat: float,
    b_lon: float,
) -> tuple[float, float, float, float]:
    metres_lon = 111_320.0 * math.cos(math.radians(lat))
    ax = (a_lon - lon) * metres_lon
    ay = (a_lat - lat) * 110_540.0
    bx = (b_lon - lon) * metres_lon
    by = (b_lat - lat) * 110_540.0
    dx = bx - ax
    dy = by - ay
    length2 = dx * dx + dy * dy
    if length2 < 1:
        t = 0.0
    else:
        t = min(1.0, max(0.0, (-ax * dx - ay * dy) / length2))
    return (
        a_lat + t * (b_lat - a_lat),
        a_lon + t * (b_lon - a_lon),
        math.hypot(ax + t * dx, ay + t * dy),
        t,
    )


def off_route_limit(mode: str) -> float:
    return 45.0 if mode == "walk" else 80.0


def should_replan(
    now: float,
    last_replan_at: float,
    meters_to_line: float,
    mode: str,
    replan_seconds: float = 8.0,
    far_off: float = 2.0,
) -> bool:
    if last_replan_at == 0:
        return True
    if meters_to_line > off_route_limit(mode) * far_off:
        return True
    return now - last_replan_at >= replan_seconds


def nth(n: int) -> str:
    teen = n % 100
    if 11 <= teen <= 13:
        return f"{n}th"
    return {1: f"{n}st", 2: f"{n}nd", 3: f"{n}rd"}.get(n % 10, f"{n}th")


def ordinal_aliases(token: str) -> set[str] | None:
    pairs = {
        "1st": "first",
        "2nd": "second",
        "3rd": "third",
        "4th": "fourth",
        "5th": "fifth",
        "6th": "sixth",
        "7th": "seventh",
        "8th": "eighth",
        "9th": "ninth",
        "10th": "tenth",
        "11th": "eleventh",
        "12th": "twelfth",
        "13th": "thirteenth",
        "14th": "fourteenth",
        "15th": "fifteenth",
        "16th": "sixteenth",
        "17th": "seventeenth",
        "18th": "eighteenth",
        "19th": "nineteenth",
        "20th": "twentieth",
    }
    inverse = {word: token for token, word in pairs.items()}

    def pack(n: int) -> set[str]:
        out = {str(n), nth(n)}
        key = nth(n)
        if key in pairs:
            out.add(pairs[key])
        return out

    if token.isdigit() and 1 <= int(token) <= 99:
        return pack(int(token))
    if token in pairs:
        return pack(int(token[:-2]))
    if token in inverse:
        return pack(int(inverse[token][:-2]))
    for suffix in ("st", "nd", "rd", "th"):
        if token.endswith(suffix) and token[: -len(suffix)].isdigit():
            n = int(token[: -len(suffix)])
            if 1 <= n <= 99 and nth(n) == token:
                return pack(n)
    return None


class MetreSnapTests(unittest.TestCase):
    def test_diagonal_at_el_paso_needs_metre_space(self):
        start = (31.76, -106.50)
        end = (31.80, -106.46)
        you = (31.781, -106.478)
        deg_pt, _ = project_degrees(you, start, end)
        m_lat, m_lon, metres, _ = project_metres(you[0], you[1], start[0], start[1], end[0], end[1])
        deg_off = haversine(you[0], you[1], deg_pt[0], deg_pt[1])
        self.assertGreater(abs(deg_off - metres), 0.4)
        self.assertLess(metres, 80)
        self.assertAlmostEqual(m_lat, 31.781, delta=0.01)

    def test_live_nav_projects_in_metre_space(self):
        live = read("Packages", "Router", "Sources", "Router", "LiveNav.swift")
        router = read("Packages", "Router", "Sources", "Router", "Router.swift")
        self.assertIn("func projectOnSegment(", router)
        self.assertIn("111_320.0", router)
        self.assertIn("110_540.0", router)
        self.assertIn("GraphRouter.projectOnSegment", live)
        self.assertNotIn("let dx = b.lat - a.lat", live)


class LiveGuideTests(unittest.TestCase):
    def test_walk_is_tighter_than_drive(self):
        self.assertEqual(off_route_limit("walk"), 45.0)
        self.assertEqual(off_route_limit("drive"), 80.0)
        live = read("Packages", "Router", "Sources", "Router", "LiveNav.swift")
        self.assertIn("offRouteWalkMeters", live)
        self.assertIn("func offRouteLimit(", live)
        self.assertIn("case .walk: return offRouteWalkMeters", live)
        self.assertIn("arriveMeters: Double = 25", live)
        self.assertIn("arriveDriveMeters: Double = 40", live)
        self.assertIn("turnCueMeters: Double = 50", live)
        self.assertIn("turnCueDriveMeters: Double = 160", live)
        self.assertIn("func turnCueLimit(", live)
        self.assertIn("replanSeconds: TimeInterval = 8", live)

    def test_first_off_route_replans_now_and_far_off_does_not_wait(self):
        self.assertTrue(should_replan(1000, 0, 50, "walk"))
        self.assertTrue(should_replan(1008, 1000, 50, "walk"))
        self.assertFalse(should_replan(1004, 1000, 50, "walk"))
        self.assertTrue(should_replan(1004, 1000, 100, "walk"))
        live = read("Packages", "Router", "Sources", "Router", "LiveNav.swift")
        self.assertIn("func shouldReplan(", live)
        self.assertIn("farOffFactor", live)
        guide = read("Blackout", "AppRuntime.swift").split("func applyLiveGuide()")[1].split(
            "static func resourceRoot"
        )[0]
        self.assertIn("LiveNav.shouldReplan(", guide)
        self.assertIn("fieldYou", guide)
        self.assertIn("gnssYou", guide)
        self.assertIn('speakNextHUD = ""', guide)
        self.assertIn("speakHUDTurns = []", guide)
        self.assertIn("RouteSummary.chrome(", guide)

    def test_first_leg_is_the_next_move_until_the_turn_is_close(self):
        live = read("Packages", "Router", "Sources", "Router", "LiveNav.swift")
        self.assertIn('hasPrefix("Walk")', live)
        self.assertIn('hasPrefix("Drive")', live)
        self.assertIn('hasPrefix("Turn")', live)
        speak = read("Blackout", "AppRuntime.swift").split("func speakMap()")[1].split(
            "func closeSpeakTurns"
        )[0]
        self.assertIn("liveSpokenTurn = cue.speakTurn", speak)

    def test_silver_line_trims_to_remaining_while_you_are_on_it(self):
        route = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift")
        tab = read("Blackout", "MapTab.swift")
        route_enum = route.split("public enum RouteLine")[1].split("public enum HoldPin")[0]
        self.assertIn("func paintCoords(", route_enum)
        self.assertIn("cue.offRoute", route_enum)
        self.assertIn("remainingCoords", route_enum)
        self.assertIn("RouteLine.paintCoords(", tab)
        self.assertIn("runtime.fieldYou", tab.split("OfflineMapView(")[1].split("destination:")[0])
        remaining = route.split("func liveRemainingHUD(")[1].split("func destValue(")[0]
        self.assertIn("cue.offRoute", remaining)
        self.assertIn('return ""', remaining)
        rail = tab.split("struct MapFieldDestRail")[1].split("private var hudReserve")[0]
        self.assertNotIn(".lineLimit(1)", rail.split("if !turn.isEmpty")[1].split("if !remain.isEmpty")[0])
        card = read("Blackout", "SpeakTurnCard.swift")
        rows = card.split("ForEach(Array(turns.prefix(2)")[1]
        self.assertNotIn(".lineLimit(1)", rows)
        voice = read("Packages", "Router", "Sources", "Router", "VoiceNav.swift")
        fit = voice.split("func hudFit(")[1].split("func turn(")[0]
        self.assertNotIn("removeLast()", fit)
        self.assertNotIn("count > 44", fit)


class HonestFixTests(unittest.TestCase):
    def test_last_fix_is_a_word_not_a_dash(self):
        desk = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "EyeDesk.swift")
        dead = read("Packages", "DeadReckoning", "Sources", "DeadReckoning", "DeadReckoning.swift")
        self.assertIn('static let lastFix = "LAST FIX"', desk)
        self.assertIn("LAST FIX", dead)
        self.assertIn("capMeters: Double = 200", dead)
        self.assertIn("func hold(", dead)
        chrome = desk.split("func fixChrome")[1].split("func condition")[0]
        self.assertIn("lastFix", chrome)
        self.assertNotIn('return "—"', chrome)
        tests = read(
            "Packages", "MapLibreMap", "Tests", "MapLibreMapTests", "MapLibreMapTests.swift"
        )
        self.assertIn('EyeDesk.fixChrome(ageSeconds: 12, hasFix: false), "LAST FIX"', tests)
        self.assertNotIn('EyeDesk.fixChrome(ageSeconds: 12, hasFix: false), "—"', tests)

    def test_dest_rail_is_green_only_on_live_gnss(self):
        chrome = read("Blackout", "MapTab.swift").split("private var fieldChrome")[1].split(
            "private var hudReserve"
        )[0]
        self.assertIn("runtime.gnssYou", chrome)
        self.assertIn("runtime.fieldYou", chrome)
        self.assertIn("liveFix", chrome)
        rail = chrome.split("struct MapFieldDestRail")[1]
        self.assertIn("liveFix ? Theme.fix : Theme.silver", rail)
        self.assertNotIn("lastKnownFix", chrome)


class PhotoDeskTests(unittest.TestCase):
    def test_schematic_water_lines_hide_on_naip(self):
        covers = (
            read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift")
            .split("func coversPhoto")[1]
            .split("func holdsKhanDetail")[0]
        )
        self.assertIn("water-fill", covers)
        self.assertIn("water-ephemeral", covers)
        self.assertIn('id == "water"', covers)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("Schematic water lines hide on the photo", qa)


class SearchAliasTests(unittest.TestCase):
    def test_tenth_and_calle_are_the_same_street(self):
        self.assertEqual(ordinal_aliases("10th"), {"10", "10th", "tenth"})
        self.assertEqual(ordinal_aliases("tenth"), {"10", "10th", "tenth"})
        self.assertEqual(ordinal_aliases("21st"), {"21", "21st"})
        self.assertEqual(ordinal_aliases("21"), {"21", "21st"})
        self.assertIsNone(ordinal_aliases("montana"))
        search = read("Packages", "Search", "Sources", "Search", "Search.swift")
        self.assertIn('"10th"', search)
        self.assertIn('"tenth"', search)
        aliases = search.split("func aliases(of")[1].split("func exactOrAlias")[0]
        self.assertIn('"calle"', aliases)
        self.assertIn('"camino"', aliases)
        self.assertIn('"northwest"', aliases)
        self.assertIn("func ordinalSet(", search)
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("10th", qa)
        self.assertIn("21st", qa)
        self.assertIn("northwest", qa)


class DeviceScriptTests(unittest.TestCase):
    def test_night_walk_script_names_the_new_moves(self):
        qa = read("docs", "SOLO_QA.md")
        device = read("docs", "DEVICE.md")
        for blob in (qa, device):
            self.assertIn("Walk or Drive the first remaining street", blob)
            self.assertIn("silver line starts at YOU", blob)
            self.assertIn("LAST FIX", blob)
            self.assertIn("45 m", blob)
            self.assertIn("160 m", blob)
            self.assertIn("no ghost progress", blob)
            self.assertNotIn("best in class", blob.lower())
            self.assertNotIn("Waze", blob)
            self.assertNotIn("Google Maps", blob)


if __name__ == "__main__":
    unittest.main()
