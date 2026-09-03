import Foundation

#if canImport(MultipeerConnectivity)
import MultipeerConnectivity
#endif
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

/// Party-scoped mesh over MultipeerConnectivity + BLE advertise/scan.
/// Airplane (Wi-Fi off, cell off, BT on) is the intended path. LoRa is never required.
public final class LiveMeshRadio: NSObject, MeshRadio {
    public private(set) var path: RadioPath = .none
    public static let serviceType = "blackoutmesh"

    private var partyCode = ""
    private var onPeer: ((String) -> Void)?
    private var onEnvelope: ((MeshEnvelope) -> Void)?

    #if canImport(MultipeerConnectivity)
    private var peerID: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    #endif

    #if canImport(CoreBluetooth)
    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    private var bleService: CBUUID?
    #endif

    override public init() { super.init() }

    public func start(partyCode: String, onPeer: @escaping (String) -> Void, onEnvelope: @escaping (MeshEnvelope) -> Void) {
        self.partyCode = partyCode.uppercased()
        self.onPeer = onPeer
        self.onEnvelope = onEnvelope
        startMPC()
        startBLE()
    }

    public func stop() {
        #if canImport(MultipeerConnectivity)
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        #endif
        #if canImport(CoreBluetooth)
        peripheral?.stopAdvertising()
        central?.stopScan()
        central = nil
        peripheral = nil
        bleService = nil
        #endif
        path = .none
    }

    public func send(_ env: MeshEnvelope) {
        guard let data = try? JSONEncoder().encode(env) else { return }
        #if canImport(MultipeerConnectivity)
        if let session, !session.connectedPeers.isEmpty {
            try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
        }
        #endif
        _ = data
    }

    private func startMPC() {
        #if canImport(MultipeerConnectivity)
        let name = String(partyCode.prefix(8))
        let peer = MCPeerID(displayName: name.isEmpty ? "BO" : name)
        peerID = peer
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        let info = ["c": partyCode]
        let adv = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: info, serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        let br = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        br.delegate = self
        br.startBrowsingForPeers()
        browser = br
        #endif
    }

    private func startBLE() {
        #if canImport(CoreBluetooth)
        bleService = CBUUID(nsuuid: PartyMeshUUID.uuid(for: partyCode))
        central = CBCentralManager(delegate: self, queue: .main)
        peripheral = CBPeripheralManager(delegate: self, queue: .main)
        #endif
    }

    fileprivate func markBLEPeer(_ name: String) {
        if path == .none { path = .ble }
        onPeer?(name)
    }

    fileprivate func markMPCPeer(_ name: String) {
        path = .mpc
        onPeer?(name)
    }
}

enum PartyMeshUUID {
    /// Stable across phones. Not Hasher — Hasher is process-local.
    static func uuid(for partyCode: String) -> UUID {
        let seed = Array("blackout.mesh.v1.\(partyCode.uppercased())".utf8)
        var h0: UInt64 = 0xcbf29ce484222325
        var h1: UInt64 = 0x100000001b3
        for b in seed {
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

#if canImport(MultipeerConnectivity)
extension LiveMeshRadio: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        if state == .connected { markMPCPeer(peerID.displayName) }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let env = try? JSONDecoder().decode(MeshEnvelope.self, from: data) {
            onEnvelope?(env)
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard info?["c"] == partyCode else { return }
        if let session { browser.invitePeer(peerID, to: session, withContext: nil, timeout: 12) }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
#endif

#if canImport(CoreBluetooth)
extension LiveMeshRadio: CBCentralManagerDelegate, CBPeripheralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn, let bleService else { return }
        central.scanForPeripherals(withServices: [bleService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        markBLEPeer(peripheral.name ?? "ble")
    }

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn, let bleService else { return }
        peripheral.startAdvertising([
            CBAdvertisementDataLocalNameKey: "BO",
            CBAdvertisementDataServiceUUIDsKey: [bleService],
        ])
    }
}
#endif
