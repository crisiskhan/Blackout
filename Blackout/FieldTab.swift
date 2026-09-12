import SwiftUI
import UIKit
import FieldCorpus
import FieldStepper
import FieldSpeech
import MapLibreMap
import OfflineSpeech
import Tokens
import VisionCoreML

struct FieldTab: View {
    @Bindable var runtime: AppRuntime
    @State private var cards: [FieldCard] = []
    @State private var query = ""
    @State private var stepper: StepperState?
    @State private var fieldTrail: [String] = []
    @State private var fieldTrailTotal: Int = 0
    @State private var fieldTrailBook: String = ""
    @State private var guess: VisionGuess?
    @State private var showVision = false
    @State private var sayFailed = false

    var body: some View {
        HUDPage(
            title: "FIELD",
            status: fieldStatus,
            statusTone: fieldTone
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // One card open, or SEARCH. Never both. SEARCH submits the
                // answering card's steps. A title dump is not an answer.
                Group {
                    if let s = stepper {
                        ScrollView {
                            open(s)
                        }
                    } else {
                        if cards.isEmpty {
                            HUDGlassCard {
                                Text("FIELD BOOK · NONE")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Theme.warn)
                            }
                        } else {
                            searchField
                            if catalogMiss {
                                HUDGlassCard {
                                    Text("NO MATCH")
                                        .font(.system(size: 13, weight: .heavy))
                                        .foregroundStyle(Theme.warn)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                visionHUD
            }
        }
        .sheet(isPresented: $showVision) {
            #if canImport(AVFoundation) && canImport(UIKit)
            VisionStill(
                onImage: { image in
                    showVision = false
                    applyVision(image: image)
                },
                onFail: {
                    showVision = false
                    applyVision(image: nil)
                },
                onCancel: { showVision = false }
            )
            .ignoresSafeArea()
            .presentationBackground(Theme.void)
            #endif
        }
        .onAppear(perform: load)
        .onChange(of: runtime.fieldJump) { _, _ in jump() }
        .onChange(of: runtime.packs?.active?.id) { _, _ in
            query = ""
            sayFailed = false
            load()
        }
    }

    private var fieldStatus: String {
        if let s = stepper {
            // A hold named a trail of plant / bite / use cards. STEP 1 OF 1
            // on every one of them hides that you are walking the biome book.
            if fieldTrailTotal > 1 {
                let at = fieldTrailTotal - fieldTrail.count
                return "CARD \(at) OF \(fieldTrailTotal)"
            }
            return "STEP \(s.index + 1) OF \(s.card.steps.count)"
        }
        guard let g = guess else { return "" }
        if g.noModel { return L10n.t("vision.none", runtime.locale) }
        if g.leaveIt {
            return "\(g.name) · \(L10n.t("vision.leave", runtime.locale))"
        }
        return g.name
    }

    private var fieldTone: HUDStatusTone {
        if stepper != nil { return .silver }
        if let g = guess {
            if g.leaveIt { return .crisis }
            if g.noModel { return .warn }
        }
        return .silver
    }

    @ViewBuilder
    private var visionHUD: some View {
        sectionLabel("VISION")
        Button("VISION") {
            guess = nil
            #if canImport(AVFoundation) && canImport(UIKit)
            showVision = true
            #else
            guess = VisionCoreML.noModelGuess()
            #endif
        }
        .buttonStyle(HUDActionStyle(filled: true))
        if let g = guess {
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    if g.noModel {
                        Text(L10n.t("vision.none", runtime.locale))
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(g.name)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(g.leaveIt ? Theme.accent : Theme.silver)
                            .fixedSize(horizontal: false, vertical: true)
                        if g.leaveIt {
                            Text(L10n.t("vision.leave", runtime.locale))
                                .font(.system(size: 18, weight: .heavy))
                                .foregroundStyle(Theme.accent)
                        }
                        if !g.leaveIt {
                            ForEach(g.lookalikes, id: \.self) { word in
                                Text(word)
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Theme.silver)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            visionFieldButton(g)
        }
    }

    /// The still named a kind. Offer the same procedure the hold would —
    /// mammal cards for a javelina, not a woodland dump. UNKNOWN and no
    /// model stay a name, not an invented card.
    @ViewBuilder
    private func visionFieldButton(_ g: VisionGuess) -> some View {
        let route = InspectField.presentRoute(
            InspectField.fieldRoute(
                forVision: g.labelId,
                state: runtime.packs?.active?.state,
                pack: runtime.packs?.active?.id
            ),
            in: Set(cards.map(\.id))
        )
        if let first = route.first {
            Button(InspectField.label(for: first)) {
                openRoute(
                    InspectField.fieldRoute(
                        forVision: g.labelId,
                        state: runtime.packs?.active?.state,
                        pack: runtime.packs?.active?.id
                    )
                )
            }
            .buttonStyle(HUDActionStyle(filled: false))
            if let book = InspectField.bookLine(for: route) {
                Text(book)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.silver.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func applyVision(image: CGImage?) {
        guard let image else {
            guess = VisionCoreML.noModelGuess()
            return
        }
        let book = runtime.visionBook()
        let locale = runtime.locale
        DispatchQueue.global(qos: .userInitiated).async {
            let observations = SystemVision.observations(from: image)
            let next: VisionGuess
            if let observations, let book {
                next = VisionCoreML.classify(
                    observations: observations.map {
                        VisionObservation(identifier: $0.identifier, confidence: $0.confidence)
                    },
                    book: book,
                    locale: locale
                )
            } else {
                next = VisionCoreML.noModelGuess()
            }
            DispatchQueue.main.async { guess = next }
        }
    }

    /// Every card ships both languages. The list was reading the locale and
    /// the steps were not, so a Spanish reader picked a card by its Spanish
    /// title and then got the instructions in English.
    private func loc(_ text: FieldLoc) -> String {
        runtime.locale == "es" ? text.es : text.en
    }

    /// One card, open at one step, with the way back to SEARCH on it. The
    /// map comes straight in here, so without that way back a hold on the
    /// ground would be a one-way door into a single card.
    private func open(_ s: StepperState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(loc(s.card.title))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.white)
                Spacer(minLength: 8)
                Button("ALL CARDS") { leaveCard() }
                    .buttonStyle(HUDOverlayChipStyle())
            }
            sectionLabel("SITUATION")
            Text(loc(s.card.situation))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.silver.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            if !fieldTrailBook.isEmpty {
                Text(fieldTrailBook)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.silver.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            sectionLabel(L10n.t("stop.if", runtime.locale))
            ForEach(Array(s.card.stop_if.enumerated()), id: \.offset) { _, line in
                Text(loc(line))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1)
                    )
            }

            sectionLabel("DO")
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    if !s.step.image.isEmpty,
                       let root = AppRuntime.resourceRoot()?.appendingPathComponent("Field/images/\(s.step.image)"),
                       let ui = UIImage(contentsOfFile: root.path)
                    {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    Text(loc(s.step.`do`))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.silver)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(loc(s.step.why))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.silver.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(loc(s.step.child))
                        .font(.caption)
                        .foregroundStyle(Theme.silver.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(loc(s.step.stop))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    if let tick = s.step.tickSeconds {
                        Text("TICK \(tick)s")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.silver)
                    }
                    if let bpm = s.step.metronomeBpm {
                        Text("CPR \(bpm)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            sectionLabel("GET-TO-CARE")
            Text(loc(s.card.get_to_care))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.silver)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.raised)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 8) {
                // On the last step NEXT did nothing at all, which reads as a
                // broken button rather than the end of the card. A hold that
                // named a trail of plant / bite / use cards still has work
                // after this one — name that procedure the same way the hold
                // button did, then open it. ALL CARDS dumps the rest and
                // returns to SEARCH.
                Button(stepTitle(s)) {
                    if s.isLast {
                        advanceTrail()
                    } else {
                        var x = s
                        x.next()
                        stepper = x
                    }
                }
                .buttonStyle(HUDActionStyle(filled: true))
                Button("SPEAK") {
                    var x = s; x.speak(); stepper = x
                    if !FieldSpeech.speak(s.card, locale: runtime.locale, engine: runtime.speech, step: s.index) {
                        runtime.speechChrome = "SPEECH FAILED"
                    } else {
                        runtime.speechChrome = ""
                    }
                }
                .buttonStyle(HUDActionStyle(filled: false))
            }
            Button("SEND TO PARTY") {
                var x = s
                x.send()
                stepper = x
                runtime.sendFieldToParty(cardID: s.card.id)
            }
            .buttonStyle(HUDActionStyle(filled: false))
            Text(runtime.mesh.chromeNet).font(.caption).foregroundStyle(Theme.warn)
            if !runtime.speechChrome.isEmpty {
                Text(runtime.speechChrome).font(.caption).foregroundStyle(Theme.warn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Theme.silver.opacity(0.5))
    }

    /// SEARCH is the menu. Empty is waiting, not a dump of the book. The
    /// loaded `cards` book stays the whole state so a javelina still still
    /// opens the west mammal card. SEARCH ranks this pack's chapter. It
    /// does not invent a card the book lacks. ALL CARDS on an open card
    /// returns here.
    private var catalogQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var catalogMiss: Bool {
        FieldCorpus.asking(catalogQuery) && listCards.isEmpty
    }

    private var listCards: [FieldCard] {
        FieldCorpus.ask(
            FieldCorpus.chapter(cards, pack: runtime.packs?.active?.id),
            query: catalogQuery,
            locale: runtime.locale
        )
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                TextField("SEARCH", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit(openAnswer)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.silver)
                    .padding(.horizontal, 12)
                    .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                    .background(Theme.glass())
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.silver.opacity(0.22), lineWidth: 1)
                    )
                Button("SAY") { say() }
                    .buttonStyle(HUDOverlayChipStyle())
            }
            if sayFailed {
                Text("SAY FAILED")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.warn)
            }
        }
    }

