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
    let crypto: LoopbackCrypto
    let location: LocationService
    let mesh: MeshFacade
    let battery: BatteryService
    let pack: FileMapPack
    let lock: AppLockService
    let bootError: String?

    init() {
        var persistError: String?
        let opened: any PersistenceServing
        if let disk = try? PersistenceService() {
            opened = disk
            persistError = nil
        } else if let memory = try? PersistenceService.fallbackInMemory() {
            opened = memory
            persistError = "Local store failed; using in-memory fallback. Chrome still paints."
        } else {
            opened = ArrayPersistence()
            persistError = "Local store unavailable. Session-only memory is in use."
        }
        persistence = opened
        crypto = LoopbackCrypto()
        location = LocationService()
        mesh = MeshFacade()
        battery = BatteryService()
        lock = AppLockService()
        pack = FileMapPack(rootURL: Self.packRoot())
        bootError = persistError
        location.applyPolicy(battery.policy)
        if location.authorization == .authorized {
            location.startUpdating()
        }
        mesh.start()
    }

    private static func packRoot() -> URL? {
        if let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "DefaultPack") {
            return url.deletingLastPathComponent()
        }
        if let root = Bundle.main.resourceURL {
            let candidate = root.appendingPathComponent("DefaultPack", isDirectory: true)
            let manifest = candidate.appendingPathComponent("manifest.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return candidate
            }
        }
        return nil
    }
}
