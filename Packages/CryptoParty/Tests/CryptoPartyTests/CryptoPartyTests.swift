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

    func testDeviceSealRoundtripAndWrongKeyFails() throws {
        let key = SymmetricKey(size: .bits256)
        let other = SymmetricKey(size: .bits256)
        let plain = Data("JOIN-CODE".utf8)
        let wire = try DeviceSeal.wrap(plain, key: key)
        XCTAssertTrue(DeviceSeal.isSealed(wire))
        XCTAssertFalse(PartySeal.isSealed(wire))
        XCTAssertEqual(try DeviceSeal.unwrap(wire, key: key), plain)
        XCTAssertNil(DeviceSeal.openBody(wire, key: other))
        XCTAssertThrowsError(try DeviceSeal.unwrap(plain, key: key))
    }

    func testDeviceOpenBodyKeepsPlaintext() {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("morning ridge".utf8)
        XCTAssertFalse(DeviceSeal.isSealed(plain))
        XCTAssertEqual(DeviceSeal.openBody(plain, key: key), plain)
        XCTAssertEqual(DeviceSeal.openBody(plain, key: nil), plain)
        XCTAssertNil(DeviceSeal.openBody(Data([0x42, 0x4F, 0x32, 0x00]), key: nil))
    }

    func testSealedPersistRoundtripAndFailClosed() {
        let name = "seal.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        let key = SymmetricKey(size: .bits256)
        DeviceKey.resolve = { key }
        defer {
            DeviceKey.resolve = nil
            suite.removePersistentDomain(forName: name)
        }
        SealedPersist.put(Data("ridge".utf8), forKey: "note", defaults: suite)
        let stored = suite.data(forKey: "note")
        XCTAssertNotNil(stored)
        XCTAssertTrue(DeviceSeal.isSealed(stored!))
        XCTAssertFalse(String(data: stored!, encoding: .utf8)?.contains("ridge") ?? true)
        XCTAssertEqual(SealedPersist.get(forKey: "note", defaults: suite), Data("ridge".utf8))
        DeviceKey.resolve = { nil }
        SealedPersist.put(Data("plain".utf8), forKey: "closed", defaults: suite)
        XCTAssertNil(suite.object(forKey: "closed"))
        XCTAssertNil(SealedPersist.get(forKey: "note", defaults: suite))
    }

    func testSealedPersistReadsLeftoverPlaintext() {
        let name = "seal.plain.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        let key = SymmetricKey(size: .bits256)
        DeviceKey.resolve = { key }
        defer {
            DeviceKey.resolve = nil
            suite.removePersistentDomain(forName: name)
        }
        suite.set(Data("old".utf8), forKey: "note")
        XCTAssertEqual(SealedPersist.get(forKey: "note", defaults: suite), Data("old".utf8))
        XCTAssertTrue(DeviceSeal.isSealed(suite.data(forKey: "note")!))
        suite.set("RUI", forKey: "you.name")
        XCTAssertEqual(SealedPersist.getText(forKey: "you.name", defaults: suite), "RUI")
        XCTAssertTrue(DeviceSeal.isSealed(suite.data(forKey: "you.name")!))
        suite.set([31.76, -106.49], forKey: "you.fix")
        let pair = SealedPersist.getPair(forKey: "you.fix", defaults: suite)
        XCTAssertEqual(pair?.0, 31.76)
        XCTAssertEqual(pair?.1, -106.49)
        XCTAssertTrue(DeviceSeal.isSealed(suite.data(forKey: "you.fix")!))
    }
}
