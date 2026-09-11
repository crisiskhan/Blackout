import Foundation

// A struct's memberwise init is internal even when the struct is public, so
// these could be decoded from the shipped corpus but never built in code. That
// is what left the FieldSpeech and FieldStepper suites uncompilable, and so
// unrun.

public struct FieldLoc: Codable, Equatable, Sendable {
    public var en: String
    public var es: String

    public init(en: String, es: String) {
        self.en = en
        self.es = es
    }
}

public struct FieldStep: Codable, Equatable, Sendable {
    public var `do`: FieldLoc
    public var why: FieldLoc
    public var child: FieldLoc
    public var stop: FieldLoc
    public var image: String
    public var tickSeconds: Int?
    public var metronomeBpm: Int?
    public var party: [String: String]?

    public init(
        do doStep: FieldLoc,
        why: FieldLoc,
        child: FieldLoc,
        stop: FieldLoc,
        image: String,
        tickSeconds: Int? = nil,
        metronomeBpm: Int? = nil,
        party: [String: String]? = nil
    ) {
        self.do = doStep
        self.why = why
        self.child = child
        self.stop = stop
        self.image = image
        self.tickSeconds = tickSeconds
        self.metronomeBpm = metronomeBpm
        self.party = party
    }
}

public struct FieldCard: Codable, Equatable, Sendable, Identifiable {
    public var schema: String
    public var id: String
    public var category: String
    public var states: [String]
    public var title: FieldLoc
    public var situation: FieldLoc
    public var stop_if: [FieldLoc]
    public var get_to_care: FieldLoc
    public var speak: Bool
    public var sendToParty: Bool
    public var steps: [FieldStep]
    /// Pack ids this card belongs to. Absent means every pack of `states`.
    /// East Texas woodland is not the west javelina chapter; a photographed
    /// javelina still opens the west card because the loaded book stays whole.
    public var packs: [String]?

    public init(
        schema: String,
        id: String,
        category: String,
        states: [String],
        title: FieldLoc,
        situation: FieldLoc,
        stop_if: [FieldLoc],
        get_to_care: FieldLoc,
        speak: Bool,
        sendToParty: Bool,
        steps: [FieldStep],
        packs: [String]? = nil
    ) {
        self.schema = schema
        self.id = id
        self.category = category
        self.states = states
        self.title = title
        self.situation = situation
        self.stop_if = stop_if
        self.get_to_care = get_to_care
        self.speak = speak
        self.sendToParty = sendToParty
        self.steps = steps
        self.packs = packs
    }
}

public struct FieldBook: Codable, Equatable, Sendable {
    public var schema: String
    public var id: String
    public var cards: [FieldCard]

    public init(schema: String, id: String, cards: [FieldCard]) {
        self.schema = schema
        self.id = id
        self.cards = cards
    }
}

public enum FieldCorpus {
    public static func load(core: Data, state: Data) throws -> [FieldCard] {
        let c = try JSONDecoder().decode(FieldBook.self, from: core)
        let s = try JSONDecoder().decode(FieldBook.self, from: state)
        let all = c.cards + s.cards
        for card in all {
            guard card.schema == "1.4" else { throw FieldError.schema }
            guard !card.steps.isEmpty else { throw FieldError.emptySteps }
            for st in card.steps {
                if st.`do`.en.isEmpty || st.image.isEmpty { throw FieldError.incompleteStep }
            }
        }
        return all
    }

    public static func visible(_ cards: [FieldCard], state: String) -> [FieldCard] {
        cards.filter { $0.states.contains(state) }
    }

    /// ALL CARDS of the open pack. Cards with no `packs` stay on every pack
    /// of their state. The loaded book is still the whole state, so VISION
    /// can open a west mammal card from a javelina still on East Texas.
    public static func chapter(_ cards: [FieldCard], pack: String?) -> [FieldCard] {
        guard let pack, !pack.isEmpty else { return cards }
        let id = pack.lowercased()
        return cards.filter { card in
            guard let packs = card.packs, !packs.isEmpty else { return true }
            return packs.contains { $0.lowercased() == id }
        }
    }

