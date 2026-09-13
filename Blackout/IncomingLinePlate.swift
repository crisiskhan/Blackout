import SwiftUI
import MapLibreMap
import Tokens

/// One inbound CALL or MESSAGE as a glass line. Tap answers; swipe up clears.
struct IncomingLinePlate: View {
    @Bindable var runtime: AppRuntime
    @State private var drag: CGFloat = 0

    var body: some View {
        if let line = runtime.incoming {
            Button(action: { runtime.answerIncoming() }) {
                HStack(spacing: 10) {
                    face(line)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(line.name)
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 8)
                            kindMark(line.kind)
                        }
                        Text(line.location)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(
                    maxWidth: .infinity,
                    minHeight: BlackoutTokens.Chrome.mapChipHitPoints,
                    alignment: .leading
                )
                .background(Theme.glass())
                .overlay(
                    Theme.plateRect()
                        .strokeBorder(Theme.metalStroke, lineWidth: 1)
                )
                .clipShape(Theme.plateRect())
                .offset(y: drag)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(kindTitle(line.kind)) \(line.name)")
            .accessibilityHint(line.location)
            .accessibilityAddTraits(.isButton)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { drag = min(0, $0.translation.height) }
                    .onEnded { value in
                        if value.translation.height < -CGFloat(BlackoutTokens.Chrome.mapChipHitPoints) {
                            runtime.clearIncoming()
                        }
                        withAnimation(Theme.Motion.heavy) { drag = 0 }
                    }
            )
        }
    }

    @ViewBuilder
    private func kindMark(_ kind: IncomingKind) -> some View {
        switch kind {
        case .call:
            Text("CALL")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.accent)
        case .message:
            Text("MESSAGE")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.silver)
        }
    }

    private func kindTitle(_ kind: IncomingKind) -> String {
        // New IncomingKind variants are Never until handled here.
        switch kind {
        case .call:
            return "CALL"
        case .message:
            return "MESSAGE"
        }
    }

    private func face(_ line: IncomingLine) -> some View {
        let size = CGFloat(BlackoutTokens.Chrome.mapChipHitPoints)
        return Group {
            if let image = PersonEmblem.image(PersonEmblem.resolved(line.emblem)) {
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
            Circle().strokeBorder(Theme.silver.opacity(0.35), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}
