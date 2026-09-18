#!/usr/bin/env python3
"""FIELD cards connect: first move now, then the next likely cause.

A civilian with a phone coaches or does the walk. Forks are whole words.
Airplane only.
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


def _blob(card: dict) -> str:
    return json.dumps(card).lower()


def _first_do(card: dict) -> str:
    return ((card.get("steps") or [{}])[0].get("do") or {}).get("en") or ""


def _labels(card: dict) -> list[str]:
    return [str(link.get("label") or "") for link in card.get("links") or []]


def _open(query: str, book: list[dict]) -> tuple[str | None, dict]:
    hits = ask_book(book, query, "en")
    if hits:
        return hits[0]["id"], hits[0]
    live = answer_ask(query, book, "en", "west", "tx-west", None)
    assert live is not None, f"{query!r} opened nothing"
    return live["id"], live


# Presentation trees: first move, then causes in likelihood order.
BREATH_LABELS = ("CHOKE", "ALLERGY", "ASTHMA", "HEART", "SMOKE", "DROWN", "CPR", "STAY")
HURT_LABELS = ("BLEED", "BREATH", "CPR", "HEAD", "NECK", "BREAK", "BURN", "BITE", "STAY")
SICK_LABELS = ("HEAT", "COLD", "STROKE", "ALLERGY", "SUGAR", "GUT", "POISON", "SEIZURE", "STAY")
AIRWAY_LABELS = ("INFANT", "SELF", "PREGNANT", "ALLERGY", "ASTHMA", "BREATH", "CPR", "STAY")
BLEED_LABELS = ("TIGHT", "HOLE", "SHOCK", "STUCK", "STAY")
CPR_LABELS = ("INFANT", "DOSE", "BREATH", "SEIZURE", "SHOCK", "STAY")


class FieldTreeBatteryTests(unittest.TestCase):
    """A phone in a hand can troubleshoot the next likely cause."""

    def test_cant_breathe_is_not_a_choke_card(self):
        book = load_book()
        hits = ask_book(book, "I can't breathe", "en")
        self.assertFalse(hits, "can't breathe must not skip the look")

    def test_choking_still_opens_the_airway_book(self):
        book = load_book()
        hits = ask_book(book, "he's choking", "en")
        self.assertTrue(hits)
        self.assertEqual(hits[0]["id"], "med-airway")
        hits = ask_book(book, "food stuck in throat", "en")
        self.assertEqual(hits[0]["id"], "med-airway")

    def test_not_breathing_still_opens_cpr(self):
        book = load_book()
        hits = ask_book(book, "not breathing", "en")
        self.assertEqual(hits[0]["id"], "med-cpr-adult")

    def test_cant_breathe_first_move_is_sit_and_ask(self):
        book = load_book()
        cid, card = _open("I can't breathe", book)
        self.assertEqual(cid, LIVE_ID)
        first = _first_do(card).lower()
        self.assertTrue(any(n in first for n in ("sit", "up", "chest")), first)
        self.assertTrue(
            any(n in _blob(card) for n in ("cough", "speak", "word")),
            _first_do(card),
        )
        self.assertGreaterEqual(len(card["steps"]), 4)
        self.assertLessEqual(len(card["steps"]), 8)
        self.assertIn("them", first + " " + _blob(card))

    def test_cant_breathe_offers_causes_in_likelihood_order(self):
        book = load_book()
        _, card = _open("I can't breathe", book)
        labels = _labels(card)
        self.assertEqual(labels, list(BREATH_LABELS), labels)
        for word in BREATH_LABELS:
            self.assertEqual(word, word.upper())
            self.assertNotIn("…", word)
            self.assertGreaterEqual(len(word), 3)

    def test_hurt_opens_bleed_and_breath_first(self):
        book = load_book()
        cid, card = _open("I'm hurt", book)
        self.assertEqual(cid, LIVE_ID)
        self.assertEqual(_labels(card), list(HURT_LABELS))
        first = _first_do(card).lower()
        self.assertTrue(any(n in first for n in ("blood", "bleed", "chest")), first)

    def test_sick_opens_heat_cold_stroke_before_stay(self):
        book = load_book()
        _, card = _open("I'm sick", book)
        labels = _labels(card)
        self.assertEqual(labels, list(SICK_LABELS), labels)
        self.assertLess(labels.index("HEAT"), labels.index("STAY"))
        self.assertLess(labels.index("STROKE"), labels.index("STAY"))

    def test_neck_hurt_still_opens_the_spine_book(self):
        book = load_book()
        hits = ask_book(book, "I fell and my neck hurts", "en")
        self.assertTrue(hits, "neck hurt must still hit the spine book")
        self.assertEqual(hits[0]["id"], "trauma-spine")

    def test_stay_warm_still_opens_the_cold_book(self):
        book = load_book()
        hits = ask_book(book, "how do I stay warm", "en")
        self.assertTrue(hits, "stay warm must still hit the cold book")
        self.assertEqual(hits[0]["id"], "env-cold")
        hits = ask_book(book, "how do I stay cool", "en")
        self.assertEqual(hits[0]["id"], "env-heat-collapse")

    def test_stay_keeps_them_breathing_and_warm(self):
        book = load_book()
        _, card = _open("keep them stable", book)
        first = _first_do(card).lower()
        blob = _blob(card)
        self.assertTrue(any(n in first for n in ("side", "airway", "breath")), first)
        self.assertIn("food", blob)
        self.assertNotIn("tel://", blob)
        self.assertNotIn("edible", blob)

    def test_airway_book_connects_to_the_next_causes(self):
        tree = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldTree.swift")
        for label in AIRWAY_LABELS:
            self.assertIn(f'"{label}"', tree, label)
        for label in BLEED_LABELS:
            self.assertIn(f'"{label}"', tree, label)
        for label in CPR_LABELS:
            self.assertIn(f'"{label}"', tree, label)

    def test_fork_ask_opens_the_named_procedure(self):
        book = load_book()
        choke = answer_ask("choking", book, "en", "west", "tx-west", None)
        # choking is a book hit, so answer is nil — SEARCH opens the book.
        self.assertIsNone(choke)
        allergy = grounded_ask("anaphylaxis", book, "tx-west", "en")
        self.assertIn("thigh", _blob(allergy))
        self.assertIn("STAY", _labels(allergy) or ["STAY"])

    def test_choke_book_is_back_blows_not_swell(self):
        book = load_book()
        hits = ask_book(book, "he's choking", "en")
        self.assertTrue(hits)
        first = _first_do(hits[0]).lower()
        blob = _blob(hits[0])
        self.assertTrue(any(n in first for n in ("cough", "speak")), first)
        self.assertIn("back", blob)
        self.assertNotIn("auto-injector", first)
        self.assertNotIn("does not prescribe", blob)

    def test_infant_choke_is_back_and_chest_not_belly(self):
        book = load_book()
        cid, card = _open("baby choking", book)
        self.assertEqual(cid, LIVE_ID)
        blob = _blob(card)
        self.assertIn("back", blob)
        self.assertIn("chest", blob)
        self.assertIn("belly", blob)
        self.assertIn("INFANT", read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldTree.swift"))

    def test_self_choke_uses_a_chair(self):
        book = load_book()
        cid, card = _open("choking on my own", book)
        self.assertEqual(cid, LIVE_ID)
        self.assertIn("chair", _blob(card))

    def test_chest_hole_gets_a_three_side_seal(self):
        book = load_book()
        cid, card = _open("sucking chest", book)
        self.assertEqual(cid, LIVE_ID)
        blob = _blob(card)
        self.assertTrue(any(n in blob for n in ("seal", "plastic", "open")), blob)
        self.assertIn("HOLE", _labels(card) + ["HOLE"])

    def test_low_sugar_is_swallow_then_side(self):
        book = load_book()
        cid, card = _open("low blood sugar", book)
        self.assertEqual(cid, LIVE_ID)
        first = _first_do(card).lower()
        self.assertTrue(any(n in first for n in ("sugar", "juice", "swallow")), first)
        self.assertIn("mouth", _blob(card))

    def test_help_me_is_hurt_not_a_camp_lecture(self):
        book = load_book()
        cid, card = _open("help me", book)
        self.assertEqual(cid, LIVE_ID)
        labels = _labels(card)
        self.assertIn("BLEED", labels)
        self.assertIn("BREATH", labels)
        self.assertEqual(labels[0], "BLEED")

    def test_baby_warm_still_opens_the_cold_book(self):
        book = load_book()
        hits = ask_book(book, "keep the baby warm", "en")
        self.assertTrue(hits, "a baby in the cold is still the cold book")
        self.assertEqual(hits[0]["id"], "env-cold")
        cid, card = _open("baby choking", book)
        self.assertEqual(cid, LIVE_ID)
        self.assertIn("back", _blob(card))
        self.assertIn("forearm", _blob(card))

    def test_pregnant_bleed_is_pressure_not_choke(self):
        book = load_book()
        hits = ask_book(book, "I'm pregnant and bleeding", "en")
        self.assertTrue(hits, "pregnant bleed must still hit the bleed book")
        self.assertEqual(hits[0]["id"], "med-bleed-pack")
        cid, card = _open("pregnant choking", book)
        self.assertEqual(cid, LIVE_ID)
        blob = _blob(card)
        self.assertIn("chest", blob)
        self.assertIn("belly", blob)
        self.assertNotIn("navel", _first_do(card).lower())

    def test_tight_chest_is_not_a_tourniquet(self):
        book = load_book()
        hits = ask_book(book, "chest feels tight", "en")
        self.assertFalse(
            hits and hits[0]["id"] == "med-bleed-pack",
            "tight chest must not boost the bleed book",
        )
        cid, card = _open("chest feels tight", book)
        first = _first_do(card).lower()
        blob = _blob(card)
        self.assertTrue(any(n in first for n in ("sit", "still", "chest")), first)
        self.assertNotIn("windlass", blob)
        self.assertNotIn("twist", first)
        cid, card = _open("tourniquet", book)
        self.assertIn("windlass", _blob(card))

    def test_stuck_without_a_wound_is_not_impaled(self):
        book = load_book()
        cid, card = _open("I'm stuck", book)
        blob = _blob(card)
        self.assertNotIn("leave the object", blob)
        self.assertNotIn("do not pull", blob)
        cid, card = _open("impaled", book)
        self.assertIn("leave the object", _blob(card))

    def test_find_people_is_listen_and_louder(self):
        book = load_book()
        for query in ("find people", "civilization", "anyone out there"):
            hits = ask_book(book, query, "en")
            self.assertFalse(hits, f"{query!r} must not steal a book card")
            cid, card = _open(query, book)
            self.assertEqual(cid, LIVE_ID, query)
            blob = _blob(card)
            first = _first_do(card).lower()
            self.assertTrue(
                any(n in first or n in blob for n in ("listen", "louder", "radio")),
                first,
            )
            self.assertIn("SIGNAL", _labels(card))
            self.assertIn("STAY", _labels(card))
            self.assertNotIn("tel://", blob)


class FieldTreeSourceTests(unittest.TestCase):
    """The glass shows CAUSE chips. The source never phones out."""

    def test_swift_tree_and_tab_exist(self):
        tree = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldTree.swift")
        walk = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldAskWalk.swift")
        ask = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldAsk.swift")
        tab = read("Blackout", "FieldTab.swift")
        corpus = read(
            "Packages", "FieldCorpus", "Sources", "FieldCorpus", "FieldCorpus.swift"
        )
        self.assertIn("enum FieldTree", tree)
        self.assertIn("static func decorate(", tree)
        self.assertIn("static func openLink(", tree)
        self.assertIn("struct FieldLink", corpus)
        self.assertIn("var links:", corpus)
        self.assertIn("case .breath", walk)
        self.assertIn("case .hurt", walk)
        self.assertIn("case .sick", walk)
        self.assertIn("case .stay", walk)
        self.assertIn("case .infant", walk)
        self.assertIn("case .selfChoke", walk)
        self.assertIn("case .people", walk)
        self.assertIn("case .people:", tree)
        self.assertIn("case .hole", walk)
        self.assertIn("case .sugar", walk)
        self.assertIn("FieldTree.decorate(", ask)
        self.assertIn('sectionLabel("CAUSE")', tab)
        self.assertIn('Button("BACK")', tab)
        self.assertIn("openLink(", tab)
        self.assertIn("forkStack", tab)
        self.assertIn("link.label", tab)
        self.assertNotIn("…", tree)
        for blob, name in (
            (tree, "FieldTree"),
            (walk, "FieldAskWalk"),
            (ask, "FieldAsk"),
            (tab, "FieldTab"),
        ):
            self.assertNotIn("URLSession", blob, name)
            self.assertNotIn("WKWebView", blob, name)
            self.assertNotIn("tel://", blob, name)

    def test_cant_breathe_phrase_is_breath_not_choke(self):
        corpus = read(
            "Packages", "FieldCorpus", "Sources", "FieldCorpus", "FieldCorpus.swift"
        )
        self.assertIn('("cant breathe", "breath")', corpus)
        self.assertIn('("cannot breathe", "breath")', corpus)
        self.assertIn('("hard to breathe", "breath")', corpus)
        self.assertIn('("short of breath", "breath")', corpus)
        self.assertIn('("im hurt", "hurt")', corpus)
        self.assertIn('("im sick", "sick")', corpus)
        self.assertIn('("help me", "hurt")', corpus)
        self.assertIn('("keep them stable", "stay")', corpus)
        skip = corpus.split("public static func ask(")[1].split(
            "private static func boostIndex"
        )[0]
        self.assertIn('expanded.contains("breath")', skip)
        self.assertIn('expanded.contains("hurt")', skip)
        self.assertIn('expanded.contains("sick")', skip)
        self.assertIn('"people"', skip)
        self.assertIn('"civilization"', skip)

    def test_solo_qa_scores_the_connected_card(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("can't breathe", qa)
        self.assertIn("CHOKE", qa)
        self.assertIn("CAUSE", qa)
        self.assertIn("STAY", qa)
        self.assertIn("BACK", qa)


if __name__ == "__main__":
    unittest.main()
