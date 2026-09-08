import XCTest
@testable import MapsChrome

final class MapRightEdgeTests: XCTestCase {
    func testDestRouteShowsNavAndRecedesChips() {
        XCTAssertEqual(MapRightEdge.stack(routeInPlay: true), .nav)
        XCTAssertFalse(MapRightEdge.showsBoth(routeInPlay: true))
    }

    func testIdleMapShowsChipsAndRecedesNav() {
        XCTAssertEqual(MapRightEdge.stack(routeInPlay: false), .chips)
        XCTAssertFalse(MapRightEdge.showsBoth(routeInPlay: false))
    }
}