    /// Spoken question uses the same ask path as type. Deny, PTT live, and
    /// a missing on-device recognizer are SAY FAILED — not a network model.
    private func say() {
        sayFailed = false
        if runtime.ptt.live || runtime.clipLive {
            sayFailed = true
            return
        }
        if runtime.speech.listening {
            runtime.speech.endListen()
            return
        }
        let started = runtime.speech.listen(locale: runtime.locale) { spoken in
            if spoken.isEmpty {
                sayFailed = true
                return
            }
            query = spoken
            if FieldCorpus.asking(query) {
                openAnswer()
            }
        }
        if !started {
            sayFailed = true
        }
    }

    private func load() {
        guard let root = AppRuntime.resourceRoot()?.appendingPathComponent("Field") else { return }
        let core = (try? Data(contentsOf: root.appendingPathComponent("field.core.json"))) ?? Data()
        let st = runtime.packs?.active?.state.lowercased() ?? "tx"
        let extra = (try? Data(contentsOf: root.appendingPathComponent("field.\(st).json"))) ?? Data()
        cards = (try? FieldCorpus.load(core: core, state: extra)) ?? []
        if let state = runtime.packs?.active?.state {
            cards = FieldCorpus.visible(cards, state: state)
        }
        cards.sort {
            if $0.category != $1.category { return $0.category < $1.category }
            return $0.title.en < $1.title.en
        }
        jump()
    }

