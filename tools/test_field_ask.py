#!/usr/bin/env python3
"""FIELD catalog is an offline ask over the shipped book.

Type a situation. Rank the cards that answer it. Submit opens the first
answering card's steps. Invent nothing. Never edible. MAP's five-hit cap
is a canvas rule, not a book rule.
"""
from __future__ import annotations

import json
import re
import unicodedata
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

STOP = {
    "a", "an", "the", "to", "of", "for", "in", "on", "at", "is", "be", "as",
    "or", "and", "how", "do", "i", "we", "you", "your", "my", "me", "what",
    "where", "when", "why", "can", "with", "from", "this", "that", "it",
    "if", "not", "no", "yes", "am", "are", "was", "have", "has", "any",
    "el", "la", "los", "las", "de", "un", "una", "y", "o", "que", "en",
    "es", "se", "te", "lo", "al", "del", "para", "por", "con", "como",
    "mi", "tu", "su",
}
LIVE = {"javelina", "peccary", "pecari", "hog", "coyote", "deer", "elk", "bear"}
MEAL = {"meat", "hunt", "cook", "already", "caza", "carne"}


def _corpus_src() -> str:
    return ROOT.joinpath(
        "Packages", "FieldCorpus", "Sources", "FieldCorpus", "FieldCorpus.swift"
    ).read_text()


def _swift_map(name: str, as_set: bool) -> dict:
    src = _corpus_src()
    start = src.index("= [", src.index(f"private static let {name}")) + 2
    depth = 0
    block = ""
    for j, ch in enumerate(src[start:], start):
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                block = src[start:j + 1]
                break
    out: dict = {}
    for key, vals in re.findall(r'"([^"]+)":\s*\[(.*?)\]', block, re.S):
        items = re.findall(r'"([^"]+)"', vals)
        out[key] = set(items) if as_set else items
    return out


EXPAND = _swift_map("expand", as_set=True)
BOOST = _swift_map("boost", as_set=False)


def _fold(s: str) -> str:
    return unicodedata.normalize("NFD", s).encode("ascii", "ignore").decode("ascii").lower()


def _stem(w: str) -> str:
    if len(w) > 4 and w.endswith("ies"):
        return w[:-3] + "y"
    if len(w) > 3 and w.endswith("s") and not w.endswith("ss"):
        return w[:-1]
    return w


def _tokens(s: str) -> list[str]:
    folded = _fold(s)
    words: list[str] = []
    cur = ""
    for ch in folded:
        if ch.isalnum():
            cur += ch
        elif cur:
            words.append(cur)
            cur = ""
    if cur:
        words.append(cur)
    out: list[str] = []
    for raw in words:
        w = _stem(raw)
        if len(w) < 2 or w in STOP:
            continue
        out.append(w)
    return out


def _index(card: dict) -> set[str]:
    parts = [
        card["id"].replace("-", " "),
        card["category"],
        card["title"]["en"], card["title"]["es"],
        card["situation"]["en"], card["situation"]["es"],
        card["get_to_care"]["en"], card["get_to_care"]["es"],
    ]
    for line in card["stop_if"]:
        parts += [line["en"], line["es"]]
    for st in card["steps"]:
        parts += [st["do"]["en"], st["do"]["es"], st["why"]["en"], st["why"]["es"]]
    toks: set[str] = set()
    for p in parts:
        toks.update(_tokens(p))
    return toks


def _boost_index(cid: str, expanded: set[str]) -> int:
    best = 10**9
    for word in expanded:
        ids = BOOST.get(word)
        if ids and cid in ids:
            best = min(best, ids.index(cid))
    return best


def ask_book(cards: list[dict], query: str, locale: str = "en") -> list[dict]:
    q_tokens = _tokens(query)
    if not q_tokens:
        return []
    expanded = set(q_tokens)
    for w in q_tokens:
        expanded |= EXPAND.get(w, set())
    boosted: set[str] = set()
    for w in expanded:
        boosted |= set(BOOST.get(w, []))
    folded_query = " ".join(q_tokens)
    prefer_es = locale == "es"
    live = any(t in LIVE for t in q_tokens)
    meal = any(t in MEAL for t in q_tokens)
    scored = []
    for card in cards:
        if live and not meal and card.get("category") == "food":
            continue
        title_tok = set(_tokens(card["title"]["en"]) + _tokens(card["title"]["es"]))
        id_tok = set(_tokens(card["id"].replace("-", " ")))
        cat_tok = set(_tokens(card["category"]))
        body_tok = _index(card)
        title_hits = len(expanded & title_tok)
        overlap = len(expanded & body_tok)
        boosted_hit = card["id"] in boosted
        if overlap == 0 and title_hits == 0 and not boosted_hit:
            continue
        score = overlap * 2 + title_hits * 10 + len(expanded & id_tok) * 8 + len(expanded & cat_tok) * 6
        if boosted_hit:
            score += 20
        if "wool" in q_tokens and card["id"] == "camp-layers":
            score += 25
        preferred = set(_tokens(card["title"]["es"] if prefer_es else card["title"]["en"]))
        score += len(expanded & preferred) * 3
        if len(q_tokens) >= 2:
            title_fold = _fold(card["title"]["en"]) + " " + _fold(card["title"]["es"])
            if title_tok.issuperset(set(q_tokens)):
                score += 40
            if len(folded_query) >= 4 and folded_query in title_fold:
                score += 20
        if score <= 0:
            continue
        scored.append((card, score, _boost_index(card["id"], expanded)))
    scored.sort(key=lambda a: (-a[1], a[2], a[0]["category"], a[0]["title"]["en"]))
    return [c for c, _, _ in scored]


