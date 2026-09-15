import XCTest
@testable import RosterRoles

final class RosterRolesTests: XCTestCase {
    func testCreateJoin() {
        let r = PartyRoster.create(lead: "A").joining("B", role: .nav)
        XCTAssertEqual(r.members.count, 2)
        XCTAssertEqual(r.members[0].role, .lead)
    }

    func testJoiningSameRoleDoesNotDuplicateNav() {
        let r = PartyRoster.create(lead: "Lead")
            .joining("Nav", role: .nav)
            .joining("Nav", role: .nav)
        XCTAssertEqual(r.members.filter { $0.role == .nav }.count, 1)
        XCTAssertEqual(r.members.count, 2)
        XCTAssertEqual(Set(r.members.map(\.role)).count, r.members.count)
    }

    func testRoleTitlesAndUniqueSeats() {
        XCTAssertEqual(PartyRole.lead.title, "LEAD")
        XCTAssertEqual(PartyRole.medic.title, "MEDIC")
        XCTAssertEqual(PartyRole.nav.title, "NAV")
        XCTAssertEqual(PartyRole.tail.title, "TAIL")
        XCTAssertEqual(PartyRole.guest.title, "GUEST")
        XCTAssertTrue(PartyRole.lead.uniqueSeat)
        XCTAssertTrue(PartyRole.medic.uniqueSeat)
        XCTAssertTrue(PartyRole.nav.uniqueSeat)
        XCTAssertTrue(PartyRole.tail.uniqueSeat)
        XCTAssertFalse(PartyRole.guest.uniqueSeat)
        XCTAssertEqual(PartyRole.lead.next, .medic)
        XCTAssertEqual(PartyRole.guest.next, .lead)
        XCTAssertEqual(PartyRole.lead.nextOpen(taken: [.nav]), .medic)
        XCTAssertEqual(PartyRole.medic.nextOpen(taken: [.lead, .medic, .nav, .tail]), .guest)
    }

    func testLiveYouIsFirstEvenSolo() {
        let planted = PartyRoster.create(lead: "Lead")
        let solo = planted.live(
            youID: "local-1",
            youName: "",
            youEmblem: "wolf",
            youStatusTitle: "GOOD",
            peers: []
        )
        XCTAssertEqual(solo.count, 1)
        XCTAssertEqual(solo[0].id, "local-1")
        XCTAssertEqual(solo[0].name, "YOU")
        XCTAssertEqual(solo[0].role, .lead)
        XCTAssertEqual(solo[0].emblem, "wolf")
        XCTAssertEqual(solo[0].statusTitle, "GOOD")
        let named = planted.live(
            youID: "local-1",
            youName: "KHAN",
            youEmblem: "owl",
            youStatusTitle: "OKAY",
            peers: []
        )
        XCTAssertEqual(named[0].name, "KHAN")
        let seated = planted
            .seating(id: "local-1", name: "KHAN", role: .nav)
            .seating(id: "peer-1", name: "RUI", role: .medic)
        let rows = seated.live(
            youID: "local-1",
            youName: "KHAN",
            youEmblem: "wolf",
            youStatusTitle: "GOOD",
            peers: [
                RosterPeer(id: "peer-1", name: "RUI", emblem: "owl", statusTitle: "OKAY"),
                RosterPeer(id: "peer-2", name: "SAM", emblem: "bear", statusTitle: "GOOD"),
                RosterPeer(id: "local-1", name: "echo", emblem: "wolf", statusTitle: "GOOD"),
            ]
        )
        XCTAssertEqual(rows.map(\.id), ["local-1", "peer-1", "peer-2"])
        XCTAssertEqual(rows.map(\.role), [.nav, .medic, .guest])
        XCTAssertFalse(rows.contains(where: { $0.id == "lead" }))
    }

    func testSeatingNavIsStickyAndUnique() {
        let you = PartyRoster.create(lead: "YOU").rebindingLead(to: "you", name: "YOU")
        XCTAssertEqual(you.members[0].id, "you")
        let nav = you.seating(id: "you", name: "YOU", role: .nav)
        XCTAssertEqual(nav.members.first { $0.id == "you" }?.role, .nav)
        XCTAssertEqual(nav.seating(id: "you", name: "YOU", role: .nav), nav)
        XCTAssertEqual(nav.seating(id: "peer", name: "RUI", role: .nav), nav)
        let guests = nav
            .seating(id: "a", name: "A", role: .guest)
            .seating(id: "b", name: "B", role: .guest)
        XCTAssertEqual(guests.members.filter { $0.role == .guest }.count, 2)
        let rows = nav.live(
            youID: "you",
            youName: "YOU",
            youEmblem: "wolf",
            youStatusTitle: "GOOD",
            peers: [RosterPeer(id: "peer", name: "RUI", emblem: "owl", statusTitle: "GOOD")]
        )
        let cycled = nav.cycling(id: "you", name: "YOU", from: rows)
        XCTAssertEqual(cycled.members.first { $0.id == "you" }?.role, .tail)
    }
}
