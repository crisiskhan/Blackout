import XCTest
@testable import MapsRouting

final class CompassLockTests: XCTestCase {
    func testStandardsAreTheSingleSeedList() {
        XCTAssertEqual(CompassLockStandards.waypoints.map(\.id), ["th", "wc"])
        XCTAssertEqual(CompassLockStandards.waypoints[0].name, "Trailhead")
        XCTAssertEqual(CompassLockStandards.waypoints[0].latitude, 31.8924, accuracy: 0.00001)
        XCTAssertEqual(CompassLockStandards.waypoints[0].longitude, -106.4401, accuracy: 0.00001)
        XCTAssertEqual(CompassLockStandards.waypoints[1].name, "Water cache")
        XCTAssertEqual(CompassLockStandards.waypoints[1].kind, .standard)
        XCTAssertFalse(CompassLockStandards.waypoints[0].canDelete)
        XCTAssertFalse(CompassLockStandards.waypoints[1].canDelete)
        let packPOI = CompassLockWaypoint(
            id: "poi:town",
            name: "Anthony",
            latitude: 31.7889,
            longitude: -106.5983,
            kind: .poi
        )
        XCTAssertFalse(packPOI.canDelete)
    }

    func testRelBearingFormula() {
        XCTAssertEqual(CompassLockMath.relBearing(target: 90, heading: 0), 90, accuracy: 0.001)
        XCTAssertEqual(CompassLockMath.relBearing(target: 0, heading: 90), -90, accuracy: 0.001)
        XCTAssertEqual(CompassLockMath.relBearing(target: 0, heading: 0), 0, accuracy: 0.001)
        XCTAssertEqual(CompassLockMath.relBearing(target: 10, heading: 350), 20, accuracy: 0.001)
        XCTAssertEqual(CompassLockMath.relBearing(target: 350, heading: 10), -20, accuracy: 0.001)
        XCTAssertEqual(CompassLockMath.relBearing(target: 8, heading: 0), 8, accuracy: 0.001)
        XCTAssertEqual(CompassLockMath.relBearing(target: 9, heading: 0), 9, accuracy: 0.001)
    }

    func testTurnPhraseHoldAndSides() {
        XCTAssertEqual(CompassLockMath.turnPhrase(rel: 0), "Hold course")
        XCTAssertEqual(CompassLockMath.turnPhrase(rel: 8), "Hold course")
        XCTAssertEqual(CompassLockMath.turnPhrase(rel: -8), "Hold course")
        XCTAssertEqual(CompassLockMath.turnPhrase(rel: 9), "Right 9°")
        XCTAssertEqual(CompassLockMath.turnPhrase(rel: -12.4), "Left 12°")
        XCTAssertEqual(CompassLockMath.turnPhrase(rel: 45.6), "Right 46°")
    }

    func testVoicePhraseAndDistance() {
        XCTAssertEqual(
            CompassLockMath.phrase(name: "Trailhead", meters: 420, rel: 0),
            "Trailhead. 420 m. Hold course."
        )
        XCTAssertEqual(
            CompassLockMath.phrase(name: "Water cache", meters: 1_200, rel: -30),
            "Water cache. 1.2 km. Left 30°."
        )
        XCTAssertEqual(CompassLockCopy.nothingToLock, "Nothing to lock. MARK a point or wait for a peer.")
    }

    func testMarkNameHHMMAndRequired() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 30
        parts.hour = 17
        parts.minute = 30
        let date = calendar.date(from: parts)!
        XCTAssertEqual(CompassLockMath.defaultMarkName(at: date, calendar: calendar), "1730")
        XCTAssertNil(CompassLockMath.committedName("   "))
        XCTAssertEqual(CompassLockMath.committedName(" Cache "), "Cache")
    }

    func testPhraseUsesBearingNeverStreetTurns() {
        let origin = RoutingCoordinate(latitude: 31.8900, longitude: -106.4401)
        let target = CompassLockStandards.waypoints[0].coordinate
        let spoken = CompassLockMath.phrase(
            name: "Trailhead",
            origin: origin,
            target: target,
            heading: 0
        )
        XCTAssertTrue(spoken.hasPrefix("Trailhead. "))
        XCTAssertTrue(spoken.contains("Hold course") || spoken.contains("Right") || spoken.contains("Left"))
        XCTAssertFalse(spoken.contains("turn left"))
        XCTAssertFalse(spoken.contains("Mesa Street"))
    }

    func testLockOnLineIsMockHeaderNotACapsule() {
        XCTAssertEqual(CompassLockMath.lockOnLine(headingDegrees: 302), "LOCK ON • 302° NW")
        XCTAssertEqual(CompassLockMath.lockOnLine(headingDegrees: 0), "LOCK ON • 0° N")
        XCTAssertEqual(CompassLockMath.lockOnLine(headingDegrees: nil), "LOCK ON")
        XCTAssertEqual(CompassLockMath.cardinal(302), "NW")
    }

    func testVoiceLockConstants() {
        XCTAssertEqual(CompassLockMath.voiceInterval, 2.2, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(CompassLockMath.speechRate, CompassLockMath.speechRateMin)
        XCTAssertLessThanOrEqual(CompassLockMath.speechRate, CompassLockMath.speechRateMax)
    }
}
