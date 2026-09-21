import XCTest
@testable import KitStore

final class KitStoreTests: XCTestCase {
    func testHazard() {
        var bag = KitBag(items: [GearItem(id: "stove", name: "Stove", working: true, failureHazard: nil)])
        bag.markFailed("stove", hazard: "no boil")
        XCTAssertEqual(bag.hazards, ["no boil"])
        bag.setWorking("stove", working: true)
        XCTAssertEqual(bag.hazards, [])
    }

    func testCountAssignAndNamedAdd() {
        var bag = KitBag(items: [GearItem(id: "stove", name: "Stove", working: true)])
        XCTAssertEqual(bag.items[0].count, 1)
        bag.bump("stove", by: 1)
        XCTAssertEqual(bag.items[0].count, 2)
        bag.bump("stove", by: -5)
        XCTAssertEqual(bag.items[0].count, 0)
        bag.assign("stove", to: "Khan")
        XCTAssertEqual(bag.items[0].assignedTo, "Khan")
        XCTAssertEqual(bag.assigned(to: "peer-1", name: "Khan", isYou: false).map(\.id), ["stove"])
        XCTAssertTrue(bag.assigned(to: "YOU", name: "", isYou: true).isEmpty)
        bag.addNamed("Tape")
        XCTAssertEqual(bag.items.last?.name, "Tape")
        XCTAssertEqual(bag.items.last?.count, 1)
        bag.addNamed("   ")
        XCTAssertEqual(bag.items.filter { $0.name == "Tape" }.count, 1)
    }

    func testYouInventoryKeepsCountAfterBump() {
        var bag = KitBag(items: [GearItem(id: "tape", name: "Tape", working: true, count: 3)])
        bag.assign("tape", to: "YOU")
        XCTAssertEqual(bag.assigned(to: "YOU", name: "Khan", isYou: true).first?.count, 3)
        bag.bump("tape", by: -1)
        XCTAssertEqual(bag.assigned(to: "YOU", name: "Khan", isYou: true).first?.count, 2)
        bag.assign("tape", to: "Khan")
        XCTAssertEqual(bag.assigned(to: "YOU", name: "Khan", isYou: true).map(\.name), ["Tape"])
        XCTAssertTrue(bag.assigned(to: "peer", name: "Sam", isYou: false).isEmpty)
    }

    func testBagSurvivesKill() {
        var bag = KitBag(items: [GearItem(id: "water", name: "Water", working: true, count: 3)])
        bag.assign("water", to: "YOU")
        bag.addNamed("Tape")
        let suite = UserDefaults(suiteName: "you.kit.test.\(UUID().uuidString)")!
        XCTAssertEqual(KitBag.load(defaults: suite).items.map(\.name), ["Water"])
        XCTAssertEqual(KitBag.load(defaults: suite).items.first?.count, 0)
        KitBag.save(bag, defaults: suite)
        let back = KitBag.load(defaults: suite)
        XCTAssertEqual(back.items.map(\.name), ["Water", "Tape"])
        XCTAssertEqual(back.items.first?.count, 3)
        XCTAssertEqual(back.items.first?.assignedTo, "YOU")
        suite.set("nope", forKey: KitBag.persistKey)
        XCTAssertEqual(KitBag.load(defaults: suite).items.map(\.name), ["Water"])
        XCTAssertEqual(KitBag.load(defaults: suite).items.first?.count, 0)
    }
}
