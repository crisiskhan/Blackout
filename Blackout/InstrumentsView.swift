import SwiftUI
import BatteryAuction
import Tokens
import Almanac
import Instruments

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
                                            .foregroundStyle(Theme.silver)
                                    }
                                }
                            }
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                            .padding(.horizontal, 12)
                            .background(Theme.glass())
                            .clipShape(Theme.plateRect())
                        }
                    } else {
                        Text("PACKS · NONE")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.warn)
                    }

                    sectionLabel("HUD")
                    hudToggle("LEFT HAND", $runtime.leftHand)
                    hudToggle("NIGHT RED", Binding(
                        get: { runtime.night.enabled },
                        set: { runtime.night.enabled = $0 }
                    ))
                    hudToggle("LAYOUT", Binding(
                        get: { runtime.hudLayoutMode },
                        set: { on in
                            runtime.hudLayoutMode = on
                            runtime.pulse()
                            if on { runtime.showInstruments = false }
                        }
                    ))
                    Button("RESET HUD") { runtime.resetHUD() }
                        .buttonStyle(HUDActionStyle(filled: false))

                    sectionLabel("MAP")
                    HStack(spacing: 1) {
                        Button("RULER") { runtime.tapRuler() }
                            .buttonStyle(HUDDockStyle())
                        Button("USNG") { runtime.tapUSNG() }
                            .buttonStyle(HUDDockStyle())
                        Button("MAG/TRUE") { runtime.tapMagTrue() }
                            .buttonStyle(HUDDockStyle())
                    }
                    .background(Theme.glass())
                    .clipShape(Theme.plateRect())
                    .overlay(
                        Theme.plateRect()
                            .strokeBorder(Theme.metalStroke, lineWidth: 1)
                    )

                    sectionLabel("SUN")
                    sunPlate

                    sectionLabel("BODY")
                    Button("TORCH 3×") { runtime.tapTorch() }
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                        .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(Theme.glass())
                        .clipShape(Theme.plateRect())
                    Text(torchWord)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(runtime.instruments.state.torchClicks == 0 ? Theme.silver.opacity(0.45) : Theme.silver)
                    hudButton("COMPASS CAL") { runtime.calibrateCompass() }
                    Text(runtime.headingDeg == nil ? "NEED" : "CAL")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(runtime.headingDeg == nil ? Theme.silver.opacity(0.45) : Theme.silver)
                    hudButton("TRUE NORTH") { runtime.setTrueNorth() }
                    Text(runtime.instruments.state.magNorth ? "MAG NORTH" : "TRUE NORTH")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.silver.opacity(0.55))
                    hudToggle("USB-C PTT", Binding(
                        get: { runtime.instruments.state.usbCPTT },
                        set: { runtime.attachUSB_C_PTT($0) }
                    ))
                    hudToggle("GNSS PUCK", Binding(
                        get: { runtime.instruments.state.externalGNSS },
                        set: { runtime.attachGNSSPuck($0) }
                    ))

                    sectionLabel("VOICE")
                    HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
                        ForEach(NavVoice.allCases, id: \.self) { voice in
                            Button(voice.title) { runtime.setNavVoice(voice) }
                                .buttonStyle(HUDActionStyle(filled: runtime.instruments.state.voice == voice))
                        }
                    }

                    sectionLabel("POWER")
                    HStack(spacing: 1) {
                        ForEach(PowerMode.allCases, id: \.self) { mode in
                            Button(mode.rawValue.uppercased()) { runtime.power.set(mode) }
                                .buttonStyle(HUDActionStyle(filled: runtime.power.state.mode == mode))
                        }
                    }
                    .clipShape(Theme.plateRect())
                    hudToggle("POCKET", Binding(
                        get: { runtime.power.state.pocket },
                        set: { runtime.power.setPocket($0) }
                    ))
                    Text("SPARE \(Int(runtime.power.state.powerBankWh)) WH")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.silver.opacity(0.55))

                    hudButton("ES / EN") {
                        runtime.locale = runtime.locale == "es" ? "en" : "es"
                        runtime.applySpeechTone()
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.void)
        .preferredColorScheme(.dark)
        .nightRedLamp(runtime.night)
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
        if !runtime.torchAvailable { return "LAMP · NONE" }
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
            Text("PACKS · NONE")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.warn)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Theme.silver.opacity(0.5))
    }

    private func hudButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.silver)
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Theme.glass())
            .clipShape(Theme.plateRect())
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
                    .foregroundStyle(value.wrappedValue ? Theme.silver : Theme.silver.opacity(0.45))
            }
        }
        .font(.system(size: 13, weight: .heavy))
        .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
        .padding(.horizontal, 12)
        .background(Theme.glass())
        .clipShape(Theme.plateRect())
    }
}
