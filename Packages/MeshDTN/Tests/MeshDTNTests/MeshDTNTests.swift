import XCTest
import BlackBox
@testable import MeshDTN

final class MeshDTNTests: XCTestCase {
    func testNetNoneIsLocalWrites() {
        let box = EventLog()
        let net = MeshNet(box: box)
        net.partyCode = "ABC123"
        net.startLocal()
        XCTAssertFalse(net.joined)
        XCTAssertEqual(net.chromeNet, "NET · NONE")
        XCTAssertEqual(net.linkKind(), .none)
        net.sendChip(from: "me", chip: "ok")
        XCTAssertEqual(net.store.count, 1)
        XCTAssertTrue(box.all().contains { $0.detail.contains("NET NONE local write") })
        XCTAssertFalse(net.loRaBrickPresent)
    }

    func testAirplaneBluetoothRadioJoins() {
        let net = MeshNet(box: EventLog())
        net.airplane = true
        net.partyCode = "ABC123"
        let radio = LoopbackRadio(path: .ble)
        net.attach(radio)
        net.startLocal()
        XCTAssertEqual(radio.startedCode, "ABC123")
        XCTAssertTrue(net.joined)
        XCTAssertEqual(net.chromeNet, "NET · BLE")
        XCTAssertEqual(net.linkKind(), .bleTensOfMeters)
        net.sendPOS(from: "me", lat: 31.76, lon: -106.49)
        net.sendChip(from: "me", chip: "ok")
        net.sendRED(from: "me", on: true)
        net.sendTimer(from: "me", task: "water", done: false)
        net.sendTimer(from: "me", task: "water", done: true)
        XCTAssertEqual(radio.sent.count, 5)
        XCTAssertEqual(net.pips.first?.lat, 31.76, accuracy: 0.01)
        XCTAssertFalse(net.loRaBrickPresent)
    }

    func testMPCPathChrome() {
        let net = MeshNet(box: EventLog())
        net.attach(LoopbackRadio(path: .mpc))
        net.partyCode = "ZZZ"
        net.startLocal()
        XCTAssertEqual(net.chromeNet, "NET · MPC")
    }

    func testMeetIsNotTheOnlyPath() {
        let net = MeshNet(box: EventLog())
        net.attach(LoopbackRadio(path: .ble))
        net.startLocal()
        XCTAssertTrue(net.joined)
        XCTAssertNotEqual(net.linkKind(), .dtnCarry)
    }
}
