import BlackoutCore
import CryptoKit
import Foundation
import Network
import Observation

/// User-initiated Field Pack downloads only. Never runs on boot, SOS, Map paint, or Guide ask.
@MainActor
@Observable
public final class PackStore {
    public private(set) var pathSatisfied = false
    public private(set) var onWiFi = false
    public private(set) var states: [String: FieldPackRowState] = [:]
    public private(set) var messages: [String: String] = [:]
    public private(set) var progress: [String: Double] = [:]

    private let bundledRoot: URL?
    private let bundledPacksRoot: URL?
    private let diskRoot: URL
    private let workRoot: URL
    private let relayRoot: URL
    private let monitor = NWPathMonitor()
    private var session: URLSession?
    private var tasks: [String: Task<Void, Never>] = [:]

    public init(bundledRoot: URL?, bundledPacksRoot: URL? = nil, diskRoot: URL? = nil) {
        self.bundledRoot = bundledRoot
        self.bundledPacksRoot = bundledPacksRoot
        let base = diskRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FieldPacks", isDirectory: true)
        self.diskRoot = base
        self.workRoot = base.appendingPathComponent(".partial", isDirectory: true)
        self.relayRoot = base.appendingPathComponent(".relay", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.diskRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: self.workRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: self.relayRoot, withIntermediateDirectories: true)
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.pathSatisfied = path.status == .satisfied
                self?.onWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                self?.refreshStates()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.crisiskhan.blackout.packs.path"))
        refreshStates()
    }

    /// Created only when the user taps Download on an optional extra. Never on boot.
    private func httpSession() -> URLSession {
        if let session { return session }
        let config = URLSessionConfiguration.ephemeral
        config.allowsCellularAccess = true
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        let created = URLSession(configuration: config)
        session = created
        return created
    }

    public var bundledIsReady: Bool {
        guard let bundledRoot else { return false }
        let manifest = bundledRoot.appendingPathComponent("manifest.json")
        return FileManager.default.fileExists(atPath: manifest.path)
            && MapPackLayout.containsTilePNGs(root: bundledRoot)
    }

    public func coverageRegions(bundled: MapRegion?) -> [MapRegion] {
        var regions: [MapRegion] = []
        if let bundled { regions.append(bundled) }
        for pack in FieldPackCatalog.installablePacks where isInstalled(pack.id) {
            regions.append(regionOnDisk(pack.id) ?? pack.region)
        }
        return regions
    }

    /// Tile roots for bundled statewide + downloaded extras. Reads `states` so SwiftUI reloads.
    public var installedPackRoots: [URL] {
        _ = states
        return FieldPackCatalog.installablePacks.compactMap { pack in
            guard let root = packRoot(for: pack.id) else { return nil }
            guard MapPackLayout.containsTilePNGs(root: root) else { return nil }
            return root
        }
    }

    public func packRoot(for id: String) -> URL? {
        if id == FieldPackCatalog.denver.id {
            return bundledIsReady ? bundledRoot : nil
        }
        if let bundled = bundledPacksRoot?.appendingPathComponent(id, isDirectory: true),
           packLooksReady(bundled) {
            return bundled
        }
        let disk = diskRoot.appendingPathComponent(id, isDirectory: true)
        return packLooksReady(disk) ? disk : nil
    }

    public func isInstalled(_ id: String) -> Bool {
        packRoot(for: id) != nil
    }

    /// One Ready query. Map / Field / Navigate ask this store.
    public func isReady(_ id: String) -> Bool {
        states[id] == .ready
    }

    public var readyRoots: [URL] { installedPackRoots }

    public var readySnapshot: PackReadySnapshot {
        PackReadySnapshot(
            readyIDs: FieldPackCatalog.all.compactMap { isReady($0.id) ? $0.id : nil }
        )
    }

    public func download(_ id: String) {
        guard let descriptor = FieldPackCatalog.remotePacks.first(where: { $0.id == id }) else { return }
        tasks[id]?.cancel()
        tasks[id] = Task { [weak self] in
            await self?.runDownload(descriptor)
        }
    }

