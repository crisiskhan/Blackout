import BlackoutCore
@testable import BlackoutCrypto
import XCTest

@MainActor
final class CryptoTests: XCTestCase {
    func testSelfSealRoundtrip() throws {
        let crypto = LoopbackCrypto(inMemoryForTesting: true)
        let box = try crypto.seal(Data("hi".utf8), to: crypto.localIdentity)
        XCTAssertEqual(box.first, 1)
        XCTAssertEqual(try crypto.open(box), Data("hi".utf8))
    }

    func testUnknownRecipientFallsBackToLocal() throws {
        let crypto = LoopbackCrypto(inMemoryForTesting: true)
        let box = try crypto.seal(Data("x".utf8), to: BlackoutID())
        XCTAssertEqual(box.first, 1)
        XCTAssertEqual(try crypto.open(box), Data("x".utf8))
    }

    func testPeerECDHRoundtrip() throws {
        let alice = LoopbackCrypto(inMemoryForTesting: true)
        let bob = LoopbackCrypto(inMemoryForTesting: true)
        alice.registerPeerAdvertisement(bob.localAdvertisement)
        bob.registerPeerAdvertisement(alice.localAdvertisement)
        XCTAssertEqual(alice.preferredRecipient, bob.localIdentity)
        XCTAssertEqual(bob.preferredRecipient, alice.localIdentity)
        let box = try alice.seal(Data("field".utf8), to: bob.localIdentity)
        XCTAssertEqual(box.first, 2)
        XCTAssertEqual(try bob.open(box), Data("field".utf8))
        XCTAssertThrowsError(try alice.open(box))
    }

    func testIgnoresSelfAdvertisement() {
        let crypto = LoopbackCrypto(inMemoryForTesting: true)
        crypto.registerPeerAdvertisement(crypto.localAdvertisement)
        XCTAssertEqual(crypto.preferredRecipient, crypto.localIdentity)
    }

    func testPartyCodeSealRoundtripBetweenDevices() throws {
        let alice = LoopbackCrypto(inMemoryForTesting: true)
        let bob = LoopbackCrypto(inMemoryForTesting: true)
        alice.setPartyCode("AB12CD")
        bob.setPartyCode("AB12CD")
        let box = try alice.seal(Data("group".utf8), partyCode: "AB12CD")
        XCTAssertEqual(box.first, 3)
        XCTAssertEqual(try bob.open(box), Data("group".utf8))
        XCTAssertEqual(try alice.open(box), Data("group".utf8))
        let stranger = LoopbackCrypto(inMemoryForTesting: true)
        stranger.setPartyCode("ZZZZ99")
        XCTAssertThrowsError(try stranger.open(box))
    }
}
