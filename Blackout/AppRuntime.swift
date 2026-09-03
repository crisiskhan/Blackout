import Foundation
import Observation
import CoreLocation
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
        fix.arm()
        if let root = Self.resourceRoot() {
            packs = try? PackStore(root: root.appendingPathComponent("Packs"), box: box)
            if let id = UserDefaults.standard.string(forKey: "pack.id") {
                try? packs?.switchTo(id)
            }
        }
        marks = MarkStore.load()
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
        let lat = fix.last?.latitude ?? lastKnownFix?.lat ?? packs?.active?.center.lat
        let lon = fix.last?.longitude ?? lastKnownFix?.lon ?? packs?.active?.center.lon
        guard let lat, let lon else { return }
        marks.append(MapMark(id: UUID().uuidString, lat: lat, lon: lon, label: packs?.active?.name ?? "mark"))
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
        let hasGraph = packs?.packURL("graph.json") != nil
        lockChrome = LockOnChrome.banner(hasGPS: hasGPS, hasGraph: hasGraph)
        sendPOSIfPossible()
    }

    func speakMap() {
        let pack = packs?.active?.name ?? "no pack"
        let bearing = headingDeg.map { String(format: "%.0f degrees", $0) } ?? "no heading"
        if speech.speak("\(pack) \(bearing)", locale: locale) {
            speechChrome = ""
        } else {
            speechChrome = "SPEECH FAILED"
        }
    }

    func beginPTTSolo() {
        ptt.beginLive()
        mesh.sendChip(from: mesh.localID, chip: "ptt")
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
    }

    private func pullFix() {
        headingDeg = fix.heading
        if let c = fix.last {
            lastKnownFix = (c.latitude, c.longitude)
        }
    }

    static func resourceRoot() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Resources")
    }
}

final class MeshFix: NSObject, CLLocationManagerDelegate {
    var last: CLLocationCoordinate2D?
    var heading: Double?
    var onChange: (() -> Void)?
    private let mgr = CLLocationManager()

    func arm() {
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
        mgr.startUpdatingHeading()
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
        onChange?()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueH = newHeading.trueHeading
        heading = trueH >= 0 ? trueH : newHeading.magneticHeading
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