    public func refreshStates() {
        if bundledIsReady {
            states[FieldPackCatalog.denver.id] = .ready
            messages[FieldPackCatalog.denver.id] = "On this device. Works airplane."
        } else {
            states[FieldPackCatalog.denver.id] = .failed
            messages[FieldPackCatalog.denver.id] = "Bundled Denver pack is missing from the app."
        }
        for pack in FieldPackCatalog.bundledStatewide {
            if isInstalled(pack.id) {
                states[pack.id] = .ready
                messages[pack.id] = "Bundled. Ready. Works airplane."
            } else {
                states[pack.id] = .failed
                messages[pack.id] = "Statewide pack missing from this IPA."
            }
        }
        for pack in FieldPackCatalog.remotePacks {
            if states[pack.id] == .downloading { continue }
            if isInstalled(pack.id) {
                states[pack.id] = .ready
                messages[pack.id] = "Ready. Works airplane."
                continue
            }
            if !pathSatisfied {
                states[pack.id] = .noWifi
                messages[pack.id] = "No network. Airplane uses packs already on disk."
            } else if !onWiFi {
                states[pack.id] = .noWifi
                messages[pack.id] = "Prefers Wi-Fi. Tap Download to try anyway from this screen."
            } else if !pack.assetReady {
                states[pack.id] = .failed
                messages[pack.id] = "Not on GitHub Releases yet. Denver stays the fallback."
            } else {
                states.removeValue(forKey: pack.id)
                messages[pack.id] = "Tap Download. Then airplane."
            }
        }
    }

    private func packLooksReady(_ root: URL) -> Bool {
        let manifest = root.appendingPathComponent("manifest.json")
        return FileManager.default.fileExists(atPath: manifest.path)
            && MapPackLayout.containsTilePNGs(root: root)
    }

    private func regionOnDisk(_ id: String) -> MapRegion? {
        guard let root = packRoot(for: id) else { return nil }
        let url = root.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let center = json["center"] as? [String: Any]
        let span = json["span"] as? [String: Any]
        return MapRegion(
            name: json["name"] as? String ?? id,
            centerLatitude: (center?["lat"] as? Double) ?? 0,
            centerLongitude: (center?["lon"] as? Double) ?? 0,
            spanLatitude: (span?["lat"] as? Double) ?? 1,
            spanLongitude: (span?["lon"] as? Double) ?? 1,
            minZoom: json["minZoom"] as? Int ?? 8,
            maxZoom: json["maxZoom"] as? Int ?? 12
        )
    }

