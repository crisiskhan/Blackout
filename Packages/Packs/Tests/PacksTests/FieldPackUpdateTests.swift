import CryptoKit
import XCTest
@testable import BlackoutPacks

final class FieldPackUpdatePolicyTests: XCTestCase {
    func testBatchTargetsAreEveryRemoteURLExceptDenver() {
        let ids = FieldPackUpdatePolicy.batchTargets().map(\.id)
        XCTAssertEqual(
            Set(ids),
            ["us-tx", "us-nm", "us-fl", "el-paso", "las-cruces", "albuquerque"]
        )
        XCTAssertFalse(ids.contains(FieldPackCatalog.denver.id))
        XCTAssertNil(FieldPackCatalog.denver.downloadURL)
    }

    func testRowGetIsOnlyForMissingCity() {
        XCTAssertTrue(
            FieldPackUpdatePolicy.showsRowGet(
                isInstalled: false,
                isCityExtra: true,
                hasRemoteURL: true
            )
        )
        XCTAssertFalse(
            FieldPackUpdatePolicy.showsRowGet(
                isInstalled: true,
                isCityExtra: true,
                hasRemoteURL: true
            )
        )
        XCTAssertFalse(
            FieldPackUpdatePolicy.showsRowGet(
                isInstalled: false,
                isCityExtra: false,
                hasRemoteURL: true
            )
        )
        XCTAssertFalse(
            FieldPackUpdatePolicy.showsRowGet(
                isInstalled: false,
                isCityExtra: false,
                hasRemoteURL: false
            )
        )
    }

    func testUpdateMapsStaysUserTapped() {
        XCTAssertTrue(
            FieldPackUpdatePolicy.updateMapsEnabled(
                downloadsAllowed: true,
                pathSatisfied: true,
                batchRunning: false
            )
        )
        XCTAssertFalse(
            FieldPackUpdatePolicy.updateMapsEnabled(
                downloadsAllowed: true,
                pathSatisfied: false,
                batchRunning: false
            )
        )
        XCTAssertFalse(
            FieldPackUpdatePolicy.updateMapsEnabled(
                downloadsAllowed: false,
                pathSatisfied: true,
                batchRunning: false
            )
        )
        XCTAssertFalse(
            FieldPackUpdatePolicy.updateMapsEnabled(
                downloadsAllowed: true,
                pathSatisfied: true,
                batchRunning: true
            )
        )
        XCTAssertTrue(FieldPackUpdatePolicy.needsCellularConfirm(pathSatisfied: true, onWiFi: false))
        XCTAssertFalse(FieldPackUpdatePolicy.needsCellularConfirm(pathSatisfied: true, onWiFi: true))
        XCTAssertFalse(FieldPackUpdatePolicy.needsCellularConfirm(pathSatisfied: false, onWiFi: false))
    }

    func testHashCompareIsHonest() {
        let sha = String(repeating: "ab", count: 32)
        XCTAssertFalse(
            FieldPackUpdatePolicy.shouldFetch(catalogSHA: sha, recordedSHA: sha, isInstalled: true)
        )
        XCTAssertTrue(
            FieldPackUpdatePolicy.shouldFetch(catalogSHA: sha, recordedSHA: sha, isInstalled: false)
        )
        XCTAssertTrue(
            FieldPackUpdatePolicy.shouldFetch(
                catalogSHA: sha,
                recordedSHA: String(repeating: "cd", count: 32),
                isInstalled: true
            )
        )
        XCTAssertTrue(FieldPackUpdatePolicy.shouldFetch(catalogSHA: sha, recordedSHA: nil, isInstalled: true))
        XCTAssertFalse(FieldPackUpdatePolicy.shouldFetch(catalogSHA: nil, recordedSHA: nil, isInstalled: true))
        XCTAssertEqual(FieldPackUpdatePolicy.upToDateCopy, "Up to date")
        XCTAssertEqual(FieldPackUpdatePolicy.updateMapsLabel, "Update maps")
        XCTAssertEqual(FieldPackUpdatePolicy.useCellularLabel, "Use Cellular")
        XCTAssertEqual(FieldPackUpdatePolicy.getLabel, "Get")
    }

    func testByteSizeWhenKnown() {
        XCTAssertEqual(FieldPackUpdatePolicy.byteSizeLabel(220_512_882), "220 MB")
        XCTAssertEqual(FieldPackUpdatePolicy.byteSizeLabel(8_568_180), "8 MB")
        XCTAssertNil(FieldPackUpdatePolicy.byteSizeLabel(nil))
    }
}

