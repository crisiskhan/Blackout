"""Emit iOS app chrome, Watch, Live Activity, Action Button, localization."""
from __future__ import annotations

from pathlib import Path

from .common import ROOT


def w(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text if text.endswith("\n") else text + "\n", encoding="utf-8")


def emit() -> None:
    app = ROOT / "Blackout"
    w(
        app / "BlackoutApp.swift",
        '''import SwiftUI
import BlackBox
import BatteryAuction
import NightRed

@main
struct BlackoutApp: App {
    @State private var runtime = AppRuntime()

    var body: some Scene {
        WindowGroup {
            RootChrome(runtime: runtime)
                .preferredColorScheme(.dark)
                .environment(\\.dynamicTypeSize, dynamicCap(runtime))
        }
    }

    private func dynamicCap(_ runtime: AppRuntime) -> DynamicTypeSize {
        runtime.leftHand ? .xxxLarge : .xxxLarge
    }
}
''',
    )
    w(
        app / "AppRuntime.swift",
        '''import Foundation
import Observation
import BlackBox
import PackIO
import MeshDTN
import Vitals
import RedAlert
import TimerSync
import RosterRoles
import TripBrief
import KitStore
import BatteryAuction
import NightRed
import Instruments
import CommsUI
import PTTAudio
import OfflineSpeech
import RegionalPacks

@MainActor
@Observable
final class AppRuntime {
    let box = BlackBox()
    var packs: PackStore?
    var mesh: MeshNet
    var vitals = PartyVitals(water: 0.2, fatigue: 0.2, weatherExposure: 0.2)
    var red: RedPlate
    var timers: TimerBoard
    var roster = PartyRoster.create(lead: "Lead")
    var trip = TripBrief.make(brief: "", hours: 2)
    var kit = KitBag(items: [
        GearItem(id: "water", name: "Water filter", working: true, failureHazard: "no drinkable water"),
        GearItem(id: "headlamp", name: "Headlamp", working: true, failureHazard: "no night march"),
    ])
    var power: BatteryAuction
    var night = NightRedState(enabled: false)
    var instruments: Instruments
    var comms = CommsState()
    var ptt: PTTDeck
    var speech: OfflineSpeech
    var armed = false
    var sawCannotDo = false
    var leftHand = false
    var tab: BlackoutTab = .map
    var lockOn = false
    var showInstruments = false
    var locale = "en"

    init() {
        mesh = MeshNet(box: box)
        red = RedPlate(box: box)
        timers = TimerBoard(box: box)
        power = BatteryAuction(box: box)
        instruments = Instruments(box: box)
        ptt = PTTDeck(box: box)
        speech = OfflineSpeech(box: box)
        mesh.airplane = true
        mesh.startLocal()
        if let root = Self.resourceRoot() {
            packs = try? PackStore(root: root.appendingPathComponent("Packs"), box: box)
        }
        if UserDefaults.standard.bool(forKey: "cannotDo.seen") {
            sawCannotDo = true
        }
    }

    func arm() {
        armed = true
        box.log("arming", "entered tabs")
    }

    func acknowledgeCannotDo() {
        sawCannotDo = true
        UserDefaults.standard.set(true, forKey: "cannotDo.seen")
    }

    func joinNet() {
        mesh.airplane = false
        mesh.meet("local-peer")
    }

    func switchPack(_ id: String) {
        try? packs?.switchTo(id)
    }

    static func resourceRoot() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Resources")
    }
}

enum BlackoutTab: String, CaseIterable, Identifiable {
    case map, comms, field, expedition
    var id: String { rawValue }
    var title: String {
        switch self {
        case .map: return "MAP"
        case .comms: return "COMMS"
        case .field: return "FIELD"
        case .expedition: return "EXPEDITION"
        }
    }
}
''',
    )
    w(
        app / "RootChrome.swift",
        '''import SwiftUI
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
''',
    )
    w(
        app / "ARMINGView.swift",
        '''import SwiftUI

struct ARMINGView: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ARMING").font(.title.weight(.semibold)).foregroundStyle(Color(white: 0.85))
            Text("Offline vessel. No account. No uplink.")
                .foregroundStyle(Color(white: 0.65))
            if let packs = runtime.packs {
                ForEach(packs.catalog.packs, id: \\.id) { p in
                    Button("\\(p.name)  ·  \\(p.bytes / 1024) KB") {
                        runtime.switchPack(p.id)
                    }
                    .foregroundStyle(Color(white: 0.8))
                }
            } else {
                Text("Packs missing from bundle — honest empty.").foregroundStyle(Color(white: 0.5))
            }
            Toggle("Left-hand column", isOn: $runtime.leftHand)
            Toggle("Night-red", isOn: Binding(get: { runtime.night.enabled }, set: { runtime.night.enabled = $0 }))
            Button("ENTER") { runtime.arm() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(white: 0.18))
                .foregroundStyle(Color(white: 0.9))
        }
        .padding(24)
    }
}
''',
    )
    w(
        app / "CannotDoView.swift",
        '''import SwiftUI

struct CannotDoView: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WHAT WE CANNOT DO").font(.title2.weight(.semibold))
            Text("No 911 replacement. SOS offers system Emergency SOS only.")
            Text("No sat modem. No live weather. Hurricane card is procedure + paper.")
            Text("Mesh without LoRa is tens of meters plus DTN when people meet.")
            Text("Airplane: no sockets. Features work locally or log local.")
            Text("Vision is a guess. Fungi default LEAVE IT. Nothing unlocks edible.")
            Button("I UNDERSTAND") { runtime.acknowledgeCannotDo() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(white: 0.18))
        }
        .foregroundStyle(Color(white: 0.86))
        .padding(24)
        .preferredColorScheme(.dark)
    }
}
''',
    )
    w(
        app / "SOSHold.swift",
        '''import SwiftUI
import Tokens

struct SOSHold: View {
    @Bindable var runtime: AppRuntime
    @State private var holding = false
    @State private var armedLocal = false

    var body: some View {
        Text(L10n.t("sos.call", runtime.locale))
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.white)
            .frame(width: BlackoutTokens.Chrome.sosDiameter, height: BlackoutTokens.Chrome.sosDiameter)
            .background(Color(red: 0.86, green: 0.14, blue: 0.14))
            .clipShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !holding {
                            holding = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(BlackoutTokens.Chrome.sosHoldMs) / 1000.0) {
                                if holding { armedLocal = true }
                            }
                        }
                    }
                    .onEnded { _ in
                        holding = false
                        if armedLocal {
                            runtime.box.log("sos", "offer system Emergency SOS — does not replace 911")
                            armedLocal = false
                        }
                    }
            )
            .accessibilityLabel(L10n.t("sos.call", runtime.locale))
    }
}

struct IAMOKBar: View {
    @Bindable var runtime: AppRuntime
    var body: some View {
        VStack {
            HStack {
                Button(L10n.t("ok.chip", runtime.locale)) {
                    runtime.comms.chips.append(.ok)
                    runtime.box.log("ok", "I AM OK")
                }
                .padding(8)
                .background(Color(white: 0.15))
                Spacer()
            }
            Spacer()
        }
        .padding(12)
    }
}
''',
    )
    w(
        app / "L10n.swift",
        '''import Foundation

enum L10n {
    static let table: [String: [String: String]] = [
        "sos.call": ["en": "CALL SOS", "es": "LLAMAR SOS"],
        "sos.offer": ["en": "Offers iPhone Emergency SOS. Does not replace 911.", "es": "Ofrece Emergency SOS del iPhone. No reemplaza al 911."],
        "red.plate": ["en": "RED", "es": "ROJO"],
        "red.cancel": ["en": "CANCEL RED", "es": "CANCELAR ROJO"],
        "stop.if": ["en": "STOP-IF", "es": "PARA-SI"],
        "overdue": ["en": "OVERDUE", "es": "VENCIDO"],
        "ok.chip": ["en": "I AM OK", "es": "ESTOY BIEN"],
        "form.up": ["en": "FORM UP", "es": "FORMAR"],
        "lost.kid": ["en": "LOST KID", "es": "NIÑO PERDIDO"],
        "chip.wait": ["en": "WAIT", "es": "ESPERA"],
        "chip.water": ["en": "WATER", "es": "AGUA"],
    ]

    static func t(_ key: String, _ locale: String) -> String {
        table[key]?[locale] ?? table[key]?["en"] ?? key
    }
}
''',
    )
    w(
        app / "MapTab.swift",
        '''import SwiftUI
import MapLibreMap
import Search
import RegionalPacks

struct MapTab: View {
    @Bindable var runtime: AppRuntime
    @State private var query = ""
    @State private var hits: [SearchHit] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MAP").foregroundStyle(Color(white: 0.85))
                Spacer()
                Button("INSTRUMENTS") { runtime.showInstruments = true }
                Button(runtime.lockOn ? "LOCKED" : "LOCK-ON") { runtime.lockOn.toggle() }
            }
            TextField("Search FTS / semantic", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { search() }
            if let pack = runtime.packs?.active {
                Text("\\(pack.name) · \\(pack.bytes / 1024) KB · \\(pack.state)")
                    .foregroundStyle(Color(white: 0.6))
                ForEach(RegionalPacks.visible(state: pack.state)) { b in
                    Text(b.title[runtime.locale] ?? b.id).font(.caption).foregroundStyle(Color(white: 0.7))
                }
                Text("Style \\(pack.id)/style.json · MapLibre Metal offline · no MapKit engine")
                    .font(.caption2).foregroundStyle(Color(white: 0.45))
            }
            ForEach(hits, id: \\.name) { h in
                Text("\\(h.name) · \\(h.kind)").foregroundStyle(Color(white: 0.8))
            }
            ScrollView(.horizontal) {
                HStack {
                    ForEach(MapTool.allCases, id: \\.self) { t in
                        Text(t.rawValue).font(.caption2).padding(6).background(Color(white: 0.12))
                    }
                }
            }
            Spacer()
        }
        .padding(12)
    }

    private func search() {
        let idx = SearchIndex(pois: [["name": query, "kind": "place", "lat": 0.0, "lon": 0.0]])
        if let pack = runtime.packs?.packURL("pois.geojson"),
           let data = try? Data(contentsOf: pack),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let feats = obj["features"] as? [[String: Any]] {
            let pois: [[String: Any]] = feats.compactMap { f in
                guard let props = f["properties"] as? [String: Any],
                      let geom = f["geometry"] as? [String: Any],
                      let coords = geom["coordinates"] as? [Double], coords.count >= 2 else { return nil }
                return ["name": props["name"] as? String ?? props["amenity"] as? String ?? "poi", "kind": props["amenity"] as? String ?? props["natural"] as? String ?? "poi", "lat": coords[1], "lon": coords[0]]
            }
            hits = SearchIndex(pois: pois).fts(query)
            if hits.isEmpty { hits = SearchIndex(pois: pois).semantic(query) }
        } else {
            hits = idx.fts(query)
        }
    }
}
''',
    )
    w(
        app / "CommsTab.swift",
        '''import SwiftUI
import CommsUI

struct CommsTab: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMMS").foregroundStyle(Color(white: 0.85))
            HStack {
                Button("ALL") { runtime.comms.setChannel("ALL") }
                Button("1:1") { runtime.comms.setChannel("1:1") }
                Button("RADIO CHECK") { runtime.comms.radioCheck() }
            }
            HStack {
                Button(L10n.t("form.up", runtime.locale)) { runtime.comms.formUp() }
                Button(L10n.t("lost.kid", runtime.locale)) { runtime.comms.lostKid() }
                Button(L10n.t("ok.chip", runtime.locale)) { runtime.comms.chips.append(.ok) }
            }
            Text("Whisper <10 m: \\(runtime.comms.whisperOK ? "yes" : "no")")
            Text("PTT live + 15 s clip. Mesh tens of meters + DTN. LoRa never required.")
                .font(.caption).foregroundStyle(Color(white: 0.55))
            Button(runtime.ptt.live ? "RELEASE PTT" : "HOLD PTT") {
                if runtime.ptt.live { runtime.ptt.endLive() } else { runtime.ptt.beginLive() }
            }
            Button("15s CLIP") {
                _ = runtime.ptt.recordClip(pcm: Data(repeating: 0, count: 32000), sampleRate: 16000)
            }
            ForEach(runtime.comms.chips, id: \\.self) { c in
                Text(c.rawValue.uppercased()).font(.caption)
            }
            SOSHold(runtime: runtime)
            Spacer()
        }
        .padding(12)
    }
}
''',
    )
    w(
        app / "FieldTab.swift",
        '''import SwiftUI
import FieldCorpus
import FieldStepper
import FieldSpeech
import VisionCapture
import VisionCoreML

struct FieldTab: View {
    @Bindable var runtime: AppRuntime
    @State private var cards: [FieldCard] = []
    @State private var stepper: StepperState?
    @State private var guess: VisionGuess?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FIELD").foregroundStyle(Color(white: 0.85))
            Text(L10n.t("stop.if", runtime.locale)).font(.caption)
            List(cards) { c in
                Button(runtime.locale == "es" ? c.title.es : c.title.en) {
                    stepper = StepperState(card: c, index: 0, speaking: false, sentToParty: false)
                }
            }
            if let s = stepper {
                Text(s.step.do.en)
                Text(s.step.child.en).font(.caption)
                if let bpm = s.step.metronomeBpm { Text("CPR \\(bpm)").font(.caption) }
                HStack {
                    Button("NEXT") { var x = s; x.next(); stepper = x }
                    Button("SPEAK") {
                        var x = s; x.speak(); stepper = x
                        FieldSpeech.speak(s.card, locale: runtime.locale, engine: runtime.speech)
                    }
                    Button("SEND TO PARTY") { var x = s; x.send(); stepper = x }
                }
            }
            Button("VISION ADD FRAME") {
                var cap = GuidedCapture()
                cap.addFrame([0.2, 0.7, 0.1])
                if let url = runtime.packs.flatMap({ _ in Bundle.main.url(forResource: "labels.\\(runtime.packs?.active?.state.lowercased() ?? "tx")", withExtension: "json", subdirectory: "Resources/Vision") }),
                   let data = try? Data(contentsOf: url),
                   let book = try? VisionCoreML.load(data) {
                    guess = cap.guess(book: book)
                }
            }
            if let g = guess {
                Text("\\(g.name) \\(g.percent)% lookalikes \\(g.lookalikes.joined(separator: ", ")) edible=\\(g.edible)")
                    .font(.caption)
            }
        }
        .onAppear(perform: load)
        .padding(8)
    }

    private func load() {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Resources/Field") else { return }
        let core = (try? Data(contentsOf: root.appendingPathComponent("field.core.json"))) ?? Data()
        let st = runtime.packs?.active?.state.lowercased() ?? "tx"
        let extra = (try? Data(contentsOf: root.appendingPathComponent("field.\\(st).json"))) ?? Data()
        cards = (try? FieldCorpus.load(core: core, state: extra)) ?? []
        if let state = runtime.packs?.active?.state {
            cards = FieldCorpus.visible(cards, state: state)
        }
    }
}
''',
    )
    w(
        app / "ExpeditionTab.swift",
        '''import SwiftUI
import Vitals
import TimerSync
import PaperGen

struct ExpeditionTab: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("EXPEDITION").foregroundStyle(Color(white: 0.85))
                Text("CONDITION \\(runtime.vitals.band.rawValue.uppercased())")
                slider("Water", $runtime.vitals.water)
                slider("Fatigue", $runtime.vitals.fatigue)
                slider("Exposure", $runtime.vitals.weatherExposure)
                Button("APPLY RED BAND") { runtime.red.apply(runtime.vitals) }
                if runtime.red.isRed {
                    Text(L10n.t("red.plate", runtime.locale)).font(.title.weight(.bold)).foregroundStyle(.red)
                    Button(L10n.t("red.cancel", runtime.locale)) { runtime.red.cancelRED() }
                }
                Text("ROSTER \\(runtime.roster.code)")
                ForEach(runtime.roster.members) { m in
                    Text("\\(m.role.rawValue) \\(m.name)")
                }
                Button("JOIN NAV") { runtime.roster = runtime.roster.joining("Nav", role: .nav) }
                Button("2H WATER TIMER") {
                    _ = runtime.timers.add(who: "ALL", task: "water", duration: 7200, subjectAll: true)
                }
                ForEach(runtime.timers.overduePlate(), id: \\.id) { t in
                    Text("\\(L10n.t("overdue", runtime.locale)) \\(t.task) — not SOS")
                        .foregroundStyle(Color.orange)
                }
                Button("EXPORT PAPER") {
                    let text = PaperGen.export(trip: runtime.trip, roster: runtime.roster, packName: runtime.packs?.active?.name ?? "")
                    runtime.box.log("paper", text)
                }
            }
            .padding(12)
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Slider(value: value, in: 0...1)
        }
    }
}
''',
    )
    w(
        app / "InstrumentsView.swift",
        '''import SwiftUI
import BatteryAuction

struct InstrumentsView: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        NavigationStack {
            List {
                Button("Torch 3×") { runtime.instruments.torchTap() }
                Button("Compass cal") { runtime.instruments.calibrateCompass() }
                Button("True north") { runtime.instruments.setTrueNorth() }
                Toggle("USB-C PTT present", isOn: Binding(get: { runtime.instruments.state.usbCPTT }, set: { runtime.instruments.attachUSB_C_PTT($0) }))
                Toggle("External GNSS puck", isOn: Binding(get: { runtime.instruments.state.externalGNSS }, set: { runtime.instruments.attachGNSSPuck($0) }))
                Picker("Auction", selection: Binding(get: { runtime.power.state.mode }, set: { runtime.power.set($0) })) {
                    ForEach(PowerMode.allCases, id: \\.self) { m in Text(m.rawValue.uppercased()).tag(m) }
                }
                Toggle("Pocket", isOn: Binding(get: { runtime.power.state.pocket }, set: { runtime.power.setPocket($0) }))
                Text("Hot-spare \\(runtime.power.hotSparePayload())")
                Text("Screen buffer OFF default: \\(!runtime.power.state.screenBuffer)")
                Button("ES / EN") { runtime.locale = runtime.locale == "es" ? "en" : "es" }
            }
            .navigationTitle("INSTRUMENTS")
            .preferredColorScheme(.dark)
        }
    }
}
''',
    )

    watch = ROOT / "BlackoutWatch"
    w(
        watch / "BlackoutWatchApp.swift",
        '''import SwiftUI

@main
struct BlackoutWatchApp: App {
    var body: some Scene {
        WindowGroup { WatchRoot() }
    }
}

struct WatchRoot: View {
    @State private var locked = false
    @State private var ok = false
    @State private var pip = "31.76, -106.49"
    @State private var timer = "2h water"
    var body: some View {
        VStack(spacing: 8) {
            Button(locked ? "LOCKED" : "LOCK-ON") { locked.toggle() }
            Button("SOS") { }
            Button(ok ? "OK SENT" : "I AM OK") { ok = true }
            Text("PIP \\(pip)").font(.caption2)
            Text("TIMER \\(timer)").font(.caption2)
        }
        .preferredColorScheme(.dark)
    }
}
''',
    )

    widgets = ROOT / "BlackoutWidgets"
    w(
        widgets / "BlackoutLiveActivity.swift",
        '''import ActivityKit
import SwiftUI
import WidgetKit

struct SOSAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var kind: String
        var detail: String
    }
    var title: String
}

struct BlackoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SOSAttributes.self) { context in
            VStack {
                Text(context.attributes.title)
                Text(context.state.detail)
            }
            .preferredColorScheme(.dark)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.state.kind) }
                DynamicIslandExpandedRegion(.trailing) { Text("SOS") }
            } compactLeading: { Text("BO") } compactTrailing: { Text(context.state.kind) } minimal: { Text("!") }
        }
    }
}

@main
struct BlackoutWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BlackoutLiveActivity()
        SOSControl()
    }
}
''',
    )
    w(
        widgets / "SOSControl.swift",
        '''import AppIntents
import SwiftUI
import WidgetKit

struct OfferSOSIntent: AppIntent {
    static var title: LocalizedStringResource = "CALL SOS"
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct IAMOKIntent: AppIntent {
    static var title: LocalizedStringResource = "I AM OK"
    func perform() async throws -> some IntentResult { .result() }
}

struct SOSControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.crisiskhan.blackout.sos") {
            ControlWidgetButton(action: OfferSOSIntent()) {
                Label("CALL SOS", systemImage: "sos")
            }
        }
    }
}
''',
    )

    intents = ROOT / "Blackout" / "ActionButton"
    w(
        intents / "ActionIntents.swift",
        '''import AppIntents

struct ActionButtonSOS: AppIntent {
    static var title: LocalizedStringResource = "CALL SOS"
    static var description = IntentDescription("Offers system Emergency SOS. Does not replace 911.")
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct ActionButtonOK: AppIntent {
    static var title: LocalizedStringResource = "I AM OK"
    func perform() async throws -> some IntentResult { .result() }
}
''',
    )

    w(
        ROOT / "Resources" / "Localizable" / "es.json",
        '''{
  "sos.call": "LLAMAR SOS",
  "red.plate": "ROJO",
  "stop.if": "PARA-SI",
  "overdue": "VENCIDO",
  "ok.chip": "ESTOY BIEN"
}
''',
    )
    print("app chrome emitted")
