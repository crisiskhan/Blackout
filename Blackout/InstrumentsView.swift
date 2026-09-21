import SwiftUI
import Tokens
import Almanac
import Instruments

private enum InstrumentPlate: String, CaseIterable {
    case packs
    case hud
    case map
    case sun
    case body
    case voice

    var title: String {
        switch self {
        case .packs: return "PACKS"
        case .hud: return "HUD"
        case .map: return "MAP"
        case .sun: return "SUN"
        case .body: return "BODY"
        case .voice: return "VOICE"
        }
    }
}

struct InstrumentsView: View {
    @Bindable var runtime: AppRuntime
    @State private var plate: InstrumentPlate = .packs

    var body: some View {
        let _ = Theme.bind(runtime.lamp)
        VStack(alignment: .leading, spacing: 0) {
            header
            plateRail
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    plateBody
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.void.ignoresSafeArea())
        .preferredColorScheme(runtime.lamp == .sun ? .light : .dark)
        .nightRedLamp(runtime.night)
    }

    @ViewBuilder
    private var plateBody: some View {
        switch plate {
        case .packs:
            sectionLabel("PACKS")
            packsPlate
        case .hud:
            hudPlate
        case .map:
            mapPlate
        case .sun:
            sectionLabel("SUN")
            sunPlate
        case .body:
            sectionLabel("BODY")
            bodyPlate
        case .voice:
            sectionLabel("VOICE")
            voicePlate
        }
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
        .padding(.top, 8)
        .padding(.bottom, 8)
        .safeAreaPadding(.top)
    }

    private var plateRail: some View {
        HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
            ForEach(InstrumentPlate.allCases, id: \.self) { item in
                Button(item.title) { plate = item }
                    .buttonStyle(HUDOverlayChipStyle(filled: plate == item))
            }
        }
    }

    @ViewBuilder
    private var packsPlate: some View {
        if let packs = runtime.packs {
            ForEach(packs.catalog.packs, id: \.id) { p in
                Button {
                    runtime.switchPack(p.id)
                } label: {
                    HStack {
                        Text("\(p.name) · \(p.bytes >= 1_000_000 ? "\(p.bytes / 1_000_000) MB" : "<1 MB")")
                        Spacer()
                        if runtime.packs?.active?.id == p.id {
                            Text("PACK")
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
    }

    private var hudPlate: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("HUD")
            hudToggle("LEFT HAND", $runtime.leftHand)
            HStack(spacing: 1) {
                Button("NIGHT") { runtime.tapLamp(.night) }
                    .buttonStyle(HUDActionStyle(filled: runtime.lamp == .night))
                Button("SUN") { runtime.tapLamp(.sun) }
                    .buttonStyle(HUDActionStyle(filled: runtime.lamp == .sun))
            }
            .clipShape(Theme.plateRect())
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
            hudButton("ES / EN") {
                runtime.locale = runtime.locale == "es" ? "en" : "es"
                runtime.applySpeechTone()
            }
        }
    }

    private var mapPlate: some View {
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
            .background(Theme.glass())
            .clipShape(Theme.plateRect())
            .overlay(
                Theme.plateRect()
                    .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
            )
        }
    }

    private var bodyPlate: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("SOS FLASHLIGHT") { runtime.tapSOSFlashlight() }
                .buttonStyle(HUDActionStyle(
                    filled: runtime.instruments.state.sosFlash,
                    crisis: runtime.instruments.state.sosFlash
                ))
            Text(lampWord)
                .font(.caption.weight(.bold))
                .foregroundStyle(runtime.instruments.state.sosFlash ? Theme.silver : Theme.silver.opacity(0.45))
            hudButton("COMPASS CAL") { runtime.calibrateCompass() }
            hudButton("TRUE NORTH") { runtime.setTrueNorth() }
            Text(runtime.instruments.state.magNorth ? "MAG NORTH" : "TRUE NORTH")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.silver.opacity(0.55))
            hudToggle("POCKET", Binding(
                get: { runtime.power.state.pocket },
                set: { runtime.setPocket($0) }
            ))
        }
    }

    private var voicePlate: some View {
        HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
            ForEach(NavVoice.allCases, id: \.self) { voice in
                Button(voice.title) { runtime.setNavVoice(voice) }
                    .buttonStyle(HUDActionStyle(filled: runtime.instruments.state.voice == voice))
            }
        }
    }

    private var lampWord: String {
        if runtime.instruments.state.sosFlash {
            return runtime.torchAvailable ? "SOS" : "SOS · SCREEN"
        }
        if !runtime.torchAvailable { return "LAMP · NONE" }
        return "LAMP · READY"
    }

    @ViewBuilder
    private var sunPlate: some View {
        if let pack = runtime.packs?.active {
            let packPoint = pack.home ?? pack.center
            let lat = runtime.fieldYou?.lat ?? packPoint.lat
            let lon = runtime.fieldYou?.lon ?? packPoint.lon
            let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
            let sun = Almanac.sun(lat: lat, lon: lon, dayOfYear: day)
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
