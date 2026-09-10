import SwiftUI
import BatteryAuction
import Tokens

struct InstrumentsView: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionLabel("MAP")
                    HStack(spacing: 1) {
                        Button("RULER") { runtime.tapRuler() }
                            .buttonStyle(HUDDockStyle())
                        Button("USNG") { runtime.tapUSNG() }
                            .buttonStyle(HUDDockStyle())
                        Button("MAG/TRUE") { runtime.tapMagTrue() }
                            .buttonStyle(HUDDockStyle())
                    }
                    .background(Theme.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.silver.opacity(0.22), lineWidth: 1)
                    )

                    sectionLabel("BODY")
                    hudButton("Torch 3×") { runtime.instruments.torchTap() }
                    hudButton("Compass cal") { runtime.instruments.calibrateCompass() }
                    hudButton("True north") { runtime.instruments.setTrueNorth() }
                    hudToggle("USB-C PTT present", Binding(
                        get: { runtime.instruments.state.usbCPTT },
                        set: { runtime.instruments.attachUSB_C_PTT($0) }
                    ))
                    hudToggle("External GNSS puck", Binding(
                        get: { runtime.instruments.state.externalGNSS },
                        set: { runtime.instruments.attachGNSSPuck($0) }
                    ))

                    sectionLabel("POWER")
                    Picker("Auction", selection: Binding(
                        get: { runtime.power.state.mode },
                        set: { runtime.power.set($0) }
                    )) {
                        ForEach(PowerMode.allCases, id: \.self) { m in
                            Text(m.rawValue.uppercased()).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    hudToggle("Pocket", Binding(
                        get: { runtime.power.state.pocket },
                        set: { runtime.power.setPocket($0) }
                    ))
                    Text("Hot-spare \(runtime.power.hotSparePayload())")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.55))
                    Text("Screen buffer OFF default: \(!runtime.power.state.screenBuffer)")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.55))

                    hudButton("ES / EN") {
                        runtime.locale = runtime.locale == "es" ? "en" : "es"
                    }
                }
                .padding(16)
            }
            .background(Theme.void)
            .navigationTitle("INSTRUMENTS")
            .toolbarBackground(Theme.void, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Color(white: 0.5))
    }

    private func hudButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.silver)
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Theme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func hudToggle(_ title: String, _ value: Binding<Bool>) -> some View {
        Toggle(title, isOn: value)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.silver)
            .tint(Theme.accent)
            .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            .padding(.horizontal, 12)
            .background(Theme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