def load_book() -> list[dict]:
    cards = json.loads((ROOT / "Resources/Field/field.core.json").read_text())["cards"]
    for st in ("tx", "nm"):
        cards += json.loads((ROOT / "Resources/Field" / f"field.{st}.json").read_text())["cards"]
    seen: dict[str, dict] = {}
    for card in cards:
        seen[card["id"]] = card
    return list(seen.values())

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
        self.assertNotIn("ForEach(listCards)", tab)
        self.assertIn("openAnswer()", tab)
        self.assertIn("onSubmit(openAnswer)", tab)
        self.assertIn(".submitLabel(.search)", tab)
        search = tab.split("private var searchField")[1].split("private func say")[0]
        self.assertIn('Button("SEARCH")', search)
        self.assertIn("openAnswer()", search)
        self.assertIn("FieldCorpus.chapter(", tab)
        self.assertIn("static func doLines", corpus)
        ask = corpus.split("static func ask(")[1].split("private static func index")[0]
        self.assertIn("liveAnimal", ask)
        self.assertIn('category == "food"', ask)
        self.assertIn("camp-layers", ask)
        self.assertIn('"food"', corpus)
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
        self.assertIn("Empty query is SEARCH", qa)
        self.assertIn("not a dump of the book", qa)
        self.assertIn("first answering card", qa)
        self.assertNotIn("Empty query is ALL CARDS", qa)
        self.assertNotIn("FIELD hits scroll", qa)
        self.assertNotIn("best in class", qa.lower())


