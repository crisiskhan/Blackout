#!/usr/bin/env python3
"""FIELD SEARCH / ASK answers any survival question offline.

Book hits stay the packed card. A miss still opens a timely first-time walk.
Vision stills open the same procedures. The glass never phones out.
"""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

from test_field_ask import (  # noqa: E402
    LIVE_ID,
    answer_ask,
    ask_book,
    grounded_ask,
    load_book,
    read,
)


# First answering card for a situation a field medic would type or say.
# A wrong card here is worse than a miss — panic breathing is not a heart attack.
BOOK = (
    ("thirst", "water-disinfect"),
    ("snake", "animal-bite"),
    ("starting from nothing", "camp-start"),
    ("wildfire", "env-wildfire"),
    ("seep", "water-seep"),
    ("wool", "camp-layers"),
    ("where am I", "nav-lost"),
    ("got bit", "animal-bite"),
    ("not breathing", "med-cpr-adult"),
    ("can't walk", "trauma-carry"),
    ("stung", "animal-bite"),
    ("I'm burned", "med-burn"),
    ("can I eat this", "plant-unknown"),
    ("heat stroke", "env-heat-collapse"),
    ("too hot", "env-heat-collapse"),
    ("hypothermia", "env-cold"),
    ("soaking wet", "env-cold"),
    ("I'm freezing", "env-cold"),
    ("how do I stay warm", "env-cold"),
    ("how do I stay cool", "env-heat-collapse"),
    ("flash flood", "env-flood"),
    ("lightning close", "env-lightning"),
    ("how do I make a fire", "fire-stove"),
    ("we need shelter", "shelter-tarp"),
    ("how do I signal for help", "sig-mirror"),
    ("how do I get rescued", "sig-mirror"),
    ("purify water", "water-disinfect"),
    ("find water", "water-find"),
    ("can I drink this", "water-disinfect"),
    ("frostbite", "env-frostbite"),
    ("can't feel my fingers", "env-frostbite"),
    ("altitude sickness", "env-altitude"),
    ("diarrhea", "med-gut"),
    ("blister", "med-feet"),
    ("infection", "med-infection"),
    ("tick bite", "env-insect"),
    ("alligator", "animal-gator"),
    ("bear encounter", "nm-mammal"),
    ("mountain lion", "nm-mammal"),
    ("javelina", "tx-mammal"),
    ("hog", "tx-east-mammal"),
    ("deer", "tx-mammal"),
    ("snow blindness", "med-glare"),
    ("hurricane", "tx-hurricane-paper"),
    ("crossing a river", "env-crossing"),
    ("someone collapsed", "med-cpr-adult"),
    ("passed out", "med-cpr-adult"),
    ("bleeding out", "med-bleed-pack"),
    ("he's choking", "med-airway"),
    ("food stuck in throat", "med-airway"),
    ("broken leg", "trauma-fracture"),
    ("I fell and my neck hurts", "trauma-spine"),
    ("smoke inhalation", "env-smoke"),
    ("got stung by a scorpion", "animal-bite"),
    ("I'm lost", "nav-lost"),
    ("starting a fire in the rain", "fire-wet"),
    ("where should I camp", "shelter-site"),
    ("wildfire coming", "env-wildfire"),
    ("mushroom", "fungi-leave"),
    ("berries", "plant-unknown"),
)

# These used to open the wrong procedure. They must never come back.
NEVER_FIRST = (
    ("heart attack", "tact-breathe"),
    ("chest pain", "tact-breathe"),
    ("how do I stay warm", "tact-staygo"),
    ("how do I stay cool", "tact-staygo"),
    ("how do I get rescued", "env-wind"),
    ("tick bite", "animal-bite"),
    ("they are in shock", "med-airway"),
    ("something in my eye", "med-glare"),
    ("allergic reaction", "med-airway"),
    ("anaphylaxis", "med-airway"),
    ("stroke", "med-cpr-adult"),
    ("swallowed bleach", "water-disinfect"),
    ("hit my head", "med-bleed-pack"),
    ("deer", None),  # a miss is fine; a meal is not. first must not be food.
)

