import SwiftUI

public enum SlideKnobStyle: Sendable, Equatable {
    case metal
    case sos
}

public struct SlideToConfirm: View {
    private let phrase: String
    private let knobStyle: SlideKnobStyle
    private let knobSize: CGFloat
    private let onConfirm: () -> Void
    @State private var offset: CGFloat = 0

    public init(
        _ phrase: String = "Slide to arm",
        knobStyle: SlideKnobStyle = .metal,
        knobSize: CGFloat = BlackoutDS.Hit.lg,
        onConfirm: @escaping () -> Void
    ) {
        self.phrase = phrase
        self.knobStyle = knobStyle
        self.knobSize = knobSize
        self.onConfirm = onConfirm
    }

    public var body: some View {
        GeometryReader { geo in
            let knob = knobSize
            let maxTravel = max(0, geo.size.width - knob - 8)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BlackoutDS.Surface.sunken)
                Text(trackPhrase)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, knob + 8)
                knobView
                    .padding(4)
                    .offset(x: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = min(max(0, value.translation.width), maxTravel)
                            }
                            .onEnded { _ in
                                if offset > maxTravel * 0.82 {
                                    offset = maxTravel
                                    onConfirm()
                                } else {
                                    withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                                }
                            }
                    )
                    .accessibilityLabel(phrase)
            }
        }
        .frame(height: knobSize + 8)
        .overlay(
            Capsule()
                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
    }

    private var trackPhrase: String {
        switch knobStyle {
        case .metal:
            return phrase
        case .sos:
            return phrase.hasSuffix(">") ? phrase : "\(phrase) >"
        }
    }

    @ViewBuilder
    private var knobView: some View {
        switch knobStyle {
        case .metal:
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BlackoutDS.Silver.metal)
                .frame(width: knobSize - 8, height: knobSize - 8)
        case .sos:
            ZStack {
                Circle()
                    .fill(BlackoutDS.Red.core)
                Circle()
                    .stroke(BlackoutDS.Red.hot, lineWidth: 2)
                Text("SOS")
                    .font(.system(size: sosLabelSize, weight: .bold))
                    .foregroundStyle(BlackoutDS.Silver.metal)
            }
            .frame(width: knobSize, height: knobSize)
            .shadow(color: BlackoutDS.Red.blood.opacity(0.55), radius: 8, y: 2)
        }
    }

    private var sosLabelSize: CGFloat {
        knobSize >= 64 ? 14 : 12
    }
}
