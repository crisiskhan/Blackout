#!/usr/bin/env python3
"""VISION glass — Linux stand-in for the still-first instrument.

The well is VISION. The finder is a reticle. The crop is visible.
WAIT sits on the still. The shutter always says why.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text()


def vision_kind_chip(ground: str) -> str:
    """Mirror of InspectField.visionKindChip."""
    mapping = {
        "fungi": "FUNGI",
        "snake": "BITE",
        "sting": "BITE",
        "mammal": "ANIMAL",
        "gator": "ANIMAL",
        "bird": "ANIMAL",
        "fish": "ANIMAL",
        "lizard": "ANIMAL",
        "turtle": "ANIMAL",
        "frog": "ANIMAL",
        "tree": "PLANT",
        "cactus": "PLANT",
        "water": "WATER",
        "fire": "FIRE",
        "smoke": "FIRE",
        "flood": "FLOOD",
        "ice": "COLD",
        "lightning": "STORM",
        "shelter": "SHELTER",
        "wound": "BLEED",
    }
    return mapping[ground]


def vision_box_to_ui(
    x: float, y: float, w: float, h: float, pad: float = 0.12
) -> tuple[float, float, float, float]:
    """Mirror of SystemVision.subjectNormalizedBox. Vision origin is bottom-left."""
    ui_y = 1.0 - (y + h)
    px = w * pad
    py = h * pad
    left = max(0.0, x - px)
    top = max(0.0, ui_y - py)
    right = min(1.0, x + w + px)
    bottom = min(1.0, ui_y + h + py)
    return (left, top, max(0.0, right - left), max(0.0, bottom - top))


class VisionWellTests(unittest.TestCase):
    def test_well_is_the_instrument_not_a_labeled_button(self):
        field = read("Blackout", "FieldTab.swift")
        qa = read("docs", "SOLO_QA.md")
        vision = field.split("private var visionHUD")[1].split("private func loc(")[0]
        self.assertNotIn('sectionLabel("VISION")', vision)
        self.assertNotIn('Button("VISION")', vision)
        self.assertIn("VISION", vision)
        self.assertIn("Image(uiImage:", vision)
        self.assertIn("openVision()", vision)
        self.assertIn("g.name", vision)
        self.assertIn('L10n.t("vision.leave"', vision)
        self.assertIn('L10n.t("vision.warn"', vision)
        self.assertIn('L10n.t("vision.none"', vision)
        self.assertNotIn("g.percent", vision)
        self.assertNotIn("g.lookalikes", vision)
        self.assertIn("visionKindChip", vision)
        hud = field.split("private var visionHUD")[1].split("private var visionWellWord")[0]
        self.assertLess(hud.find("visionWell"), hud.find("visionKindChip"))
        self.assertGreater(vision.find("visionFieldButton"), vision.find("visionKindChip"))
        self.assertIn("Tap the well to shoot or retake", qa)
        self.assertIn("Kind chip", qa)
        self.assertIn("The word sits on the still", qa)
        self.assertNotIn("best in class", qa.lower())

    def test_walk_stays_pinned_and_vision_stays_on_search(self):
        field = read("Blackout", "FieldTab.swift")
        open_fn = field.split("private func open(")[1].split("private var plateRail")[0]
        self.assertNotIn("visionHUD", open_fn)
        self.assertIn("HUDActionStyle(filled: true)", field.split("func visionFieldButton")[1])
        body = field.split("var body:")[1].split("private var fieldStatus")[0]
        self.assertIn("visionHUD", body)
        self.assertNotRegex(
            body,
            r"maxHeight: \.infinity\)\s+visionHUD",
            "VISION is SEARCH-only",
        )


class VisionWaitTests(unittest.TestCase):
    def test_still_stays_up_while_it_thinks(self):
        session = read("Blackout", "FieldSession.swift")
        field = read("Blackout", "FieldTab.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("var visionBusy", session)
        apply = session.split("func applyFieldVision")[1].split("func speakFieldVision")[0]
        self.assertIn("stillJPEG =", apply)
        self.assertIn("visionBusy = true", apply)
        self.assertIn("visionBusy = false", apply)
        self.assertLess(apply.find("stillJPEG ="), apply.find("visionBusy = true"))
        else_block = apply.split("guard let image")[1]
        self.assertIn("noModelGuess", else_block)
        self.assertIn("stillJPEG = nil", else_block)
        vision = field.split("private var visionHUD")[1].split(
            "private func visionFieldButton"
        )[0]
        self.assertIn("visionBusy", vision)
        self.assertIn('L10n.t("chip.wait"', vision)
        status = field.split("private var fieldStatus")[1].split("private var fieldTone")[0]
        self.assertIn("visionBusy", status)
        self.assertIn("Last still stays until the new one lands", qa)
        self.assertIn("WAIT on the well", qa)
        reopen = field.split("func openVision")[1].split("private func")[0]
        self.assertIn("showVision = true", reopen)
        self.assertNotIn("stillJPEG = nil", reopen)


class VisionFinderTests(unittest.TestCase):
    def test_finder_is_reticle_shutter_and_lamp(self):
        still = read("Blackout", "VisionStill.swift")
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        qa = read("docs", "SOLO_QA.md")
        chrome = still.split("func installChrome")[1].split("func cancel")[0]
        self.assertIn("reticle", still.lower())
        self.assertIn("CAPTURE", chrome)
        self.assertIn("CLOSE", chrome)
        self.assertIn("LAMP", chrome)
        self.assertIn("LAMP · NONE", still)
        self.assertIn("CAMERA DENIED", still)
        self.assertIn("WAIT", still)
        self.assertIn("visionShutterPoints", chrome)
        self.assertIn("visionShutterPoints", tokens)
        self.assertIn("= 64", tokens.split("visionShutterPoints")[1].split("\n", 1)[0])
        self.assertIn("HUD reticle", qa)
        self.assertIn("64pt CAPTURE", qa)
        self.assertIn("LAMP · NONE", qa)
        self.assertNotIn("best in class", still.lower())

    def test_shutter_is_always_a_hit(self):
        still = read("Blackout", "VisionStill.swift")
        qa = read("docs", "SOLO_QA.md")
        chrome = still.split("func installChrome")[1].split("func cancel")[0]
        self.assertNotIn("isEnabled = false", chrome)
        shoot = still.split("func shoot()")[1].split("func photoOutput")[0]
        self.assertIn("CAMERA DENIED", still)
        self.assertIn("WAIT", shoot)
        self.assertIn("session.isRunning", shoot)
        self.assertIn("always a hit", qa)
        self.assertIn("CAMERA DENIED", qa)

    def test_live_subject_box_and_result_crop(self):
        still = read("Blackout", "VisionStill.swift")
        session = read("Blackout", "FieldSession.swift")
        field = read("Blackout", "FieldTab.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertNotIn("AVCaptureVideoDataOutput", still)
        self.assertIn("func subjectNormalizedBox", still)
        self.assertIn("salientObjects", still)
        self.assertIn("subjectBox", still)
        self.assertIn("var visionCrop", session)
        apply = session.split("func applyFieldVision")[1].split("func speakFieldVision")[0]
        self.assertIn("subjectNormalizedBox", apply)
        self.assertIn("visionCrop", apply)
        vision = field.split("private var visionHUD")[1].split(
            "private func visionFieldButton"
        )[0]
        self.assertIn("visionCrop", vision)
        self.assertIn("marks the crop", qa)
        x, y, w, h = vision_box_to_ui(0.2, 0.1, 0.4, 0.5, pad=0.12)
        self.assertAlmostEqual(x, 0.2 - 0.4 * 0.12)
        self.assertAlmostEqual(y, 1.0 - 0.6 - 0.5 * 0.12)
        self.assertGreater(w, 0.4)
        self.assertGreater(h, 0.5)
        self.assertLessEqual(x + w, 1.0)
        self.assertLessEqual(y + h, 1.0)


class VisionKindChipTests(unittest.TestCase):
    def test_kind_chip_matches_the_walk(self):
        inspect = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "WaterInspect.swift"
        )
        self.assertIn("func visionKindChip", inspect)
        chip = inspect.split("func visionKindChip")[1].split("switch ground")[1].split("}")[0]
        for ground, word in (
            ("fungi", "FUNGI"),
            ("snake", "BITE"),
            ("sting", "BITE"),
            ("mammal", "ANIMAL"),
            ("gator", "ANIMAL"),
            ("bird", "ANIMAL"),
            ("fish", "ANIMAL"),
            ("lizard", "ANIMAL"),
            ("turtle", "ANIMAL"),
            ("frog", "ANIMAL"),
            ("tree", "PLANT"),
            ("cactus", "PLANT"),
            ("water", "WATER"),
            ("fire", "FIRE"),
            ("smoke", "FIRE"),
            ("flood", "FLOOD"),
            ("ice", "COLD"),
            ("lightning", "STORM"),
            ("shelter", "SHELTER"),
            ("wound", "BLEED"),
        ):
            self.assertEqual(vision_kind_chip(ground), word)
            self.assertIn(f'return "{word}"', chip)
            self.assertIn(f".{ground}", chip)
        self.assertNotIn("unknown", chip.lower())
        self.assertNotIn("no-model", chip.lower())

    def test_chip_is_in_the_audit_chain(self):
        agents = read("AGENTS.md")
        validate = read("tools", "validate_v3.py")
        self.assertIn("test_vision_glass.py", agents)
        self.assertIn("vision_glass()", validate)
        self.assertIn("test_vision_glass.py", validate)


class VisionTenFinderTests(unittest.TestCase):
    def test_finder_is_hud_chips_tap_focus_and_lamp_flash(self):
        still = read("Blackout", "VisionStill.swift")
        tokens = read("Packages", "Tokens", "Sources", "Tokens", "Tokens.swift")
        qa = read("docs", "SOLO_QA.md")
        self.assertIn("mapChipHitPoints", still)
        self.assertIn("mapChipHitPoints", tokens)
        self.assertIn("focusPointOfInterest", still)
        self.assertIn("exposurePointOfInterest", still)
        self.assertIn("captureDevicePointConverted", still)
        self.assertIn("UITapGestureRecognizer", still)
        self.assertIn("flashMode", still)
        self.assertIn(".flashMode = .on", still)
        self.assertNotIn("AVCaptureVideoDataOutput", still)
        self.assertNotIn("lastBoxAt", still)
        self.assertIn("locks focus", qa.lower())
        self.assertIn("no live classify", qa.lower())

    def test_kind_chip_is_a_44pt_hit(self):
        field = read("Blackout", "FieldTab.swift")
        hud = field.split("private var visionHUD")[1].split("private var visionWellWord")[0]
        self.assertIn("mapChipHitPoints", hud)
        self.assertNotIn("minHeight: 22", hud)
        self.assertIn("HUDOverlayChipStyle", hud)


class VisionTenHitTests(unittest.TestCase):
    def test_crop_classifies_before_the_full_frame(self):
        vis = read(
            "Packages", "VisionCoreML", "Sources", "VisionCoreML", "VisionCoreML.swift"
        )
        session = read("Blackout", "FieldSession.swift")
        still = read("Blackout", "VisionStill.swift")
        classify = vis.split("observations: [VisionObservation]")[1].split(
            "func lookalikeWord"
        )[0]
        self.assertIn("crop: [VisionObservation]", classify)
        apply = session.split("func applyFieldVision")[1].split("func speakFieldVision")[0]
        self.assertIn("aim:", apply)
        self.assertIn("cropHits", apply)
        self.assertIn("frameHits", apply)
        self.assertIn("crop:", apply)
        self.assertIn("aim", still)
        self.assertIn("onImage?(image, aim)", still)
        finish = still.split("func photoOutput(")[1].split("func failClosed")[0]
        self.assertIn("let aim = self.aim", finish)
        self.assertLess(finish.find("let aim = self.aim"), finish.find("DispatchQueue.main.async"))

    def test_desert_needles_and_book_cover_the_yard(self):
        vis = read(
            "Packages", "VisionCoreML", "Sources", "VisionCoreML", "VisionCoreML.swift"
        )
        inspect = read(
            "Packages", "MapLibreMap", "Sources", "MapLibreMap", "WaterInspect.swift"
        )
        tx = read("Resources", "Vision", "labels.tx.json")
        nm = read("Resources", "Vision", "labels.nm.json")
        emit = read("tools", "v3", "vision.py")
        qa = read("docs", "SOLO_QA.md")
        low = vis.lower()
        for word in (
            "ocotillo",
            "creosote",
            "lechuguilla",
            "barrel cactus",
            "saltcedar",
            "tamarisk",
            "palo verde",
        ):
            self.assertIn(word, low)
        for word in (
            "ocotillo",
            "creosote",
            "lechuguilla",
            "barrel",
            "saltcedar",
            "palo verde",
        ):
            self.assertIn(word, tx.lower())
            self.assertIn(word, nm.lower())
            self.assertIn(word, emit.lower())
        ground = inspect.split("func visionGroundFromSpecies")[1].split(
            "func visionKindChip"
        )[0]
        self.assertIn("ocotillo", ground)
        self.assertIn("creosote", ground)
        self.assertIn("lechuguilla", ground)
        self.assertIn("OCOTILLO", qa)
        self.assertIn("CREOSOTE", qa)


class VisionHonestyTests(unittest.TestCase):
    def test_never_edible_no_percent_unknown_stays(self):
        field = read("Blackout", "FieldTab.swift")
        vis = read("Packages", "VisionCoreML", "Sources", "VisionCoreML", "VisionCoreML.swift")
        qa = read("docs", "SOLO_QA.md")
        vision = field.split("private var visionHUD")[1].split(
            "private func visionFieldButton"
        )[0]
        self.assertNotIn("g.percent", vision)
        self.assertNotIn("g.lookalikes", vision)
        self.assertNotIn("edible=", vision)
        self.assertIn("onDeviceModelPresent = false", vis)
        self.assertIn("NO VISION MODEL", vis)
        self.assertIn("unknownGuess", vis)
        self.assertIn("Never edible", qa)
        self.assertIn("No percent", qa)
        self.assertIn("UNKNOWN", qa)
        self.assertIn("NO VISION MODEL", qa)
        self.assertNotIn("`EDIBLE`", qa)


if __name__ == "__main__":
    unittest.main()
