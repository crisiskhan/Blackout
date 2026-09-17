import Foundation
import FieldCorpus

public enum FieldAsk {
    public static let modelFile = "Dolphin3.0-Llama3.2-3B-Q4_K_M.gguf"
    public static let missing = "NO ASK MODEL"
    public static let liveID = "ask-live"

    private static let childHandsEn = "Do this one move with your hands. Then tap NEXT."
    private static let childHandsEs = "Haz este único movimiento con las manos. Luego toca NEXT."

    public static func modelURL(in resourceRoot: URL?) -> URL? {
        if let root = resourceRoot {
            let file = root.appendingPathComponent("Field").appendingPathComponent(modelFile)
            if FileManager.default.fileExists(atPath: file.path) {
                return file
            }
        }
        if let bundled = Bundle.main.url(
            forResource: "Dolphin3.0-Llama3.2-3B-Q4_K_M",
            withExtension: "gguf",
            subdirectory: "Field"
        ) {
            return bundled
        }
        return nil
    }

    public static func prompt(
        query: String,
        packName: String,
        excerpts: [FieldCard],
        locale: String
    ) -> String {
        var bits: [String] = []
        for card in excerpts.prefix(8) {
            let do0 = card.steps.first.map { String($0.do.en.prefix(180)) } ?? ""
            bits.append("- \(card.id): \(card.title.en). \(card.situation.en) \(do0)".trimmingCharacters(in: .whitespaces))
        }
        let ground = bits.isEmpty ? "(no book excerpts)" : bits.joined(separator: "\n")
        let system = """
        You are FIELD ASK on an offline survival HUD. The reader may be a child who has never done this. Answer with schema 1.4 JSON only. One action per step. child is what the child's hands do. First time: name the object, where to put hands, when to stop. 4 to 8 steps. STOP-IF and GET-TO-CARE. Never edible. Never a drinkable number. Never a phone number or a tel link. Use the pack book excerpts as ground when they apply. If they do not, still give a first-time walk that keeps them alive and getting to care. JSON only.
        """
        let user = """
        locale: \(locale)
        pack: \(packName)
        ask: \(query)
        book:
        \(ground)
        Return one FieldCard JSON object with title, situation, stop_if, get_to_care, and steps[{do,why,child,stop,image}]. Both en and es. image is a filename from the book steps. id must be ask-live. sendToParty false.
        """
        return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
    }

    public static func parse(_ text: String) -> FieldCard? {
        var raw = text.replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
        raw = raw.replacingOccurrences(of: "```", with: "")
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end
        else { return nil }
        let blob = String(raw[start...end])
        guard let data = blob.data(using: .utf8) else { return nil }
        guard let draft = try? JSONDecoder().decode(DraftCard.self, from: data) else { return nil }
        guard let steps = draft.steps, !steps.isEmpty else { return nil }
        return sanitize(from: draft, query: "", chapter: [], packId: nil)
    }

    public static func sanitize(_ card: FieldCard) -> FieldCard {
        sanitize(from: DraftCard(card: card), query: card.title.en, chapter: [], packId: card.packs?.first)
    }

    public static func sanitize(
        _ card: FieldCard,
        query: String,
        chapter: [FieldCard],
        packId: String?
    ) -> FieldCard {
        sanitize(from: DraftCard(card: card), query: query, chapter: chapter, packId: packId)
    }

    public static func grounded(
        query: String,
        chapter: [FieldCard],
        packId: String?,
        locale: String
    ) -> FieldCard {
        FieldAskWalk.build(query: query, chapter: chapter, packId: packId, locale: locale)
    }

    public static func answer(
        query: String,
        chapter: [FieldCard],
        locale: String,
        packName: String,
        packId: String?,
        modelURL: URL?
    ) -> FieldCard? {
        guard FieldCorpus.asking(query) else { return nil }
        if FieldCorpus.ask(chapter, query: query, locale: locale).first != nil {
            return nil
        }
        let ground = excerpts(chapter, query: query, locale: locale)
        if let url = modelURL,
           let text = FieldAskLlama.complete(prompt: prompt(query: query, packName: packName, excerpts: ground, locale: locale), modelURL: url),
           let parsed = parse(text)
        {
            return sanitize(parsed, query: query, chapter: chapter, packId: packId)
        }
        return grounded(query: query, chapter: chapter, packId: packId, locale: locale)
    }

    private static func excerpts(_ chapter: [FieldCard], query: String, locale: String) -> [FieldCard] {
        var out = Array(FieldCorpus.ask(chapter, query: query, locale: locale).prefix(6))
        let core = [
            "camp-start", "water-disinfect", "plant-unknown", "fungi-leave",
            "med-cpr-adult", "med-bleed-pack", "animal-bite",
        ]
        for id in core {
            if out.count >= 8 { break }
            if let card = chapter.first(where: { $0.id == id }),
               !out.contains(where: { $0.id == id })
            {
                out.append(card)
            }
        }
        return out
    }

    private static func picture(_ chapter: [FieldCard], prefer: String? = nil) -> String {
        var names: [String] = []
        for card in chapter {
            for st in card.steps where !st.image.isEmpty {
                names.append(st.image)
            }
        }
        if let prefer, names.contains(prefer) { return prefer }
        return names.first ?? "bleed-pack.png"
    }

