import XCTest
@testable import Vitals

final class VitalsTests: XCTestCase {
    func testBands() {
        XCTAssertEqual(PartyVitals(water: 0.1, fatigue: 0.1, weatherExposure: 0.1).band, .green)
        XCTAssertEqual(PartyVitals(water: 0.5, fatigue: 0.2, weatherExposure: 0.1).band, .yellow)
        XCTAssertEqual(PartyVitals(water: 0.2, fatigue: 0.2, weatherExposure: 0.2, flags: ["RED"]).band, .red)
        XCTAssertEqual(
            ConditionBand.allCases.map(\.rawValue),
            ["green", "yellow", "orange", "red", "black"]
        )
        XCTAssertEqual(
            PartyVitals(
                hunger: 1.0,
                thirst: 0.2,
                pain: 0.2,
                water: 0.2,
                fatigue: 0.2,
                weatherExposure: 0.2
            ).band,
            .black
        )
    }

    func testSixAxesDriveBand() {
        let axes = PartyVitals(hunger: 0.1, thirst: 0.1, pain: 0.9, water: 0.1, fatigue: 0.1, weatherExposure: 0.1)
        XCTAssertEqual(axes.band, .red)
        XCTAssertEqual(PartyVitals(hunger: 0.5, thirst: 0.1, pain: 0.1, water: 0.1, fatigue: 0.1, weatherExposure: 0.1).band, .yellow)
        XCTAssertEqual(
            PartyVitals(hunger: 0.65, thirst: 0.1, pain: 0.1, water: 0.1, fatigue: 0.1, weatherExposure: 0.1).band,
            .orange
        )
    }

    func testRailSnapsToBandTicks() {
        XCTAssertEqual(PartyVitals.yellowAt, 0.45)
        XCTAssertEqual(PartyVitals.orangeAt, 0.65)
        XCTAssertEqual(PartyVitals.redAt, 0.8)
        XCTAssertEqual(PartyVitals.blackAt, 1.0)
        XCTAssertEqual(PartyVitals.blackLoad, 4)
        XCTAssertEqual(PartyVitals.colorSteps, [0.2, 0.45, 0.65, 0.8, 1.0])
        XCTAssertEqual(
            PartyVitals.railTitles,
            ["HUNGER", "THIRST", "PAIN", "WATER", "FATIGUE", "EXPOSURE"]
        )
        XCTAssertEqual(PartyVitals.stackYellowToOrange, 2)
        XCTAssertEqual(PartyVitals.stackYellowToRed, 3)
        XCTAssertEqual(PartyVitals.stackOrangeToRed, 2)
        XCTAssertEqual(PartyVitals.railSteps, [0, 0.2, 0.45, 0.65, 0.8, 1.0])
        XCTAssertEqual(PartyVitals.snap(0.1), 0.2)
        XCTAssertEqual(PartyVitals.snap(0.625), 0.65)
        XCTAssertEqual(PartyVitals.snap(0.73), 0.8)
        XCTAssertEqual(PartyVitals.step(0.2, 1), 0.45)
        XCTAssertEqual(PartyVitals.step(0.45, 1), 0.65)
        XCTAssertEqual(PartyVitals.step(0.2, -1), 0.0)
        XCTAssertEqual(PartyVitals.step(1.0, 1), 1.0)
        XCTAssertEqual(PartyVitals.band(of: 0.2), .green)
        XCTAssertEqual(PartyVitals.band(of: 0.45), .yellow)
        XCTAssertEqual(PartyVitals.band(of: 0.65), .orange)
        XCTAssertEqual(PartyVitals.band(of: 0.8), .red)
        XCTAssertEqual(PartyVitals.band(of: 0.999), .red)
        XCTAssertEqual(PartyVitals.band(of: 1.0), .black)
        XCTAssertEqual(PartyVitals.load(of: 0.2), 0)
        XCTAssertEqual(PartyVitals.load(of: 0.45), 1)
        XCTAssertEqual(PartyVitals.load(of: 0.65), 2)
        XCTAssertEqual(PartyVitals.load(of: 0.8), 3)
        XCTAssertEqual(PartyVitals.load(of: 1.0), 4)
        let packed = PartyVitals.fromPOS([0.1, 0.2, 0.45, 0.65, 0.8, 1.0])
        XCTAssertEqual(packed?.hunger, 0.2)
        XCTAssertEqual(packed?.thirst, 0.2)
        XCTAssertEqual(packed?.pain, 0.45)
        XCTAssertEqual(packed?.water, 0.65)
        XCTAssertEqual(packed?.fatigue, 0.8)
        XCTAssertEqual(packed?.weatherExposure, 1.0)
        XCTAssertNil(PartyVitals.fromPOS(nil))
        XCTAssertNil(PartyVitals.fromPOS([0.2, 0.2]))
        XCTAssertEqual(
            PartyVitals(water: 0.2, fatigue: 0.2, weatherExposure: 0.2).posRails,
            [0.2, 0.2, 0.2, 0.2, 0.2, 0.2]
        )
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
        XCTAssertEqual(twoYellow.band, .orange)
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
        let oneOrange = PartyVitals(
            hunger: 0.65,
            thirst: 0.2,
            pain: 0.2,
            water: 0.2,
            fatigue: 0.2,
            weatherExposure: 0.2
        )
        XCTAssertEqual(oneOrange.band, .orange)
        let twoOrange = PartyVitals(
            hunger: 0.65,
            thirst: 0.65,
            pain: 0.2,
            water: 0.2,
            fatigue: 0.2,
            weatherExposure: 0.2
        )
        XCTAssertEqual(twoOrange.band, .red)
        let orangePlusYellow = PartyVitals(
            hunger: 0.65,
            thirst: 0.45,
            pain: 0.2,
            water: 0.2,
            fatigue: 0.2,
            weatherExposure: 0.2
        )
        XCTAssertEqual(orangePlusYellow.band, .red)
        XCTAssertEqual(PartyVitals.orangeLoad * PartyVitals.stackOrangeToRed, 4)
        let oneBlack = PartyVitals(
            hunger: 1.0,
            thirst: 0.2,
            pain: 0.2,
            water: 0.2,
            fatigue: 0.2,
            weatherExposure: 0.2
        )
        XCTAssertEqual(oneBlack.band, .black)
        XCTAssertEqual(oneBlack.blackTitles, ["HUNGER"])
        XCTAssertEqual(
            oneBlack.partyAlertLine(coordinates: "31.76190, -106.49000", bearing: "042°"),
            "SOS HUNGER BLACK 31.76190, -106.49000 042°"
        )
        let twoBlack = PartyVitals(
            hunger: 1.0,
            thirst: 1.0,
            pain: 0.2,
            water: 0.2,
            fatigue: 0.2,
            weatherExposure: 0.2
        )
        XCTAssertEqual(twoBlack.band, .black)
        XCTAssertEqual(
            twoBlack.partyAlertLine(coordinates: "NO FIX", bearing: "NO HEADING"),
            "SOS CONDITION BLACK NO FIX NO HEADING"
        )
        let redFlagStillBlack = PartyVitals(
            hunger: 1.0,
            thirst: 0.2,
            pain: 0.2,
            water: 0.2,
            fatigue: 0.2,
            weatherExposure: 0.2,
            flags: ["RED"]
        )
        XCTAssertEqual(redFlagStillBlack.band, .black)
    }
}
