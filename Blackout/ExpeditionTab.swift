import SwiftUI
import Vitals
import TimerSync
import PaperGen

struct ExpeditionTab: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("EXPEDITION").foregroundStyle(Color(white: 0.85))
                Text("CONDITION \(runtime.vitals.band.rawValue.uppercased())")
                slider("Water", $runtime.vitals.water)
                slider("Fatigue", $runtime.vitals.fatigue)
                slider("Exposure", $runtime.vitals.weatherExposure)
                Button("APPLY RED BAND") { runtime.red.apply(runtime.vitals) }
                if runtime.red.isRed {
                    Text(L10n.t("red.plate", runtime.locale)).font(.title.weight(.bold)).foregroundStyle(.red)
                    Button(L10n.t("red.cancel", runtime.locale)) { runtime.red.cancelRED() }
                }
                Text("ROSTER \(runtime.roster.code)")
                ForEach(runtime.roster.members) { m in
                    Text("\(m.role.rawValue) \(m.name)")
                }
                Button("JOIN NAV") { runtime.roster = runtime.roster.joining("Nav", role: .nav) }
                Button("2H WATER TIMER") {
                    _ = runtime.timers.add(who: "ALL", task: "water", duration: 7200, subjectAll: true)
                }
                ForEach(runtime.timers.overduePlate(), id: \.id) { t in
                    Text("\(L10n.t("overdue", runtime.locale)) \(t.task) — not SOS")
                        .foregroundStyle(Color.orange)
                }
                Button("EXPORT PAPER") {
                    let text = PaperGen.export(trip: runtime.trip, roster: runtime.roster, packName: runtime.packs?.active?.name ?? "")
                    runtime.box.log("paper", text)
                }
            }
            .padding(12)
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Slider(value: value, in: 0...1)
        }
    }
}
