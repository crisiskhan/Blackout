import Foundation
import Observation
import CoreLocation
import UIKit
import AVFoundation
import BlackBox
import PackIO
import MapLibreMap
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
import Router
import Tokens
import VisionCoreML
import FieldCorpus

@MainActor
@Observable
final class AppRuntime {
    let box = EventLog()
    var packs: PackStore?
    var mesh: MeshNet
    var vitals = PartyVitals(water: 0.2, fatigue: 0.2, weatherExposure: 0.2)
    var red: RedPlate
    var timers: TimerBoard
    var roster = PartyRoster.create(lead: "Lead")
    var trip = TripFactory.make(brief: "", hours: 2)
    var kit = KitBag(items: [
        GearItem(id: "water", name: "Water filter", working: true, failureHazard: "no drinkable water"),
        GearItem(id: "headlamp", name: "Headlamp", working: true, failureHazard: "no night march"),
    ])
    var power: AuctionBoard
    var night = NightRedState(enabled: false)
    var instruments: InstrumentBoard
    var comms = CommsState()
    var ptt: PTTDeck
    var speech: SpeechEngine
    var armed = false
    var bootStage: BootStage = .cold
    var bootProgress: Double = 0
    var bootStyleURL: URL?
    var leftHand = false
    var tab: BlackoutTab = .map
    var lockOn = false
    var showInstruments = false
    var chromeAwake = true
    var hudLayoutMode = false
    var hudLayout = HUDLayout.load()
    var hudFocus: HUDFocus = .none
    var locale = "en"
    var lastKnownFix: (lat: Double, lon: Double)?
    var marks: [MapMark] = []
    /// The inspect card the map is holding open. `nil` whenever it is clear.
    var held: HeldPoint?
    /// Cards the FIELD tab should try to open the next time it appears, best
    /// first, set by the hold card's FIELD button. The last one is always core,
    /// so the walk down the list cannot come up empty.
    var fieldJump: [String]?
    /// Card ids the open pack's Field book actually ships. The hold button
    /// names the first of these on the route, so a Texas peak is not COLD
    /// for an ice-on-rock card that is not in the book.
    var fieldBookIDs: Set<String> = []
    var headingDeg: Double?
    var youEmblem: PersonEmblem = .wolf
    var lockChrome = ""
    var speechChrome = ""
    /// Mic deny on CALL. Empty unless the last arm failed.
    var commsChrome = ""
    /// 15s CLIP is armed. The pad reads RECORDING until the clip ends.
    var clipLive = false
    /// Machine plan state for VoiceNav: "" on graph, `GraphPlan.offGraph` otherwise.
    var navChrome = ""
    /// What the map says after a WALK/DRIVE tap: the route, or why there isn't one.
    var routeChrome = ""
    var toolChrome = ""
    var routeCoords: [(lat: Double, lon: Double)] = []
    var routeTarget: (lat: Double, lon: Double)?
    /// Last WALK or DRIVE tap. The canvas dashes the core for a walk.
    var travelMode: TravelMode = .walk
    /// Bumped by FIT PACK. The canvas otherwise opens on YOU at walking zoom.
    var fitPackToken = 0
    var canRouteOnGraph: Bool { packs?.hasUsableGraph() ?? false }
    private var graphCache: RouteGraph?
    private var graphsByPack: [String: RouteGraph] = [:]
    private var graphPackID: String?
    private var graphWarmup: Task<RouteGraph?, Never>?
    private var waterCache: WaterIndex?
    private var watersByPack: [String: WaterIndex] = [:]
    private var waterPackID: String?
    private var waterWarmup: Task<WaterIndex?, Never>?
    private var bootTask: Task<Void, Never>?
    private var clipTask: Task<Void, Never>?
    private var pulseTask: Task<Void, Never>?
    /// Thumb is down on HOLD PTT. Live chrome waits on the mic.
    private var pttHold = false
    /// CLIP tap is waiting on the mic. Not live yet.
    private var clipArming = false
    private let fix = MeshFix()