class FieldSearchSayAndStepperTests(unittest.TestCase):
    """Type or SAY finds a pack card. Miss is silence. Never invent a protocol."""

    def test_say_is_on_device_dictation_into_the_same_ask(self):
        tab = read("Blackout", "FieldTab.swift")
        speech = read(
            "Packages", "OfflineSpeech", "Sources", "OfflineSpeech", "OfflineSpeech.swift"
        )
        gen = read("tools", "v3", "generate_project.py")
        pbx = read("Blackout.xcodeproj", "project.pbxproj")
        self.assertIn('Button("SAY")', tab)
        self.assertIn("SAY FAILED", tab)
        search = tab.split("private var searchField")[1].split("private func say")[0]
        self.assertIn('Button("SEARCH")', search)
        self.assertIn("openAnswer()", search)
        self.assertIn("runtime.speech.listen(locale:", tab)
        self.assertIn("runtime.ptt.live", tab)
        self.assertIn("openAnswer()", tab)
        self.assertNotIn("import Speech", tab)
        self.assertNotIn("URLSession", tab)
        self.assertNotIn("SFSpeechURLRecognitionRequest", tab)
        self.assertIn("func listen(", speech)
        self.assertIn("requiresOnDeviceRecognition = true", speech)
        self.assertIn("canImport(Speech)", speech)
        rec = speech.split("recognitionTask(with:")[1].split("armSilence")[0]
        self.assertIn("DispatchQueue.main.async", rec)
        self.assertNotIn("SFSpeechURLRecognitionRequest", speech)
        self.assertNotIn("URLSession", speech)
        self.assertNotIn("private let synth = AVSpeechSynthesizer()", speech)
        self.assertIn("INFOPLIST_KEY_NSSpeechRecognitionUsageDescription", gen)
        self.assertIn("INFOPLIST_KEY_NSSpeechRecognitionUsageDescription", pbx)
        self.assertGreaterEqual(
            pbx.count("INFOPLIST_KEY_NSSpeechRecognitionUsageDescription"), 2
        )
        self.assertIn("Deny is supported", gen)
        self.assertIn("on this device", gen.lower())
        self.assertIn("Deny is supported.", pbx)
        self.assertIn("on this device", pbx.lower())

    def test_open_card_is_situation_do_stop_if_get_to_care_with_pictures(self):
        tab = read("Blackout", "FieldTab.swift")
        open_fn = tab.split("private func open(")[1].split("private func sectionLabel")[0]
        self.assertIn('sectionLabel("SITUATION")', tab)
        self.assertIn('sectionLabel("DO")', tab)
        self.assertIn('L10n.t("stop.if"', tab)
        self.assertIn('sectionLabel("GET-TO-CARE")', tab)
        self.assertNotIn('sectionLabel("CARE")', tab)
        self.assertIn("s.step.image", open_fn)
        self.assertIn("FieldCorpus.doLines", open_fn)
        self.assertIn("s.step.child", open_fn)
        self.assertLess(
            open_fn.find('sectionLabel("DO")'),
            open_fn.find('L10n.t("stop.if"'),
        )
        self.assertLess(open_fn.find("s.step.image"), open_fn.find("FieldCorpus.doLines"))
        self.assertIn("Field/images", tab)
        self.assertIn("UIImage(contentsOfFile:", tab)
        self.assertTrue((ROOT / "Resources/Field/images/bleed-pack.png").is_file())
        self.assertIn("x.next()", tab)
        self.assertIn("openRoute([first.id])", tab)
        self.assertNotIn("ForEach(listCards)", tab)
        self.assertIn("NO MATCH", tab)
        self.assertNotIn("edible", tab.lower())
        self.assertNotIn("drinkable", tab.lower())
        self.assertNotIn("g.percent", tab)

    def test_solo_qa_scores_say_pictures_and_silence(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("SAY", qa)
        self.assertIn("GET-TO-CARE", qa)
        self.assertIn("SITUATION", qa)
        self.assertIn("NO MATCH", qa)
        self.assertIn("on this device", qa.lower())
        self.assertIn("Remaining hits stay out", qa)
        blob = qa.lower().replace("’", "'")
        self.assertIn("we don't have that", blob)
        self.assertIn("never invent", blob)
        self.assertIn("picture", blob)
        field_sec = qa.split("## FIELD")[1].split("## EXPEDITION")[0]
        self.assertIn("Sure % is not on SEARCH", field_sec)
        self.assertIn("no drinkable or edible number", field_sec.lower())


class FieldRankedBookTests(unittest.TestCase):
    """SEARCH opens the procedure the situation asked for, not a title hit."""

    def test_expand_and_boost_tables_are_loaded(self):
        self.assertIn("thirst", EXPAND)
        self.assertEqual(BOOST["thirst"][0], "water-disinfect")
        self.assertEqual(BOOST["food"][0], "food-cook")
        self.assertEqual(BOOST["wool"][0], "camp-layers")

    def test_shipped_book_opens_the_procedure(self):
        cards = load_book()
        first = lambda q: ask_book(cards, q)[0]["id"]
        self.assertEqual(first("javelina"), "tx-mammal")
        self.assertEqual(first("hog"), "tx-east-mammal")
        self.assertEqual(first("javelina meat"), "tx-game")
        self.assertEqual(first("wet wool"), "camp-layers")
        self.assertEqual(first("food"), "food-cook")
        self.assertEqual(first("thirst"), "water-disinfect")
        self.assertEqual(first("thirsty"), "water-disinfect")
        self.assertEqual(first("snake"), "animal-bite")
        self.assertEqual(first("starting from nothing"), "camp-start")
        self.assertEqual(first("wildfire"), "env-wildfire")
        self.assertEqual(first("seep"), "water-seep")
        self.assertEqual(first("mushroom"), "fungi-leave")
        self.assertEqual(first("panic"), "tact-breathe")
        self.assertEqual(first("gps"), "nav-lost")
        self.assertEqual(first("sed"), "water-find")
        self.assertEqual(first("comida"), "food-cook")
        self.assertFalse(ask_book(cards, "xyzzy plugh"))
        self.assertEqual(ask_book(cards, "javelina")[0]["category"], "animals")

    def test_every_open_step_has_a_picture_and_a_child_line(self):
        cards = load_book()
        images = {p.name for p in (ROOT / "Resources/Field/images").iterdir()}
        for card in cards:
            for i, step in enumerate(card["steps"]):
                img = step["image"]
                self.assertTrue(img, f"{card['id']} step {i} has no picture")
                self.assertIn(img, images, f"{card['id']} step {i} {img}")
                self.assertTrue(step["child"]["en"].strip(), f"{card['id']} step {i} child")
                self.assertTrue(step["do"]["en"].strip(), f"{card['id']} step {i} do")


if __name__ == "__main__":
    unittest.main()
