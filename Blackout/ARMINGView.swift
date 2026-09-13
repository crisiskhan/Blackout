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
                interactive: false,
                youEmblem: runtime.youEmblem.rawValue
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .opacity(worldIn ? 0.22 : 0)
        }
    }

    private var vignette: some View {
        RadialGradient(
            colors: [
                Theme.void.opacity(0.62),
                Theme.void.opacity(0.82),
                Theme.void.opacity(0.97),
            ],
            center: .center,
            startRadius: 40,
            endRadius: 520
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
            let size = CGFloat(BlackoutTokens.Chrome.bootLogoPoints)
            let bloom = 0.38 + 0.22 * pulse
            ZStack {
                HUDRing(diameter: size + 28, lit: runtime.bootReady)
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .shadow(color: Theme.accent.opacity(0.82 + 0.18 * pulse), radius: 6 + 3 * pulse)
                    .shadow(color: Theme.accent.opacity(bloom), radius: 18 + 8 * pulse)
                    .shadow(color: Theme.accent.opacity(0.18 + 0.16 * pulse), radius: 36 + 10 * pulse)
                    .compositingGroup()
            }
            .scaleEffect(markIn ? 1 : 0.98)
            .opacity(markIn ? 1 : 0)
            .accessibilityLabel("Blackout")
        }
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
        .animation(.easeOut(duration: 0.25), value: runtime.bootReady)
    }
}