    init() {
        mesh = MeshNet(box: box)
        red = RedPlate(box: box)
        timers = TimerBoard(box: box)
        power = AuctionBoard(box: box)
        instruments = InstrumentBoard(box: box)
        ptt = PTTDeck(box: box)
        speech = SpeechEngine(box: box)
        mesh.airplane = true
        if let saved = UserDefaults.standard.string(forKey: "party.code"), !saved.isEmpty {
            roster = roster.setting(code: saved)
        }
        mesh.partyCode = roster.code
        youEmblem = PersonEmblem.load()
        mesh.onInbound = { [weak self] env in
            Task { @MainActor in self?.applyInbound(env) }
        }
        mesh.onPeersChanged = { [weak self] in
            Task { @MainActor in self?.sendPOSIfPossible() }
        }
        mesh.startLocal()
        fix.onChange = { [weak self] in
            Task { @MainActor in self?.pullFix() }
        }
        if let root = Self.resourceRoot() {
            packs = try? PackStore(root: root.appendingPathComponent("Packs"), box: box)
            if let id = UserDefaults.standard.string(forKey: "pack.id") {
                try? packs?.switchTo(id)
            }
        }
        marks = MarkStore.load()
        relabelMarksForActivePack()
        loadFieldBookIDs()
        bootVessel()
        applyMapKeepAwake()
    }

    var bootReady: Bool {
        switch bootStage {
        case .ready, .failed:
            return true
        case .cold, .loading:
            return false
        }
    }

    /// Cold launch: read every shipped pack, resolve its style, load its graph.
    /// ACTIVATE stays dark until this finishes. TX WEST is still the first map.
    func bootVessel() {
        guard bootTask == nil else { return }
        bootTask = Task { [weak self] in
            await self?.runBoot()
        }
    }

    func arm() {
        guard bootReady else { return }
        armed = true
        box.log("arming", "activated")
        applyMapKeepAwake()
        pulse()
    }

    func joinNet() {
        mesh.airplane = true
        mesh.partyCode = roster.code
        persistPartyCode()
        if mesh.radio == nil { mesh.attach(LiveMeshRadio()) }
        mesh.startLocal()
    }

    func leaveNet() {
        clipTask?.cancel()
        clipTask = nil
        clipLive = false
        clipArming = false
        pttHold = false
        if ptt.live { endPTTSolo() }
        _ = PTTMic.shared.stop()
        mesh.stopLocal()
        comms.radioCheck(heard: false)
        commsChrome = ""
    }

    func persistPartyCode() {
        UserDefaults.standard.set(roster.code, forKey: "party.code")
    }

    func pickEmblem(_ emblem: PersonEmblem) {
        youEmblem = emblem
        PersonEmblem.save(emblem)
        sendPOSIfPossible()
    }

    func dropMark() {
        pulse()
        fix.arm()
        let lat = fix.last?.latitude ?? lastKnownFix?.lat ?? packs?.active?.center.lat
        let lon = fix.last?.longitude ?? lastKnownFix?.lon ?? packs?.active?.center.lon
        guard let lat, let lon else { return }
        dropMark(lat: lat, lon: lon)
    }

    /// A mark on a place the thumb chose rather than on the fix. `name` is the
    /// record's own name when it has one; it goes in front of the coordinate
    /// label so a list of marks reads as places instead of numbers.
    func dropMark(lat: Double, lon: Double, name: String? = nil) {
        let pack = packs?.active
        let bbox = pack.map { ($0.bbox.south, $0.bbox.west, $0.bbox.north, $0.bbox.east) }
        let coords = PackChrome.markLabel(
            lat: lat,
            lon: lon,
            packName: pack?.name ?? "mark",
            bbox: bbox
        )
        let named = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let label = named.isEmpty || named == Inspect.unnamed ? coords : "\(named) · \(coords)"
        marks = MarkDrop.merging(marks, lat: lat, lon: lon, label: label)
        MarkStore.save(marks)
    }