@MainActor
final class PackStoreUpdateTests: XCTestCase {
    func testSameHashOnTapIsUpToDateAndDoesNotFetch() async throws {
        let env = try PackUpdateFixture.make()
        defer { env.tearDown() }
        for pack in FieldPackUpdatePolicy.batchTargets() {
            try env.writePack(id: pack.id, name: pack.id)
            try env.writeSHA(pack.id, pack.sha256!)
        }
        let fetches = PackUpdateCounter()
        let store = env.store(enableMonitor: false) { _, _ in
            fetches.value += 1
            throw PackStoreError.badResponse
        }
        store.applyNetworkPathForTests(satisfied: true, onWiFi: true)
        store.updateAllMaps()
        await store.waitForIdle()
        XCTAssertEqual(fetches.value, 0)
        XCTAssertEqual(store.messages["el-paso"], "Up to date")
        XCTAssertEqual(store.states["el-paso"], .ready)
        XCTAssertTrue(store.isInstalled("el-paso"))
    }

    func testBadHashKeepsOldTilesAndContinues() async throws {
        let env = try PackUpdateFixture.make()
        defer { env.tearDown() }
        try env.writePack(id: "el-paso", name: "old-el-paso")
        try env.writePack(id: "las-cruces", name: "old-cruces")
        try env.writeSHA("el-paso", String(repeating: "11", count: 32))
        try env.writeSHA("las-cruces", String(repeating: "22", count: 32))

        let good = try env.makeZip(id: "las-cruces", name: "new-cruces", schema: 1)
        let goodSHA = PackUpdateFixture.sha256(of: good)
        let bad = Data("not-a-zip".utf8)

        let store = env.store(
            enableMonitor: false,
            sha256ForPack: { id in
                id == "las-cruces" ? goodSHA : FieldPackCatalog.descriptor(id: id)?.sha256
            }
        ) { url, _ in
            if url.lastPathComponent.contains("el-paso") { return bad }
            if url.lastPathComponent.contains("las-cruces") { return good }
            throw PackStoreError.notOnReleases
        }
        store.applyNetworkPathForTests(satisfied: true, onWiFi: true)
        store.updateAllMaps()
        await store.waitForIdle()

        XCTAssertEqual(store.states["el-paso"], .failed)
        XCTAssertTrue(store.isInstalled("el-paso"))
        XCTAssertEqual(try env.packName("el-paso"), "old-el-paso")
        XCTAssertEqual(store.states["las-cruces"], .ready)
        XCTAssertEqual(try env.packName("las-cruces"), "new-cruces")
    }

    func testTooNewSchemaKeepsOldTiles() async throws {
        let env = try PackUpdateFixture.make()
        defer { env.tearDown() }
        try env.writePack(id: "el-paso", name: "keep-me")
        try env.writeSHA("el-paso", String(repeating: "33", count: 32))
        let zip = try env.makeZip(id: "el-paso", name: "too-new", schema: 2)
        let sha = PackUpdateFixture.sha256(of: zip)
        let store = env.store(
            enableMonitor: false,
            sha256ForPack: { _ in sha }
        ) { _, _ in zip }
        store.applyNetworkPathForTests(satisfied: true, onWiFi: true)
        store.updateAllMaps()
        await store.waitForIdle()
        XCTAssertEqual(store.states["el-paso"], .failed)
        XCTAssertEqual(store.messages["el-paso"], "Pack too new.")
        XCTAssertEqual(try env.packName("el-paso"), "keep-me")
        XCTAssertTrue(store.isInstalled("el-paso"))
    }

    func testAirplaneAndLastTwoPercentRefuseBatch() async throws {
        let env = try PackUpdateFixture.make()
        defer { env.tearDown() }
        let fetches = PackUpdateCounter()
        let store = env.store(enableMonitor: false) { _, _ in
            fetches.value += 1
            throw PackStoreError.badResponse
        }
        store.applyNetworkPathForTests(satisfied: false, onWiFi: false)
        store.updateAllMaps()
        await store.waitForIdle()
        XCTAssertEqual(fetches.value, 0)

        store.applyNetworkPathForTests(satisfied: true, onWiFi: false)
        store.updateAllMaps()
        await store.waitForIdle()
        XCTAssertEqual(fetches.value, 0)

        store.applyNetworkPathForTests(satisfied: true, onWiFi: true)
        store.setDownloadsAllowed(false)
        store.updateAllMaps()
        await store.waitForIdle()
        XCTAssertEqual(fetches.value, 0)
    }

