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
        self.assertIn("import FieldAsk", tab)
        self.assertIn("FieldAsk.answer", tab)
        self.assertIn("openLive(", tab)
        self.assertIn("askBusy", tab)
        self.assertIn("askFailed", tab)
        self.assertNotIn("asking(catalogQuery) && listCards.isEmpty", tab)
        self.assertIn('HUDField("SEARCH"', tab)
        self.assertNotIn("TextField(", tab)
        self.assertNotIn("textInputAutocapitalization", tab)
        self.assertIn("NO MATCH", tab)
        self.assertIn("NO ASK MODEL", tab)
        self.assertIn("ASK · LIVE", tab)
        self.assertNotIn("ForEach(listCards)", tab)
        self.assertIn("openAnswer()", tab)
        self.assertIn("onSubmit: openAnswer", tab)
        self.assertNotIn(".submitLabel(.search)", tab)
        search = tab.split("private var searchField")[1].split("private func say")[0]
        self.assertIn('Button("SEARCH")', search)
        self.assertIn("openAnswer()", search)
        self.assertIn('submit: "SEARCH"', search)
        bar = search.split("HStack", 1)[1].split("if sayFailed", 1)[0]
        self.assertIn('HUDField("SEARCH"', bar)
        self.assertIn('Button("SAY")', bar)
        self.assertLess(bar.find('HUDField("SEARCH"'), bar.find('Button("SEARCH")'))
        self.assertLess(bar.find('Button("SEARCH")'), bar.find('Button("SAY")'))
        self.assertLess(search.find("HStack"), search.find('HUDField("SEARCH"'))
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
        self.assertIn("ASK · LIVE", qa)
        self.assertIn("starting from nothing", qa.lower())
        self.assertIn("wool", qa.lower())
        self.assertIn("Empty query is SEARCH", qa)
        self.assertIn("not a dump of the book", qa)
        self.assertIn("first answering card", qa)
        self.assertNotIn("Empty query is ALL CARDS", qa)
        self.assertNotIn("FIELD hits scroll", qa)
        self.assertNotIn("best in class", qa.lower())


class FieldSearchSayAndStepperTests(unittest.TestCase):
    """Type or SAY finds a pack card. Book miss opens a live ASK walk."""

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
        bar = search.split("HStack", 1)[1].split("if sayFailed", 1)[0]
        self.assertIn('HUDField("SEARCH"', bar)
        self.assertIn('Button("SAY")', bar)
        self.assertLess(bar.find('HUDField("SEARCH"'), bar.find('Button("SEARCH")'))
        self.assertLess(bar.find('Button("SEARCH")'), bar.find('Button("SAY")'))
        self.assertLess(search.find("HStack"), search.find('HUDField("SEARCH"'))
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
        self.assertIn("openLive(", tab)
        self.assertNotIn("ForEach(listCards)", tab)
        self.assertIn("NO MATCH", tab)
        self.assertIn("NO ASK MODEL", tab)
        self.assertIn("ASK · LIVE", tab)
        self.assertNotIn("edible", tab.lower())
        self.assertNotIn("drinkable", tab.lower())
        self.assertNotIn("g.percent", tab)

    def test_solo_qa_scores_say_pictures_and_live_ask(self):
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("SAY", qa)
        self.assertIn("GET-TO-CARE", qa)
        self.assertIn("SITUATION", qa)
        self.assertIn("NO MATCH", qa)
        self.assertIn("ASK · LIVE", qa)
        self.assertIn("on this device", qa.lower())
        self.assertIn("Remaining hits stay out", qa)
        blob = qa.lower().replace("’", "'")
        self.assertIn("live walk", blob)
        self.assertIn("not a catalog", blob)
        self.assertNotIn("we don't have that", blob)
        self.assertNotIn("never invent a protocol", blob)
        self.assertIn("picture", blob)
        field_sec = qa.split("## FIELD")[1].split("## EXPEDITION")[0]
        self.assertIn("Sure % is not on SEARCH", field_sec)
        self.assertIn("no drinkable or edible number", field_sec.lower())
        self.assertIn("child", field_sec.lower())


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
        self.assertEqual(first("bleeding"), "med-bleed-pack")
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


