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
    public private(set) var isRunning = false

    public var onInbound: ((MeshInbound) -> Void)?
    public var onNearbyCount: ((Int) -> Void)?
    public var onFileProgress: ((String, Double) -> Void)?
    public var onFileReceiveStarted: ((String) -> Void)?
    public var onSendComplete: ((String, Bool) -> Void)?

    private var advertisement: Data = Data()
    private var pipe: MultipeerPipe?
    private var partyCode: String?
    private var callsign: String = Callsign.defaultValue
    private var deviceID = BlackoutID()
    let storeQueue: StoreAndForwardQueue

    public init(storeURL: URL? = nil) {
        storeQueue = StoreAndForwardQueue(fileURL: storeURL ?? Self.defaultStoreURL())
    }

    private static func defaultStoreURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("blackout-store-forward.json")
    }

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
        if isRunning, changed {
            stop()
            start()
        }
    }

    public func start() {
        if isRunning { return }
        guard MeshGate.allowsTraffic(partyCode: partyCode), let partyCode else { return }
        isRunning = true
        let localPeer = MCPeerID(displayName: Callsign.radioName(callsign, id: deviceID))
        let radio = MultipeerPipe(
            localPeer: localPeer,
            partyCode: partyCode,
            deviceID: deviceID
        )
        radio.onPeerCount = { [weak self] count in
            self?.nearbyPeerCount = count
            self?.onNearbyCount?(count)
            if count > 0 {
                self?.flushStore()
            }
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
        isRunning = false
        pipe?.stop()
        pipe = nil
        nearbyPeerCount = 0
    }

    @discardableResult
    public func send(_ envelope: Envelope) -> MeshSendResult {
        lastOutbound = envelope
        guard let frame = MeshWire.encodeEnvelope(envelope) else { return .failed }
        storeQueue.noteOutbound(envelope)
        guard isRunning, MeshGate.allowsTraffic(partyCode: partyCode) else { return .notRunning }
        guard nearbyPeerCount > 0 else { return .noPeers }
        guard pipe?.send(frame: frame) == true else { return .failed }
        return .sent
    }

    @discardableResult
    public func sendPTTFrame(_ payload: Data) -> Bool {
        guard isRunning, MeshGate.allowsTraffic(partyCode: partyCode), nearbyPeerCount > 0 else {
            return false
        }
        return pipe?.send(frame: MeshWire.encodePTTFrame(payload), reliable: false) == true
    }

    public func sendFile(at url: URL, named name: String) {
        guard isRunning, MeshGate.allowsTraffic(partyCode: partyCode) else {
            onSendComplete?(name, true)
            return
        }
        pipe?.sendFile(at: url, named: name)
    }

    private func receive(_ inbound: MeshInbound) {
        if case .envelope(let envelope) = inbound {
            switch storeQueue.acceptInbound(envelope) {
            case .duplicate:
                return
            case .deliverAndForward(let next):
                lastEvent = .envelope(next)
                onInbound?(.envelope(next))
                inboundSequence &+= 1
                if nearbyPeerCount > 0, let frame = MeshWire.encodeEnvelope(next) {
                    _ = pipe?.send(frame: frame)
                }
                return
            }
        }
        lastEvent = inbound
        onInbound?(inbound)
        inboundSequence &+= 1
    }

    private func flushStore() {
        guard isRunning, nearbyPeerCount > 0 else { return }
        for envelope in storeQueue.flushPending() {
            guard let frame = MeshWire.encodeEnvelope(envelope) else { continue }
            _ = pipe?.send(frame: frame)
        }
    }
}
