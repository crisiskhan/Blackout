import SwiftUI
import Vitals
import TimerSync
import PaperGen
import Tokens

struct ExpeditionTab: View {
    @Bindable var runtime: AppRuntime
    @State private var paperText = ""
    @State private var navChrome: String?

    var body: some View {
        HUDPage(
            title: "EXPEDITION",
            status: "CONDITION \(runtime.vitals.band.rawValue.uppercased())",
            statusTone: statusTone
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionLabel("CONDITION")
                    HUDGlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            slider("HUNGER", Binding(get: { runtime.vitals.hunger }, set: { runtime.vitals.hunger = $0 }))
                            slider("THIRST", Binding(get: { runtime.vitals.thirst }, set: { runtime.vitals.thirst = $0 }))
                            slider("PAIN", Binding(get: { runtime.vitals.pain }, set: { runtime.vitals.pain = $0 }))
                            slider("WATER", Binding(get: { runtime.vitals.water }, set: { runtime.vitals.water = $0 }))
                            slider("FATIGUE", Binding(get: { runtime.vitals.fatigue }, set: { runtime.vitals.fatigue = $0 }))
                            slider("EXPOSURE", Binding(get: { runtime.vitals.weatherExposure }, set: { runtime.vitals.weatherExposure = $0 }))
                        }
                    }

                    sectionLabel("RED")
                    Button("APPLY RED BAND") {
                        runtime.applySelfRed()
                    }
                    .buttonStyle(HUDActionStyle(filled: true))
                    if runtime.red.isRed || runtime.mesh.lastRedOn == true {
                        redPlate
                    }