LIVE_ID = "ask-live"
MODEL_FILE = "Dolphin3.0-Llama3.2-3B-Q4_K_M.gguf"
CHILD_HANDS_EN = "Do this one move with your hands. Then tap NEXT."
CHILD_HANDS_ES = "Haz este único movimiento con las manos. Luego toca NEXT."


def _loc(en: str, es: str | None = None) -> dict:
    return {"en": en, "es": es if es else en}


def _picture(chapter: list[dict], prefer: str | None = None) -> str:
    names = []
    for card in chapter:
        for step in card.get("steps") or []:
            img = (step.get("image") or "").strip()
            if img:
                names.append(img)
    if prefer and prefer in names:
        return prefer
    if names:
        return names[0]
    return "bleed-pack.png"


def _scrub(text: str) -> str:
    t = text or ""
    t = re.sub(r"telprompt:[^\s]+", "", t, flags=re.I)
    t = re.sub(r"tel://[^\s]+", "", t, flags=re.I)
    t = t.replace("98.6", "")
    replacements = (
        (r"\bsafe to eat\b", "do not eat wild plants"),
        (r"\bedible\b", "do not eat wild plants"),
        (r"\beat this plant\b", "do not eat wild plants"),
        (r"\bdrinkable\b", "not a drink until treated"),
    )
    for pat, rep in replacements:
        t = re.sub(pat, rep, t, flags=re.I)
    return re.sub(r"\s+", " ", t).strip()


def _loc_scrub(value: object, fallback: str) -> dict:
    if isinstance(value, dict):
        en = _scrub(str(value.get("en") or fallback))
        es = _scrub(str(value.get("es") or en or fallback))
    else:
        en = _scrub(str(value or fallback))
        es = en
    if not en:
        en = fallback
    if not es:
        es = en
    return _loc(en, es)


def parse_ask_json(text: str) -> dict | None:
    raw = text or ""
    raw = re.sub(r"```(?:json)?", "", raw, flags=re.I).replace("```", "")
    start = raw.find("{")
    end = raw.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        data = json.loads(raw[start : end + 1])
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    steps = data.get("steps")
    if not isinstance(steps, list) or not steps:
        return None
    return data


def sanitize_ask(card: dict, query: str, chapter: list[dict], pack_id: str | None) -> dict:
    picture = _picture(chapter)
    title = _loc_scrub(card.get("title"), query.strip() or "ASK")
    situation = _loc_scrub(
        card.get("situation"),
        f"You asked: {query.strip()}. One move at a time. Tap NEXT after each.",
    )
    care = _loc_scrub(
        card.get("get_to_care"),
        "Get to trained help. Do not wait on a number the glass cannot dial.",
    )
    stops_in = card.get("stop_if") or []
    stops = []
    if isinstance(stops_in, list):
        for line in stops_in:
            loc = _loc_scrub(line, "Stop if the scene is unsafe.")
            if loc["en"]:
                stops.append(loc)
    if not stops:
        stops = [
            _loc(
                "Stop if the place is on fire, collapsing, or in traffic.",
                "Para si hay fuego, derrumbe o tráfico.",
            )
        ]
    steps_out = []
    for step in card.get("steps") or []:
        if not isinstance(step, dict):
            continue
        do = _loc_scrub(step.get("do"), "Stop and look around.")
        child = _loc_scrub(step.get("child"), CHILD_HANDS_EN)
        if not child["en"]:
            child = _loc(CHILD_HANDS_EN, CHILD_HANDS_ES)
        why = _loc_scrub(step.get("why"), "One move. Then check.")
        stop = _loc_scrub(step.get("stop"), "Stop if it hurts more or the scene turns unsafe.")
        img = str(step.get("image") or "").strip() or picture
        steps_out.append(
            {
                "do": do,
                "why": why,
                "child": child,
                "stop": stop,
                "image": img,
            }
        )
    if len(steps_out) < 4:
        extra = grounded_ask(query, chapter, pack_id, "en")
        for st in extra["steps"]:
            if len(steps_out) >= 4:
                break
            steps_out.append(st)
    if len(steps_out) > 8:
        steps_out = steps_out[:8]
    return {
        "schema": "1.4",
        "id": LIVE_ID,
        "category": "ask",
        "states": ["TX", "NM"],
        "title": title,
        "situation": situation,
        "stop_if": stops,
        "get_to_care": care,
        "speak": True,
        "sendToParty": False,
        "steps": steps_out,
        "packs": [pack_id] if pack_id else None,
    }


