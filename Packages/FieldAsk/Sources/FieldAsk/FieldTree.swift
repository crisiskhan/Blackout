import Foundation
import FieldCorpus

/// Connected emergency cards. First move now, then the next likely cause.
/// Airplane only. A civilian with a phone coaches or does the walk.
public enum FieldTree {
    public static func decorate(_ card: FieldCard, query: String) -> FieldCard {
        var out = card
        out.links = links(cardID: card.id, tokens: Set(FieldCorpus.situationWords(query)))
        return out
    }

    public static func links(cardID: String, tokens: Set<String>) -> [FieldLink] {
        if cardID != FieldAsk.liveID {
            return forks(forCard: cardID)
        }
        if let tree = presentation(for: tokens) {
            return forks(forTree: tree)
        }
        return forks(forFamily: FieldAskWalk.family(for: tokens))
    }

    public static func openLink(
        _ link: FieldLink,
        chapter: [FieldCard],
        packId: String?,
        locale: String
    ) -> FieldCard {
        if let book = chapter.first(where: { $0.id == link.id }) {
            return decorate(book, query: link.ask)
        }
        let q = link.ask.isEmpty ? link.label.lowercased() : link.ask
        return decorate(
            FieldAskWalk.build(query: q, chapter: chapter, packId: packId, locale: locale),
            query: q
        )
    }

    private enum Tree {
        case breath, hurt, sick, stay
    }

    private static func presentation(for tokens: Set<String>) -> Tree? {
        if !tokens.isDisjoint(with: ["choke", "choking", "airway"]) { return nil }
        if !tokens.isDisjoint(with: ["allergy", "allergic", "anaphylaxis", "epipen"]) { return nil }
        if !tokens.isDisjoint(with: ["asthma", "inhaler", "wheezing", "wheeze"]) { return nil }
        if !tokens.isDisjoint(with: ["cardiac", "chest"]) { return nil }
        if !tokens.isDisjoint(with: ["cpr", "unresponsive", "pulse", "unconscious", "collapsed", "fainted"]) {
            return nil
        }
        if !tokens.isDisjoint(with: ["stable", "stabilize"]) { return .stay }
        if !tokens.isDisjoint(with: ["stay"])
            && tokens.isDisjoint(with: ["cold", "heat", "warm", "cool"])
        {
            return .stay
        }
        if !tokens.isDisjoint(with: ["breath", "breathe"]) { return .breath }
        if !tokens.isDisjoint(with: ["hurt", "injured", "injury"]) { return .hurt }
        if !tokens.isDisjoint(with: ["sick", "ill"]) { return .sick }
        return nil
    }

    private static func forks(forTree tree: Tree) -> [FieldLink] {
        switch tree {
        case .breath:
            return [choke, allergy, asthma, heart, smoke, drown, cpr, stay]
        case .hurt:
            return [bleed, breath, cpr, head, neck, brk, burn, bite, stay]
        case .sick:
            return [heat, cold, stroke, allergy, gut, poison, seizure, stay]
        case .stay:
            return [cpr]
        }
    }

    private static func forks(forFamily family: FieldAskWalk.Family) -> [FieldLink] {
        switch family {
        case .breath: return forks(forTree: .breath)
        case .hurt: return forks(forTree: .hurt)
        case .sick: return forks(forTree: .sick)
        case .stay: return forks(forTree: .stay)
        case .choke: return [allergy, asthma, breath, cpr, stay]
        case .cardiac: return [breath, cpr, stay]
        case .allergy: return [breath, cpr, stay]
        case .asthma: return [breath, allergy, cpr, stay]
        case .cpr: return [breath, seizure, shock, stay]
        case .bleed: return [shock, head, nose, stay]
        case .shock: return [bleed, cpr, stay]
        case .drown: return [cpr, stay]
        case .stroke: return [cpr, stay]
        case .head: return [cpr, bleed, neck, stay]
        case .poison: return [cpr, stay]
        case .seizure: return [cpr, stay]
        case .burn: return [breath, stay]
        case .heat: return [stroke, cpr, stay]
        case .cold: return [cpr, stay]
        case .nose: return [bleed, stay]
        case .flood: return [drown, stay]
        case .lightning: return [cpr, burn, stay]
        case .tornado: return [cpr, stay]
        case .fracture: return [bleed, shock, stay]
        case .lost: return [signal, stay]
        case .eye: return [stay]
        case .animal: return [bite, stay]
        case .avalanche: return [cpr, cold, stay]
        case .rip: return [drown, stay]
        case .start: return [bleed, breath, stay]
        default: return [stay]
        }
    }