    // MARK: - Hold to inspect

    /// A thumb stayed put long enough to mean it. Read the record under it and
    /// raise the card. This never calls SOS and never routes anywhere; it only
    /// says what is there.
    func holdInspect(lat: Double, lon: Double, tags: [String: String], zoom: Double) {
        pulse()
        let id = packs?.active?.id
        let index = id.flatMap { watersByPack[$0] } ?? (waterPackID == id ? waterCache : nil)
        held = HeldPoint(
            lat: lat,
            lon: lon,
            card: Inspect.resolve(
                tags: tags,
                lat: lat,
                lon: lon,
                zoom: zoom,
                index: index,
                packDate: packs?.active?.osmFetched,
                state: packs?.active?.state,
                pack: packs?.active?.id
            ),
            // Holding a spring marked last week has to open reading MARKED.
            // Marks merge by coordinate, so pressing MARK there does nothing,
            // and a button that offers something it will not do is a lie.
            marked: marks.contains { MarkDrop.sameCoord(($0.lat, $0.lon), (lat, lon)) }
        )
    }

    func closeHold() {
        held = nil
        pulse()
    }

    /// MARK on the card puts the mark on the held place, not on the fix.
    func markHeld() {
        guard let point = held, !point.marked else { return }
        dropMark(lat: point.lat, lon: point.lon, name: point.card.title)
        held?.marked = true
    }

    /// FIELD on the card hands the matching card to the FIELD tab and goes
    /// there. Water reaches the treat tree; ground reaches its own biome card.
    ///
    /// The card button that calls this still owns the stack. Switching tab and
    /// nil-ing `held` here tore the card out from under that button and crashed
    /// on device (ASC 72). Queue the teardown for the next main turn so the
    /// button can finish first; the Field route is latched already.
    func openFieldFromHold() {
        guard let point = held else { return }
        fieldJump = point.card.fieldRoute
        Task { @MainActor in
            tab = .field
            closeHold()
            applyMapKeepAwake()
        }
    }

    func toggleLockOn() {
        touch(.overlay)
        lockOn.toggle()
        if !lockOn {
            lockChrome = ""
            return
        }
        fix.arm()
        pullFix()
        let hasGPS = fix.last != nil || lastKnownFix != nil
        let hasGraph = packs?.hasUsableGraph() ?? false
        lockChrome = LockOnChrome.banner(hasGPS: hasGPS, hasGraph: hasGraph)
        sendPOSIfPossible()
    }

    func pickDestination(lat: Double, lon: Double) {
        pulse()
        routeTarget = (lat, lon)
        // A new destination invalidates everything the old one produced.
        routeCoords = []
        navChrome = ""
        routeChrome = ""
        toolChrome = ""
        speechChrome = ""
    }

    func navigate(mode: TravelMode) {
        touch(.dock)
        speechChrome = ""
        travelMode = mode
        let pack = packs?.active
        let packName = pack?.name ?? ""
        let dest = destination()
        if let block = WalkDriveChip.block(
            hasPack: pack != nil,
            hasUsableGraph: canRouteOnGraph,
            hasDestination: dest != nil,
            destinationOnPack: destinationOnPack(dest)
        ) {
            clearRoute(plan: block.planChrome, chrome: block.chrome(mode: mode, packName: packName))
            return
        }
        guard let dest else { return }
        routeTarget = dest
        routeCoords = []
        navChrome = ""
        routeChrome = WalkDriveChip.working(mode: mode)
        let from = youCoordinate()
        let id = pack?.id
        let url = packs?.graphURL()
        let cached = id.flatMap { graphsByPack[$0] } ?? (graphPackID == id ? graphCache : nil)
        let inflight = graphWarmup
        Task { [weak self] in
            let graph: RouteGraph?
            if let cached {
                graph = cached
            } else if let inflight {
                graph = await inflight.value
            } else {
                graph = await Task.detached { RouteGraph.load(from: url) }.value
            }
            let plan = await Task.detached {
                GraphPlan.line(graph: graph, from: from, to: dest, mode: mode)
            }.value
            await MainActor.run {
                guard let self, self.packs?.active?.id == id else { return }
                self.graphCache = graph
                self.graphPackID = id
                self.routeCoords = plan.coords
                self.navChrome = plan.chrome
                self.routeChrome = RouteLine.shouldDraw(plan.coords)
                    ? RouteSummary.chrome(mode: mode, coords: plan.coords)
                    : RouteBlock.noPath.chrome(mode: mode, packName: packName)
            }
        }
    }

