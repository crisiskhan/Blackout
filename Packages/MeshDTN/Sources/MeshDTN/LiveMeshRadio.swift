import Foundation

#if canImport(MultipeerConnectivity)
import MultipeerConnectivity
#endif
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

/// Party-scoped mesh: MPC session + BLE GATT write/notify on the same party UUID.
/// A fixed hop UUID carries store through any Blackout phone. Open scan hears
/// every radio and probes ones that can answer hop GATT.
/// Discovery-only scan is not a peer. LoRa never required.
public final class LiveMeshRadio: NSObject, MeshRadio {
    public private(set) var path: RadioPath = .none
    public static let serviceType = "blackoutmesh"
    public var onHear: ((MeshHear) -> Void)?
    public var onHop: ((String) -> Void)?
    public var onHopLost: ((String) -> Void)?
    public var carry: (() -> [MeshEnvelope])?

    private var partyCode = ""
    private var onPeer: ((String) -> Void)?
    private var onLost: ((String) -> Void)?
    private var onEnvelope: ((MeshEnvelope) -> Void)?
    private var knownPeers: Set<String> = []
    private var knownHops: Set<String> = []

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
    private var hopUUID: CBUUID?
    private var hopCharUUID: CBUUID?
    private var envelopeChar: CBMutableCharacteristic?
    private var hopEnvelopeChar: CBMutableCharacteristic?
    private var subscribedCentrals: [CBCentral] = []
    private var hopCentrals: [CBCentral] = []
    private var remotes: [UUID: CBPeripheral] = [:]
    private var remoteChars: [UUID: CBCharacteristic] = [:]
    private var hopRemotes: [UUID: CBPeripheral] = [:]
    private var hopChars: [UUID: CBCharacteristic] = [:]
    private var connecting: Set<UUID> = []
    private var hopConnecting: Set<UUID> = []
    private var probedClosed: Set<UUID> = []
    private var rxPeripheral = [UUID: BLEEnvelopeCodec.Assembler]()
    private var rxCentral = [UUID: BLEEnvelopeCodec.Assembler]()
    #endif

    override public init() { super.init() }

    public func start(
        partyCode: String,
        join: Bool,
        onPeer: @escaping (String) -> Void,
        onLost: @escaping (String) -> Void,
        onEnvelope: @escaping (MeshEnvelope) -> Void
    ) {
        stop()
        self.partyCode = join ? partyCode.uppercased() : ""
        self.onPeer = onPeer
        self.onLost = onLost
        self.onEnvelope = onEnvelope
        knownPeers = []
        knownHops = []
        path = .none
        if join, !self.partyCode.isEmpty {
            startMPC()
        }
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
        for p in hopRemotes.values { central?.cancelPeripheralConnection(p) }
        central = nil
        peripheralMgr = nil
        envelopeChar = nil
        hopEnvelopeChar = nil
        subscribedCentrals = []
        hopCentrals = []
        remotes = [:]
        remoteChars = [:]
        hopRemotes = [:]
        hopChars = [:]
        connecting = []
        hopConnecting = []
        probedClosed = []
        rxPeripheral = [:]
        rxCentral = [:]
        #endif
        path = .none
        knownPeers = []
        knownHops = []
    }

    public func send(_ env: MeshEnvelope) {
        guard let data = try? JSONEncoder().encode(env) else { return }
        var sent = false
        #if canImport(MultipeerConnectivity)
        if let session {
            let peers: [MCPeerID]
            if env.to == "*" {
                peers = session.connectedPeers
            } else {
                peers = session.connectedPeers.filter { $0.displayName == env.to }
            }
            if !peers.isEmpty {
                try? session.send(data, toPeers: peers, with: .reliable)
                sent = true
            }
        }
        #endif
        #if canImport(CoreBluetooth)
        let frames = BLEEnvelopeCodec.chunk(data)
        if let char = envelopeChar, let peripheralMgr {
            let dests: [CBCentral]
            if env.to == "*" {
                dests = subscribedCentrals
            } else {
                dests = subscribedCentrals.filter { $0.identifier.uuidString == env.to }
            }
            if !dests.isEmpty {
                for frame in frames {
                    _ = peripheralMgr.updateValue(frame, for: char, onSubscribedCentrals: dests)
                }
                sent = true
            }
        }
        for (id, p) in remotes {
            if env.to != "*" && id.uuidString != env.to { continue }
            guard let ch = remoteChars[id] else { continue }
            write(frames, on: p, char: ch)
            sent = true
        }
        if env.kind != "voice" {
            if let char = hopEnvelopeChar, let peripheralMgr, !hopCentrals.isEmpty {
                for frame in frames {
                    _ = peripheralMgr.updateValue(frame, for: char, onSubscribedCentrals: hopCentrals)
                }
                sent = true
            }
            for (id, p) in hopRemotes {
                guard let ch = hopChars[id] else { continue }
                write(frames, on: p, char: ch)
                sent = true
            }
        }
        #endif
        _ = sent
    }

