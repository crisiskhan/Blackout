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
    public private(set) var downloadsAllowed = true
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
    private let sha256ForPack: (String) -> String?
    private let zipProvider: ((URL, String) async throws -> Data)?

    public convenience init(
        bundledRoot: URL?,
        bundledPacksRoot: URL? = nil,
        diskRoot: URL? = nil
    ) {
        self.init(
            bundledRoot: bundledRoot,
            bundledPacksRoot: bundledPacksRoot,
            diskRoot: diskRoot,
            enablePathMonitor: true,
            sha256ForPack: nil,
            zipProvider: nil
        )
    }

    init(
        bundledRoot: URL?,
        bundledPacksRoot: URL?,
        diskRoot: URL?,
        enablePathMonitor: Bool,
        sha256ForPack: ((String) -> String?)?,
        zipProvider: ((URL, String) async throws -> Data)?
    ) {
        self.bundledRoot = bundledRoot
        self.bundledPacksRoot = bundledPacksRoot
        let base = diskRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FieldPacks", isDirectory: true)
        self.diskRoot = base
        self.workRoot = base.appendingPathComponent(".partial", isDirectory: true)
        self.relayRoot = base.appendingPathComponent(".relay", isDirectory: true)
        self.sha256ForPack = { id in
            sha256ForPack?(id) ?? FieldPackCatalog.descriptor(id: id)?.sha256
        }
        self.zipProvider = zipProvider
        try? FileManager.default.createDirectory(at: self.diskRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: self.workRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: self.relayRoot, withIntermediateDirectories: true)
        if enablePathMonitor {
            monitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor in
                    self?.pathSatisfied = path.status == .satisfied
                    self?.onWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                    self?.refreshStates()
                }
            }
            monitor.start(queue: DispatchQueue(label: "com.crisiskhan.blackout.packs.path"))
        }
        refreshStates()
    }

    /// Created only when the user taps Get / Update maps. Never on boot.
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
        bundledFilesPresent && bundledSchemaOK
    }

    private var bundledFilesPresent: Bool {
        guard let bundledRoot else { return false }
        return packFilesPresent(bundledRoot)
    }

    private var bundledSchemaOK: Bool {
        guard let bundledRoot else { return false }
        return packSchemaOK(bundledRoot)
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

    /// On-disk pack roots including too-new schema. Map fail-closes; Ready stays schema-ok.
    public var diskPackRoots: [URL] {
        _ = states
        return FieldPackCatalog.installablePacks.compactMap { packOnDisk($0.id) }
    }

    public func packRoot(for id: String) -> URL? {
        guard let root = packOnDisk(id), packSchemaOK(root) else { return nil }
        return root
    }

    /// Files on disk, including a too-new schema we must not call Ready.
    /// User-updated Application Support wins over the read-only archive copy.
    public func packOnDisk(_ id: String) -> URL? {
        if id == FieldPackCatalog.denver.id {
            return bundledFilesPresent ? bundledRoot : nil
        }
        let disk = diskRoot.appendingPathComponent(id, isDirectory: true)
        if packFilesPresent(disk) { return disk }
        if let bundled = bundledPacksRoot?.appendingPathComponent(id, isDirectory: true),
           packFilesPresent(bundled) {
            return bundled
        }
        return nil
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

    var isBusyForTests: Bool {
        !tasks.isEmpty
    }

    public func setDownloadsAllowed(_ allowed: Bool) {
        downloadsAllowed = allowed
        if !allowed {
            for task in tasks.values { task.cancel() }
            tasks.removeAll()
            for id in states.keys where states[id] == .downloading {
                progress[id] = nil
            }
            refreshStates()
        }
    }

    func applyNetworkPathForTests(satisfied: Bool, onWiFi: Bool) {
        pathSatisfied = satisfied
        self.onWiFi = onWiFi
        refreshStates()
    }

    /// First install of one missing city. Not an update path.
    public func download(_ id: String, allowCellular: Bool = false) {
        guard downloadsAllowed else { return }
        guard let descriptor = FieldPackCatalog.descriptor(id: id) else { return }
        guard FieldPackUpdatePolicy.showsRowGet(
            isInstalled: isInstalled(id),
            isCityExtra: FieldPackCatalog.remotePacks.contains(where: { $0.id == id }),
            hasRemoteURL: descriptor.downloadURL != nil
        ) else { return }
        startInstall(descriptor, replacing: false, allowCellular: allowCellular || onWiFi)
    }

    /// One tap. Every catalog pack with a remote URL. Wi-Fi default.
    public func updateAllMaps(allowCellular: Bool = false) {
        guard FieldPackUpdatePolicy.updateMapsEnabled(
            downloadsAllowed: downloadsAllowed,
            pathSatisfied: pathSatisfied,
            batchRunning: tasks["*batch*"] != nil
        ) else { return }
        if !onWiFi && !allowCellular { return }
        tasks["*batch*"] = Task { [weak self] in
            await self?.runBatchUpdate(allowCellular: allowCellular)
            self?.tasks["*batch*"] = nil
        }
    }

    public func refreshStates() {
        if bundledIsReady {
            states[FieldPackCatalog.denver.id] = .ready
            messages[FieldPackCatalog.denver.id] = "On this device. Works airplane."
        } else if bundledFilesPresent {
            states[FieldPackCatalog.denver.id] = .failed
            messages[FieldPackCatalog.denver.id] = MapPackLayout.tooNewCopy
        } else {
            states[FieldPackCatalog.denver.id] = .failed
            messages[FieldPackCatalog.denver.id] = "Bundled Denver pack is missing from the app."
        }
        for pack in FieldPackCatalog.installablePacks {
            if states[pack.id] == .downloading { continue }
            applyCatalogState(
                pack,
                isBundled: FieldPackCatalog.bundledStatewide.contains(where: { $0.id == pack.id }),
                isRemote: FieldPackCatalog.remotePacks.contains(where: { $0.id == pack.id })
            )
        }
    }

    private func applyCatalogState(_ pack: FieldPackDescriptor, isBundled: Bool, isRemote: Bool) {
        if packOnDisk(pack.id) != nil, !isInstalled(pack.id) {
            states[pack.id] = .failed
            messages[pack.id] = MapPackLayout.tooNewCopy
            return
        }
        let installed = isInstalled(pack.id)
        if let state = FieldPackHonesty.rowState(
            isInstalled: installed,
            downloading: false,
            isRemote: isRemote,
            assetReady: pack.assetReady,
            pathSatisfied: pathSatisfied,
            onWiFi: onWiFi
        ) {
            states[pack.id] = state
        } else {
            states.removeValue(forKey: pack.id)
        }
        messages[pack.id] = FieldPackHonesty.message(
            isInstalled: installed,
            isBundled: isBundled,
            isRemote: isRemote,
            assetReady: pack.assetReady,
            pathSatisfied: pathSatisfied,
            onWiFi: onWiFi
        )
    }

    private func packFilesPresent(_ root: URL) -> Bool {
        let manifest = root.appendingPathComponent("manifest.json")
        return FileManager.default.fileExists(atPath: manifest.path)
            && MapPackLayout.containsTilePNGs(root: root)
    }

    private func packSchemaOK(_ root: URL) -> Bool {
        guard let json = MapPackLayout.readManifestJSON(root: root) else { return false }
        return MapPackLayout.isSupported(json: json)
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

    private func startInstall(
        _ descriptor: FieldPackDescriptor,
        replacing: Bool,
        allowCellular: Bool
    ) {
        let id = descriptor.id
        tasks[id]?.cancel()
        tasks[id] = Task { [weak self] in
            await self?.runInstall(descriptor, replacing: replacing, allowCellular: allowCellular)
            self?.tasks[id] = nil
        }
    }

    private func runBatchUpdate(allowCellular: Bool) async {
        for pack in FieldPackUpdatePolicy.batchTargets() {
            if Task.isCancelled || !downloadsAllowed { break }
            if !pathSatisfied { break }
            if !onWiFi && !allowCellular { break }
            await runInstall(pack, replacing: true, allowCellular: allowCellular)
        }
    }

    private func runInstall(
        _ descriptor: FieldPackDescriptor,
        replacing: Bool,
        allowCellular: Bool
    ) async {
        let id = descriptor.id
        if !downloadsAllowed { return }
        if !replacing && isInstalled(id) { return }
        if replacing,
           !FieldPackUpdatePolicy.shouldFetch(
                catalogSHA: sha256ForPack(id),
                recordedSHA: recordedSHA256(id),
                isInstalled: isInstalled(id)
           ) {
            if isInstalled(id) {
                states[id] = .ready
                messages[id] = FieldPackUpdatePolicy.upToDateCopy
            }
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
            messages[id] = FieldPackUpdatePolicy.noPathCopy
            return
        }
        if !onWiFi && !allowCellular {
            states[id] = .noWifi
            messages[id] = FieldPackHonesty.message(
                isInstalled: isInstalled(id),
                isBundled: FieldPackCatalog.bundledStatewide.contains(where: { $0.id == id }),
                isRemote: FieldPackCatalog.remotePacks.contains(where: { $0.id == id }),
                assetReady: descriptor.assetReady,
                pathSatisfied: pathSatisfied,
                onWiFi: onWiFi
            )
            return
        }
        do {
            let zipURL = try await fetchZip(from: url, id: id, expectedSHA: sha256ForPack(id))
            if Task.isCancelled { return }
            try installVerifiedZip(zipURL, id: id)
            keepRelayZip(id: id, from: zipURL)
            writeSHA256(id, sha256ForPack(id))
            try? FileManager.default.removeItem(at: zipURL)
            states[id] = .ready
            messages[id] = "Ready. Works airplane."
            progress[id] = 1
        } catch is CancellationError {
            refreshStates()
        } catch PackStoreError.tooNew {
            states[id] = .failed
            messages[id] = MapPackLayout.tooNewCopy
        } catch {
            if isInstalled(id) {
                states[id] = .failed
                messages[id] = "Failed. Old tiles stay on this phone."
            } else if !pathSatisfied {
                states[id] = .noWifi
                messages[id] = FieldPackUpdatePolicy.noPathCopy
            } else {
                states[id] = .failed
                messages[id] = "Failed. Airplane still uses Denver plus any pack already on disk."
            }
        }
    }

    private func fetchZip(from url: URL, id: String, expectedSHA: String?) async throws -> URL {
        let partial = workRoot.appendingPathComponent("\(id).zip.part")
        if let zipProvider {
            let data = try await zipProvider(url, id)
            try verifySHA256(data, expected: expectedSHA)
            try data.write(to: partial, options: .atomic)
            return partial
        }
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
        do {
            try verifySHA256(data, expected: expectedSHA)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        return partial
    }

    private func verifySHA256(_ data: Data, expected: String?) throws {
        guard let expected = FieldPackUpdatePolicy.normalizedSHA(expected) else { return }
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if hex != expected { throw PackStoreError.checksum }
    }

    /// Extract to staging, verify, then swap. Failure leaves the working pack untouched.
    private func installVerifiedZip(_ zipURL: URL, id: String) throws {
        let fm = FileManager.default
        let staging = workRoot.appendingPathComponent("\(id).new", isDirectory: true)
        let dest = diskRoot.appendingPathComponent(id, isDirectory: true)
        let backup = workRoot.appendingPathComponent("\(id).old", isDirectory: true)
        try? fm.removeItem(at: staging)
        try? fm.removeItem(at: backup)
        try PackZip.extract(zipURL: zipURL, to: staging)
        let manifest = staging.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifest.path),
              MapPackLayout.containsTilePNGs(root: staging) else {
            try? fm.removeItem(at: staging)
            throw PackStoreError.missingManifest
        }
        guard packSchemaOK(staging) else {
            try? fm.removeItem(at: staging)
            throw PackStoreError.tooNew
        }
        if fm.fileExists(atPath: dest.path) {
            try fm.moveItem(at: dest, to: backup)
            do {
                try fm.moveItem(at: staging, to: dest)
                try? fm.removeItem(at: backup)
            } catch {
                try? fm.removeItem(at: dest)
                try? fm.moveItem(at: backup, to: dest)
                try? fm.removeItem(at: staging)
                throw error
            }
        } else {
            try fm.moveItem(at: staging, to: dest)
        }
    }

    func recordedSHA256(_ id: String) -> String? {
        let candidates: [URL] = [
            diskRoot.appendingPathComponent("\(id).sha256"),
            diskRoot.appendingPathComponent(id, isDirectory: true).appendingPathComponent("catalog.sha256"),
            bundledPacksRoot?.appendingPathComponent(id, isDirectory: true).appendingPathComponent("catalog.sha256")
        ].compactMap { $0 }
        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let hex = FieldPackUpdatePolicy.normalizedSHA(text) {
                return hex
            }
        }
        return nil
    }

    private func writeSHA256(_ id: String, _ hex: String?) {
        guard let hex = FieldPackUpdatePolicy.normalizedSHA(hex) else { return }
        let sidecar = diskRoot.appendingPathComponent("\(id).sha256")
        try? Data(hex.utf8).write(to: sidecar, options: .atomic)
        let inside = diskRoot.appendingPathComponent(id, isDirectory: true).appendingPathComponent("catalog.sha256")
        try? Data(hex.utf8).write(to: inside, options: .atomic)
    }

    /// Zip bytes for the 1/N radio. Prefers the kept GitHub zip (catalog SHA-256).
    /// Already-extracted city packs are re-zipped; that archive cannot match the catalog hash.
    public func prepareRelayZip(_ id: String) throws -> URL {
        guard FieldPackCatalog.isRelayable(id) else { throw PackStoreError.notCityRelay }
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
        guard FieldPackCatalog.isRelayable(id) else { return }
        if isInstalled(id) { return }
        states[id] = .downloading
        messages[id] = "Receiving from nearby phone…"
        progress[id] = 0
    }

    /// Local radio only. No GitHub, no URLSession. Fail leaves Denver / SOS / Guide alone.
    public func installRelayedZip(id: String, zipURL: URL) {
        guard FieldPackCatalog.isRelayable(id) else {
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
            let expected = FieldPackUpdatePolicy.normalizedSHA(sha256ForPack(id))
            let catalogMatch = expected != nil && hex == expected

            try installVerifiedZip(zipURL, id: id)
            keepRelayZip(id: id, from: zipURL)
            if catalogMatch { writeSHA256(id, hex) }
            try? FileManager.default.removeItem(at: zipURL)
            states[id] = .ready
            progress[id] = 1
            messages[id] = catalogMatch
                ? "Ready from nearby phone. Checksum matches catalog."
                : "Ready from nearby phone. Tiles verified on disk."
        } catch PackStoreError.tooNew {
            try? FileManager.default.removeItem(at: zipURL)
            states[id] = .failed
            messages[id] = MapPackLayout.tooNewCopy
            progress[id] = nil
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
        guard FieldPackCatalog.isRelayable(id) else { return }
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
    case tooNew
    case notCityRelay
    case notInstalled
}
