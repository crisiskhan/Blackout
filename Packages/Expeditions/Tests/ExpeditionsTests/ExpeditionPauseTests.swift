import XCTest
@testable import Expeditions

final class ExpeditionPauseTests: XCTestCase {
    func testRosterEmptyCopyIsHonestSolo() {
        XCTAssertEqual(ExpeditionPauseCopy.rosterEmpty, "Solo outing. Roster is empty.")
    }

    func testGearStubCopyIsHonest() {
        XCTAssertEqual(ExpeditionPauseCopy.gearStub, "No custom kit. Default outing list.")
    }

    func testPacksRowOpensManagerNotDownloadWall() {
        XCTAssertEqual(ExpeditionPauseCopy.packsReady, "Florida, Texas, New York, and New Mexico are Ready on this phone.")
        XCTAssertEqual(ExpeditionPauseCopy.packManager, "Pack manager")
        XCTAssertFalse(ExpeditionPauseCopy.packsReady.localizedCaseInsensitiveContains("download"))
    }

    func testDefaultGearIsToolsListNotGrid() {
        XCTAssertLessThan(DefaultOutingGear.items.count, 17)
        XCTAssertEqual(DefaultOutingGear.items, [
            "Headlamp",
            "Knife",
            "Cordage",
            "Ferro rod",
            "Tarp kit",
            "Repair kit"
        ])
    }

    func testPauseSectionsStayFour() {
        XCTAssertEqual(ExpeditionPauseCopy.sections, ["Roster", "Gear", "Packs", "Settings"])
    }
}