def _step(do_en: str, do_es: str, child_en: str, child_es: str, why_en: str, why_es: str, stop_en: str, stop_es: str, image: str) -> dict:
    return {
        "do": _loc(do_en, do_es),
        "why": _loc(why_en, why_es),
        "child": _loc(child_en, child_es),
        "stop": _loc(stop_en, stop_es),
        "image": image,
    }


def grounded_ask(query: str, chapter: list[dict], pack_id: str | None, locale: str) -> dict:
    q = " ".join(_tokens(query))
    picture = _picture(chapter)
    bleed_pic = _picture(chapter, "bleed-pack.png")
    water_pic = _picture(chapter)
    toks = set(_tokens(query))
    asked = query.strip() or "this"
    if toks & {"bleed", "bleeding", "blood", "cut", "wound", "shot", "stab", "gash"}:
        family = "bleed"
    elif toks & {"choke", "choking"}:
        family = "choke"
    elif toks & {"cpr", "unresponsive", "pulse"} or ("breath" in q and "not" in q):
        family = "cpr"
    elif toks & {"burn", "scald"}:
        family = "burn"
    elif toks & {"lost", "gps", "separated"}:
        family = "lost"
    elif toks & {"break", "broken", "sprain", "sling", "fracture"}:
        family = "break"
    else:
        family = "start"
    start = [
        _step(
            "Stop. Look around. Do not run.",
            "Para. Mira alrededor. No corras.",
            "Stand still. Hold a grown-up's hand if one is there.",
            "Quédate quieto. Toma la mano de un adulto si hay uno.",
            "Running makes you miss the danger and the way back.",
            "Correr te hace perder el peligro y el camino de vuelta.",
            "Stop if the ground is falling, on fire, or under traffic.",
            "Para si el piso se cae, hay fuego o hay tráfico.",
            picture,
        ),
        _step(
            "Move to the safest near spot you can see: off the road, out of the water, away from fire.",
            "Muévete al sitio cercano más seguro: fuera del camino, fuera del agua, lejos del fuego.",
            "Walk, do not run. Stay where people can see you.",
            "Camina, no corras. Quédate donde la gente te vea.",
            "The first job is a place that will not hit you.",
            "Lo primero es un lugar que no te golpee.",
            "Stop if moving would put you in the hazard.",
            "Para si moverte te mete en el peligro.",
            picture,
        ),
    ]
    if family == "bleed":
        body = [
            _step(
                "If you have a cloth, press it hard on the bleeding spot and keep pressing.",
                "Si tienes un paño, presiónalo fuerte en el sangrado y no lo sueltes.",
                "Use both hands. Do not peek. Peeking lets the blood out.",
                "Usa las dos manos. No mires debajo. Mirar deja salir la sangre.",
                "Pressure is the first move. Looking under the cloth restarts the bleed.",
                "La presión es el primer movimiento. Mirar debajo reinicia el sangrado.",
                "Stop if the scene is unsafe. Move them with you if you must.",
                "Para si la escena es insegura. Muévelos contigo si hace falta.",
                bleed_pic,
            ),
            _step(
                "If blood soaks through, put another cloth on top. Do not take the first one off.",
                "Si la sangre traspasa, pon otro paño encima. No quites el primero.",
                "Keep pressing. Ask a grown-up to hold if your arms shake.",
                "Sigue presionando. Pide a un adulto que sostenga si te tiembran los brazos.",
                "The first cloth is the plug.",
                "El primer paño es el tapón.",
                "Stop pressing only if trained help takes over.",
                "Deja de presionar solo si la ayuda entrenada toma el relevo.",
                bleed_pic,
            ),
        ]
        care = _loc(
            "Keep pressure and get to trained help. Do not wait on a number the glass cannot dial.",
            "Sigue la presión y llega a ayuda entrenada. No esperes un número que el visor no puede marcar.",
        )
    elif family == "choke":
        body = [
            _step(
                "If they can cough or speak, let them cough. Stay next to them.",
                "Si pueden toser o hablar, déjalos toser. Quédate a su lado.",
                "Do not put fingers in their mouth.",
                "No metas los dedos en la boca.",
                "Air can still move if they cough.",
                "El aire aún puede pasar si tosen.",
                "If they stop coughing and cannot breathe, go to the next move.",
                "Si dejan de toser y no respiran, pasa al siguiente movimiento.",
                picture,
            ),
            _step(
                "If they cannot cough, speak, or breathe, hit their back hard between the shoulders five times.",
                "Si no pueden toser, hablar ni respirar, golpea la espalda fuerte entre los hombros cinco veces.",
                "Stand to the side. Aim at the back, not the neck.",
                "Ponte a un lado. Apunta a la espalda, no al cuello.",
                "A hard back blow can move the block.",
                "Un golpe fuerte en la espalda puede mover el bloqueo.",
                "Stop if they start coughing or breathing.",
                "Para si empiezan a toser o respirar.",
                picture,
            ),
        ]
        care = _loc(
            "Get trained help even if the block comes out. They can swell later.",
            "Consigue ayuda entrenada aunque salga el bloqueo. Pueden hincharse después.",
        )
    elif family == "cpr":
        body = [
            _step(
                "Tap the shoulders and look at the chest for ten seconds. No normal breathing means start compressions.",
                "Toca los hombros y mira el pecho diez segundos. Sin respiración normal, empieza compresiones.",
                "Keep other children back. One person pushes. Another watches the child.",
                "Aleja a otros niños. Una persona empuja. Otra vigila al niño.",
                "Delay kills. Gasping is not normal breathing.",
                "La demora mata. El jadeo no es respiración normal.",
                "If they cough, move, or breathe normally, stop compressions and watch them.",
                "Si tosen, se mueven o respiran normal, detén y vigílalos.",
                _picture(chapter, "cpr-check.png"),
            ),
            _step(
                "Hard, fast compressions in the center of the chest. Let the chest come back up each time.",
                "Compresiones fuertes y rápidas al centro del pecho. Deja que el pecho suba cada vez.",
                "Do not stand on the chest. Do not 'help' with a bounce.",
                "No te subas al pecho. No 'ayudes' con un rebote.",
                "Blood has to reach the brain. Shallow pumps do nothing.",
                "La sangre tiene que llegar al cerebro. Las palmaditas no sirven.",
                "Stop if an AED is attached and says stay clear, or if they start breathing.",
                "Para si un DEA dice apartarse o si empiezan a respirar.",
                _picture(chapter, "cpr-compress.png"),
            ),
        ]
        care = _loc(
            "Get trained help and an AED. Keep compressions until they take over.",
            "Consigue ayuda entrenada y un DEA. Sigue hasta que tomen el relevo.",
        )
    elif family == "burn":
        body = [
            _step(
                "Get the heat off. Cool the burn with clean water. Do not put ice, butter, or toothpaste on it.",
                "Quita el calor. Enfría la quemadura con agua limpia. No pongas hielo, mantequilla ni pasta.",
                "Hold the water on the skin. Do not smear anything on it.",
                "Sostén el agua en la piel. No untes nada.",
                "Ice and grease hold heat in.",
                "El hielo y la grasa guardan el calor.",
                "Stop cooling if they start to shake from cold.",
                "Deja de enfriar si empiezan a temblar de frío.",
                picture,
            ),
            _step(
                "Cover loosely with a clean cloth. Do not pop blisters.",
                "Cubre flojo con un paño limpio. No revientes ampollas.",
                "Touch the cloth, not the burn.",
                "Toca el paño, no la quemadura.",
                "Open skin is how dirt gets in.",
                "La piel abierta es por donde entra suciedad.",
                "Stop if the cloth sticks — leave it and get care.",
                "Para si el paño se pega — déjalo y busca cuidado.",
                picture,
            ),
        ]
        care = _loc(
            "Get to trained help for any burn that is big, on the face, or on the hands.",
            "Llega a ayuda entrenada si la quemadura es grande, en la cara o en las manos.",
        )
    elif family == "lost":
        body = [
            _step(
                "Stay where you are if that spot is safe. Hug a tree or sit on a rock people can see.",
                "Quédate si el sitio es seguro. Abraza un árbol o siéntate en una roca visible.",
                "Sit. Do not wander to 'look for camp'.",
                "Siéntate. No deambules a 'buscar el campamento'.",
                "Searchers walk a line. A moving child is the one they miss.",
                "Los buscadores caminan una línea. Un niño que se mueve es el que pierden.",
                "Move only if fire, water, or night cold will hit you here.",
                "Muévete solo si el fuego, el agua o el frío de noche te van a pegar aquí.",
                picture,
            ),
            _step(
                "Make yourself big and loud from that spot: yell in threes, wave a bright cloth.",
                "Hazte grande y ruidoso desde ese sitio: grita de a tres, agita un paño brillante.",
                "Three yells. Then listen. Then three more.",
                "Tres gritos. Luego escucha. Luego tres más.",
                "A pattern is how people know you are a person.",
                "Un patrón es cómo saben que eres una persona.",
                "Stop yelling if you need that breath to stay warm.",
                "Deja de gritar si necesitas ese aire para no enfriar.",
                picture,
            ),
        ]
        care = _loc(
            "Stay put until a known voice reaches you. Do not follow a stranger off your spot.",
            "Quédate hasta que una voz conocida te alcance. No sigas a un extraño fuera de tu sitio.",
        )
    elif family == "break":
        body = [
            _step(
                "Do not try to push a bone back. Leave the limb how it lies.",
                "No intentes meter un hueso. Deja el miembro como está.",
                "Hands off the break. Hold the rest of the body still.",
                "Manos fuera de la fractura. Sostén el resto del cuerpo quieto.",
                "Moving the bone can cut the rest of the limb.",
                "Mover el hueso puede cortar el resto del miembro.",
                "Stop if they faint or the fingers go white and cold.",
                "Para si se desmayan o los dedos se ponen blancos y fríos.",
                picture,
            ),
            _step(
                "Pad around the limb with cloth and tie it to something stiff so it cannot flop. Tie loose enough to slip a finger under.",
                "Acolcha el miembro con tela y átalo a algo rígido para que no se mueva. Lo bastante flojo para meter un dedo.",
                "Hold the stick. Let a grown-up tie if they are there.",
                "Sostén el palo. Deja que un adulto ate si está ahí.",
                "A floppy break keeps tearing.",
                "Una fractura suelta sigue rasgando.",
                "Stop if the tie makes fingers numb or blue.",
                "Para si el nudo deja los dedos entumecidos o azules.",
                picture,
            ),
        ]
        care = _loc(
            "Carry them if you can. Get to trained help. Do not wait on a number the glass cannot dial.",
            "Cárgalos si puedes. Llega a ayuda entrenada. No esperes un número que el visor no puede marcar.",
        )
    else:
        body = [
            _step(
                f"Do one first move for this ask: {asked}. Use your hands. One thing only.",
                f"Haz un primer movimiento para esto: {asked}. Usa las manos. Una sola cosa.",
                CHILD_HANDS_EN,
                CHILD_HANDS_ES,
                "First time means one action, then check.",
                "La primera vez es un acto, luego revisar.",
                "Stop if it hurts more or the scene turns unsafe.",
                "Para si duele más o la escena se vuelve insegura.",
                water_pic,
            ),
            _step(
                "Check the person or the camp after that one move. Then do the next one move, not three.",
                "Revisa a la persona o el campamento después de ese movimiento. Luego haz el siguiente, no tres.",
                "Look. Then one more hand move. Then tap NEXT.",
                "Mira. Luego un movimiento más. Luego toca NEXT.",
                "Stacking jobs is how first-timers skip the one that saves them.",
                "Apilar tareas es cómo los principiantes saltan la que los salva.",
                "Stop if you cannot see, cannot stand, or cannot hear.",
                "Para si no ves, no te sostienes o no oyes.",
                picture,
            ),
        ]
        care = _loc(
            "Get to people who can help. Stay with the party. Do not wait on a number the glass cannot dial.",
            "Llega a gente que pueda ayudar. Quédate con el grupo. No esperes un número que el visor no puede marcar.",
        )
    finish = [
        _step(
            "If you cannot finish, stay visible and stay with the party. Do not eat wild plants. Do not drink untreated water.",
            "Si no puedes terminar, quédate visible y con el grupo. No comas plantas silvestres. No bebas agua sin tratar.",
            "Hands off plants and standing water. Sit where people can see you.",
            "Manos fuera de plantas y agua estancada. Siéntate donde te vean.",
            "Unknown plants and untreated water are how a small problem becomes two.",
            "Plantas desconocidas y agua sin tratar convierten un problema en dos.",
            "Stop if you feel faint. Sit. Yell.",
            "Para si te desmayas. Siéntate. Grita.",
            picture,
        ),
    ]
    steps = start + body + finish
    if len(steps) > 8:
        steps = steps[:8]
    title_en = asked[:44] if asked else "ASK"
    return {
        "schema": "1.4",
        "id": LIVE_ID,
        "category": "ask",
        "states": ["TX", "NM"],
        "title": _loc(title_en, title_en),
        "situation": _loc(
            f"You asked: {asked}. First time. One move per step. A child can follow it.",
            f"Preguntaste: {asked}. Primera vez. Un movimiento por paso. Un niño puede seguirlo.",
        ),
        "stop_if": [
            _loc(
                "Stop if the place is on fire, collapsing, or in traffic.",
                "Para si hay fuego, derrumbe o tráfico.",
            ),
            _loc(
                "Stop if they stop breathing, or bleeding soaks through and you cannot keep pressure.",
                "Para si dejan de respirar, o el sangrado traspasa y no puedes mantener presión.",
            ),
        ],
        "get_to_care": care,
        "speak": True,
        "sendToParty": False,
        "steps": steps,
        "packs": [pack_id] if pack_id else None,
    }


