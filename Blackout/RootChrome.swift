import SwiftUI
import Tokens
import RegionalPacks

struct RootChrome: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        ZStack {
            Color(red: BlackoutTokens.Color.void.r, green: BlackoutTokens.Color.void.g, blue: BlackoutTokens.Color.void.b)
                .ignoresSafeArea()
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
    }

    private var tabBar: some View {
        HStack {
            ForEach(BlackoutTab.allCases) { t in
                Button(t.title) { runtime.tab = t }
                    .foregroundStyle(runtime.tab == t ? Color(white: 0.85) : Color(white: 0.45))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 8)
        .background(Color(white: 0.08))
    }

    private var tabColumn: some View {
        VStack {
            ForEach(BlackoutTab.allCases) { t in
                Button(t.title) { runtime.tab = t }
                    .rotationEffect(.degrees(-90))
                    .frame(height: 72)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var contextualSOS: some View {
        if runtime.lockOn || runtime.tab == .comms {
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
}
