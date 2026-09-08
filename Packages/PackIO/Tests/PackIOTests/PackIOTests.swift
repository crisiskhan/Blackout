import XCTest
import BlackBox
@testable import PackIO

final class PackIOTests: XCTestCase {
    func testCatalogRoundTrip() throws {
        let cat = PackCatalog(packs: [
            PackManifest(id: "tx-west", name: "TX WEST", state: "TX", bytes: 12, banners: ["heat-island"], center: .init(lat: 31.7, lon: -106.4), bbox: .init(south: 31, west: -107, north: 32, east: -106))
        ])
        let data = try JSONEncoder().encode(cat)
        let back = try JSONDecoder().decode(PackCatalog.self, from: data)
        XCTAssertEqual(back.packs.first?.id, "tx-west")
    }

    func testPreferPrimaryPutsTXWestFirst() {
        let nm = PackManifest(id: "nm", name: "NM", state: "NM", bytes: 1, banners: [], center: .init(lat: 35.15, lon: -106.53), bbox: .init(south: 35.06, west: -106.68, north: 35.25, east: -106.38))
        let tx = PackManifest(id: "tx-west", name: "TX WEST", state: "TX", bytes: 2, banners: [], center: .init(lat: 31.76, lon: -106.49), bbox: .init(south: 31.7, west: -106.62, north: 32.0, east: -106.35))
        let ordered = PackStore.preferPrimary([nm, tx])
        XCTAssertEqual(ordered.map(\.id), ["tx-west", "nm"])
        XCTAssertEqual(PackStore.defaultPackID, "tx-west")
        XCTAssertEqual(PackStore.osmAttribution, "© OpenStreetMap contributors")
    }

    func testSwitchRefusesAPackOffTheStatesWeShip() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("packio-states-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let tx = PackManifest(id: "tx-west", name: "TX WEST", state: "TX", bytes: 2, banners: [], center: .init(lat: 31.76, lon: -106.49), bbox: .init(south: 31.7, west: -106.62, north: 32.0, east: -106.35))
        let stray = PackManifest(id: "fl-north", name: "FL NORTH", state: "FL", bytes: 1, banners: [], center: .init(lat: 30.4, lon: -81.5), bbox: .init(south: 30, west: -82, north: 31, east: -81))
        try JSONEncoder().encode(PackCatalog(states: ["TX", "NM"], packs: [tx, stray]))
            .write(to: root.appendingPathComponent("catalog.json"))
        let store = try PackStore(root: root, box: EventLog())
        XCTAssertThrowsError(try store.switchTo("fl-north")) { error in
            XCTAssertEqual(error as? PackError, .regionLeak)
        }
        XCTAssertEqual(store.active?.id, "tx-west")
        try store.switchTo("tx-west")
        XCTAssertEqual(store.active?.id, "tx-west")
    }

    func testHasUsableGraphIsHonestWhenEmpty() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("packio-graph-\(UUID().uuidString)")
        let pack = root.appendingPathComponent("tx-west")
        try fm.createDirectory(at: pack, withIntermediateDirectories: true)
        let cat = PackCatalog(packs: [
            PackManifest(id: "tx-west", name: "TX WEST", state: "TX", bytes: 1, banners: [], center: .init(lat: 31.76, lon: -106.49), bbox: .init(south: 31.7, west: -106.62, north: 32.0, east: -106.35))
        ])
        try JSONEncoder().encode(cat).write(to: root.appendingPathComponent("catalog.json"))
        let store = try PackStore(root: root, box: EventLog())
        XCTAssertEqual(store.active?.id, "tx-west")
        XCTAssertFalse(store.hasUsableGraph())
        try Data("{\"edges\":[]}".utf8).write(to: pack.appendingPathComponent("graph.json"))
        XCTAssertFalse(store.hasUsableGraph())
        try Data("{\"edges\":[{\"a\":1,\"b\":2,\"m\":10,\"walk\":true,\"drive\":true}]}".utf8).write(to: pack.appendingPathComponent("graph.json"))
        XCTAssertTrue(store.hasUsableGraph())
    }

    func testHomeCoordinateFallsBackToCenterWhenAbsent() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("packio-home-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("tx-west"), withIntermediateDirectories: true)
        let bare = PackManifest(
            id: "tx-west",
            name: "TX WEST",
            state: "TX",
            bytes: 1,
            banners: [],
            center: .init(lat: 31.85, lon: -106.485),
            bbox: .init(south: 31.7, west: -106.62, north: 32.0, east: -106.35)
        )
        try JSONEncoder().encode(PackCatalog(packs: [bare]))
            .write(to: root.appendingPathComponent("catalog.json"))
        let withoutHome = try PackStore(root: root, box: EventLog())
        XCTAssertEqual(withoutHome.homeCoordinate()?.lat, 31.85)

        var withHome = bare
        withHome.home = .init(lat: 31.78, lon: -106.46)
        try JSONEncoder().encode(PackCatalog(packs: [withHome]))
            .write(to: root.appendingPathComponent("catalog.json"))
        let store = try PackStore(root: root, box: EventLog())
        XCTAssertEqual(store.homeCoordinate()?.lat, 31.78)
        XCTAssertEqual(store.homeCoordinate()?.lon, -106.46)
    }

    func testGraphProbeRejectsEmptyAndAcceptsOneEdgeBytes() {
        XCTAssertFalse(GraphProbe.isUsable(byteCount: 0))
        XCTAssertFalse(GraphProbe.isUsable(byteCount: 13))
        XCTAssertFalse(GraphProbe.isUsable(byteCount: GraphProbe.emptyMaxBytes))
        XCTAssertTrue(GraphProbe.isUsable(byteCount: 58))
        XCTAssertTrue(GraphProbe.isUsable(byteCount: 4_749_212))
    }

    func testHasUsableGraphDoesNotParseFullGraphBytes() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("packio-graph-noload-\(UUID().uuidString)")
        let pack = root.appendingPathComponent("tx-west")
        try fm.createDirectory(at: pack, withIntermediateDirectories: true)
        let cat = PackCatalog(packs: [
            PackManifest(id: "tx-west", name: "TX WEST", state: "TX", bytes: 1, banners: [], center: .init(lat: 31.76, lon: -106.49), bbox: .init(south: 31.7, west: -106.62, north: 32.0, east: -106.35))
        ])
        try JSONEncoder().encode(cat).write(to: root.appendingPathComponent("catalog.json"))
        let store = try PackStore(root: root, box: EventLog())
        let junk = Data(repeating: 0x78, count: 2_000_000)
        try junk.write(to: pack.appendingPathComponent("graph.json"))
        let started = Date()
        XCTAssertTrue(store.hasUsableGraph())
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.05)
    }
}
