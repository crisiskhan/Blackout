import SwiftUI

public struct SlideToConfirm: View {
    private let phrase: String
    private let onConfirm: () -> Void
    @State private var offset: CGFloat = 0
    @State private var trackWidth: CGFloat = 0

    public init(_ phrase: String = "Slide to arm", onConfirm: @escaping () -> Void) {
        self.phrase = phrase
        self.onConfirm = onConfirm
    }

    public var body: some View {
        GeometryReader { geo in
            let knob: CGFloat = BlackoutDS.Hit.lg
            let maxTravel = max(0, geo.size.width - knob - 8)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(BlackoutDS.Surface.sunken)
                Text(phrase)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BlackoutDS.Silver.metal)
                    .frame(width: knob - 8, height: knob - 8)
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
            .onAppear { trackWidth = geo.size.width }
        }
        .frame(height: BlackoutDS.Hit.lg)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
    }
}
