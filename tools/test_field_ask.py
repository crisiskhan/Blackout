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
        "someone", "somebody", "please", "hes", "shes", "theyre",
        "they", "them", "their", "something",
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


def _phrase_pairs() -> list[tuple[str, str]]:
    src = _corpus_src()
    start = src.index("private static let phrases")
    lb = src.index("= [", start) + 2
    depth = 0
    end = lb
    for j, ch in enumerate(src[lb:], lb):
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                end = j
                break
    block = src[lb:end + 1]
    return [(a, b) for a, b in re.findall(r'\("([^"]+)",\s*"([^"]+)"\)', block)]


PHRASES = _phrase_pairs()


def _has_phrase(hay: str, needle: str) -> bool:
    if " " in needle or len(needle) >= 6:
        return needle in hay
    words: list[str] = []
    cur = ""
    for ch in hay:
        if ch.isalnum():
            cur += ch
        elif cur:
            words.append(cur)
            cur = ""
    if cur:
        words.append(cur)
    return needle in words


def _prepare(query: str) -> str:
    t = _fold(query)
    for mark in ("'", "’", "`", "´", "‘"):
        t = t.replace(mark, "")
    extra: list[str] = []
    for needle, words in PHRASES:
        if _has_phrase(t, needle):
            extra.append(words)
    if not extra:
        return t
    return t + " " + " ".join(extra)


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
    q_tokens = _tokens(_prepare(query))
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
        if ("choke" in expanded or "unknown" in expanded) and card.get("category") == "food":
            continue
        if "burn" in q_tokens and card.get("category") == "fire":
            continue
        if "cardiac" in expanded:
            continue
        if "drown" in expanded:
            continue
        if "seizure" in expanded:
            continue
        if "tornado" in expanded:
            continue
        if "nose" in expanded:
            continue
        if "shock" in expanded and "choke" not in expanded:
            continue
        if "eye" in expanded and "glare" not in expanded:
            continue
        if "allergy" in expanded:
            continue
        if "stroke" in expanded and "heat" not in expanded:
            continue
        if "poison" in expanded and not ({"ivy", "oak", "sumac"} & expanded):
            continue
        if "asthma" in expanded:
            continue
        if "avalanche" in expanded:
            continue
        if "rip" in expanded:
            continue
        if "breath" in expanded and "choke" not in expanded and "cpr" not in expanded:
            continue
        if (
            "hurt" in expanded
            and "fracture" not in expanded
            and "bleed" not in expanded
            and "burn" not in expanded
            and "bite" not in expanded
            and "sting" not in expanded
            and "spine" not in expanded
            and "neck" not in q_tokens
            and "fell" not in q_tokens
            and "fall" not in q_tokens
        ):
            continue
        if "infant" in expanded and (
            "choke" in expanded
            or "cpr" in expanded
            or "airway" in expanded
            or "selfchoke" in expanded
        ):
            continue
        if "selfchoke" in expanded:
            continue
        if "pregnant" in expanded and (
            "choke" in expanded or "cpr" in expanded or "airway" in expanded
        ):
            continue
        if "sugar" in expanded:
            continue
        if "overdose" in expanded:
            continue
        if "impaled" in expanded:
            continue
        if "hole" in expanded and (
            "chest" in q_tokens or "sucking" in q_tokens or "puncture" in q_tokens
        ):
            continue
        if "sick" in expanded:
            continue
        if (
            {"people", "civilization", "anyone", "radio", "phone"} & expanded
            and not ({"water", "thirst", "choke", "bleed", "hurt"} & expanded)
        ):
            continue
        if (
            "stay" in expanded
            and ({"stable", "stabilize", "alive"} & set(q_tokens))
            and "cold" not in expanded
            and "heat" not in expanded
            and "warm" not in q_tokens
            and "cool" not in q_tokens
        ):
            continue
        if "head" in expanded and "bleed" not in expanded and "wound" not in q_tokens:
            continue
        if ("warm" in q_tokens or "cool" in q_tokens) and card.get("id") == "tact-staygo":
            continue
        if "tick" in q_tokens and card.get("id") == "animal-bite":
            continue
        title_tok = set(_tokens(card["title"]["en"]) + _tokens(card["title"]["es"]))
        id_tok = set(_tokens(card["id"].replace("-", " ")))
        cat_tok = set(_tokens(card["category"]))
        body_tok = _index(card)
        title_hits = len(expanded & title_tok)
        overlap = len(expanded & body_tok)
        id_hits = len(expanded & id_tok)
        cat_hits = len(expanded & cat_tok)
        boosted_hit = card["id"] in boosted
        if not boosted_hit and title_hits == 0 and id_hits == 0 and overlap < 2:
            continue
        score = overlap * 2 + title_hits * 10 + id_hits * 8 + cat_hits * 6
        if boosted_hit:
            score += 20
        if "wool" in q_tokens and card["id"] == "camp-layers":
            score += 25
        if "lost" in q_tokens and card["id"] == "nav-lost":
            score += 25
        if "burn" in q_tokens and card["id"] == "med-burn":
            score += 25
        if "tick" in q_tokens and card["id"] == "env-insect":
            score += 25
        if ("heat" in expanded or "cool" in q_tokens) and card["id"] == "env-heat-collapse":
            score += 25
        if (
            "cold" in expanded or "warm" in q_tokens or "freezing" in q_tokens
        ) and card["id"] == "env-cold":
            score += 25
        if "deer" in q_tokens and card["id"] in {
            "tx-mammal",
            "tx-east-mammal",
            "nm-mammal",
        }:
            score += 25
        if "signal" in expanded and card["id"] in {"sig-mirror", "sig-ground"}:
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
        session = read("Blackout", "FieldSession.swift")
        app = read("Blackout", "AppRuntime.swift")
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
        self.assertIn("FieldAsk.answer", session)
        self.assertIn("openFieldLive(", session)
        self.assertIn("askBusy", session)
        self.assertIn("askFailed", session)
        self.assertNotIn("asking(catalogQuery) && listCards.isEmpty", tab)
        self.assertIn('L10n.t("field.search"', tab)
        self.assertNotIn("TextField(", tab)
        self.assertNotIn("textInputAutocapitalization", tab)
        self.assertIn("NO MATCH", tab)
        self.assertIn("ASK · LIVE", session)
        self.assertNotIn("ForEach(listCards)", tab)
        self.assertIn("openAnswer()", tab)
        self.assertIn("onSubmit: openAnswer", tab)
        self.assertNotIn(".submitLabel(.search)", tab)
        search = tab.split("private var searchField")[1].split("private func say")[0]
        self.assertIn('L10n.t("field.search"', search)
        self.assertIn("openAnswer()", search)
        bar = search.split("HStack", 1)[1].split("sayFailed", 1)[0]
        self.assertIn('L10n.t("field.search"', bar)
        self.assertIn('L10n.t("field.say"', bar)
        self.assertLess(bar.find('L10n.t("field.search"'), bar.find('L10n.t("field.say"'))
        self.assertLess(search.find("HStack"), search.find('L10n.t("field.search"'))
        apply_ask = session.split("func applyFieldAsk")[1].split("func openFieldLive")[0]
        self.assertIn("now.isEmpty", apply_ask)
        self.assertIn("now != expected", apply_ask)
        self.assertIn("field.clearInstrument()", app)
        status = tab.split("private var fieldStatus")[1].split("private var fieldTone")[0]
        self.assertIn('askFailed { return "NO MATCH" }', status)
        self.assertNotIn('if askFailed { return "NO ASK MODEL" }', status)
        vision = session.split("func applyFieldVision")[1].split("func speakFieldVision")[0]
        self.assertIn("visionSeq += 1", vision)
        self.assertIn("guard seq == self.field.visionSeq", vision)
        self.assertIn("FieldCorpus.chapter(", tab)
        self.assertIn("static func doLines", corpus)
        self.assertIn("static func prepare(", corpus)
        self.assertIn("where am i", corpus)
        self.assertIn("got bit", corpus)
        self.assertIn("not breathing", corpus)
        self.assertIn("cant breathe", corpus)
        self.assertIn("cant walk", corpus)
        self.assertIn("stung", corpus)
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
        self.assertNotIn("safe to eat", corpus.lower())
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
        self.assertIn('L10n.t("field.say"', tab)
        self.assertIn("SAY FAILED", tab)
        search = tab.split("private var searchField")[1].split("private func say")[0]
        self.assertIn('L10n.t("field.search"', search)
        self.assertIn("openAnswer()", search)
        bar = search.split("HStack", 1)[1].split("sayFailed", 1)[0]
        self.assertIn('L10n.t("field.search"', bar)
        self.assertIn('L10n.t("field.say"', bar)
        self.assertLess(bar.find('L10n.t("field.search"'), bar.find('L10n.t("field.say"'))
        self.assertLess(search.find("HStack"), search.find('L10n.t("field.search"'))
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
        self.assertIn('sectionLabel("HANDS")', open_fn)
        self.assertLess(
            open_fn.find('sectionLabel("HANDS")'),
            open_fn.find("s.step.child"),
        )
        self.assertLess(
            open_fn.find("s.step.child"),
            open_fn.find("s.step.why"),
        )
        self.assertLess(
            open_fn.find('sectionLabel("DO")'),
            open_fn.find('L10n.t("stop.if"'),
        )
        self.assertLess(open_fn.find("s.step.image"), open_fn.find("FieldCorpus.doLines"))
        self.assertLess(
            open_fn.find("stepTitle"),
            open_fn.find('L10n.t("stop.if"'),
            "NEXT must sit after DO, before STOP-IF",
        )
        self.assertLess(
            open_fn.find('Button("SPEAK")'),
            open_fn.find('L10n.t("stop.if"'),
            "SPEAK stays with NEXT on the move",
        )
        self.assertGreater(
            open_fn.find('L10n.t("field.send"'),
            open_fn.find('sectionLabel("GET-TO-CARE")'),
        )
        self.assertRegex(
            open_fn,
            r"maxHeight:\s*1[0-6]\d",
            "open-card picture must stay short so DO and NEXT fit on the glass",
        )
        body = tab.split("var body:")[1].split("private var fieldStatus")[0]
        self.assertNotRegex(
            body,
            r"maxHeight: \.infinity\)\s+visionHUD",
            "VISION must not sit under an open card",
        )
        self.assertIn("visionHUD", tab.split("} else {", 1)[1].split("private var fieldStatus")[0])
        self.assertNotIn("visionHUD", open_fn)
        self.assertIn("Field/images", tab)
        self.assertIn("UIImage(contentsOfFile:", tab)
        self.assertTrue((ROOT / "Resources/Field/images/bleed-pack.png").is_file())
        self.assertIn("x.next()", tab)
        self.assertIn("openRoute([first.id]", tab)
        self.assertIn("speakFirst: true", tab)
        self.assertIn("speakFieldStep(", tab)
        self.assertIn("openFieldLive(", read("Blackout", "FieldSession.swift"))
        self.assertNotIn("ForEach(listCards)", tab)
        self.assertIn("NO MATCH", tab)
        self.assertIn("ASK · LIVE", read("Blackout", "FieldSession.swift"))
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
        self.assertIn("where am I", qa)
        self.assertIn("got bit", qa)
        self.assertIn("not breathing", qa)
        self.assertIn("HANDS", qa)
        self.assertIn("NEXT sits after DO", qa)
        self.assertIn("VISION stays on SEARCH", qa)
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

    def test_spoken_field_talk_opens_the_procedure(self):
        """A scared human does not type catalog ids. SEARCH still has to open a walk."""
        cards = load_book()
        first = lambda q: ask_book(cards, q)[0]["id"]
        self.assertEqual(first("where am I"), "nav-lost")
        self.assertEqual(first("where are we"), "nav-lost")
        self.assertEqual(first("I don't know where I am"), "nav-lost")
        self.assertEqual(first("donde estoy"), "nav-lost")
        self.assertEqual(first("I got bit"), "animal-bite")
        self.assertEqual(first("he got bitten"), "animal-bite")
        self.assertEqual(first("snake bit me"), "animal-bite")
        self.assertEqual(first("not breathing"), "med-cpr-adult")
        self.assertEqual(first("no pulse"), "med-cpr-adult")
        self.assertFalse(ask_book(cards, "can't breathe"))
        self.assertFalse(ask_book(cards, "I can't breathe"))
        self.assertEqual(first("broken leg"), "trauma-fracture")
        self.assertEqual(first("sprained ankle"), "trauma-fracture")
        self.assertEqual(first("cut my arm"), "med-bleed-pack")
        self.assertEqual(first("sangrando"), "med-bleed-pack")
        self.assertEqual(first("too hot"), "env-heat-collapse")
        self.assertEqual(first("soaking wet"), "env-cold")
        self.assertEqual(first("he's choking"), "med-airway")
        self.assertEqual(first("choking"), "med-airway")
        self.assertEqual(first("someone collapsed"), "med-cpr-adult")
        self.assertEqual(first("my ankle hurts"), "trauma-fracture")
        self.assertEqual(first("I fell"), "trauma-spine")
        self.assertEqual(first("donde estamos"), "nav-lost")
        self.assertFalse(ask_book(cards, "how do I"))
        self.assertFalse(ask_book(cards, "xyzzy plugh"))
        self.assertFalse(ask_book(cards, "help me"))
        self.assertFalse(ask_book(cards, "snapshot"))
        self.assertEqual(first("I can't walk"), "trauma-carry")
        self.assertEqual(first("they can't walk"), "trauma-carry")
        self.assertEqual(first("no puedo caminar"), "trauma-carry")
        self.assertEqual(first("bee stung me"), "animal-bite")
        self.assertEqual(first("I got stung"), "animal-bite")
        self.assertEqual(first("scorpion"), "animal-bite")
        self.assertEqual(first("I twisted my knee"), "trauma-fracture")
        self.assertEqual(first("I'm burned"), "med-burn")
        self.assertEqual(first("sunburn"), "med-burn")
        self.assertEqual(first("throwing up"), "med-gut")
        self.assertEqual(first("is this edible"), "plant-unknown")
        self.assertEqual(first("can I eat this"), "plant-unknown")
        self.assertEqual(first("food stuck"), "med-airway")
        self.assertEqual(first("where's camp"), "nav-lost")
        self.assertEqual(first("can't find camp"), "nav-lost")
        self.assertEqual(first("dehydration"), "water-disinfect")
        self.assertEqual(first("drink this water"), "water-disinfect")
        self.assertEqual(first("head wound"), "med-bleed-pack")
        self.assertEqual(first("me cai"), "trauma-spine")
        self.assertEqual(first("se ahoga"), "med-airway")
        self.assertEqual(first("picadura"), "animal-bite")
        self.assertEqual(first("I'm on fire"), "med-burn")
        self.assertFalse(ask_book(cards, "my chest hurts"))
        self.assertFalse(ask_book(cards, "heart attack"))
        self.assertFalse(ask_book(cards, "allergic"))
        self.assertFalse(ask_book(cards, "anaphylaxis"))
        self.assertEqual(first("walk"), "env-sky")

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