    func fitPack() {
        fitPackToken += 1
    }

    func tapRuler() {
        toolChrome = MapRuler.chrome(from: youCoordinate(), to: destination())
        showInstruments = false
    }

    func tapUSNG() {
        let you = youCoordinate()
        toolChrome = USNG.label(lat: you.lat, lon: you.lon)
        showInstruments = false
    }

    func tapMagTrue() {
        instruments.toggleMagTrue()
        toolChrome = MagTrueChip.chrome(magNorth: instruments.state.magNorth)
        showInstruments = false
    }

    /// SOS is a mesh-wide alert, not a label. The hold wakes the radio if it
    /// is down, lights every peer with chip + RED + POS, and never auto-dials.
    var hudCrisis: Bool {
        red.isRed || comms.chips.contains(.sos)
    }

    var chromeVeil: Double {
        HUDPulse.opacity(awake: chromeAwake, crisis: hudCrisis, arranging: hudLayoutMode)
    }

    func alive(_ piece: HUDFocus) -> Double {
        if hudLayoutMode { return 1 }
        return HUDPulse.piece(focus: hudFocus, piece: piece)
    }

    func touch(_ piece: HUDFocus) {
        pulse()
        hudFocus = piece
    }

    func pulse() {
        chromeAwake = true
        hudFocus = .none
        pulseTask?.cancel()
        pulseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(BlackoutTokens.Chrome.chromeIdleSeconds))
            if Task.isCancelled { return }
            if hudCrisis || hudLayoutMode || held != nil { return }
            hudFocus = .none
            chromeAwake = false
        }
    }

    func resetHUD() {
        hudLayout = .origin
        hudLayout.save()
        hudLayoutMode = false
        pulse()
    }

    func offerSOS() {
        pulse()
        if mesh.radio == nil {
            joinNet()
        }
        if !comms.chips.contains(.sos) {
            comms.push(.sos)
        }
        mesh.sendChip(from: mesh.localID, chip: Chip.sos.rawValue)
        red.force(true)
        mesh.sendRED(from: mesh.localID, on: true)
        sendPOSIfPossible()
        box.log("sos", "mesh SOS armed")
    }

    /// I AM OK is the all-clear: the mesh hears it, the SOS chip goes dark,
    /// and a RED plate we lit goes dark.
    func iamOK() {
        comms.chips.removeAll { $0 == .sos }
        mesh.clearInboundChip(Chip.sos.rawValue)
        if !comms.chips.contains(.ok) {
            comms.push(.ok)
        }
        mesh.sendChip(from: mesh.localID, chip: Chip.ok.rawValue)
        if red.isRed {
            cancelSelfRed()
        }
        box.log("ok", "I AM OK")
    }

    func speakMap() {
        touch(.dock)
        let pack = packs?.active?.name ?? "no pack"
        let text = VoiceNav.prompt(
            packName: pack,
            headingDeg: headingDeg,
            routeCoords: routeCoords,
            planChrome: navChrome,
            destination: destination(),
            you: youCoordinate(),
            locale: locale
        )
        // The whole turn-by-turn script goes to the voice. The field only gets one short
        // status line — the route itself is already drawn in silver.
        let spoke = speech.speak(text, locale: locale)
        speechChrome = SpeakStatus.chrome(
            spoke: spoke,
            routeCoords: routeCoords,
            planChrome: navChrome,
            destination: destination(),
            you: youCoordinate()
        )
    }

    func beginPTTSolo() {
        if clipTask != nil { finishClip() }
        guard !ptt.live, !pttHold else { return }
        pttHold = true
        commsChrome = ""
        PTTMic.shared.arm { [weak self] ok in
            guard let self else { return }
            guard self.pttHold else {
                _ = PTTMic.shared.stop()
                return
            }
            guard ok else {
                self.commsChrome = "MIC DENIED"
                self.pttHold = false
                return
            }
            self.ptt.beginLive()
            self.mesh.sendChip(from: self.mesh.localID, chip: "ptt", to: self.meshDest)
        }
    }

    func endPTTSolo() {
        pttHold = false
        guard ptt.live else {
            _ = PTTMic.shared.stop()
            return
        }
        let pcm = PTTMic.shared.stop()
        ptt.endLive()
        _ = ptt.recordClip(pcm: pcm, sampleRate: 16_000)
        if !pcm.isEmpty, let opus = ptt.last?.opus {
            mesh.sendVoice(from: mesh.localID, opus: opus, to: meshDest)
        }
    }

    func captureClip() {
        if clipTask != nil || clipLive {
            finishClip()
            return
        }
        if clipArming { return }
        if ptt.live { endPTTSolo() }
        commsChrome = ""
        clipArming = true
        PTTMic.shared.arm { [weak self] ok in
            guard let self else { return }
            guard self.clipArming else {
                _ = PTTMic.shared.stop()
                return
            }
            if !ok {
                self.commsChrome = "MIC DENIED"
                self.clipLive = false
                self.clipArming = false
                _ = self.ptt.recordClip(pcm: Data(), sampleRate: 16_000)
                return
            }
            self.clipLive = true
            self.clipArming = false
            self.clipTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { return }
                self.finishClip()
            }
        }
    }

    func radioCheckParty() {
        comms.radioCheck(heard: mesh.joined)
        mesh.sendChip(from: mesh.localID, chip: "radio", to: meshDest)
    }

    func sendPartyChip(_ chip: Chip) {
        comms.push(chip)
        mesh.sendChip(from: mesh.localID, chip: chip.rawValue, to: meshDest)
    }

    func tapTorch() {
        instruments.torchTap()
        applyTorch(level: instruments.state.torchClicks)
    }

    private func applyTorch(level: Int) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if level == 0 {
                device.torchMode = .off
            } else if device.isTorchModeSupported(.on) {
                let fraction = Float(level) / 3.0
                try device.setTorchModeOn(level: max(0.1, min(1, fraction)))
            }
            device.unlockForConfiguration()
        } catch {
            box.log("torch", "lamp failed")
        }
    }

    func applySelfRed() {
        red.apply(vitals)
        mesh.sendRED(from: mesh.localID, on: red.isRed)
    }

    func cancelSelfRed() {
        red.cancelRED()
        mesh.sendRED(from: mesh.localID, on: false)
    }

    func sendFieldToParty(cardID: String) {
        mesh.sendChip(from: mesh.localID, chip: "field:\(cardID)")
    }

    private var meshDest: String {
        comms.meshTo(nearby: mesh.nearby)
    }

    private func finishClip() {
        clipTask?.cancel()
        clipTask = nil
        clipLive = false
        clipArming = false
        let pcm = PTTMic.shared.stop()
        _ = ptt.recordClip(pcm: pcm, sampleRate: 16_000)
        if pcm.isEmpty {
            commsChrome = "CLIP EMPTY"
            return
        }
        if let opus = ptt.last?.opus {
            mesh.sendVoice(from: mesh.localID, opus: opus, to: meshDest)
        }
    }

    func visionBook() -> VisionBook? {
        let state = packs?.active?.state.lowercased() ?? "tx"
        guard let root = Self.resourceRoot() else { return nil }
        let url = root.appendingPathComponent("Vision/labels.\(state).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? VisionCoreML.load(data)
    }

    func sendPOSIfPossible() {
        fix.arm()
        let pack = packs?.active?.center
        let lat = fix.last?.latitude ?? lastKnownFix?.lat ?? pack?.lat
        let lon = fix.last?.longitude ?? lastKnownFix?.lon ?? pack?.lon
        guard let lat, let lon else { return }
        lastKnownFix = (lat, lon)
        mesh.sendPOS(
            from: mesh.localID,
            lat: lat,
            lon: lon,
            headingDeg: headingDeg,
            emblem: youEmblem.rawValue
        )
    }

    func applyInbound(_ env: MeshEnvelope) {
        switch env.kind {
        case "red":
            red.force(String(data: env.body, encoding: .utf8) == "on")
        case "timer.set":
            if let task = String(data: env.body, encoding: .utf8) {
                _ = timers.add(who: env.from, task: task, duration: 7200, subjectAll: true)
            }
        case "timer.done":
            if let task = String(data: env.body, encoding: .utf8) {
                timers.markDoneTask(task)
            }
        case "chip":
            if let raw = String(data: env.body, encoding: .utf8) {
                if raw == Chip.sos.rawValue {
                    red.force(true)
                }
                if let chip = Chip(rawValue: raw) {
                    comms.push(chip)
                }
            }
        case "voice":
            if let pcm = OpusLite.decode(env.body) {
                PTTMic.shared.play(pcm)
            }
        default:
            break
        }
    }

    func switchPack(_ id: String) {
        try? packs?.switchTo(id)
        UserDefaults.standard.set(id, forKey: "pack.id")
        routeTarget = nil
        clearRoute(plan: "", chrome: "")
        relabelMarksForActivePack()
        graphCache = graphsByPack[id]
        graphPackID = id
        waterCache = watersByPack[id]
        waterPackID = id
        if let pack = packs?.active, let root = Self.resourceRoot()?.appendingPathComponent("Packs") {
            let packRoot = root.appendingPathComponent(pack.id)
            bootStyleURL = try? PackStyle.resolved(
                styleAt: packRoot.appendingPathComponent("style.json"),
                packRoot: packRoot
            )
        }
        if graphCache == nil {
            graphWarmup = nil
            warmupActiveGraph()
        }
        if waterCache == nil {
            waterWarmup = nil
            warmupActiveWater()
        }
        loadFieldBookIDs()
    }

    func applyMapKeepAwake() {
        UIApplication.shared.isIdleTimerDisabled = MapKeepAwake.idleTimerDisabled(
            mapInstrumentActive: armed && tab == .map
        )
    }

    private func youCoordinate() -> (lat: Double, lon: Double) {
        let pack = packs?.active
        let home = packs?.homeCoordinate()
        return UserPuck.coordinate(
            lastKnown: lastKnownFix,
            packCenter: (home?.lat ?? pack?.center.lat ?? 0, home?.lon ?? pack?.center.lon ?? 0),
            packSouth: pack?.bbox.south ?? 0,
            packWest: pack?.bbox.west ?? 0,
            packNorth: pack?.bbox.north ?? 0,
            packEast: pack?.bbox.east ?? 0
        )
    }

    private func destination() -> (lat: Double, lon: Double)? {
        RouteTarget.pick(
            explicit: routeTarget,
            lastMark: marks.last.map { ($0.lat, $0.lon) },
            origin: youCoordinate()
        )
    }

    private func runBoot() async {
        let started = Date()
        bootStage = .loading("PACKS")
        bootProgress = 0.04
        guard let store = packs else {
            bootStage = .failed("Packs missing from bundle — honest empty.")
            bootProgress = 0
            return
        }
        let catalog = store.catalog.packs
        guard !catalog.isEmpty else {
            bootStage = .failed("Packs missing from bundle — honest empty.")
            return
        }
        let steps = Double(catalog.count * 2 + 1)
        var done = 0.0
        var loaded: [String: RouteGraph] = [:]
        var waters: [String: WaterIndex] = [:]
        for pack in catalog {
            bootStage = .loading(pack.name.uppercased())
            let root = store.packRoot(id: pack.id)
            let style = root.appendingPathComponent("style.json")
            let resolved = try? PackStyle.resolved(styleAt: style, packRoot: root)
            if pack.id == store.active?.id {
                bootStyleURL = resolved
            }
            done += 1
            bootProgress = done / steps
            let url = store.graphURL(for: pack.id)
            let waterURL = root.appendingPathComponent("layers/water.bin")
            let graph = await Task.detached { RouteGraph.load(from: url) }.value
            let water = await Task.detached { WaterIndex.load(from: waterURL) }.value
            if let graph {
                loaded[pack.id] = graph
            }
            if let water {
                waters[pack.id] = water
            }
            done += 1
            bootProgress = done / steps
        }
        prefetchField()
        done += 1
        bootProgress = 1
        graphsByPack = loaded
        watersByPack = waters
        if let id = store.active?.id {
            graphCache = loaded[id]
            graphPackID = id
            waterCache = waters[id]
            waterPackID = id
        }
        let remain = BlackoutTokens.Chrome.bootMinSeconds - Date().timeIntervalSince(started)
        if remain > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remain * 1_000_000_000))
        }
        bootStage = .ready
        box.log("boot", "ready packs=\(loaded.count)")
    }

    private func prefetchField() {
        guard let root = Self.resourceRoot()?.appendingPathComponent("Field") else { return }
        for name in ["field.core.json", "field.tx.json", "field.nm.json"] {
            _ = try? Data(contentsOf: root.appendingPathComponent(name), options: .mappedIfSafe)
        }
        loadFieldBookIDs()
    }

    /// Core plus this state's book, minus the other state's cards. Hold reads
    /// this so FIELD · COLD is only offered when ice-on-rock is actually
    /// in the loaded book.
    private func loadFieldBookIDs() {
        guard let root = Self.resourceRoot()?.appendingPathComponent("Field") else {
            fieldBookIDs = []
            return
        }
        let core = (try? Data(contentsOf: root.appendingPathComponent("field.core.json"))) ?? Data()
        let st = packs?.active?.state.lowercased() ?? "tx"
        let extra = (try? Data(contentsOf: root.appendingPathComponent("field.\(st).json"))) ?? Data()
        let cards = (try? FieldCorpus.load(core: core, state: extra)) ?? []
        if let state = packs?.active?.state {
            fieldBookIDs = Set(FieldCorpus.visible(cards, state: state).map(\.id))
        } else {
            fieldBookIDs = Set(cards.map(\.id))
        }
    }

    private func warmupActiveGraph() {
        let id = packs?.active?.id
        let url = packs?.graphURL()
        let task = Task.detached { RouteGraph.load(from: url) }
        graphWarmup = task
        Task { [weak self] in
            let graph = await task.value
            await MainActor.run {
                guard let self, self.packs?.active?.id == id else { return }
                self.graphCache = graph
                self.graphPackID = id
            }
        }
    }

    private func warmupActiveWater() {
        let id = packs?.active?.id
        let url = packs?.packURL("layers/water.bin")
        let task = Task.detached { WaterIndex.load(from: url) }
        waterWarmup = task
        Task { [weak self] in
            let index = await task.value
            await MainActor.run {
                guard let self, self.packs?.active?.id == id else { return }
                self.waterCache = index
                self.waterPackID = id
                if let id, let index {
                    self.watersByPack[id] = index
                }
            }
        }
    }

    private func clearRoute(plan: String, chrome: String) {
        routeCoords = []
        navChrome = plan
        routeChrome = chrome
        speechChrome = ""
    }

    private func destinationOnPack(_ dest: (lat: Double, lon: Double)?) -> Bool {
        guard let dest else { return false }
        return coordinateOnPack(lat: dest.lat, lon: dest.lon)
    }

    private func coordinateOnPack(lat: Double, lon: Double) -> Bool {
        guard let pack = packs?.active else { return false }
        return UserPuck.contains(
            lat: lat,
            lon: lon,
            south: pack.bbox.south,
            west: pack.bbox.west,
            north: pack.bbox.north,
            east: pack.bbox.east
        )
    }

    private func relabelMarksForActivePack() {
        guard let pack = packs?.active else { return }
        let names = packs?.catalog.packs.map(\.name) ?? []
        marks = marks.map { m in
            MapMark(
                id: m.id,
                lat: m.lat,
                lon: m.lon,
                label: MarkLabel.relabel(
                    existing: m.label,
                    packName: pack.name,
                    packNames: names,
                    offPack: !coordinateOnPack(lat: m.lat, lon: m.lon)
                )
            )
        }
        MarkStore.save(marks)
    }

    private func pullFix() {
        headingDeg = fix.heading
        if let c = fix.last {
            lastKnownFix = (c.latitude, c.longitude)
        }
        sendPOSIfPossible()
    }

    static func resourceRoot() -> URL? {
        guard let base = Bundle.main.resourceURL else { return nil }
        let flat = base.appendingPathComponent("Packs/catalog.json")
        if FileManager.default.fileExists(atPath: flat.path) {
            return base
        }
        let nested = base.appendingPathComponent("Resources")
        if FileManager.default.fileExists(atPath: nested.appendingPathComponent("Packs/catalog.json").path) {
            return nested
        }
        return base
    }
}

