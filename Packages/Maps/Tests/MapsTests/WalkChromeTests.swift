import XCTest
@testable import MapsRouting

final class WalkChromeTests: XCTestCase {
    func testDistanceIsMockMiles() {
        XCTAssertEqual(WalkChrome.distance(643.7), "0.4 mi")
        XCTAssertEqual(WalkChrome.distance(804.7), "0.5 mi")
        XCTAssertEqual(WalkChrome.distance(30), "100 ft")
    }

    func testRoadNameIsMockUppercase() {
        XCTAssertEqual(WalkChrome.roadName("Raven Rock Rd"), "RAVEN ROCK RD")
        XCTAssertEqual(WalkChrome.roadName("  mesa street "), "MESA STREET")
        XCTAssertEqual(WalkChrome.roadName(nil), "CONTINUE")
        XCTAssertEqual(WalkChrome.roadName(""), "CONTINUE")
    }

    func testTurnArrowMatchesKind() {
        XCTAssertEqual(WalkChrome.arrowSystemName(.right), "arrow.turn.up.right")
        XCTAssertEqual(WalkChrome.arrowSystemName(.left), "arrow.turn.up.left")
        XCTAssertEqual(WalkChrome.arrowSystemName(.straight), "arrow.up")
        XCTAssertEqual(WalkChrome.arrowSystemName(.uTurn), "arrow.uturn.left")
    }

    func testScaleLineIsMilesAndEta() {
        XCTAssertEqual(WalkChrome.scaleLine(meters: 804.7, etaSeconds: 60), "0.5 mi / 1 MIN")
    }
}
