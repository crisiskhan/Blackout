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
        VStack(alignment: .leading, spacing: 8) {
            Text("FIELD")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.silver)
            Text(L10n.t("stop.if", runtime.locale)).font(.caption)
            // One card open, or the list. Never both. The map's FIELD button
            // has already chosen a card, and landing on the list with the
            // steps pushed under it makes you hunt for the thing you picked.
            if let s = stepper {
                open(s)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(cards) { c in
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
            Text(L10n.t("sos.call", runtime.locale)).font(.caption.weight(.bold))
            Text(L10n.t("sos.offer", runtime.locale)).font(.caption2).foregroundStyle(Color(white: 0.55))
            Text(L10n.t("vision.none", runtime.locale))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.orange)
            Text("No on-device CoreML model ships in this build. Hash-to-label is not an ID. Fungi default LEAVE IT. Edible unlock is off.")
                .font(.caption2)
                .foregroundStyle(Color(white: 0.5))
        }
        .onAppear(perform: load)
        .onChange(of: runtime.fieldJump) { _, _ in jump() }
        .padding(8)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(loc(s.card.title))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.white)
                Spacer(minLength: 8)
                Button("ALL CARDS") { stepper = nil }
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            }
            Text("STEP \(s.index + 1) OF \(s.card.steps.count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(white: 0.55))
            Text(loc(s.step.`do`))
            Text(loc(s.step.child)).font(.caption)
            if let bpm = s.step.metronomeBpm { Text("CPR \(bpm)").font(.caption) }
            HStack {
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
                .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                Button("SPEAK") {
                    var x = s; x.speak(); stepper = x
                    if !FieldSpeech.speak(s.card, locale: runtime.locale, engine: runtime.speech) {
                        runtime.speechChrome = "SPEECH FAILED"
                    } else {
                        runtime.speechChrome = ""
                    }
                }
                .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                Button("SEND TO PARTY") {
                    var x = s
                    x.send()
                    stepper = x
                    runtime.sendFieldToParty(cardID: s.card.id)
                }
                .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            }
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Theme.silver)
            Text(runtime.mesh.chromeNet).font(.caption).foregroundStyle(Color.orange)
            if !runtime.speechChrome.isEmpty {
                Text(runtime.speechChrome).font(.caption).foregroundStyle(Color.orange)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
