import SwiftUI
import MapLibreMap
import Tokens

/// Second glass over the YOU profile. Pick a mark without leaving MAP.
struct EmblemPickCard: View {
    let selected: PersonEmblem
    let onPick: (PersonEmblem) -> Void
    let onClose: () -> Void

    @State private var drag: CGFloat = 0

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
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(PersonEmblem.allCases, id: \.self) { emblem in
                        Button {
                            onPick(emblem)
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
        VStack(alignment: .leading, spacing: 2) {
            Text("FACE")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("YOU")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.silver)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func thumb(_ emblem: PersonEmblem, lit: Bool) -> some View {
        let size: CGFloat = 56
        return Group {
            if let image = PersonEmblem.image(emblem) {
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
            Circle().strokeBorder(
                lit ? Theme.accent : Theme.silver.opacity(0.35),
                lineWidth: lit ? 2.4 : 1
            )
        )
        .accessibilityHidden(true)
    }
}
