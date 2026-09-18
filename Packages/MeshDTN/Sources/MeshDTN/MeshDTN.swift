import Foundation
import Observation
import BlackBox
import CryptoParty
import CryptoKit

public enum LinkKind: String, Sendable { case none, bleTensOfMeters, dtnCarry, optionalLoRaBrick }

public enum RadioPath: String, Sendable, Equatable { case none, mpc, ble, hop }

public struct MeshEnvelope: Codable, Equatable, Sendable {
    public var id: String
    public var from: String
    public var to: String
    public var kind: String
    public var body: Data
    public var created: Date

    public init(id: String, from: String, to: String, kind: String, body: Data, created: Date = Date()) {
        self.id = id
        self.from = from
        self.to = to
        self.kind = kind
        self.body = body
        self.created = created
    }
}

public struct MeshPip: Equatable, Sendable {
    public var from: String
    public var lat: Double
    public var lon: Double
    public var headingDeg: Double?
    public var emblem: String?
    public var name: String?
    public var status: String?
    public var vitals: [Double]?
    public init(
        from: String,
        lat: Double,
        lon: Double,
        headingDeg: Double? = nil,
        emblem: String? = nil,
        name: String? = nil,
        status: String? = nil,
        vitals: [Double]? = nil
    ) {
        self.from = from
        self.lat = lat
        self.lon = lon
        self.headingDeg = headingDeg
        self.emblem = emblem
        self.name = name
        self.status = status
        self.vitals = vitals
    }
}

/// Safety chrome on a person, not a party-wide chip blast.
public enum PartyStatus: String, CaseIterable, Sendable {
    case good, okay, bad, emergency

    public static let fallback = PartyStatus.good

    public var title: String {
        switch self {
        case .good:
            return "GOOD"
        case .okay:
            return "OKAY"
        case .bad:
            return "BAD"
        case .emergency:
            return "EMERGENCY!"
        }
    }

    public static func parse(_ raw: String?) -> PartyStatus {
        guard let raw else { return .good }
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "good", "ok":
            return .good
        case "okay", "wait":
            return .okay
        case "bad", "water":
            return .bad
        case "emergency", "emergency!", "down":
            return .emergency
        default:
            return .good
        }
    }
}

public enum PartyNote {
    public static let maxChars = 80

    public static func clean(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxChars))
    }
}

public struct PartyThreadLine: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var from: String
    public var to: String
    public var text: String

    public init(id: String = UUID().uuidString, from: String, to: String, text: String) {
        self.id = id
        self.from = from
        self.to = to
        self.text = PartyNote.clean(text)
    }
}

/// `lat,lon` still parses. Newer peers add heading, face, name, status, rails.
public enum MeshPOS {
    public static func body(
        lat: Double,
        lon: Double,
        headingDeg: Double?,
        emblem: String?,
        name: String? = nil,
        status: String? = nil,
        vitals: [Double]? = nil
    ) -> String {
        let heading: String
        if let headingDeg, headingDeg >= 0 {
            heading = String(headingDeg)
        } else {
            heading = ""
        }
        let face = emblem ?? ""
        let who = nameToken(name ?? "")
        let band = PartyStatus.parse(status).rawValue
        let core = "\(lat),\(lon),\(heading),\(face),\(who),\(band)"
        guard let vitals, vitals.count == 6 else { return core }
        let rails = vitals.map { String(format: "%.2f", $0) }.joined(separator: ",")
        return "\(core),\(rails)"
    }

    public static func nameToken(_ raw: String) -> String {
        let kept = raw.uppercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
        let collapsed = kept.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return String(collapsed.prefix(16))
    }

