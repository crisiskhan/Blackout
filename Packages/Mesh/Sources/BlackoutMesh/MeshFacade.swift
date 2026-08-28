import BlackoutCore
import Foundation
import Observation

/// Dumb pipe. Live 1/N mesh is wave 2. Zero peers is calm success.
@MainActor
@Observable
public final class MeshFacade: MeshServing {
    public private(set) var nearbyPeerCount: Int = 0
    public var statusLine: String { "\(nearbyPeerCount) nearby" }
    public private(set) var lastOutbound: Envelope?

    public init() {}

    public func start() {}

    public func stop() {}

    public func send(_ envelope: Envelope) {
        lastOutbound = envelope
    }
}
