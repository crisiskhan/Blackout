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
        ZStack(alignment: runtime.leftHand ? .leading : .bottom) {
            tabBody
                .padding(.bottom, overlayBottomPad)
                .padding(.leading, overlayLeadingPad)
            if runtime.leftHand {
                tabColumn.frame(width: BlackoutTokens.Chrome.hudSideReservePoints)
            } else {
                tabBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// MAP draws under the strip. Other tabs keep their content off it.
    private var overlayBottomPad: CGFloat {
        if runtime.leftHand || runtime.tab == .map { return 0 }
        return CGFloat(BlackoutTokens.Chrome.hudTabReservePoints)
    }

    private var overlayLeadingPad: CGFloat {
        if !runtime.leftHand || runtime.tab == .map { return 0 }
        return CGFloat(BlackoutTokens.Chrome.hudSideReservePoints)
    }

    private var tabBody: some View {
        Group {
            switch runtime.tab {
            case .map: MapTab(runtime: runtime)
            case .comms: CommsTab(runtime: runtime)
            case .field: FieldTab(runtime: runtime)
            case .expedition: ExpeditionTab(runtime: runtime)
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
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background(Theme.void.opacity(0.94))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.silver.opacity(0.18))
                .frame(height: 1)
        }
    }

    private var tabColumn: some View {
        VStack(spacing: 4) {
            ForEach(BlackoutTab.allCases) { t in
                tabButton(t)
                    .rotationEffect(.degrees(-90))
                    .frame(height: BlackoutTokens.Chrome.hudSideReservePoints)
            }
            Spacer()
        }
        .background(Theme.void.opacity(0.94))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.silver.opacity(0.18))
                .frame(width: 1)
        }
    }

    private func tabButton(_ t: BlackoutTab) -> some View {
        Button {
            runtime.tab = t
        } label: {
            VStack(spacing: 3) {
                Text(t.title)
                    .font(.system(size: BlackoutTokens.Chrome.tabCaptionPoints, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .multilineTextAlignment(.center)
                Rectangle()
                    .fill(runtime.tab == t ? Theme.accent : Color.clear)
                    .frame(width: 18, height: 2)
            }
        }
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
                        .padding(.bottom, sosBottomPad)
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