    private static func sanitize(from draft: DraftCard, query: String, chapter: [FieldCard], packId: String?) -> FieldCard {
        let fallbackTitle = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ASK" : query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pic = picture(chapter)
        let title = loc(draft.title, fallback: fallbackTitle)
        let situation = loc(
            draft.situation,
            fallback: "You asked: \(fallbackTitle). One move at a time. Tap NEXT after each."
        )
        let care = loc(
            draft.get_to_care,
            fallback: "Get to trained help. Do not wait on a number the glass cannot dial."
        )
        var stops: [FieldLoc] = (draft.stop_if ?? []).map { loc($0, fallback: "Stop if the scene is unsafe.") }.filter { !$0.en.isEmpty }
        if stops.isEmpty {
            stops = [
                FieldLoc(
                    en: "Stop if the place is on fire, collapsing, or in traffic.",
                    es: "Para si hay fuego, derrumbe o tráfico."
                ),
            ]
        }
        var steps: [FieldStep] = []
        for st in draft.steps ?? [] {
            var child = loc(st.child, fallback: childHandsEn)
            if child.en.isEmpty {
                child = FieldLoc(en: childHandsEn, es: childHandsEs)
            }
            let image = scrub(st.image ?? "").isEmpty ? pic : (st.image ?? pic)
            steps.append(
                FieldStep(
                    do: loc(st.do, fallback: "Stop and look around."),
                    why: loc(st.why, fallback: "One move. Then check."),
                    child: child,
                    stop: loc(st.stop, fallback: "Stop if it hurts more or the scene turns unsafe."),
                    image: image.isEmpty ? pic : image
                )
            )
        }
        if steps.count < 4 {
            let extra = grounded(query: query, chapter: chapter, packId: packId, locale: "en")
            for st in extra.steps where steps.count < 4 {
                steps.append(st)
            }
        }
        if steps.count > 8 { steps = Array(steps.prefix(8)) }
        if steps.isEmpty {
            return grounded(query: query, chapter: chapter, packId: packId, locale: "en")
        }
        return FieldCard(
            schema: "1.4",
            id: liveID,
            category: "ask",
            states: ["TX", "NM"],
            title: title,
            situation: situation,
            stop_if: stops,
            get_to_care: care,
            speak: true,
            sendToParty: false,
            steps: steps,
            packs: packId.map { [$0] }
        )
    }

    private static func loc(_ raw: DraftLoc?, fallback: String) -> FieldLoc {
        let en = scrub(raw?.en ?? fallback)
        var es = scrub(raw?.es ?? en)
        let enOut = en.isEmpty ? fallback : en
        if es.isEmpty { es = enOut }
        return FieldLoc(en: enOut, es: es)
    }

    private static func scrub(_ text: String) -> String {
        var t = text
        t = replace(t, pattern: #"telprompt:[^\s]+"#, with: "")
        t = replace(t, pattern: "tel:" + #"//[^\s]+"#, with: "")
        t = t.replacingOccurrences(of: "98.6", with: "")
        t = replace(t, pattern: #"\bsafe to eat\b"#, with: "do not eat wild plants")
        t = replace(t, pattern: #"\bedible\b"#, with: "do not eat wild plants")
        t = replace(t, pattern: #"\beat this plant\b"#, with: "do not eat wild plants")
        t = replace(t, pattern: #"\bdrinkable\b"#, with: "not a drink until treated")
        return t.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ text: String, pattern: String, with: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: with)
    }

}

private struct DraftLoc: Codable {
    var en: String?
    var es: String?
}

private struct DraftStep: Codable {
    var `do`: DraftLoc?
    var why: DraftLoc?
    var child: DraftLoc?
    var stop: DraftLoc?
    var image: String?
}

private struct DraftCard: Codable {
    var title: DraftLoc?
    var situation: DraftLoc?
    var stop_if: [DraftLoc]?
    var get_to_care: DraftLoc?
    var steps: [DraftStep]?

    init(title: DraftLoc?, situation: DraftLoc?, stop_if: [DraftLoc]?, get_to_care: DraftLoc?, steps: [DraftStep]?) {
        self.title = title
        self.situation = situation
        self.stop_if = stop_if
        self.get_to_care = get_to_care
        self.steps = steps
    }

    init(card: FieldCard) {
        self.title = DraftLoc(en: card.title.en, es: card.title.es)
        self.situation = DraftLoc(en: card.situation.en, es: card.situation.es)
        self.stop_if = card.stop_if.map { DraftLoc(en: $0.en, es: $0.es) }
        self.get_to_care = DraftLoc(en: card.get_to_care.en, es: card.get_to_care.es)
        self.steps = card.steps.map {
            DraftStep(do: DraftLoc(en: $0.do.en, es: $0.do.es), why: DraftLoc(en: $0.why.en, es: $0.why.es), child: DraftLoc(en: $0.child.en, es: $0.child.es), stop: DraftLoc(en: $0.stop.en, es: $0.stop.es), image: $0.image)
        }
    }
}
