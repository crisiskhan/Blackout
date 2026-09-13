import SwiftUI
import MapLibreMap
import Tokens

/// Glass composer for a party place. NAME, NOTE, and FACE stay here until DROP.
struct PlaceMarkCard: View {
    @Bindable var runtime: AppRuntime

    @State private var drag: CGFloat = 0

    private static let smallestUsableCard: CGFloat = 180

    private var corner: CGFloat { CGFloat(BlackoutTokens.Chrome.holdCardCornerPoints) }

    private var nameText: Binding<String> {
        Binding(
            get: { runtime.markDraft?.name ?? "" },
            set: { next in
                guard var draft = runtime.markDraft else { return }
                draft.name = next
                runtime.markDraft = draft
            }
        )
    }

    private var noteText: Binding<String> {
        Binding(
            get: { runtime.markDraft?.note ?? "" },
            set: { next in
                guard var draft = runtime.markDraft else { return }
                draft.note = next
                runtime.markDraft = draft
            }
        )
    }

    private var selected: PersonEmblem {
        PersonEmblem.resolved(runtime.markDraft?.emblem)
    }

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
                            runtime.closeMark()
                        }
                        withAnimation(Theme.Motion.heavy) { drag = 0 }
                    }
            )
        }
        .transition(.opacity)
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
        .onTapGesture { runtime.closeMark() }
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
                    HUDField("NAME",
                        text: nameText,
                        id: "mark.name",
                        locked: true,
                        pointSize: 20,
                        weight: .heavy,
                        ink: Color.white,
                        onOpen: { runtime.pulse() }
                    )
                    HUDField("NOTE",
                        text: noteText,
                        id: "mark.note",
                        pointSize: 15,
                        weight: .bold,
                        ink: Color.white,
                        onOpen: { runtime.pulse() }
                    )
                    faceGrid
                    row(key: "COORDINATES", value: coordinates)
                    Button("DROP") { runtime.commitMark() }
                        .buttonStyle(HoldActionStyle(filled: true, expand: true))
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: cap, alignment: .top)
        .background(Theme.glass())
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.accent)
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
        )
        .shadow(color: .black.opacity(0.7), radius: 18, y: -4)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var grabber: some View {
        Rectangle()
            .fill(Theme.silver.opacity(0.4))
            .frame(width: 36, height: 3)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MARK")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("PARTY")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.silver)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var faceGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FACE")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.75))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                spacing: 8
            ) {
                ForEach(PersonEmblem.allCases, id: \.self) { emblem in
                    Button {
                        pick(emblem)
                    } label: {
                        VStack(spacing: 4) {
                            thumb(emblem, lit: selected == emblem)
                            Text(emblem.title)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Theme.silver)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(
                        minWidth: BlackoutTokens.Chrome.mapChipHitPoints,
                        minHeight: BlackoutTokens.Chrome.mapChipHitPoints
                    )
                    .accessibilityLabel(emblem.title)
                }
            }
        }
    }

    private var coordinates: String {
        guard let draft = runtime.markDraft else { return MapFieldChrome.destValue(point: nil) }
        return MapFieldChrome.destValue(point: (draft.lat, draft.lon))
    }

    private func pick(_ emblem: PersonEmblem) {
        guard var draft = runtime.markDraft else { return }
        draft.emblem = emblem.rawValue
        runtime.markDraft = draft
        runtime.pulse()
    }

    private func thumb(_ emblem: PersonEmblem, lit: Bool) -> some View {
        let size: CGFloat = 56
        return Group {
            if let image = PersonEmblem.image(emblem) {
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
            Circle().strokeBorder(
                lit ? Theme.accent : Theme.silver.opacity(0.35),
                lineWidth: lit ? 2.4 : 1
            )
        )
        .accessibilityHidden(true)
    }

    private func row(key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.75))
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
