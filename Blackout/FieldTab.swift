import SwiftUI
import UIKit
import FieldCorpus
import FieldStepper
import FieldAsk
import MapLibreMap
import Tokens
import VisionCoreML

struct FieldTab: View {
    @Bindable var runtime: AppRuntime
    @State private var cards: [FieldCard] = []
    @State private var showVision = false

    var body: some View {
        HUDPage(
            title: "FIELD",
            status: fieldStatus,
            statusTone: fieldTone
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // One card open, or SEARCH. Never both. SEARCH submits the
                // answering card's steps. A title dump is not an answer.
                // VISION stays on SEARCH so the open procedure is the book.
                Group {
                    if let s = runtime.field.stepper {
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
                        visionHUD
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay {
            if showVision {
                #if canImport(AVFoundation) && canImport(UIKit)
                VisionStill(
                    onImage: { image in
                        showVision = false
                        runtime.applyFieldVision(image: image)
                    },
                    onFail: {
                        showVision = false
                        runtime.applyFieldVision(image: nil)
                    },
                    onCancel: { showVision = false }
                )
                .ignoresSafeArea()
                .transition(.opacity)
                #endif
            }
        }
        .animation(Theme.Motion.heavy, value: showVision)
        .onAppear(perform: load)
        .onDisappear {
            runtime.haltFieldListen()
            showVision = false
        }
        .onChange(of: runtime.fieldJump) { _, _ in jump() }
        .onChange(of: runtime.packs?.active?.id) { _, _ in
            load()
        }
        .onChange(of: runtime.field.query) { _, _ in
            runtime.field.askFailed = false
        }
    }

    private var fieldStatus: String {
        if runtime.speech.listening { return L10n.t("field.say", runtime.locale) }
        if runtime.field.askBusy { return L10n.t("field.ask", runtime.locale) }
        if runtime.speechChrome == "SPEECH FAILED" { return "SPEECH FAILED" }
        if let s = runtime.field.stepper {
            // A hold named a trail of plant / bite / use cards. STEP 1 OF 1
            // on every one of them hides that you are walking the biome book.
            if runtime.field.trailTotal > 1 {
                let at = runtime.field.trailTotal - runtime.field.trail.count
                return "\(L10n.t("field.card", runtime.locale)) \(at) \(L10n.t("field.of", runtime.locale)) \(runtime.field.trailTotal)"
            }
            return "\(L10n.t("field.step", runtime.locale)) \(s.index + 1) \(L10n.t("field.of", runtime.locale)) \(s.card.steps.count)"
        }
        guard let g = runtime.field.guess else {
            if runtime.field.askFailed { return "NO MATCH" }
            return L10n.t("field.type", runtime.locale)
        }
        if g.noModel { return L10n.t("vision.none", runtime.locale) }
        if g.leaveIt {
            return "\(g.name) · \(L10n.t("vision.leave", runtime.locale))"
        }
        return g.name
    }

    private var fieldTone: HUDStatusTone {
        if runtime.speech.listening { return .silver }
        if runtime.field.askBusy { return .silver }
        if runtime.speechChrome == "SPEECH FAILED" { return .warn }
        if runtime.field.askFailed { return .warn }
        if runtime.field.stepper != nil { return .silver }
        if let g = runtime.field.guess {
            if g.leaveIt { return .crisis }
            if g.noModel { return .warn }
        }
        return .silver
    }

    @ViewBuilder
    private var visionHUD: some View {
        sectionLabel("VISION")
        Button("VISION") {
            runtime.field.guess = nil
            #if canImport(AVFoundation) && canImport(UIKit)
            showVision = true
            #else
            runtime.applyFieldVision(image: nil)
            #endif
        }
        .buttonStyle(HUDActionStyle(filled: true))
        if let g = runtime.field.guess {
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
                            ForEach(Array(g.lookalikes.enumerated()), id: \.offset) { _, word in
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
                openRoute(route, speakFirst: true)
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
                    .foregroundStyle(Theme.silver)
                Spacer(minLength: 8)
                if !runtime.field.fork.isEmpty {
                    Button(L10n.t("field.back", runtime.locale)) { backFork() }
                        .buttonStyle(HUDOverlayChipStyle())
                }
                Button(L10n.t("field.search", runtime.locale)) { leaveCard() }
                    .buttonStyle(HUDOverlayChipStyle())
            }
            plateRail
            switch runtime.field.plate {
            case .walk:
                walkPlate(s)
            case .care:
                carePlate(s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var plateRail: some View {
        HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
            ForEach(FieldPlate.allCases, id: \.self) { item in
                Button(plateTitle(item)) { runtime.field.plate = item }
                    .buttonStyle(HUDOverlayChipStyle(filled: runtime.field.plate == item))
            }
        }
    }

    private func plateTitle(_ item: FieldPlate) -> String {
        switch item {
        case .walk: return L10n.t("field.do", runtime.locale)
        case .care: return L10n.t("field.care", runtime.locale)
        }
    }

    @ViewBuilder
    private func walkPlate(_ s: StepperState) -> some View {
        sectionLabel("SITUATION")
        Text(loc(s.card.situation))
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.silver.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
        if !runtime.field.trailBook.isEmpty {
            Text(runtime.field.trailBook)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        causeChips(s)

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
                        .frame(maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)
                }
                if s.card.steps.count > 1 {
                    Text("\(L10n.t("field.step", runtime.locale)) \(s.index + 1) \(L10n.t("field.of", runtime.locale)) \(s.card.steps.count)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                }
                ForEach(Array(FieldCorpus.doLines(loc(s.step.`do`)).enumerated()), id: \.offset) { n, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n + 1)")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                            .frame(minWidth: 18, alignment: .leading)
                        Text(line)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                sectionLabel("HANDS")
                Text(loc(s.step.child))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .fixedSize(horizontal: false, vertical: true)
                Text(loc(s.step.why))
                    .font(.caption.weight(.semibold))
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
        HStack(spacing: 8) {
            // On the last step NEXT did nothing at all, which reads as a
            // broken button rather than the end of the card. A hold that
            // named a trail of plant / bite / use cards still has work
            // after this one — name that procedure the same way the hold
            // button did, then open it. SEARCH dumps the rest and
            // returns to the catalog field.
            Button(stepTitle(s)) {
                if s.isLast {
                    advanceTrail()
                } else {
                    var x = s
                    x.next()
                    runtime.field.stepper = x
                }
            }
            .buttonStyle(HUDActionStyle(filled: true))
            Button("SPEAK") {
                var x = s
                x.speak()
                runtime.field.stepper = x
                runtime.speakFieldStep(s.card, step: s.index)
            }
            .buttonStyle(HUDActionStyle(filled: false))
        }
        if !runtime.speechChrome.isEmpty {
            Text(runtime.speechChrome).font(.caption).foregroundStyle(Theme.warn)
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
                .clipShape(Theme.plateRect())
                .overlay(
                    Theme.plateRect()
                        .strokeBorder(Theme.accent.opacity(0.55), lineWidth: Theme.strokeWidth(1))
                )
        }
    }

    @ViewBuilder
    private func carePlate(_ s: StepperState) -> some View {
        sectionLabel("GET-TO-CARE")
        Text(loc(s.card.get_to_care))
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.silver)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.glass())
            .clipShape(Theme.plateRect())

        Button(L10n.t("field.send", runtime.locale)) {
            var x = s
            x.send()
            runtime.field.stepper = x
            runtime.sendFieldToParty(cardID: s.card.id)
        }
        .buttonStyle(HUDActionStyle(filled: false))
        Text(
            [runtime.mesh.chromeNet, runtime.mesh.chromeNear, runtime.mesh.chromeSignal]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        ).font(.caption).foregroundStyle(Theme.warn)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Theme.silver.opacity(0.5))
    }

    @ViewBuilder
    private func causeChips(_ s: StepperState) -> some View {
        if let links = s.card.links, !links.isEmpty {
            sectionLabel("CAUSE")
            HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
                ForEach(links) { link in
                    Button(link.label) { openLink(link) }
                        .buttonStyle(HUDOverlayChipStyle())
                }
            }
        }
    }

    /// SEARCH is the menu. Empty is waiting, not a dump of the book. Hits
    /// are not a title list — the SEARCH chip (or keyboard Search) opens the
    /// first answering card. A miss opens a live ASK walk on the same card.
    /// SEARCH on an open card returns here.
    private var catalogQuery: String {
        runtime.field.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var catalogMiss: Bool {
        runtime.field.askFailed
    }

    private var listCards: [FieldCard] {
        FieldCorpus.ask(
            FieldCorpus.chapter(cards, pack: runtime.packs?.active?.id),
            query: catalogQuery,
            locale: runtime.locale
        )
    }

    private var queryBind: Binding<String> {
        Binding(
            get: { runtime.field.query },
            set: { runtime.field.query = $0 }
        )
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                HUDField(
                    L10n.t("field.search", runtime.locale),
                    text: queryBind,
                    id: "field.search",
                    submit: L10n.t("field.search", runtime.locale),
                    onSubmit: openAnswer
                )
                Button(L10n.t("field.search", runtime.locale)) { openAnswer() }
                    .buttonStyle(HUDOverlayChipStyle())
                Button(L10n.t("field.say", runtime.locale)) { say() }
                    .buttonStyle(HUDOverlayChipStyle(filled: runtime.speech.listening))
            }
            if runtime.field.sayFailed {
                Text("SAY FAILED")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.warn)
            }
        }
    }

    /// Spoken question uses the same ask path as type. Deny, PTT live, and
    /// a missing on-device recognizer are SAY FAILED — not a network model.
    /// A second tap stops the mic.
    private func say() {
        runtime.field.sayFailed = false
        if runtime.ptt.live || runtime.clipLive {
            runtime.field.sayFailed = true
            return
        }
        if runtime.speech.listening {
            runtime.speech.endListen()
            return
        }
        let started = runtime.speech.listen(locale: runtime.locale) { spoken in
            if spoken.isEmpty {
                runtime.field.sayFailed = true
                return
            }
            runtime.field.query = spoken
            if FieldCorpus.asking(runtime.field.query) {
                openAnswer()
            }
        }
        if !started {
            runtime.field.sayFailed = true
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
    /// answer. Unknown words open a live ASK walk on the same stepper.
    /// SEARCH while ASK is building cancels that walk, then starts again.
    private func openAnswer() {
        if runtime.field.askBusy {
            runtime.cancelFieldAsk()
            if !FieldCorpus.asking(catalogQuery) { return }
        }
        guard FieldCorpus.asking(catalogQuery) else { return }
        if let first = listCards.first {
            runtime.field.sayFailed = false
            runtime.field.askFailed = false
            runtime.field.fieldQuery = catalogQuery
            openRoute([first.id], speakFirst: true)
            return
        }
        runtime.beginFieldAsk(
            query: catalogQuery,
            chapter: FieldCorpus.chapter(cards, pack: runtime.packs?.active?.id),
            locale: runtime.locale,
            packName: runtime.packs?.active?.name ?? "pack",
            packId: runtime.packs?.active?.id
        )
    }

    /// The map's hold card named the cards that answer the ground it held,
    /// best first. Take the first one this state's book actually has — the
    /// heat island card only ships in Texas, the ice-on-rock card only in New
    /// Mexico — and keep the rest of the route as a trail so DONE can open
    /// plant-use after plant-danger, bite after the state's snake, shelter
    /// after the trees. SEARCH dumps the trail and returns to the field.
    private func jump() {
        guard let route = runtime.fieldJump else { return }
        runtime.fieldJump = nil
        runtime.field.fieldQuery = ""
        runtime.field.fork = []
        openRoute(route)
    }

    private func openRoute(_ route: [String], speakFirst: Bool = false) {
        runtime.field.query = ""
        let present = InspectField.presentRoute(route, in: Set(cards.map(\.id)))
        guard let first = present.first,
              let card = cards.first(where: { $0.id == first })
        else { return }
        runtime.field.trail = Array(present.dropFirst())
        runtime.field.trailTotal = present.count
        runtime.field.trailBook = InspectField.bookLine(for: present) ?? ""
        runtime.field.plate = .walk
        let wired = FieldTree.decorate(card, query: runtime.field.fieldQuery)
        runtime.field.stepper = StepperState(card: wired, index: 0, speaking: false, sentToParty: false)
        if speakFirst {
            runtime.speakFieldStep(wired, step: 0)
        }
    }

    private func leaveCard() {
        runtime.field.leaveCard()
    }

    private func openLink(_ link: FieldLink) {
        if let current = runtime.field.stepper?.card {
            runtime.field.fork.append(current)
        }
        let chapter = FieldCorpus.chapter(cards, pack: runtime.packs?.active?.id)
        let next = FieldTree.openLink(
            link,
            chapter: chapter,
            packId: runtime.packs?.active?.id,
            locale: runtime.locale
        )
        runtime.field.fieldQuery = link.ask
        runtime.field.trail = []
        runtime.field.trailTotal = 1
        runtime.field.trailBook = link.label
        runtime.field.plate = .walk
        runtime.field.stepper = StepperState(card: next, index: 0, speaking: false, sentToParty: false)
        runtime.speakFieldStep(next, step: 0)
    }

    private func backFork() {
        guard let prev = runtime.field.fork.popLast() else { return }
        runtime.field.plate = .walk
        runtime.field.stepper = StepperState(card: prev, index: 0, speaking: false, sentToParty: false)
    }

    private func advanceTrail() {
        while !runtime.field.trail.isEmpty {
            let id = runtime.field.trail.removeFirst()
            if let card = cards.first(where: { $0.id == id }) {
                runtime.field.plate = .walk
                runtime.field.stepper = StepperState(card: card, index: 0, speaking: false, sentToParty: false)
                return
            }
        }
        runtime.field.trailTotal = 0
        runtime.field.trailBook = ""
        runtime.field.stepper = nil
        runtime.field.plate = .walk
    }

    private func stepTitle(_ s: StepperState) -> String {
        if !s.isLast { return L10n.t("field.next", runtime.locale) }
        if let id = runtime.field.trail.first { return InspectField.nextAction(for: id) }
        return L10n.t("field.done", runtime.locale)
    }
}
