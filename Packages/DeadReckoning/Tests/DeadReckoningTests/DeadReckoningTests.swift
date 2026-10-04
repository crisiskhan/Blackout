import XCTest
@testable import DeadReckoning

final class DeadReckoningTests: XCTestCase {
    func testNorthWalk() {
        let p = DeadReckoning.advance(DRFix(lat: 0, lon: 0, headingDeg: 0, strideMeters: 1, steps: 111_320))
        XCTAssertEqual(p.lat, 1, accuracy: 0.01)
        XCTAssertEqual(DeadReckoning.calibrateStride(knownMeters: 100, steps: 125), 0.8, accuracy: 0.001)
        let quiet = DeadReckoning.hold(
            last: (0, 0),
            headingDeg: 0,
            strideMeters: 1,
            steps: 0,
            ageSeconds: 12
        )
        XCTAssertEqual(quiet.chrome, DeadReckoning.lastFix)
        XCTAssertFalse(quiet.advanced)
        let far = DeadReckoning.hold(
            last: (0, 0),
            headingDeg: 0,
            strideMeters: 1,
            steps: 400,
            ageSeconds: 12
        )
        XCTAssertFalse(far.advanced)
        let step = DeadReckoning.hold(
            last: (0, 0),
            headingDeg: 0,
            strideMeters: 1,
            steps: 10,
            ageSeconds: 12
        )
        XCTAssertTrue(step.advanced)
        XCTAssertEqual(step.lat, 10.0 / 111_320.0, accuracy: 0.00001)
    }
}
