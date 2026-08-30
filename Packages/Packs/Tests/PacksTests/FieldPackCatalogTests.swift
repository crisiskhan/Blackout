import XCTest
@testable import BlackoutPacks

final class FieldPackCatalogTests: XCTestCase {
    func testStatewidePacksAreBundledReady() {
        let ids = FieldPackCatalog.bundledStatewide.map(\.id)
        XCTAssertEqual(Set(ids), ["us-tx", "us-nm", "us-fl", "us-ny"])
        for pack in FieldPackCatalog.bundledStatewide {
            XCTAssertTrue(pack.isBundled)
            XCTAssertTrue(pack.assetReady)
            XCTAssertNotNil(pack.sha256)
            XCTAssertEqual(pack.sha256?.count, 64)
        }
        XCTAssertEqual(
            FieldPackCatalog.texas.sha256,
            "6ff6c9a191fe5df8d3bf48abb360ad361990bc672c1c59bd0cf2e3a3d5d55ade"
        )
        XCTAssertEqual(
            FieldPackCatalog.newMexico.sha256,
            "2e605b0a386c6fbfa1288e5bea4ef96f42ddd5c60633f954b42c8c0e7665a4a8"
        )
        XCTAssertEqual(
            FieldPackCatalog.florida.sha256,
            "49d27c808c49fc894a1ba1021f951966560408c1ebe808f4c0d158e0c238b62d"
        )
        XCTAssertEqual(
            FieldPackCatalog.newYork.sha256,
            "928034851277ab8628521f5bfd7f2f06e6bfed5b588d58f9b46033bae5e64500"
        )
    }

    func testCityPacksStayOptionalDownloads() {
        for pack in FieldPackCatalog.remotePacks {
            XCTAssertFalse(pack.isBundled)
            XCTAssertTrue(FieldPackCatalog.isCityRelay(pack.id))
        }
        XCTAssertEqual(
            Set(FieldPackCatalog.remotePacks.map(\.id)),
            ["el-paso", "las-cruces", "albuquerque"]
        )
    }
}
