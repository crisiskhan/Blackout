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
                if runtime.mesh.joined {
                    IAMOKBar(runtime: runtime)
                }
                contextualSOS
            }
            if runtime.night.enabled {
                Color(red: 0.55, green: 0.05, blue: 0.05).opacity(0.28).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $runtime.showInstruments) {
            InstrumentsView(runtime: runtime)
        }
        .fullScreenCover(isPresented: Binding(
            get: { runtime.armed && !runtime.sawCannotDo },
            set: { if !$0 { runtime.acknowledgeCannotDo() } }
        )) {
            CannotDoView(runtime: runtime)
        }
        .onAppear { runtime.applyMapKeepAwake() }
        .onChange(of: runtime.tab) { _, _ in runtime.applyMapKeepAwake() }
        .onChange(of: runtime.armed) { _, _ in runtime.applyMapKeepAwake() }
    }

    private var tabChrome: some View {
        VStack(spacing: 0) {
            if runtime.leftHand {
                HStack(alignment: .top, spacing: 0) {
                    tabColumn.frame(width: 72)
                    tabBody
                }
            } else {
                tabBody
                tabBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabBody: some View {
        // MapLibre dies if MapTab is destroyed while Field opens from the
        // inspect card (ASC 72/73). Keep Map mounted under every tab; hide it
        // when another tab is selected instead of switching it out of the tree.
        ZStack {
            MapTab(runtime: runtime)
                .opacity(runtime.tab == .map ? 1 : 0)
                .allowsHitTesting(runtime.tab == .map)
                .accessibilityHidden(runtime.tab != .map)
            switch runtime.tab {
            case .map:
                EmptyView()
            case .comms:
                CommsTab(runtime: runtime)
            case .field:
                FieldTab(runtime: runtime)
            case .expedition:
                ExpeditionTab(runtime: runtime)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(BlackoutTab.allCases) { t in
                tabButton(t)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 8)
        .background(Color(white: 0.08))
    }

    private var tabColumn: some View {
        VStack {
            ForEach(BlackoutTab.allCases) { t in
                tabButton(t)
                    .rotationEffect(.degrees(-90))
                    .frame(height: 72)
            }
            Spacer()
        }
    }

    private func tabButton(_ t: BlackoutTab) -> some View {
        Button(t.title) { runtime.tab = t }
            .font(.system(size: BlackoutTokens.Chrome.tabCaptionPoints, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
            .foregroundStyle(runtime.tab == t ? Theme.silver : Color(white: 0.45))
    }

    @ViewBuilder
    private var contextualSOS: some View {
        if BlackoutTokens.Chrome.sosFAB(tab: tokenTab, lockOn: runtime.lockOn) {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    SOSHold(runtime: runtime)
                        .padding(.trailing, 16)
                        .padding(.bottom, 72)
                }
            }
            .allowsHitTesting(true)
        }
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