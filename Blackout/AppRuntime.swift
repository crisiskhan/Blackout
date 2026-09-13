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
import Search
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
    var lastConditionSOS = ""
    var red: RedPlate
    var timers: TimerBoard
    var timerSeq = 0
    var kitSeq = 0
    var roster = PartyRoster.create(lead: "Lead")
    var trip = TripFactory.make(brief: "", hours: 2)
    var kit = KitBag(items: [
        GearItem(id: "water", name: "Water", working: true, count: 0),
    ])
    var power: AuctionBoard
    var night = NightRedState(enabled: false)
    var lamp: HUDLamp = .off
    var instruments: InstrumentBoard
    var comms = CommsState()
    var ptt: PTTDeck
    var speech: SpeechEngine
    var armed = false
    /// Live Morse beat. Screen veil reads this; the LED follows the same edge.
    var sosFlashLit = false
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
    /// Packed name index for SEARCH and named SPEAK streets.
    var searchIndex: SearchIndex?
    /// HUD words for the glass TURNS plate. Empty until SPEAK has a line.
    var speakHUDTurns: [String] = []
    /// Dest-rail next street. Empty when the line is straight in.
    var speakNextHUD = ""
    /// Glass TURNS plate after SPEAK. Not a paragraph over the canvas.
    var showSpeakTurns = false
    /// The inspect card the map is holding open. `nil` whenever it is clear.
    var held: HeldPoint?
    /// A person mark the map is holding open. Mutually exclusive with `held`.
    var heldParty: HeldPerson?
    /// A packed door the search book interpolated. Mutually exclusive with ground and party.
    var heldAddress: HeldAddress?
    /// Party place composer. NAME / NOTE / FACE live here until DROP.
    var markDraft: MapMarkDraft?
    /// Planted place the thumb is holding. Mutually exclusive with ground and party.
    var heldMark: MapMark?
    /// FACE glass over the YOU profile. Never on a peer card.
    var pickingEmblem = false
    /// Chosen name on YOU. Empty is still YOU on the card.
    var youName = ""
    var youStatus: PartyStatus = .good
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
    /// NOTE field should open after MESSAGE from a profile glass.
    var pendingNoteFocus = false
    /// One live inbound CALL or MESSAGE. Newest replaces.
    var incoming: IncomingLine?
    /// 15s CLIP is armed. The pad reads RECORDING until the clip ends.
    var clipLive = false
    /// HUD typewriter. Replaces the iPhone keyboard on every field.
    var hudKeys = HUDKeyboardGate()
    /// Machine plan state for VoiceNav: "" on graph, `GraphPlan.offGraph` otherwise.
    var navChrome = ""
    /// What the map says after a WALK/DRIVE tap: the route, or why there isn't one.
    var routeChrome = ""
    var toolChrome = ""
    var routeCoords: [(lat: Double, lon: Double)] = []
    var routeTarget: (lat: Double, lon: Double)?
    /// Last WALK or DRIVE tap. The canvas dashes the core for a walk.
    var travelMode: TravelMode = .walk
    /// Spoken live-turn cue already played for this plot. Empty until a turn is close.
    private var liveSpokenTurn = ""
    private var liveArrived = false
    private var lastLiveRerouteAt: TimeInterval = 0
    /// Bumped by FIT PACK. The canvas otherwise opens on YOU at walking zoom.
    var fitPackToken = 0
    var canRouteOnGraph: Bool { packs?.hasUsableGraph() ?? false }
    /// Last WALK or DRIVE tap. Drops a stale plot so it cannot speak over a newer one.
    private var navSeq = 0
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
    private var incomingTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?
    private var savedBrightness: CGFloat?
    private var brightnessLock: NSObjectProtocol?
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
        instruments.setVoice(NavVoice.parse(UserDefaults.standard.string(forKey: "nav.voice")))
        applySpeechTone()
        fix.applyInstrument(instruments.state)
        if let saved = UserDefaults.standard.string(forKey: "party.code"), !saved.isEmpty {
            roster = roster.setting(code: saved)
        }
        mesh.partyCode = roster.code
        youEmblem = PersonEmblem.load()
        youName = MeshPOS.nameToken(UserDefaults.standard.string(forKey: "you.name") ?? "")
        youStatus = PartyStatus.parse(UserDefaults.standard.string(forKey: "you.status"))
        if let raw = UserDefaults.standard.string(forKey: "hud.lamp"),
           let saved = HUDLamp(rawValue: raw)
        {
            lamp = saved
            night.enabled = saved.nightOn
        }
        mesh.onInbound = { [weak self] env in
            Task { @MainActor in self?.applyInbound(env) }
        }
        mesh.onPeersChanged = { [weak self] in
            Task { @MainActor in
                self?.sendPOSIfPossible()
                self?.sendRosterSeat()
            }
        }
        mesh.startLocal()
        roster = roster.rebindingLead(to: mesh.localID, name: displayYouName)
        if let raw = UserDefaults.standard.string(forKey: "you.role"),
           let role = PartyRole.parse(raw)
        {
            roster = roster.seating(id: mesh.localID, name: displayYouName, role: role)
        }
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
        fix.arm()
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
        clearIncoming()
    }

    func persistPartyCode() {
        UserDefaults.standard.set(roster.code, forKey: "party.code")
    }

    var displayYouName: String {
        let named = youName.trimmingCharacters(in: .whitespacesAndNewlines)
        return named.isEmpty ? "YOU" : named
    }

    var liveRoster: [LiveRosterRow] {
        roster.live(
            youID: mesh.localID,
            youName: youName,
            youEmblem: youEmblem.rawValue,
            youStatusTitle: youStatus.title,
            peers: mesh.pips.compactMap { pip in
                guard pip.from != mesh.localID else { return nil }
                let named = MeshPOS.nameToken(pip.name ?? "")
                return RosterPeer(
                    id: pip.from,
                    name: named.isEmpty ? pip.from.uppercased() : named,
                    emblem: pip.emblem ?? "",
                    statusTitle: PartyStatus.parse(pip.status).title
                )
            }
        )
    }

    func paperRoster() -> PartyRoster {
        PartyRoster(
            code: roster.code,
            members: liveRoster.map { PartyMember(id: $0.id, name: $0.name, role: $0.role) }
        )
    }

    func seatNav() -> String? {
        seat(id: mesh.localID, name: displayYouName, role: .nav)
    }

    func cycleSeat(_ id: String) -> String? {
        let rows = liveRoster
        let name = rows.first(where: { $0.id == id })?.name ?? displayYouName
        let before = roster
        roster = roster.cycling(id: id, name: name, from: rows)
        if roster == before {
            let role = rows.first(where: { $0.id == id })?.role ?? .lead
            return "\(role.title) · SEATED"
        }
        let role = roster.members.first(where: { $0.id == id })?.role ?? .lead
        if id == mesh.localID {
            UserDefaults.standard.set(role.rawValue, forKey: "you.role")
        }
        sendRosterSeat(id: id, name: name, role: role)
        return nil
    }

    func seat(id: String, name: String, role: PartyRole) -> String? {
        let before = roster
        roster = roster.seating(id: id, name: name, role: role)
        if roster == before {
            return "\(role.title) · SEATED"
        }
        if id == mesh.localID {
            UserDefaults.standard.set(role.rawValue, forKey: "you.role")
        }
        sendRosterSeat(id: id, name: name, role: role)
        return nil
    }

    func sendRosterSeat() {
        let row = liveRoster.first { $0.id == mesh.localID }
        sendRosterSeat(id: mesh.localID, name: displayYouName, role: row?.role ?? .lead)
    }

    func sendRosterSeat(id: String, name: String, role: PartyRole) {
        mesh.sendRoster(from: mesh.localID, id: id, role: role.rawValue, name: name)
    }

    func tapLamp(_ tap: HUDLamp) {
        lamp = HUDLamp.toggling(current: lamp, tap: tap)
        night.enabled = lamp.nightOn
        applyLampChrome()
        pulse()
    }

    func applyLampChrome() {
        Theme.bind(lamp)
        UserDefaults.standard.set(lamp.rawValue, forKey: "hud.lamp")
        switch lamp {
        case .sun:
            if savedBrightness == nil {
                savedBrightness = UIScreen.main.brightness
            }
            UIScreen.main.brightness = 1
            if brightnessLock == nil {
                brightnessLock = NotificationCenter.default.addObserver(
                    forName: UIScreen.brightnessDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.lamp == .sun else { return }
                        if UIScreen.main.brightness < 0.999 {
                            UIScreen.main.brightness = 1
                        }
                    }
                }
            }
        case .off, .night:
            if let lock = brightnessLock {
                NotificationCenter.default.removeObserver(lock)
                brightnessLock = nil
            }
            if let saved = savedBrightness {
                UIScreen.main.brightness = saved
                savedBrightness = nil
            }
        }
    }

    func pickEmblem(_ emblem: PersonEmblem) {
        youEmblem = emblem
        PersonEmblem.save(emblem)
        if heldParty?.isYou == true {
            heldParty?.emblem = emblem.rawValue
        }
        sendPOSIfPossible()
    }

    func openEmblemPick() {
        guard heldParty?.isYou == true else { return }
        pickingEmblem = true
        pulse()
    }

    func closeEmblemPick() {
        pickingEmblem = false
        pulse()
    }

    func dropMark() {
        pulse()
        guard let dest = routeTarget else {
            routeChrome = PlaceMark.setDest
            return
        }
        openMark(lat: dest.lat, lon: dest.lon)
    }

    /// A mark on a place the thumb chose rather than on the fix. `name` is the
    /// record's own name when it has one; it fills NAME on the composer.
    func dropMark(lat: Double, lon: Double, name: String? = nil) {
        openMark(lat: lat, lon: lon, name: name)
    }

    func openMark(lat: Double, lon: Double, name: String? = nil) {
        guard lat.isFinite, lon.isFinite else { return }
        hudKeys.close()
        pickingEmblem = false
        closeSpeakTurns()
        held = nil
        heldParty = nil
        heldAddress = nil
        let pref = MeshMarkBody.clean(name ?? "")
        let unnamed = pref.isEmpty || pref == Inspect.unnamed
        if let existing = marks.first(where: { MarkDrop.sameCoord(($0.lat, $0.lon), (lat, lon)) }) {
            heldMark = existing
            let named = existing.name.isEmpty && !unnamed ? pref : existing.name
            markDraft = MapMarkDraft(
                lat: existing.lat,
                lon: existing.lon,
                name: named,
                note: existing.note,
                emblem: existing.emblem,
                existingID: existing.id
            )
            pulse()
            return
        }
        heldMark = nil
        markDraft = MapMarkDraft(
            lat: lat,
            lon: lon,
            name: unnamed ? "" : pref,
            note: "",
            emblem: PersonEmblem.fallback.rawValue,
            existingID: nil
        )
        pulse()
    }

    /// Same coord stays one pin. MarkDrop.merging is insert-only; DROP uses upsert.
    func commitMark() {
        guard let draft = markDraft else { return }
        guard draft.lat.isFinite, draft.lon.isFinite else { return }
        let pack = packs?.active
        let bbox = pack.map { ($0.bbox.south, $0.bbox.west, $0.bbox.north, $0.bbox.east) }
        let coords = PackChrome.markLabel(
            lat: draft.lat,
            lon: draft.lon,
            packName: pack?.name ?? "mark",
            bbox: bbox
        )
        let named = MeshMarkBody.clean(draft.name)
        let note = MeshMarkBody.clean(draft.note)
        let label = named.isEmpty || named == Inspect.unnamed ? coords : "\(named) · \(coords)"
        let emblem = PersonEmblem.resolved(draft.emblem).rawValue
        let existing = marks.first {
            $0.id == draft.existingID || MarkDrop.sameCoord(($0.lat, $0.lon), (draft.lat, draft.lon))
        }
        let mark = MapMark(
            id: existing?.id ?? draft.existingID ?? UUID().uuidString,
            lat: draft.lat,
            lon: draft.lon,
            label: label,
            name: named == Inspect.unnamed ? "" : named,
            note: note,
            emblem: emblem,
            from: mesh.localID
        )
        marks = MarkDrop.upsert(marks, mark: mark)
        MarkStore.save(marks)
        mesh.sendMark(
            from: mesh.localID,
            id: mark.id,
            lat: mark.lat,
            lon: mark.lon,
            name: mark.name,
            note: mark.note,
            emblem: mark.emblem,
            label: mark.label
        )
        closeMark()
    }

    func closeMark() {
        markDraft = nil
        heldMark = nil
        hudKeys.close()
        pulse()
    }

    func holdPlaceMark(_ mark: MapMark) {
        hudKeys.close()
        pickingEmblem = false
        closeSpeakTurns()
        held = nil
        heldParty = nil
        heldAddress = nil
        heldMark = mark
        markDraft = MapMarkDraft(
            lat: mark.lat,
            lon: mark.lon,
            name: mark.name,
            note: mark.note,
            emblem: mark.emblem,
            existingID: mark.id
        )
        pulse()
    }

    // MARK: - Hold to inspect

    /// A thumb stayed put long enough to mean it. Read the record under it and
    /// raise the card. This never calls SOS and never routes anywhere; it only
    /// says what is there.
    func holdInspect(lat: Double, lon: Double, tags: [String: String], zoom: Double) {
        guard lat.isFinite, lon.isFinite else { return }
        pulse()
        pickingEmblem = false
        closeSpeakTurns()
        markDraft = nil
        heldMark = nil
        heldParty = nil
        heldAddress = nil
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
            marked: marks.contains { MarkDrop.sameCoord(($0.lat, $0.lon), (lat, lon)) }
        )
    }

    func closeHold() {
        held = nil
        heldParty = nil
        heldAddress = nil
        pickingEmblem = false
        pulse()
    }

    func holdAddress(_ hit: SearchHit) {
        guard hit.lat.isFinite, hit.lon.isFinite else { return }
        pulse()
        pickingEmblem = false
        closeSpeakTurns()
        markDraft = nil
        heldMark = nil
        held = nil
        heldParty = nil
        let what = hit.what.trimmingCharacters(in: .whitespacesAndNewlines)
        heldAddress = HeldAddress(
            name: hit.name,
            city: hit.city,
            post: hit.post,
            what: what.isEmpty ? "door on the street" : what,
            sure: hit.sure == 0 ? 72 : hit.sure,
            why: hit.why,
            lat: hit.lat,
            lon: hit.lon,
            marked: marks.contains { MarkDrop.sameCoord(($0.lat, $0.lon), (hit.lat, hit.lon)) }
        )
    }

    func walkHeldAddress() {
        guard let address = heldAddress else { return }
        pickDestination(lat: address.lat, lon: address.lon)
        Task { @MainActor in
            closeHold()
            navigate(mode: .walk)
        }
    }

    func markHeldAddress() {
        guard let address = heldAddress, !address.marked else { return }
        pickDestination(lat: address.lat, lon: address.lon)
        openMark(lat: address.lat, lon: address.lon, name: address.name)
    }

    func addressCourse(lat: Double, lon: Double) -> String {
        let you = youCoordinate()
        let deg = VoiceNav.bearing(from: you, to: (lat, lon))
        return String(format: "%.0f°", deg)
    }

    func addressFix(lat: Double, lon: Double) -> String {
        MapFieldChrome.destValue(point: (lat, lon))
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

    func holdParty(id: String, lat: Double, lon: Double) {
        guard lat.isFinite, lon.isFinite else { return }
        if let markID = PlaceMark.parse(id) {
            if let mark = marks.first(where: { $0.id == markID }) {
                holdPlaceMark(mark)
            }
            return
        }
        pulse()
        pickingEmblem = false
        closeSpeakTurns()
        markDraft = nil
        heldMark = nil
        held = nil
        heldAddress = nil
        if id == UserPuck.title {
            let you = youCoordinate()
            heldParty = HeldPerson(
                id: id,
                name: youName,
                emblem: youEmblem.rawValue,
                status: youStatus,
                lat: you.lat,
                lon: you.lon,
                headingDeg: headingDeg,
                isYou: true,
                vitals: vitals
            )
            return
        }
        let pip = mesh.pips.first { $0.from == id }
        let plat = pip?.lat ?? lat
        let plon = pip?.lon ?? lon
        guard plat.isFinite, plon.isFinite else { return }
        heldParty = HeldPerson(
            id: id,
            name: MeshPOS.nameToken(pip?.name ?? ""),
            emblem: pip?.emblem ?? PersonEmblem.fallback.rawValue,
            status: PartyStatus.parse(pip?.status),
            lat: plat,
            lon: plon,
            headingDeg: pip?.headingDeg,
            isYou: false,
            vitals: PartyVitals.fromPOS(pip?.vitals)
        )
    }

    func setYouName(_ raw: String) {
        youName = MeshPOS.nameToken(raw)
        UserDefaults.standard.set(youName, forKey: "you.name")
        if heldParty?.isYou == true {
            heldParty?.name = youName
        }
        let role = liveRoster.first(where: { $0.id == mesh.localID })?.role ?? .lead
        roster = roster.seating(id: mesh.localID, name: displayYouName, role: role)
        sendPOSIfPossible()
    }

    func setYouStatus(_ status: PartyStatus) {
        youStatus = status
        UserDefaults.standard.set(status.rawValue, forKey: "you.status")
        if heldParty?.isYou == true {
            heldParty?.status = status
        }
        sendPOSIfPossible()
    }

    func setYouVitals(_ next: PartyVitals) {
        let gained = Set(next.blackTitles).subtracting(vitals.blackTitles)
        vitals = next
        if heldParty?.isYou == true {
            heldParty?.vitals = next
        }
        sendPOSIfPossible()
        if !gained.isEmpty {
            offerConditionSOS()
        }
    }

    func setYouRail(_ key: WritableKeyPath<PartyVitals, Double>, _ value: Double) {
        var next = vitals
        next[keyPath: key] = PartyVitals.snap(value)
        setYouVitals(next)
    }

    func callHeldParty() {
        guard let person = heldParty else { return }
        if person.isYou {
            comms.pickPeer("YOU")
        } else {
            comms.pickPeer(person.id)
        }
        Task { @MainActor in
            tab = .comms
            closeHold()
            applyMapKeepAwake()
            if person.isYou || mesh.nearby.isEmpty {
                mesh.sendChip(from: mesh.localID, chip: "ptt", to: meshDest)
            } else {
                beginPTTSolo()
            }
        }
    }

    func messageHeldParty() {
        guard let person = heldParty else { return }
        if person.isYou {
            comms.pickPeer("YOU")
        } else {
            comms.pickPeer(person.id)
        }
        pendingNoteFocus = true
        Task { @MainActor in
            tab = .comms
            closeHold()
            applyMapKeepAwake()
        }
    }

    func sendPartyNote(_ raw: String) {
        let text = PartyNote.clean(raw)
        guard !text.isEmpty else { return }
        mesh.sendNote(from: mesh.localID, text: text, to: meshDest)
    }

    func partyCourse(for person: HeldPerson) -> String {
        if person.isYou {
            if let headingDeg, headingDeg >= 0 {
                return String(format: "%.0f°", headingDeg)
            }
            return "NO HEADING"
        }
        let you = youCoordinate()
        let deg = VoiceNav.bearing(from: you, to: (person.lat, person.lon))
        return String(format: "%.0f°", deg)
    }

    func partyFix(_ person: HeldPerson) -> String {
        MapFieldChrome.destValue(point: (person.lat, person.lon))
    }

    private func refreshHeldParty() {
        guard let card = heldParty else { return }
        if card.isYou {
            let you = youCoordinate()
            heldParty?.lat = you.lat
            heldParty?.lon = you.lon
            heldParty?.headingDeg = headingDeg
            heldParty?.name = youName
            heldParty?.status = youStatus
            heldParty?.emblem = youEmblem.rawValue
            heldParty?.vitals = vitals
            return
        }
        guard let pip = mesh.pips.first(where: { $0.from == card.id }) else { return }
        guard pip.lat.isFinite, pip.lon.isFinite else { return }
        heldParty?.lat = pip.lat
        heldParty?.lon = pip.lon
        heldParty?.headingDeg = pip.headingDeg
        heldParty?.emblem = pip.emblem ?? card.emblem
        heldParty?.name = MeshPOS.nameToken(pip.name ?? "")
        heldParty?.status = PartyStatus.parse(pip.status)
        heldParty?.vitals = PartyVitals.fromPOS(pip.vitals)
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
        guard lat.isFinite, lon.isFinite else { return }
        pulse()
        routeTarget = (lat, lon)
        // A new destination invalidates everything the old one produced.
        routeCoords = []
        navChrome = ""
        routeChrome = ""
        toolChrome = ""
        speechChrome = ""
        clearSpeakTurns()
        resetLiveGuide()
    }

    func navigate(mode: TravelMode) {
        touch(.dock)
        speechChrome = ""
        travelMode = mode
        liveSpokenTurn = ""
        liveArrived = false
        clearSpeakTurns()
        navSeq += 1
        let seq = navSeq
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
            speakMap()
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
                guard let self, self.packs?.active?.id == id, self.navSeq == seq else { return }
                self.graphCache = graph
                self.graphPackID = id
                self.routeCoords = plan.coords
                self.navChrome = plan.chrome
                self.routeChrome = RouteLine.shouldDraw(plan.coords)
                    ? RouteSummary.chrome(mode: mode, coords: plan.coords, seconds: plan.seconds)
                    : RouteBlock.noPath.chrome(mode: mode, packName: packName)
                self.speakMap()
            }
        }
    }

    func fitPack() {
        fitPackToken += 1
    }

    func tapRuler() {
        fix.arm()
        toolChrome = MapRuler.chrome(from: gnssYou, to: routeTarget)
        showInstruments = false
    }

    func tapUSNG() {
        fix.arm()
        let you = gnssYou
        toolChrome = USNG.label(lat: you?.lat ?? .nan, lon: you?.lon ?? .nan)
        showInstruments = false
    }

    func tapMagTrue() {
        fix.arm()
        instruments.toggleMagTrue()
        applyInstrumentBoard()
        toolChrome = MagTrueChip.chrome(magNorth: instruments.state.magNorth)
        showInstruments = false
    }

    func setTrueNorth() {
        fix.arm()
        instruments.setTrueNorth()
        applyInstrumentBoard()
        toolChrome = MagTrueChip.chrome(magNorth: instruments.state.magNorth)
    }

    func calibrateCompass() {
        fix.arm()
        instruments.calibrateCompass()
        fix.requestHeadingCalibration()
    }

    func attachUSB_C_PTT(_ present: Bool) {
        instruments.attachUSB_C_PTT(present)
        PTTMic.shared.preferWiredPTT(present)
    }

    func attachGNSSPuck(_ present: Bool) {
        instruments.attachGNSSPuck(present)
        fix.arm()
        applyInstrumentBoard()
    }

    var torchAvailable: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch == true
    }

    private func applyInstrumentBoard() {
        fix.applyInstrument(instruments.state)
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
            if hudCrisis || incoming != nil || hudLayoutMode || held != nil || heldParty != nil || heldAddress != nil || markDraft != nil || heldMark != nil { return }
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

    /// BLACK CONDITION tick. Mesh-wide note with condition, coordinates, and
    /// bearing. Same radio as hold SOS. Not a phone call.
    func offerConditionSOS() {
        offerSOS()
        let pack = packs?.active?.center
        let lat = fix.last?.latitude ?? lastKnownFix?.lat ?? pack?.lat
        let lon = fix.last?.longitude ?? lastKnownFix?.lon ?? pack?.lon
        let coordinates: String
        if let lat, let lon, lat.isFinite, lon.isFinite {
            coordinates = MapFieldChrome.destValue(point: (lat, lon))
        } else {
            coordinates = MapFieldChrome.destValue(point: nil)
        }
        let bearing: String
        if let headingDeg, headingDeg >= 0 {
            bearing = String(format: "%.0f°", headingDeg)
        } else {
            bearing = "NO HEADING"
        }
        let line = PartyNote.clean(
            vitals.partyAlertLine(coordinates: coordinates, bearing: bearing)
        )
        guard !line.isEmpty else { return }
        lastConditionSOS = line
        mesh.sendNote(from: mesh.localID, text: line, to: "*")
        box.log("sos", line)
    }

    /// I AM OK is the all-clear: the mesh hears it, the SOS chip goes dark,
    /// and a RED plate we lit goes dark.
    func iamOK() {
        lastConditionSOS = ""
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
        let streets = searchIndex?.streetNames(along: routeCoords) ?? []
        let text = VoiceNav.prompt(
            packName: pack,
            headingDeg: headingDeg,
            routeCoords: routeCoords,
            planChrome: navChrome,
            destination: destination(),
            you: youCoordinate(),
            locale: locale,
            travelMode: travelMode,
            streets: streets
        )
        // The whole turn-by-turn script goes to the voice. The field only gets one short
        // status line — the route itself is already drawn in silver. Named streets live
        // on the TURNS plate and the dest rail, never as a spoken paragraph on the canvas.
        applySpeechTone()
        let spoke = speech.speak(text, locale: locale)
        speechChrome = SpeakStatus.chrome(
            spoke: spoke,
            routeCoords: routeCoords,
            planChrome: navChrome,
            destination: destination(),
            you: youCoordinate()
        )
        if spoke, routeCoords.count >= 2 {
            speakHUDTurns = VoiceNav.hudTurns(routeCoords, travelMode: travelMode, streets: streets)
            speakNextHUD = VoiceNav.nextTurnHUD(routeCoords, streets: streets)
            showSpeakTurns = !speakHUDTurns.isEmpty
        } else {
            clearSpeakTurns()
        }
    }

    func closeSpeakTurns() {
        showSpeakTurns = false
    }

    private func clearSpeakTurns() {
        speakHUDTurns = []
        speakNextHUD = ""
        showSpeakTurns = false
    }

    func setNavVoice(_ voice: NavVoice) {
        instruments.setVoice(voice)
        UserDefaults.standard.set(voice.rawValue, forKey: "nav.voice")
        applySpeechTone()
    }

    func applySpeechTone() {
        let voice = instruments.state.voice
        speech.setTone(
            SpeechTone(
                identifier: voice.identifier(locale: locale),
                rate: voice.rate,
                pitch: voice.pitch,
                preDelay: voice.preDelay,
                postDelay: voice.postDelay
            )
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
        let dest = comms.peer == "YOU" || mesh.nearby.isEmpty ? "YOU" : meshDest
        mesh.sendChip(from: mesh.localID, chip: "radio", to: dest)
    }

    func sendPartyChip(_ chip: Chip) {
        comms.push(chip)
        mesh.sendChip(from: mesh.localID, chip: chip.rawValue, to: meshDest)
    }

    func tapSOSFlashlight() {
        instruments.sosFlashTap()
        if instruments.state.sosFlash {
            startSOSFlash()
        } else {
            stopSOSFlash()
        }
        applyMapKeepAwake()
    }

    func haltSOSFlash() {
        instruments.setSOSFlash(false)
        stopSOSFlash()
        applyMapKeepAwake()
    }

    private func startSOSFlash() {
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            while !Task.isCancelled, instruments.state.sosFlash {
                for (on, units) in SOSFlash.cycleUnits {
                    if Task.isCancelled || !instruments.state.sosFlash { return }
                    sosFlashLit = on
                    applyTorchLamp(on: on)
                    let ns = UInt64(SOSFlash.unitMs) * UInt64(units) * 1_000_000
                    try? await Task.sleep(nanoseconds: ns)
                }
            }
        }
    }

    private func stopSOSFlash() {
        flashTask?.cancel()
        flashTask = nil
        sosFlashLit = false
        applyTorchLamp(on: false)
    }

    private func applyTorchLamp(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on, device.isTorchModeSupported(.on) {
                try device.setTorchModeOn(level: 1)
            } else {
                device.torchMode = .off
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

    func timerOwner() -> String {
        let named = youName.trimmingCharacters(in: .whitespacesAndNewlines)
        return named.isEmpty ? "YOU" : named
    }

    func addPartyTimer(task: String, duration: TimeInterval) {
        guard duration.isFinite, duration > 0 else { return }
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? TimerDuration.label(duration) : trimmed
        let who = trimmed.isEmpty ? "ALL" : timerOwner()
        if timers.add(who: who, task: name, duration: duration, subjectAll: true, owner: timerOwner()) != nil {
            mesh.sendTimer(from: mesh.localID, task: name, done: false, duration: duration)
            timerSeq += 1
        }
    }

    func finishPartyTimer(_ id: String, task: String) {
        timers.markDone(id)
        mesh.sendTimer(from: mesh.localID, task: task, done: true)
        timerSeq += 1
    }

    func bumpKit(_ id: String, by: Int) {
        kit.bump(id, by: by)
        sendKitItem(id)
        kitSeq += 1
    }

    func syncKit(_ id: String) {
        sendKitItem(id)
        kitSeq += 1
    }

    func assignKitItem(_ id: String, to: String) {
        kit.assign(id, to: to)
        sendKitItem(id)
        kitSeq += 1
    }

    func addKitItem(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        kit.addNamed(trimmed)
        if let item = kit.items.last, item.name == trimmed {
            sendKitMesh(item)
            kitSeq += 1
        }
    }

    private func sendKitItem(_ id: String) {
        guard let item = kit.items.first(where: { $0.id == id }) else { return }
        sendKitMesh(item)
    }

    private func sendKitMesh(_ item: GearItem) {
        mesh.sendKit(
            from: mesh.localID,
            itemID: item.id,
            name: item.name,
            count: item.count,
            assignedTo: item.assignedTo ?? "",
            working: item.working
        )
    }

    private func applyKitMesh(
        _ parsed: (id: String, name: String, count: Int, assignedTo: String, working: Bool)
    ) {
        kit.upsert(
            GearItem(
                id: parsed.id,
                name: parsed.name,
                working: parsed.working,
                count: parsed.count,
                assignedTo: parsed.assignedTo.isEmpty ? nil : parsed.assignedTo
            )
        )
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
        guard let lat, let lon, lat.isFinite, lon.isFinite else { return }
        lastKnownFix = (lat, lon)
        mesh.sendPOS(
            from: mesh.localID,
            lat: lat,
            lon: lon,
            headingDeg: headingDeg,
            emblem: youEmblem.rawValue,
            name: youName,
            status: youStatus.rawValue,
            vitals: vitals.posRails
        )
    }

    func applyInbound(_ env: MeshEnvelope) {
        switch env.kind {
        case "red":
            red.force(String(data: env.body, encoding: .utf8) == "on")
        case "timer.set":
            if let raw = String(data: env.body, encoding: .utf8) {
                let parsed = MeshTimerBody.parse(raw)
                _ = timers.add(
                    who: env.from,
                    task: parsed.task,
                    duration: parsed.duration,
                    subjectAll: true,
                    owner: env.from
                )
                timerSeq += 1
            }
        case "timer.done":
            if let raw = String(data: env.body, encoding: .utf8) {
                let parsed = MeshTimerBody.parse(raw)
                timers.markDoneTask(parsed.task)
                timerSeq += 1
            }
        case "kit":
            if let raw = String(data: env.body, encoding: .utf8),
               let parsed = MeshKitBody.parse(raw) {
                applyKitMesh(parsed)
                kitSeq += 1
            }
        case "chip":
            if let raw = String(data: env.body, encoding: .utf8) {
                if raw == Chip.sos.rawValue {
                    red.force(true)
                }
                if let chip = Chip(rawValue: raw) {
                    comms.push(chip)
                }
                if raw == "ptt" || (raw == "radio" && (env.to == "YOU" || env.to == mesh.localID)) {
                    raiseIncoming(from: env, kind: .call)
                }
            }
        case "mark":
            if let raw = String(data: env.body, encoding: .utf8),
               let parsed = MeshMarkBody.parse(raw),
               parsed.lat.isFinite,
               parsed.lon.isFinite {
                let pack = packs?.active
                let bbox = pack.map { ($0.bbox.south, $0.bbox.west, $0.bbox.north, $0.bbox.east) }
                let fallback = PackChrome.markLabel(
                    lat: parsed.lat,
                    lon: parsed.lon,
                    packName: pack?.name ?? "mark",
                    bbox: bbox
                )
                let mark = MapMark(
                    id: parsed.id.isEmpty ? UUID().uuidString : parsed.id,
                    lat: parsed.lat,
                    lon: parsed.lon,
                    label: parsed.label.isEmpty ? fallback : parsed.label,
                    name: parsed.name,
                    note: parsed.note,
                    emblem: PersonEmblem.resolved(parsed.emblem).rawValue,
                    from: env.from
                )
                marks = MarkDrop.upsert(marks, mark: mark)
                MarkStore.save(marks)
            }
        case "voice":
            if let pcm = OpusLite.decode(env.body) {
                PTTMic.shared.play(pcm)
            }
        case "pos":
            refreshHeldParty()
        case "roster":
            if let raw = String(data: env.body, encoding: .utf8),
               let parsed = MeshRosterBody.parse(raw),
               let role = PartyRole.parse(parsed.role)
            {
                let beforeYou = roster.members.first(where: { $0.id == mesh.localID })?.role
                roster = roster.upserting(id: parsed.id, name: parsed.name, role: role)
                if let youRole = roster.members.first(where: { $0.id == mesh.localID })?.role {
                    UserDefaults.standard.set(youRole.rawValue, forKey: "you.role")
                }
                if parsed.id != mesh.localID, beforeYou != roster.members.first(where: { $0.id == mesh.localID })?.role {
                    sendRosterSeat()
                }
            }
        case "note":
            if let text = String(data: env.body, encoding: .utf8) {
                let note = PartyNote.clean(text)
                if note.hasPrefix("SOS ") {
                    lastConditionSOS = note
                } else if !note.isEmpty {
                    raiseIncoming(from: env, kind: .message)
                }
            }
        default:
            break
        }
    }

    func raiseIncoming(from env: MeshEnvelope, kind: IncomingKind) {
        guard incomingIsForLocal(env) else { return }
        let selfLine = env.from == mesh.localID
        let pip = mesh.pips.first { $0.from == env.from }
        let name: String
        let emblem: String
        let location: String
        let from: String
        if selfLine {
            name = displayYouName.uppercased()
            emblem = youEmblem.rawValue
            if let you = gnssYou, you.lat.isFinite, you.lon.isFinite {
                location = MapFieldChrome.destValue(point: (you.lat, you.lon))
            } else {
                // NO FIX when YOU has no usable GNSS.
                location = MapFieldChrome.destValue(point: nil)
            }
            from = "YOU"
        } else {
            let named = MeshPOS.nameToken(pip?.name ?? "")
            name = named.isEmpty ? env.from.uppercased() : named.uppercased()
            emblem = pip?.emblem ?? ""
            if let pip, pip.lat.isFinite, pip.lon.isFinite {
                location = MapFieldChrome.destValue(point: (pip.lat, pip.lon))
            } else {
                // NO FIX when the pip has no usable coordinate.
                location = MapFieldChrome.destValue(point: nil)
            }
            from = env.from
        }
        incoming = IncomingLine(
            from: from,
            name: name,
            emblem: emblem,
            location: location,
            kind: kind,
            raisedAt: Date()
        )
        pulse()
        let stamp = incoming?.raisedAt
        incomingTask?.cancel()
        incomingTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(BlackoutTokens.Chrome.incomingLineSeconds))
            if Task.isCancelled { return }
            if incoming?.raisedAt == stamp {
                clearIncoming()
            }
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    func answerIncoming() {
        guard let line = incoming else { return }
        let selfLine = line.from == "YOU" || line.from == mesh.localID
        if selfLine {
            comms.pickPeer("YOU")
        } else {
            comms.pickPeer(line.from)
        }
        switch line.kind {
        case .call:
            break
        case .message:
            pendingNoteFocus = true
        }
        clearIncoming()
        Task { @MainActor in
            tab = .comms
            closeHold()
            applyMapKeepAwake()
            switch line.kind {
            case .call:
                if selfLine || mesh.nearby.contains(line.from) {
                    beginPTTSolo()
                }
            case .message:
                break
            }
        }
    }

    func clearIncoming() {
        incomingTask?.cancel()
        incomingTask = nil
        incoming = nil
        pulse()
    }

    private func incomingIsForLocal(_ env: MeshEnvelope) -> Bool {
        let dest = env.to.trimmingCharacters(in: .whitespacesAndNewlines)
        if dest.isEmpty || dest == "*" || dest == "YOU" { return true }
        return dest == mesh.localID
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
            mapInstrumentActive: armed && tab == .map,
            pocket: power.state.pocket,
            signaling: instruments.state.sosFlash
        )
    }

    func setPocket(_ on: Bool) {
        power.setPocket(on)
        applyMapKeepAwake()
    }

    /// Live GNSS only. Pack center and cached fallbacks stay off the MAP COORDINATES rail.
    var gnssYou: (lat: Double, lon: Double)? {
        guard let c = fix.last, c.latitude.isFinite, c.longitude.isFinite else { return nil }
        return (lat: c.latitude, lon: c.longitude)
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
        clearSpeakTurns()
        resetLiveGuide()
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
                ),
                name: m.name,
                note: m.note,
                emblem: m.emblem,
                from: m.from
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
        refreshHeldParty()
        applyLiveGuide()
    }

    private func applyLiveGuide() {
        guard routeCoords.count >= 2 else { return }
        guard let you = gnssYou ?? lastKnownFix else { return }
        let streets = searchIndex?.streetNames(along: routeCoords) ?? []
        let cue = LiveNav.progress(
            you: you,
            dest: destination(),
            coords: routeCoords,
            streets: streets,
            travelMode: travelMode
        )
        if cue.arrived {
            applyRemainingChrome(cue)
            if !liveArrived {
                liveArrived = true
                applySpeechTone()
                _ = speech.speak(VoiceNav.arrive, locale: locale)
            }
            return
        }
        if cue.offRoute {
            speechChrome = SpeakStatus.offRouteLine()
            let now = Date().timeIntervalSince1970
            if now - lastLiveRerouteAt >= LiveNav.replanSeconds {
                lastLiveRerouteAt = now
                navigate(mode: travelMode)
            }
            return
        }
        lastLiveRerouteAt = 0
        applyRemainingChrome(cue)
        if !cue.speakTurn.isEmpty, cue.speakTurn != liveSpokenTurn {
            liveSpokenTurn = cue.speakTurn
            applySpeechTone()
            _ = speech.speak(cue.speakTurn, locale: locale)
        }
    }

    private func applyRemainingChrome(_ cue: LiveNav.Cue) {
        let names = searchIndex?.streetNames(along: cue.remainingCoords) ?? []
        speechChrome = SpeakStatus.chrome(
            spoke: true,
            routeCoords: cue.remainingCoords,
            planChrome: navChrome,
            destination: destination(),
            you: gnssYou ?? lastKnownFix
        )
        speakHUDTurns = VoiceNav.hudTurns(
            cue.remainingCoords,
            travelMode: travelMode,
            streets: names
        )
        speakNextHUD = cue.nextHUD
        showSpeakTurns = !speakHUDTurns.isEmpty
    }

    private func resetLiveGuide() {
        liveSpokenTurn = ""
        liveArrived = false
        lastLiveRerouteAt = 0
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
    private var magNorth = true
    private var preferExternalGNSS = false
    private var wantCalibration = false
    private var lastTrue: Double = -1
    private var lastMag: Double = -1
    private var lastAcc: Double = -1
    private var haveHeadingSample = false

    func applyInstrument(_ state: InstrumentState) {
        let gnssChanged = preferExternalGNSS != state.externalGNSS
        magNorth = state.magNorth
        preferExternalGNSS = state.externalGNSS
        applyAccuracy()
        if gnssChanged, mgr != nil {
            mgr?.stopUpdatingLocation()
            mgr?.startUpdatingLocation()
        }
        refreshHeading()
    }

    func requestHeadingCalibration() {
        wantCalibration = true
        mgr?.stopUpdatingHeading()
        startHeading()
    }

    func arm() {
        let mgr = self.mgr ?? CLLocationManager()
        self.mgr = mgr
        mgr.delegate = self
        applyAccuracy()
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

    private func applyAccuracy() {
        guard let mgr else { return }
        mgr.desiredAccuracy = preferExternalGNSS
            ? kCLLocationAccuracyBestForNavigation
            : kCLLocationAccuracyBest
    }

    private func startHeading() {
        guard CLLocationManager.headingAvailable() else { return }
        mgr?.startUpdatingHeading()
    }

    private func refreshHeading() {
        guard haveHeadingSample else { return }
        heading = PersonCompass.liveHeading(
            trueHeading: lastTrue,
            magneticHeading: lastMag,
            accuracy: lastAcc,
            magNorth: magNorth
        )
        onChange?()
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
        if let coordinate = locations.last?.coordinate, CLLocationCoordinate2DIsValid(coordinate) {
            last = coordinate
        }
        publishIfNeeded()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        lastTrue = newHeading.trueHeading
        lastMag = newHeading.magneticHeading
        lastAcc = newHeading.headingAccuracy
        haveHeadingSample = true
        heading = PersonCompass.liveHeading(
            trueHeading: lastTrue,
            magneticHeading: lastMag,
            accuracy: lastAcc,
            magNorth: magNorth
        )
        if wantCalibration, lastAcc >= 0 {
            wantCalibration = false
        }
        publishIfNeeded()
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        wantCalibration
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

enum IncomingKind: Equatable {
    case call
    case message
}

struct IncomingLine: Equatable {
    var from: String
    var name: String
    var emblem: String
    var location: String
    var kind: IncomingKind
    var raisedAt: Date
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
