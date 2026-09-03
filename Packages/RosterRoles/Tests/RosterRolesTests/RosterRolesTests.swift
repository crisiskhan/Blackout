import XCTest
@testable import RosterRoles

final class RosterRolesTests: XCTestCase {
    func testCreateJoin() {
        let r = PartyRoster.create(lead: "A").joining("B", role: .nav)
        XCTAssertEqual(r.members.count, 2)
        XCTAssertEqual(r.members[0].role, .lead)
    }
}
