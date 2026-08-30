import BlackoutCore
import DesignSystem
import XCTest
@testable import Expeditions

final class ExpeditionPauseTests: XCTestCase {
    func testRosterEmptyCopyIsHonestSolo() {
        XCTAssertEqual(ExpeditionPauseCopy.rosterEmpty, "Solo outing. Roster is empty.")
    }

    func testGearStubCopyIsHonest() {
        XCTAssertEqual(ExpeditionPauseCopy.gearStub, "No custom kit. Default outing list.")
    }

    func testPacksPlateIsCatalogNotDownloadWall() {
        XCTAssertEqual(
            ExpeditionPauseCopy.packsReady,
            "Florida, Texas, New York, and New Mexico are Ready on this phone. 4 states on disk."
        )
        XCTAssertFalse(ExpeditionPauseCopy.packsReady.localizedCaseInsensitiveContains("download"))
    }

    func testMapBannerIsThinHonestEmpty() {
        XCTAssertEqual(ExpeditionPauseCopy.mapBannerEmpty, "No open expedition")
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
        XCTAssertEqual(ExpeditionPauseCopy.about, "About")
        XCTAssertFalse(ExpeditionPauseCopy.sections.contains("About"))
    }

    func testRosterKeepsHonestEmptyAndTwoTapVitals() {
        XCTAssertEqual(ExpeditionPauseCopy.rosterEmpty, "Solo outing. Roster is empty.")
        XCTAssertEqual(PartyVitalsCopy.drank, "DRANK")
        XCTAssertEqual(PartyVitalsCopy.ate, "ATE")
        XCTAssertEqual(PartyVitalsCopy.notOK, "I AM NOT OK")
    }

    func testRosterPlateOwnsCallsignAndPartyCode() {
        XCTAssertEqual(PartyIdentityCopy.callsign, "Callsign")
        XCTAssertEqual(PartyIdentityCopy.create, "Create")
        XCTAssertEqual(PartyIdentityCopy.join, "Join")
        XCTAssertEqual(PartyIdentityCopy.leave, "Leave")
        XCTAssertEqual(PartyIdentityCopy.end, "End")
        XCTAssertEqual(PartyIdentityCopy.noParty, "No party")
        XCTAssertEqual(PartyIdentityCopy.soloValid, "Solo. Mesh is off until you Create or Join.")
        XCTAssertEqual(PartyIdentityCopy.outingNameHint, "Outing name. Not your callsign.")
        XCTAssertEqual(Callsign.defaultValue, "YOU")
        XCTAssertEqual(Callsign.maxLength, 12)
    }

    func testVitalsChipIs56AndSOSStays88() {
        XCTAssertEqual(PartyVitalsCopy.chipHeight, 56)
        XCTAssertEqual(PartyVitalsCopy.sosHeight, 88)
        XCTAssertEqual(BlackoutDS.Vitals.chip, 56)
        XCTAssertEqual(BlackoutDS.Vitals.pip, 6)
        XCTAssertEqual(BlackoutDS.Vitals.sosGap, 8)
        XCTAssertEqual(BlackoutDS.Vitals.sosClearance, 88)
        XCTAssertEqual(BlackoutDS.Vitals.tabBar, 49)
        XCTAssertEqual(BlackoutDS.Hit.sm, 56)
        XCTAssertEqual(BlackoutDS.Hit.sos, 88)
        XCTAssertEqual(BlackoutDS.Motion.moveDuration, 0.220)
        XCTAssertEqual(BlackoutDS.Motion.snapDuration, 0.120)
    }
}
