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
            EmblemFaceGrid(
                selected: selected,
                onPick: onPick,
                compact: false
            )
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
}
