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
    var showFieldPacks = false
    let guidePackURL: URL?
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
        packs = PackStore(bundledRoot: Self.packRoot())
        guidePackURL = Self.guidePackRoot()
        if pack.pack == nil || !packs.bundledIsReady {
            errors.append("DefaultPack missing from the app bundle. Map shows the honest no-pack canvas.")
        }
        if guidePackURL == nil {
            errors.append("GuidePack missing from the app bundle. Field ask cannot retrieve.")
        }
        bootError = errors.isEmpty ? nil : errors.joined(separator: "\n\n")
        location.applyPolicy(battery.policy)
        if battery.isCritical {
            location.stopUpdating()
            mesh.stop()
        } else {
            location.startUpdating()
            mesh.start()
        }
        startMissedCheckInWatch()
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
