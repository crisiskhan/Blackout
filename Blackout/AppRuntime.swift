import Foundation
import Observation
import CoreLocation
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
        fix.arm()
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
        mesh.airplane = true
        mesh.partyCode = roster.code
        UserDefaults.standard.set(roster.code, forKey: "party.code")
        if mesh.radio == nil { mesh.attach(LiveMeshRadio()) }
        mesh.startLocal()
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
    }

    static func resourceRoot() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Resources")
    }
}

final class MeshFix: NSObject, CLLocationManagerDelegate {
    var last: CLLocationCoordinate2D?
    private let mgr = CLLocationManager()

    func arm() {
        mgr.delegate = self
        switch mgr.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            mgr.startUpdatingLocation()
        case .notDetermined:
            mgr.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        last = locations.last?.coordinate
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