                    sectionLabel("ROSTER")
                    HUDGlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                PartyQRImage(code: runtime.roster.code)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ROSTER \(runtime.roster.code)")
                                        .font(.system(size: 13, weight: .heavy))
                                        .foregroundStyle(Theme.silver)
                                    Text(runtime.mesh.chromeNet)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Theme.warn)
                                }
                            }
                            ForEach(runtime.roster.members) { m in
                                Text("\(m.role.rawValue) \(m.name)")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Theme.silver)
                            }
                            if let navChrome {
                                Text(navChrome)
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Theme.warn)
                            }
                            Button("JOIN NAV") {
                                if runtime.roster.members.contains(where: { $0.role == .nav }) {
                                    navChrome = "NAV · SEATED"
                                } else {
                                    navChrome = nil
                                    runtime.roster = runtime.roster.joining("Nav", role: .nav)
                                }
                            }
                            .buttonStyle(HUDActionStyle(filled: false))
                        }
                    }

                    sectionLabel("TIMERS")
                    HUDGlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(spacing: 1) {
                                Button("1 MIN TIMER SET") {
                                    if runtime.timers.add(who: "ALL", task: "1min", duration: 60, subjectAll: true) != nil {
                                        runtime.mesh.sendTimer(from: runtime.mesh.localID, task: "1min", done: false)
                                    }
                                }
                                .buttonStyle(HUDDockStyle())
                                Button("2H WATER TIMER SET") {
                                    if runtime.timers.add(who: "ALL", task: "water", duration: 7200, subjectAll: true) != nil {
                                        runtime.mesh.sendTimer(from: runtime.mesh.localID, task: "water", done: false)
                                    }
                                }
                                .buttonStyle(HUDDockStyle())
                            }
                            .background(Theme.raised)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Theme.silver.opacity(0.22), lineWidth: 1)
                            )
                            ForEach(runtime.timers.timers, id: \.id) { t in
                                HStack {
                                    Text("\(t.task) \(t.who)")
                                        .font(.system(size: 13, weight: .heavy))
                                        .foregroundStyle(Theme.silver)
                                    Spacer(minLength: 8)
                                    Button("DONE") {
                                        runtime.timers.markDone(t.id)
                                        runtime.mesh.sendTimer(from: runtime.mesh.localID, task: t.task, done: true)
                                    }
                                    .buttonStyle(HUDOverlayChipStyle())
                                }
                                .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                            }
                            ForEach(runtime.timers.doneLines(), id: \.self) { line in
                                Text(line)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color(white: 0.7))
                            }
                            ForEach(runtime.mesh.inboundTimers) { ev in
                                Text("RX TIMER \(ev.done ? "DONE" : "SET") \(ev.task) \(ev.from)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.warn)
                            }
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(runtime.timers.overduePlate(now: context.date), id: \.overdueRowID) { t in
                                        overdueRow(t)
                                    }
                                }
                            }
                        }
                    }

                    sectionLabel("KIT")
                    HUDGlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(runtime.kit.items) { item in
                                Button {
                                    if item.working {
                                        runtime.kit.markFailed(item.id, hazard: item.failureHazard ?? "FAILED")
                                    } else {
                                        runtime.kit.setWorking(item.id, working: true)
                                    }
                                } label: {
                                    HStack {
                                        Text(item.name.uppercased())
                                            .foregroundStyle(Theme.silver)
                                        Spacer()
                                        Text(item.working ? "OK" : "FAILED")
                                            .foregroundStyle(item.working ? Theme.accent : Theme.warn)
                                    }
                                }
                                .font(.system(size: 13, weight: .heavy))
                                .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                            }
                            ForEach(runtime.kit.hazards, id: \.self) { hazard in
                                Text(hazard.uppercased())
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.warn)
                            }
                        }
                    }

                    sectionLabel("TRIP")
                    HUDGlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("BRIEF", text: Binding(
                                get: { runtime.trip.brief },
                                set: { runtime.trip.brief = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.silver)
                            .padding(.horizontal, 10)
                            .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                            .background(Theme.raised)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text("DUE \(dueClock)")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(runtime.trip.overdue() ? Theme.warn : Theme.silver)
                        }
                    }

                    sectionLabel("PAPER")
                    Button("EXPORT PAPER") {
                        let text = PaperGen.export(trip: runtime.trip, roster: runtime.roster, packName: runtime.packs?.active?.name ?? "")
                        paperText = text
                        runtime.box.log("paper", text)
                    }
                    .buttonStyle(HUDActionStyle(filled: false))
                    if !paperText.isEmpty {
                        HUDGlassCard {
                            Text(paperText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.silver)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var statusTone: HUDStatusTone {
        if runtime.red.isRed || runtime.mesh.lastRedOn == true {
            return .crisis
        }
        switch runtime.vitals.band {
        case .green: return .silver
        case .yellow: return .warn
        case .red: return .crisis
        }
    }

    private var redPlate: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 10, height: 10)
            Text(L10n.t("red.plate", runtime.locale))
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.accent)
            Spacer(minLength: 8)
            Button(L10n.t("red.cancel", runtime.locale)) {
                runtime.cancelSelfRed()
            }
            .buttonStyle(HUDOverlayChipStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.accent.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1.5)
        )
    }

    private func overdueRow(_ t: PartyTimer) -> some View {
        Text("\(L10n.t("overdue", runtime.locale)) \(t.task)")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.warn)
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Theme.warn.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.warn, lineWidth: 1)
            )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Color(white: 0.5))
    }

    private var dueClock: String {
        runtime.trip.dueBack.formatted(date: .abbreviated, time: .shortened)
    }

    private func slider(_ title: String, _ value: Binding<Double>) -> some View {
        HUDVitalsRail(title: title, value: value)
    }
}

/// 44pt metal rail. Five ticks aligned to PartyVitals band math. Not a system Slider.
struct HUDVitalsRail: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        let hit = BlackoutTokens.Chrome.mapChipHitPoints
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.silver)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.raised)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ink.opacity(0.88))
                        .frame(width: max(0, width * CGFloat(value)))
                    ForEach(Array(PartyVitals.railSteps.enumerated()), id: \.offset) { _, step in
                        if step > 0 && step < 1 {
                            Rectangle()
                                .fill(Theme.silver.opacity(0.4))
                                .frame(width: 1, height: hit * 0.5)
                                .offset(x: width * CGFloat(step))
                        }
                    }
                }
                .frame(height: hit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.silver.opacity(0.28), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { gesture in
                        guard width > 0 else { return }
                        value = PartyVitals.snap(gesture.location.x / width)
                    }
                )
            }
            .frame(height: hit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(2))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = PartyVitals.step(value, 1)
            case .decrement:
                value = PartyVitals.step(value, -1)
            @unknown default:
                break
            }
        }
    }

    private var ink: Color {
        if value >= PartyVitals.redAt { return Theme.accent }
        if value >= PartyVitals.yellowAt { return Theme.warn }
        return Theme.silver
    }
}
