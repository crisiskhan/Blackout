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
}
