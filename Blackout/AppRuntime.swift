import Foundation
import Observation
import CoreLocation
import UIKit
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
    var sawCannotDo = false
    var leftHand = false
    var tab: BlackoutTab = .map
    var lockOn = false
    var showInstruments = false
    var locale = "en"
    var lastKnownFix: (lat: Double, lon: Double)?
    var marks: [MapMark] = []
    var headingDeg: Double?
    var lockChrome = ""
    var speechChrome = ""
    var navChrome = ""
    var toolChrome = ""
    var routeCoords: [(lat: Double, lon: Double)] = []
    var routeTarget: (lat: Double, lon: Double)?
    var canRouteOnGraph: Bool { packs?.hasUsableGraph() ?? false }
    var hasRouteDestination: Bool { destination() != nil }
    var walkDriveEnabled: Bool {
        WalkDriveChip.isEnabled(hasUsableGraph: canRouteOnGraph, hasDestination: hasRouteDestination)
    }
    var routeChrome: String {
        WalkDriveChip.chrome(
            hasUsableGraph: canRouteOnGraph,
            hasDestination: hasRouteDestination,
            planChrome: navChrome
        )
    }
    private var graphCache: RouteGraph?
    private var graphPackID: String?
    private var graphWarmup: Task<RouteGraph?, Never>?
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
        if UserDefaults.standard.bool(forKey: "cannotDo.seen") {
            sawCannotDo = true
        }
        warmupActiveGraph()
        applyMapKeepAwake()
    }

    func arm() {
        armed = true
        box.log("arming", "entered tabs")
        applyMapKeepAwake()
    }

    func acknowledgeCannotDo() {
        sawCannotDo = true
        UserDefaults.standard.set(true, forKey: "cannotDo.seen")
    }

    func joinNet() {
        mesh.airplane = true
        mesh.partyCode = roster.code
        persistPartyCode()
        if mesh.radio == nil { mesh.attach(LiveMeshRadio()) }
        mesh.startLocal()
    }

    func persistPartyCode() {
        UserDefaults.standard.set(roster.code, forKey: "party.code")
    }

    func dropMark() {
        fix.arm()
        let lat = fix.last?.latitude ?? lastKnownFix?.lat ?? packs?.active?.center.lat
        let lon = fix.last?.longitude ?? lastKnownFix?.lon ?? packs?.active?.center.lon
        guard let lat, let lon else { return }
        let pack = packs?.active
        let bbox = pack.map { ($0.bbox.south, $0.bbox.west, $0.bbox.north, $0.bbox.east) }
        let label = PackChrome.markLabel(
            lat: lat,
            lon: lon,
            packName: pack?.name ?? "mark",
            bbox: bbox
        )
        marks = MarkDrop.merging(marks, lat: lat, lon: lon, label: label)
        MarkStore.save(marks)
    }

    func toggleLockOn() {
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
        routeTarget = (lat, lon)
        routeCoords = []
        navChrome = ""
        toolChrome = ""
    }

    func navigate(mode: TravelMode) {
        switch mode {
        case .walk, .drive:
            break
        }
        guard walkDriveEnabled, let dest = destination() else {
            clearRoute(chrome: GraphPlan.offGraph)
            return
        }
        routeTarget = dest
        let from = youCoordinate()
        if graphPackID == packs?.active?.id {
            let plan = GraphPlan.line(graph: graphCache, from: from, to: dest, mode: mode)
            routeCoords = plan.coords
            navChrome = plan.chrome
            return
        }
        let id = packs?.active?.id
        let url = packs?.packURL("graph.json")
        let inflight = graphWarmup
        Task { [weak self] in
            let graph: RouteGraph?
            if let inflight {
                graph = await inflight.value
            } else {
                graph = await Task.detached { RouteGraph.load(from: url) }.value
            }
            let plan = GraphPlan.line(graph: graph, from: from, to: dest, mode: mode)
            await MainActor.run {
                guard let self, self.packs?.active?.id == id else { return }
                self.graphCache = graph
                self.graphPackID = id
                self.routeCoords = plan.coords
                self.navChrome = plan.chrome
            }
        }
    }

    func tapRuler() {
        toolChrome = MapRuler.chrome(from: youCoordinate(), to: destination())
    }

    func tapUSNG() {
        let you = youCoordinate()
        toolChrome = USNG.label(lat: you.lat, lon: you.lon)
    }

    func tapMagTrue() {
        instruments.toggleMagTrue()
        toolChrome = MagTrueChip.chrome(magNorth: instruments.state.magNorth)
    }

    func speakMap() {
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
        if speech.speak(text, locale: locale) {
            speechChrome = text
        } else {
            speechChrome = "SPEECH FAILED"
        }
    }

    func beginPTTSolo() {
        ptt.beginLive()
        _ = ptt.recordClip(pcm: Data(repeating: 0, count: 3200), sampleRate: 16_000)
        mesh.sendChip(from: mesh.localID, chip: "ptt")
    }

    func endPTTSolo() {
        ptt.endLive()
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

    func sendPOSIfPossible() {
        fix.arm()
        let pack = packs?.active?.center
        let lat = fix.last?.latitude ?? lastKnownFix?.lat ?? pack?.lat
        let lon = fix.last?.longitude ?? lastKnownFix?.lon ?? pack?.lon
        guard let lat, let lon else { return }
        lastKnownFix = (lat, lon)
        mesh.sendPOS(from: mesh.localID, lat: lat, lon: lon)
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
            if let raw = String(data: env.body, encoding: .utf8), let chip = Chip(rawValue: raw) {
                comms.chips.append(chip)
            }
        default:
            break
        }
    }

    func switchPack(_ id: String) {
        try? packs?.switchTo(id)
        UserDefaults.standard.set(id, forKey: "pack.id")
        graphCache = nil
        graphPackID = nil
        graphWarmup = nil
        clearRoute(chrome: "")
        relabelMarksForActivePack()
        warmupActiveGraph()
    }

    func applyMapKeepAwake() {
        UIApplication.shared.isIdleTimerDisabled = MapKeepAwake.idleTimerDisabled(
            mapInstrumentActive: armed && tab == .map
        )
    }

    private func youCoordinate() -> (lat: Double, lon: Double) {
        let pack = packs?.active
        return UserPuck.coordinate(
            lastKnown: lastKnownFix,
            packCenter: (pack?.center.lat ?? 0, pack?.center.lon ?? 0),
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

    private func warmupActiveGraph() {
        let id = packs?.active?.id
        let url = packs?.packURL("graph.json")
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

    private func clearRoute(chrome: String) {
        routeCoords = []
        navChrome = chrome
    }

    private func relabelMarksForActivePack() {
        guard let pack = packs?.active else { return }
        let bbox = (pack.bbox.south, pack.bbox.west, pack.bbox.north, pack.bbox.east)
        marks = marks.map { m in
            MapMark(
                id: m.id,
                lat: m.lat,
                lon: m.lon,
                label: PackChrome.markLabel(lat: m.lat, lon: m.lon, packName: pack.name, bbox: bbox)
            )
        }
        MarkStore.save(marks)
    }

    private func pullFix() {
        headingDeg = fix.heading
        if let c = fix.last {
            lastKnownFix = (c.latitude, c.longitude)
        }
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
        let trueH = newHeading.trueHeading
        heading = trueH >= 0 ? trueH : newHeading.magneticHeading
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
