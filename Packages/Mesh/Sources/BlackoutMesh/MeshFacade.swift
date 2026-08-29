import BlackoutCore
import Foundation
import MultipeerConnectivity
import Observation

/// Dumb local-radio pipe. MultipeerConnectivity only — no cloud, no accounts, no WAN.
/// 1/N: MeshPill goes 0→1 when one phone on the same radio connects. N>1 routing is out of scope.
@MainActor
@Observable
public final class MeshFacade: MeshServing {
    public private(set) var nearbyPeerCount: Int = 0
    public var statusLine: String { "\(nearbyPeerCount) nearby" }
    public private(set) var lastOutbound: Envelope?
    public private(set) var lastEvent: MeshInbound?
    public private(set) var inboundSequence: UInt64 = 0

    public var onInbound: ((MeshInbound) -> Void)?

    private let localPeer: MCPeerID
    private var advertisement: Data = Data()
    private var pipe: MultipeerPipe?
    private var running = false

    public init() {
        localPeer = MCPeerID(displayName: String(UUID().uuidString.prefix(8)))
    }

    public func setLocalAdvertisement(_ data: Data) {
        advertisement = data
        pipe?.setAdvertisement(data)
    }

    public func start() {
        if running { return }
        running = true
        let radio = MultipeerPipe(localPeer: localPeer)
        radio.onPeerCount = { [weak self] count in
            self?.nearbyPeerCount = count
        }
        radio.onInbound = { [weak self] event in
            self?.receive(event)
        }
        radio.setAdvertisement(advertisement)
        radio.start()
        pipe = radio
    }

    public func stop() {
        running = false
        pipe?.stop()
        pipe = nil
        nearbyPeerCount = 0
    }

    public func send(_ envelope: Envelope) {
        lastOutbound = envelope
        guard let frame = MeshWire.encodeEnvelope(envelope) else { return }
        pipe?.send(frame: frame)
    }

    private func receive(_ inbound: MeshInbound) {
        lastEvent = inbound
        inboundSequence &+= 1
        onInbound?(inbound)
    }
}