def prompt_ask(query: str, pack_name: str, excerpts: list[dict], locale: str) -> str:
    bits = []
    for card in excerpts[:8]:
        title = card.get("title") or {}
        sit = card.get("situation") or {}
        do0 = ""
        if card.get("steps"):
            do0 = ((card["steps"][0].get("do") or {}).get("en") or "")[:180]
        bits.append(f"- {card.get('id')}: {title.get('en', '')}. {sit.get('en', '')} {do0}".strip())
    ground = "\n".join(bits) if bits else "(no book excerpts)"
    system = (
        "You are FIELD ASK on an offline survival HUD. The reader may be a child "
        "who has never done this. Answer with schema 1.4 JSON only. One action per "
        "step. child is what the child's hands do. First time: name the object, "
        "where to put hands, when to stop. 4 to 8 steps. STOP-IF and GET-TO-CARE. "
        "Never edible. Never a drinkable number. Never a phone number or tel://. "
        "Use the pack book excerpts as ground when they apply. If they do not, "
        "still give a first-time walk that keeps them alive and getting to care. JSON only."
    )
    user = (
        f"locale: {locale}\npack: {pack_name}\nask: {query}\nbook:\n{ground}\n"
        "Return one FieldCard JSON object with title, situation, stop_if, get_to_care, "
        "and steps[{do,why,child,stop,image}]. Both en and es. image is a filename "
        "from the book steps. id must be ask-live. sendToParty false."
    )
    return (
        "<|im_start|>system\n"
        f"{system}<|im_end|>\n"
        "<|im_start|>user\n"
        f"{user}<|im_end|>\n"
        "<|im_start|>assistant\n"
    )


