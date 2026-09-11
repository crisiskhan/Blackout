#!/usr/bin/env python3
"""FIELD catalog is an offline ask over the shipped book.

Type a situation. Rank the cards that answer it. Invent nothing. Never edible.
FIELD hits scroll — MAP's five-hit cap is a canvas rule, not a book rule.
"""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FROM_NOTHING = (
    "camp-start",
    "water-find",
    "water-catch",
    "fire-spark",
    "shelter-site",
    "sig-ground",
    "camp-latrine",
    "med-gut",
    "med-burn",
    "med-feet",
    "env-flood",
    "env-lightning",
    "env-desert-day",
    "env-crossing",
    "plant-cordage",
    "camp-blade",
    "env-bog",
    "med-infection",
    "camp-watch",
    "env-insect",
)


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


class FieldAskGlassTests(unittest.TestCase):
    def test_corpus_ranks_the_book_and_the_catalog_asks(self):
        corpus = read("Packages", "FieldCorpus", "Sources", "FieldCorpus", "FieldCorpus.swift")
        tab = read("Blackout", "FieldTab.swift")
        self.assertIn("static func ask(", corpus)
        self.assertIn("thirst", corpus)
        self.assertIn("starting", corpus)
        self.assertIn("víbora", corpus)
        self.assertIn("vibora", corpus)
        self.assertIn("forage", corpus)
        self.assertIn("FieldCorpus.ask(", tab)
        self.assertIn('TextField("SEARCH"', tab)
        self.assertIn("textInputAutocapitalization(.never)", tab)
        self.assertIn("NO MATCH", tab)
        self.assertIn("ForEach(listCards)", tab)
        self.assertIn("FieldCorpus.chapter(", tab)
        self.assertNotIn("mapSearchHitCap", tab)
        self.assertNotIn("best in class", tab.lower())
        self.assertNotIn("best in class", corpus.lower())

    def test_ask_does_not_invent_and_does_not_unlock_a_meal(self):
        corpus = read("Packages", "FieldCorpus", "Sources", "FieldCorpus", "FieldCorpus.swift")
        self.assertIn("animal-bite", corpus)
        self.assertIn("water-disinfect", corpus)
        self.assertIn("fungi-leave", corpus)
        self.assertIn("plant-unknown", corpus)
        self.assertIn("camp-start", corpus)
        self.assertNotIn("edible", corpus.lower())
        book = json.loads((ROOT / "Resources/Field/field.core.json").read_text())
        blob = json.dumps(book).lower()
        self.assertNotIn("safe to eat", blob)
        self.assertNotIn("dual survival", blob)
        by_id = {card["id"]: card for card in book["cards"]}
        for cid in FROM_NOTHING:
            self.assertNotIn("edible", json.dumps(by_id[cid]).lower(), cid)

    def test_from_nothing_cards_ship_in_core(self):
        book = json.loads((ROOT / "Resources/Field/field.core.json").read_text())
        ids = {card["id"] for card in book["cards"]}
        for cid in FROM_NOTHING:
            self.assertIn(cid, ids, cid)
        by_id = {card["id"]: card for card in book["cards"]}
        start = json.dumps(by_id["camp-start"]).lower()
        self.assertIn("shade", start)
        self.assertIn("water", start)
        self.assertIn("food is last", start)
        find = json.dumps(by_id["water-find"]).lower()
        self.assertIn("urine", find)
        self.assertIn("seawater", find)
        self.assertNotIn("drink the cactus", find)
        fire = json.dumps(by_id["fire-spark"]).lower()
        self.assertIn("friction", fire)
        self.assertIn("daylight", fire)
        field_py = read("tools", "v3", "field.py")
        self.assertIn("def from_nothing_core", field_py)
        self.assertIn("from_nothing_core()", field_py)

    def test_solo_qa_scores_field_search(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("SEARCH", qa)
        self.assertIn("NO MATCH", qa)
        self.assertIn("starting from nothing", qa.lower())
        self.assertIn("FIELD hits scroll", qa)


if __name__ == "__main__":
    unittest.main()
