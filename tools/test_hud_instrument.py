#!/usr/bin/env python3
"""HUD instrument — Linux stand-in for the five glass surfaces.

WALK/DRIVE keep the maneuver up. FIELD is one move. COMMS is the radio.
Hold cards show the thing. SEARCH and VISION classify the ask.
"""
from __future__ import annotations

import math
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


METERS_PER_MILE = 1609.344
FEET_PER_METER = 3.280839895


def haversine(a: float, b: float, c: float, d: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(a), math.radians(c)
    dp, dl = math.radians(c - a), math.radians(d - b)
    x = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(x)))


def remaining_meters(coords: list[tuple[float, float]]) -> float:
    """Mirror of VoiceNav.remainingMeters."""
    total = 0.0
    for a, b in zip(coords, coords[1:]):
        total += haversine(a[0], a[1], b[0], b[1])
    return total


def remaining_hud(coords: list[tuple[float, float]]) -> str:
    """Mirror of VoiceNav.remainingHUD / BlackoutTokens.Distance.hud."""
    if len(coords) < 2:
        return ""
    meters = remaining_meters(coords)
    if meters >= METERS_PER_MILE:
        return f"{meters / METERS_PER_MILE:.1f} MI"
    return f"{round(round(meters) * FEET_PER_METER):.0f} FT"


def dest_field(
    dest: tuple[float, float] | None,
    you: tuple[float, float] | None,
    navigating: bool,
) -> tuple[float, float] | None:
    """Mirror of MapFieldChrome.destField. YOU when idle, dest while navigating."""
    if navigating:
        return dest
    return you if you is not None else dest


def maneuver_live(has_destination: bool, has_route: bool) -> bool:
    """Mirror of MapFieldChrome.maneuverLive."""
    return has_destination and has_route


def chrome_sleep_blocked(
    crisis: bool,
    incoming: bool,
    arranging: bool,
    holding: bool,
    maneuver: bool,
) -> bool:
    """Mirror of HUDPulse.sleepBlocked."""
    return crisis or incoming or arranging or holding or maneuver


