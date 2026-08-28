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
    private let diskRoot: URL
    private let workRoot: URL
    private let monitor = NWPathMonitor()
    private let session: URLSession
    private var tasks: [String: Task<Void, Never>] = [:]

    public init(bundledRoot: URL?, diskRoot: URL? = nil) {
        self.bundledRoot = bundledRoot
        let base = diskRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FieldPacks", isDirectory: true)
        self.diskRoot = base
        self.workRoot = base.appendingPathComponent(".partial", isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.allowsCellularAccess = true
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
        try? FileManager.default.createDirectory(at: self.diskRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: self.workRoot, withIntermediateDirectories: true)
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

    public var bundledIsReady: Bool {
        guard let bundledRoot else { return false }
        let manifest = bundledRoot.appendingPathComponent("manifest.json")
        return FileManager.default.fileExists(atPath: manifest.path)
            && MapPackLayout.containsTilePNGs(root: bundledRoot)
    }

    public func coverageRegions(bundled: MapRegion?) -> [MapRegion] {
        var regions: [MapRegion] = []
        if let bundled { regions.append(bundled) }
        for pack in FieldPackCatalog.remotePacks where isInstalled(pack.id) {
            regions.append(regionOnDisk(pack.id) ?? pack.region)
        }
        return regions
    }

    public func isInstalled(_ id: String) -> Bool {
        if id == FieldPackCatalog.denver.id { return bundledIsReady }
        let manifest = diskRoot.appendingPathComponent(id, isDirectory: true).appendingPathComponent("manifest.json")
        return FileManager.default.fileExists(atPath: manifest.path)
    }

    public func skipIntro() {
        UserDefaults.standard.set(true, forKey: BlackoutKeys.fieldPacksIntroCompleted)
        for pack in FieldPackCatalog.remotePacks where states[pack.id] != .ready && states[pack.id] != .downloading {
            states[pack.id] = .skip
        }
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
                messages[pack.id] = "Not on GitHub Releases yet. Skip uses the Denver sample."
            } else if states[pack.id] != .skip {
                states[pack.id] = .available
                messages[pack.id] = "On GitHub Releases. Tap Download. Then airplane."
            }
        }
    }

    private func regionOnDisk(_ id: String) -> MapRegion? {
        let url = diskRoot.appendingPathComponent(id, isDirectory: true).appendingPathComponent("manifest.json")
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
            messages[id] = "Not on GitHub Releases yet. Skip uses the Denver sample."
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
        let (temp, response) = try await session.download(for: request)
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
}

public enum PackStoreError: Error {
    case badResponse
    case notOnReleases
    case checksum
    case missingManifest
}
