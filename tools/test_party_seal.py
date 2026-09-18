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
