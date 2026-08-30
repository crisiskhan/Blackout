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
    public var onFileProgress: ((String, Double) -> Void)?
    public var onFileReceiveStarted: ((String) -> Void)?
    public var onSendComplete: ((String, Bool) -> Void)?

    private var advertisement: Data = Data()
    private var pipe: MultipeerPipe?
    private var running = false
    private var partyCode: String?
    private var callsign: String = Callsign.defaultValue
    private var deviceID = BlackoutID()

    public init() {}

    public func setLocalAdvertisement(_ data: Data) {
        advertisement = data
        pipe?.setAdvertisement(data)
    }

    /// Same-code parties auto-join. No code means the radio stays down.
    public func setParty(code: String?, callsign: String, deviceID: BlackoutID) {
        let nextCode = PartyCode.isValid(code) ? code : nil
        let nextSign = Callsign.commit(callsign)
        let changed = partyCode != nextCode || self.callsign != nextSign || self.deviceID != deviceID
        partyCode = nextCode
        self.callsign = nextSign
        self.deviceID = deviceID
        if running, changed {
            stop()
            start()
        }
    }

    public func start() {
        if running { return }
        guard MeshGate.allowsTraffic(partyCode: partyCode), let partyCode else { return }
        running = true
        let localPeer = MCPeerID(displayName: callsign)
        let radio = MultipeerPipe(
            localPeer: localPeer,
            partyCode: partyCode,
            deviceID: deviceID
        )
        radio.onPeerCount = { [weak self] count in
            self?.nearbyPeerCount = count
        }
        radio.onInbound = { [weak self] event in
            self?.receive(event)
        }
        radio.onFileProgress = { [weak self] name, value in
            self?.onFileProgress?(name, value)
        }
        radio.onFileReceiveStarted = { [weak self] name in
            self?.onFileReceiveStarted?(name)
        }
        radio.onSendComplete = { [weak self] name, failed in
            self?.onSendComplete?(name, failed)
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
        guard running, MeshGate.allowsTraffic(partyCode: partyCode) else { return }
        lastOutbound = envelope
        guard let frame = MeshWire.encodeEnvelope(envelope) else { return }
        pipe?.send(frame: frame)
    }

    public func sendFile(at url: URL, named name: String) {
        guard running, MeshGate.allowsTraffic(partyCode: partyCode) else {
            onSendComplete?(name, true)
            return
        }
        pipe?.sendFile(at: url, named: name)
    }

    private func receive(_ inbound: MeshInbound) {
        lastEvent = inbound
        inboundSequence &+= 1
        onInbound?(inbound)
    }
}
