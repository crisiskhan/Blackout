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
        You are FIELD ASK on an offline survival HUD. The reader may be a child who has never done this. Answer with schema 1.4 JSON only. One action per step. child is what the child's hands do. First time: name the object, where to put hands, when to stop. 4 to 8 steps. STOP-IF and GET-TO-CARE. Never edible. Never a drinkable number. Never a phone number or tel://. Use the pack book excerpts as ground when they apply. If they do not, still give a first-time walk that keeps them alive and getting to care. JSON only.
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
        let toks = Set(FieldCorpus.situationWords(query))
        let asked = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let family = family(for: toks)
        let bookPic = picture(chapter)
        let bleedPic = picture(chapter, prefer: "bleed-pack.png")
        let start: [FieldStep] = [
            step(
                "Stop. Look around. Do not run.",
                "Para. Mira alrededor. No corras.",
                "Stand still. Hold a grown-up's hand if one is there.",
                "Quédate quieto. Toma la mano de un adulto si hay uno.",
                "Running makes you miss the danger and the way back.",
                "Correr te hace perder el peligro y el camino de vuelta.",
                "Stop if the ground is falling, on fire, or under traffic.",
                "Para si el piso se cae, hay fuego o hay tráfico.",
                bookPic
            ),
            step(
                "Move to the safest near spot you can see: off the road, out of the water, away from fire.",
                "Muévete al sitio cercano más seguro: fuera del camino, fuera del agua, lejos del fuego.",
                "Walk, do not run. Stay where people can see you.",
                "Camina, no corras. Quédate donde la gente te vea.",
                "The first job is a place that will not hit you.",
                "Lo primero es un lugar que no te golpee.",
                "Stop if moving would put you in the hazard.",
                "Para si moverte te mete en el peligro.",
                bookPic
            ),
        ]
        let body: [FieldStep]
        let care: FieldLoc
        switch family {
        case .bleed:
            body = [
                step(
                    "If you have a cloth, press it hard on the bleeding spot and keep pressing.",
                    "Si tienes un paño, presiónalo fuerte en el sangrado y no lo sueltes.",
                    "Use both hands. Do not peek. Peeking lets the blood out.",
                    "Usa las dos manos. No mires debajo. Mirar deja salir la sangre.",
                    "Pressure is the first move. Looking under the cloth restarts the bleed.",
                    "La presión es el primer movimiento. Mirar debajo reinicia el sangrado.",
                    "Stop if the scene is unsafe. Move them with you if you must.",
                    "Para si la escena es insegura. Muévelos contigo si hace falta.",
                    bleedPic
                ),
                step(
                    "If blood soaks through, put another cloth on top. Do not take the first one off.",
                    "Si la sangre traspasa, pon otro paño encima. No quites el primero.",
                    "Keep pressing. Ask a grown-up to hold if your arms shake.",
                    "Sigue presionando. Pide a un adulto que sostenga si te tiembran los brazos.",
                    "The first cloth is the plug.",
                    "El primer paño es el tapón.",
                    "Stop pressing only if trained help takes over.",
                    "Deja de presionar solo si la ayuda entrenada toma el relevo.",
                    bleedPic
                ),
            ]
            care = FieldLoc(
                en: "Keep pressure and get to trained help. Do not wait on a number the glass cannot dial.",
                es: "Sigue la presión y llega a ayuda entrenada. No esperes un número que el visor no puede marcar."
            )
        case .choke:
            body = [
                step(
                    "If they can cough or speak, let them cough. Stay next to them.",
                    "Si pueden toser o hablar, déjalos toser. Quédate a su lado.",
                    "Do not put fingers in their mouth.",
                    "No metas los dedos en la boca.",
                    "Air can still move if they cough.",
                    "El aire aún puede pasar si tosen.",
                    "If they stop coughing and cannot breathe, go to the next move.",
                    "Si dejan de toser y no respiran, pasa al siguiente movimiento.",
                    bookPic
                ),
                step(
                    "If they cannot cough, speak, or breathe, hit their back hard between the shoulders five times.",
                    "Si no pueden toser, hablar ni respirar, golpea la espalda fuerte entre los hombros cinco veces.",
                    "Stand to the side. Aim at the back, not the neck.",
                    "Ponte a un lado. Apunta a la espalda, no al cuello.",
                    "A hard back blow can move the block.",
                    "Un golpe fuerte en la espalda puede mover el bloqueo.",
                    "Stop if they start coughing or breathing.",
                    "Para si empiezan a toser o respirar.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get trained help even if the block comes out. They can swell later.",
                es: "Consigue ayuda entrenada aunque salga el bloqueo. Pueden hincharse después."
            )
        case .cpr:
            body = [
                step(
                    "Tap the shoulders and look at the chest for ten seconds. No normal breathing means start compressions.",
                    "Toca los hombros y mira el pecho diez segundos. Sin respiración normal, empieza compresiones.",
                    "Keep other children back. One person pushes. Another watches the child.",
                    "Aleja a otros niños. Una persona empuja. Otra vigila al niño.",
                    "Delay kills. Gasping is not normal breathing.",
                    "La demora mata. El jadeo no es respiración normal.",
                    "If they cough, move, or breathe normally, stop compressions and watch them.",
                    "Si tosen, se mueven o respiran normal, detén y vigílalos.",
                    picture(chapter, prefer: "cpr-check.png")
                ),
                step(
                    "Hard, fast compressions in the center of the chest. Let the chest come back up each time.",
                    "Compresiones fuertes y rápidas al centro del pecho. Deja que el pecho suba cada vez.",
                    "Do not stand on the chest. Do not 'help' with a bounce.",
                    "No te subas al pecho. No 'ayudes' con un rebote.",
                    "Blood has to reach the brain. Shallow pumps do nothing.",
                    "La sangre tiene que llegar al cerebro. Las palmaditas no sirven.",
                    "Stop if an AED is attached and says stay clear, or if they start breathing.",
                    "Para si un DEA dice apartarse o si empiezan a respirar.",
                    picture(chapter, prefer: "cpr-compress.png")
                ),
            ]
            care = FieldLoc(
                en: "Get trained help and an AED. Keep compressions until they take over.",
                es: "Consigue ayuda entrenada y un DEA. Sigue hasta que tomen el relevo."
            )
        case .burn:
            body = [
                step(
                    "Get the heat off. Cool the burn with clean water. Do not put ice, butter, or toothpaste on it.",
                    "Quita el calor. Enfría la quemadura con agua limpia. No pongas hielo, mantequilla ni pasta.",
                    "Hold the water on the skin. Do not smear anything on it.",
                    "Sostén el agua en la piel. No untes nada.",
                    "Ice and grease hold heat in.",
                    "El hielo y la grasa guardan el calor.",
                    "Stop cooling if they start to shake from cold.",
                    "Deja de enfriar si empiezan a temblar de frío.",
                    bookPic
                ),
                step(
                    "Cover loosely with a clean cloth. Do not pop blisters.",
                    "Cubre flojo con un paño limpio. No revientes ampollas.",
                    "Touch the cloth, not the burn.",
                    "Toca el paño, no la quemadura.",
                    "Open skin is how dirt gets in.",
                    "La piel abierta es por donde entra suciedad.",
                    "Stop if the cloth sticks — leave it and get care.",
                    "Para si el paño se pega — déjalo y busca cuidado.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help for any burn that is big, on the face, or on the hands.",
                es: "Llega a ayuda entrenada si la quemadura es grande, en la cara o en las manos."
            )
        case .lost:
            body = [
                step(
                    "Stay where you are if that spot is safe. Hug a tree or sit on a rock people can see.",
                    "Quédate si el sitio es seguro. Abraza un árbol o siéntate en una roca visible.",
                    "Sit. Do not wander to 'look for camp'.",
                    "Siéntate. No deambules a 'buscar el campamento'.",
                    "Searchers walk a line. A moving child is the one they miss.",
                    "Los buscadores caminan una línea. Un niño que se mueve es el que pierden.",
                    "Move only if fire, water, or night cold will hit you here.",
                    "Muévete solo si el fuego, el agua o el frío de noche te van a pegar aquí.",
                    bookPic
                ),
                step(
                    "Make yourself big and loud from that spot: yell in threes, wave a bright cloth.",
                    "Hazte grande y ruidoso desde ese sitio: grita de a tres, agita un paño brillante.",
                    "Three yells. Then listen. Then three more.",
                    "Tres gritos. Luego escucha. Luego tres más.",
                    "A pattern is how people know you are a person.",
                    "Un patrón es cómo saben que eres una persona.",
                    "Stop yelling if you need that breath to stay warm.",
                    "Deja de gritar si necesitas ese aire para no enfriar.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Stay put until a known voice reaches you. Do not follow a stranger off your spot.",
                es: "Quédate hasta que una voz conocida te alcance. No sigas a un extraño fuera de tu sitio."
            )
        case .fracture:
            body = [
                step(
                    "Do not try to push a bone back. Leave the limb how it lies.",
                    "No intentes meter un hueso. Deja el miembro como está.",
                    "Hands off the break. Hold the rest of the body still.",
                    "Manos fuera de la fractura. Sostén el resto del cuerpo quieto.",
                    "Moving the bone can cut the rest of the limb.",
                    "Mover el hueso puede cortar el resto del miembro.",
                    "Stop if they faint or the fingers go white and cold.",
                    "Para si se desmayan o los dedos se ponen blancos y fríos.",
                    bookPic
                ),
                step(
                    "Pad around the limb with cloth and tie it to something stiff so it cannot flop. Tie loose enough to slip a finger under.",
                    "Acolcha el miembro con tela y átalo a algo rígido para que no se mueva. Lo bastante flojo para meter un dedo.",
                    "Hold the stick. Let a grown-up tie if they are there.",
                    "Sostén el palo. Deja que un adulto ate si está ahí.",
                    "A floppy break keeps tearing.",
                    "Una fractura suelta sigue rasgando.",
                    "Stop if the tie makes fingers numb or blue.",
                    "Para si el nudo deja los dedos entumecidos o azules.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Carry them if you can. Get to trained help. Do not wait on a number the glass cannot dial.",
                es: "Cárgalos si puedes. Llega a ayuda entrenada. No esperes un número que el visor no puede marcar."
            )
        case .start:
            let label = asked.isEmpty ? "this" : asked
            body = [
                step(
                    "Do one first move for this ask: \(label). Use your hands. One thing only.",
                    "Haz un primer movimiento para esto: \(label). Usa las manos. Una sola cosa.",
                    childHandsEn,
                    childHandsEs,
                    "First time means one action, then check.",
                    "La primera vez es un acto, luego revisar.",
                    "Stop if it hurts more or the scene turns unsafe.",
                    "Para si duele más o la escena se vuelve insegura.",
                    bookPic
                ),
                step(
                    "Check the person or the camp after that one move. Then do the next one move, not three.",
                    "Revisa a la persona o el campamento después de ese movimiento. Luego haz el siguiente, no tres.",
                    "Look. Then one more hand move. Then tap NEXT.",
                    "Mira. Luego un movimiento más. Luego toca NEXT.",
                    "Stacking jobs is how first-timers skip the one that saves them.",
                    "Apilar tareas es cómo los principiantes saltan la que los salva.",
                    "Stop if you cannot see, cannot stand, or cannot hear.",
                    "Para si no ves, no te sostienes o no oyes.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to people who can help. Stay with the party. Do not wait on a number the glass cannot dial.",
                es: "Llega a gente que pueda ayudar. Quédate con el grupo. No esperes un número que el visor no puede marcar."
            )
        }
        let finish = [
            step(
                "If you cannot finish, stay visible and stay with the party. Do not eat wild plants. Do not drink untreated water.",
                "Si no puedes terminar, quédate visible y con el grupo. No comas plantas silvestres. No bebas agua sin tratar.",
                "Hands off plants and standing water. Sit where people can see you.",
                "Manos fuera de plantas y agua estancada. Siéntate donde te vean.",
                "Unknown plants and untreated water are how a small problem becomes two.",
                "Plantas desconocidas y agua sin tratar convierten un problema en dos.",
                "Stop if you feel faint. Sit. Yell.",
                "Para si te desmayas. Siéntate. Grita.",
                bookPic
            ),
        ]
        var steps = start + body + finish
        if steps.count > 8 { steps = Array(steps.prefix(8)) }
        let titleText = asked.isEmpty ? "ASK" : String(asked.prefix(44))
        _ = locale
        return FieldCard(
            schema: "1.4",
            id: liveID,
            category: "ask",
            states: ["TX", "NM"],
            title: FieldLoc(en: titleText, es: titleText),
            situation: FieldLoc(
                en: "You asked: \(asked). First time. One move per step. A child can follow it.",
                es: "Preguntaste: \(asked). Primera vez. Un movimiento por paso. Un niño puede seguirlo."
            ),
            stop_if: [
                FieldLoc(
                    en: "Stop if the place is on fire, collapsing, or in traffic.",
                    es: "Para si hay fuego, derrumbe o tráfico."
                ),
                FieldLoc(
                    en: "Stop if they stop breathing, or bleeding soaks through and you cannot keep pressure.",
                    es: "Para si dejan de respirar, o el sangrado traspasa y no puedes mantener presión."
                ),
            ],
            get_to_care: care,
            speak: true,
            sendToParty: false,
            steps: steps,
            packs: packId.map { [$0] }
        )
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

    private enum Family {
        case bleed, choke, cpr, burn, lost, fracture, start
    }

    private static func family(for toks: Set<String>) -> Family {
        if !toks.isDisjoint(with: ["bleed", "bleeding", "blood", "cut", "wound", "shot", "stab", "gash", "sangrando"]) {
            return .bleed
        }
        if !toks.isDisjoint(with: ["choke", "choking", "airway"]) {
            return .choke
        }
        if !toks.isDisjoint(with: ["cpr", "unresponsive", "pulse", "unconscious", "collapsed", "fainted"]) {
            return .cpr
        }
        if !toks.isDisjoint(with: ["burn", "scald"]) {
            return .burn
        }
        if !toks.isDisjoint(with: ["lost", "gps", "separated"]) {
            return .lost
        }
        if !toks.isDisjoint(with: ["break", "broken", "broke", "sprain", "sling", "fracture"]) {
            return .fracture
        }
        return .start
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

    private static func step(
        _ doEn: String, _ doEs: String,
        _ childEn: String, _ childEs: String,
        _ whyEn: String, _ whyEs: String,
        _ stopEn: String, _ stopEs: String,
        _ image: String
    ) -> FieldStep {
        FieldStep(
            do: FieldLoc(en: doEn, es: doEs),
            why: FieldLoc(en: whyEn, es: whyEs),
            child: FieldLoc(en: childEn, es: childEs),
            stop: FieldLoc(en: stopEn, es: stopEs),
            image: image
        )
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
        t = replace(t, pattern: #"tel://[^\s]+"#, with: "")
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
