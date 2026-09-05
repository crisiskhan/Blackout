import XCTest
@testable import Vitals

final class VitalsTests: XCTestCase {
    func testBands() {
        XCTAssertEqual(PartyVitals(water: 0.1, fatigue: 0.1, weatherExposure: 0.1).band, .green)
        XCTAssertEqual(PartyVitals(water: 0.5, fatigue: 0.2, weatherExposure: 0.1).band, .yellow)
        XCTAssertEqual(PartyVitals(water: 0.2, fatigue: 0.2, weatherExposure: 0.2, flags: ["RED"]).band, .red)
    }

    func testSixAxesDriveBand() {
        let axes = PartyVitals(hunger: 0.1, thirst: 0.1, pain: 0.9, water: 0.1, fatigue: 0.1, weatherExposure: 0.1)
        XCTAssertEqual(axes.band, .red)
        XCTAssertEqual(PartyVitals(hunger: 0.5, thirst: 0.1, pain: 0.1, water: 0.1, fatigue: 0.1, weatherExposure: 0.1).band, .yellow)
    }
}
