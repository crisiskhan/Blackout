import SwiftUI
import Tokens

/// Glass plate of street turns. HUD words, not the spoken script. SPEAK
/// already said the line out loud; this is the same path for the thumb.
struct SpeakTurnCard: View {
    let turns: [String]
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
        .ignoresSafeArea()
    }

    private var scrim: some View {
        Theme.void.opacity(0.45)
            .ignoresSafeArea()
            .onTapGesture(perform: onClose)
    }

    private func card(cappedAt cap: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            grabber
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HUDMark()
                Text("TURNS")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Button("CLOSE") { onClose() }
                    .buttonStyle(HUDOverlayChipStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(turns.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                            .padding(.horizontal, 12)
                            .background(Theme.glass())
                            .clipShape(Theme.plateRect())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: cap, alignment: .top)
        .background(Theme.glass(opacity: 0.94))
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Theme.metalStroke, lineWidth: 1)
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
}
