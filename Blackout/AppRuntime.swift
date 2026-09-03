import Foundation
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
        mesh.airplane = true
        mesh.partyCode = roster.code
        UserDefaults.standard.set(roster.code, forKey: "party.code")
        #if canImport(MultipeerConnectivity)
        if mesh.radio == nil { mesh.attach(LiveMeshRadio()) }
        #endif
        mesh.startLocal()
    }

    func sendPOSIfPossible() {
        if let c = packs?.active?.center {
            mesh.sendPOS(from: roster.code, lat: c.lat, lon: c.lon)
        }
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