    private static func forks(forCard id: String) -> [FieldLink] {
        switch id {
        case "med-airway": return [allergy, asthma, breath, cpr, stay]
        case "med-cpr-adult": return [breath, seizure, shock, stay]
        case "med-bleed-pack": return [shock, head, nose, stay]
        case "med-burn": return [breath, stay]
        case "trauma-fracture": return [bleed, shock, stay]
        case "trauma-spine": return [cpr, head, stay]
        case "trauma-carry": return [brk, bleed, stay]
        case "animal-bite": return [allergy, bleed, stay]
        case "env-heat-collapse": return [stroke, cpr, stay]
        case "env-cold": return [cpr, stay]
        case "env-smoke": return [breath, cpr, stay]
        case "env-flood": return [drown, stay]
        case "env-lightning": return [cpr, burn, stay]
        case "env-wildfire": return [smoke, breath, stay]
        case "nav-lost": return [signal, stay]
        case "shelter-tarp": return [cold, signal, stay]
        case "med-gut": return [poison, stay]
        default: return [stay]
        }
    }

    private static func link(
        _ id: String,
        _ label: String,
        en: String,
        es: String,
        ask: String
    ) -> FieldLink {
        FieldLink(id: id, label: label, when: FieldLoc(en: en, es: es), ask: ask)
    }

    private static let choke = link(
        "med-airway", "CHOKE",
        en: "Cannot cough or speak",
        es: "No puede toser ni hablar",
        ask: "choking"
    )
    private static let allergy = link(
        "live-allergy", "ALLERGY",
        en: "Face or throat swelling",
        es: "Cara o garganta hinchada",
        ask: "anaphylaxis"
    )
    private static let asthma = link(
        "live-asthma", "ASTHMA",
        en: "Wheeze, has an inhaler",
        es: "Silbido, tiene inhalador",
        ask: "asthma"
    )
    private static let heart = link(
        "live-cardiac", "HEART",
        en: "Chest pain or pressure",
        es: "Dolor o presión en el pecho",
        ask: "heart attack"
    )
    private static let smoke = link(
        "env-smoke", "SMOKE",
        en: "Fire or thick smoke",
        es: "Fuego o humo espeso",
        ask: "smoke"
    )
    private static let drown = link(
        "live-drown", "DROWN",
        en: "Water in the chest",
        es: "Agua en el pecho",
        ask: "drowning"
    )
    private static let cpr = link(
        "med-cpr-adult", "CPR",
        en: "Chest has stopped",
        es: "El pecho paró",
        ask: "not breathing"
    )
    private static let stay = link(
        "live-stay", "STAY",
        en: "Still breathing, none of these",
        es: "Aún respira, ninguna de estas",
        ask: "keep them stable"
    )
    private static let bleed = link(
        "med-bleed-pack", "BLEED",
        en: "Blood you can see",
        es: "Sangre que se ve",
        ask: "bleeding out"
    )
    private static let breath = link(
        "live-breath", "BREATH",
        en: "Fighting for air",
        es: "Pelea por aire",
        ask: "can't breathe"
    )
    private static let head = link(
        "live-head", "HEAD",
        en: "Hit or knocked out",
        es: "Golpe o desmayo",
        ask: "hit my head"
    )
    private static let neck = link(
        "trauma-spine", "NECK",
        en: "Fell or the neck hurts",
        es: "Cayó o duele el cuello",
        ask: "I fell and my neck hurts"
    )
    private static let brk = link(
        "trauma-fracture", "BREAK",
        en: "Bone will not hold",
        es: "El hueso no sostiene",
        ask: "broken leg"
    )
    private static let burn = link(
        "med-burn", "BURN",
        en: "Burned skin",
        es: "Piel quemada",
        ask: "I'm burned"
    )
    private static let bite = link(
        "animal-bite", "BITE",
        en: "Bite or sting",
        es: "Mordida o picadura",
        ask: "got bit"
    )
    private static let heat = link(
        "env-heat-collapse", "HEAT",
        en: "Hot, confused, no sweat",
        es: "Calor, confusión, no suda",
        ask: "heat stroke"
    )
    private static let cold = link(
        "env-cold", "COLD",
        en: "Wet, shaking, slowing",
        es: "Mojado, temblando, lento",
        ask: "hypothermia"
    )
    private static let stroke = link(
        "live-stroke", "STROKE",
        en: "Face, arm, or speech gone",
        es: "Cara, brazo o habla rara",
        ask: "stroke"
    )
    private static let gut = link(
        "med-gut", "GUT",
        en: "Vomiting or diarrhea",
        es: "Vómito o diarrea",
        ask: "diarrhea"
    )
    private static let poison = link(
        "live-poison", "POISON",
        en: "Swallowed a bottle or plant",
        es: "Tragó una botella o planta",
        ask: "swallowed bleach"
    )
    private static let shock = link(
        "live-shock", "SHOCK",
        en: "Pale, cold, fading",
        es: "Pálido, frío, se apaga",
        ask: "they are in shock"
    )
    private static let nose = link(
        "live-nose", "NOSE",
        en: "Blood from the nose",
        es: "Sangre de la nariz",
        ask: "nosebleed"
    )
    private static let seizure = link(
        "live-seizure", "SEIZURE",
        en: "Shaking, not holding them",
        es: "Temblando, no los sujetes",
        ask: "seizure"
    )
    private static let signal = link(
        "sig-mirror", "SIGNAL",
        en: "Need to be seen",
        es: "Hay que ser visto",
        ask: "how do I get rescued"
    )
}