final class MeshFix: NSObject, CLLocationManagerDelegate {
    var last: CLLocationCoordinate2D?
    var heading: Double?
    var onChange: (() -> Void)?
    private var mgr: CLLocationManager?
    private var lastPublish: TimeInterval = 0
    private var publishedHeading: Double?
    private var publishedCoord: (lat: Double, lon: Double)?

    func arm() {
        let mgr = self.mgr ?? CLLocationManager()
        self.mgr = mgr
        mgr.delegate = self
        switch mgr.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            mgr.startUpdatingLocation()
            startHeading()
        case .notDetermined:
            mgr.requestWhenInUseAuthorization()
        default:
            startHeading()
        }
    }

    private func startHeading() {
        guard CLLocationManager.headingAvailable() else { return }
        mgr?.startUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            startHeading()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        last = locations.last?.coordinate
        publishIfNeeded()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = PersonCompass.liveHeading(
            trueHeading: newHeading.trueHeading,
            magneticHeading: newHeading.magneticHeading,
            accuracy: newHeading.headingAccuracy
        )
        publishIfNeeded()
    }

    private func publishIfNeeded() {
        let now = Date().timeIntervalSince1970
        let coord = last.map { ($0.latitude, $0.longitude) }
        let lastStamp = lastPublish > 0 ? lastPublish : nil
        guard FixPublish.shouldPublish(
            now: now,
            lastPublished: lastStamp,
            heading: heading,
            lastHeading: publishedHeading,
            coord: coord,
            lastCoord: publishedCoord
        ) else { return }
        lastPublish = now
        publishedHeading = heading
        publishedCoord = coord
        onChange?()
    }
}

enum BootStage: Equatable {
    case cold
    case loading(String)
    case ready
    case failed(String)

    var line: String {
        switch self {
        case .cold:
            return ""
        case .loading(let name):
            return name
        case .ready:
            return "READY"
        case .failed(let why):
            return why
        }
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