def _walk_family(toks: set[str]) -> str:
    if toks & {"infant", "baby", "newborn"} and toks & {
        "choke",
        "choking",
        "airway",
        "cpr",
        "unresponsive",
        "unconscious",
        "collapsed",
        "fainted",
        "selfchoke",
    }:
        return "infant"
    if toks & {"selfchoke"}:
        return "selfchoke"
    if toks & {"pregnant", "pregnancy"} and toks & {
        "choke",
        "choking",
        "airway",
        "cpr",
        "unresponsive",
        "unconscious",
        "collapsed",
        "fainted",
    }:
        return "pregnant"
    if "sucking" in toks or (
        toks & {"hole", "puncture"} and "chest" in toks
    ):
        return "hole"
    if "impaled" in toks or (
        "stuck" in toks
        and toks & {"wound", "bleed", "chest"}
        and not (toks & {"food", "throat", "choke"})
    ):
        return "stuck"
    if toks & {"sugar", "diabetic", "glucose"}:
        return "sugar"
    if toks & {"overdose", "narcan", "fentanyl", "opioid"}:
        return "overdose"
    if toks & {"tourniquet", "windlass"}:
        return "tight"
    if toks & {"bleed", "bleeding", "blood", "cut", "wound", "shot", "stab", "gash", "sangrando"} and not (
        toks & {"nose", "nosebleed"}
    ):
        return "bleed"
    if toks & {"cardiac", "chest"}:
        return "cardiac"
    if toks & {"allergy", "allergic", "anaphylaxis", "epipen"}:
        return "allergy"
    if toks & {"choke", "choking", "airway"}:
        return "choke"
    if toks & {"cpr", "unresponsive", "pulse", "unconscious", "collapsed", "fainted"}:
        return "cpr"
    if toks & {"drown", "drowning", "drowned"}:
        return "drown"
    if toks & {"shock"}:
        return "shock"
    if toks & {"seizure", "seizing", "convulsion"}:
        return "seizure"
    if toks & {"burn", "scald", "sunburn"}:
        return "burn"
    if toks & {"heat", "hot", "calor"}:
        return "heat"
    if toks & {"cold", "freezing", "hypothermia", "frio"}:
        return "cold"
    if toks & {"flood", "arroyo", "wash"}:
        return "flood"
    if toks & {"lightning", "thunder", "thunderstorm", "rayo"}:
        return "lightning"
    if toks & {"tornado", "twister", "storm"}:
        return "tornado"
    if toks & {"break", "broken", "broke", "sprain", "sling", "fracture"}:
        return "break"
    if toks & {"lost", "gps", "separated"}:
        return "lost"
    if toks & {"people", "civilization", "anyone", "radio", "phone"}:
        return "people"
    if toks & {"eye"}:
        return "eye"
    if toks & {"nose", "nosebleed"}:
        return "nose"
    if toks & {"deer", "hog", "javelina", "coyote", "bear", "lion", "cougar", "puma", "elk", "mammal"}:
        return "animal"
    if toks & {"stroke", "slurred", "droop"}:
        return "stroke"
    if toks & {"concussion", "head"} and not (toks & {"bleed", "wound", "nose", "nosebleed"}):
        return "head"
    if toks & {"poison", "ingested", "bleach", "overdose"} and not (toks & {"ivy", "oak", "sumac"}):
        return "poison"
    if toks & {"asthma", "inhaler", "wheezing", "wheeze"}:
        return "asthma"
    if toks & {"avalanche"}:
        return "avalanche"
    if toks & {"rip", "undertow"}:
        return "rip"
    if toks & {"breath", "breathe"}:
        return "breath"
    if toks & {"hurt", "injured", "injury"}:
        return "hurt"
    if toks & {"sick", "ill"}:
        return "sick"
    if toks & {"stay", "stable"}:
        return "stay"
    return "start"


