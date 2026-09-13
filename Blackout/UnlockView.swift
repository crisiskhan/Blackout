import SwiftUI
import Tokens
import UIKit

enum UnlockGlass {
    static let invertWindow = 40.0

    static func inverted(degrees: Double) -> Bool {
        let wrapped = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let delta = min(abs(wrapped - 180), abs(wrapped - (180 + 360)))
        return delta <= invertWindow
    }
}

/// Fingerprint glass before ACTIVATE. Upright UNLOCK is Face ID. Inverted asks first.
struct UnlockView: View {
    @Bindable var runtime: AppRuntime
    @State private var turn: Double = 0
    private let goTick = UIImpactFeedbackGenerator(style: .rigid)

    var body: some View {
        ZStack {
            Theme.void.ignoresSafeArea()
            chrome
        }
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            Spacer()
            mark
            Spacer()
            status
            if runtime.wipeConfirm {
                sure
            } else {
                unlock
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 36)
    }

    private var mark: some View {
        Image(systemName: "touchid")
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
            .foregroundStyle(Theme.silver)
            .rotationEffect(.degrees(turn))
            .gesture(
                RotationGesture()
                    .onChanged { value in
                        turn = value.degrees
                    }
            )
            .accessibilityLabel("Fingerprint")
    }

    private var status: some View {
        Text(runtime.wipeConfirm ? "ARE YOU SURE" : (runtime.unlockChrome.isEmpty ? "UNLOCK" : runtime.unlockChrome))
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Theme.silver)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 16)
            .padding(.bottom, 22)
    }

    private var unlock: some View {
        Button("UNLOCK") {
            goTick.impactOccurred()
            runtime.requestUnlock(inverted: UnlockGlass.inverted(degrees: turn))
        }
        .font(.system(size: 16, weight: .heavy))
        .tracking(4)
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.bootActivateHeight)
        .background(Theme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1)
        )
        .accessibilityHint("Unlocks the vessel")
    }

    private var sure: some View {
        HStack(spacing: 10) {
            Button("YES") {
                goTick.impactOccurred()
                runtime.confirmWipe()
            }
            .font(.system(size: 16, weight: .heavy))
            .tracking(4)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.bootActivateHeight)
            .background(Theme.fix)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button("NO") {
                goTick.impactOccurred()
                runtime.cancelWipe()
            }
            .font(.system(size: 16, weight: .heavy))
            .tracking(4)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.bootActivateHeight)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
