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

    func testRailSnapsToBandTicks() {
        XCTAssertEqual(PartyVitals.yellowAt, 0.45)
        XCTAssertEqual(PartyVitals.redAt, 0.8)
        XCTAssertEqual(PartyVitals.stackYellowToRed, 3)
        XCTAssertEqual(PartyVitals.railSteps, [0, 0.2, 0.45, 0.8, 1.0])
        XCTAssertEqual(PartyVitals.snap(0.1), 0.2)
        XCTAssertEqual(PartyVitals.snap(0.625), 0.8)
        XCTAssertEqual(PartyVitals.step(0.2, 1), 0.45)
        XCTAssertEqual(PartyVitals.step(0.2, -1), 0.0)
        XCTAssertEqual(PartyVitals.step(1.0, 1), 1.0)
        XCTAssertEqual(PartyVitals.band(of: 0.2), .green)
        XCTAssertEqual(PartyVitals.band(of: 0.45), .yellow)
        XCTAssertEqual(PartyVitals.band(of: 0.8), .red)
    }

    func testStackedYellowIsARedBody() {
        let twoYellow = PartyVitals(
            hunger: 0.45,
            thirst: 0.45,
            pain: 0.2,
            water: 0.2,
            fatigue: 0.2,
            weatherExposure: 0.2
        )
        XCTAssertEqual(twoYellow.band, .yellow)
        let threeYellow = PartyVitals(
            hunger: 0.45,
            thirst: 0.45,
            pain: 0.45,
            water: 0.2,
            fatigue: 0.2,
            weatherExposure: 0.2
        )
        XCTAssertEqual(threeYellow.band, .red)
        let everyYellow = PartyVitals(
            hunger: 0.45,
            thirst: 0.45,
            pain: 0.45,
            water: 0.45,
            fatigue: 0.45,
            weatherExposure: 0.45
        )
        XCTAssertEqual(everyYellow.band, .red)
    }
}
