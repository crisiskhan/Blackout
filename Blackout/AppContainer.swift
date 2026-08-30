import BlackoutBattery
import BlackoutCore
import BlackoutCrypto
import BlackoutLocation
import BlackoutMesh
import BlackoutPacks
import BlackoutPersistence
import Foundation
import Maps
import Observation
import Settings
import UIKit

@MainActor
@Observable
final class AppContainer {
    let persistence: any PersistenceServing
    let crypto: any CryptoServing
    let location: LocationService
    let mesh: MeshFacade
    let battery: BatteryService
    let pack: FileMapPack
    let packs: PackStore
    let lock: AppLockService
    let bootError: String?
    var sosConfirmRequested = false
    var sosCoverOpen = false
    var showFieldPacks = false
    let guidePackURL: URL?
    let identity: LocalIdentityStore
    let party: PartyRoster
    private var missedCheckInTask: Task<Void, Never>?
    private var signaledMissedCheckIns: Set<String> = []

    init() {
        var errors: [String] = []
        let opened: any PersistenceServing
        do {
            opened = try PersistenceService()
        } catch {
            opened = UnavailablePersistence()
            errors.append(error.localizedDescription)
        }
        persistence = opened

        let cryptoOpened: any CryptoServing
        do {
            cryptoOpened = try LoopbackCrypto()
        } catch {
            cryptoOpened = UnavailableCrypto()
            errors.append("Crypto keychain: \(error.localizedDescription). Old ciphertext will not be opened with a new identity.")
        }
        crypto = cryptoOpened

        location = LocationService()
        mesh = MeshFacade()
        battery = BatteryService()
        lock = AppLockService()
        pack = FileMapPack(rootURL: Self.packRoot())
        packs = PackStore(bundledRoot: Self.packRoot(), bundledPacksRoot: Self.fieldPacksRoot())
        guidePackURL = Self.guidePackRoot()
        if pack.pack == nil || !packs.bundledIsReady {
            errors.append("DefaultPack missing from the app bundle. Map shows the honest no-pack canvas.")
        }
        if guidePackURL == nil {
            errors.append("GuidePack missing from the app bundle. Field ask cannot retrieve.")
        }
        bootError = errors.isEmpty ? nil : errors.joined(separator: "\n\n")
        identity = LocalIdentityStore(deviceID: crypto.localIdentity)
        party = PartyRoster(
            localID: identity.deviceID,
            recipientID: crypto.preferredRecipient,
            identity: identity
        )
        mesh.setLocalAdvertisement(crypto.localAdvertisement)
        mesh.setParty(code: identity.partyCode, callsign: identity.callsign, deviceID: identity.deviceID)
        mesh.onInbound = { [weak self] event in
            self?.handleMeshInbound(event)
        }
        mesh.onFileProgress = { [weak self] name, value in
            self?.packs.updateRelayProgress(name, value)
        }
        mesh.onFileReceiveStarted = { [weak self] name in
            self?.packs.noteReceiving(name)
        }
        mesh.onSendComplete = { [weak self] name, failed in
            self?.packs.finishRelaySend(name, failed: failed)
        }
        location.applyPolicy(battery.policy)
        if battery.isCritical {
            location.stopUpdating()
            mesh.stop()
        } else {
            location.startUpdating()
            syncMeshToParty()
        }
        startMissedCheckInWatch()
    }

    func syncMeshToParty() {
        mesh.setParty(code: identity.partyCode, callsign: identity.callsign, deviceID: identity.deviceID)
        if battery.isCritical || !MeshGate.allowsTraffic(partyCode: identity.partyCode) {
            mesh.stop()
        } else {
            mesh.start()
        }
    }

    func commitCallsign(_ raw: String) {
        _ = party.commitCallsign(raw)
        syncMeshToParty()
        if let envelope = party.broadcastSelf(fix: location.navigationFix) {
            sendPartyStatus(envelope)
        }
    }

    func createParty() {
        _ = party.createParty()
        syncMeshToParty()
    }

    func joinParty(_ code: String) -> Bool {
        let ok = party.joinParty(code)
        if ok {
            syncMeshToParty()
        }
        return ok
    }

    func leaveParty() {
        party.leaveParty()
        mesh.stop()
    }