def answer_ask(
    query: str,
    chapter: list[dict],
    locale: str,
    pack_name: str,
    pack_id: str | None,
    model_text: str | None,
) -> dict | None:
    if not _tokens(query):
        return None
    if ask_book(chapter, query, locale):
        return None
    if model_text:
        parsed = parse_ask_json(model_text)
        if parsed:
            return sanitize_ask(parsed, query, chapter, pack_id)
    return grounded_ask(query, chapter, pack_id, locale)


class FieldAskLiveTests(unittest.TestCase):
    """Unknown survival asks still open a child-first walk. Book hits stay the book."""

    def test_oracle_book_first_then_live_child_walk(self):
        book = load_book()
        self.assertIsNone(answer_ask("thirst", book, "en", "west", "tx-west", None))
        self.assertIsNone(answer_ask("snake", book, "en", "west", "tx-west", None))
        self.assertIsNone(answer_ask("", book, "en", "west", "tx-west", None))
        live = answer_ask("xyzzy plugh", book, "en", "west", "tx-west", None)
        self.assertIsNotNone(live)
        assert live is not None
        self.assertEqual(live["id"], LIVE_ID)
        self.assertFalse(live["sendToParty"])
        self.assertGreaterEqual(len(live["steps"]), 4)
        self.assertLessEqual(len(live["steps"]), 8)
        images = {p.name for p in (ROOT / "Resources/Field/images").iterdir()}
        for step in live["steps"]:
            self.assertTrue(step["child"]["en"].strip())
            self.assertTrue(step["do"]["en"].strip())
            self.assertTrue(step["image"])
            self.assertIn(step["image"], images)
            blob = json.dumps(step).lower()
            self.assertNotIn("edible", blob)
            self.assertNotIn("tel://", blob)
            self.assertNotIn("drinkable", blob)
        bleed = grounded_ask("my friend is bleeding a lot", book, "tx-west", "en")
        self.assertIn("press", json.dumps(bleed).lower())
        lost = grounded_ask("I am a kid and I am lost", book, "tx-west", "en")
        assert lost is not None
        self.assertIn("stay", json.dumps(lost).lower())
        poison = {
            "title": {"en": "Eat this plant, it is edible", "es": "Come"},
            "situation": {"en": "Call tel://911 now", "es": "tel://911"},
            "stop_if": [{"en": "safe to eat", "es": "edible"}],
            "get_to_care": {"en": "drinkable 98.6", "es": "98.6"},
            "steps": [
                {
                    "do": {"en": "Eat this plant", "es": "Come"},
                    "why": {"en": "edible", "es": "edible"},
                    "child": {"en": "", "es": ""},
                    "stop": {"en": "tel://911", "es": "tel://911"},
                    "image": "bleed-pack.png",
                },
                {
                    "do": {"en": "Stay put.", "es": "Quédate."},
                    "why": {"en": "One move.", "es": "Un movimiento."},
                    "child": {"en": "Sit.", "es": "Siéntate."},
                    "stop": {"en": "Stop if unsafe.", "es": "Para si es inseguro."},
                    "image": "bleed-pack.png",
                },
                {
                    "do": {"en": "Stay visible.", "es": "Quédate visible."},
                    "why": {"en": "People find still kids.", "es": "Encuentran a niños quietos."},
                    "child": {"en": "Wave a cloth.", "es": "Agita un paño."},
                    "stop": {"en": "Stop if the scene turns unsafe.", "es": "Para si se vuelve inseguro."},
                    "image": "bleed-pack.png",
                },
                {
                    "do": {"en": "Get to care.", "es": "Llega a cuidado."},
                    "why": {"en": "Help is people, not a number.", "es": "La ayuda es gente, no un número."},
                    "child": {"en": "Walk with a grown-up.", "es": "Camina con un adulto."},
                    "stop": {"en": "Stop if you cannot walk.", "es": "Para si no puedes caminar."},
                    "image": "bleed-pack.png",
                },
            ],
        }
        clean = sanitize_ask(poison, "berries", book, "tx-west")
        blob = json.dumps(clean).lower()
        self.assertNotIn("edible", blob)
        self.assertNotIn("tel://", blob)
        self.assertNotIn("98.6", blob)
        self.assertNotIn("drinkable", blob)
        self.assertTrue(clean["steps"][0]["child"]["en"].strip())
        self.assertEqual(clean["id"], LIVE_ID)
        parsed = parse_ask_json(
            '```json\n{"title":{"en":"Sling","es":"Cabestrillo"},'
            '"steps":[{"do":{"en":"Pad the arm.","es":"Acolcha."},'
            '"why":{"en":"Keep it still.","es":"Quieto."},'
            '"child":{"en":"Hold the cloth.","es":"Sostén el paño."},'
            '"stop":{"en":"Stop if numb.","es":"Para si entumece."},'
            '"image":"bleed-pack.png"}]}\n```'
        )
        self.assertIsNotNone(parsed)
        prompt = prompt_ask("broken arm sling", "west", book[:3], "en")
        self.assertIn("<|im_start|>system", prompt)
        self.assertIn("<|im_end|>", prompt)
        self.assertIn("<|im_start|>user", prompt)
        self.assertIn("<|im_start|>assistant", prompt)
        self.assertIn("Never edible", prompt)
        self.assertIn("child", prompt)
        self.assertNotIn("best in class", prompt.lower())

    def test_swift_field_ask_is_dolphin_q4_on_device(self):
        ask = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldAsk.swift")
        llama = read("Packages", "FieldAsk", "Sources", "FieldAsk", "FieldAskLlama.swift")
        pkg = read("Packages", "FieldAsk", "Package.swift")
        tab = read("Blackout", "FieldTab.swift")
        fetch = read("tools", "fetch_field_ask_model.py")
        gitignore = read(".gitignore")
        pbx = read("Blackout.xcodeproj", "project.pbxproj")
        gen = read("tools", "v3", "generate_project.py")
        validate = read("tools", "validate_v3.py")
        tf = read(".github", "ci", "tf-archive.sh")
        unsigned = read(".github", "workflows", "xcodebuild.yml")
        self.assertIn("enum FieldAsk", ask)
        self.assertIn("static func answer(", ask)
        self.assertIn("static func prompt(", ask)
        self.assertIn("static func parse(", ask)
        self.assertIn("static func sanitize(", ask)
        self.assertIn("static func grounded(", ask)
        self.assertIn("static func modelURL(", ask)
        self.assertIn(MODEL_FILE, ask)
        self.assertIn("NO ASK MODEL", ask)
        self.assertIn(LIVE_ID, ask)
        self.assertIn("<|im_start|>", ask)
        self.assertIn("<|im_end|>", ask)
        self.assertIn("Never edible", ask)
        self.assertIn("sendToParty: false", ask)
        self.assertNotIn("URLSession", ask)
        self.assertNotIn("best in class", ask.lower())
        self.assertIn("import llama", llama)
        self.assertIn("static func complete(", llama)
        self.assertIn("llama_model_load_from_file", llama)
        self.assertIn("llama_init_from_model", llama)
        self.assertIn("<|im_end|>", llama)
        self.assertNotIn("print(", llama)
        self.assertNotIn("URLSession", llama)
        self.assertIn('name: "llama"', pkg)
        self.assertIn("llama-b8638-xcframework.zip", pkg)
        self.assertIn("7d7d44e35550ebf5ac803173f1897d9dd3dd9a5f8d44218559228cfe966399b7", pkg)
        self.assertIn('.iOS("18.0")', pkg)
        self.assertNotIn("watchOS", pkg)
        self.assertIn("import FieldAsk", tab)
        self.assertIn("openLive(", tab)
        self.assertIn("FieldAsk.answer", tab)
        self.assertIn("Task.detached", tab)
        self.assertIn("ASK · LIVE", tab)
        self.assertIn("askBusy", tab)
        open_ans = tab.split("private func openAnswer(")[1].split("private func jump")[0]
        self.assertIn("listCards.first", open_ans)
        self.assertIn("openRoute([first.id])", open_ans)
        self.assertIn("FieldAsk.answer", open_ans)
        self.assertIn("openLive", open_ans)
        self.assertNotIn("URLSession", tab)
        self.assertIn(MODEL_FILE, fetch)
        self.assertIn("5d6d02eeefa1ab5dbf23f97afdf5c2c95ad3d946dc3b6e9ab72e6c1637d54177", fetch)
        self.assertIn("huggingface.co", fetch)
        self.assertIn("Dolphin3.0-Llama3.2-3B-Q4_K_M.gguf", fetch)
        self.assertNotIn("URLSession", fetch)
        self.assertIn("*.gguf", gitignore)
        self.assertIn("FieldAsk", pbx)
        self.assertIn("AB685F0E850F09BAF71E9E35", pbx)
        self.assertIn("635D413CD909912F4D333731", pbx)
        self.assertIn("BF2D63524A24050AD76A805D", pbx)
        self.assertIn('("FieldAsk", "FieldAsk")', gen)
        self.assertIn("FieldAsk", validate)
        self.assertIn("fetch_field_ask_model", tf)
        self.assertNotIn("fetch_field_ask_model", unsigned)
        self.assertNotIn("best in class", fetch.lower())
        self.assertNotIn("best in class", llama.lower())


if __name__ == "__main__":
    unittest.main()
