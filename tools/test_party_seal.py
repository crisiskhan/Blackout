#!/usr/bin/env python3
"""Party traffic is sealed when a party code exists. SNAP stays HTTPS.

No new chrome. Discovery advertisements stay as they are. A hop carries
the sealed body without reading it. Plaintext inbound from an older phone
still opens.
"""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


class PartySealTests(unittest.TestCase):
    def test_crypto_wraps_with_party_code_and_opens_plaintext(self):
        crypto = read(
            "Packages", "CryptoParty", "Sources", "CryptoParty", "CryptoParty.swift"
        )
        tests = read(
            "Packages",
            "CryptoParty",
            "Tests",
            "CryptoPartyTests",
            "CryptoPartyTests.swift",
        )
        self.assertIn("enum PartySeal", crypto)
        self.assertIn("0x42, 0x4F, 0x31", crypto)
        self.assertIn("func key(code:", crypto)
        self.assertIn("HKDF<SHA256>", crypto)
        self.assertIn("func wrap(", crypto)
        self.assertIn("func unwrap(", crypto)
        self.assertIn("func openBody(", crypto)
        self.assertIn("func isSealed(", crypto)
        self.assertIn("AES.GCM.seal", crypto)
        self.assertIn("testWrapRoundtripAndWrongKeyFails", tests)
        self.assertIn("testOpenBodyKeepsPlaintext", tests)
        self.assertIn("enum DeviceSeal", crypto)
        self.assertIn("0x42, 0x4F, 0x32", crypto)
        self.assertNotEqual(
            crypto.split("0x42, 0x4F, 0x31")[0],
            crypto.split("0x42, 0x4F, 0x32")[0],
            "device vault magic BO2 must stay distinct from mesh BO1",
        )
        self.assertIn("testDeviceSealRoundtripAndWrongKeyFails", tests)
        self.assertIn("testDeviceOpenBodyKeepsPlaintext", tests)

    def test_typed_party_code_rests_sealed_on_this_phone(self):
        """PARTY CODE leaves the typewriter into AES-GCM, never plaintext UserDefaults."""
        vault = read("Blackout", "DeviceVault.swift")
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn("import CryptoParty", vault)
        self.assertIn("enum DeviceVault", vault)
        self.assertIn("DeviceSeal.wrap", vault)
        self.assertIn("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly", vault)
        self.assertIn("kSecAttrSynchronizable", vault)
        self.assertIn("false", vault)
        self.assertNotIn("kSecAttrSynchronizableAny", vault)
        self.assertNotIn("kSecAttrAccessibleAlways", vault)
        self.assertIn("party.code.sealed", vault)
        self.assertIn('partyPlainKey = "party.code"', vault)
        self.assertIn("removeObject(forKey: partyPlainKey)", vault)
        persist = app.split("func persistPartyCode()")[1].split("var diaryAttend")[0]
        self.assertIn("DeviceVault.savePartyCode", persist)
        self.assertNotIn('UserDefaults.standard.set(roster.code, forKey: "party.code")', persist)
        boot = app.split("if let saved = UserDefaults.standard.string(forKey: \"hud.locale\")")[1].split(
            "mesh.partyCode = roster.code"
        )[0]
        self.assertIn("DeviceVault.loadPartyCode", boot)
        self.assertNotIn('string(forKey: "party.code")', boot)

    def test_mesh_seals_outbound_and_opens_inbound(self):
        mesh = read("Packages", "MeshDTN", "Sources", "MeshDTN", "MeshDTN.swift")
        pkg = read("Packages", "MeshDTN", "Package.swift")
        tests = read(
            "Packages", "MeshDTN", "Tests", "MeshDTNTests", "MeshDTNTests.swift"
        )
        live = read("Packages", "MeshDTN", "Sources", "MeshDTN", "LiveMeshRadio.swift")
        self.assertIn("import CryptoParty", mesh)
        self.assertIn("CryptoParty", pkg)
        self.assertIn("PartySeal.wrap", mesh)
        self.assertIn("PartySeal.openBody", mesh)
        self.assertIn("partyKey", mesh)
        self.assertIn("testPartySealsChipAndStillReadsPlaintext", tests)
        self.assertIn("encryptionPreference: .required", live)
        comms = read("Blackout", "CommsTab.swift")
        self.assertNotIn("ENCRYPTED", comms)
        self.assertNotIn("Whisper", comms)

    def test_snap_refuses_clear_http(self):
        sock = read("Blackout", "UpdateSocket.swift")
        self.assertIn('url.scheme?.lowercased() == "https"', sock)
        self.assertIn('hasPrefix("https://")', sock)
        self.assertIn("tlsMinimumSupportedProtocolVersion", sock)
        self.assertNotIn('hasPrefix("http")', sock.replace('hasPrefix("https://")', ""))


if __name__ == "__main__":
    unittest.main()
