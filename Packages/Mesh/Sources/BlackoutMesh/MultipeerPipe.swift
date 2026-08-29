import Foundation
import MultipeerConnectivity

/// Apple Multipeer radio. Wi-Fi / Bluetooth peer-to-peer — local only, no WAN.
/// 1/N: at most one connected peer. Discovery is local Bonjour + P2P only.
final class MultipeerPipe: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    private let localPeer: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser
    private var advertisement: Data = Data()
    private var running = false

    var onPeerCount: ((Int) -> Void)?
    var onInbound: ((MeshInbound) -> Void)?

    init(localPeer: MCPeerID) {
        self.localPeer = localPeer
        session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(
            peer: localPeer,
            discoveryInfo: nil,
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
        _ = (resourceName, peerID, progress)
    }

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        _ = (resourceName, peerID, localURL, error)
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        _ = (peerID, context)
        if session.connectedPeers.isEmpty {
            invitationHandler(true, session)
        } else {
            invitationHandler(false, nil)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        _ = info
        guard session.connectedPeers.isEmpty else { return }
        // One side invites so both phones do not double-handshake.
        guard localPeer.displayName < peerID.displayName else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 12)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        _ = peerID
    }
}