    /// Rank the open chapter for a situation. Empty or stopword-only query
    /// returns the chapter as-is. Unknown words return nothing — the catalog
    /// does not invent a card.
    public static func ask(_ cards: [FieldCard], query: String, locale: String) -> [FieldCard] {
        let qTokens = tokens(query)
        if qTokens.isEmpty { return cards }
        var expanded = Set(qTokens)
        for word in qTokens {
            if let extra = expand[word] {
                expanded.formUnion(extra)
            }
        }
        var boosted = Set<String>()
        for word in expanded {
            if let ids = boost[word] {
                boosted.formUnion(ids)
            }
        }
        let foldedQuery = qTokens.joined(separator: " ")
        let preferEs = locale == "es"
        var scored: [(FieldCard, Double)] = []
        for card in cards {
            let titleTok = Set(tokens(card.title.en) + tokens(card.title.es))
            let idTok = Set(tokens(card.id.replacingOccurrences(of: "-", with: " ")))
            let catTok = Set(tokens(card.category))
            let bodyTok = index(card)
            let titleHits = expanded.intersection(titleTok).count
            let overlap = expanded.intersection(bodyTok).count
            let boostedHit = boosted.contains(card.id)
            if overlap == 0 && titleHits == 0 && !boostedHit { continue }
            var score = Double(overlap) * 2
            score += Double(titleHits) * 10
            score += Double(expanded.intersection(idTok).count) * 8
            score += Double(expanded.intersection(catTok).count) * 6
            if boostedHit { score += 20 }
            let preferredTitle = Set(tokens(preferEs ? card.title.es : card.title.en))
            score += Double(expanded.intersection(preferredTitle).count) * 3
            if !foldedQuery.isEmpty {
                let titleFold = fold(card.title.en) + " " + fold(card.title.es)
                if titleTok.isSuperset(of: Set(qTokens)) { score += 40 }
                if foldedQuery.count >= 4 && titleFold.contains(foldedQuery) { score += 20 }
            }
            guard score > 0 else { continue }
            scored.append((card, score))
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.category != b.0.category { return a.0.category < b.0.category }
            return a.0.title.en < b.0.title.en
        }.map(\.0)
    }

    private static func index(_ card: FieldCard) -> Set<String> {
        var parts: [String] = [
            card.id.replacingOccurrences(of: "-", with: " "),
            card.category,
            card.title.en, card.title.es,
            card.situation.en, card.situation.es,
            card.get_to_care.en, card.get_to_care.es,
        ]
        for line in card.stop_if {
            parts.append(line.en)
            parts.append(line.es)
        }
        for st in card.steps {
            parts.append(st.`do`.en)
            parts.append(st.`do`.es)
            parts.append(st.why.en)
            parts.append(st.why.es)
        }
        return Set(parts.flatMap { tokens($0) })
    }

    private static func fold(_ s: String) -> String {
        s.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func tokens(_ s: String) -> [String] {
        let folded = fold(s)
        var words: [String] = []
        var current = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.compactMap { raw -> String? in
            let w = stem(raw)
            if w.count < 2 { return nil }
            if stop.contains(w) { return nil }
            return w
        }
    }

    private static func stem(_ w: String) -> String {
        if w.count > 4, w.hasSuffix("ies") {
            return String(w.dropLast(3)) + "y"
        }
        if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") {
            return String(w.dropLast())
        }
        return w
    }

    private static let stop: Set<String> = [
        "a", "an", "the", "to", "of", "for", "in", "on", "at", "is", "be", "as",
        "or", "and", "how", "do", "i", "we", "you", "your", "my", "me", "what",
        "where", "when", "why", "can", "with", "from", "this", "that", "it",
        "if", "not", "no", "yes", "am", "are", "was", "have", "has", "any",
        "el", "la", "los", "las", "de", "un", "una", "y", "o", "que", "en",
        "es", "se", "te", "lo", "al", "del", "para", "por", "con", "como",
        "mi", "tu", "su",
    ]

