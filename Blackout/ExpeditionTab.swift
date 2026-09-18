import SwiftUI
import Vitals
import TimerSync
import PaperGen
import TripBrief
import Tokens
import MapLibreMap
import KitStore
import MeshDTN
import RosterRoles

private struct KitAssignPerson: Identifiable {
    let label: String
    let token: String
    var id: String { token }
}

private enum ExpeditionPlate: String, CaseIterable {
    case condition, roster, timers, inventory, diary

    var title: String {
        switch self {
        case .condition: return "CONDITION"
        case .roster: return "ROSTER"
        case .timers: return "TIMERS"
        case .inventory: return "INVENTORY"
        case .diary: return "DIARY"
        }
    }
}

struct ExpeditionTab: View {
    @Bindable var runtime: AppRuntime
    @State private var paperText = ""
    @State private var navChrome: String?
    @State private var timerName = ""
    @State private var timerTime = ""
    @State private var timerChrome: String?
    @State private var itemDraft = ""
    @State private var kitChrome: String?
    @State private var diaryDraft = ""
    @State private var diaryChrome: String?
    @State private var assigningID: String?
    @State private var plate: ExpeditionPlate = .condition

    var body: some View {
        HUDPage(
            title: "EXPEDITION",
            status: "CONDITION \(runtime.vitals.band.rawValue.uppercased())",
            statusTone: statusTone
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if runtime.red.isRed || runtime.mesh.lastRedOn == true {
                    redPlate
                }
                plateRail
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        plateBody
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var plateRail: some View {
        HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
            ForEach(ExpeditionPlate.allCases, id: \.self) { item in
                Button(item.title) { plate = item }
                    .buttonStyle(HUDOverlayChipStyle(filled: plate == item))
            }
        }
    }

    @ViewBuilder
    private var plateBody: some View {
        switch plate {
        case .condition:
            conditionPlate
        case .roster:
            rosterPlate
        case .timers:
            timersPlate
        case .inventory:
            inventoryPlate
        case .diary:
            diaryPlate
        }
    }

    private var conditionPlate: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("CONDITION")
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    slider("HUNGER", Binding(get: { runtime.vitals.hunger }, set: { runtime.setYouRail(\.hunger, $0) }))
                    slider("THIRST", Binding(get: { runtime.vitals.thirst }, set: { runtime.setYouRail(\.thirst, $0) }))
                    slider("PAIN", Binding(get: { runtime.vitals.pain }, set: { runtime.setYouRail(\.pain, $0) }))
                    slider("FATIGUE", Binding(get: { runtime.vitals.fatigue }, set: { runtime.setYouRail(\.fatigue, $0) }))
                    slider("EXPOSURE", Binding(get: { runtime.vitals.weatherExposure }, set: { runtime.setYouRail(\.weatherExposure, $0) }))
                }
            }
        }
    }

    private var rosterPlate: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("ROSTER")
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        PartyQRImage(code: runtime.roster.code)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ROSTER \(runtime.roster.code)")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Theme.silver)
                            Text(
                                [runtime.mesh.chromeNet, runtime.mesh.chromeNear, runtime.mesh.chromeSignal]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · ")
                            )
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.warn)
                        }
                    }
                    ForEach(runtime.liveRoster) { row in
                        rosterRow(row)
                    }
                    if let navChrome {
                        Text(navChrome)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.warn)
                    }
                    Button("JOIN NAV") {
                        navChrome = runtime.seatNav() == nil ? nil : "NAV · SEATED"
                    }
                    .buttonStyle(HUDActionStyle(filled: false))
                }
            }
        }
    }

    private var timersPlate: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("TIMERS")
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    let _ = runtime.timerSeq
                    HUDField("NAME", text: $timerName, id: "exped.timer", locked: true)
                    HUDField("TIME",
                        text: $timerTime,
                        id: "exped.time",
                        submit: "SET",
                        digits: true,
                        onSubmit: setPartyTimer
                    )
                    HStack(spacing: 8) {
                        Button("30 MIN") {
                            timerTime = "30"
                            timerChrome = nil
                        }
                        .buttonStyle(HoldActionStyle(filled: timerTime == "30", expand: true))
                        Button("1 HR") {
                            timerTime = "1H"
                            timerChrome = nil
                        }
                        .buttonStyle(HoldActionStyle(filled: timerTime == "1H", expand: true))
                        Button("2 HRS") {
                            timerTime = "2H"
                            timerChrome = nil
                        }
                        .buttonStyle(HoldActionStyle(filled: timerTime == "2H", expand: true))
                    }
                    VStack(spacing: 1) {
                        Button("SET") {
                            guard TimerDuration.parse(timerTime) != nil else {
                                timerChrome = "SET TIME"
                                return
                            }
                            setPartyTimer()
                        }
                        .buttonStyle(HUDDockStyle())
                    }
                    .background(Theme.glass())
                    .clipShape(Theme.plateRect())
                    .overlay(
                        Theme.plateRect()
                            .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
                    )
                    if let timerChrome {
                        Text(timerChrome)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.warn)
                            .textCase(.uppercase)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
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
        }
    }

    private var inventoryPlate: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("INVENTORY")
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    HUDField("ITEM", text: $itemDraft, id: "exped.item", submit: "ADD", locked: true, onSubmit: addKitItem)
                    Button("ADD") {
                        if itemDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            kitChrome = "NAME ITEM"
                            return
                        }
                        addKitItem()
                    }
                    .buttonStyle(HUDActionStyle(filled: false))
                    if let kitChrome {
                        Text(kitChrome)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.warn)
                            .textCase(.uppercase)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
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
        }
    }

    private var diaryPlate: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("DIARY")
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HUDField("TODAY",
                        text: $diaryDraft,
                        id: "exped.diary",
                        submit: "LOG",
                        onSubmit: logToday
                    )
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(context.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                    }
                    Button("LOG") {
                        if diaryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            diaryChrome = "WRITE TODAY"
                            return
                        }
                        logToday()
                    }
                    .buttonStyle(HUDActionStyle(filled: false))
                    if let diaryChrome {
                        Text(diaryChrome)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.warn)
                            .textCase(.uppercase)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    sectionLabel("ATTENDANCE")
                    ForEach(runtime.diaryAttend) { row in
                        let mark = row.mark == .here ? "HERE" : "SILENT"
                        Text("\(row.name) · \(mark)")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(row.mark == .here ? Theme.silver : Theme.silver.opacity(0.55))
                            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                    }
                    ForEach(runtime.diary.feed()) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.name.uppercased())
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Theme.silver)
                            Text(line.at.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.silver.opacity(0.7))
                            Text(line.text)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.silver)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            sectionLabel("PAPER")
            Button("EXPORT PAPER") {
                let text = PaperGen.export(diary: runtime.diary, roster: runtime.paperRoster(), packName: runtime.packs?.active?.name ?? "")
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
                .strokeBorder(Theme.accent, lineWidth: Theme.strokeWidth(1.5))
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
        for row in runtime.liveRoster {
            if row.id == runtime.mesh.localID { continue }
            add(row.name, token: row.name)
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
                    .strokeBorder(Theme.accent, lineWidth: Theme.strokeWidth(1))
            )
    }

    private func rosterRow(_ row: LiveRosterRow) -> some View {
        let hit = BlackoutTokens.Chrome.mapChipHitPoints
        return HStack(spacing: 10) {
            rosterFace(row)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel("NAME")
                    .accessibilityValue(row.name)
                Text(row.statusTitle)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(rosterStatusInk(row.statusTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel("STATUS")
                    .accessibilityValue(row.statusTitle)
            }
            Spacer(minLength: 8)
            Button(row.role.title) {
                navChrome = runtime.cycleSeat(row.id)
            }
            .buttonStyle(HUDOverlayChipStyle())
            .accessibilityLabel("ROLE")
            .accessibilityValue(row.role.title)
        }
        .frame(maxWidth: .infinity, minHeight: hit, alignment: .leading)
    }

    private func rosterFace(_ row: LiveRosterRow) -> some View {
        let size = CGFloat(BlackoutTokens.Chrome.mapChipHitPoints)
        return Group {
            if let image = PersonEmblem.image(PersonEmblem.resolved(row.emblem)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(Theme.metalLow)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Theme.silver.opacity(0.35), lineWidth: Theme.strokeWidth(1))
        )
        .accessibilityLabel("FACE")
    }

    private func rosterStatusInk(_ title: String) -> Color {
        switch PartyStatus.parse(title) {
        case .good:
            return Theme.fix
        case .okay:
            return Theme.caution
        case .bad:
            return Theme.heat
        case .emergency:
            return Theme.accent
        }
    }

    private func setPartyTimer() {
        guard let duration = TimerDuration.parse(timerTime) else {
            timerChrome = "SET TIME"
            return
        }
        timerChrome = nil
        runtime.addPartyTimer(task: timerName, duration: duration)
        timerName = ""
        timerTime = ""
        runtime.hudKeys.close()
    }

    private func addKitItem() {
        let name = itemDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            kitChrome = "NAME ITEM"
            return
        }
        kitChrome = nil
        runtime.addKitItem(name)
        itemDraft = ""
    }

    private func logToday() {
        if runtime.logDiary(diaryDraft) {
            diaryChrome = runtime.mesh.chromeNet == "NO PEERS · LOGGED" ? "NO PEERS · LOGGED" : nil
            diaryDraft = ""
            runtime.hudKeys.close()
        } else {
            diaryChrome = "WRITE TODAY"
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Theme.silver.opacity(0.5))
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
                                    lineWidth: Theme.strokeWidth(1.5)
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
                        .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
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
