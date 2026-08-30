import XCTest
@testable import BlackoutPacks

final class FieldPackHonestyTests: XCTestCase {
    func testMissingStatewideIsAvailableNotFailedOrReady() {
        let state = FieldPackHonesty.rowState(
            isInstalled: false,
            downloading: false,
            isRemote: false,
            assetReady: true,
            pathSatisfied: true,
            onWiFi: true
        )
        XCTAssertNil(state)
        XCTAssertFalse(FieldPackHonesty.claimsBundledReady(isInstalled: false))
        XCTAssertEqual(
            FieldPackHonesty.message(
                isInstalled: false,
                isBundled: true,
                isRemote: false,
                assetReady: true,
                pathSatisfied: true,
                onWiFi: true
            ),
            "Available. Not installed on this device."
        )
        XCTAssertFalse(FieldPackHonesty.showsCatalogSummary(isReady: false))
    }

    func testInstalledStatewideIsReady() {
        XCTAssertEqual(
            FieldPackHonesty.rowState(
                isInstalled: true,
                downloading: false,
                isRemote: false,
                assetReady: true,
                pathSatisfied: true,
                onWiFi: true
            ),
            .ready
        )
        XCTAssertTrue(FieldPackHonesty.claimsBundledReady(isInstalled: true))
        XCTAssertTrue(FieldPackHonesty.showsCatalogSummary(isReady: true))
        XCTAssertEqual(
            FieldPackHonesty.message(
                isInstalled: true,
                isBundled: true,
                isRemote: false,
                assetReady: true,
                pathSatisfied: true,
                onWiFi: true
            ),
            "Bundled. Ready. Works airplane."
        )
    }

    func testCityReadyButNotInstalledIsAvailableNotFailed() {
        let state = FieldPackHonesty.rowState(
            isInstalled: false,
            downloading: false,
            isRemote: true,
            assetReady: true,
            pathSatisfied: true,
            onWiFi: true
        )
        XCTAssertNil(state)
        XCTAssertNotEqual(state, .failed)
        XCTAssertEqual(
            FieldPackHonesty.message(
                isInstalled: false,
                isBundled: false,
                isRemote: true,
                assetReady: true,
                pathSatisfied: true,
                onWiFi: true
            ),
            "Tap Download. Then airplane."
        )
    }

    func testMissingAssetIsNotReadyNotAFakeMap() {
        XCTAssertEqual(
            FieldPackHonesty.rowState(
                isInstalled: false,
                downloading: false,
                isRemote: true,
                assetReady: false,
                pathSatisfied: true,
                onWiFi: true
            ),
            .failed
        )
        XCTAssertEqual(
            FieldPackHonesty.message(
                isInstalled: false,
                isBundled: false,
                isRemote: true,
                assetReady: false,
                pathSatisfied: true,
                onWiFi: true
            ),
            "Not on GitHub Releases yet. Denver stays the fallback."
        )
    }

    func testCatalogFactsStayFLTXNYNM() {
        XCTAssertEqual(
            Set(FieldPackCatalog.bundledStatewide.map(\.id)),
            ["us-tx", "us-nm", "us-fl", "us-ny"]
        )
        for pack in FieldPackCatalog.bundledStatewide {
            XCTAssertTrue(pack.isBundled)
            XCTAssertTrue(pack.assetReady)
        }
        XCTAssertFalse(FieldPackCatalog.elPaso.isBundled)
    }
}
