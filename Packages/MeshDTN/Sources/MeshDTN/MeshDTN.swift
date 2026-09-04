import Foundation
import Observation
import BlackBox

public enum LinkKind: String, Sendable { case none, bleTensOfMeters, dtnCarry, optionalLoRaBrick }

public enum RadioPath: String, Sendable, Equatable { case none, mpc, ble }

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
    public init(from: String, lat: Double, lon: Double) {
        self.from = from
        self.lat = lat
        self.lon = lon
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

public protocol MeshRadio: AnyObject {
    var path: RadioPath { get }
    func start(partyCode: String, onPeer: @escaping (String) -> Void, onLost: @escaping (String) -> Void, onEnvelope: @escaping (MeshEnvelope) -> Void)
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
    private var onEnvelope: ((MeshEnvelope) -> Void)?

    public init(path: RadioPath = .ble) { livePath = path }

    public func start(
        partyCode: String,
        onPeer: @escaping (String) -> Void,
        onLost: @escaping (String) -> Void,
        onEnvelope: @escaping (MeshEnvelope) -> Void
    ) {
        startedCode = partyCode
        self.onPeer = onPeer
        self.onEnvelope = onEnvelope
        path = .none
        _ = onLost
    }

    public func stop() { path = .none }

    public func send(_ env: MeshEnvelope) { sent.append(env) }

    public func appearPeer(_ name: String = "loop") {
        path = livePath
        onPeer?(name)
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
    public private(set) var store: [MeshEnvelope] = []
    public private(set) var inbox: [MeshEnvelope] = []
    public private(set) var pips: [MeshPip] = []
    public private(set) var inboundChips: [String] = []
    public private(set) var inboundTimers: [MeshTimerEvent] = []
    public private(set) var lastRedOn: Bool?
    public private(set) var chromeNet = "NET · NONE"
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

    public func startLocal() {
        radio?.stop()
        if airplane {
            box.log("mesh", "airplane: no sockets; radio is Bluetooth only")
        }
        nearby = []
        joined = false
        refreshChrome()
        guard let radio else {
            box.log("mesh", "NET NONE local writes only")
            return
        }
        radio.start(partyCode: partyCode, onPeer: { [weak self] peer in
            self?.heardPeer(peer)
        }, onLost: { [weak self] peer in
            self?.lostPeer(peer)
        }, onEnvelope: { [weak self] env in
            self?.receive(env)
        })
        refreshChrome()
    }

    public func stopLocal() {
        radio?.stop()
        nearby = []
        joined = false
        refreshChrome()
        box.log("mesh", "radio stopped")
    }

    /// DTN carry when you later meet. Not the live join path.
    public func meet(_ peer: String) {
        heardPeer(peer)
        box.log("dtn", "carry-forward meet \(peer) n=\(store.count)")
    }

    public func enqueue(_ env: MeshEnvelope) {
        store.append(env)
        if hasLiveLink, let radio {
            radio.send(env)
            box.log("mesh", "tx \(env.kind) \(env.id)")
        } else {
            chromeNet = "NO PEERS · LOGGED"
            box.log("mesh", "NO PEERS · LOGGED local write \(env.kind) \(env.id)")
        }
    }

    public func sendPOS(from: String, lat: Double, lon: Double) {
        enqueue(make(from: from, kind: "pos", body: Data("\(lat),\(lon)".utf8)))
        upsertPip(MeshPip(from: from, lat: lat, lon: lon))
    }

    public func sendChip(from: String, chip: String) {
        enqueue(make(from: from, kind: "chip", body: Data(chip.utf8)))
    }

    public func sendRED(from: String, on: Bool) {
        enqueue(make(from: from, kind: "red", body: Data((on ? "on" : "off").utf8)))
    }

    public func sendTimer(from: String, task: String, done: Bool) {
        enqueue(make(from: from, kind: done ? "timer.done" : "timer.set", body: Data(task.utf8)))
    }

    public func linkKind() -> LinkKind {
        if loRaBrickPresent { return .optionalLoRaBrick }
        if joined { return .bleTensOfMeters }
        if !store.isEmpty { return .dtnCarry }
        return .none
    }

    private var hasLiveLink: Bool {
        guard let radio else { return false }
        if radio.path == .none { return false }
        return !nearby.isEmpty
    }

    private func make(from: String, kind: String, body: Data) -> MeshEnvelope {
        MeshEnvelope(id: UUID().uuidString, from: from, to: "*", kind: kind, body: body)
    }

    private func heardPeer(_ peer: String) {
        if !nearby.contains(peer) { nearby.append(peer) }
        refreshChrome()
        box.log("mesh", "peer \(peer) \(chromeNet)")
        onPeersChanged?()
    }

    private func lostPeer(_ peer: String) {
        nearby.removeAll { $0 == peer }
        refreshChrome()
        box.log("mesh", "lost \(peer) \(chromeNet)")
    }

    private func receive(_ env: MeshEnvelope) {
        if env.from == localID { return }
        if inbox.contains(where: { $0.id == env.id }) { return }
        inbox.append(env)
        store.append(env)
        switch env.kind {
        case "pos":
            if let text = String(data: env.body, encoding: .utf8) {
                let parts = text.split(separator: ",")
                if parts.count >= 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                    upsertPip(MeshPip(from: env.from, lat: lat, lon: lon))
                }
            }
        case "chip":
            if let name = String(data: env.body, encoding: .utf8) {
                inboundChips.append(name)
            }
        case "red":
            lastRedOn = String(data: env.body, encoding: .utf8) == "on"
        case "timer.set", "timer.done":
            if let task = String(data: env.body, encoding: .utf8) {
                inboundTimers.append(MeshTimerEvent(id: env.id, from: env.from, task: task, done: env.kind == "timer.done"))
            }
        default:
            break
        }
        box.log("mesh", "rx \(env.kind) from \(env.from)")
        onInbound?(env)
    }

    private func upsertPip(_ pip: MeshPip) {
        if let i = pips.firstIndex(where: { $0.from == pip.from }) {
            pips[i] = pip
        } else {
            pips.append(pip)
        }
    }

    private func refreshChrome() {
        let path = radio?.path ?? .none
        if nearby.isEmpty || path == .none {
            joined = false
            chromeNet = "NET · NONE"
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
        }
    }
}
