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
}
