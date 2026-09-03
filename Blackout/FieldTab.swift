import SwiftUI
import FieldCorpus
import FieldStepper
import FieldSpeech
import VisionCapture
import VisionCoreML

struct FieldTab: View {
    @Bindable var runtime: AppRuntime
    @State private var cards: [FieldCard] = []
    @State private var stepper: StepperState?
    @State private var guess: VisionGuess?

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
            Button("VISION ADD FRAME") {
                var cap = GuidedCapture()
                cap.addFrame([0.2, 0.7, 0.1])
                let st = runtime.packs?.active?.state.lowercased() ?? "tx"
                let url = Bundle.main.resourceURL?
                    .appendingPathComponent("Resources/Vision/labels.\(st).json")
                if let url, let data = try? Data(contentsOf: url),
                   let book = try? VisionCoreML.load(data) {
                    guess = cap.guess(book: book)
                }
            }
            if let g = guess {
                Text("\(g.name) \(g.percent)% lookalikes \(g.lookalikes.joined(separator: ", ")) edible=\(g.edible)")
                    .font(.caption)
            }
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
