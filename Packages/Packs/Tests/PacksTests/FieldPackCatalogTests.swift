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
        XCTAssertEqual(
            FieldPackCatalog.elPaso.sha256,
            "883158ef09620500b06eaf564f43c02a95fbb71ac9bf11592e325e644c72f34b"
        )
        XCTAssertEqual(FieldPackCatalog.elPaso.byteCount, 20_215_735)
        XCTAssertEqual(
            FieldPackCatalog.lasCruces.sha256,
            "f26b8675adb9fe0e8b09161f28659f208e609d201104d4c185728060508ddad4"
        )
        XCTAssertEqual(FieldPackCatalog.lasCruces.byteCount, 8_076_313)
        XCTAssertEqual(
            FieldPackCatalog.albuquerque.sha256,
            "29a8dc25e0d923df6845f26a30569393b707297a1ab73ea43f3d72e50756d01d"
        )
        XCTAssertEqual(FieldPackCatalog.albuquerque.byteCount, 12_308_725)
    }
}
