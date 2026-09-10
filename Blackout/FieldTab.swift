import SwiftUI
import FieldCorpus
import FieldStepper
import FieldSpeech
import Tokens

struct FieldTab: View {
    @Bindable var runtime: AppRuntime
    @State private var cards: [FieldCard] = []
    @State private var stepper: StepperState?

    var body: some View {
        HUDPage(
            title: "FIELD",
            status: openStatus,
            statusTone: .silver
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // One card open, or the list. Never both. The map's FIELD button
                // has already chosen a card, and landing on the list with the
                // steps pushed under it makes you hunt for the thing you picked.
                if let s = stepper {
                    ScrollView {
                        open(s)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(cards) { c in
                                if cards.first(where: { $0.category == c.category })?.id == c.id {
                                    Text(c.category.uppercased())
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundStyle(Color(white: 0.5))
                                        .padding(.top, 10)
                                        .padding(.bottom, 4)
                                }
                                Button(loc(c.title)) {
                                    stepper = StepperState(card: c, index: 0, speaking: false, sentToParty: false)
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.silver)
                                .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                                .padding(.horizontal, 12)
                                .background(Theme.raised)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                Text(L10n.t("vision.none", runtime.locale))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.warn)
            }
        }
        .onAppear(perform: load)
        .onChange(of: runtime.fieldJump) { _, _ in jump() }
    }

    private var openStatus: String {
        guard let s = stepper else { return "" }
        return "STEP \(s.index + 1) OF \(s.card.steps.count)"
    }

    /// Every card ships both languages. The list was reading the locale and
    /// the steps were not, so a Spanish reader picked a card by its Spanish
    /// title and then got the instructions in English.
    private func loc(_ text: FieldLoc) -> String {
        runtime.locale == "es" ? text.es : text.en
    }

    /// One card, open at one step, with the way back to the list on it. The
    /// map comes straight in here, so without that way back a hold on the
    /// ground would be a one-way door into a single card.
    private func open(_ s: StepperState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(loc(s.card.title))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.white)
                Spacer(minLength: 8)
                Button("ALL CARDS") { stepper = nil }
                    .buttonStyle(HUDOverlayChipStyle())
            }
            Text(loc(s.card.situation))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.7))
                .fixedSize(horizontal: false, vertical: true)

            sectionLabel(L10n.t("stop.if", runtime.locale))
            ForEach(Array(s.card.stop_if.enumerated()), id: \.offset) { _, line in
                Text(loc(line))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.warn.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.warn.opacity(0.55), lineWidth: 1)
                    )
            }

            HUDGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc(s.step.`do`))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.silver)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(loc(s.step.why))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(loc(s.step.child))
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(loc(s.step.stop))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.warn)
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

            sectionLabel("CARE")
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
                // broken button rather than the end of the card.
                Button(s.isLast ? "DONE" : "NEXT") {
                    if s.isLast {
                        stepper = nil
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
            .foregroundStyle(Color(white: 0.5))
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

    /// The map's hold card named the cards that answer the ground it held,
    /// best first. Take the first one this state's book actually has — the
    /// heat island card only ships in Texas, the ice-on-rock card only in New
    /// Mexico — and fall through to the core card at the end of the list.
    /// Then clear the request, so coming back to FIELD later lands on the list
    /// as usual.
    private func jump() {
        guard let route = runtime.fieldJump else { return }
        runtime.fieldJump = nil
        for id in route {
            guard let card = cards.first(where: { $0.id == id }) else { continue }
            stepper = StepperState(card: card, index: 0, speaking: false, sentToParty: false)
            return
        }
    }
}
