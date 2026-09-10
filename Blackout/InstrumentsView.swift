import SwiftUI
import BatteryAuction
import Tokens
import Almanac

struct InstrumentsView: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionLabel("PACKS")
                    if let packs = runtime.packs {
                        ForEach(packs.catalog.packs, id: \.id) { p in
                            Button {
                                runtime.switchPack(p.id)
                            } label: {
                                HStack {
                                    Text(p.name)
                                    Spacer()
                                    if runtime.packs?.active?.id == p.id {
                                        Text("LIVE")
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                            .padding(.horizontal, 12)
                            .background(Theme.raised)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    } else {
                        Text("Packs missing from bundle — honest empty.")
                            .font(.caption)
                            .foregroundStyle(Color(white: 0.5))
                    }

                    sectionLabel("HUD")
                    hudToggle("Left-hand column", $runtime.leftHand)
                    hudToggle("Night-red", Binding(
                        get: { runtime.night.enabled },
                        set: { runtime.night.enabled = $0 }
                    ))

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

                    sectionLabel("SUN")
                    sunPlate

                    sectionLabel("BODY")
                    Button("Torch 3×") { runtime.tapTorch() }
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                        .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(Theme.raised)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(torchWord)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(runtime.instruments.state.torchClicks == 0 ? Color(white: 0.45) : Theme.accent)
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
                    HStack(spacing: 1) {
                        ForEach(PowerMode.allCases, id: \.self) { mode in
                            Button(mode.rawValue.uppercased()) { runtime.power.set(mode) }
                                .buttonStyle(HUDActionStyle(filled: runtime.power.state.mode == mode))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    hudToggle("Pocket", Binding(
                        get: { runtime.power.state.pocket },
                        set: { runtime.power.setPocket($0) }
                    ))
                    Text("Hot-spare \(runtime.power.hotSparePayload())")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.55))

                    hudButton("ES / EN") {
                        runtime.locale = runtime.locale == "es" ? "en" : "es"
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.void)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            HUDMark()
            Text("INSTRUMENTS")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.silver)
            Spacer(minLength: 8)
            Button("CLOSE") { runtime.showInstruments = false }
                .buttonStyle(HUDOverlayChipStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var torchWord: String {
        let n = runtime.instruments.state.torchClicks
        return n == 0 ? "OFF" : "\(n)"
    }

    @ViewBuilder
    private var sunPlate: some View {
        if let pack = runtime.packs?.active {
            let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
            let sun = Almanac.sun(lat: pack.center.lat, lon: pack.center.lon, dayOfYear: day)
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("RISE \(Almanac.clock(sun.sunriseHour))")
                        Spacer()
                        Text("SET \(Almanac.clock(sun.sunsetHour))")
                    }
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    if Almanac.shadePreferSummer(month: Calendar.current.component(.month, from: Date())) {
                        Text("SHADE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.warn)
                    }
                }
            }
        } else {
            Text("Packs missing from bundle — honest empty.")
                .font(.caption)
                .foregroundStyle(Color(white: 0.5))
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

    /// 44pt plate. ON / OFF is the instrument, not a system Toggle.
    private func hudToggle(_ title: String, _ value: Binding<Bool>) -> some View {
        Button {
            value.wrappedValue.toggle()
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Theme.silver)
                Spacer()
                Text(value.wrappedValue ? "ON" : "OFF")
                    .foregroundStyle(value.wrappedValue ? Theme.accent : Color(white: 0.45))
            }
        }
        .font(.system(size: 13, weight: .heavy))
        .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
        .padding(.horizontal, 12)
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
