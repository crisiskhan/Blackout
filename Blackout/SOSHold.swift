import SwiftUI
import UIKit
import Tokens
import CommsUI

struct SOSHold: View {
    @Bindable var runtime: AppRuntime
    @State private var holding = false
    @State private var armedLocal = false
    @State private var press = 0
    private let tick = UIImpactFeedbackGenerator(style: .rigid)

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !holding)) { context in
            let pulse = holding
                ? (sin(context.date.timeIntervalSinceReferenceDate * 9) * 0.5 + 0.5)
                : 0
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.25 + 0.7 * pulse), lineWidth: 3 + 3 * pulse)
                    .frame(
                        width: BlackoutTokens.Chrome.sosDiameter + 14,
                        height: BlackoutTokens.Chrome.sosDiameter + 14
                    )
                    .scaleEffect(1 + 0.08 * pulse)
                Circle()
                    .fill(lit ? Theme.accent : Theme.accent.opacity(0.92))
                    .frame(
                        width: BlackoutTokens.Chrome.sosDiameter,
                        height: BlackoutTokens.Chrome.sosDiameter
                    )
                Circle()
                    .stroke(Theme.silver.opacity(0.55), lineWidth: 1.5)
                    .frame(
                        width: BlackoutTokens.Chrome.sosDiameter,
                        height: BlackoutTokens.Chrome.sosDiameter
                    )
                Text("SOS")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.white)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !holding else { return }
                    holding = true
                    press &+= 1
                    tick.impactOccurred()
                    // Tag the press. Tapping, letting go and pressing again left the
                    // first timer in flight; it saw the second press still holding and
                    // armed it early, so SOS could fire well short of its 800 ms.
                    let armed = press
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(BlackoutTokens.Chrome.sosHoldMs) / 1000.0) {
                        if holding, armed == press { armedLocal = true }
                    }
                }
                .onEnded { _ in
                    holding = false
                    if armedLocal {
                        runtime.offerSOS()
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        armedLocal = false
                    }
                }
        )
        .accessibilityLabel(L10n.t("sos.call", runtime.locale))
        .accessibilityHint(L10n.t("sos.hold", runtime.locale))
        .accessibilityAddTraits(.isButton)
    }

    private var lit: Bool {
        runtime.red.isRed || runtime.comms.chips.contains(.sos)
    }
}

struct IAMOKBar: View {
    @Bindable var runtime: AppRuntime
    var body: some View {
        VStack {
            HStack {
                Button(L10n.t("ok.chip", runtime.locale)) {
                    runtime.iamOK()
                }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver)
                .padding(.horizontal, 12)
                .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                .background(Theme.glass())
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.silver.opacity(0.28), lineWidth: 1)
                )
                Spacer()
            }
            Spacer()
        }
        .padding(12)
        .allowsHitTesting(true)
    }
}