# Book miss still has to be a timely walk, not "do one first move for xyzzy".
LIVE_FIRST = (
    ("heart attack", ("sit", "still", "loosen", "collar", "rest")),
    ("chest pain", ("sit", "still", "loosen", "collar", "rest")),
    ("drowning", ("land", "shore", "out of the water", "throw", "reach")),
    ("seizure", ("clear", "mouth", "side", "hold them")),
    ("they are in shock", ("down", "warm", "press", "legs")),
    ("nosebleed", ("forward", "pinch", "nose", "sit")),
    ("tornado", ("low", "ditch", "head", "tree")),
    ("something in my eye", ("rub", "rinse", "water")),
    ("anaphylaxis", ("thigh", "injector", "lie")),
    ("allergic reaction", ("thigh", "injector", "walk")),
    ("stroke", ("sit", "time", "food", "drink")),
    ("swallowed bleach", ("vomit", "milk", "bottle", "rinse")),
    ("rip current", ("parallel", "float", "against")),
    ("avalanche", ("mark", "face", "dig")),
    ("asthma", ("sit", "inhaler", "flat")),
    ("hit my head", ("neck", "vomit", "roll")),
    ("help me", ("blood", "bleed", "chest")),
    ("I can't breathe", ("sit", "cough", "speak")),
    ("I'm hurt", ("blood", "bleed", "chest")),
    ("I'm sick", ("shade", "sense", "hurt")),
    ("keep them stable", ("side", "breath", "food")),
    ("baby choking", ("back", "chest", "belly")),
    ("choking on my own", ("chair", "fist", "navel")),
    ("sucking chest", ("seal", "plastic", "open")),
    ("low blood sugar", ("sugar", "swallow", "juice")),
    ("overdose", ("naloxone", "side", "kit")),
    ("find people", ("listen", "louder", "radio")),
    ("civilization", ("listen", "louder", "radio")),
    ("anyone out there", ("listen", "louder", "radio")),
)


def _blob(card: dict) -> str:
    return json.dumps(card).lower()


def _first_do(card: dict) -> str:
    return ((card.get("steps") or [{}])[0].get("do") or {}).get("en") or ""


def _open(query: str, book: list[dict]) -> tuple[str | None, dict]:
    """What FIELD SEARCH opens: the book card, or the live walk."""
    hits = ask_book(book, query, "en")
    if hits:
        return hits[0]["id"], hits[0]
    live = answer_ask(query, book, "en", "west", "tx-west", None)
    assert live is not None, f"{query!r} opened nothing"
    return live["id"], live


class SurvivalAskBatteryTests(unittest.TestCase):
    """A child in the field can type any of these and get the right first move."""

    def test_book_opens_the_procedure_that_answers_the_ask(self):
        book = load_book()
        for query, expect in BOOK:
            hits = ask_book(book, query, "en")
            self.assertTrue(hits, f"{query!r} missed the book")
            self.assertEqual(hits[0]["id"], expect, query)

    def test_wrong_cards_never_win(self):
        book = load_book()
        for query, banned in NEVER_FIRST:
            hits = ask_book(book, query, "en")
            first = hits[0]["id"] if hits else None
            if banned is None:
                if first:
                    self.assertNotEqual(
                        book_by_id(book, first).get("category"),
                        "food",
                        f"{query!r} opened a meal",
                    )
                continue
            self.assertNotEqual(first, banned, f"{query!r} opened {banned}")

    def test_live_walks_are_timely_and_honest(self):
        book = load_book()
        for query, needles in LIVE_FIRST:
            cid, card = _open(query, book)
            if cid != LIVE_ID and query in {row[0] for row in BOOK}:
                continue
            self.assertEqual(cid, LIVE_ID, query)
            self.assertGreaterEqual(len(card["steps"]), 4, query)
            self.assertLessEqual(len(card["steps"]), 8, query)
            first = _first_do(card).lower()
            self.assertTrue(
                any(n in first or n in _blob(card) for n in needles),
                f"{query!r} first move {first!r} missed {needles}",
            )
            self.assertNotIn("do one first move for this ask", first)
            self.assertNotIn("edible", _blob(card))
            self.assertNotIn("tel://", _blob(card))
            self.assertNotIn("drinkable", _blob(card))
            self.assertFalse(card["sendToParty"])
            for step in card["steps"]:
                self.assertTrue(step["child"]["en"].strip(), query)
                self.assertTrue(step["do"]["en"].strip(), query)

    def test_cardiac_is_not_panic_breathing(self):
        book = load_book()
        for query in ("heart attack", "chest pain", "dolor de pecho"):
            cid, card = _open(query, book)
            blob = _blob(card)
            self.assertNotEqual(cid, "tact-breathe", query)
            self.assertNotIn("three slow breaths", blob)
            self.assertTrue(
                "sit" in blob and ("compress" in blob or "collapse" in blob or "still" in blob),
                query,
            )

    def test_drowning_gets_them_out_before_compressions(self):
        walk = grounded_ask("someone is drowning", load_book(), "tx-west", "en")
        first = _first_do(walk).lower()
        self.assertTrue(
            any(n in first for n in ("land", "shore", "out of the water", "throw", "reach")),
            first,
        )
        self.assertIn("compression", _blob(walk))

    def test_every_ask_opens_a_walk(self):
        book = load_book()
        for query, _ in BOOK + LIVE_FIRST:
            cid, card = _open(query, book)
            self.assertTrue(card["steps"], query)
            self.assertTrue(cid)

    def test_airplane_ask_never_phones_out(self):
        ask = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldAsk.swift")
        walk = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldAskWalk.swift")
        llama = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldAskLlama.swift")
        vis = read("Packages", "VisionCoreML", "Sources", "VisionCoreML", "VisionCoreML.swift")
        tab = read("Blackout", "FieldTab.swift")
        for blob, name in (
            (ask, "FieldAsk"),
            (walk, "FieldAskWalk"),
            (llama, "FieldAskLlama"),
            (vis, "VisionCoreML"),
            (tab, "FieldTab"),
        ):
            self.assertNotIn("URLSession", blob, name)
            self.assertNotIn("WKWebView", blob, name)
            self.assertNotIn("tel://", blob, name)


