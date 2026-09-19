import SwiftUI
import MapLibreMap
import Tokens

/// FACE picker used on COMMS, YOU, and MARK. Compact plates scroll so the
/// page stays short. Order is PersonEmblem.faces — look-alike marks sit together.
struct EmblemFaceGrid: View {
    let selected: PersonEmblem
    let onPick: (PersonEmblem) -> Void
    var titleSize: CGFloat = 11
    var compact: Bool = true

    private var plate: CGFloat { CGFloat(BlackoutTokens.Chrome.mapChipHitPoints) * 4 }

    var body: some View {
        if compact {
            rail.frame(height: plate)
        } else {
            rail.frame(minHeight: 0, maxHeight: .infinity)
        }
    }

    private var rail: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                spacing: 8
            ) {
                ForEach(PersonEmblem.faces, id: \.self) { emblem in
                    Button {
                        onPick(emblem)
                    } label: {
                        VStack(spacing: 4) {
                            thumb(emblem, lit: selected == emblem)
                            Text(emblem.title)
                                .font(.system(size: titleSize, weight: .heavy))
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
}
