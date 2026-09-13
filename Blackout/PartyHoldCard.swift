import SwiftUI
import MapLibreMap
import MeshDTN
import Tokens
import Vitals

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

    @State private var drag: CGFloat = 0
    @State private var nameDraft: String = ""

    private static let smallestUsableCard: CGFloat = 180

    private var corner: CGFloat { CGFloat(BlackoutTokens.Chrome.holdCardCornerPoints) }

    var body: some View {
        GeometryReader { canvas in
            let cap = max(
                Self.smallestUsableCard,
                canvas.size.height * CGFloat(BlackoutTokens.Chrome.holdCardMaxHeightFraction)
            )
            ZStack(alignment: .bottom) {
                scrim
                card(cappedAt: cap)
                    .offset(y: drag)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { drag = max(0, $0.translation.height) }
                    .onEnded { value in
                        if value.translation.height > CGFloat(BlackoutTokens.Chrome.holdCardDismissDragPoints) {
                            onClose()
                        }
                        withAnimation(Theme.Motion.heavy) { drag = 0 }
                    }
            )
        }
        .transition(.opacity)
        .onAppear { nameDraft = person.name }
    }

    private var scrim: some View {
        LinearGradient(
            colors: [
                Theme.void.opacity(BlackoutTokens.Chrome.holdCardScrimTopOpacity),
                Theme.void.opacity(BlackoutTokens.Chrome.holdCardScrimOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityLabel("Close card")
        .accessibilityAddTraits(.isButton)
    }

    private func card(cappedAt cap: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            grabber
            headline
            Rectangle()
                .fill(Theme.silver.opacity(0.22))
                .frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    statusRail
                    conditionBlock
                    rows
                    if !person.isYou {
                        actions
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: cap, alignment: .top)
        .background(glass)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.accent)
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Theme.silver.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.7), radius: 18, y: -4)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var glass: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Theme.void.opacity(0.74))
        }
    }

    private var grabber: some View {
        Rectangle()
            .fill(Theme.silver.opacity(0.4))
            .frame(width: 36, height: 3)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var headline: some View {
        HStack(alignment: .center, spacing: 12) {
            face
            VStack(alignment: .leading, spacing: 2) {
                if person.isYou {
                    TextField("NAME", text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
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
        .accessibilityElement(children: .combine)
    }

    private var face: some View {
        let size: CGFloat = 56
        return Group {
            if let image = PersonEmblem.image(PersonEmblem.resolved(person.emblem)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(Theme.raised)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Theme.silver.opacity(0.35), lineWidth: 1)
        )
        .accessibilityHidden(true)
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
                HUDVitalsRail(title: "WATER", value: rail(\.water), editable: person.isYou)
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
                .buttonStyle(HoldActionStyle(filled: false, expand: true))
            Button("MESSAGE") { onMessage() }
                .buttonStyle(HoldActionStyle(filled: false, expand: true))
        }
    }

    private func statusInk(_ status: PartyStatus) -> Color {
        switch status {
        case .ok:
            return Theme.fix
        case .wait, .water:
            return Theme.caution
        case .down:
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
        }
    }
}