    public static func parse(
        _ text: String
    ) -> (
        lat: Double,
        lon: Double,
        headingDeg: Double?,
        emblem: String?,
        name: String?,
        status: String?,
        vitals: [Double]?
    )? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              lat.isFinite, lon.isFinite else {
            return nil
        }
        var heading: Double?
        if parts.count >= 3, !parts[2].isEmpty, let value = Double(parts[2]), value >= 0 {
            heading = value
        }
        var emblem: String?
        if parts.count >= 4 {
            let raw = String(parts[3])
            if !raw.isEmpty { emblem = raw }
        }
        var name: String?
        if parts.count >= 5 {
            let token = nameToken(String(parts[4]))
            if !token.isEmpty { name = token }
        }
        var status: String?
        if parts.count >= 6 {
            let raw = String(parts[5])
            if !raw.isEmpty { status = PartyStatus.parse(raw).rawValue }
        }
        var vitals: [Double]?
        if parts.count >= 12 {
            let rails = (6..<12).compactMap { Double(String(parts[$0])) }
            if rails.count == 6 { vitals = rails }
        }
        return (lat, lon, heading, emblem, name, status, vitals)
    }
}

public enum MeshTimerBody {
    public static func parse(_ raw: String) -> (task: String, duration: TimeInterval) {
        let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 2, let sec = TimeInterval(parts[1]), sec > 0 {
            return (parts[0], sec)
        }
        if raw == "1min" { return ("1min", 60) }
        return (raw, 7200)
    }

    public static func encode(task: String, duration: TimeInterval, done: Bool) -> String {
        if done { return task }
        if task == "1min", duration == 60 { return "1min" }
        if task == "water", duration == 7200 { return "water" }
        return "\(task)\t\(Int(duration.rounded()))"
    }
}

public enum MeshKitBody {
    public static func parse(_ raw: String) -> (id: String, name: String, count: Int, assignedTo: String, working: Bool)? {
        let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else { return nil }
        let count = Int(parts[2]) ?? 0
        let assigned = parts[3] == "-" ? "" : parts[3]
        return (parts[0], parts[1], count, assigned, parts[4] == "1")
    }
}

public enum MeshMarkBody {
    public static func encode(
        id: String,
        lat: Double,
        lon: Double,
        name: String,
        note: String,
        emblem: String,
        label: String
    ) -> String {
        [
            id,
            String(lat),
            String(lon),
            clean(name),
            clean(note),
            emblem,
            clean(label),
        ].joined(separator: "\t")
    }

    public static func parse(_ raw: String) -> (
        id: String,
        lat: Double,
        lon: Double,
        name: String,
        note: String,
        emblem: String,
        label: String
    )? {
        let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 7 else { return nil }
        guard let lat = Double(parts[1]), let lon = Double(parts[2]) else { return nil }
        return (parts[0], lat, lon, parts[3], parts[4], parts[5], parts[6])
    }