    /// Composition root only. Mesh stays a dumb pipe; Crypto and Persistence stay in their kits.
    func handleMeshInbound(_ event: MeshInbound) {
        switch event {
        case .advertisement(let data):
            crypto.registerPeerAdvertisement(data)
            party.recipientID = crypto.preferredRecipient
        case .envelope(let envelope):
            ingestEnvelope(envelope)
        case .resource(let name, let fileURL):
            packs.installRelayedZip(id: name, zipURL: fileURL)
        }
    }

    func relayPack(_ id: String) {
        guard mesh.nearbyPeerCount > 0 else {
            packs.noteRelayBlocked(id)
            return
        }
        do {
            let url = try packs.prepareRelayZip(id)
            packs.beginRelaySend(id)
            mesh.sendFile(at: url, named: id)
        } catch {
            packs.finishRelaySend(id, failed: true)
        }
    }

    func sendPartyStatus(_ envelope: Envelope) {
        guard mesh.nearbyPeerCount > 0 else { return }
        mesh.send(envelope)
    }

    private func ingestEnvelope(_ envelope: Envelope) {
        switch envelope.kind {
        case .partyStatus:
            ingestPartyStatus(envelope)
        case .message:
            ingestMessage(envelope)
        case .sosAlert, .pttClip, .locationFix, .breadcrumb:
            return
        }
    }

    private func ingestPartyStatus(_ envelope: Envelope) {
        switch party.ingest(envelope) {
        case .becameRed:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .ignored, .updated:
            break
        }
    }

    private func ingestMessage(_ envelope: Envelope) {
        guard envelope.sender != crypto.localIdentity else { return }
        do {
            let existing = try persistence.messages()
            if existing.contains(where: { $0.id == envelope.id }) { return }
            try persistence.saveMessage(
                MessageRecordDTO(
                    id: envelope.id,
                    createdAt: envelope.timestamp,
                    ciphertext: envelope.ciphertext,
                    status: .onMesh,
                    senderID: envelope.sender,
                    recipientID: envelope.recipient
                )
            )
        } catch {
            return
        }
    }

    /// Lives on the composition root so a missed check-in can open SOS confirm
    /// without Expedition (or any tab) staying mounted. Never auto-arms.
    private func startMissedCheckInWatch() {
        missedCheckInTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.pollMissedCheckIns()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private func pollMissedCheckIns() {
        let items: [ExpeditionRecordDTO]
        do {
            items = try persistence.expeditions()
        } catch {
            return
        }
        let now = Date()
        for item in items where item.isOpen && item.checkInEnabled {
            let last = item.lastCheckInAt ?? item.createdAt
            let overdue = now.timeIntervalSince(last) > Double(max(60, item.checkInIntervalSeconds))
            let key = item.id.rawValue.uuidString
            if overdue {
                if !signaledMissedCheckIns.contains(key) {
                    signaledMissedCheckIns.insert(key)
                    sosConfirmRequested = true
                }
            } else {
                signaledMissedCheckIns.remove(key)
            }
        }
    }

    static func packRoot() -> URL? {
        locateFolder("DefaultPack")
    }

    static func fieldPacksRoot() -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("FieldPacks", isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent("FieldPacks", isDirectory: true)
        ]
        for candidate in candidates {
            guard let candidate else { continue }
            let hasStatewide = FieldPackCatalog.bundledStatewide.contains { pack in
                fileManager.fileExists(
                    atPath: candidate.appendingPathComponent(pack.id, isDirectory: true)
                        .appendingPathComponent("manifest.json").path
                )
            }
            if hasStatewide { return candidate }
        }
        return nil
    }

    static func guidePackRoot() -> URL? {
        locateFolder("GuidePack")
    }

    private static func locateFolder(_ name: String) -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: name)?.deletingLastPathComponent(),
            Bundle.main.resourceURL?.appendingPathComponent(name, isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent(name, isDirectory: true)
        ]
        for candidate in candidates {
            guard let candidate else { continue }
            let manifest = candidate.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifest.path) else { continue }
            if name == "DefaultPack", !MapPackLayout.containsTilePNGs(root: candidate) {
                continue
            }
            return candidate
        }
        return nil
    }
}
