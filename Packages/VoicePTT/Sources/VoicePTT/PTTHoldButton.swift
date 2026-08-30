import BlackoutCore
import DesignSystem
import SwiftUI
import UIKit

public struct PTTHoldButton: View {
    var decision: PTTDecision
    var isTransmitting: Bool
    var refusal: String?
    var onPress: () -> Bool
    var onRelease: () -> Void
    var onDeniedTap: () -> Void

    @State private var pressed = false

    public init(
        decision: PTTDecision,
        isTransmitting: Bool,
        refusal: String?,
        onPress: @escaping () -> Bool,
        onRelease: @escaping () -> Void,
        onDeniedTap: @escaping () -> Void
    ) {
        self.decision = decision
        self.isTransmitting = isTransmitting
        self.refusal = refusal
        self.onPress = onPress
        self.onRelease = onRelease
        self.onDeniedTap = onDeniedTap
    }

    public var body: some View {
        VStack(spacing: 6) {
            if isTransmitting {
                Text(PTTCopy.live)
                    .font(BlackoutDS.captionFont())
                    .fontWeight(.semibold)
                    .foregroundStyle(BlackoutDS.Red.core)
                    .tracking(BlackoutDS.Comms.liveTracking)
            } else if let refusal {
                Text(refusal)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 160)
            } else if decision.dimmed, let empty = decision.emptyMessage {
                Text(empty)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 160)
            }
            Circle()
                .fill(BlackoutDS.Silver.metal)
                .frame(width: BlackoutDS.Hit.lg, height: BlackoutDS.Hit.lg)
                .overlay(
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: BlackoutDS.Comms.waveform, weight: .semibold))
                        .foregroundStyle(BlackoutDS.Surface.void)
                )
                .scaleEffect(isTransmitting || pressed ? BlackoutDS.Comms.pttPressScale : 1)
                .opacity(decision.dimmed ? BlackoutDS.Comms.dimmed : 1)
                .animation(.easeOut(duration: BlackoutDS.Comms.pttPressSeconds), value: isTransmitting)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !pressed else { return }
                            pressed = true
                            if decision.allowsTransmit {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if !onPress() {
                                    pressed = false
                                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                }
                            } else {
                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                onDeniedTap()
                            }
                        }
                        .onEnded { _ in
                            if pressed, decision.allowsTransmit {
                                onRelease()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            pressed = false
                        }
                )
                .accessibilityLabel("Push to talk")
        }
    }
}