def grounded_ask(query: str, chapter: list[dict], pack_id: str | None, locale: str) -> dict:
    picture = _picture(chapter)
    bleed_pic = _picture(chapter, "bleed-pack.png")
    toks = set(_tokens(_prepare(query)))
    asked = query.strip() or "this"
    family = _walk_family(toks)
    urgent = {
        "bleed",
        "cardiac",
        "allergy",
        "choke",
        "cpr",
        "drown",
        "stroke",
        "poison",
        "asthma",
        "avalanche",
        "rip",
        "breath",
        "hurt",
        "stay",
        "infant",
        "selfchoke",
        "pregnant",
        "hole",
        "sugar",
        "overdose",
        "tight",
        "stuck",
        "people",
    }
    start = [] if family in urgent else [
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
            _step(
                "Keep them lying down and warm while you press. Do not leave the cloth to go look for a number.",
                "Mantenlos acostados y calientes mientras presionas. No sueltes el paño para ir a buscar un número.",
                "Kneel. Both hands on the cloth. Talk to them.",
                "Arrodíllate. Las dos manos en el paño. Háblales.",
                "A bleed that waits on a phone starts again.",
                "Un sangrado que espera un teléfono vuelve a salir.",
                "Stop if trained help takes the cloth.",
                "Para si la ayuda entrenada toma el paño.",
                bleed_pic,
            ),
        ]
        care = _loc(
            "Keep pressure and get to trained help. Do not wait on a number the glass cannot dial.",
            "Sigue la presión y llega a ayuda entrenada. No esperes un número que el visor no puede marcar.",
        )
    elif family == "allergy":
        body = [
            _step(
                "If they have their own injector, use it in the outer thigh now. Hold three seconds. Do not wait to see if it 'gets better'.",
                "Si tienen su inyector, úsalo en el muslo de afuera ya. Sostén tres segundos. No esperes a ver si 'mejora'.",
                "Take the injector. Orange to the thigh. Click. Hold.",
                "Toma el inyector. Naranja al muslo. Clic. Sostén.",
                "The injector is the first move. Waiting is how a throat closes.",
                "El inyector es el primer movimiento. Esperar es cómo se cierra la garganta.",
                "If there is no injector, skip to lying them down.",
                "Si no hay inyector, pasa a acostarlos.",
                picture,
            ),
            _step(
                "Lay them down. Legs up if they can breathe. Do not make them walk or stand. Do not put anything in the mouth.",
                "Acuéstalos. Piernas arriba si pueden respirar. No los hagas caminar ni pararse. No metas nada en la boca.",
                "Jacket under the legs. Hands off the mouth.",
                "Chaqueta bajo las piernas. Manos fuera de la boca.",
                "Walking an allergic person is how they collapse. Back blows are for a block, not a swell.",
                "Hacer caminar a alguien alérgico es cómo se caen. Los golpes en la espalda son para un bloqueo, no para una hinchazón.",
                "Sit them up if they cannot breathe lying down.",
                "Siéntalos si no pueden respirar acostados.",
                picture,
            ),
            _step(
                "If they stop breathing, start hard fast compressions in the center of the chest. Stay with them.",
                "Si dejan de respirar, empieza compresiones fuertes y rápidas al centro del pecho. Quédate.",
                "Keep other children back. One person pushes.",
                "Aleja a otros niños. Una persona empuja.",
                "A closed throat becomes no pulse. Delay kills.",
                "Una garganta cerrada se vuelve sin pulso. La demora mata.",
                "Stop compressions if they cough, move, or breathe normally.",
                "Para las compresiones si tosen, se mueven o respiran normal.",
                _picture(chapter, "cpr-compress.png"),
            ),
        ]
        care = _loc(
            "Get to trained help even if they look better. A second wave can close the throat later.",
            "Llega a ayuda entrenada aunque se vean mejor. Una segunda ola puede cerrar la garganta después.",
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
            _step(
                "If the block will not move, wrap your arms around their middle from behind and pull in and up. Then back blows again.",
                "Si el bloqueo no sale, abraza su medio por detrás y tira adentro y arriba. Luego otra vez golpes en la espalda.",
                "Stand behind. Fist above the navel. Pull. Do not squeeze the ribs of a small child the same way — keep back blows.",
                "Ponte detrás. Puño sobre el ombligo. Tira. No aprietes las costillas de un niño igual — sigue con la espalda.",
                "The second move is for a block that back blows did not shift.",
                "El segundo movimiento es para un bloqueo que los golpes no movieron.",
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
            _step(
                "Keep going. Swap every two minutes if someone else can push. Do not stop to check a pulse with your fingers.",
                "Sigue. Cambia cada dos minutos si otra persona puede empujar. No pares a buscar pulso con los dedos.",
                "Count out loud. Then swap. Hands off the neck.",
                "Cuenta en voz alta. Luego cambia. Manos fuera del cuello.",
                "A pulse check with untrained fingers wastes the pumps that keep the brain.",
                "Buscar pulso con dedos sin oficio gasta las bombas que sostienen el cerebro.",
                "Stop if they breathe or trained help takes over.",
                "Para si respiran o la ayuda entrenada toma el relevo.",
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
    elif family == "people":
        body = [
            _step(
                "Open COMMS LISTEN. Face the radio. Walk toward NEAR · LOUDER. A louder radio is closer. Silence is not a house.",
                "Abre COMMS LISTEN. Enfrenta la radio. Camina hacia NEAR · LOUDER. Una radio más fuerte está más cerca. El silencio no es una casa.",
                "Tap LISTEN. Walk toward louder. Do not invent a house.",
                "Toca LISTEN. Camina hacia más fuerte. No inventes una casa.",
                "The glass cannot place a closed phone. Louder is closer. A quiet radio is farther, not gone.",
                "El visor no coloca un teléfono cerrado. Más fuerte es más cerca. Una radio quieta está más lejos, no desapareció.",
                "Stop if the path is a cliff, fire, or water you cannot cross.",
                "Para si el camino es un acantilado, fuego o agua que no puedes cruzar.",
                picture,
            ),
            _step(
                "If a LAST hop mark sits on the field, walk that street. If the hold says NO PLACE, stay visible and tap SIGNAL. Do not invent a house from a quiet radio.",
                "Si un LAST hop está en el campo, camina esa calle. Si el hold dice NO PLACE, quédate visible y toca SIGNAL. No inventes una casa desde una radio quieta.",
                "Walk the LAST mark. If there is no place, sit where people can see you.",
                "Camina la marca LAST. Si no hay lugar, siéntate donde te vean.",
                "A hop POS is the last place a Blackout phone told. RSSI is not a map pin.",
                "Un hop POS es el último sitio que un teléfono Blackout dijo. RSSI no es un pin.",
                "Stop if moving would put you in a wash, fire, or night cold you cannot survive.",
                "Para si moverte te mete en un arroyo, fuego o frío de noche que no sobrevives.",
                picture,
            ),
            _step(
                "From that spot, yell in threes and wave a bright cloth. Keep LISTEN on. Tap SIGNAL when you need to be seen.",
                "Desde ese sitio, grita de a tres y agita un paño brillante. Deja LISTEN encendido. Toca SIGNAL cuando hay que ser visto.",
                "Three yells. Then listen. Then three more.",
                "Tres gritos. Luego escucha. Luego tres más.",
                "A pattern is how people know you are a person. The radio keeps listening while you stay put.",
                "Un patrón es cómo saben que eres una persona. La radio sigue escuchando mientras te quedas.",
                "Stop yelling if you need that breath to stay warm.",
                "Deja de gritar si necesitas ese aire para no enfriar.",
                picture,
            ),
        ]
        care = _loc(
            "Stay visible. Keep LISTEN on. Do not wait on a number the glass cannot dial.",
            "Quédate visible. Deja LISTEN encendido. No esperes un número que el visor no puede marcar.",
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
    elif family == "cardiac":
        body = [
            _step(
                "Sit them still. Loosen the collar. Do not make them walk or stand to 'get air'.",
                "Siéntalos quietos. Afloja el cuello. No los hagas caminar ni pararse a 'tomar aire'.",
                "Sit next to them. Hold their hand. Do not bounce or jog them.",
                "Siéntate a su lado. Toma su mano. No los sacudas ni los hagas trotar.",
                "A working heart wants rest. Walking a chest-pain person is how they collapse.",
                "Un corazón que aún late quiere reposo. Hacer caminar a alguien con dolor de pecho es cómo se caen.",
                "If they collapse or stop breathing, go to compressions next.",
                "Si se caen o dejan de respirar, pasa a compresiones.",
                picture,
            ),
            _step(
                "Watch the chest. If they collapse or stop normal breathing, start hard fast compressions in the center of the chest.",
                "Mira el pecho. Si se caen o deja la respiración normal, empieza compresiones fuertes y rápidas al centro.",
                "Keep other children back. One person pushes.",
                "Aleja a otros niños. Una persona empuja.",
                "Chest pain can become no pulse. Delay kills.",
                "El dolor de pecho puede volverse sin pulso. La demora mata.",
                "Stop compressions if they cough, move, or breathe normally.",
                "Para las compresiones si tosen, se mueven o respiran normal.",
                _picture(chapter, "cpr-compress.png"),
            ),
            _step(
                "Stay with them. If they collapse again, go back to compressions. Do not leave them alone to 'get help'.",
                "Quédate. Si se caen otra vez, vuelve a las compresiones. No los dejes solos a 'buscar ayuda'.",
                "Sit next to them. Watch the chest.",
                "Siéntate a su lado. Mira el pecho.",
                "A person left alone with chest pain is the one who dies on the walk for help.",
                "Quien se queda solo con dolor de pecho es el que muere en el camino a pedir ayuda.",
                "Stop if trained help takes over.",
                "Para si la ayuda entrenada toma el relevo.",
                picture,
            ),
        ]
        care = _loc(
            "Get to trained help. Stay with them. Do not wait on a number the glass cannot dial.",
            "Llega a ayuda entrenada. Quédate con ellos. No esperes un número que el visor no puede marcar.",
        )
    elif family == "drown":
        body = [
            _step(
                "Get them onto land. Throw a branch or cloth. Do not go in if you cannot stand.",
                "Sácalos a tierra. Lanza una rama o un paño. No entres si no puedes hacer pie.",
                "Stay on the bank. Hold the cloth. Do not jump in after them.",
                "Quédate en la orilla. Sostén el paño. No saltes detrás.",
                "A second drowning starts when a helper goes in over their head.",
                "Un segundo ahogo empieza cuando el que ayuda entra sin pie.",
                "Stop if the water is taking you. Get back on land and yell.",
                "Para si el agua te lleva. Vuelve a tierra y grita.",
                picture,
            ),
            _step(
                "On land, tap and look at the chest. No normal breathing means hard fast compressions in the center of the chest.",
                "En tierra, toca y mira el pecho. Sin respiración normal, compresiones fuertes y rápidas al centro.",
                "Keep other children back. One person pushes.",
                "Aleja a otros niños. Una persona empuja.",
                "Water in the lungs does not change the first move. Blood still has to reach the brain.",
                "El agua en los pulmones no cambia el primer movimiento. La sangre tiene que llegar al cerebro.",
                "Roll them if they vomit. Then resume compressions.",
                "Gíralos si vomitan. Luego reanuda las compresiones.",
                _picture(chapter, "cpr-compress.png"),
            ),
            _step(
                "If they start breathing, roll them onto their side and keep them warm. Watch the chest.",
                "Si empiezan a respirar, gíralos de lado y mantenlos calientes. Mira el pecho.",
                "Jacket on the trunk. Sit by the head.",
                "Chaqueta en el tronco. Siéntate junto a la cabeza.",
                "Water can come back up. The side keeps it out of the airway.",
                "El agua puede volver. De lado no tapa el aire.",
                "If the chest stops again, go back to compressions.",
                "Si el pecho para otra vez, vuelve a las compresiones.",
                picture,
            ),
        ]
        care = _loc(
            "Get trained help even if they cough it out. Water can swell later.",
            "Consigue ayuda entrenada aunque tosan el agua. Puede hincharse después.",
        )
    elif family == "shock":
        body = [
            _step(
                "Lay them down. Keep them warm. Legs up only if they can breathe and no bone is broken.",
                "Acuéstalos. Mantenlos calientes. Piernas arriba solo si respiran y no hay hueso roto.",
                "Cover them with a jacket. Sit by their head.",
                "Cúbrelos con una chaqueta. Siéntate junto a la cabeza.",
                "Shock is the body running out of blood or heat. Flat and warm buys time.",
                "El shock es el cuerpo sin sangre o sin calor. Plano y caliente compra tiempo.",
                "Sit them up if they cannot breathe lying down.",
                "Siéntalos si no pueden respirar acostados.",
                picture,
            ),
            _step(
                "If they are bleeding, press that first. Do not give food or drink.",
                "Si sangran, presiónalo primero. No des comida ni bebida.",
                "Hands on the cloth. Not on a bottle.",
                "Manos en el paño. No en una botella.",
                "A drink they cannot swallow is how a shock case chokes.",
                "Una bebida que no pueden tragar es cómo un shock se ahoga.",
                "Stop if they vomit — roll them and keep the pressure.",
                "Para si vomitan — gíralos y sigue la presión.",
                bleed_pic,
            ),
        ]
        care = _loc(
            "Get to trained help. Stay with them. Do not wait on a number the glass cannot dial.",
            "Llega a ayuda entrenada. Quédate. No esperes un número que el visor no puede marcar.",
        )
    elif family == "seizure":
        body = [
            _step(
                "Clear hard things around them. Do not hold them down. Do not put anything in the mouth.",
                "Quita cosas duras alrededor. No los sujetes. No metas nada en la boca.",
                "Move rocks and sticks. Hands off their jaw.",
                "Mueve piedras y palos. Manos fuera de la mandíbula.",
                "A seized jaw bites a finger. Holding them breaks a bone.",
                "Una mandíbula en convulsión muerde un dedo. Sujetarlos rompe un hueso.",
                "Stop if the scene is on fire or in traffic — drag them by the clothes, not the neck.",
                "Para si hay fuego o tráfico — arrástralos de la ropa, no del cuello.",
                picture,
            ),
            _step(
                "Time it. When it stops, roll them onto their side. Stay until they talk sense.",
                "Mídele el tiempo. Cuando pare, gíralos de lado. Quédate hasta que hablen con sentido.",
                "Count out loud. Then roll. Then sit with them.",
                "Cuenta en voz alta. Luego gira. Luego siéntate con ellos.",
                "The side keeps the tongue and spit out of the airway.",
                "De lado la lengua y la saliva no tapan el aire.",
                "If it lasts longer than they can stay pink, get to care now.",
                "Si dura más de lo que pueden seguir rosados, busca cuidado ya.",
                picture,
            ),
        ]
        care = _loc(
            "Get to trained help after any first seizure, or any that repeats. Stay on their side.",
            "Llega a ayuda entrenada después de la primera convulsión o si se repite. Sigue de lado.",
        )
    elif family == "eye":
        body = [
            _step(
                "Do not rub. Rinse with clean water from the inside corner out.",
                "No frotes. Enjuaga con agua limpia del lagrimal hacia afuera.",
                "Hold the water. Tilt the head. Do not poke.",
                "Sostén el agua. Inclina la cabeza. No pinches.",
                "Rubbing scratches the eye. A rinse can float the speck out.",
                "Frotar raya el ojo. Un enjuague puede sacar la mota.",
                "Stop if the eye is cut or the pupil looks wrong — cover loose and go.",
                "Para si el ojo está cortado o la pupila se ve rara — cubre flojo y vete.",
                picture,
            ),
            _step(
                "Cover loose with a clean cloth. Do not tape the eye shut.",
                "Cubre flojo con un paño limpio. No tapes el ojo cerrado.",
                "Touch the cloth, not the eye.",
                "Toca el paño, no el ojo.",
                "Pressure on a hurt eye makes it worse.",
                "La presión en un ojo herido lo empeora.",
                "Stop if they cannot see or the pain grows — get to care.",
                "Para si no ven o el dolor crece — busca cuidado.",
                picture,
            ),
        ]
        care = _loc(
            "Get to trained help if it still hurts or they cannot see. Do not wait on a number the glass cannot dial.",
            "Llega a ayuda entrenada si aún duele o no ven. No esperes un número que el visor no puede marcar.",
        )
    elif family == "nose":
        body = [
            _step(
                "Sit up. Lean forward. Pinch the soft part of the nose. Do not tip the head back.",
                "Siéntate. Inclínate adelante. Pellizca la parte blanda de la nariz. No eches la cabeza atrás.",
                "Pinch. Lean. Breathe through the mouth.",
                "Pellizca. Inclínate. Respira por la boca.",
                "Head back dumps blood into the throat. Forward lets it out.",
                "La cabeza atrás tira sangre a la garganta. Adelante la saca.",
                "Stop if they faint or the blood will not slow — press and get care.",
                "Para si se desmayan o la sangre no afloja — aprieta y busca cuidado.",
                picture,
            ),
            _step(
                "Spit blood out. Keep the pinch for a full ten minutes. Do not pack the nose with tissue.",
                "Escupe la sangre. Sigue el pellizco diez minutos enteros. No rellenes la nariz con papel.",
                "Hold the pinch. Count. Spit.",
                "Sostén el pellizco. Cuenta. Escupe.",
                "A tissue plug is how a nosebleed becomes a choke.",
                "Un tapón de papel es cómo una hemorragia nasal se ahoga.",
                "Stop if they cannot breathe through the mouth.",
                "Para si no pueden respirar por la boca.",
                picture,
            ),
        ]
        care = _loc(
            "Get to trained help if it will not stop or they feel faint. Sit forward on the way.",
            "Llega a ayuda entrenada si no para o se marean. Adelante en el camino.",
        )
    elif family == "tornado":
        body = [
            _step(
                "Get low. A ditch or the lowest room. Not under a lone tree. Cover the head.",
                "Ponte bajo. Una zanja o el cuarto más bajo. No bajo un árbol solo. Cubre la cabeza.",
                "Lie down. Hands on the head. Cloth over the face if dirt flies.",
                "Acuéstate. Manos en la cabeza. Un paño en la cara si vuela tierra.",
                "Flying wood kills more than the wind.",
                "La madera que vuela mata más que el viento.",
                "Stop if a wall is coming down — crawl to the open ditch.",
                "Para si un muro se cae — gatea a la zanja abierta.",
                picture,
            ),
            _step(
                "Stay down until the wind has been quiet. Then move to visible ground and yell in threes.",
                "Quédate abajo hasta que el viento esté quieto. Luego muévete a tierra visible y grita de a tres.",
                "Listen. Then stand. Then three yells.",
                "Escucha. Luego párate. Luego tres gritos.",
                "A second cell can sit behind a quiet minute.",
                "Otra celda puede venir detrás de un minuto quieto.",
                "Move only if fire or flood will hit you in that ditch.",
                "Muévete solo si el fuego o la crecida te van a pegar en esa zanja.",
                picture,
            ),
        ]
        care = _loc(
            "Stay put until a known voice reaches you. Do not walk a debris field alone.",
            "Quédate hasta que una voz conocida te alcance. No camines solo entre escombros.",
        )
    elif family == "stroke":
        body = [
            _step(
                "Sit them still. Note the time. One side of the face, one arm, or speech gone wrong is enough.",
                "Siéntalos quietos. Anota la hora. Un lado de la cara, un brazo o el habla rara basta.",
                "Sit next to them. Look at the face. Say the time out loud.",
                "Siéntate a su lado. Mira la cara. Di la hora en voz alta.",
                "Time is the drug. Walking a stroke off is how the brain keeps dying.",
                "El tiempo es el fármaco. Hacer caminar un derrame es cómo el cerebro sigue muriendo.",
                "If they collapse or stop breathing, go to compressions.",
                "Si se caen o dejan de respirar, pasa a compresiones.",
                picture,
            ),
            _step(
                "Do not give food, drink, or pills. Do not make them walk. Keep them sitting or lying with the head a little up.",
                "No des comida, bebida ni pastillas. No los hagas caminar. Manténlos sentados o acostados con la cabeza un poco alta.",
                "Hands off the bottle and the pills. Hold their hand.",
                "Manos fuera de la botella y las pastillas. Toma su mano.",
                "A swallow they cannot control is how a stroke becomes a choke.",
                "Un trago que no controlan es cómo un derrame se ahoga.",
                "If they vomit, roll them onto the weak side.",
                "Si vomitan, gíralos hacia el lado débil.",
                picture,
            ),
            _step(
                "Stay with them. If they stop breathing, start hard fast compressions in the center of the chest.",
                "Quédate. Si dejan de respirar, empieza compresiones fuertes y rápidas al centro del pecho.",
                "Watch the chest. One person pushes if it stops.",
                "Mira el pecho. Una persona empuja si para.",
                "A stroke can become no pulse. Delay kills.",
                "Un derrame puede volverse sin pulso. La demora mata.",
                "Stop compressions if they breathe or trained help takes over.",
                "Para las compresiones si respiran o la ayuda entrenada toma el relevo.",
                _picture(chapter, "cpr-compress.png"),
            ),
        ]
        care = _loc(
            "Get to trained help now. Say the time it started. Do not wait on a number the glass cannot dial.",
            "Llega a ayuda entrenada ya. Di la hora en que empezó. No esperes un número que el visor no puede marcar.",
        )
    elif family == "head":
        body = [
            _step(
                "If they fell or were hit, do not move the neck. Keep the head in line with the back.",
                "Si se cayeron o los golpearon, no muevas el cuello. La cabeza en línea con la espalda.",
                "Hands on the ears. Hold the head still. Do not twist.",
                "Manos en las orejas. Sostén la cabeza quieta. No gires.",
                "A broken neck can cut the rest of the body when you sit them up.",
                "Un cuello roto puede cortar el resto del cuerpo si los sientas.",
                "Move them only if fire, water, or traffic will hit them here.",
                "Muévelos solo si el fuego, el agua o el tráfico los va a pegar aquí.",
                picture,
            ),
            _step(
                "Watch the chest. If they vomit, roll the whole body as one piece. Do not stuff a wound in the scalp.",
                "Mira el pecho. Si vomitan, gira el cuerpo entero de una pieza. No rellenes una herida en el cuero.",
                "Hold the head. Let someone else roll the hips.",
                "Sostén la cabeza. Que otro gire las caderas.",
                "Stuffing a scalp wound hides a bleed you still have to press.",
                "Rellenar el cuero esconde un sangrado que aún hay que presionar.",
                "If they stop breathing, start compressions and keep the neck still.",
                "Si dejan de respirar, empieza compresiones y sigue el cuello quieto.",
                picture,
            ),
        ]
        care = _loc(
            "Get to trained help after any knock-out or a head that will not stop bleeding. Keep the neck still on the way.",
            "Llega a ayuda entrenada si se desmayaron o la cabeza no para de sangrar. Cuello quieto en el camino.",
        )
    elif family == "poison":
        body = [
            _step(
                "Take the bottle or plant away. Do not make them vomit. Do not give milk or salt water.",
                "Quita la botella o la planta. No los hagas vomitar. No des leche ni agua con sal.",
                "Hands on the bottle. Not on their throat.",
                "Manos en la botella. No en su garganta.",
                "Forced vomit burns the throat twice and can choke them.",
                "El vómito forzado quema la garganta dos veces y puede ahogarlos.",
                "If they are already vomiting, roll them and keep the bottle.",
                "Si ya vomitan, gíralos y quédate con la botella.",
                picture,
            ),
            _step(
                "Rinse the mouth with clean water. If it is on the skin, water for fifteen minutes. Keep the container.",
                "Enjuaga la boca con agua limpia. Si está en la piel, agua quince minutos. Quédate con el envase.",
                "Hold the water. Tilt. Spit. Do not swallow the rinse.",
                "Sostén el agua. Inclina. Escupe. No tragues el enjuague.",
                "The label is what trained help reads. The rinse is what stops more going in.",
                "La etiqueta es lo que lee la ayuda. El enjuague es lo que para más entrada.",
                "Stop rinsing if they cannot swallow or cannot stay awake.",
                "Para el enjuague si no pueden tragar o no se mantienen despiertos.",
                picture,
            ),
            _step(
                "If they stop breathing, start hard fast compressions. Stay with them and the container.",
                "Si dejan de respirar, empieza compresiones fuertes y rápidas. Quédate con ellos y el envase.",
                "One person pushes. Another holds the bottle.",
                "Una persona empuja. Otra sostiene la botella.",
                "A swallowed poison can stop the chest. The bottle still has to go with them.",
                "Un veneno tragado puede parar el pecho. La botella tiene que ir con ellos.",
                "Stop compressions if they breathe or trained help takes over.",
                "Para las compresiones si respiran o la ayuda entrenada toma el relevo.",
                _picture(chapter, "cpr-compress.png"),
            ),
        ]
        care = _loc(
            "Get to trained help with the container. Do not wait on a number the glass cannot dial.",
            "Llega a ayuda entrenada con el envase. No esperes un número que el visor no puede marcar.",
        )
    elif family == "asthma":
        body = [
            _step(
                "Sit them up. Their own inhaler, two puffs, then wait. Do not make them lie flat or walk.",
                "Siéntalos. Su inhalador, dos puff, luego espera. No los acuestes ni los hagas caminar.",
                "Shake the inhaler. One puff. Breathe. Then the second.",
                "Agita el inhalador. Un puff. Respira. Luego el segundo.",
                "Flat and walking both steal the air they have left.",
                "Acostados y caminando les roban el aire que les queda.",
                "If there is no inhaler, keep them sitting and go to the next move.",
                "Si no hay inhalador, síguelos sentados y pasa al siguiente.",
                picture,
            ),
            _step(
                "If they cannot speak a full sentence, stay sitting and get to care. Watch the chest.",
                "Si no pueden decir una frase entera, sigue sentado y busca cuidado. Mira el pecho.",
                "Sit behind them. Hands on their shoulders. Count breaths out loud.",
                "Siéntate detrás. Manos en los hombros. Cuenta las respiraciones.",
                "A silent chest is the danger, not the wheeze.",
                "El peligro es el pecho silencioso, no el silbido.",
                "If the chest stops, start compressions.",
                "Si el pecho para, empieza compresiones.",
                picture,
            ),
            _step(
                "If they stop breathing, start hard fast compressions in the center of the chest. Stay sitting them up until then.",
                "Si dejan de respirar, empieza compresiones fuertes y rápidas al centro. Hasta entonces síguelos sentados.",
                "Keep other children back. One person pushes.",
                "Aleja a otros niños. Una persona empuja.",
                "An empty inhaler does not change the first move when the chest stops.",
                "Un inhalador vacío no cambia el primer movimiento cuando el pecho para.",
                "Stop compressions if they breathe or trained help takes over.",
                "Para las compresiones si respiran o la ayuda entrenada toma el relevo.",
                _picture(chapter, "cpr-compress.png"),
            ),
        ]
        care = _loc(
            "Get to trained help if two puffs do not open the chest. Sit them on the way.",
            "Llega a ayuda entrenada si dos puff no abren el pecho. Siéntalos en el camino.",
        )
    elif family == "avalanche":
        body = [
            _step(
                "Mark the last place you saw them. Dig from downhill of that mark, not from below the pile.",
                "Marca el último sitio donde los viste. Cava río abajo de esa marca, no desde abajo del montón.",
                "Plant a stick at the last-seen. Dig toward it, not under it.",
                "Clava un palo en el último visto. Cava hacia él, no debajo.",
                "Digging from below drops more snow on the face.",
                "Cavar desde abajo tira más nieve a la cara.",
                "Stop if a second slide is coming — get off the slope, then come back.",
                "Para si viene otra placa — sal de la pendiente, luego vuelve.",
                picture,
            ),
            _step(
                "Clear the face first. Then the chest. Then get them onto something dry.",
                "Limpia la cara primero. Luego el pecho. Luego ponlos en algo seco.",
                "Hands at the mouth. Then the chest. Then drag onto a pack.",
                "Manos en la boca. Luego el pecho. Luego arrastra a una mochila.",
                "Air is the first minute. Wet snow on the trunk is the second death.",
                "El aire es el primer minuto. Nieve mojada en el tronco es la segunda muerte.",
                "If they are not breathing on the dry spot, start compressions.",
                "Si no respiran en el sitio seco, empieza compresiones.",
                picture,
            ),
            _step(
                "On dry ground, tap and look at the chest. No normal breathing means hard fast compressions.",
                "En tierra seca, toca y mira el pecho. Sin respiración normal, compresiones fuertes y rápidas.",
                "Keep other children back. One person pushes.",
                "Aleja a otros niños. Una persona empuja.",
                "Snow in the lungs does not change the first move. Blood still has to reach the brain.",
                "La nieve en los pulmones no cambia el primer movimiento. La sangre tiene que llegar al cerebro.",
                "Stop if they breathe or trained help takes over.",
                "Para si respiran o la ayuda entrenada toma el relevo.",
                _picture(chapter, "cpr-compress.png"),
            ),
        ]
        care = _loc(
            "Get to trained help even if they cough it out. Stay dry and visible.",
            "Llega a ayuda entrenada aunque tosan la nieve. Sigue seco y visible.",
        )
    elif family == "rip":
        body = [
            _step(
                "Do not swim against the current. Float. Face the beach. Wave.",
                "No nades contra la corriente. Flota. Mira la playa. Saluda.",
                "On your back. Hand up. Do not fight the pull.",
                "De espaldas. Mano arriba. No pelees el tiro.",
                "A rip is a conveyor. Fighting it is how you empty the tank.",
                "Una resaca es una cinta. Pelearla es cómo se acaba el aire.",
                "If you can stand, walk out to the side, not straight in.",
                "Si haces pie, sal de lado, no derecho.",
                picture,
            ),
            _step(
                "Swim parallel to the beach until the pull lets go, then in. Do not aim at the place you left.",
                "Nada paralelo a la playa hasta que suelte, luego hacia adentro. No apuntes al sitio de donde saliste.",
                "Look down the beach. Swim that way. Then in.",
                "Mira a lo largo de la playa. Nada ahí. Luego hacia adentro.",
                "The rip is a narrow river. Sideways is out of it.",
                "La resaca es un río estrecho. De lado sales.",
                "If you cannot swim, keep floating and waving until a throw-line reaches you.",
                "Si no sabes nadar, sigue flotando y saludando hasta que llegue una cuerda.",
                picture,
            ),
            _step(
                "Once you can stand, walk out. Do not go back in for a board or a bag. Yell in threes from the sand.",
                "Cuando hagas pie, sal. No vuelvas por una tabla o una bolsa. Grita de a tres desde la arena.",
                "Walk. Then sit. Then three yells.",
                "Camina. Luego siéntate. Luego tres gritos.",
                "Most second drownings are the trip back for gear.",
                "La mayoría de los segundos ahogos son el viaje de vuelta por el equipo.",
                "If someone else is still in it, throw a branch or cloth. Do not go in if you cannot stand.",
                "Si alguien más sigue adentro, lanza una rama o un paño. No entres si no haces pie.",
                picture,
            ),
        ]
        care = _loc(
            "Stay on the sand until a known voice reaches you. Do not go back in.",
            "Quédate en la arena hasta que una voz conocida te alcance. No vuelvas al agua.",
        )
    elif family == "breath":
        body = [
            _step(
                "Sit them up if they can sit. If you are the one who cannot breathe, sit, hands on your knees. Look at the chest.",
                "Siéntalos si pueden sentarse. Si eres tú quien no puede respirar, siéntate, manos en las rodillas. Mira el pecho.",
                "Hands on their shoulders — or on your own knees. Watch the mouth.",
                "Manos en sus hombros — o en tus rodillas. Mira la boca.",
                "Sitting opens the chest. Lying flat steals the air they have left.",
                "Sentados abre el pecho. Acostados les roba el aire que les queda.",
                "If they collapse or the chest stops, tap CPR.",
                "Si se caen o el pecho para, toca CPR.",
                picture,
            ),
            _step(
                "Ask: can you cough? Can you say a word? If they cannot, tap CHOKE. Do not put fingers in the mouth.",
                "Pregunta: ¿puedes toser? ¿Puedes decir una palabra? Si no pueden, toca CHOKE. No metas los dedos en la boca.",
                "Listen. Watch the mouth. Hands off the throat.",
                "Escucha. Mira la boca. Manos fuera de la garganta.",
                "A person who can cough still has an open throat. A silent chest is the block.",
                "Quien puede toser aún tiene la garganta abierta. Un pecho silencioso es el bloqueo.",
                "If the face or tongue is swelling, tap ALLERGY now.",
                "Si la cara o la lengua hinchan, toca ALLERGY ya.",
                picture,
            ),
            _step(
                "Loosen the collar. Do not make them walk. Do not lay them flat if they are fighting for air. Wheeze and an inhaler: tap ASTHMA. Chest pain: tap HEART. Chest stopped: tap CPR.",
                "Afloja el cuello. No los hagas caminar. No los acuestes si pelean por aire. Silbido e inhalador: toca ASTHMA. Dolor de pecho: toca HEART. Pecho parado: toca CPR.",
                "Hands on the collar, not on a bottle. Stay next to them.",
                "Manos en el cuello, no en una botella. Quédate a su lado.",
                "Walking and lying flat both steal the air. The cause chips are the next move.",
                "Caminar y acostarse roban el aire. Las fichas de causa son el siguiente movimiento.",
                "If none of those is it and they still breathe, tap STAY.",
                "Si ninguna es y aún respiran, toca STAY.",
                picture,
            ),
        ]
        care = _loc(
            "Get to trained help. Stay sitting. Do not wait on a number the glass cannot dial.",
            "Llega a ayuda entrenada. Sigue sentado. No esperes un número que el visor no puede marcar.",
        )
    elif family == "hurt":
        body = [
            _step(
                "Look for blood you can see and whether the chest is moving. If fire, traffic, or falling rock will hit them, move them. Else stay.",
                "Busca sangre que se vea y si el pecho se mueve. Si el fuego, el tráfico o una roca los va a pegar, muévelos. Si no, quédate.",
                "Eyes on the body. Then one hand. Then the cause chips.",
                "Ojos en el cuerpo. Luego una mano. Luego las fichas de causa.",
                "Bleed and breath kill first. The rest can wait one look.",
                "Sangrado y aire matan primero. El resto puede esperar una mirada.",
                "If the scene is still hitting them, move, then look again.",
                "Si la escena aún los pega, muévete, luego mira otra vez.",
                picture,
            ),
            _step(
                "Blood you can see: tap BLEED and press now. Silent chest or no air: tap BREATH or CPR.",
                "Sangre que se ve: toca BLEED y presiona ya. Pecho silencioso o sin aire: toca BREATH o CPR.",
                "Hands on the cloth or on the shoulders. Not both at once.",
                "Manos en el paño o en los hombros. No las dos a la vez.",
                "A bleed that waits on a guess restarts. A silent chest becomes no pulse.",
                "Un sangrado que espera una duda vuelve. Un pecho silencioso se vuelve sin pulso.",
                "If they are talking and the blood is a trickle, keep looking.",
                "Si hablan y la sangre es un hilo, sigue mirando.",
                bleed_pic,
            ),
            _step(
                "Head hit or knocked out: tap HEAD. Fell or the neck hurts: tap NECK. A bone that will not hold: tap BREAK. Burned skin: tap BURN. A bite or sting: tap BITE. None of those: tap STAY.",
                "Golpe en la cabeza o desmayo: toca HEAD. Cayó o duele el cuello: toca NECK. Un hueso que no sostiene: toca BREAK. Piel quemada: toca BURN. Mordida o picadura: toca BITE. Nada de eso: toca STAY.",
                "Name the next chip out loud. Then tap it.",
                "Di la ficha en voz alta. Luego tócala.",
                "The chips are the rest of the walk. Guessing past a bleed wastes the minute.",
                "Las fichas son el resto del camino. Adivinar pasado un sangrado gasta el minuto.",
                "If they fade, go back to BLEED or CPR.",
                "Si se apagan, vuelve a BLEED o CPR.",
                picture,
            ),
        ]
        care = _loc(
            "Get to trained help. Keep pressure and the airway on the way.",
            "Llega a ayuda entrenada. Sigue la presión y la vía aérea en el camino.",
        )
    elif family == "sick":
        body = [
            _step(
                "Sit them in shade. Loosen cloth. Ask: what hurts, and can they talk sense?",
                "Siéntalos a la sombra. Afloja la ropa. Pregunta: qué duele, y ¿hablan con sentido?",
                "Hands on the shoulders. Listen. Watch the face.",
                "Manos en los hombros. Escucha. Mira la cara.",
                "Sense and sweat tell heat from a stroke from a gut.",
                "El sentido y el sudor dicen calor, derrame o estómago.",
                "If they collapse, tap CPR.",
                "Si se caen, toca CPR.",
                picture,
            ),
            _step(
                "Hot and confused: tap HEAT. Wet and shaking: tap COLD. Face, arm, or speech gone: tap STROKE. Swell or sting: tap ALLERGY. Shaking they cannot stop: tap SEIZURE.",
                "Calor y confusión: toca HEAT. Mojado y temblando: toca COLD. Cara, brazo o habla rara: toca STROKE. Hincha o picadura: toca ALLERGY. Temblor que no para: toca SEIZURE.",
                "Name the chip. Then tap it. Stay next to them.",
                "Di la ficha. Luego tócala. Quédate a su lado.",
                "The first matching cause is the walk. Stacking causes skips the one that is killing them.",
                "La primera causa que cabe es el camino. Apilar causas se salta la que los mata.",
                "If they start to vomit, roll them and keep going.",
                "Si vomitan, gíralos y sigue.",
                picture,
            ),
            _step(
                "Throwing up: roll them onto their side. No food. Watch the chest. Gut pain or diarrhea: tap GUT. A bottle or plant they swallowed: tap POISON. None of those: tap STAY.",
                "Si vomitan: gíralos de lado. Sin comida. Mira el pecho. Dolor de panza o diarrea: toca GUT. Una botella o planta que tragaron: toca POISON. Nada de eso: toca STAY.",
                "Hands on the shoulder. Roll. Then sit.",
                "Manos en el hombro. Gira. Luego siéntate.",
                "A swallow they cannot control is how sick becomes a choke.",
                "Un trago que no controlan es cómo un enfermo se ahoga.",
                "If the chest stops, tap CPR.",
                "Si el pecho para, toca CPR.",
                picture,
            ),
        ]
        care = _loc(
            "Get to trained help if they will not wake, will not make sense, or cannot keep water down.",
            "Llega a ayuda entrenada si no despiertan, no tienen sentido o no retienen agua.",
        )
    elif family == "stay":
        body = [
            _step(
                "They are breathing. If they will not stay awake, roll them onto their side. Tilt the head so the tongue is off the throat.",
                "Están respirando. Si no se mantienen despiertos, gíralos de lado. Inclina la cabeza para que la lengua no tape la garganta.",
                "Hands on the shoulder and the hip. Roll as one piece.",
                "Manos en el hombro y la cadera. Gira de una pieza.",
                "The side keeps spit and the tongue out of the airway.",
                "De lado la saliva y la lengua no tapan el aire.",
                "If the chest stops, tap CPR.",
                "Si el pecho para, toca CPR.",
                picture,
            ),
            _step(
                "Jacket on the trunk. Shade or a windbreak. No food, no drink, no alcohol.",
                "Chaqueta en el tronco. Sombra o un rompeviento. Sin comida, sin bebida, sin alcohol.",
                "Cover the trunk. Hands off the bottle.",
                "Cubre el tronco. Manos fuera de la botella.",
                "A drink they cannot swallow is how a stable person chokes. Alcohol dumps the last heat.",
                "Una bebida que no pueden tragar es cómo un estable se ahoga. El alcohol tira el último calor.",
                "If they start to shake from cold, add a layer. If they overheat, shade and fan.",
                "Si tiemblan de frío, otra capa. Si se calientan, sombra y abanico.",
                picture,
            ),
            _step(
                "Watch the chest. If it stops, tap CPR. Stay visible. Yell in threes. Do not leave them.",
                "Mira el pecho. Si para, toca CPR. Quédate visible. Grita de a tres. No los dejes.",
                "Sit by the head. Count breaths out loud.",
                "Siéntate junto a la cabeza. Cuenta las respiraciones.",
                "A person left alone is the one who dies on the walk for help.",
                "Quien se queda solo es el que muere en el camino a pedir ayuda.",
                "Stop if trained help takes over.",
                "Para si la ayuda entrenada toma el relevo.",
                picture,
            ),
        ]
        care = _loc(
            "Stay with them until a known voice reaches you. Do not wait on a number the glass cannot dial.",
            "Quédate hasta que una voz conocida te alcance. No esperes un número que el visor no puede marcar.",
        )
    elif family == "infant":
        body = [
            _step(
                "A baby. Face down on your forearm. Five hard back blows. Then look in the mouth.",
                "Un bebé. Boca abajo en tu antebrazo. Cinco golpes en la espalda. Luego mira la boca.",
                "Support the head. Hits go to the back, not the neck.",
                "Sostén la cabeza. Golpes a la espalda, no al cuello.",
                "A baby airway is short. Belly thrusts crush it.",
                "La vía de un bebé es corta. Los empujes al vientre la aplastan.",
                "If they cry, stop. If limp, chest thrusts.",
                "Si lloran, para. Si quedan flojos, empujes al pecho.",
                picture,
            ),
            _step(
                "Face up. Two fingers in the center of the chest. Five chest thrusts, not the belly.",
                "Boca arriba. Dos dedos al centro. Cinco empujes al pecho, no el vientre.",
                "Say the count. Two fingers.",
                "Di la cuenta. Dos dedos.",
                "Chest thrusts move a block a belly thrust would lodge.",
                "El pecho mueve un bloqueo que el vientre clavaría.",
                "If limp, infant compressions.",
                "Si quedan flojos, compresiones de bebé.",
                picture,
            ),
            _step(
                "If the chest has stopped: two fingers, one third deep, one hundred to one hundred twenty a minute.",
                "Si el pecho paró: dos dedos, un tercio, cien a ciento veinte.",
                "Say the count. Do not shake the baby.",
                "Di la cuenta. No sacudas al bebé.",
                "Two fingers. Not a palm.",
                "Dos dedos. No la palma.",
                "Stop if they cry or breathe.",
                "Para si lloran o respiran.",
                picture,
            ),
        ]
        care = _loc("Get trained help even if they cry it out.", "Consigue ayuda aunque lloren el bloqueo.")
    elif family == "selfchoke":
        body = [
            _step(
                "If you can cough, keep coughing. Then fist above the navel. Bend over a chair back and drive in and up.",
                "Si puedes toser, tose. Luego puño sobre el ombligo. Inclínate sobre un respaldo y empuja adentro y arriba.",
                "Fist. Chair. Drive.",
                "Puño. Silla. Empuja.",
                "The chair is the other pair of hands.",
                "La silla es el otro par de manos.",
                "If you fade, get to the floor.",
                "Si te apagas, al piso.",
                picture,
            ),
            _step(
                "Repeat until air moves. Do not put fingers in your mouth.",
                "Repite hasta que pase el aire. No metas los dedos.",
                "Drive. Count.",
                "Empuja. Cuenta.",
                "Air can still move if you cough.",
                "El aire aún pasa si toses.",
                "If someone is there and you go down, they start CPR.",
                "Si hay alguien y te caes, ellos empiezan RCP.",
                picture,
            ),
            _step(
                "If air is moving, sit and watch your chest. Do not eat or drink.",
                "Si el aire pasa, siéntate y mira tu pecho. No comas ni bebas.",
                "Hands on your knees.",
                "Manos en las rodillas.",
                "A second swell can close what you just opened.",
                "Una segunda hinchazón puede cerrar lo que abriste.",
                "Stay visible.",
                "Quédate visible.",
                picture,
            ),
        ]
        care = _loc("Get trained help even if the block comes out.", "Consigue ayuda aunque salga el bloqueo.")
    elif family == "pregnant":
        body = [
            _step(
                "If they can cough, let them. If silent: five back blows, then five chest thrusts, not the belly.",
                "Si pueden toser, déjalos. Si silencio: cinco en la espalda, luego cinco en el pecho, no el vientre.",
                "Chest, not the belly.",
                "Pecho, no el vientre.",
                "A belly thrust on a pregnant belly hits the wrong thing.",
                "Un empuje al vientre en un embarazo pega donde no es.",
                "If they go down, CPR a little higher on the chest.",
                "Si se caen, RCP un poco más arriba.",
                picture,
            ),
            _step(
                "If they go down: hard fast compressions a little higher than usual.",
                "Si se caen: compresiones un poco más arriba.",
                "Say the count.",
                "Di la cuenta.",
                "Blood still has to reach two bodies.",
                "La sangre tiene que llegar a dos cuerpos.",
                "Stop if they breathe.",
                "Para si respiran.",
                picture,
            ),
            _step(
                "If they breathe again, roll them onto the left side. Watch the chest.",
                "Si vuelven a respirar, gíralos al lado izquierdo. Mira el pecho.",
                "Left side. Watch.",
                "Lado izquierdo. Vigila.",
                "Left side keeps blood moving.",
                "El lado izquierdo sigue la sangre.",
                "If the chest stops again, go back to compressions.",
                "Si el pecho para otra vez, vuelve a las compresiones.",
                picture,
            ),
        ]
        care = _loc("Get trained help. Two patients.", "Consigue ayuda. Dos pacientes.")
    elif family == "hole":
        body = [
            _step(
                "Sit them if they want. Cover the hole with a palm, then plastic. Leave one side open so air can get out.",
                "Siéntalos si quieren. Cubre el hueco con la palma, luego plástico. Deja un lado abierto.",
                "Palm first. Then the seal. Three sides.",
                "Primero la palma. Luego el sello. Tres lados.",
                "A four-side patch can trap air and drop the lung.",
                "Un parche de cuatro lados atrapa aire y tira el pulmón.",
                "If they get worse, lift a corner.",
                "Si empeoran, levanta una esquina.",
                picture,
            ),
            _step(
                "Keep the seal. Do not make them walk. Watch the chest.",
                "Sigue el sello. No los hagas caminar. Mira el pecho.",
                "Stay still. I have the hole.",
                "Quieto. Tengo el hueco.",
                "Walking a sucking chest is how they collapse.",
                "Caminar un pecho que chupa es cómo se caen.",
                "If the chest stops, start CPR.",
                "Si el pecho para, empieza RCP.",
                picture,
            ),
            _step(
                "If they fade, lay them on the injured side. Keep the three-side seal.",
                "Si se apagan, acuéstalos del lado herido. Sigue el sello de tres lados.",
                "Injured side down.",
                "Lado herido abajo.",
                "Injured side down keeps blood in the good lung.",
                "El lado herido abajo deja la sangre en el pulmón bueno.",
                "If the chest stops, start CPR.",
                "Si el pecho para, empieza RCP.",
                picture,
            ),
        ]
        care = _loc("Get to trained help now. Keep the three-side seal.", "Llega a ayuda ya. Sigue el sello de tres lados.")
    elif family == "sugar":
        body = [
            _step(
                "If they can sit and swallow, give them sugar they already have: juice, gel, or four teaspoons. Do not force it.",
                "Si pueden sentarse y tragar, dales azúcar: jugo, gel o cuatro cucharaditas. No lo fuerces.",
                "Sip this. Hold the cup. Do not pour it down.",
                "Sorbe esto. Sostén el vaso. No lo viertas.",
                "A swallow they cannot control is a choke.",
                "Un trago que no controlan es un ahogo.",
                "If they cannot swallow, nothing in the mouth.",
                "Si no tragan, nada en la boca.",
                picture,
            ),
            _step(
                "Wait. If they will not wake, roll them onto their side. Nothing in the mouth.",
                "Espera. Si no despiertan, gíralos de lado. Nada en la boca.",
                "Roll as one piece.",
                "Gira de una pieza.",
                "Gel in an unconscious mouth is a choke.",
                "Gel en una boca inconsciente es un ahogo.",
                "If the chest stops, tap CPR.",
                "Si el pecho para, toca CPR.",
                picture,
            ),
            _step(
                "Stay with them. If they seize, tap SEIZURE. If the chest stops, tap CPR.",
                "Quédate. Si convulsiónan, toca SEIZURE. Si el pecho para, toca CPR.",
                "Watch the chest.",
                "Mira el pecho.",
                "A second crash comes when they walk it off.",
                "Un segundo bajón viene cuando lo caminan.",
                "Stop if trained help takes over.",
                "Para si la ayuda entrenada toma el relevo.",
                picture,
            ),
        ]
        care = _loc("Get to trained help if they will not wake.", "Llega a ayuda si no despiertan.")
    elif family == "overdose":
        body = [
            _step(
                "If they have their own naloxone, use it now. Then roll them onto their side.",
                "Si tienen su naloxona, úsala ya. Luego gíralos de lado.",
                "Give the kit. Then roll.",
                "Da el kit. Luego gira.",
                "Waiting is how a chest stops.",
                "Esperar es cómo para el pecho.",
                "If no kit, side and watch the chest.",
                "Si no hay kit, de lado y mira el pecho.",
                picture,
            ),
            _step(
                "Watch the chest for ten seconds. No normal breathing means hard fast compressions.",
                "Mira el pecho diez segundos. Sin respiración normal, compresiones fuertes y rápidas.",
                "Say the count.",
                "Di la cuenta.",
                "The kit still has to go with them.",
                "El kit tiene que ir con ellos.",
                "Stop if they breathe.",
                "Para si respiran.",
                picture,
            ),
            _step(
                "A second naloxone after three minutes if they have it and they are still out. Keep the kit with them.",
                "Una segunda naloxona a los tres minutos si tienen y siguen fuera. El kit va con ellos.",
                "Keep the kit.",
                "Quédate con el kit.",
                "They can stop again after they wake.",
                "Pueden parar otra vez después de despertar.",
                "Stop if trained help takes over.",
                "Para si la ayuda entrenada toma el relevo.",
                picture,
            ),
        ]
        care = _loc("Get to trained help with the kit.", "Llega a ayuda con el kit.")
    elif family == "tight":
        body = [
            _step(
                "Windlass two to three inches above the wound, not on a joint. Twist until the bleed slows. Write the time.",
                "Torniquete cinco a siete centímetros arriba, no en articulación. Gira. Escribe la hora.",
                "This will hurt. Twist. Note the time.",
                "Va a doler. Gira. Di la hora.",
                "A loose strap is jewelry.",
                "Una correa floja es adorno.",
                "Never on the neck. Never loosen it to check.",
                "Nunca en el cuello. Nunca lo aflojes.",
                picture,
            ),
            _step(
                "Keep the twist. Keep them warm. No food.",
                "Sigue el giro. Mantenlos calientes. Sin comida.",
                "Do not let it unwind.",
                "Que no se suelte.",
                "Loosening is how they bleed out.",
                "Aflojar es cómo se desangran.",
                "If they fade, tap SHOCK.",
                "Si se apagan, toca SHOCK.",
                picture,
            ),
            _step(
                "Never loosen it to check. Watch the chest.",
                "Nunca lo aflojes para mirar. Mira el pecho.",
                "Hold the twist.",
                "Sostén el giro.",
                "Checking is how they bleed out.",
                "Mirar es cómo se desangran.",
                "If the chest stops, tap CPR.",
                "Si el pecho para, toca CPR.",
                picture,
            ),
        ]
        care = _loc("Get to trained help with the time you wrote.", "Llega a ayuda con la hora que escribiste.")
    elif family == "stuck":
        body = [
            _step(
                "Leave the object where it is. Pack cloth around it. Do not pull it out.",
                "Deja el objeto. Tapa alrededor. No lo saques.",
                "Do not pull it. Hold the cloth.",
                "No lo saques. Sostén la tela.",
                "The object is the plug.",
                "El objeto es el tapón.",
                "If the chest sucks, tap HOLE.",
                "Si el pecho chupa, toca HOLE.",
                picture,
            ),
            _step(
                "Press around the object, not on it. Keep them still.",
                "Presiona alrededor, no encima. Mantenlos quietos.",
                "Stay still. I have the wound.",
                "Quieto. Tengo la herida.",
                "Pulling it opens the vessel.",
                "Sacarlo abre el vaso.",
                "If they fade, tap SHOCK.",
                "Si se apagan, toca SHOCK.",
                picture,
            ),
            _step(
                "Carry them if you can. The object stays. Watch the chest.",
                "Cárgalos si puedes. El objeto se queda. Mira el pecho.",
                "Hold the pack. Move the body.",
                "Sostén el tapón. Mueve el cuerpo.",
                "A pulled object is a bleed you cannot put back.",
                "Un objeto sacado es un sangrado que no puedes devolver.",
                "Stop if trained help takes the wound.",
                "Para si la ayuda entrenada toma la herida.",
                picture,
            ),
        ]
        care = _loc("Get to trained help with the object still in.", "Llega a ayuda con el objeto aún dentro.")
    else:
        body = [
            _step(
                "If someone is hurt: stop bleeding or start breaths first. If no one is hurt, stay visible and stay with the party.",
                "Si alguien está herido: para el sangrado o empieza respiraciones primero. Si nadie está herido, quédate visible y con el grupo.",
                "Look at the person. Then one hand move. Then tap NEXT.",
                "Mira a la persona. Luego un movimiento. Luego toca NEXT.",
                "The first job is the thing that is killing them. Stacking jobs skips that.",
                "Lo primero es lo que los está matando. Apilar tareas se salta eso.",
                "Stop if you cannot see, cannot stand, or cannot hear.",
                "Para si no ves, no te sostienes o no oyes.",
                picture,
            ),
            _step(
                "From that spot, yell in threes and wave a bright cloth. Do not wander. Do not eat wild plants. Do not drink untreated water.",
                "Desde ese sitio, grita de a tres y agita un paño brillante. No deambules. No comas plantas silvestres. No bebas agua sin tratar.",
                "Three yells. Then sit. Hands off plants and standing water.",
                "Tres gritos. Luego siéntate. Manos fuera de plantas y agua estancada.",
                "Searchers walk a line. Unknown plants and untreated water make two problems.",
                "Los buscadores caminan una línea. Plantas desconocidas y agua sin tratar hacen dos problemas.",
                "Stop if you feel faint. Sit. Yell.",
                "Para si te desmayas. Siéntate. Grita.",
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
    return _attach_links(
        {
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
        },
        query,
    )


def _link(cid: str, label: str, en: str, es: str, ask: str) -> dict:
    return {"id": cid, "label": label, "when": _loc(en, es), "ask": ask}


_FORK = {
    "CHOKE": _link("med-airway", "CHOKE", "Cannot cough or speak", "No puede toser ni hablar", "choking"),
    "ALLERGY": _link("live-allergy", "ALLERGY", "Face or throat swelling", "Cara o garganta hinchada", "anaphylaxis"),
    "ASTHMA": _link("live-asthma", "ASTHMA", "Wheeze, has an inhaler", "Silbido, tiene inhalador", "asthma"),
    "HEART": _link("live-cardiac", "HEART", "Chest pain or pressure", "Dolor o presión en el pecho", "heart attack"),
    "SMOKE": _link("env-smoke", "SMOKE", "Fire or thick smoke", "Fuego o humo espeso", "smoke"),
    "DROWN": _link("live-drown", "DROWN", "Water in the chest", "Agua en el pecho", "drowning"),
    "CPR": _link("med-cpr-adult", "CPR", "Chest has stopped", "El pecho paró", "not breathing"),
    "STAY": _link("live-stay", "STAY", "Still breathing, none of these", "Aún respira, ninguna de estas", "keep them stable"),
    "BLEED": _link("med-bleed-pack", "BLEED", "Blood you can see", "Sangre que se ve", "bleeding out"),
    "BREATH": _link("live-breath", "BREATH", "Fighting for air", "Pelea por aire", "can't breathe"),
    "HEAD": _link("live-head", "HEAD", "Hit or knocked out", "Golpe o desmayo", "hit my head"),
    "NECK": _link("trauma-spine", "NECK", "Fell or the neck hurts", "Cayó o duele el cuello", "I fell and my neck hurts"),
    "BREAK": _link("trauma-fracture", "BREAK", "Bone will not hold", "El hueso no sostiene", "broken leg"),
    "BURN": _link("med-burn", "BURN", "Burned skin", "Piel quemada", "I'm burned"),
    "BITE": _link("animal-bite", "BITE", "Bite or sting", "Mordida o picadura", "got bit"),
    "HEAT": _link("env-heat-collapse", "HEAT", "Hot, confused, no sweat", "Calor, confusión, no suda", "heat stroke"),
    "COLD": _link("env-cold", "COLD", "Wet, shaking, slowing", "Mojado, temblando, lento", "hypothermia"),
    "STROKE": _link("live-stroke", "STROKE", "Face, arm, or speech gone", "Cara, brazo o habla rara", "stroke"),
    "GUT": _link("med-gut", "GUT", "Vomiting or diarrhea", "Vómito o diarrea", "diarrhea"),
    "POISON": _link("live-poison", "POISON", "Swallowed a bottle or plant", "Tragó una botella o planta", "swallowed bleach"),
    "SHOCK": _link("live-shock", "SHOCK", "Pale, cold, fading", "Pálido, frío, se apaga", "they are in shock"),
    "NOSE": _link("live-nose", "NOSE", "Blood from the nose", "Sangre de la nariz", "nosebleed"),
    "SEIZURE": _link("live-seizure", "SEIZURE", "Shaking, not holding them", "Temblando, no los sujetes", "seizure"),
    "SIGNAL": _link("sig-mirror", "SIGNAL", "Need to be seen", "Hay que ser visto", "how do I get rescued"),
    "INFANT": _link("live-infant", "INFANT", "Baby, under one year", "Bebé, menos de un año", "baby choking"),
    "SELF": _link("live-selfchoke", "SELF", "You are the one choking", "Tú eres quien se ahoga", "choking on my own"),
    "PREGNANT": _link("live-pregnant", "PREGNANT", "Belly you cannot reach around", "Vientre que no alcanzas", "pregnant choking"),
    "TIGHT": _link("med-bleed-pack", "TIGHT", "Limb pouring, windlass next", "Extremidad que chorrea, torniquete", "tourniquet"),
    "HOLE": _link("live-hole", "HOLE", "Chest sucking air", "Pecho que chupa aire", "sucking chest"),
    "STUCK": _link("live-stuck", "STUCK", "Object still in the wound", "Objeto aún en la herida", "impaled"),
    "DOSE": _link("live-overdose", "DOSE", "Pills or powder, very small pupils", "Pastillas o polvo, pupilas muy chicas", "overdose"),
    "SUGAR": _link("live-sugar", "SUGAR", "Known diabetic, shaky, fading", "Diabético, temblor, se apaga", "low blood sugar"),
}

_BREATH_FORKS = ("CHOKE", "ALLERGY", "ASTHMA", "HEART", "SMOKE", "DROWN", "CPR", "STAY")
_HURT_FORKS = ("BLEED", "BREATH", "CPR", "HEAD", "NECK", "BREAK", "BURN", "BITE", "STAY")
_SICK_FORKS = ("HEAT", "COLD", "STROKE", "ALLERGY", "SUGAR", "GUT", "POISON", "SEIZURE", "STAY")
_FAMILY_FORKS = {
    "breath": _BREATH_FORKS,
    "hurt": _HURT_FORKS,
    "sick": _SICK_FORKS,
    "stay": ("CPR", "BLEED"),
    "choke": ("INFANT", "SELF", "PREGNANT", "ALLERGY", "ASTHMA", "BREATH", "CPR", "STAY"),
    "infant": ("CPR", "CHOKE", "STAY"),
    "selfchoke": ("CHOKE", "CPR", "STAY"),
    "pregnant": ("CPR", "ALLERGY", "STAY"),
    "cardiac": ("BREATH", "CPR", "STAY"),
    "allergy": ("BREATH", "CPR", "STAY"),
    "asthma": ("BREATH", "ALLERGY", "CPR", "STAY"),
    "cpr": ("INFANT", "DOSE", "BREATH", "SEIZURE", "SHOCK", "STAY"),
    "bleed": ("TIGHT", "HOLE", "SHOCK", "STUCK", "STAY"),
    "tight": ("SHOCK", "HOLE", "STAY"),
    "hole": ("CPR", "SHOCK", "STAY"),
    "stuck": ("BLEED", "SHOCK", "STAY"),
    "shock": ("BLEED", "CPR", "STAY"),
    "drown": ("CPR", "STAY"),
    "stroke": ("CPR", "STAY"),
    "head": ("CPR", "BLEED", "NECK", "STAY"),
    "poison": ("DOSE", "CPR", "STAY"),
    "overdose": ("CPR", "STAY"),
    "sugar": ("SEIZURE", "STAY"),
    "seizure": ("CPR", "SUGAR", "STAY"),
    "burn": ("BREATH", "STAY"),
    "heat": ("STROKE", "CPR", "STAY"),
    "cold": ("CPR", "STAY"),
    "nose": ("BLEED", "STAY"),
    "flood": ("DROWN", "STAY"),
    "lightning": ("CPR", "BURN", "STAY"),
    "tornado": ("CPR", "STAY"),
    "break": ("BLEED", "SHOCK", "STAY"),
    "lost": ("SIGNAL", "STAY"),
    "people": ("SIGNAL", "STAY"),
    "eye": ("STAY",),
    "animal": ("BITE", "STAY"),
    "avalanche": ("CPR", "COLD", "STAY"),
    "rip": ("DROWN", "STAY"),
    "start": ("BLEED", "BREATH", "STAY"),
}


def _presentation(toks: set[str]) -> str | None:
    if toks & {"choke", "choking", "airway"}:
        return None
    if toks & {"allergy", "allergic", "anaphylaxis", "epipen"}:
        return None
    if toks & {"asthma", "inhaler", "wheezing", "wheeze"}:
        return None
    if toks & {"cardiac", "chest"}:
        return None
    if toks & {"cpr", "unresponsive", "pulse", "unconscious", "collapsed", "fainted"}:
        return None
    if toks & {"infant", "baby", "newborn"}:
        return None
    if toks & {"selfchoke", "pregnant", "hole", "sugar", "overdose", "stuck"}:
        return None
    if toks & {"stable", "stabilize"}:
        return "stay"
    if toks & {"stay"} and not (toks & {"cold", "heat", "warm", "cool"}):
        return "stay"
    if toks & {"breath", "breathe"}:
        return "breath"
    if toks & {"hurt", "injured", "injury"}:
        return "hurt"
    if toks & {"sick", "ill"}:
        return "sick"
    return None


def _attach_links(card: dict, query: str) -> dict:
    toks = set(_tokens(_prepare(query)))
    cid = card.get("id")
    if cid and cid != LIVE_ID:
        labels = ()
    else:
        tree = _presentation(toks)
        if tree == "breath":
            labels = _BREATH_FORKS
        elif tree == "hurt":
            labels = _HURT_FORKS
        elif tree == "sick":
            labels = _SICK_FORKS
        elif tree == "stay":
            labels = ("CPR",)
        else:
            labels = _FAMILY_FORKS.get(_walk_family(toks), ("STAY",))
    out = dict(card)
    out["links"] = [_FORK[name] for name in labels]
    return out


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
        "Never edible. Never a drinkable number. Never a phone number or a tel link. "
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
    if not _tokens(_prepare(query)):
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
        panic = answer_ask("help me", book, "en", "west", "tx-west", None)
        self.assertIsNotNone(panic)
        assert panic is not None
        self.assertEqual(panic["id"], LIVE_ID)
        first = panic["steps"][0]["do"]["en"].lower()
        self.assertTrue(any(n in first for n in ("blood", "bleed", "chest")), first)
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
        allergy = grounded_ask("anaphylaxis", book, "tx-west", "en")
        allergy_blob = json.dumps(allergy).lower()
        self.assertIn("thigh", allergy_blob)
        self.assertNotIn("between the shoulders", allergy_blob)
        self.assertGreaterEqual(len(allergy["steps"]), 4)
        cpr = grounded_ask("not breathing", book, "tx-west", "en")
        self.assertIn("compression", json.dumps(cpr).lower())
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
        session = read("Blackout", "FieldSession.swift")
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
        self.assertNotIn(
            "let picture = picture(",
            ask,
            "local picture shadows picture(chapter:) and will not compile on device",
        )
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
        self.assertNotIn("import llama", llama)
        self.assertIn("static func complete(", llama)
        self.assertIn("return nil", llama)
        self.assertNotIn("llama_model_load_from_file", llama)
        self.assertNotIn("print(", llama)
        self.assertNotIn("URLSession", llama)
        self.assertNotIn('name: "llama"', pkg)
        self.assertNotIn("llama-b8638-xcframework.zip", pkg)
        self.assertNotIn(".binaryTarget", pkg)
        self.assertIn('.iOS("18.0")', pkg)
        self.assertNotIn("watchOS", pkg)
        self.assertIn("import FieldAsk", tab)
        self.assertIn("openFieldLive(", session)
        self.assertIn("FieldAsk.answer", session)
        self.assertIn("Task.detached", session)
        self.assertIn("ASK · LIVE", session)
        self.assertIn("askBusy", session)
        open_ans = tab.split("private func openAnswer(")[1].split("private func jump")[0]
        self.assertIn("listCards.first", open_ans)
        self.assertIn("openRoute([first.id]", open_ans)
        self.assertIn("speakFirst: true", open_ans)
        self.assertIn("beginFieldAsk", open_ans)
        self.assertIn("cancelFieldAsk", open_ans)
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
