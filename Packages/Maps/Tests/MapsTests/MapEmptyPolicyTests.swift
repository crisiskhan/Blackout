import XCTest
@testable import MapsRouting

final class MapEmptyPolicyTests: XCTestCase {
    func testNoMountedPackIsEmptyCardNotCanvas() {
        XCTAssertTrue(MapEmptyPolicy.showsEmptyCard(packMounted: false))
        XCTAssertFalse(MapEmptyPolicy.paintsCanvas(packMounted: false))
        XCTAssertFalse(MapEmptyPolicy.showsChips(packMounted: false, sosOnly: false))
        XCTAssertFalse(MapEmptyPolicy.showsRadar(packMounted: false, sosOnly: false, radarOn: true, extremeSaver: true))
        XCTAssertFalse(MapEmptyPolicy.showsRadar(packMounted: true, sosOnly: false, radarOn: true, extremeSaver: false))
        XCTAssertFalse(MapEmptyPolicy.showsRadar(packMounted: true, sosOnly: false, radarOn: true, extremeSaver: true))
    }

    func testMountedPackPaintsFileTiles() {
        XCTAssertFalse(MapEmptyPolicy.showsEmptyCard(packMounted: true))
        XCTAssertTrue(MapEmptyPolicy.paintsCanvas(packMounted: true))
        XCTAssertTrue(MapEmptyPolicy.showsChips(packMounted: true, sosOnly: false))
        XCTAssertFalse(MapEmptyPolicy.showsChips(packMounted: true, sosOnly: true))
    }

    func testFollowGPSStaysOnCoveringPack() {
        XCTAssertTrue(MapEmptyPolicy.followGPS(pinToPack: false, packContainsSelf: true))
        XCTAssertFalse(MapEmptyPolicy.followGPS(pinToPack: true, packContainsSelf: true))
        XCTAssertFalse(MapEmptyPolicy.followGPS(pinToPack: false, packContainsSelf: false))
        XCTAssertFalse(MapEmptyPolicy.followGPS(pinToPack: true, packContainsSelf: false))
    }

    func testEmptyCopyStaysOriginalPlusHonestNoTiles() {
        XCTAssertEqual(MapEmptyCopy.noPack, "No pack for this area")
        XCTAssertEqual(MapEmptyCopy.noTiles, "No tiles for this location")
        XCTAssertEqual(MapEmptyCopy.eyebrow, "MAP")
    }
}
