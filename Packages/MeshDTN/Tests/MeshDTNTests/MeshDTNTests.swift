import XCTest
import BlackBox
@testable import MeshDTN

final class MeshDTNTests: XCTestCase {
    func testAirplaneNoJoin() {
        let net = MeshNet(box: EventLog())
        net.startLocal()
        XCTAssertFalse(net.joined)
        net.meet("peer")
        XCTAssertEqual(net.linkKind(), .bleTensOfMeters)
    }
}