    func testRowGetInstallsMissingCityOnly() async throws {
        let env = try PackUpdateFixture.make()
        defer { env.tearDown() }
        try env.writePack(id: "el-paso", name: "already")
        let zip = try env.makeZip(id: "albuquerque", name: "abq", schema: 1)
        let sha = PackUpdateFixture.sha256(of: zip)
        let fetched = PackUpdateCounter()
        let store = env.store(
            enableMonitor: false,
            sha256ForPack: { id in id == "albuquerque" ? sha : FieldPackCatalog.descriptor(id: id)?.sha256 }
        ) { url, id in
            fetched.ids.append(id)
            if url.lastPathComponent.contains("albuquerque") { return zip }
            throw PackStoreError.notOnReleases
        }
        store.applyNetworkPathForTests(satisfied: true, onWiFi: true)
        store.download("el-paso")
        await store.waitForIdle()
        XCTAssertTrue(fetched.ids.isEmpty)
        XCTAssertEqual(try env.packName("el-paso"), "already")

        store.download("albuquerque")
        await store.waitForIdle()
        XCTAssertEqual(fetched.ids, ["albuquerque"])
        XCTAssertEqual(try env.packName("albuquerque"), "abq")
        XCTAssertEqual(store.states["albuquerque"], .ready)
    }

    func testInitDoesNotFetch() throws {
        let env = try PackUpdateFixture.make()
        defer { env.tearDown() }
        let fetches = PackUpdateCounter()
        _ = env.store(enableMonitor: false) { _, _ in
            fetches.value += 1
            throw PackStoreError.badResponse
        }
        XCTAssertEqual(fetches.value, 0)
    }
}

private final class PackUpdateCounter: @unchecked Sendable {
    var value = 0
    var ids: [String] = []
}

private struct PackUpdateFixture {
    let fm = FileManager.default
    let disk: URL
    let work: URL

    static func make() throws -> PackUpdateFixture {
        let disk = FileManager.default.temporaryDirectory
            .appendingPathComponent("fp-upd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: true)
        return PackUpdateFixture(disk: disk, work: disk.appendingPathComponent(".partial"))
    }

    func tearDown() {
        try? fm.removeItem(at: disk)
    }

    func store(
        enableMonitor: Bool,
        sha256ForPack: ((String) -> String?)? = nil,
        fetch: @escaping (URL, String) async throws -> Data
    ) -> PackStore {
        PackStore(
            bundledRoot: nil,
            bundledPacksRoot: nil,
            diskRoot: disk,
            enablePathMonitor: enableMonitor,
            sha256ForPack: sha256ForPack,
            zipProvider: fetch
        )
    }

    func writePack(id: String, name: String) throws {
        let root = disk.appendingPathComponent(id, isDirectory: true)
        let tiles = root.appendingPathComponent("tiles/10/1", isDirectory: true)
        try fm.createDirectory(at: tiles, withIntermediateDirectories: true)
        try Data("{\"name\":\"\(name)\",\"schema\":1}".utf8).write(to: root.appendingPathComponent("manifest.json"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tiles.appendingPathComponent("1.png"))
    }

    func writeSHA(_ id: String, _ hex: String) throws {
        try Data(hex.utf8).write(to: disk.appendingPathComponent("\(id).sha256"))
    }

    func packName(_ id: String) throws -> String {
        let data = try Data(contentsOf: disk.appendingPathComponent(id).appendingPathComponent("manifest.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["name"] as? String ?? ""
    }

    func makeZip(id: String, name: String, schema: Int) throws -> Data {
        let root = disk.appendingPathComponent("fixture-\(id)-\(UUID().uuidString)", isDirectory: true)
        let tiles = root.appendingPathComponent("tiles/10/1", isDirectory: true)
        try fm.createDirectory(at: tiles, withIntermediateDirectories: true)
        try Data("{\"name\":\"\(name)\",\"schema\":\(schema)}".utf8)
            .write(to: root.appendingPathComponent("manifest.json"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tiles.appendingPathComponent("1.png"))
        let zip = disk.appendingPathComponent("fixture-\(id).zip")
        try PackZip.archive(directory: root, to: zip)
        return try Data(contentsOf: zip)
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension PackStore {
    func waitForIdle() async {
        for _ in 0..<80 {
            if !isBusyForTests { return }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }
}
