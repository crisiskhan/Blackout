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
                slider("Hunger", Binding(get: { runtime.vitals.hunger }, set: { runtime.vitals.hunger = $0 }))
                slider("Thirst", Binding(get: { runtime.vitals.thirst }, set: { runtime.vitals.thirst = $0 }))
                slider("Pain", Binding(get: { runtime.vitals.pain }, set: { runtime.vitals.pain = $0 }))
                slider("Water", Binding(get: { runtime.vitals.water }, set: { runtime.vitals.water = $0 }))
                slider("Fatigue", Binding(get: { runtime.vitals.fatigue }, set: { runtime.vitals.fatigue = $0 }))
                slider("Exposure", Binding(get: { runtime.vitals.weatherExposure }, set: { runtime.vitals.weatherExposure = $0 }))
                Button("APPLY RED BAND") {
                    runtime.applySelfRed()
                }
                .foregroundStyle(Theme.accent)
                if runtime.red.isRed || runtime.mesh.lastRedOn == true {
                    Text(L10n.t("red.plate", runtime.locale)).font(.title.weight(.bold)).foregroundStyle(.red)
                    Button(L10n.t("red.cancel", runtime.locale)) {
                        runtime.cancelSelfRed()
                    }
                }
                Text("ROSTER \(runtime.roster.code)")
                PartyQRImage(code: runtime.roster.code)
                Text(runtime.mesh.chromeNet).font(.caption).foregroundStyle(Color.orange)
                ForEach(runtime.roster.members) { m in
                    Text("\(m.role.rawValue) \(m.name)")
                }
                Button("JOIN NAV") { runtime.roster = runtime.roster.joining("Nav", role: .nav) }
                    .foregroundStyle(Theme.accent)
                Button("1 MIN TIMER SET") {
                    if runtime.timers.add(who: "ALL", task: "1min", duration: 60, subjectAll: true) != nil {
                        runtime.mesh.sendTimer(from: runtime.mesh.localID, task: "1min", done: false)
                    }
                }
                Button("2H WATER TIMER SET") {
                    if runtime.timers.add(who: "ALL", task: "water", duration: 7200, subjectAll: true) != nil {
                        runtime.mesh.sendTimer(from: runtime.mesh.localID, task: "water", done: false)
                    }
                }
                ForEach(runtime.timers.timers, id: \.id) { t in
                    HStack {
                        Text("\(t.task) \(t.who)")
                        Button("DONE") {
                            runtime.timers.markDone(t.id)
                            runtime.mesh.sendTimer(from: runtime.mesh.localID, task: t.task, done: true)
                        }
                    }
                }
                ForEach(runtime.mesh.inboundTimers) { ev in
                    Text("RX TIMER \(ev.done ? "DONE" : "SET") \(ev.task) \(ev.from)")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(runtime.timers.overduePlate(now: context.date), id: \.overdueRowID) { t in
                            Text("\(L10n.t("overdue", runtime.locale)) \(t.task) — not SOS")
                                .foregroundStyle(Color.orange)
                        }
                    }
                }
                Button("EXPORT PAPER") {
                    let text = PaperGen.export(trip: runtime.trip, roster: runtime.roster, packName: runtime.packs?.active?.name ?? "")
                    runtime.box.log("paper", text)
                }
            }
            .padding(12)
            .tint(Theme.accent)
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text(title).foregroundStyle(Theme.silver)
            Slider(value: value, in: 0...1)
                .tint(Theme.accent)
        }
    }
}
