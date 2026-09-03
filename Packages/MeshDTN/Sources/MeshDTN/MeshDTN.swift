import Foundation
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

public protocol MeshRadio: AnyObject {
    var path: RadioPath { get }
    func start(partyCode: String, onPeer: @escaping (String) -> Void, onEnvelope: @escaping (MeshEnvelope) -> Void)
    func stop()
    func send(_ env: MeshEnvelope)
}

/// Test / Linux stand-in. Same party envelopes. Not a store-and-meet-only path.
public final class LoopbackRadio: MeshRadio {
    public private(set) var path: RadioPath
    public private(set) var startedCode: String?
    public private(set) var sent: [MeshEnvelope] = []
    public init(path: RadioPath = .ble) { self.path = path }

    public func start(partyCode: String, onPeer: @escaping (String) -> Void, onEnvelope: @escaping (MeshEnvelope) -> Void) {
        startedCode = partyCode
        onPeer("loop")
        _ = onEnvelope
    }

    public func stop() {}
    public func send(_ env: MeshEnvelope) { sent.append(env) }
}

public final class MeshNet: @unchecked Sendable {
    public private(set) var joined = false
    public private(set) var nearby: [String] = []
    public private(set) var store: [MeshEnvelope] = []
    public private(set) var inbox: [MeshEnvelope] = []
    public private(set) var pips: [MeshPip] = []
    public private(set) var chromeNet = "NET · NONE"
    public var airplane = true
    public var loRaBrickPresent = false
    public var partyCode = ""
    public var radio: MeshRadio?
    private let box: EventLog

    public init(box: EventLog) { self.box = box }

    public func attach(_ radio: MeshRadio) { self.radio = radio }

    public func startLocal() {
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
        if joined, let radio, radio.path != .none {
            radio.send(env)
            box.log("mesh", "tx \(env.kind) \(env.id)")
        } else {
            box.log("mesh", "NET NONE local write \(env.kind) \(env.id)")
        }
    }

    public func sendPOS(from: String, lat: Double, lon: Double) {
        let body = Data("\(lat),\(lon)".utf8)
        enqueue(make(from: from, kind: "pos", body: body))
        upsertPip(MeshPip(from: from, lat: lat, lon: lon))
    }

    public func sendChip(from: String, chip: String) {
        enqueue(make(from: from, kind: "chip", body: Data(chip.utf8)))
    }

    public func sendRED(from: String, on: Bool) {
        enqueue(make(from: from, kind: "red", body: Data(on ? "on" : "off", using: .utf8)!))
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

    private func make(from: String, kind: String, body: Data) -> MeshEnvelope {
        MeshEnvelope(id: UUID().uuidString, from: from, to: "*", kind: kind, body: body)
    }

    private func heardPeer(_ peer: String) {
        if !nearby.contains(peer) { nearby.append(peer) }
        refreshChrome()
        box.log("mesh", "peer \(peer) \(chromeNet)")
    }

    private func receive(_ env: MeshEnvelope) {
        inbox.append(env)
        store.append(env)
        if env.kind == "pos", let text = String(data: env.body, encoding: .utf8) {
            let parts = text.split(separator: ",")
            if parts.count >= 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                upsertPip(MeshPip(from: env.from, lat: lat, lon: lon))
            }
        }
        box.log("mesh", "rx \(env.kind) from \(env.from)")
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
