import SwiftUI
import Vitals
import TimerSync
import PaperGen
import Tokens
import MapLibreMap
import KitStore
import MeshDTN

private struct KitAssignPerson: Identifiable {
    let label: String
    let token: String
    var id: String { token }
}

struct ExpeditionTab: View {
    @Bindable var runtime: AppRuntime
    @State private var paperText = ""
    @State private var navChrome: String?
    @State private var timerName = ""
    @State private var timerTime = ""
    @State private var itemDraft = ""
    @State private var assigningID: String?

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
                            slider("HUNGER", Binding(get: { runtime.vitals.hunger }, set: { runtime.setYouRail(\.hunger, $0) }))
                            slider("THIRST", Binding(get: { runtime.vitals.thirst }, set: { runtime.setYouRail(\.thirst, $0) }))
                            slider("PAIN", Binding(get: { runtime.vitals.pain }, set: { runtime.setYouRail(\.pain, $0) }))
                            slider("WATER", Binding(get: { runtime.vitals.water }, set: { runtime.setYouRail(\.water, $0) }))
                            slider("FATIGUE", Binding(get: { runtime.vitals.fatigue }, set: { runtime.setYouRail(\.fatigue, $0) }))
                            slider("EXPOSURE", Binding(get: { runtime.vitals.weatherExposure }, set: { runtime.setYouRail(\.weatherExposure, $0) }))
                        }
                    }

                    sectionLabel("RED")
                    Button("APPLY RED BAND") {
                        runtime.applySelfRed()
                    }
                    .buttonStyle(HUDActionStyle(filled: true, crisis: true))
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
                            let _ = runtime.timerSeq
                            HUDField("NAME", text: $timerName, id: "exped.timer", locked: true)
                            HUDField("TIME",
                                text: $timerTime,
                                id: "exped.time",
                                digits: true
                            )
                            HStack(spacing: 8) {
                                Button("30 MIN") { timerTime = "30" }
                                    .buttonStyle(HoldActionStyle(filled: timerTime == "30", expand: true))
                                Button("1 HR") { timerTime = "1H" }
                                    .buttonStyle(HoldActionStyle(filled: timerTime == "1H", expand: true))
                                Button("2 HRS") { timerTime = "2H" }
                                    .buttonStyle(HoldActionStyle(filled: timerTime == "2H", expand: true))
                            }
                            VStack(spacing: 1) {
                                Button("SET") {
                                    guard let duration = TimerDuration.parse(timerTime) else { return }
                                    runtime.addPartyTimer(
                                        task: timerName,
                                        duration: duration
                                    )
                                    timerName = ""
                                    timerTime = ""
                                    runtime.hudKeys.close()
                                }
                                .buttonStyle(HUDDockStyle())
                            }
                            .background(Theme.glass())
                            .clipShape(Theme.plateRect())
                            .overlay(
                                Theme.plateRect()
                                    .strokeBorder(Theme.metalStroke, lineWidth: 1)
                            )
                            ForEach(Array(runtime.timers.doneLines().enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.silver.opacity(0.7))
                            }
                            ForEach(runtime.mesh.inboundTimers) { ev in
                                Text("RX TIMER \(ev.done ? "DONE" : "SET") \(ev.task) \(ev.from)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.warn)
                            }
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(runtime.timers.timers, id: \.id) { t in
                                        timerRow(t, now: context.date)
                                    }
                                    ForEach(runtime.timers.overduePlate(now: context.date), id: \.overdueRowID) { t in
                                        overdueRow(t)
                                    }
                                }
                            }
                        }
                    }

                    sectionLabel("INVENTORY")
                    HUDGlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HUDField("ITEM", text: $itemDraft, id: "exped.item", locked: true)
                            Button("ADD") {
                                runtime.addKitItem(itemDraft)
                                itemDraft = ""
                            }
                            .buttonStyle(HUDActionStyle(filled: false))
                            ForEach(runtime.kit.items) { item in
                                kitRow(item)
                            }
                            ForEach(Array(runtime.kit.hazards.enumerated()), id: \.offset) { _, hazard in
                                Text(hazard.uppercased())
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }

                    sectionLabel("TRIP")
                    HUDGlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HUDField("BRIEF",
                                text: Binding(
                                    get: { runtime.trip.brief },
                                    set: { runtime.trip.brief = $0 }
                                ),
                                id: "exped.brief"
                            )
                            Text("DUE \(dueClock)")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(runtime.trip.overdue() ? Theme.accent : Theme.silver)
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
        if runtime.vitals.band == .black {
            return .sos
        }
        if runtime.red.isRed || runtime.mesh.lastRedOn == true {
            return .crisis
        }
        switch runtime.vitals.band {
        case .green: return .go
        case .yellow: return .caution
        case .orange: return .heat
        case .red: return .crisis
        case .black: return .sos
        }
    }

    private var redPlate: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 10, height: 10)
            Text(runtime.lastConditionSOS.isEmpty ? L10n.t("red.plate", runtime.locale) : runtime.lastConditionSOS)
                .font(.system(size: runtime.lastConditionSOS.isEmpty ? 18 : 13, weight: .heavy))
                .foregroundStyle(Theme.accent)
                .lineLimit(2)
                .minimumScaleFactor(1)
            Spacer(minLength: 8)
            Button(L10n.t("red.cancel", runtime.locale)) {
                runtime.cancelSelfRed()
            }
            .buttonStyle(HUDOverlayChipStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.accent.opacity(0.16))
        .clipShape(Theme.plateRect())
        .overlay(
            Theme.plateRect()
                .strokeBorder(Theme.accent, lineWidth: 1.5)
        )
    }

    private func timerRow(_ t: PartyTimer, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(t.task) \(timerWho(t))")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                Spacer(minLength: 8)
                Text(clock(t.remaining(now: now)))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                Button("DONE") {
                    runtime.finishPartyTimer(t.id, task: t.task)
                }
                .buttonStyle(HUDOverlayChipStyle())
            }
            .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.silver.opacity(0.2))
                    Rectangle()
                        .fill(t.remaining(now: now) == 0 ? Theme.accent : Theme.silver)
                        .frame(width: geo.size.width * t.remainingFraction(now: now))
                }
            }
            .frame(height: 8)
            .clipShape(Theme.plateRect())
        }
    }

    private func kitRow(_ item: GearItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.name.uppercased())
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                    Text("\(item.count)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: Inspect.holdSeconds)
                        .onEnded { _ in
                            assigningID = item.id
                        }
                )
                Button("+1") { runtime.bumpKit(item.id, by: 1) }
                    .buttonStyle(HUDOverlayChipStyle())
                Button("−1") { runtime.bumpKit(item.id, by: -1) }
                    .buttonStyle(HUDOverlayChipStyle())
                Button(item.working ? "OK" : "FAILED") {
                    if item.working {
                        runtime.kit.markFailed(item.id, hazard: item.failureHazard ?? "FAILED")
                    } else {
                        runtime.kit.setWorking(item.id, working: true)
                    }
                    runtime.syncKit(item.id)
                }
                .buttonStyle(HUDOverlayChipStyle())
            }
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            if let assigned = item.assignedTo, !assigned.isEmpty {
                Text(assigned.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.silver.opacity(0.7))
            }
            if assigningID == item.id {
                Text("ASSIGN")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.silver.opacity(0.5))
                HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
                    Button("YOU") {
                        runtime.assignKitItem(item.id, to: runtime.timerOwner())
                        assigningID = nil
                    }
                    .buttonStyle(HUDOverlayChipStyle())
                    ForEach(assignPeople) { person in
                        Button(person.label.uppercased()) {
                            runtime.assignKitItem(item.id, to: person.token)
                            assigningID = nil
                        }
                        .buttonStyle(HUDOverlayChipStyle())
                    }
                    Button("NONE") {
                        runtime.assignKitItem(item.id, to: "")
                        assigningID = nil
                    }
                    .buttonStyle(HUDOverlayChipStyle())
                }
            }
        }
    }

    private var assignPeople: [KitAssignPerson] {
        var seen: [String] = []
        var rows: [KitAssignPerson] = []
        let you = runtime.timerOwner().uppercased()
        func add(_ label: String, token: String) {
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return }
            let key = token.uppercased()
            if key == you { return }
            if seen.contains(key) { return }
            seen.append(key)
            rows.append(KitAssignPerson(label: label.isEmpty ? token : label, token: token))
        }
        for member in runtime.roster.members {
            add(member.name, token: member.name)
        }
        for pip in runtime.mesh.pips {
            let named = (pip.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            add(named.isEmpty ? pip.from : named, token: named.isEmpty ? pip.from : named)
        }
        return rows
    }

    private func timerWho(_ t: PartyTimer) -> String {
        if t.who == "ALL", !t.owner.isEmpty, t.owner != "ALL" {
            return t.owner
        }
        return t.who.isEmpty ? t.owner : t.who
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    private func overdueRow(_ t: PartyTimer) -> some View {
        Text("\(L10n.t("overdue", runtime.locale)) \(t.task)")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Theme.accent.opacity(0.16))
            .clipShape(Theme.plateRect())
            .overlay(
                Theme.plateRect()
                    .strokeBorder(Theme.accent, lineWidth: 1)
            )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Theme.silver.opacity(0.5))
    }

    private var dueClock: String {
        runtime.trip.dueBack.formatted(date: .abbreviated, time: .shortened)
    }

    private func slider(_ title: String, _ value: Binding<Double>) -> some View {
        HUDVitalsRail(title: title, value: value)
    }
}

