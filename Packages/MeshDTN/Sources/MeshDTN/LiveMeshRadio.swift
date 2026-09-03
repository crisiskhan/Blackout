import Foundation

#if canImport(MultipeerConnectivity)
import MultipeerConnectivity
#endif
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

/// Party-scoped mesh: MPC session + BLE GATT write/notify on the same party UUID.
/// Airplane path is Bluetooth. Discovery-only scan is not a peer. LoRa never required.
public final class LiveMeshRadio: NSObject, MeshRadio {
    public private(set) var path: RadioPath = .none
    public static let serviceType = "blackoutmesh"

    private var partyCode = ""
    private var onPeer: ((String) -> Void)?
    private var onLost: ((String) -> Void)?
    private var onEnvelope: ((MeshEnvelope) -> Void)?
    private var knownPeers: Set<String> = []

    #if canImport(MultipeerConnectivity)
    private var peerID: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    #endif

    #if canImport(CoreBluetooth)
    private var central: CBCentralManager?
    private var peripheralMgr: CBPeripheralManager?
    private var serviceUUID: CBUUID?
    private var charUUID: CBUUID?
    private var envelopeChar: CBMutableCharacteristic?
    private var subscribedCentrals: [CBCentral] = []
    private var remotes: [UUID: CBPeripheral] = [:]
    private var remoteChars: [UUID: CBCharacteristic] = [:]
    private var connecting: Set<UUID> = []
    private var rxPeripheral = [UUID: BLEEnvelopeCodec.Assembler]()
    private var rxCentral = [UUID: BLEEnvelopeCodec.Assembler]()
    #endif

    override public init() { super.init() }

    public func start(
        partyCode: String,
        onPeer: @escaping (String) -> Void,
        onLost: @escaping (String) -> Void,
        onEnvelope: @escaping (MeshEnvelope) -> Void
    ) {
        stop()
        self.partyCode = partyCode.uppercased()
        self.onPeer = onPeer
        self.onLost = onLost
        self.onEnvelope = onEnvelope
        knownPeers = []
        path = .none
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
        peripheralMgr?.stopAdvertising()
        central?.stopScan()
        for p in remotes.values { central?.cancelPeripheralConnection(p) }
        central = nil
        peripheralMgr = nil
        envelopeChar = nil
        subscribedCentrals = []
        remotes = [:]
        remoteChars = [:]
        connecting = []
        rxPeripheral = [:]
        rxCentral = [:]
        #endif
        path = .none
        knownPeers = []
    }

    public func send(_ env: MeshEnvelope) {
        guard let data = try? JSONEncoder().encode(env) else { return }
        var sent = false
        #if canImport(MultipeerConnectivity)
        if let session, !session.connectedPeers.isEmpty {
            try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
            sent = true
        }
        #endif
        #if canImport(CoreBluetooth)
        let frames = BLEEnvelopeCodec.chunk(data)
        if let char = envelopeChar, let peripheralMgr, !subscribedCentrals.isEmpty {
            for frame in frames {
                _ = peripheralMgr.updateValue(frame, for: char, onSubscribedCentrals: subscribedCentrals)
            }
            sent = true
        }
        for (id, p) in remotes {
            guard let ch = remoteChars[id] else { continue }
            let w: CBCharacteristicWriteType = ch.properties.contains(.writeWithoutResponse)
                ? .withoutResponse
                : .withResponse
            for frame in frames { p.writeValue(frame, for: ch, type: w) }
            sent = true
        }
        #endif
        _ = sent
    }

    private func startMPC() {
        #if canImport(MultipeerConnectivity)
        let suffix = String(UUID().uuidString.prefix(6))
        let name = "\(String(partyCode.prefix(4)))-\(suffix)"
        let peer = MCPeerID(displayName: name)
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
        serviceUUID = CBUUID(nsuuid: PartyMeshUUID.uuid(for: partyCode))
        charUUID = CBUUID(nsuuid: PartyMeshUUID.characteristic(for: partyCode))
        central = CBCentralManager(delegate: self, queue: .main)
        peripheralMgr = CBPeripheralManager(delegate: self, queue: .main)
        #endif
    }

