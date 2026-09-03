import SwiftUI
import FieldCorpus
import FieldStepper
import FieldSpeech

struct FieldTab: View {
    @Bindable var runtime: AppRuntime
    @State private var cards: [FieldCard] = []
    @State private var stepper: StepperState?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FIELD").foregroundStyle(Color(white: 0.85))
            Text(L10n.t("stop.if", runtime.locale)).font(.caption)
            List(cards) { c in
                Button(runtime.locale == "es" ? c.title.es : c.title.en) {
                    stepper = StepperState(card: c, index: 0, speaking: false, sentToParty: false)
                }
            }
            if let s = stepper {
                Text(s.step.`do`.en)
                Text(s.step.child.en).font(.caption)
                if let bpm = s.step.metronomeBpm { Text("CPR \(bpm)").font(.caption) }
                HStack {
                    Button("NEXT") { var x = s; x.next(); stepper = x }
                    Button("SPEAK") {
                        var x = s; x.speak(); stepper = x
                        FieldSpeech.speak(s.card, locale: runtime.locale, engine: runtime.speech)
                    }
                    Button("SEND TO PARTY") { var x = s; x.send(); stepper = x }
                }
            }
            Text(L10n.t("vision.none", runtime.locale))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.orange)
            Text("No on-device CoreML model ships in this build. Hash-to-label is not an ID. Fungi default LEAVE IT. Edible unlock is off.")
                .font(.caption2)
                .foregroundStyle(Color(white: 0.5))
        }
        .onAppear(perform: load)
        .padding(8)
    }

    private func load() {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Resources/Field") else { return }
        let core = (try? Data(contentsOf: root.appendingPathComponent("field.core.json"))) ?? Data()
        let st = runtime.packs?.active?.state.lowercased() ?? "tx"
        let extra = (try? Data(contentsOf: root.appendingPathComponent("field.\(st).json"))) ?? Data()
        cards = (try? FieldCorpus.load(core: core, state: extra)) ?? []
        if let state = runtime.packs?.active?.state {
            cards = FieldCorpus.visible(cards, state: state)
        }
    }
}