    /// Extra query tokens so a situation word hits the procedure that answers it.
    private static let expand: [String: Set<String>] = [
        "thirst": ["water", "drink", "boil"],
        "thirsty": ["water", "drink", "boil"],
        "sed": ["agua", "water", "drink"],
        "hydrate": ["water", "drink"],
        "snake": ["bite", "viper", "venom"],
        "snakes": ["bite", "viper"],
        "viper": ["bite", "snake"],
        "vibora": ["bite", "snake", "viper"],
        "víbora": ["bite", "snake", "viper"],
        "serpiente": ["bite", "snake", "viper"],
        "rattler": ["bite", "snake", "viper"],
        "rattlesnake": ["bite", "snake"],
        "mushroom": ["fungi", "leave"],
        "fungi": ["leave", "mushroom"],
        "forage": ["plant", "unknown"],
        "berry": ["plant", "unknown"],
        "berries": ["plant", "unknown"],
        "hunt": ["meat", "already"],
        "starting": ["nothing", "order"],
        "survival": ["nothing", "start"],
        "sobrevivir": ["nada", "nothing"],
    ]

    /// Card ids to raise when the query names a situation the title omitted.
    private static let boost: [String: [String]] = [
        "thirst": ["water-disinfect", "water-find"],
        "thirsty": ["water-disinfect", "water-find"],
        "sed": ["water-disinfect", "water-find"],
        "drink": ["water-disinfect", "water-find"],
        "agua": ["water-disinfect", "water-find"],
        "water": ["water-disinfect", "water-find", "water-catch"],
        "rain": ["water-catch", "env-flood"],
        "dew": ["water-catch"],
        "urine": ["water-find"],
        "seawater": ["water-find"],
        "boil": ["water-disinfect", "food-cook"],
        "snake": ["animal-bite"],
        "viper": ["animal-bite"],
        "vibora": ["animal-bite"],
        "víbora": ["animal-bite"],
        "serpiente": ["animal-bite"],
        "rattler": ["animal-bite"],
        "rattlesnake": ["animal-bite"],
        "cottonmouth": ["animal-bite", "tx-east-snake"],
        "copperhead": ["animal-bite", "tx-east-snake"],
        "diamondback": ["animal-bite", "tx-snake", "nm-snake"],
        "bite": ["animal-bite"],
        "sting": ["animal-bite"],
        "venom": ["animal-bite"],
        "mordedura": ["animal-bite"],
        "mushroom": ["fungi-leave"],
        "fungi": ["fungi-leave"],
        "toadstool": ["fungi-leave"],
        "hongo": ["fungi-leave"],
        "seta": ["fungi-leave"],
        "forage": ["plant-unknown", "plant-use"],
        "berry": ["plant-unknown"],
        "plant": ["plant-unknown", "plant-use"],
        "planta": ["plant-unknown", "plant-use"],
        "chew": ["plant-unknown", "tx-plant-danger", "nm-plant-danger"],
        "taste": ["plant-unknown"],
        "hunt": ["food-game"],
        "trap": ["food-game"],
        "spear": ["food-game"],
        "meat": ["food-game", "food-cook"],
        "caza": ["food-game"],
        "carne": ["food-game"],
        "fire": ["fire-stove", "fire-spark"],
        "flame": ["fire-stove", "fire-spark"],
        "spark": ["fire-spark"],
        "ferro": ["fire-spark"],
        "tinder": ["fire-spark"],
        "friction": ["fire-spark"],
        "bowdrill": ["fire-spark"],
        "fuego": ["fire-stove", "fire-spark"],
        "stove": ["fire-stove"],
        "shelter": ["shelter-tarp", "shelter-site"],
        "tarp": ["shelter-tarp"],
        "camp": ["shelter-site", "camp-start"],
        "refugio": ["shelter-tarp", "shelter-site"],
        "lost": ["nav-lost"],
        "perdido": ["nav-lost"],
        "gps": ["nav-lost"],
        "signal": ["sig-mirror", "sig-ground"],
        "mirror": ["sig-mirror"],
        "smoke": ["sig-ground", "fire-spark"],
        "rescue": ["sig-mirror", "sig-ground"],
        "whistle": ["sig-ground", "nav-lost"],
        "heat": ["env-heat-collapse", "env-desert-day"],
        "hot": ["env-heat-collapse", "env-desert-day"],
        "desert": ["env-desert-day"],
        "shade": ["env-desert-day", "plant-use"],
        "calor": ["env-heat-collapse", "env-desert-day"],
        "cold": ["env-cold"],
        "wet": ["env-cold", "shelter-tarp"],
        "hypothermia": ["env-cold"],
        "frio": ["env-cold"],
        "bleed": ["med-bleed-pack"],
        "blood": ["med-bleed-pack"],
        "tourniquet": ["med-bleed-pack"],
        "cpr": ["med-cpr-adult"],
        "rcp": ["med-cpr-adult"],
        "unresponsive": ["med-cpr-adult"],
        "airway": ["med-airway"],
        "choke": ["med-airway"],
        "spine": ["trauma-spine"],
        "fracture": ["trauma-fracture"],
        "splint": ["trauma-fracture"],
        "burn": ["med-burn"],
        "scald": ["med-burn"],
        "quemadura": ["med-burn"],
        "diarrhea": ["med-gut"],
        "diarrea": ["med-gut"],
        "vomit": ["med-gut"],
        "gut": ["med-gut"],
        "blister": ["med-feet"],
        "feet": ["med-feet"],
        "foot": ["med-feet"],
        "infection": ["med-infection"],
        "pus": ["med-infection"],
        "cave": ["cave-dark"],
        "hole": ["cave-dark"],
        "cueva": ["cave-dark"],
        "flood": ["env-flood"],
        "wash": ["env-flood"],
        "arroyo": ["env-flood"],
        "monsoon": ["env-flood", "nm-monsoon"],
        "lightning": ["env-lightning"],
        "rayo": ["env-lightning"],
        "thunder": ["env-lightning"],
        "river": ["env-crossing", "water-find"],
        "crossing": ["env-crossing"],
        "swim": ["env-crossing"],
        "bog": ["env-bog"],
        "mud": ["env-bog"],
        "swamp": ["env-bog"],
        "latrine": ["camp-latrine"],
        "toilet": ["camp-latrine"],
        "hygiene": ["camp-latrine"],
        "letrina": ["camp-latrine"],
        "rope": ["plant-cordage"],
        "fiber": ["plant-cordage"],
        "knife": ["camp-blade"],
        "blade": ["camp-blade"],
        "axe": ["camp-blade"],
        "tick": ["env-insect"],
        "mosquito": ["env-insect"],
        "insect": ["env-insect"],
        "nothing": ["camp-start"],
        "starting": ["camp-start"],
        "survival": ["camp-start"],
        "prioridad": ["camp-start"],
        "nada": ["camp-start"],
        "hurricane": ["tx-hurricane-paper"],
        "cactus": ["tx-cactus", "nm-cactus"],
        "oleander": ["tx-plant-danger"],
        "datura": ["nm-plant-danger"],
        "javelina": ["tx-mammal", "tx-game"],
        "hog": ["tx-east-mammal", "tx-east-game"],
        "coyote": ["tx-mammal", "tx-east-mammal", "nm-mammal"],
        "bear": ["nm-mammal"],
        "elk": ["nm-mammal", "nm-game"],
        "cattle": ["tx-cattle-guard"],
        "hospital": ["tx-nm-border-hospital"],
        "form": ["tact-formup"],
        "container": ["water-vessel", "water-disinfect"],
        "vessel": ["water-vessel"],
        "pot": ["water-vessel", "water-disinfect"],
        "cotton": ["env-cold", "env-core-temp"],
        "insulate": ["shelter-insulate", "shelter-tarp"],
        "insulation": ["shelter-insulate"],
        "debris": ["shelter-insulate", "shelter-tarp"],
        "temperature": ["env-core-temp", "env-cold", "env-heat-collapse"],
        "trunk": ["env-core-temp"],
        "cutting": ["camp-five", "camp-blade"],
        "combustion": ["camp-five", "fire-spark"],
        "cover": ["camp-five", "shelter-site"],
        "cordage": ["plant-cordage", "camp-five"],
        "sun": ["nav-sun"],
        "handrail": ["nav-sun", "nav-lost", "camp-start"],
        "watch": ["camp-watch"],
        "night": ["camp-watch"],
    ]
}

public enum FieldError: Error { case schema, emptySteps, incompleteStep }