/// 44pt metal rail. Five color cells, not a system Slider. BLACK carries SOS.
struct HUDVitalsRail: View {
    let title: String
    @Binding var value: Double
    var editable: Bool = true

    var body: some View {
        let hit = BlackoutTokens.Chrome.mapChipHitPoints
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(ink)
            GeometryReader { geo in
                let width = geo.size.width
                let steps = PartyVitals.colorSteps
                HStack(spacing: 1) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        let band = PartyVitals.band(of: step)
                        let on = PartyVitals.band(of: PartyVitals.snap(value)) == band
                        ZStack {
                            Rectangle()
                                .fill(plateInk(for: band))
                            if band == .black {
                                Text("SOS")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(Theme.accent)
                                    .lineLimit(1)
                                    .minimumScaleFactor(1)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(band == .black || on ? 1 : 0.5)
                        .overlay(
                            Rectangle()
                                .strokeBorder(
                                    on ? (band == .black ? Theme.accent : Theme.silver) : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                    }
                }
                .padding(1)
                .frame(width: width, height: hit)
                .background(Theme.metalLow)
                .clipShape(Theme.plateRect())
                .overlay(
                    Theme.plateRect()
                        .strokeBorder(Theme.metalStroke, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .allowsHitTesting(editable)
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { gesture in
                        guard editable, width > 0 else { return }
                        let t = max(0, min(0.999, gesture.location.x / width))
                        let i = min(steps.count - 1, Int(t * CGFloat(steps.count)))
                        value = PartyVitals.snap(steps[i])
                    }
                )
            }
            .frame(height: hit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(2))))
        .accessibilityAdjustableAction { direction in
            guard editable else { return }
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
        switch PartyVitals.band(of: value) {
        case .green: return Theme.fix
        case .yellow: return Theme.caution
        case .orange: return Theme.heat
        case .red: return Theme.accent
        case .black: return Theme.accent
        }
    }

    private func plateInk(for band: ConditionBand) -> Color {
        switch band {
        case .green: return Theme.fix
        case .yellow: return Theme.caution
        case .orange: return Theme.heat
        case .red: return Theme.accent
        case .black: return Theme.void
        }
    }
}