    private func runDownload(_ descriptor: FieldPackDescriptor) async {
        let id = descriptor.id
        if isInstalled(id) {
            states[id] = .ready
            messages[id] = "Ready. Works airplane."
            return
        }
        states[id] = .downloading
        messages[id] = onWiFi ? "Downloading…" : "Downloading without Wi-Fi…"
        progress[id] = 0
        defer { progress[id] = nil }

        guard descriptor.assetReady, let url = descriptor.downloadURL else {
            states[id] = .failed
            messages[id] = "Not on GitHub Releases yet. Denver stays the fallback."
            return
        }
        if !pathSatisfied {
            states[id] = .noWifi
            messages[id] = "No network. Airplane uses packs already on disk."
            return
        }
        do {
            let zipURL = try await fetchZip(from: url, id: id, expectedSHA: descriptor.sha256)
            if Task.isCancelled { return }
            let dest = diskRoot.appendingPathComponent(id, isDirectory: true)
            try? FileManager.default.removeItem(at: dest)
            try PackZip.extract(zipURL: zipURL, to: dest)
            let manifest = dest.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifest.path) else {
                try? FileManager.default.removeItem(at: dest)
                throw PackStoreError.missingManifest
            }
            keepRelayZip(id: id, from: zipURL)
            try? FileManager.default.removeItem(at: zipURL)
            states[id] = .ready
            messages[id] = "Ready. Works airplane."
            progress[id] = 1
        } catch is CancellationError {
            refreshStates()
        } catch {
            if isInstalled(id) {
                states[id] = .ready
                messages[id] = "Ready. Works airplane."
            } else if !pathSatisfied {
                states[id] = .noWifi
                messages[id] = "No network. Airplane uses packs already on disk."
            } else {
                states[id] = .failed
                messages[id] = "Download failed. Airplane still uses Denver plus any pack already on disk."
            }
        }
    }

    private func fetchZip(from url: URL, id: String, expectedSHA: String?) async throws -> URL {
        let partial = workRoot.appendingPathComponent("\(id).zip.part")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let existing = (try? FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value ?? 0
        if existing > 0 {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
        }
        let (temp, response) = try await httpSession().download(for: request)
        guard let http = response as? HTTPURLResponse else { throw PackStoreError.badResponse }
        if http.statusCode == 404 || http.statusCode == 403 {
            throw PackStoreError.notOnReleases
        }
        guard (200...206).contains(http.statusCode) else { throw PackStoreError.badResponse }
        if http.statusCode == 206, existing > 0, FileManager.default.fileExists(atPath: partial.path) {
            let handle = try FileHandle(forWritingTo: partial)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(contentsOf: temp))
            try? FileManager.default.removeItem(at: temp)
        } else {
            try? FileManager.default.removeItem(at: partial)
            try FileManager.default.moveItem(at: temp, to: partial)
        }
        let data = try Data(contentsOf: partial, options: [.mappedIfSafe])
        if let expectedSHA, expectedSHA.count == 64, expectedSHA.contains(where: { $0 != "0" }) {
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            if hex != expectedSHA.lowercased() {
                try? FileManager.default.removeItem(at: partial)
                throw PackStoreError.checksum
            }
        }
        return partial
    }

    /// Zip bytes for the 1/N radio. Prefers the kept GitHub zip (catalog SHA-256).
    /// Already-extracted city packs are re-zipped; that archive cannot match the catalog hash.
    public func prepareRelayZip(_ id: String) throws -> URL {
        guard FieldPackCatalog.isCityRelay(id) else { throw PackStoreError.notCityRelay }
        guard isInstalled(id) else { throw PackStoreError.notInstalled }
        let kept = relayZipURL(id)
        if FileManager.default.fileExists(atPath: kept.path) {
            return kept
        }
        let dest = workRoot.appendingPathComponent("\(id).relay.zip")
        try? FileManager.default.removeItem(at: dest)
        try PackZip.archive(directory: diskRoot.appendingPathComponent(id, isDirectory: true), to: dest)
        return dest
    }

    public func beginRelaySend(_ id: String) {
        progress[id] = 0
        messages[id] = "Sending to nearby phone…"
    }

    public func updateRelayProgress(_ id: String, _ value: Double) {
        progress[id] = min(1, max(0, value))
    }

    public func finishRelaySend(_ id: String, failed: Bool) {
        progress[id] = nil
        if isInstalled(id) {
            states[id] = .ready
            messages[id] = failed
                ? "Send failed. Pack stays on this phone. Map, SOS, and Guide unchanged."
                : "Sent to nearby phone. Still on this phone."
        }
    }

    public func noteRelayBlocked(_ id: String) {
        messages[id] = "No nearby phone. Connect 1/N, then send."
    }

    public func noteReceiving(_ id: String) {
        guard FieldPackCatalog.isCityRelay(id) else { return }
        if isInstalled(id) { return }
        states[id] = .downloading
        messages[id] = "Receiving from nearby phone…"
        progress[id] = 0
    }

    /// Local radio only. No GitHub, no URLSession. Fail leaves Denver / SOS / Guide alone.
    public func installRelayedZip(id: String, zipURL: URL) {
        guard FieldPackCatalog.isCityRelay(id) else {
            try? FileManager.default.removeItem(at: zipURL)
            return
        }
        if isInstalled(id) {
            states[id] = .ready
            messages[id] = "Ready. Works airplane."
            progress[id] = nil
            try? FileManager.default.removeItem(at: zipURL)
            return
        }
        states[id] = .downloading
        messages[id] = "Installing from nearby phone…"
        do {
            let data = try Data(contentsOf: zipURL, options: [.mappedIfSafe])
            let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let expected = FieldPackCatalog.descriptor(id: id)?.sha256?.lowercased()
            let catalogMatch = expected?.count == 64 && hex == expected

            let dest = diskRoot.appendingPathComponent(id, isDirectory: true)
            try? FileManager.default.removeItem(at: dest)
            try PackZip.extract(data: data, to: dest)
            let manifest = dest.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifest.path),
                  MapPackLayout.containsTilePNGs(root: dest) else {
                try? FileManager.default.removeItem(at: dest)
                throw PackStoreError.missingManifest
            }
            keepRelayZip(id: id, from: zipURL)
            try? FileManager.default.removeItem(at: zipURL)
            states[id] = .ready
            progress[id] = 1
            messages[id] = catalogMatch
                ? "Ready from nearby phone. Checksum matches catalog."
                : "Ready from nearby phone. Tiles verified on disk."
        } catch {
            try? FileManager.default.removeItem(at: zipURL)
            if isInstalled(id) {
                states[id] = .ready
                messages[id] = "Ready. Works airplane."
            } else {
                states[id] = .failed
                messages[id] = "Nearby pack failed. Map, SOS, and Guide still work."
            }
            progress[id] = nil
        }
    }

    private func relayZipURL(_ id: String) -> URL {
        relayRoot.appendingPathComponent("\(id).zip")
    }

    private func keepRelayZip(id: String, from zipURL: URL) {
        guard FieldPackCatalog.isCityRelay(id) else { return }
        let kept = relayZipURL(id)
        try? FileManager.default.removeItem(at: kept)
        try? FileManager.default.copyItem(at: zipURL, to: kept)
    }
}

public enum PackStoreError: Error {
    case badResponse
    case notOnReleases
    case checksum
    case missingManifest
    case notCityRelay
    case notInstalled
}
