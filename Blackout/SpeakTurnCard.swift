import SwiftUI
import Tokens

/// Glass plate of street turns. HUD words, not the spoken script. SPEAK
/// already said the line out loud; this is the same path for the thumb.
struct SpeakTurnCard: View {
    let turns: [String]
    let onClose: () -> Void

    var body: some View {
        HoldGlassShell(onClose: onClose) {
            VStack(alignment: .leading, spacing: 10) {
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(turns.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Theme.silver)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: BlackoutTokens.Chrome.mapChipHitPoints,
                                    alignment: .leading
                                )
                                .padding(.horizontal, 12)
                                .background(Theme.glass())
                                .clipShape(Theme.plateRect())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}
