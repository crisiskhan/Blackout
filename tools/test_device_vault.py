#!/usr/bin/env python3
"""User-written and location persist is AES-GCM on this phone.

Chrome prefs (voice, lamp, handedness, pocket, locale, eye palette) stay
plaintext so the HUD still boots if Keychain cannot mint a key. Packed
tiles stay public OSM. SNAP stills are public cameras — file protection
only. Fail closed: a missing device key does not write plaintext.
"""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


class SealedPersistTests(unittest.TestCase):
    def test_sealed_persist_is_one_door(self):
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
        self.assertIn("enum DeviceKey", crypto)
        self.assertIn("enum SealedPersist", crypto)
        persist = crypto.split("enum SealedPersist")[1]
        self.assertIn("func put(", persist)
        self.assertIn("func get(", persist)
        self.assertIn("func putText(", persist)
        self.assertIn("func getText(", persist)
        self.assertIn("func putPair(", persist)
        self.assertIn("func getPair(", persist)
        self.assertIn("func putDoubles(", persist)
        self.assertIn("func getDoubles(", persist)
        self.assertIn("func putStrings(", persist)
        self.assertIn("func getStrings(", persist)
        self.assertIn("DeviceSeal.wrap", persist)
        self.assertIn("DeviceKey.resolve", persist)
        self.assertIn("testSealedPersistRoundtripAndFailClosed", tests)
        self.assertIn("testSealedPersistReadsLeftoverPlaintext", tests)
        fail_closed = tests.split("func testSealedPersistRoundtripAndFailClosed")[1].split("func test")[0]
        self.assertIn(
            '(String(data: stored!, encoding: .utf8) ?? "").contains("ridge")',
            fail_closed,
        )
        self.assertNotIn("?? true", fail_closed)

    def test_boot_attaches_the_device_key_before_any_load(self):
        app = read("Blackout", "AppRuntime.swift")
        vault = read("Blackout", "DeviceVault.swift")
        self.assertIn("func attach()", vault)
        self.assertIn("DeviceKey.resolve", vault)
        boot = app.split("init()")[1].split("func persistPartyCode")[0]
        self.assertIn("DeviceVault.attach()", boot)
        self.assertLess(
            boot.find("DeviceVault.attach()"),
            boot.find("PartyVitals.load()"),
            "attach the Keychain key before vitals come off disk",
        )
        self.assertLess(
            boot.find("DeviceVault.attach()"),
            boot.find("MarkStore.load()"),
        )
        self.assertLess(
            boot.find("DeviceVault.attach()"),
            boot.find("AdultKeep.load()"),
        )

    def test_user_written_and_location_persist_use_the_door(self):
        marks = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "MapLibreMap.swift"
        )
        route = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "RouteLine.swift"
        )
        emblem = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "PersonEmblem.swift"
        )
        eye = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "EyeDesk.swift"
        )
        vitals = read("Packages", "Vitals", "Sources", "Vitals", "Vitals.swift")
        kit = read("Packages", "KitStore", "Sources", "KitStore", "KitStore.swift")
        timers = read(
            "Packages", "TimerSync", "Sources", "TimerSync", "TimerSync.swift"
        )
        field = read("Blackout", "FieldSession.swift")
        adult = read("Blackout", "AdultKeep.swift")
        app = read("Blackout", "AppRuntime.swift")
        mark_save = marks.split("public static func save(_ marks: [MapMark]")[1].split(
            "public static func load("
        )[0]
        self.assertIn("SealedPersist.put", mark_save)
        self.assertNotIn("defaults.set(data, forKey: key)", mark_save)
        gone = marks.split("public enum MarkGone")[1].split("public enum MarkLabel")[0]
        self.assertIn("SealedPersist.putStrings", gone)
        fix = marks.split("public static func saveFix(")[1].split(
            "public static func loadFix("
        )[0]
        self.assertIn("SealedPersist.putPair", fix)
        self.assertNotIn("defaults.set([lat, lon]", fix)
        dest = route.split("public static func save(")[1].split(
            "public static func load("
        )[0]
        self.assertIn("SealedPersist.putPair", dest)
        self.assertIn("SealedPersist.getPair", route.split("public static func load(")[1].split(
            "public static func clear("
        )[0])
        self.assertIn("SealedPersist.putText", emblem.split("public static func save(")[1])
        self.assertIn("SealedPersist.getText", emblem.split("public static func load(")[1])
        scenes = eye.split("public static func saveScenes(")[1]
        self.assertIn("SealedPersist.put", scenes)
        self.assertIn("SealedPersist.get", eye.split("public static func loadScenes(")[1])
        self.assertIn("SealedPersist.putDoubles", vitals.split("public static func save(_ vitals: PartyVitals")[1])
        self.assertIn(
            "SealedPersist.getDoubles",
            vitals.split("public static func load(defaults:")[1],
        )
        self.assertIn("SealedPersist.put", kit.split("public static func save(")[1])
        self.assertIn("SealedPersist.get", kit.split("public static func load(")[1])
        self.assertIn("SealedPersist.put", timers.split("public func save(")[1])
        self.assertIn("SealedPersist.get", timers.split("public func load(")[1])
        walk = field.split("static func save(")[1].split("static func load(")[0]
        self.assertIn("SealedPersist.put", walk)
        self.assertNotIn("defaults.set(data, forKey: key)", walk)
        keep = adult.split("private static func save(")[1]
        self.assertIn("SealedPersist.put", keep)
        self.assertNotIn('UserDefaults.standard.set(data, forKey: key)', keep)
        self.assertIn("SealedPersist.putText", app.split("func setYouName(")[1].split("func setYouStatus(")[0])
        self.assertNotIn('UserDefaults.standard.set(youName, forKey: "you.name")', app)
        self.assertIn("SealedPersist.putText", app.split("func setYouStatus(")[1].split("func setYouVitals(")[0])
        self.assertIn("SealedPersist.getText", app.split("init()")[1].split("func persistPartyCode")[0])
        self.assertIn('SealedPersist.putText(id, forKey: "pack.id")', app)
        self.assertNotIn('UserDefaults.standard.set(id, forKey: "pack.id")', app)

    def test_packages_depend_on_cryptoparty(self):
        for pkg in ("MapLibreMap", "Vitals", "KitStore", "TimerSync"):
            manifest = read("Packages", pkg, "Package.swift")
            self.assertIn("CryptoParty", manifest, pkg)

    def test_snap_stills_use_file_protection(self):
        sock = read("Blackout", "UpdateSocket.swift")
        self.assertIn("completeFileProtectionUntilFirstUserAuthentication", sock)
        self.assertIn("completeUntilFirstUserAuthentication", sock)

    def test_chrome_prefs_stay_plaintext(self):
        """Voice / lamp / hand / pocket / locale are not secrets."""
        app = read("Blackout", "AppRuntime.swift")
        self.assertIn('forKey: "nav.voice"', app)
        self.assertIn('forKey: "hud.lamp"', app)
        self.assertIn('forKey: "hud.leftHand"', app)
        self.assertIn('forKey: "hud.pocket"', app)
        self.assertIn('forKey: "hud.locale"', app)

    def test_solo_qa_names_the_seal(self):
        qa = read("docs", "SOLO_QA.md")
        device = read("docs", "DEVICE.md")
        self.assertIn("DEVICE SEAL", qa)
        self.assertIn("AES-GCM", qa)
        self.assertIn("marks", qa.lower())
        self.assertIn("NAME", qa)
        self.assertIn("AES-GCM", device)
        self.assertIn("no iCloud", device)


if __name__ == "__main__":
    unittest.main()
