import XCTest
@testable import MapsRouting

final class RoadLookTests: XCTestCase {
    func testWalkOnlyIsTrail() {
        let edge = RoutingEdge(
            from: 0, to: 1, nameId: 2,
            flags: RoutingLayout.walkFlag,
            lengthCm: 1000, walkMs: 800, driveMs: 0
        )
        XCTAssertEqual(RoadLook.classify(edge: edge, name: "Arroyo Path"), .trail)
    }

    func testHighwayNameAndShield() {
        let edge = RoutingEdge(
            from: 0, to: 1, nameId: 1,
            flags: RoutingLayout.walkFlag | RoutingLayout.driveFlag,
            lengthCm: 1000, walkMs: 800, driveMs: 400
        )
        XCTAssertEqual(RoadLook.classify(edge: edge, name: "I-10"), .highway)
        XCTAssertEqual(RoadLook.shieldText("I-10"), "10")
        XCTAssertEqual(RoadLook.shieldText("US 54"), "54")
        XCTAssertEqual(RoadLook.displayName("MESA STREET"), "Mesa Street")
        XCTAssertEqual(RoadLook.displayName("Mesa Street"), "Mesa Street")
    }

    func testDriveSpeedSplitsLocalAndArterial() {
        let flags = RoutingLayout.walkFlag | RoutingLayout.driveFlag
        let local = RoutingEdge(from: 0, to: 1, nameId: 1, flags: flags, lengthCm: 1000, walkMs: 800, driveMs: 1_200)
        let arterial = RoutingEdge(from: 0, to: 1, nameId: 1, flags: flags, lengthCm: 1000, walkMs: 800, driveMs: 700)
        XCTAssertEqual(RoadLook.classify(edge: local, name: "Oregon St"), .local)
        XCTAssertEqual(RoadLook.classify(edge: arterial, name: "Mesa"), .arterial)
    }

    func testNoActiveTurnMeansZeroChevrons() {
        XCTAssertFalse(RoadLook.isActiveTurn(.depart))
        XCTAssertFalse(RoadLook.isActiveTurn(.arrive))
        XCTAssertTrue(RoadLook.isActiveTurn(.left))
        XCTAssertTrue(RoadLook.isActiveTurn(.right))
    }
}
