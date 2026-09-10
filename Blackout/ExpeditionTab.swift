import SwiftUI
import Vitals
import TimerSync
import PaperGen
import Tokens

struct ExpeditionTab: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        HUDPage(
            title: "EXPEDITION",
            status: "CONDITION \(runtime.vitals.band.rawValue.uppercased())"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HUDGlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            slider("Hunger", Binding(get: { runtime.vitals.hunger }, set: { runtime.vitals.hunger = $0 }))
                            slider("Thirst", Binding(get: { runtime.vitals.thirst }, set: { runtime.vitals.thirst = $0 }))
                            slider("Pain", Binding(get: { runtime.vitals.pain }, set: { runtime.vitals.pain = $0 }))
                            slider("Water", Binding(get: { runtime.vitals.water }, set: { runtime.vitals.water = $0 }))
                            slider("Fatigue", Binding(get: { runtime.vitals.fatigue }, set: { runtime.vitals.fatigue = $0 }))
                            slider("Exposure", Binding(get: { runtime.vitals.weatherExposure }, set: { runtime.vitals.weatherExposure = $0 }))
                        }
                    }
                    Button("APPLY RED BAND") {
                        runtime.applySelfRed()
                    }
                    .buttonStyle(HUDActionStyle(filled: true))
                    if runtime.red.isRed || runtime.mesh.lastRedOn == true {
                        Text(L10n.t("red.plate", runtime.locale))
                            .font(.title.weight(.bold))
                            .foregroundStyle(Theme.accent)
                        Button(L10n.t("red.cancel", runtime.locale)) {
                            runtime.cancelSelfRed()
                        }
                        .buttonStyle(HUDActionStyle(filled: false))
                    }
                    HUDGlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ROSTER \(runtime.roster.code)")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Theme.silver)
                            PartyQRImage(code: runtime.roster.code)
                            Text(runtime.mesh.chromeNet)
                                .font(.caption)
                                .foregroundStyle(Theme.warn)
                            ForEach(runtime.roster.members) { m in
                                Text("\(m.role.rawValue) \(m.name)")
                                    .foregroundStyle(Theme.silver)
                            }
                            Button("JOIN NAV") { runtime.roster = runtime.roster.joining("Nav", role: .nav) }
                                .buttonStyle(HUDActionStyle(filled: false))
                        }
                    }
                    HUDGlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("1 MIN TIMER SET") {
                                if runtime.timers.add(who: "ALL", task: "1min", duration: 60, subjectAll: true) != nil {
                                    runtime.mesh.sendTimer(from: runtime.mesh.localID, task: "1min", done: false)
                                }
                            }
                            .buttonStyle(HUDActionStyle(filled: false))
                            Button("2H WATER TIMER SET") {
                                if runtime.timers.add(who: "ALL", task: "water", duration: 7200, subjectAll: true) != nil {
                                    runtime.mesh.sendTimer(from: runtime.mesh.localID, task: "water", done: false)
                                }
                            }
                            .buttonStyle(HUDActionStyle(filled: false))
                            ForEach(runtime.timers.timers, id: \.id) { t in
                                HStack {
                                    Text("\(t.task) \(t.who)")
                                        .foregroundStyle(Theme.silver)
                                    Button("DONE") {
                                        runtime.timers.markDone(t.id)
                                        runtime.mesh.sendTimer(from: runtime.mesh.localID, task: t.task, done: true)
                                    }
                                    .buttonStyle(HUDOverlayChipStyle())
                                }
                            }
                            ForEach(runtime.timers.doneLines(), id: \.self) { line in
                                Text(line).font(.caption).foregroundStyle(Color(white: 0.7))
                            }
                            ForEach(runtime.mesh.inboundTimers) { ev in
                                Text("RX TIMER \(ev.done ? "DONE" : "SET") \(ev.task) \(ev.from)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.warn)
                            }
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(runtime.timers.overduePlate(now: context.date), id: \.overdueRowID) { t in
                                        Text("\(L10n.t("overdue", runtime.locale)) \(t.task)")
                                            .foregroundStyle(Theme.warn)
                                    }
                                }
                            }
                        }
                    }
                    Button("EXPORT PAPER") {
                        let text = PaperGen.export(trip: runtime.trip, roster: runtime.roster, packName: runtime.packs?.active?.name ?? "")
                        runtime.box.log("paper", text)
                    }
                    .buttonStyle(HUDActionStyle(filled: false))
                }
            }
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
