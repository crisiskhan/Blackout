import Foundation
import BlackBox

public enum LinkKind: String, Sendable { case none, bleTensOfMeters, dtnCarry, optionalLoRaBrick }

public struct MeshEnvelope: Codable, Equatable, Sendable {
    public var id: String
    public var from: String
    public var to: String
    public var kind: String
    public var body: Data
    public var created: Date
}

public final class MeshNet: @unchecked Sendable {
    public private(set) var joined = false
    public private(set) var nearby: [String] = []
    public private(set) var store: [MeshEnvelope] = []
    public var airplane = true
    public var loRaBrickPresent = false
    private let box: EventLog
    public init(box: EventLog) { self.box = box }

    public func startLocal() {
        if airplane {
            box.log("mesh", "airplane deny-all sockets; local store only")
            joined = false
            nearby = []
            return
        }
        joined = true
        box.log("mesh", "local radio tens-of-meters")
    }

    public func meet(_ peer: String) {
        nearby.append(peer)
        joined = true
        box.log("dtn", "carry-forward meet \(peer) n=\(store.count)")
    }

    public func enqueue(_ env: MeshEnvelope) {
        store.append(env)
        box.log("dtn", "queued \(env.id)")
    }

    public func linkKind() -> LinkKind {
        if loRaBrickPresent { return .optionalLoRaBrick }
        if !nearby.isEmpty { return .bleTensOfMeters }
        if !store.isEmpty { return .dtnCarry }
        return .none
    }
}
