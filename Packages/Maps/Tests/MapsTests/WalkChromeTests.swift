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

    func testOffCourseHapticFiresOnRisingEdgeOnly() {
        XCTAssertTrue(WalkChrome.shouldFireOffCourseHaptic(wasOffRoute: false, nowOffRoute: true))
        XCTAssertFalse(WalkChrome.shouldFireOffCourseHaptic(wasOffRoute: true, nowOffRoute: true))
        XCTAssertFalse(WalkChrome.shouldFireOffCourseHaptic(wasOffRoute: false, nowOffRoute: false))
        XCTAssertFalse(WalkChrome.shouldFireOffCourseHaptic(wasOffRoute: true, nowOffRoute: false))
    }

    func testReturnBreadcrumbDashesEstimatedAndSolidsGPS() {
        let start = WalkReturnBreadcrumb.Node(latitude: 31.76, longitude: -106.48, estimated: false)
        let gps = WalkReturnBreadcrumb.Node(latitude: 31.761, longitude: -106.481, estimated: false)
        let guessed = WalkReturnBreadcrumb.Node(latitude: 31.762, longitude: -106.482, estimated: true)
        let end = WalkReturnBreadcrumb.Node(latitude: 31.763, longitude: -106.483, estimated: false)

        let walked = WalkReturnBreadcrumb.segments(start: start, crumbs: [gps, guessed], end: end)
        XCTAssertEqual(walked.count, 3)
        XCTAssertFalse(walked[0].dashed)
        XCTAssertTrue(walked[1].dashed)
        XCTAssertTrue(walked[2].dashed)

        let estimatedReturn = WalkReturnBreadcrumb.segments(start: start, crumbs: [], end: end)
        XCTAssertEqual(estimatedReturn.count, 1)
        XCTAssertTrue(estimatedReturn[0].dashed)

        XCTAssertTrue(WalkReturnBreadcrumb.segments(start: start, crumbs: [], end: nil).isEmpty)
    }
}
