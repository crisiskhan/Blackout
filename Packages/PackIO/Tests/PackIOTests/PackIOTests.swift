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
        let fl = PackManifest(id: "fl-north", name: "FL NORTH", state: "FL", bytes: 1, banners: [], center: .init(lat: 30.4, lon: -81.5), bbox: .init(south: 30, west: -82, north: 31, east: -81))
        let tx = PackManifest(id: "tx-west", name: "TX WEST", state: "TX", bytes: 2, banners: [], center: .init(lat: 31.76, lon: -106.49), bbox: .init(south: 31.7, west: -106.62, north: 32.0, east: -106.35))
        let ordered = PackStore.preferPrimary([fl, tx])
        XCTAssertEqual(ordered.map(\.id), ["tx-west", "fl-north"])
        XCTAssertEqual(PackStore.defaultPackID, "tx-west")
        XCTAssertEqual(PackStore.osmAttribution, "© OpenStreetMap contributors")
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
}