class ManeuverHUDTests(unittest.TestCase):
    def test_dest_field_is_you_when_idle_and_dest_while_navigating(self):
        dest = (31.75800, -106.48700)
        you = (31.76190, -106.49000)
        self.assertEqual(dest_field(dest, you, False), you)
        self.assertEqual(dest_field(dest, you, True), dest)
        self.assertEqual(dest_field(dest, None, False), dest)
        self.assertIsNone(dest_field(None, None, False))

    def test_remaining_shrinks_along_the_line(self):
        start = (31.76190, -106.49000)
        mid = (31.76300, -106.49000)
        end = (31.76400, -106.49000)
        full = remaining_hud([start, mid, end])
        half = remaining_hud([mid, end])
        self.assertTrue(full.endswith("FT") or full.endswith("MI"), full)
        self.assertTrue(half.endswith("FT") or half.endswith("MI"), half)
        self.assertGreater(remaining_meters([start, mid, end]), remaining_meters([mid, end]))
        self.assertEqual(remaining_hud([start]), "")

    def test_maneuver_is_dest_plus_a_drawn_line(self):
        self.assertTrue(maneuver_live(True, True))
        self.assertFalse(maneuver_live(True, False))
        self.assertFalse(maneuver_live(False, True))
        self.assertFalse(maneuver_live(False, False))

    def test_live_walk_keeps_chrome_awake(self):
        self.assertTrue(chrome_sleep_blocked(False, False, False, False, True))
        self.assertTrue(chrome_sleep_blocked(True, False, False, False, False))
        self.assertTrue(chrome_sleep_blocked(False, True, False, False, False))
        self.assertFalse(chrome_sleep_blocked(False, False, False, False, False))

    def test_dest_rail_owns_the_maneuver_and_captions_coords(self):
        voice = read("Packages", "Router", "Sources", "Router", "VoiceNav.swift")
        route = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift")
        tab = read("Blackout", "MapTab.swift")
        pulse = read("Blackout", "HUDLayout.swift")
        app = read("Blackout", "AppRuntime.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("func remainingMeters(", voice)
        self.assertIn("func remainingHUD(", voice)
        self.assertIn("func maneuverLive(", route)
        self.assertIn("hasDestination && hasRoute", route)
        chrome = tab.split("private var fieldChrome")[1].split("private var hudReserve")[0]
        rail = chrome.split("struct MapFieldDestRail")[1]
        self.assertIn("remaining", rail)
        self.assertIn("navigating", rail)
        self.assertIn("MapFieldChrome.liveRemainingHUD", chrome)
        self.assertIn("MapFieldChrome.destField", chrome)
        self.assertIn("func destField(", route)
        self.assertIn("func liveRemainingHUD(", route)
        self.assertNotIn("VoiceNav.remainingHUD(runtime.routeCoords)", chrome)
        self.assertIn("MapFieldChrome.maneuverLive", chrome)
        self.assertNotIn("dest ?? you", chrome)
        self.assertIn("Theme.fix", rail)
        self.assertIn("chip(MapFieldDestMode.turns)", rail)
        self.assertNotIn("chip(MapFieldDestMode.coordinates)", rail)
        self.assertNotIn("Walk … Turn … Arrive", rail)
        self.assertNotIn("Turn left onto", rail)
        self.assertIn("func sleepBlocked(", pulse)
        sleep = app.split("func scheduleChromeSleep")[1].split("func resetHUD")[0]
        self.assertIn("HUDPulse.sleepBlocked", sleep)
        self.assertIn("maneuverLive", sleep)
        self.assertIn("remaining distance own the field", qa)
        self.assertIn("does not fade until arrival or OFF GRAPH", qa)
        self.assertNotIn("best in class", qa.lower())

    def test_speak_still_does_not_paint_the_script(self):
        tab = read("Blackout", "MapTab.swift")
        card = read("Blackout", "SpeakTurnCard.swift")
        self.assertIn("SpeakTurnCard(", tab)
        self.assertNotIn("Turn left onto", tab)
        self.assertNotIn("Arrive at destination.", tab)
        self.assertNotIn("Turn left onto", card)
        self.assertIn("prefix(2)", card)


class FieldOneMoveTests(unittest.TestCase):
    def test_walk_is_the_move_and_care_holds_why_stop(self):
        field = read("Blackout", "FieldTab.swift")
        qa = read("docs", "SOLO_QA.md")
        walk = field.split("private func walkPlate")[1].split("private func carePlate")[0]
        care = field.split("private func carePlate")[1].split("private func sectionLabel")[0]
        open_fn = field.split("private func open(")[1].split("private func sectionLabel")[0]
        self.assertIn("s.step.image", walk)
        self.assertIn("FieldCorpus.doLines", walk)
        self.assertIn("s.step.child", walk)
        self.assertIn("tickSeconds", walk)
        self.assertIn("metronomeBpm", walk)
        self.assertNotIn("s.step.why", walk)
        self.assertNotIn("s.step.stop", walk)
        self.assertNotIn('L10n.t("stop.if"', walk)
        self.assertNotIn('sectionLabel("SITUATION")', walk)
        self.assertIn("s.step.why", care)
        self.assertIn("s.step.stop", care)
        self.assertIn('L10n.t("stop.if"', care)
        self.assertIn('sectionLabel("GET-TO-CARE")', care)
        self.assertIn('L10n.t("field.send"', care)
        self.assertIn('Button("SPEAK")', open_fn)
        self.assertIn("stepTitle(s)", open_fn)
        self.assertLess(open_fn.find("walkPlate"), open_fn.find('Button("SPEAK")'))
        self.assertGreater(open_fn.find('Button("SPEAK")'), open_fn.find("ScrollView"))
        self.assertRegex(walk, r"maxHeight:\s*2[0-9]\d")
        self.assertNotIn("visionHUD", open_fn)
        self.assertIn("picture fills the plate", qa)
        self.assertIn("NEXT and SPEAK stay pinned", qa)
        self.assertIn("STOP-IF live on CARE", qa)

    def test_vision_keeps_the_still_on_search(self):
        field = read("Blackout", "FieldTab.swift")
        session = read("Blackout", "FieldSession.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("var stillJPEG", session)
        self.assertIn("stillJPEG = nil", session)
        self.assertIn("stillJPEG", field)
        vision = field.split("private var visionHUD")[1].split("private func visionFieldButton")[0]
        self.assertIn("Image(uiImage:", vision)
        self.assertIn("g.name", vision)
        self.assertIn('L10n.t("vision.leave"', vision)
        self.assertIn("VISION keeps the still", qa)
        self.assertNotIn("g.percent", vision)


class CommsRadioTests(unittest.TestCase):
    def test_radio_is_the_face_and_party_holds_the_code(self):
        comms = read("Blackout", "CommsTab.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("enum CommsPlate", comms)
        self.assertIn("case radio, party", comms)
        self.assertIn('case .radio: return "RADIO"', comms)
        self.assertIn('case .party: return "PARTY"', comms)
        self.assertIn("plate: CommsPlate = .radio", comms)
        self.assertIn("pendingNoteFocus { plate = .party }", comms)
        self.assertNotIn("case net, call, note, chips", comms)
        self.assertNotIn("case .net", comms)
        radio = comms.split("private var radioPlate")[1].split("private var partyPlate")[0]
        party = comms.split("private var partyPlate")[1].split("private var pageStatus")[0]
        self.assertIn("pttPad", radio)
        self.assertIn("HOLD PTT", comms)
        self.assertIn("LISTEN", radio)
        self.assertIn('Button("SCAN")', radio)
        self.assertIn("JOIN LOCAL NET", radio)
        self.assertIn("ForEach(Chip.rail", radio)
        self.assertIn("log", radio)
        self.assertIn("15s CLIP", radio)
        self.assertIn('Button("PLAY")', radio)
        self.assertIn("RADIO CHECK", radio)
        self.assertIn("partyCard", party)
        self.assertIn("PARTY CODE", comms)
        self.assertIn("PartyQRImage", comms)
        self.assertIn('HUDField("NOTE"', party)
        self.assertNotIn("HOLD PTT", party)
        self.assertIn("RADIO is PTT", qa)
        self.assertIn("PARTY is the code, QR, and NOTE", qa)
        self.assertNotIn("Whisper <10 m", comms)


class HoldThingFirstTests(unittest.TestCase):
    def test_ground_do_is_the_card(self):
        hold = read("Blackout", "HoldCard.swift")
        qa = read("docs", "SOLO_QA.md")
        ground = hold.split("struct HoldCardView")[1]
        self.assertIn("held.card.doLine", ground)
        self.assertLess(ground.find("held.card.doLine"), ground.find('"SURE"'))
        self.assertLess(ground.find("actions"), ground.find("ScrollView"))
        self.assertIn("Ground DO is the card", qa)

    def test_camera_still_is_the_card(self):
        cam = read("Blackout", "CamHoldCard.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertLess(cam.find("stillWell"), cam.find("actions"))
        self.assertLess(cam.find("stillWell"), cam.find("private var rows"))
        self.assertIn("TAP UPDATE", cam)
        self.assertIn("Camera still is the card", qa)

    def test_party_face_and_condition_beat_the_ledger(self):
        party = read("Blackout", "PartyHoldCard.swift")
        qa = read("docs", "SOLO_QA.md")
        body = party.split("var body:")[1].split("private var headline")[0]
        self.assertLess(body.find("statusRail"), body.find("timerBlock"))
        self.assertLess(body.find("conditionBlock"), body.find("inventoryBlock"))
        self.assertLess(body.find("conditionBlock"), body.find("rows"))
        self.assertIn('Button("CALL")', party)
        self.assertIn('Button("MESSAGE")', party)
        self.assertLess(party.find("actions"), party.find("ScrollView"))
        self.assertIn("bearing and inventory scroll", qa)


class AuditChainTests(unittest.TestCase):
    def test_instrument_guards_are_in_the_chain(self):
        agents = read("AGENTS.md")
        validate = read("tools", "validate_v3.py")
        self.assertIn("test_hud_instrument.py", agents)
        self.assertIn("hud_instrument()", validate)
        self.assertIn("test_hud_instrument.py", validate)


class SearchHitInstrumentTests(unittest.TestCase):
    def test_hits_are_name_kind_chip_and_gnss_range(self):
        tab = read("Blackout", "MapTab.swift")
        qa = read("docs", "SOLO_QA.md")
        hits = tab.split("private var hitList")[1].split("private var markList")[0]
        self.assertIn("SearchHUDWord.from", hits)
        self.assertIn("SearchIndex.rangeLabel", hits)
        self.assertIn("Theme.fix", hits)
        self.assertNotIn('joined(separator: " · ")', hits)
        self.assertIn("mapSearchHitCap", hits)
        self.assertIn("Kind is a metal chip", qa)
        self.assertIn("Range is GNSS green", qa)
        self.assertIn("Hits cap at five", qa)


if __name__ == "__main__":
    unittest.main()
