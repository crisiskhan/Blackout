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
}
