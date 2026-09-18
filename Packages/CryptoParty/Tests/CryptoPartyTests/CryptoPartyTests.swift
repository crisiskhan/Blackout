import XCTest
import CryptoKit
@testable import CryptoParty

final class CryptoPartyTests: XCTestCase {
    func testSealOpenAndGuest4h() throws {
        let key = SymmetricKey(size: .bits256)
        let box = try CryptoParty.seal(plain: Data("ok".utf8), key: key)
        XCTAssertEqual(try CryptoParty.open(box, key: key), Data("ok".utf8))
        let d = CryptoParty.guestDeadline()
        XCTAssertTrue(CryptoParty.guestValid(d))
        XCTAssertFalse(CryptoParty.guestValid(d.addingTimeInterval(-5 * 3600), now: Date()))
    }

    func testWrapRoundtripAndWrongKeyFails() throws {
        let key = PartySeal.key(code: "abc123")
        let again = PartySeal.key(code: "ABC123")
        let plain = Data("31.76,-106.49".utf8)
        let wire = try PartySeal.wrap(plain, key: key)
        XCTAssertTrue(PartySeal.isSealed(wire))
        XCTAssertEqual(try PartySeal.unwrap(wire, key: again), plain)
        XCTAssertNil(PartySeal.openBody(wire, key: PartySeal.key(code: "ZZZZZZ")))
        XCTAssertThrowsError(try PartySeal.unwrap(plain, key: key))
    }

    func testOpenBodyKeepsPlaintext() {
        let key = PartySeal.key(code: "ABC123")
        let plain = Data("rally".utf8)
        XCTAssertFalse(PartySeal.isSealed(plain))
        XCTAssertEqual(PartySeal.openBody(plain, key: key), plain)
        XCTAssertEqual(PartySeal.openBody(plain, key: nil), plain)
        XCTAssertNil(PartySeal.openBody(Data([0x42, 0x4F, 0x31, 0x00]), key: nil))
    }
}
