import BlackoutCore
import SwiftUI

/// Unlock track. 56 metal capsule, 56 metal handle, 56 red.core SOS twin.
/// Slide unlocks. Hold the twin 1.5s presents the unarmed cover. Not the 88pt Map FAB.
public struct SlideToUnlock: View {
    private let phrase: String
    private let knobSize: CGFloat
    private let onUnlock: () -> Void
    private let onHoldSOS: (() -> Void)?
    @State private var offset: CGFloat = 0

    public init(
        _ phrase: String = LaunchLock.phrase,
        knobSize: CGFloat = CGFloat(LaunchLock.sosTwinHit),
        onHoldSOS: (() -> Void)? = nil,
        onUnlock: @escaping () -> Void
    ) {
        self.phrase = phrase
        self.knobSize = knobSize
        self.onHoldSOS = onHoldSOS
        self.onUnlock = onUnlock
    }

    public var body: some View {
        GeometryReader { geo in
            let knob = knobSize
            let maxTravel = max(0, geo.size.width - knob)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BlackoutDS.Surface.raised)
                Text(phrase)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, knob)
                    .allowsHitTesting(false)
                HStack {
                    Spacer(minLength: 0)
                    sosTwin
                }
                metalHandle
                    .offset(x: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = min(max(0, value.translation.width), maxTravel)
                            }
                            .onEnded { _ in
                                if offset > maxTravel * 0.82 {
                                    offset = maxTravel
                                    onUnlock()
                                } else {
                                    withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                                }
                            }
                    )
                    .accessibilityLabel(phrase)
            }
        }
        .frame(height: CGFloat(LaunchLock.trackHit))
        .overlay(
            Capsule()
                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
    }

    private var metalHandle: some View {
        Circle()
            .fill(BlackoutDS.Silver.metal)
            .overlay(Circle().stroke(BlackoutDS.Silver.edge, lineWidth: 1))
            .frame(width: knobSize, height: knobSize)
    }

    private var sosTwin: some View {
        ZStack {
            Circle()
                .fill(BlackoutDS.Red.core)
            Circle()
                .stroke(BlackoutDS.Red.hot, lineWidth: 2)
            Text("SOS")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BlackoutDS.Silver.metal)
        }
        .frame(width: knobSize, height: knobSize)
        .onLongPressGesture(minimumDuration: SOSChrome.holdSeconds) {
            onHoldSOS?()
        }
        .accessibilityLabel("SOS. Hold to confirm.")
    }
}