    fileprivate func notePeer(_ name: String) {
        if knownPeers.insert(name).inserted { onPeer?(name) }
        refreshPath()
    }

    fileprivate func dropPeer(_ name: String) {
        if knownPeers.remove(name) != nil { onLost?(name) }
        refreshPath()
    }

    fileprivate func refreshPath() {
        var mpc = false
        #if canImport(MultipeerConnectivity)
        mpc = session.map { !$0.connectedPeers.isEmpty } ?? false
        #endif
        var ble = false
        #if canImport(CoreBluetooth)
        ble = !subscribedCentrals.isEmpty || !remoteChars.isEmpty
        #endif
        if mpc { path = .mpc }
        else if ble { path = .ble }
        else { path = .none }
    }

    fileprivate func acceptEnvelope(_ data: Data) {
        if let env = try? JSONDecoder().decode(MeshEnvelope.self, from: data) {
            onEnvelope?(env)
        }
    }
}

#if canImport(MultipeerConnectivity)
extension LiveMeshRadio: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            notePeer(peerID.displayName)
        case .notConnected:
            dropPeer(peerID.displayName)
        case .connecting:
            break
        @unknown default:
            break
        }
        refreshPath()
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        acceptEnvelope(data)
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
extension LiveMeshRadio: CBCentralManagerDelegate, CBPeripheralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn, let serviceUUID else { return }
        central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        if remotes[id] != nil || remoteChars[id] != nil || connecting.contains(id) { return }
        connecting.insert(id)
        remotes[id] = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connecting.remove(peripheral.identifier)
        remotes[peripheral.identifier] = peripheral
        guard let serviceUUID else { return }
        peripheral.discoverServices([serviceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connecting.remove(peripheral.identifier)
        remotes.removeValue(forKey: peripheral.identifier)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        remotes.removeValue(forKey: id)
        remoteChars.removeValue(forKey: id)
        rxPeripheral.removeValue(forKey: id)
        connecting.remove(id)
        dropPeer(id.uuidString)
        refreshPath()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let serviceUUID, let svc = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        if let charUUID { peripheral.discoverCharacteristics([charUUID], for: svc) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let charUUID, let ch = service.characteristics?.first(where: { $0.uuid == charUUID }) else { return }
        remotes[peripheral.identifier] = peripheral
        peripheral.setNotifyValue(true, for: ch)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.isNotifying else { return }
        remoteChars[peripheral.identifier] = characteristic
        notePeer(peripheral.identifier.uuidString)
        refreshPath()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let chunk = characteristic.value else { return }
        var asm = rxPeripheral[peripheral.identifier] ?? BLEEnvelopeCodec.Assembler()
        if let full = asm.push(chunk) { acceptEnvelope(full) }
        rxPeripheral[peripheral.identifier] = asm
    }

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn, let serviceUUID, let charUUID else { return }
        let ch = CBMutableCharacteristic(
            type: charUUID,
            properties: [.write, .writeWithoutResponse, .notify],
            value: nil,
            permissions: [.writeable, .readable]
        )
        envelopeChar = ch
        let svc = CBMutableService(type: serviceUUID, primary: true)
        svc.characteristics = [ch]
        peripheral.removeAllServices()
        peripheral.add(svc)
        peripheral.startAdvertising([
            CBAdvertisementDataLocalNameKey: "BO",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
        ])
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
            subscribedCentrals.append(central)
        }
        notePeer(central.identifier.uuidString)
        refreshPath()
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
        dropPeer(central.identifier.uuidString)
        refreshPath()
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if let chunk = req.value {
                var asm = rxCentral[req.central.identifier] ?? BLEEnvelopeCodec.Assembler()
                if let full = asm.push(chunk) { acceptEnvelope(full) }
                rxCentral[req.central.identifier] = asm
            }
            peripheral.respond(to: req, withResult: .success)
        }
    }
}
#endif
