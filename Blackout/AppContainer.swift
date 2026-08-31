import BlackoutBattery
import BlackoutCore
import BlackoutCrypto
import BlackoutLocation
import BlackoutMesh
import BlackoutPacks
import BlackoutPersistence
import Foundation
import Maps
import Messaging
import Observation
import Settings
import UIKit
import VoicePTT

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
    let suppressPersistedArmedAutoPresent: Bool
    let guidePackURL: URL?
    let identity: LocalIdentityStore
    let party: PartyRoster
    let outbox: CommsOutbox
    let ptt: LivePTTHub
    let radios = MeshRadioProbe()
    var latestInbound: LatestInboundPing?
    var navLockActive = false
    var radioBanner = MeshRadioBannerPolicy()
    var fieldMode: FieldJobMode?
    var inboundGuideID: String?
    var inboundGuideMissing = false
    var inboundGuideMissingNeedsPack = false
    var leaveBehindRelay = UserDefaults.standard.bool(forKey: BlackoutKeys.leaveBehindRelay)
    var nightRed = UserDefaults.standard.bool(forKey: BlackoutKeys.mapNightRed)
    var sharedTrack: [FollowTrackWire.Point] = []
    private var missedCheckInTask: Task<Void, Never>?
    private var signaledMissedCheckIns: Set<String> = []
    private var lastNearbyCount = 0

    init() {
        let build = SOSArmedRestore.currentBuild()
        let lastSeen = UserDefaults.standard.string(forKey: BlackoutKeys.sosLastSeenBuild)
        suppressPersistedArmedAutoPresent = SOSArmedRestore.isNewBinaryLaunch(
            currentBuild: build,
            lastSeenBuild: lastSeen
        )
        UserDefaults.standard.set(build, forKey: BlackoutKeys.sosLastSeenBuild)
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
        if !packs.bundledIsReady {
            if packs.packOnDisk(FieldPackCatalog.denver.id) != nil {
                errors.append(MapPackLayout.tooNewCopy)
            } else {
                errors.append("DefaultPack missing from the app bundle. Map shows the honest no-pack canvas.")
            }
        }
        if let guidePackURL,
           let json = MapPackLayout.readManifestJSON(root: guidePackURL),
           GuidePackSchema.inspect(manifest: json, articles: [], inverted: [:]) == .tooNew {
            errors.append(GuidePackSchema.tooNewCopy)
        } else if guidePackURL == nil {
            errors.append("GuidePack missing from the app bundle. Field ask cannot retrieve.")
        }
        bootError = errors.isEmpty ? nil : errors.joined(separator: "\n\n")
        identity = LocalIdentityStore(deviceID: crypto.localIdentity)
        party = PartyRoster(
            localID: identity.deviceID,
            recipientID: crypto.preferredRecipient,
            identity: identity
        )
        crypto.setPartyCode(identity.partyCode)
        let meshRef = mesh
        let cryptoRef = crypto
        let persistenceRef = persistence
        outbox = CommsOutbox(
            persistence: persistenceRef,
            crypto: cryptoRef,
            transmit: { meshRef.send($0) },
            meshState: { (meshRef.isRunning, meshRef.nearbyPeerCount) }
        )
        ptt = LivePTTHub()
        ptt.bindSender { meshRef.sendPTTFrame($0) }
        ptt.extremeSaver = battery.isExtremeSaver
        radioBanner.dismissed = UserDefaults.standard.bool(forKey: BlackoutKeys.meshRadioBannerDismissed)
        ptt.installRemoteCommands { [ptt, mesh, identity] in
            ptt.decision(
                nearbyPeerCount: mesh.nearbyPeerCount,
                partyCode: identity.partyCode,
                meshRunning: mesh.isRunning
            )
        }
        PTTIntentBridge.bind(hub: ptt)
        mesh.setLocalAdvertisement(crypto.localAdvertisement)
        mesh.setParty(code: identity.partyCode, callsign: identity.callsign, deviceID: identity.deviceID)
        mesh.onInbound = { [weak self] event in
            self?.handleMeshInbound(event)
        }
        mesh.onNearbyCount = { [weak self] count in
            self?.broadcastSelfIfRadioUp(count)
            self?.flushQueuedIfPeerAppeared(count)
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
            packs.setDownloadsAllowed(false)
            location.stopUpdating()
            mesh.stop()
            ptt.stop()
        }
        startMissedCheckInWatch()
    }

    func syncMeshToParty() {
        radios.start()
        crypto.setPartyCode(identity.partyCode)
        mesh.setParty(code: identity.partyCode, callsign: identity.callsign, deviceID: identity.deviceID)
        ptt.extremeSaver = battery.isExtremeSaver
        if battery.isCritical || !MeshGate.allowsTraffic(partyCode: identity.partyCode) {
            mesh.stop()
            ptt.stop()
        } else {
            mesh.start()
            broadcastSelfIfRadioUp(mesh.nearbyPeerCount)
        }
        refreshLiveActivity()
        applyIdleTimer()
    }

    private func broadcastSelfIfRadioUp(_ count: Int) {
        guard count > 0 else { return }
        if let envelope = party.broadcastSelf(fix: location.navigationFix) {
            sendPartyStatus(envelope)
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
        setLeaveBehindRelay(false)
        mesh.stop()
        LiveActivityHub.end(newBinaryLaunch: suppressPersistedArmedAutoPresent)
        latestInbound = nil
        applyIdleTimer()
    }

    var hasOpenExpedition: Bool {
        (try? persistence.expeditions().contains(where: \.isOpen)) ?? false
    }

    var openExpeditionID: String? {
        (try? persistence.expeditions().first(where: \.isOpen))?.id.rawValue.uuidString
    }

    func setLeaveBehindRelay(_ on: Bool) {
        if LeaveBehindRelayPolicy.shouldStop(leaveOrEnd: !hasOpenExpedition, batteryCritical: battery.isCritical) {
            leaveBehindRelay = false
        } else {
            leaveBehindRelay = on
        }
        UserDefaults.standard.set(leaveBehindRelay, forKey: BlackoutKeys.leaveBehindRelay)
        applyIdleTimer()
    }

    func setNightRed(_ on: Bool) {
        nightRed = on
        UserDefaults.standard.set(on, forKey: BlackoutKeys.mapNightRed)
    }

    func sendGuideCard(_ articleID: String) {
        let envelope = GuideCardWire.envelope(
            articleID: articleID,
            sender: crypto.localIdentity,
            recipient: crypto.preferredRecipient
        )
        mesh.send(envelope)
    }

    func startFieldMode(_ mode: FieldJobMode) {
        fieldMode = mode
    }

    func exitFieldMode() {
        fieldMode = nil
    }

    func sendFollowTrack(_ crumbs: [BreadcrumbRecordDTO]) {
        guard FollowTrackWire.canShare(crumbs: crumbs) else { return }
        let envelope = FollowTrackWire.envelope(
            points: FollowTrackWire.points(from: crumbs),
            sender: crypto.localIdentity,
            recipient: crypto.preferredRecipient
        )
        mesh.send(envelope)
    }

    func applySharedTrack(_ points: [FollowTrackWire.Point]) {
        sharedTrack = points
    }

    func acknowledgeLatestPing() {
        latestInbound?.acknowledged = true
        latestInbound = nil
        refreshLiveActivity()
        applyIdleTimer()
    }

    func replyToLatest(_ reply: FieldReplyID) {
        guard let inbound = latestInbound, inbound.isOpen() else { return }
        do {
            _ = try outbox.sendReply(reply, fix: location.navigationFix ?? location.lastKnown, thread: inbound.thread)
        } catch {
            return
        }
        acknowledgeLatestPing()
    }

    var inboundImDownOpen: Bool {
        latestInbound?.keepsScreenAwake() == true
    }

    var shouldDisableIdleTimer: Bool {
        IdleTimerPolicy.shouldDisable(
            navLockOn: navLockActive,
            pttTransmitting: ptt.isTransmitting,
            pttLastHeard: ptt.lastHeardAt,
            sosCoverPresented: sosCoverOpen,
            inboundImDownOpen: inboundImDownOpen,
            leaveBehindRelay: LeaveBehindRelayPolicy.isActive(
                enabled: leaveBehindRelay,
                expeditionOpen: hasOpenExpedition,
                batteryCritical: battery.isCritical
            )
        )
    }

    func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = shouldDisableIdleTimer
    }

    func refreshRadiosBanner() {
        radioBanner.applyRadios(cannotRun: radios.cannotRun)
        persistBanner()
    }

    func dismissRadioBanner() {
        radioBanner.dismiss()
        persistBanner()
    }

    var showRadioBanner: Bool {
        radioBanner.shouldShow(cannotRun: radios.cannotRun)
    }

    func persistBanner() {
        UserDefaults.standard.set(radioBanner.dismissed, forKey: BlackoutKeys.meshRadioBannerDismissed)
    }

    func refreshLiveActivity() {
        expireInboundIfNeeded()
        LiveActivityHub.sync(
            partyCode: identity.partyCode,
            inbound: latestInbound,
            peerCount: mesh.nearbyPeerCount,
            callsign: identity.callsign,
            newBinaryLaunch: suppressPersistedArmedAutoPresent
        )
    }

    func expireInboundIfNeeded() {
        if let latestInbound, !latestInbound.isOpen() {
            self.latestInbound = nil
        }
    }

    func applyDeepLink(_ url: URL) -> AppDestination? {
        switch url.host {
        case "map": return .map
        case "comms": return .comms
        default: return nil
        }
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
        case .pttFrame(let payload):
            ptt.receive(payload)
        case .unsupportedVersion:
            return
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
        mesh.send(envelope)
    }

    private func ingestEnvelope(_ envelope: Envelope) {
        switch envelope.kind {
        case .partyStatus, .sosAlert:
            ingestPartyStatus(envelope)
        case .message:
            ingestMessage(envelope)
        case .guideCard:
            ingestGuideCard(envelope)
        case .followTrack:
            ingestFollowTrack(envelope)
        case .pttClip, .locationFix, .breadcrumb:
            return
        }
    }

    private func ingestGuideCard(_ envelope: Envelope) {
        guard let id = GuideCardWire.decode(envelope.ciphertext) else { return }
        inboundGuideID = id
        inboundGuideMissing = !localGuideHasArticle(id)
        inboundGuideMissingNeedsPack = inboundGuideMissing
    }

    private func localGuideHasArticle(_ id: String) -> Bool {
        guard let root = guidePackURL else { return false }
        let articles = root.appendingPathComponent("articles.jsonl")
        guard let raw = try? String(contentsOf: articles, encoding: .utf8) else { return false }
        return raw.contains("\"id\":\"\(id)\"")
    }

    private func ingestFollowTrack(_ envelope: Envelope) {
        guard let points = FollowTrackWire.decode(envelope.ciphertext), points.count >= 2 else { return }
        sharedTrack = points
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
        do {
            guard let record = try outbox.ingest(envelope) else { return }
            noteInboundIfPing(record)
        } catch {
            return
        }
    }

    private func noteInboundIfPing(_ record: MessageRecordDTO) {
        let body = outbox.openBody(record)
        guard let ping = body.fieldPing else { return }
        let thread: ChatThreadRef
        if let code = identity.partyCode, PartyThread.isGroupRecipient(record.recipientID, partyCode: code) {
            thread = .group(partyCode: code)
        } else {
            thread = .dm(peerID: record.senderID)
        }
        let inbound = LatestInboundPing(
            id: record.id,
            ping: ping,
            callsign: party.peers.first(where: { $0.id == record.senderID })?.callsign
                ?? Callsign.defaultValue,
            createdAt: record.createdAt,
            latitude: body.latitude,
            longitude: body.longitude,
            thread: thread
        )
        latestInbound = inbound
        PingAlert.announce(inbound, reduceMotion: UIAccessibility.isReduceMotionEnabled)
        refreshLiveActivity()
        applyIdleTimer()
    }

    private func flushQueuedIfPeerAppeared(_ count: Int) {
        if lastNearbyCount == 0, count > 0 {
            try? outbox.flushQueued()
        }
        lastNearbyCount = count
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
        guard lock.isUnlocked else { return }
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
                    let armed = UserDefaults.standard.bool(forKey: BlackoutKeys.sosArmed)
                    if SOSArmedRestore.shouldRequestConfirmAfterMissedCheckIn(
                        persistedArmed: armed,
                        newBinaryLaunch: suppressPersistedArmedAutoPresent
                    ) {
                        sosConfirmRequested = true
                    }
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
