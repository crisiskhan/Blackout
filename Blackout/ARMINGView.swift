import SwiftUI
import UIKit
import MapLibreMap
import Tokens

/// Cold launch. Not a menu. The world comes up under the mark, then ACTIVATE.
struct ARMINGView: View {
    @Bindable var runtime: AppRuntime
    @State private var markIn = false
    @State private var worldIn = false
    private let readyTick = UINotificationFeedbackGenerator()
    private let goTick = UIImpactFeedbackGenerator(style: .rigid)

    var body: some View {
        ZStack {
            Theme.void.ignoresSafeArea()
            world
            vignette
            chrome
        }
        .onAppear {
            runtime.bootVessel()
            withAnimation(.easeOut(duration: 0.9)) { markIn = true }
            if runtime.bootStyleURL != nil {
                withAnimation(.easeIn(duration: 1.15)) { worldIn = true }
            }
            if runtime.bootReady { readyTick.notificationOccurred(.success) }
        }
        .onChange(of: runtime.bootStyleURL) { _, url in
            if url != nil {
                withAnimation(.easeIn(duration: 1.15)) { worldIn = true }
            }
        }
        .onChange(of: runtime.bootReady) { _, ready in
            if ready { readyTick.notificationOccurred(.success) }
        }
    }

    /// The active pack, quiet, no GPS, no chrome. Streets are the load.
    @ViewBuilder
    private var world: some View {
        if let style = runtime.bootStyleURL, let pack = runtime.packs?.active {
            let home = pack.home ?? pack.center
            OfflineMapView(
                styleURL: style,
                centerLat: home.lat,
                centerLon: home.lon,
                puckLat: home.lat,
                puckLon: home.lon,
                packSouth: pack.bbox.south,
                packWest: pack.bbox.west,
                packNorth: pack.bbox.north,
                packEast: pack.bbox.east,
                trackUser: false,
                interactive: false
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .opacity(worldIn ? 0.55 : 0)
        }
    }

    private var vignette: some View {
        RadialGradient(
            colors: [
                Theme.void.opacity(0.18),
                Theme.void.opacity(0.72),
                Theme.void.opacity(0.94),
            ],
            center: .center,
            startRadius: 20,
            endRadius: 420
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            Spacer()
            mark
            Spacer()
            status
            activate
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 36)
    }

    private var mark: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: runtime.bootReady)) { context in
            let pulse = runtime.bootReady
                ? 1.0
                : (sin(context.date.timeIntervalSinceReferenceDate * 2.2) * 0.5 + 0.5)
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(
                    width: BlackoutTokens.Chrome.bootLogoPoints,
                    height: BlackoutTokens.Chrome.bootLogoPoints
                )
                .shadow(color: Theme.accent.opacity(0.25 + 0.45 * pulse), radius: 18 + 14 * pulse)
                .scaleEffect(markIn ? 1 : 0.86)
                .opacity(markIn ? 1 : 0)
                .accessibilityLabel("Blackout")
        }
    }

    private var status: some View {
        VStack(spacing: 10) {
            Text(runtime.bootStage.line)
                .font(.system(size: 11, weight: .heavy))
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
        .background(runtime.bootReady ? Theme.accent : Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    runtime.bootReady ? Theme.accent : Theme.silver.opacity(0.28),
                    lineWidth: 1
                )
        )
        .opacity(runtime.bootReady ? 1 : 0.55)
        .allowsHitTesting(runtime.bootReady)
        .accessibilityHint("Loads the vessel and opens the map")
        .animation(.easeOut(duration: 0.25), value: runtime.bootReady)
    }
}