    #if canImport(CoreBluetooth)
    private func write(_ frames: [Data], on peripheral: CBPeripheral, char: CBCharacteristic) {
        let w: CBCharacteristicWriteType = char.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse
        for frame in frames { peripheral.writeValue(frame, for: char, type: w) }
    }
    #endif

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
        if !partyCode.isEmpty {
            serviceUUID = CBUUID(nsuuid: PartyMeshUUID.uuid(for: partyCode))
            charUUID = CBUUID(nsuuid: PartyMeshUUID.characteristic(for: partyCode))
        } else {
            serviceUUID = nil
            charUUID = nil
        }
        hopUUID = CBUUID(nsuuid: PartyMeshUUID.hopService())
        hopCharUUID = CBUUID(nsuuid: PartyMeshUUID.hopCharacteristic())
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
        var hop = false
        #if canImport(CoreBluetooth)
        ble = !subscribedCentrals.isEmpty || !remoteChars.isEmpty
        hop = !hopCentrals.isEmpty || !hopChars.isEmpty
        #endif
        if mpc { path = .mpc }
        else if ble { path = .ble }
        else if hop { path = .hop }
        else { path = .none }
    }

    fileprivate func noteHopPeer(_ name: String) {
        if knownHops.insert(name).inserted { onHop?(name) }
        refreshPath()
        replayCarry()
    }

    fileprivate func dropHopPeer(_ name: String) {
        if knownHops.remove(name) != nil { onHopLost?(name) }
        refreshPath()
    }

    fileprivate func replayCarry() {
        guard let carry else { return }
        for env in carry() { send(env) }
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
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? ""
        let services = (
            (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        ) + (
            (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []
        )
        let mfg = MeshPresence.manufacturerID(
            advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        )
        var labels = services.map(\.uuidString)
        if hopUUID.map({ services.contains($0) }) == true || name == "BO" {
            labels.append("hop")
        }
        let partyHit = serviceUUID.map { services.contains($0) } ?? false
        let hopHit = hopUUID.map { services.contains($0) } ?? false || name == "BO"
        let tx = (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
        let link = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        if !partyHit {
            onHear?(
                MeshHear(
                    id: id.uuidString,
                    name: name,
                    kind: MeshPresence.classify(name: name, manufacturer: mfg, services: labels),
                    rssi: RSSI.intValue,
                    manufacturer: mfg,
                    services: labels,
                    txPower: tx,
                    connectable: link
                )
            )
        }
        if partyHit, remotes[id] == nil, remoteChars[id] == nil, !connecting.contains(id) {
            connecting.insert(id)
            remotes[id] = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
            return
        }
        if hopHit, hopRemotes[id] == nil, hopChars[id] == nil, !hopConnecting.contains(id), !partyHit {
            hopConnecting.insert(id)
            hopRemotes[id] = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
            return
        }
        let probing = MeshPresence.shouldProbe(name: name, services: labels)
            && !probedClosed.contains(id)
            && hopRemotes[id] == nil
            && hopChars[id] == nil
            && !hopConnecting.contains(id)
            && remotes[id] == nil
            && !connecting.contains(id)
            && hopConnecting.count < MeshPresence.probeCap
        if probing {
            hopConnecting.insert(id)
            hopRemotes[id] = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connecting.remove(peripheral.identifier)
        hopConnecting.remove(peripheral.identifier)
        let want: [CBUUID] = [serviceUUID, hopUUID].compactMap { $0 }
        guard !want.isEmpty else { return }
        peripheral.discoverServices(want)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connecting.remove(peripheral.identifier)
        hopConnecting.remove(peripheral.identifier)
        remotes.removeValue(forKey: peripheral.identifier)
        hopRemotes.removeValue(forKey: peripheral.identifier)
        probedClosed.insert(peripheral.identifier)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        remotes.removeValue(forKey: id)
        remoteChars.removeValue(forKey: id)
        hopRemotes.removeValue(forKey: id)
        hopChars.removeValue(forKey: id)
        rxPeripheral.removeValue(forKey: id)
        connecting.remove(id)
        hopConnecting.remove(id)
        dropPeer(id.uuidString)
        dropHopPeer(id.uuidString)
        refreshPath()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        var found = false
        if let serviceUUID, let svc = peripheral.services?.first(where: { $0.uuid == serviceUUID }) {
            found = true
            remotes[peripheral.identifier] = peripheral
            if let charUUID { peripheral.discoverCharacteristics([charUUID], for: svc) }
        }
        if let hopUUID, let svc = peripheral.services?.first(where: { $0.uuid == hopUUID }) {
            found = true
            hopRemotes[peripheral.identifier] = peripheral
            if let hopCharUUID { peripheral.discoverCharacteristics([hopCharUUID], for: svc) }
        }
        if !found {
            probedClosed.insert(peripheral.identifier)
            hopConnecting.remove(peripheral.identifier)
            connecting.remove(peripheral.identifier)
            hopRemotes.removeValue(forKey: peripheral.identifier)
            remotes.removeValue(forKey: peripheral.identifier)
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let charUUID, let ch = service.characteristics?.first(where: { $0.uuid == charUUID }) {
            remotes[peripheral.identifier] = peripheral
            peripheral.setNotifyValue(true, for: ch)
        }
        if let hopCharUUID, let ch = service.characteristics?.first(where: { $0.uuid == hopCharUUID }) {
            hopRemotes[peripheral.identifier] = peripheral
            peripheral.setNotifyValue(true, for: ch)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.isNotifying else { return }
        if characteristic.uuid == hopCharUUID {
            hopChars[peripheral.identifier] = characteristic
            noteHopPeer(peripheral.identifier.uuidString)
            return
        }
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
        guard peripheral.state == .poweredOn, let hopUUID, let hopCharUUID else { return }
        peripheral.removeAllServices()
        var advertised: [CBUUID] = []
        if let serviceUUID, let charUUID {
            let ch = CBMutableCharacteristic(
                type: charUUID,
                properties: [.write, .writeWithoutResponse, .notify],
                value: nil,
                permissions: [.writeable, .readable]
            )
            envelopeChar = ch
            let svc = CBMutableService(type: serviceUUID, primary: true)
            svc.characteristics = [ch]
            peripheral.add(svc)
            advertised.append(serviceUUID)
        }
        let hopCh = CBMutableCharacteristic(
            type: hopCharUUID,
            properties: [.write, .writeWithoutResponse, .notify],
            value: nil,
            permissions: [.writeable, .readable]
        )
        hopEnvelopeChar = hopCh
        let hopSvc = CBMutableService(type: hopUUID, primary: true)
        hopSvc.characteristics = [hopCh]
        peripheral.add(hopSvc)
        advertised.append(hopUUID)
        peripheral.startAdvertising([
            CBAdvertisementDataLocalNameKey: "BO",
            CBAdvertisementDataServiceUUIDsKey: advertised,
        ])
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == hopCharUUID {
            if !hopCentrals.contains(where: { $0.identifier == central.identifier }) {
                hopCentrals.append(central)
            }
            noteHopPeer(central.identifier.uuidString)
            return
        }
        if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
            subscribedCentrals.append(central)
        }
        notePeer(central.identifier.uuidString)
        refreshPath()
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if characteristic.uuid == hopCharUUID {
            hopCentrals.removeAll { $0.identifier == central.identifier }
            dropHopPeer(central.identifier.uuidString)
            return
        }
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