def book_by_id(book: list[dict], cid: str) -> dict:
    for card in book:
        if card["id"] == cid:
            return card
    return {}


class SurvivalAskSourceTests(unittest.TestCase):
    """The Swift walk library and the vision stills stay on the same book."""

    def test_swift_has_the_timely_families(self):
        walk = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldAskWalk.swift")
        ask = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldAsk.swift")
        self.assertIn("enum FieldAskWalk", walk)
        self.assertIn("static func build(", walk)
        self.assertIn("FieldAskWalk.build(", ask)
        for name in (
            "cardiac",
            "drown",
            "shock",
            "seizure",
            "nose",
            "tornado",
            "eye",
            "heat",
            "cold",
            "flood",
            "lightning",
            "allergy",
            "stroke",
            "poison",
            "asthma",
            "avalanche",
            "rip",
            "breath",
            "hurt",
            "sick",
            "stay",
        ):
            self.assertIn(name, walk, name)

    def test_corpus_maps_spoken_survival_talk(self):
        corpus = read("Packages", "FieldCorpus", "Sources", "FieldCorpus", "FieldCorpus.swift")
        self.assertIn('("heart attack", "cardiac")', corpus)
        self.assertIn('("chest pain", "cardiac")', corpus)
        self.assertIn('("stay warm", "cold")', corpus)
        self.assertIn('("stay cool", "heat")', corpus)
        self.assertIn('("im freezing", "cold")', corpus)
        self.assertIn('("get rescued", "signal")', corpus)
        self.assertIn('("drowning", "drown")', corpus)
        self.assertIn('("in shock", "shock")', corpus)
        self.assertIn('("seizure", "seizure")', corpus)
        self.assertIn('("snow blindness", "glare")', corpus)
        self.assertIn('("nosebleed", "nose")', corpus)
        self.assertIn('("tornado", "tornado")', corpus)
        self.assertIn('("allergic", "allergy")', corpus)
        self.assertIn('("anaphylaxis", "allergy")', corpus)
        self.assertIn('("stroke", "stroke")', corpus)
        self.assertIn('("rip current", "rip")', corpus)
        self.assertIn('"they"', corpus)
        self.assertIn('"cardiac"', corpus)
        boost = corpus.split("private static let boost")[1].split("public enum FieldError")[0]
        heart = boost[boost.find('"heart"'): boost.find('"heart"') + 80]
        self.assertNotIn("tact-breathe", heart)

    def test_vision_stills_open_survival_cards(self):
        vis = read("Packages", "VisionCoreML", "Sources", "VisionCoreML", "VisionCoreML.swift")
        field = read("Packages", "MapLibreMap", "Sources", "MapLibreMap", "WaterInspect.swift")
        tab = read("Blackout", "FieldTab.swift")
        qa = read("docs", "SOLO_QA.md")
        for kind in ("fire", "flood", "ice", "smoke", "lightning", "shelter", "wound"):
            self.assertIn(f"kind:{kind}", vis, kind)
            self.assertIn(f"case .{kind}", field, kind)
        self.assertIn("env-wildfire", field)
        self.assertIn("env-flood", field)
        self.assertIn("env-lightning", field)
        self.assertIn("env-smoke", field)
        self.assertIn("med-bleed-pack", field)
        self.assertIn("shelter-tarp", field)
        self.assertIn("env-cold", field)
        self.assertIn("InspectField.fieldRoute(", tab)
        self.assertIn("FIELD · FIRE", qa)
        self.assertIn("FIELD · FLOOD", qa)
        self.assertIn("UNKNOWN and `NO VISION MODEL` do not invent a card", qa)
        self.assertNotIn("URLSession", vis)
        self.assertIn("onDeviceModelPresent = false", vis)

    def test_status_ring_keeps_current_size(self):
        emblem = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "PersonEmblem.swift"
        )
        offline = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "OfflineMapView.swift"
        )
        self.assertIn("static let statusRingPoints: Double = 3", emblem)
        mark = offline.split("static func mark(")[1].split("static func pin(")[0]
        self.assertIn("PersonCompass.statusRingPoints", mark)
        self.assertIn("strokeEllipse", mark)


if __name__ == "__main__":
    unittest.main()
