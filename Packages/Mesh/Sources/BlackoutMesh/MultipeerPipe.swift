import BlackoutCore
import Foundation
import MultipeerConnectivity

/// Apple Multipeer radio. Wi-Fi / Bluetooth peer-to-peer — local only, no WAN.
/// 1/N: at most one connected peer. Discovery is local Bonjour + P2P only.
final class MultipeerPipe: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    private let localPeer: MCPeerID
    private let partyCode: String
    private let deviceID: BlackoutID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser
    private var advertisement: Data = Data()
    private var running = false

    var onPeerCount: ((Int) -> Void)?
    var onInbound: ((MeshInbound) -> Void)?
    var onFileProgress: ((String, Double) -> Void)?
    var onFileReceiveStarted: ((String) -> Void)?
    var onSendComplete: ((String, Bool) -> Void)?
    private var progressObservations: [String: NSKeyValueObservation] = [:]

    init(localPeer: MCPeerID, partyCode: String, deviceID: BlackoutID) {
        self.localPeer = localPeer
        self.partyCode = partyCode
        self.deviceID = deviceID
        session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(
            peer: localPeer,
            discoveryInfo: MeshRadio.discoveryInfo(partyCode: partyCode, deviceID: deviceID),
            serviceType: MeshRadio.serviceType
        )
        browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: MeshRadio.serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        guard !running else { return }
        running = true
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        running = false
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        publishCount()
    }

    func setAdvertisement(_ data: Data) {
        advertisement = data
        flushAdvertisement()
    }

    func send(frame: Data) {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }
        _ = try? session.send(frame, toPeers: peers, with: .reliable)
    }

    func sendFile(at url: URL, named name: String) {
        guard MeshRadio.isSafeResourceName(name) else {
            Task { @MainActor [onSendComplete] in onSendComplete?(name, true) }
            return
        }
        guard let peer = session.connectedPeers.first else {
            Task { @MainActor [onSendComplete] in onSendComplete?(name, true) }
            return
        }
        let progress = session.sendResource(at: url, withName: name, toPeer: peer) { [weak self] error in
            Task { @MainActor [weak self] in
                self?.progressObservations[name] = nil
                self?.onSendComplete?(name, error != nil)
            }
        }
        observe(progress, name: name)
    }

    private func observe(_ progress: Progress?, name: String) {
        guard let progress else { return }
        progressObservations[name] = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] item, _ in
            let value = item.fractionCompleted
            Task { @MainActor [weak self] in
                self?.onFileProgress?(name, value)
            }
        }
    }

    private func flushAdvertisement() {
        guard !advertisement.isEmpty, !session.connectedPeers.isEmpty else { return }
        send(frame: MeshWire.encodeAdvertisement(advertisement))
    }

    private func publishCount() {
        let count = min(session.connectedPeers.count, 1)
        Task { @MainActor [onPeerCount] in
            onPeerCount?(count)
        }
    }

    private func deliver(_ inbound: MeshInbound) {
        Task { @MainActor [onInbound] in
            onInbound?(inbound)
        }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        _ = peerID
        publishCount()
        if state == .connected {
            flushAdvertisement()
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        _ = peerID
        guard let inbound = MeshWire.decode(data) else { return }
        deliver(inbound)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        _ = (stream, streamName, peerID)
    }

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        _ = peerID
        guard MeshRadio.isSafeResourceName(resourceName) else { return }
        Task { @MainActor [onFileReceiveStarted] in
            onFileReceiveStarted?(resourceName)
        }
        observe(progress, name: resourceName)
    }

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        _ = peerID
        progressObservations[resourceName] = nil
        guard MeshRadio.isSafeResourceName(resourceName) else { return }
        if error != nil || localURL == nil {
            return
        }
        // MCSession deletes the temp file after this returns. Copy first.
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("blackout-relay-\(resourceName).zip")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: localURL!, to: dest)
            deliver(.resource(name: resourceName, fileURL: dest))
        } catch {
            return
        }
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        _ = peerID
        let invitedCode = context.flatMap { String(data: $0, encoding: .utf8) }
        let sameParty = invitedCode == nil || invitedCode == partyCode
        if sameParty, session.connectedPeers.isEmpty {
            invitationHandler(true, session)
        } else {
            invitationHandler(false, nil)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard MeshRadio.matchesParty(info, partyCode: partyCode) else { return }
        guard session.connectedPeers.isEmpty else { return }
        // One side invites so both phones do not double-handshake.
        guard MeshRadio.shouldInvite(
            localID: deviceID,
            peerInfo: info,
            peerDisplayName: peerID.displayName
        ) else { return }
        let context = partyCode.data(using: .utf8)
        browser.invitePeer(peerID, to: session, withContext: context, timeout: 12)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        _ = peerID
    }
}
