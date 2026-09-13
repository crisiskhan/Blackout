import SwiftUI
import Tokens

struct RootChrome: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        ZStack {
            Theme.void.ignoresSafeArea()
            if !runtime.armed {
                ARMINGView(runtime: runtime)
            } else {
                tabChrome
                // Map and Comms carry their own I AM OK. Field / Exped get
                // the corner chip only while SOS or RED is actually lit.
                if runtime.hudCrisis && runtime.tab != .map && runtime.tab != .comms {
                    IAMOKBar(runtime: runtime)
                }
                contextualSOS
            }
        }
        .nightRedLamp(runtime.night)
        .tint(Theme.silver)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $runtime.showInstruments) {
            InstrumentsView(runtime: runtime)
                .presentationBackground(Theme.void)
        }
        .onAppear {
            runtime.applyMapKeepAwake()
            runtime.pulse()
        }
        .onChange(of: runtime.tab) { _, _ in
            runtime.applyMapKeepAwake()
            runtime.pulse()
        }
        .onChange(of: runtime.armed) { _, _ in runtime.applyMapKeepAwake() }
    }

    private var tabChrome: some View {
        ZStack(alignment: runtime.leftHand ? .leading : .bottom) {
            tabBody
            if runtime.leftHand {
                tabColumn.frame(width: BlackoutTokens.Chrome.hudSideReservePoints)
            } else {
                tabBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(runtime.chromeAwake ? Theme.Motion.wake : Theme.Motion.sleep, value: runtime.chromeAwake)
        .animation(Theme.Motion.heavy, value: runtime.hudFocus)
        .animation(Theme.Motion.heavy, value: runtime.hudLayoutMode)
    }

    /// Overlay pages sit above the tab strip. MapTab stays full-bleed so a
    /// tab change cannot resize MapLibre and snap the camera back to YOU.
    private var overlayBottomPad: CGFloat {
        runtime.leftHand ? 0 : CGFloat(BlackoutTokens.Chrome.hudTabReservePoints)
    }

    private var overlayLeadingPad: CGFloat {
        runtime.leftHand ? CGFloat(BlackoutTokens.Chrome.hudSideReservePoints) : 0
    }

    private func overlayPage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.bottom, overlayBottomPad)
            .padding(.leading, overlayLeadingPad)
    }

    private var tabBody: some View {
        // MapLibre dies if MapTab is destroyed while Field opens from the
        // hold card (ASC 72/73). Keep Map mounted under every tab. The other
        // tabs are glass over it so the ground is still there.
        ZStack {
            MapTab(runtime: runtime)
                .allowsHitTesting(runtime.tab == .map)
                .accessibilityHidden(runtime.tab != .map)
            switch runtime.tab {
            case .map:
                EmptyView()
            case .comms:
                overlayPage { CommsTab(runtime: runtime) }
            case .field:
                overlayPage { FieldTab(runtime: runtime) }
            case .expedition:
                overlayPage { ExpeditionTab(runtime: runtime) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabBar: some View {
        placedTabs {
            HStack(spacing: 0) {
                ForEach(BlackoutTab.allCases) { t in
                    tabButton(t)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .background(
                ZStack {
                    Theme.void.opacity(0.96)
                    LinearGradient(
                        colors: [Theme.metalHigh.opacity(0.18), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Theme.metalStroke)
                    .frame(height: 1)
            }
        }
    }

    private var tabColumn: some View {
        placedTabs {
            VStack(spacing: 4) {
                ForEach(BlackoutTab.allCases) { t in
                    tabButton(t)
                        .rotationEffect(.degrees(-90))
                        .frame(height: BlackoutTokens.Chrome.hudSideReservePoints)
                }
                Spacer()
            }
            .background(
                ZStack {
                    Theme.void.opacity(0.96)
                    LinearGradient(
                        colors: [Theme.metalHigh.opacity(0.14), Color.clear],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                }
            )
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Theme.metalStroke)
                    .frame(width: 1)
            }
        }
    }

    private func placedTabs<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HUDPlaced(
            offset: runtime.hudLayout.tabs,
            arranging: runtime.hudLayoutMode,
            veil: runtime.tab == .map ? runtime.chromeVeil : 1,
            alive: runtime.alive(.tabs),
            onMove: { runtime.hudLayout.tabs = $0 },
            onStore: { runtime.hudLayout.save() }
        ) {
            content()
        }
    }

    private func tabButton(_ t: BlackoutTab) -> some View {
        Button {
            runtime.touch(.tabs)
            runtime.tab = t
        } label: {
            VStack(spacing: 3) {
                Text(t.title)
                    .font(.system(size: BlackoutTokens.Chrome.tabCaptionPoints, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                    .allowsTightening(true)
                    .multilineTextAlignment(.center)
                HUDReticle(lit: runtime.tab == t, crisis: runtime.hudCrisis)
            }
        }
        .foregroundStyle(runtime.tab == t ? Theme.silver : Theme.silver.opacity(0.45))
    }

    @ViewBuilder
    private var contextualSOS: some View {
        if BlackoutTokens.Chrome.sosFAB(
            tab: tokenTab,
            lockOn: runtime.lockOn,
            arranging: runtime.hudLayoutMode
        ) {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HUDPlaced(
                        offset: runtime.hudLayout.sos,
                        arranging: runtime.hudLayoutMode,
                        veil: 1,
                        alive: 1,
                        onMove: { runtime.hudLayout.sos = $0 },
                        onStore: { runtime.hudLayout.save() }
                    ) {
                        SOSHold(runtime: runtime)
                            .padding(.trailing, 16)
                            .padding(.bottom, sosBottomPad)
                    }
                }
            }
            .allowsHitTesting(true)
        }
    }

    private var sosBottomPad: CGFloat {
        let gutter = CGFloat(BlackoutTokens.Chrome.oneThumbGutter)
        if runtime.leftHand { return gutter }
        return gutter + CGFloat(BlackoutTokens.Chrome.hudTabReservePoints)
    }

    private var tokenTab: BlackoutTokens.Tab {
        switch runtime.tab {
        case .map: return .map
        case .comms: return .comms
        case .field: return .field
        case .expedition: return .expedition
        }
    }
}