    public static func clean(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Seat announcement. Separate from POS so vitals stay a 12-part body.
public enum MeshRosterBody {
    public static func encode(id: String, role: String, name: String) -> String {
        [id, role, MeshMarkBody.clean(name)].joined(separator: "\t")
    }

    public static func parse(_ raw: String) -> (id: String, role: String, name: String)? {
        let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        return (id, parts[1], parts[2])
    }
}

/// Party day line. Same group only — the body seals with the party code.
public enum MeshDiaryBody {
    public static func encode(id: String, from: String, name: String, at: Date, text: String) -> String {
        [
            id,
            from,
            MeshMarkBody.clean(name),
            String(Int(at.timeIntervalSince1970)),
            MeshMarkBody.clean(text),
        ].joined(separator: "\t")
    }

    public static func parse(_ raw: String) -> (id: String, from: String, name: String, at: Date, text: String)? {
        let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else { return nil }
        let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let from = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !from.isEmpty, let epoch = TimeInterval(parts[3]) else { return nil }
        let text = MeshMarkBody.clean(parts[4])
        guard !text.isEmpty else { return nil }
        return (id, from, MeshMarkBody.clean(parts[2]), Date(timeIntervalSince1970: epoch), text)
    }
}

public struct MeshTimerEvent: Equatable, Sendable, Identifiable {
    public var id: String
    public var from: String
    public var task: String
    public var done: Bool
    public init(id: String, from: String, task: String, done: Bool) {
        self.id = id
        self.from = from
        self.task = task
        self.done = done
    }
}

public struct MeshDiaryEvent: Equatable, Sendable, Identifiable {
    public var id: String
    public var from: String
    public var name: String
    public var text: String
    public var at: Date
    public init(id: String, from: String, name: String, text: String, at: Date) {
        self.id = id
        self.from = from
        self.name = name
        self.text = text
        self.at = at
    }
}

public protocol MeshRadio: AnyObject {
    var path: RadioPath { get }
    func start(
        partyCode: String,
        join: Bool,
        onPeer: @escaping (String) -> Void,
        onLost: @escaping (String) -> Void,
        onEnvelope: @escaping (MeshEnvelope) -> Void
    )
    func stop()
    func send(_ env: MeshEnvelope)
}

/// Test stand-in. Does not auto-connect. appearPeer is a real GATT/MPC link, not a scan hit.
public final class LoopbackRadio: MeshRadio {
    public private(set) var path: RadioPath = .none
    public private(set) var startedCode: String?
    public private(set) var sent: [MeshEnvelope] = []
    private let livePath: RadioPath
    private var onPeer: ((String) -> Void)?
    private var onLost: ((String) -> Void)?
    private var onEnvelope: ((MeshEnvelope) -> Void)?
    public var onHear: ((MeshHear) -> Void)?
    public var onHop: ((String) -> Void)?
    public var onHopLost: ((String) -> Void)?

    public init(path: RadioPath = .ble) { livePath = path }

    public func start(
        partyCode: String,
        join: Bool,
        onPeer: @escaping (String) -> Void,
        onLost: @escaping (String) -> Void,
        onEnvelope: @escaping (MeshEnvelope) -> Void
    ) {
        startedCode = join ? partyCode : ""
        self.onPeer = onPeer
        self.onLost = onLost
        self.onEnvelope = onEnvelope
        path = .none
    }

    public func stop() { path = .none }

    public func send(_ env: MeshEnvelope) { sent.append(env) }

    public func appearPeer(_ name: String = "loop") {
        path = livePath
        onPeer?(name)
    }

    public func appearHop(_ name: String = "hop") {
        path = .hop
        onHop?(name)
    }

    public func appearHear(_ hear: MeshHear) {
        onHear?(hear)
    }

    public func losePeer(_ name: String) {
        onLost?(name)
    }

    public func loseHop(_ name: String) {
        onHopLost?(name)
        if path == .hop { path = .none }
    }

    public func deliver(_ env: MeshEnvelope) { onEnvelope?(env) }
}

public enum PartyMeshUUID {
    public static func uuid(for partyCode: String) -> UUID {
        fnvUUID(seed: "blackout.mesh.v1.\(partyCode.uppercased())")
    }

    public static func characteristic(for partyCode: String) -> UUID {
        fnvUUID(seed: "blackout.mesh.char.v1.\(partyCode.uppercased())")
    }

    public static func hopService() -> UUID {
        fnvUUID(seed: "blackout.mesh.hop.v1")
    }

    public static func hopCharacteristic() -> UUID {
        fnvUUID(seed: "blackout.mesh.hop.char.v1")
    }

    private static func fnvUUID(seed: String) -> UUID {
        var h0: UInt64 = 0xcbf29ce484222325
        var h1: UInt64 = 0x100000001b3
        for b in seed.utf8 {
            h0 ^= UInt64(b)
            h0 &*= 0x100000001b3
            h1 ^= UInt64(b) &* 16_777_619
            h1 &*= 0xcbf29ce484222325
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: h0 >> (UInt64(i) * 8))
            bytes[i + 8] = UInt8(truncatingIfNeeded: h1 >> (UInt64(i) * 8))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

public enum BLEEnvelopeCodec {
    public static let maxChunk = 160
    private static let magic: [UInt8] = [0x4D, 0x45, 0x30, 0x31]

    public static func chunk(_ payload: Data) -> [Data] {
        var framed = Data(magic)
        let n = UInt32(payload.count)
        framed.append(contentsOf: [
            UInt8(truncatingIfNeeded: n >> 24),
            UInt8(truncatingIfNeeded: n >> 16),
            UInt8(truncatingIfNeeded: n >> 8),
            UInt8(truncatingIfNeeded: n),
        ])
        framed.append(payload)
        var out: [Data] = []
        var i = 0
        while i < framed.count {
            out.append(framed.subdata(in: i..<min(i + maxChunk, framed.count)))
            i += maxChunk
        }
        return out
    }

    public struct Assembler {
        private var buf = Data()
        public init() {}

        public mutating func push(_ chunk: Data) -> Data? {
            buf.append(chunk)
            guard buf.count >= 8, Array(buf.prefix(4)) == BLEEnvelopeCodec.magic else {
                if buf.count >= 4, Array(buf.prefix(4)) != BLEEnvelopeCodec.magic { buf.removeAll() }
                return nil
            }
            let n = (UInt32(buf[4]) << 24) | (UInt32(buf[5]) << 16) | (UInt32(buf[6]) << 8) | UInt32(buf[7])
            guard buf.count >= 8 + Int(n) else { return nil }
            let payload = buf.subdata(in: 8..<(8 + Int(n)))
            buf.removeAll()
            return payload
        }
    }
}

@Observable
public final class MeshNet: @unchecked Sendable {
    public private(set) var joined = false
    public private(set) var nearby: [String] = []
    public private(set) var hops: [String] = []
    public private(set) var hears: [MeshHear] = []
    public private(set) var store: [MeshEnvelope] = []
    public private(set) var inbox: [MeshEnvelope] = []
    public private(set) var pips: [MeshPip] = []
    public private(set) var inboundChips: [String] = []
    public private(set) var inboundTimers: [MeshTimerEvent] = []
    public private(set) var inboundDiary: [MeshDiaryEvent] = []
    public private(set) var lastRedOn: Bool?
    public private(set) var chromeNet = "NET · NONE"
    public private(set) var chromeNear = ""
    public private(set) var chromeSignal = ""
    public private(set) var listening = false
    public private(set) var placing = false
    public private(set) var lasts: [MeshPresence.LastFix] = []
    private var lastRSSI: Int?
    public var airplane = true
    public var loRaBrickPresent = false
    public var partyCode = ""
    public let localID: String
    @ObservationIgnored public var radio: MeshRadio?
    @ObservationIgnored public var onInbound: ((MeshEnvelope) -> Void)?
    @ObservationIgnored public var onPeersChanged: (() -> Void)?
    @ObservationIgnored private let box: EventLog

    public init(box: EventLog) {
        self.box = box
        self.localID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6))
    }

    public func attach(_ radio: MeshRadio) { self.radio = radio }

    public func startScan() {
        placing = true
        if listening {
            refreshChrome()
            return
        }
        startListen()
    }

    public func startListen() {
        radio?.stop()
        if airplane {
            box.log("mesh", "airplane: listen is Bluetooth only")
        }
        nearby = []
        hops = []
        joined = false
        refreshChrome()
        guard let radio else {
            box.log("mesh", "NET NONE local writes only")
            return
        }
        listening = true
        bindRadioHooks()
        radio.start(partyCode: "", join: false, onPeer: { [weak self] peer in
            self?.heardPeer(peer)
        }, onLost: { [weak self] peer in
            self?.lostPeer(peer)
        }, onEnvelope: { [weak self] env in
            self?.receive(env)
        })
        refreshChrome()
    }

    public func startLocal() {
        placing = true
        radio?.stop()
        if airplane {
            box.log("mesh", "airplane: no sockets; radio is Bluetooth only")
        }
        nearby = []
        hops = []
        joined = false
        refreshChrome()
        guard let radio else {
            box.log("mesh", "NET NONE local writes only")
            return
        }
        listening = true
        bindRadioHooks()
        radio.start(partyCode: partyCode, join: true, onPeer: { [weak self] peer in
            self?.heardPeer(peer)
        }, onLost: { [weak self] peer in
            self?.lostPeer(peer)
        }, onEnvelope: { [weak self] env in
            self?.receive(env)
        })
        refreshChrome()
    }

    public func stopParty() {
        nearby = []
        hops = []
        pips.removeAll()
        joined = false
        if radio != nil {
            startListen()
        } else {
            refreshChrome()
        }
        box.log("mesh", "party left; listen holds")
    }

    public func stopLocal() {
        radio?.stop()
        nearby = []
        hops = []
        hears = []
        lasts = []
        lastRSSI = nil
        chromeNear = ""
        chromeSignal = ""
        pips.removeAll()
        joined = false
        listening = false
        placing = false
        refreshChrome()
        box.log("mesh", "radio stopped")
    }

    /// DTN carry when you later meet. Not the live join path.
    public func meet(_ peer: String) {
        heardPeer(peer)
        box.log("dtn", "carry-forward meet \(peer) n=\(store.count)")
    }

    public func enqueue(_ env: MeshEnvelope) {
        var wire = env
        if let key = partyKey, let sealed = try? PartySeal.wrap(env.body, key: key) {
            wire.body = sealed
        }
        store.append(wire)
        if hasLiveLink, let radio {
            radio.send(wire)
            box.log("mesh", "tx \(env.kind) \(env.id)")
        } else {
            chromeNet = "NO PEERS · LOGGED"
            box.log("mesh", "NO PEERS · LOGGED local write \(env.kind) \(env.id)")
        }
        if isSelfAddressed(env) {
            receive(wire)
        }
    }

    public func sendPOS(
        from: String,
        lat: Double,
        lon: Double,
        headingDeg: Double? = nil,
        emblem: String? = nil,
        name: String? = nil,
        status: String? = nil,
        vitals: [Double]? = nil
    ) {
        guard lat.isFinite, lon.isFinite else { return }
        enqueue(
            make(
                from: from,
                kind: "pos",
                body: Data(
                    MeshPOS.body(
                        lat: lat,
                        lon: lon,
                        headingDeg: headingDeg,
                        emblem: emblem,
                        name: name,
                        status: status,
                        vitals: vitals
                    ).utf8
                )
            )
        )
        if from != localID {
            upsertPip(
                MeshPip(
                    from: from,
                    lat: lat,
                    lon: lon,
                    headingDeg: headingDeg,
                    emblem: emblem,
                    name: name,
                    status: status,
                    vitals: vitals
                )
            )
        }
    }

    public func sendChip(from: String, chip: String, to: String = "*") {
        enqueue(make(from: from, kind: "chip", body: Data(chip.utf8), to: to))
    }

    public func sendNote(from: String, text: String, to: String = "*") {
        let body = PartyNote.clean(text)
        guard !body.isEmpty else { return }
        enqueue(make(from: from, kind: "note", body: Data(body.utf8), to: to))
    }

    public func clearInboundChip(_ name: String) {
        inboundChips.removeAll { $0 == name }
    }

    public func sendVoice(from: String, opus: Data, to: String = "*") {
        enqueue(make(from: from, kind: "voice", body: opus, to: to))
    }

    public func sendRED(from: String, on: Bool) {
        enqueue(make(from: from, kind: "red", body: Data((on ? "on" : "off").utf8)))
    }

    public func sendTimer(from: String, task: String, done: Bool, duration: TimeInterval = 7200) {
        let body = MeshTimerBody.encode(task: task, duration: duration, done: done)
        enqueue(make(from: from, kind: done ? "timer.done" : "timer.set", body: Data(body.utf8)))
    }

    public func sendKit(
        from: String,
        itemID: String,
        name: String,
        count: Int,
        assignedTo: String,
        working: Bool
    ) {
        let assigned = assignedTo.isEmpty ? "-" : assignedTo
        let work = working ? "1" : "0"
        let body = "\(itemID)\t\(name)\t\(count)\t\(assigned)\t\(work)"
        enqueue(make(from: from, kind: "kit", body: Data(body.utf8)))
    }

    public func sendMark(
        from: String,
        id: String,
        lat: Double,
        lon: Double,
        name: String,
        note: String,
        emblem: String,
        label: String
    ) {
        guard lat.isFinite, lon.isFinite else { return }
        let body = MeshMarkBody.encode(
            id: id,
            lat: lat,
            lon: lon,
            name: name,
            note: note,
            emblem: emblem,
            label: label
        )
        enqueue(make(from: from, kind: "mark", body: Data(body.utf8)))
    }

    public func sendRoster(from: String, id: String, role: String, name: String) {
        let body = MeshRosterBody.encode(id: id, role: role, name: name)
        enqueue(make(from: from, kind: "roster", body: Data(body.utf8)))
    }

    public func sendDiary(
        from: String,
        name: String,
        text: String,
        at: Date = Date(),
        id: String = UUID().uuidString
    ) {
        let body = MeshDiaryBody.encode(id: id, from: from, name: name, at: at, text: text)
        guard MeshDiaryBody.parse(body) != nil else { return }
        enqueue(make(from: from, kind: "diary", body: Data(body.utf8)))
    }

    public func linkKind() -> LinkKind {
        if loRaBrickPresent { return .optionalLoRaBrick }
        if joined { return .bleTensOfMeters }
        if !store.isEmpty { return .dtnCarry }
        return .none
    }

    public func noteHear(_ hear: MeshHear) {
        if nearby.contains(hear.id) { return }
        if let i = hears.firstIndex(where: { $0.id == hear.id }) {
            var next = hear
            if next.lat == nil { next.lat = hears[i].lat }
            if next.lon == nil { next.lon = hears[i].lon }
            if next.name.isEmpty { next.name = hears[i].name }
            if next.manufacturer == nil { next.manufacturer = hears[i].manufacturer }
            if next.services.isEmpty { next.services = hears[i].services }
            if next.txPower == nil { next.txPower = hears[i].txPower }
            if next.connectable == nil { next.connectable = hears[i].connectable }
            hears[i] = next
        } else {
            hears.append(hear)
        }
        if let lat = hear.lat, let lon = hear.lon, lat.isFinite, lon.isFinite {
            rememberLast(lat: lat, lon: lon, kinds: [hear.kind.rawValue])
        }
        pruneHears()
    }

    public func noteHop(_ peer: String) {
        if !hops.contains(peer) { hops.append(peer) }
        refreshChrome()
        replayCarry()
        onPeersChanged?()
    }

    public func lostHop(_ peer: String) {
        hops.removeAll { $0 == peer }
        hears.removeAll { $0.id == peer && $0.kind == .hop }
        refreshChrome()
        onPeersChanged?()
    }

    public func pruneHears(now: Date = Date()) {
        hears.removeAll { now.timeIntervalSince($0.heardAt) > MeshPresence.hearSeconds }
        lasts.removeAll { now.timeIntervalSince($0.at) > MeshPresence.lastSeconds }
        chromeNear = MeshPresence.chrome(count: hears.count)
        let nowMax = hears.map(\.rssi).filter { $0 > -120 && $0 < 0 }.max()
        let next = MeshPresence.signal(was: lastRSSI, now: nowMax)
        if nowMax == nil {
            chromeSignal = ""
        } else if !next.isEmpty {
            chromeSignal = next
        }
        lastRSSI = nowMax
    }

    public func presenceMarks(you: (lat: Double, lon: Double)?) -> [MeshPresence.Mark] {
        pruneHears()
        let live = MeshPresence.marks(hears: hears, you: you, place: placing)
        return live + MeshPresence.lasts(remembered: lasts, live: live)
    }

    public func rememberLast(lat: Double, lon: Double, kinds: [String], count: Int = 1, at: Date = Date()) {
        guard lat.isFinite, lon.isFinite else { return }
        if let i = lasts.firstIndex(where: {
            MeshPresence.meters($0.lat, $0.lon, lat, lon) <= MeshPresence.houseMeters
        }) {
            lasts[i] = MeshPresence.LastFix(
                lat: lat,
                lon: lon,
                count: max(lasts[i].count, count),
                kinds: kinds.isEmpty ? lasts[i].kinds : kinds,
                at: at
            )
            return
        }
        lasts.append(MeshPresence.LastFix(lat: lat, lon: lon, count: count, kinds: kinds, at: at))
    }

    private func bindRadioHooks() {
        if let live = radio as? LiveMeshRadio {
            live.onHear = { [weak self] hear in self?.noteHear(hear) }
            live.onHop = { [weak self] peer in self?.noteHop(peer) }
            live.onHopLost = { [weak self] peer in self?.lostHop(peer) }
            live.carry = { [weak self] in
                Array((self?.store ?? []).filter { $0.kind != "voice" }.suffix(24))
            }
        }
        if let loop = radio as? LoopbackRadio {
            loop.onHear = { [weak self] hear in self?.noteHear(hear) }
            loop.onHop = { [weak self] peer in self?.noteHop(peer) }
            loop.onHopLost = { [weak self] peer in self?.lostHop(peer) }
        }
    }

    private func replayCarry() {
        guard let radio, !hops.isEmpty else { return }
        for env in store where env.kind != "voice" {
            radio.send(env)
        }
    }

    private var hasLiveLink: Bool {
        guard radio != nil else { return false }
        if !nearby.isEmpty, radio?.path != .none { return true }
        return !hops.isEmpty
    }

    private var partyKey: SymmetricKey? {
        let code = partyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        return PartySeal.key(code: code)
    }

    private func make(from: String, kind: String, body: Data, to: String = "*") -> MeshEnvelope {
        MeshEnvelope(id: UUID().uuidString, from: from, to: to, kind: kind, body: body)
    }

    private func isSelfAddressed(_ env: MeshEnvelope) -> Bool {
        guard env.from == localID else { return false }
        let dest = env.to.trimmingCharacters(in: .whitespacesAndNewlines)
        return dest == "YOU" || dest == localID
    }

    private func heardPeer(_ peer: String) {
        if !nearby.contains(peer) { nearby.append(peer) }
        hears.removeAll { $0.id == peer }
        refreshChrome()
        box.log("mesh", "peer \(peer) \(chromeNet)")
        onPeersChanged?()
    }

    private func lostPeer(_ peer: String) {
        nearby.removeAll { $0 == peer }
        pips.removeAll { $0.from == peer }
        refreshChrome()
        box.log("mesh", "lost \(peer) \(chromeNet)")
        onPeersChanged?()
    }

    private func receive(_ env: MeshEnvelope) {
        if env.from == localID, !isSelfAddressed(env) { return }
        if inbox.contains(where: { $0.id == env.id }) { return }
        if !store.contains(where: { $0.id == env.id }) {
            store.append(env)
        }
        guard let plain = PartySeal.openBody(env.body, key: partyKey) else {
            box.log("mesh", "rx sealed \(env.kind) from \(env.from)")
            return
        }
        var shown = env
        shown.body = plain
        inbox.append(shown)
        switch shown.kind {
        case "pos":
            if let text = String(data: shown.body, encoding: .utf8),
               let parsed = MeshPOS.parse(text) {
                if nearby.contains(env.from) {
                    upsertPip(
                        MeshPip(
                            from: env.from,
                            lat: parsed.lat,
                            lon: parsed.lon,
                            headingDeg: parsed.headingDeg,
                            emblem: parsed.emblem,
                            name: parsed.name,
                            status: parsed.status,
                            vitals: parsed.vitals
                        )
                    )
                } else {
                    noteHear(
                        MeshHear(
                            id: env.from,
                            kind: .hop,
                            lat: parsed.lat,
                            lon: parsed.lon
                        )
                    )
                    rememberLast(lat: parsed.lat, lon: parsed.lon, kinds: ["hop"])
                }
            }
        case "chip":
            if let name = String(data: shown.body, encoding: .utf8) {
                inboundChips.append(name)
                if inboundChips.count > 16 {
                    inboundChips.removeFirst(inboundChips.count - 16)
                }
            }
        case "note":
            if let text = String(data: shown.body, encoding: .utf8) {
                let note = PartyNote.clean(text)
                if !note.isEmpty {
                    inboundChips.append(note)
                    if inboundChips.count > 16 {
                        inboundChips.removeFirst(inboundChips.count - 16)
                    }
                }
            }
        case "red":
            lastRedOn = String(data: shown.body, encoding: .utf8) == "on"
        case "timer.set", "timer.done":
            if let raw = String(data: shown.body, encoding: .utf8) {
                let parsed = MeshTimerBody.parse(raw)
                upsertTimer(MeshTimerEvent(id: env.id, from: env.from, task: parsed.task, done: env.kind == "timer.done"))
            }
        case "diary":
            if let raw = String(data: shown.body, encoding: .utf8),
               let parsed = MeshDiaryBody.parse(raw) {
                upsertDiary(
                    MeshDiaryEvent(
                        id: parsed.id,
                        from: parsed.from,
                        name: parsed.name,
                        text: parsed.text,
                        at: parsed.at
                    )
                )
            }
        case "mark", "kit", "voice", "roster":
            break
        default:
            break
        }
        box.log("mesh", "rx \(env.kind) from \(env.from)")
        onInbound?(shown)
    }

    private func upsertPip(_ pip: MeshPip) {
        if let i = pips.firstIndex(where: { $0.from == pip.from }) {
            pips[i] = pip
        } else {
            pips.append(pip)
        }
    }

    private func upsertTimer(_ ev: MeshTimerEvent) {
        if let i = inboundTimers.firstIndex(where: { $0.task == ev.task && $0.from == ev.from }) {
            inboundTimers[i] = ev
        } else {
            inboundTimers.append(ev)
        }
    }

    private func upsertDiary(_ ev: MeshDiaryEvent) {
        if let i = inboundDiary.firstIndex(where: { $0.id == ev.id }) {
            inboundDiary[i] = ev
        } else {
            inboundDiary.append(ev)
        }
        inboundDiary.sort {
            if $0.at != $1.at { return $0.at > $1.at }
            return $0.id > $1.id
        }
    }

    private func refreshChrome() {
        pruneHears()
        let path = radio?.path ?? .none
        if nearby.isEmpty && hops.isEmpty {
            joined = false
            chromeNet = "NET · NONE"
            chromeNear = MeshPresence.chrome(count: hears.count)
            return
        }
        if nearby.isEmpty {
            joined = false
            chromeNet = "NET · HOP"
            chromeNear = MeshPresence.chrome(count: hears.count)
            return
        }
        if path == .none {
            joined = false
            chromeNet = "NET · NONE"
            chromeNear = MeshPresence.chrome(count: hears.count)
            return
        }
        joined = true
        switch path {
        case .none:
            joined = false
            chromeNet = "NET · NONE"
        case .mpc:
            chromeNet = "NET · MPC"
        case .ble:
            chromeNet = "NET · BLE"
        case .hop:
            chromeNet = "NET · HOP"
        }
        chromeNear = MeshPresence.chrome(count: hears.count)
    }
}
