import XCTest
@testable import BlackoutCore

final class FieldPingTests: XCTestCase {
    func testPingCopyAndHuesAreLocked() {
        XCTAssertEqual(FieldPingID.allCases.map(FieldPing.label), [
            "Rally here",
            "Need escort",
            "Danger here",
            "I'm down",
        ])
        XCTAssertEqual(FieldPing.hue(.rally), .ok)
        XCTAssertEqual(FieldPing.hue(.escort), .warn)
        XCTAssertEqual(FieldPing.hue(.danger), .red)
        XCTAssertEqual(FieldPing.hue(.down), .red)
        XCTAssertEqual(FieldPing.chipHeight, 56)
        XCTAssertEqual(FieldPing.cardHeight, 64)
        XCTAssertEqual(FieldPing.pip, 8)
        XCTAssertLessThan(FieldPing.chipHeight, 88)
        XCTAssertLessThan(FieldPing.cardHeight, 88)
    }

    func testReplyCopyAndHuesAreLocked() {
        XCTAssertEqual(FieldReplyID.allCases.map(FieldPing.label), [
            "Copy",
            "Coming",
            "Hold",
            "Can't",
        ])
        XCTAssertEqual(FieldPing.hue(.copy), .ok)
        XCTAssertEqual(FieldPing.hue(.coming), .ok)
        XCTAssertEqual(FieldPing.hue(.hold), .warn)
        XCTAssertEqual(FieldPing.hue(.cant), .red)
        XCTAssertTrue(FieldPing.requiresSenderPin(.coming))
        XCTAssertFalse(FieldPing.requiresSenderPin(.copy))
        XCTAssertFalse(FieldPing.requiresSenderPin(.hold))
        XCTAssertFalse(FieldPing.requiresSenderPin(.cant))
    }

    func testHapticsAreLightGreenMediumYellowRed() {
        XCTAssertEqual(FieldPing.haptic(.ok), .light)
        XCTAssertEqual(FieldPing.haptic(.warn), .medium)
        XCTAssertEqual(FieldPing.haptic(.red), .medium)
    }

    func testImDownIsCommsOnlyNotSOS() {
        XCTAssertEqual(FieldPing.envelopeKind, .message)
        XCTAssertNotEqual(FieldPing.envelopeKind, .sosAlert)
        XCTAssertFalse(FieldPing.armsSOS)
        XCTAssertFalse(FieldPing.autoDials911)
        XCTAssertFalse(FieldPing.downSetsInjury)
        XCTAssertFalse(SOSConfirm.autoDials911)
        XCTAssertNotEqual(FieldPing.envelopeKind, SOSConfirm.meshKind)
        XCTAssertFalse(FieldPing.label(.down).contains("911"))
        XCTAssertFalse(FieldPing.label(.down).localizedCaseInsensitiveContains("sos"))
    }

    func testPinFootnoteIsHonestNoFixOrCoords() {
        XCTAssertEqual(SealedChatBody(text: "x", noFix: true).pinFootnote(), SOSConfirm.noFix)
        let pinned = SealedChatBody(text: "x", latitude: 31.76190, longitude: -106.48500)
        XCTAssertEqual(pinned.pinFootnote(), "31.76190, -106.48500")
        let aged = SealedChatBody(
            text: "x",
            latitude: 31.76190,
            longitude: -106.48500,
            fixAgeSeconds: 12
        )
        XCTAssertEqual(aged.pinFootnote(), "31.76190, -106.48500 · 12s")
    }
}
