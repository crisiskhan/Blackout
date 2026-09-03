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
}
