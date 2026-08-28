import BlackoutBattery
import BlackoutCore
import BlackoutCrypto
import BlackoutLocation
import BlackoutMesh
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
    let lock: AppLockService
    let bootError: String?
    var sosConfirmRequested = false
    let guidePackURL: URL?

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
        guidePackURL = Self.guidePackRoot()
        if pack.pack == nil {
            errors.append("DefaultPack missing from the app bundle. Map shows the honest no-pack canvas.")
        }
        if guidePackURL == nil {
            errors.append("GuidePack missing from the app bundle. Field ask cannot retrieve.")
        }
        bootError = errors.isEmpty ? nil : errors.joined(separator: "\n\n")
        location.applyPolicy(battery.policy)
        location.startUpdating()
        mesh.start()
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
            if fileManager.fileExists(atPath: manifest.path) {
                return candidate
            }
        }
        return nil
    }
}
