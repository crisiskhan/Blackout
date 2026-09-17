import SwiftUI
import MapLibreMap
import MeshDTN
import Tokens
import Vitals
import TimerSync
import KitStore

/// Glass profile over a person mark. CALL and MESSAGE are mesh, never a cell.
struct PartyHoldCard: View {
    let person: HeldPerson
    let bearing: String
    let coordinates: String
    let vitals: PartyVitals?
    let onName: (String) -> Void
    let onStatus: (PartyStatus) -> Void
    let onVitals: (PartyVitals) -> Void
    let onCall: () -> Void
    let onMessage: () -> Void
    let onClose: () -> Void
    let onFaceHold: () -> Void
    let timers: TimerBoard
    let kit: KitBag
    let timerSeq: Int
    let kitSeq: Int
    let onKitBump: (String, Int) -> Void

    @State private var nameDraft: String = ""

    var body: some View {
        HoldGlassShell(onClose: onClose) {
            VStack(alignment: .leading, spacing: 10) {
                headline
                Rectangle()
                    .fill(Theme.silver.opacity(0.22))
                    .frame(height: 1)
                actions
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        statusRail
                        conditionBlock
                        rows
                        timerBlock
                        inventoryBlock
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onAppear { nameDraft = person.name }
    }

    private var headline: some View {
        HStack(alignment: .center, spacing: 12) {
            face
            VStack(alignment: .leading, spacing: 2) {
                if person.isYou {
                    HUDField("NAME",
                        text: $nameDraft,
                        id: "party.name",
                        locked: true,
                        pointSize: 20,
                        weight: .heavy,
                        ink: Color.white
                    )
                    .onChange(of: nameDraft) { _, value in
                        onName(value)
                    }
                } else {
                    Text(displayName)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                Text(person.isYou ? "YOU" : "PARTY")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: person.isYou ? .contain : .combine)
    }

    private var face: some View {
        let size: CGFloat = 56
        return Group {
            if let image = PersonEmblem.image(PersonEmblem.resolved(person.emblem)) {
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
        .contentShape(Circle())
        .accessibilityHidden(!person.isYou)
        .accessibilityLabel("FACE")
        .accessibilityHint("Hold to pick a mark")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "FACE") {
            if person.isYou { onFaceHold() }
        }
        .highPriorityGesture(
            LongPressGesture(minimumDuration: Inspect.holdSeconds)
                .onEnded { _ in
                    if person.isYou { onFaceHold() }
                }
        )
        .allowsHitTesting(person.isYou)
    }

    private var displayName: String {
        let named = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if named.isEmpty { return person.id.uppercased() }
        return named
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(key: "STATUS", value: person.status.title, ink: statusInk(person.status))
            row(key: "BEARING", value: bearing, ink: Color.white)
            row(key: "COORDINATES", value: coordinates, ink: Color.white)
        }
    }

    private var profileTimers: [PartyTimer] {
        timers.onProfile(personID: person.id, name: person.name, isYou: person.isYou)
    }

    private var kitItems: [GearItem] {
        kit.assigned(to: person.id, name: person.name, isYou: person.isYou)
    }

    private var timerBlock: some View {
        Group {
            if !profileTimers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TIMER")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.silver.opacity(0.75))
                    let _ = timerSeq
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(profileTimers) { t in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(t.task.uppercased())
                                            .font(.system(size: 13, weight: .heavy))
                                            .foregroundStyle(Theme.silver)
                                        Spacer(minLength: 8)
                                        Text(clock(t.remaining(now: context.date)))
                                            .font(.system(size: 13, weight: .heavy))
                                            .foregroundStyle(t.remaining(now: context.date) == 0 ? Theme.accent : Theme.silver)
                                    }
                                    if !t.owner.isEmpty,
                                       t.owner != "ALL",
                                       t.owner.uppercased() != displayName.uppercased(),
                                       t.owner.uppercased() != t.task.uppercased() {
                                        Text(t.owner.uppercased())
                                            .font(.system(size: 11, weight: .heavy))
                                            .foregroundStyle(Theme.silver.opacity(0.7))
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Rectangle()
                                                .fill(Theme.silver.opacity(0.2))
                                            Rectangle()
                                                .fill(t.remaining(now: context.date) == 0 ? Theme.accent : Theme.silver)
                                                .frame(width: geo.size.width * t.remainingFraction(now: context.date))
                                        }
                                    }
                                    .frame(height: 8)
                                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var inventoryBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            let _ = kitSeq
            Text("INVENTORY")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.75))
            if kitItems.isEmpty {
                Text("NONE")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.silver.opacity(0.7))
            } else {
                ForEach(kitItems) { item in
                    HStack(spacing: 8) {
                        Text(item.name.uppercased())
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                        Text("\(item.count)")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                        Spacer(minLength: 8)
                        Button("+1") { onKitBump(item.id, 1) }
                            .buttonStyle(HoldActionStyle(filled: false))
                        Button("−1") { onKitBump(item.id, -1) }
                            .buttonStyle(HoldActionStyle(filled: false))
                    }
                    .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                }
            }
        }
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    private var statusRail: some View {
        HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
            ForEach(PartyStatus.allCases, id: \.self) { status in
                Button(status.title) {
                    if person.isYou { onStatus(status) }
                }
                .buttonStyle(HoldActionStyle(filled: person.status == status))
                .allowsHitTesting(person.isYou)
            }
        }
    }

    private var conditionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let vitals {
                Text("CONDITION \(vitals.band.rawValue.uppercased())")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(bandInk(vitals.band))
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                HUDVitalsRail(title: "HUNGER", value: rail(\.hunger), editable: person.isYou)
                HUDVitalsRail(title: "THIRST", value: rail(\.thirst), editable: person.isYou)
                HUDVitalsRail(title: "PAIN", value: rail(\.pain), editable: person.isYou)
                HUDVitalsRail(title: "FATIGUE", value: rail(\.fatigue), editable: person.isYou)
                HUDVitalsRail(title: "EXPOSURE", value: rail(\.weatherExposure), editable: person.isYou)
            } else {
                Text("NO CONDITION")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.warn)
                    .lineLimit(1)
                    .minimumScaleFactor(1)
            }
        }
    }

    private func rail(_ key: WritableKeyPath<PartyVitals, Double>) -> Binding<Double> {
        Binding(
            get: { vitals?[keyPath: key] ?? 0 },
            set: { value in
                guard person.isYou else { return }
                var next = vitals ?? PartyVitals(water: 0.2, fatigue: 0.2, weatherExposure: 0.2)
                next[keyPath: key] = PartyVitals.snap(value)
                onVitals(next)
            }
        )
    }

    private func row(key: String, value: String, ink: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.75))
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("CALL") { onCall() }
                .buttonStyle(HUDActionStyle(filled: false))
            Button("MESSAGE") { onMessage() }
                .buttonStyle(HUDActionStyle(filled: false))
        }
    }

    private func statusInk(_ status: PartyStatus) -> Color {
        switch status {
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

    private func bandInk(_ band: ConditionBand) -> Color {
        switch band {
        case .green:
            return Theme.fix
        case .yellow:
            return Theme.caution
        case .orange:
            return Theme.heat
        case .red:
            return Theme.accent
        case .black:
            return Color.white
        }
    }
}
