import SwiftUI
import UIKit
import Tokens

/// Cold launch. Not a menu. The poster covers the page, then ACTIVATE.
struct ARMINGView: View {
    @Bindable var runtime: AppRuntime
    @State private var chromeIn = false
    private let readyTick = UINotificationFeedbackGenerator()
    private let goTick = UIImpactFeedbackGenerator(style: .rigid)

    var body: some View {
        ZStack {
            Theme.void.ignoresSafeArea()
            field
            chrome.ignoresSafeArea()
        }
        .onAppear {
            runtime.bootVessel()
            withAnimation(Theme.Motion.heavy) { chromeIn = true }
            if runtime.bootReady { readyTick.notificationOccurred(.success) }
        }
        .onChange(of: runtime.bootReady) { _, ready in
            if ready { readyTick.notificationOccurred(.success) }
        }
    }

    private var field: some View {
        Image("BootField")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityLabel("Blackout")
    }

    private var chrome: some View {
        ZStack(alignment: .center) {
            VStack(spacing: 0) {
                Spacer()
                status
                activate
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
        .opacity(chromeIn ? 1 : 0)
    }

    private var status: some View {
        VStack(spacing: 10) {
            Text(runtime.bootStage.line)
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(runtime.bootReady ? Theme.silver : Theme.silver.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 16)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.silver.opacity(0.16))
                    Rectangle()
                        .fill(runtime.bootReady ? Theme.accent : Theme.silver.opacity(0.85))
                        .frame(width: max(2, g.size.width * runtime.bootProgress))
                }
            }
            .frame(height: 1)
            .padding(.bottom, 22)
        }
    }

    private var activate: some View {
        Button("ACTIVATE") {
            goTick.impactOccurred()
            runtime.arm()
        }
        .font(.system(size: 16, weight: .heavy))
        .tracking(4)
        .foregroundStyle(runtime.bootReady ? Color.white : Theme.silver.opacity(0.45))
        .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.bootActivateHeight)
        .background {
            if runtime.bootReady {
                Theme.accent
            } else {
                Theme.glass()
            }
        }
        .clipShape(Theme.plateRect())
        .overlay {
            if runtime.bootReady {
                Theme.plateRect()
                    .strokeBorder(Theme.accent, lineWidth: 1)
            } else {
                Theme.plateRect()
                    .strokeBorder(Theme.metalStroke, lineWidth: 1)
            }
        }
        .opacity(runtime.bootReady ? 1 : 0.55)
        .shadow(
            color: Theme.accent.opacity(runtime.bootReady ? 0.42 : 0),
            radius: runtime.bootReady ? 14 : 0
        )
        .allowsHitTesting(runtime.bootReady)
        .accessibilityHint("Loads the vessel and opens the map")
        .animation(Theme.Motion.wake, value: runtime.bootReady)
    }
}
