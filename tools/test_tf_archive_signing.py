#!/usr/bin/env python3
"""Archive CLI must not set CODE_SIGN_IDENTITY; Manual Dist is app/widget only.

33927056130: a global xcodebuild CODE_SIGN_IDENTITY hit Automatic SPM
packages (VisionCoreML, MapLibreMap, …) and exited 65. Fail closed.
No network.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

import tf_archive_signing as signing
import tf_asc_reuse as reuse


ROOT = Path(__file__).resolve().parents[1]
TF_ARCHIVE = ROOT / ".github/ci/tf-archive.sh"
TEAM = "TEAMID12"
HASH = "DEADBEEFCAFE0123456789ABCDEF0123456789AB"
WATCH = "com.crisiskhan.blackout.watchkitapp"
SPM = "com.example.VisionCoreML"


def _block(bundle: str, *, style: str = "Automatic", identity: str | None = None) -> str:
    ident = f'\t\t\t\tCODE_SIGN_IDENTITY = "{identity}";\n' if identity else ""
    return (
        "\t\t\tbuildSettings = {\n"
        f"\t\t\t\tCODE_SIGN_STYLE = {style};\n"
        f"{ident}"
        '\t\t\t\tDEVELOPMENT_TEAM = "";\n'
        f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {bundle};\n"
        "\t\t\t}"
    )


def _pbx() -> str:
    return "\n".join(
        [
            _block(signing.APP_BUNDLE),
            _block(signing.WIDGET_BUNDLE),
            _block(WATCH),
            _block(SPM),
        ]
    )


def _settings(text: str, bundle: str) -> str:
    marker = f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};"
    start = text.find(marker)
    if start < 0:
        raise AssertionError(f"missing {bundle}")
    left = text.rfind("buildSettings = {", 0, start)
    right = text.find("}", start)
    return text[left:right]


class TestArchiveCliHasNoCodeSignIdentity(unittest.TestCase):
    def test_archive_xcodebuild_omits_code_sign_identity(self) -> None:
        script = TF_ARCHIVE.read_text()
        block = signing.xcodebuild_archive_cli_block(script)
        self.assertNotIn("CODE_SIGN_IDENTITY=", block)
        self.assertIn("CURRENT_PROJECT_VERSION=", block)
        self.assertIn("tf_archive_signing.py", script)

    def test_export_archive_omits_code_sign_identity(self) -> None:
        script = TF_ARCHIVE.read_text()
        block = signing.xcodebuild_export_cli_block(script)
        self.assertNotIn("CODE_SIGN_IDENTITY=", block)
        self.assertIn("-exportArchive", block)


class TestManualDistAppWidgetOnly(unittest.TestCase):
    def test_manual_bundles_are_app_and_widget_only(self) -> None:
        ids = [ident for ident, _name, _plat in reuse.BUNDLES]
        self.assertEqual(list(signing.MANUAL_BUNDLES), ids)
        self.assertEqual(
            list(signing.MANUAL_BUNDLES),
            ["com.crisiskhan.blackout", "com.crisiskhan.blackout.widgets"],
        )
        self.assertNotIn(WATCH, signing.MANUAL_BUNDLES)
        self.assertNotIn(SPM, signing.MANUAL_BUNDLES)

    def test_has_local_dist_key_patches_only_app_and_widget(self) -> None:
        out = signing.apply_ci_signing_patch(
            _pbx(),
            has_local_dist_key=True,
            team_id=TEAM,
        )
        app = _settings(out, signing.APP_BUNDLE)
        widget = _settings(out, signing.WIDGET_BUNDLE)
        watch = _settings(out, WATCH)
        spm = _settings(out, SPM)

        self.assertIn("CODE_SIGN_STYLE = Manual;", app)
        self.assertIn("CODE_SIGN_STYLE = Manual;", widget)
        self.assertIn(f'CODE_SIGN_IDENTITY = "{signing.DIST_IDENTITY_PLACEHOLDER}";', app)
        self.assertIn(f'CODE_SIGN_IDENTITY = "{signing.DIST_IDENTITY_PLACEHOLDER}";', widget)
        self.assertIn(f"DEVELOPMENT_TEAM = {TEAM};", app)
        self.assertIn(f"DEVELOPMENT_TEAM = {TEAM};", widget)
        self.assertIn(
            'PROVISIONING_PROFILE_SPECIFIER = "Blackout iOS App Store GHA Local";',
            app,
        )
        self.assertIn(
            'PROVISIONING_PROFILE_SPECIFIER = "Blackout Widgets App Store GHA Local";',
            widget,
        )

        self.assertIn("CODE_SIGN_STYLE = Automatic;", watch)
        self.assertIn("CODE_SIGN_STYLE = Automatic;", spm)
        self.assertNotIn("CODE_SIGN_IDENTITY", watch)
        self.assertNotIn("CODE_SIGN_IDENTITY", spm)
        self.assertNotIn("PROVISIONING_PROFILE_SPECIFIER", watch)
        self.assertNotIn("PROVISIONING_PROFILE_SPECIFIER", spm)
        self.assertNotIn("Manual", watch)
        self.assertNotIn("Manual", spm)

    def test_hash_rewrite_uses_the_same_placeholder_as_the_patch(self) -> None:
        patched = signing.apply_ci_signing_patch(
            _pbx(),
            has_local_dist_key=True,
            team_id=TEAM,
        )
        self.assertIn(
            f'CODE_SIGN_IDENTITY = "{signing.DIST_IDENTITY_PLACEHOLDER}";',
            patched,
        )
        rewritten = signing.rewrite_dist_identity_hash(patched, HASH)
        self.assertNotIn(
            f'CODE_SIGN_IDENTITY = "{signing.DIST_IDENTITY_PLACEHOLDER}";',
            rewritten,
        )
        self.assertEqual(rewritten.count(f'CODE_SIGN_IDENTITY = "{HASH}";'), 2)
        self.assertNotIn("CODE_SIGN_IDENTITY", _settings(rewritten, WATCH))
        self.assertNotIn("CODE_SIGN_IDENTITY", _settings(rewritten, SPM))
        self.assertIn("CODE_SIGN_STYLE = Automatic;", _settings(rewritten, SPM))

    def test_placeholder_is_iphone_distribution(self) -> None:
        self.assertEqual(signing.DIST_IDENTITY_PLACEHOLDER, "iPhone Distribution")
        self.assertEqual(
            signing.DIST_IDENTITY_ALIASES,
            frozenset({"iPhone Distribution", "iOS Distribution", "Apple Distribution"}),
        )


def main() -> None:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)


if __name__ == "__main__":
    main()