    /// SEARCH ranked a situation. Open the first answering card's steps.
    /// Remaining hits stay out — a title list is a menu of cards, not an
    /// answer. Unknown words already showed NO MATCH. Invent nothing.
    private func openAnswer() {
        guard FieldCorpus.asking(catalogQuery) else { return }
        guard let first = listCards.first else { return }
        sayFailed = false
        openRoute([first.id])
    }

    /// The map's hold card named the cards that answer the ground it held,
    /// best first. Take the first one this state's book actually has — the
    /// heat island card only ships in Texas, the ice-on-rock card only in New
    /// Mexico — and keep the rest of the route as a trail so DONE can open
    /// plant-use after plant-danger, bite after the state's snake, shelter
    /// after the trees. ALL CARDS dumps the trail and returns to SEARCH.
    private func jump() {
        guard let route = runtime.fieldJump else { return }
        runtime.fieldJump = nil
        openRoute(route)
    }

    private func openRoute(_ route: [String]) {
        query = ""
        let present = InspectField.presentRoute(route, in: Set(cards.map(\.id)))
        guard let first = present.first,
              let card = cards.first(where: { $0.id == first })
        else { return }
        fieldTrail = Array(present.dropFirst())
        fieldTrailTotal = present.count
        fieldTrailBook = InspectField.bookLine(for: present) ?? ""
        stepper = StepperState(card: card, index: 0, speaking: false, sentToParty: false)
    }

    private func leaveCard() {
        fieldTrail = []
        fieldTrailTotal = 0
        fieldTrailBook = ""
        stepper = nil
    }

    private func advanceTrail() {
        while !fieldTrail.isEmpty {
            let id = fieldTrail.removeFirst()
            if let card = cards.first(where: { $0.id == id }) {
                stepper = StepperState(card: card, index: 0, speaking: false, sentToParty: false)
                return
            }
        }
        fieldTrailTotal = 0
        fieldTrailBook = ""
        stepper = nil
    }

    private func stepTitle(_ s: StepperState) -> String {
        if !s.isLast { return "NEXT" }
        if let id = fieldTrail.first { return InspectField.nextAction(for: id) }
        return "DONE"
    }
}
