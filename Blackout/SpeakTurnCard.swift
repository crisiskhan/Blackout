import SwiftUI
import Tokens

/// Next two turns on the HUD, not a hold-glass over the globe. SPEAK
/// already said the line out loud; CLOSE puts this away until SPEAK again.
struct SpeakTurnCard: View {
    let turns: [String]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HUDMark()
                Text("TURNS")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Button("CLOSE") { onClose() }
                    .buttonStyle(HUDOverlayChipStyle())
            }
            ForEach(Array(turns.prefix(2).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.glass())
        .clipShape(Theme.plateRect())
        .transition(.opacity)
    }
}
