import XCTest
@testable import DeadReckoning

final class DeadReckoningTests: XCTestCase {
    func testNorthWalk() {
        let p = DeadReckoning.advance(DRFix(lat: 0, lon: 0, headingDeg: 0, strideMeters: 1, steps: 111_320))
        XCTAssertEqual(p.lat, 1, accuracy: 0.01)
        XCTAssertEqual(DeadReckoning.calibrateStride(knownMeters: 100, steps: 125), 0.8, accuracy: 0.001)
    }
}
