import SwiftUI
import MapLibreMap
import Tokens

/// Second glass over the YOU profile. Pick a mark without leaving MAP.
struct EmblemPickCard: View {
    let selected: PersonEmblem
    let onPick: (PersonEmblem) -> Void
    let onClose: () -> Void

    var body: some View {
        HoldGlassShell(onClose: onClose) {
            VStack(alignment: .leading, spacing: 10) {
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
        }
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
