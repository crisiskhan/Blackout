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
    "camp-five",
    "env-core-temp",
    "water-vessel",
    "shelter-insulate",
    "nav-sun",
    "water-seep",
    "fire-wet",
    "fire-char",
    "fire-reflector",
    "shelter-platform",
    "env-wildfire",
    "env-smoke",
    "env-altitude",
    "env-coast",
    "env-frostbite",
    "env-scree",
    "env-wind",
    "env-night-move",
    "trauma-carry",
    "water-rockboil",
    "camp-sweat",
    "med-glare",
    "animal-gator",
    "water-urban",
    "camp-layers",
    "camp-tape",
    "shelter-knots",
    "nav-pace",
    "camp-pack",
    "env-sky",
    "tact-breathe",
    "camp-sleep",
    "camp-light",
    "med-booze",
    "camp-rest-step",
    "food-pantry",
    "nav-compass",
    "fire-bow",
    "water-salt",
    "tact-staygo",
)


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


class FieldAskGlassTests(unittest.TestCase):
    def test_corpus_ranks_the_book_and_the_catalog_asks(self):
        corpus = read("Packages", "FieldCorpus", "Sources", "FieldCorpus", "FieldCorpus.swift")
        tab = read("Blackout", "FieldTab.swift")
        self.assertIn("static func ask(", corpus)
        self.assertIn("static func asking(", corpus)
        self.assertIn("thirst", corpus)
        self.assertIn("starting", corpus)
        self.assertIn("víbora", corpus)
        self.assertIn("vibora", corpus)
        self.assertIn("forage", corpus)
        self.assertIn("FieldCorpus.ask(", tab)
        self.assertIn("FieldCorpus.asking(", tab)
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
        self.assertIn("wool", corpus)
        self.assertIn("camp-layers", corpus)
        self.assertIn("tact-breathe", corpus)
        self.assertIn("food-pantry", corpus)
        book = json.loads((ROOT / "Resources/Field/field.core.json").read_text())
        blob = json.dumps(book).lower()
        self.assertNotIn("safe to eat", blob)
        self.assertNotIn("dual survival", blob)
        self.assertNotIn("lundin", blob)
        self.assertNotIn("canterbury", blob)
        self.assertNotIn("graham", blob)
        self.assertNotIn("bushcraft 101", blob)
        self.assertNotIn("98.6", json.dumps(book))
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
        five = json.dumps(by_id["camp-five"]).lower()
        self.assertIn("cutting", five)
        self.assertIn("container", five)
        self.assertIn("cordage", five)
        self.assertNotIn("lundin", five)
        self.assertNotIn("canterbury", five)
        trunk = json.dumps(by_id["env-core-temp"]).lower()
        self.assertIn("cotton", trunk)
        self.assertIn("trunk", trunk)
        seep = json.dumps(by_id["water-seep"]).lower()
        self.assertIn("seep", seep)
        self.assertNotIn("first muddy scoop is the drink", seep)
        wild = json.dumps(by_id["env-wildfire"]).lower()
        self.assertIn("already-burned", wild)
        rock = json.dumps(by_id["water-rockboil"]).lower()
        self.assertIn("wet rock", rock)
        gator = json.dumps(by_id["animal-gator"]).lower()
        self.assertIn("give it the water", gator)
        urban = json.dumps(by_id["water-urban"]).lower()
        self.assertIn("tank, not the bowl", urban)
        layers = json.dumps(by_id["camp-layers"]).lower()
        self.assertIn("wet cotton next to skin", layers)
        knots = json.dumps(by_id["shelter-knots"]).lower()
        self.assertIn("taut line", knots)
        rest = json.dumps(by_id["camp-rest-step"]).lower()
        self.assertIn("rest-step", rest)
        breathe = json.dumps(by_id["tact-breathe"]).lower()
        self.assertIn("slow the heart", breathe)
        booze = json.dumps(by_id["med-booze"]).lower()
        self.assertIn("does not warm you", booze)
        pantry = json.dumps(by_id["food-pantry"]).lower()
        self.assertIn("already in the kit or the house you already occupy", pantry)
        self.assertNotIn("raid the", pantry)
        field_py = read("tools", "v3", "field.py")
        self.assertIn("def from_nothing_core", field_py)
        self.assertIn("from_nothing_core()", field_py)
        self.assertIn("def craft_core", field_py)
        self.assertIn("craft_core()", field_py)
        self.assertIn("def manual_core", field_py)
        self.assertIn("manual_core()", field_py)
        self.assertNotIn("dual survival", field_py.lower())
        self.assertNotIn("lundin", field_py.lower())
        self.assertNotIn("canterbury", field_py.lower())
        self.assertNotIn("graham", field_py.lower())
        self.assertNotIn("bushcraft 101", field_py.lower())
        self.assertNotIn("98.6", field_py)

    def test_solo_qa_scores_field_search(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("SEARCH", qa)
        self.assertIn("NO MATCH", qa)
        self.assertIn("starting from nothing", qa.lower())
        self.assertIn("wool", qa.lower())
        self.assertIn("FIELD hits scroll", qa)
        self.assertIn("Empty query is SEARCH", qa)
        self.assertIn("not a dump of the book", qa)
        self.assertNotIn("Empty query is ALL CARDS", qa)
        self.assertNotIn("best in class", qa.lower())


if __name__ == "__main__":
    unittest.main()
