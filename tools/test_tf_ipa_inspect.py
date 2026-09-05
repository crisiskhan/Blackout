#!/usr/bin/env python3
"""IPA inspect: keep vendor MapLibre BID. No network. Fail before implement."""
from __future__ import annotations

import plistlib
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

import tf_ipa_inspect as inspect


APP_BID = "com.crisiskhan.blackout"
WIDGET_BID = "com.crisiskhan.blackout.widgets"
MAPBOX = "com.maplibre.mapbox"
CHILD_MAPLIBRE = "com.crisiskhan.blackout.maplibre"


def _write_plist(path: Path, body: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(body))


def _read_plist(path: Path) -> dict:
    return plistlib.loads(path.read_bytes())


def _fake_payload(root: Path, *, maplibre_bid: str | None = MAPBOX, widget: bool = True) -> Path:
    payload = root / "Payload"
    app = payload / "Blackout.app"
    _write_plist(
        app / "Info.plist",
        {
            "CFBundleIdentifier": APP_BID,
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "Blackout",
        },
    )
    if widget:
        _write_plist(
            app / "PlugIns" / "BlackoutWidgets.appex" / "Info.plist",
            {
                "CFBundleIdentifier": WIDGET_BID,
                "CFBundlePackageType": "XPC",
                "CFBundleExecutable": "BlackoutWidgets",
            },
        )
    body: dict = {
        "CFBundlePackageType": "FMWK",
        "CFBundleExecutable": "MapLibre",
    }
    if maplibre_bid is not None:
        body["CFBundleIdentifier"] = maplibre_bid
    _write_plist(app / "Frameworks" / "MapLibre.framework" / "Info.plist", body)
    return payload


class TestValidateFrameworkPlist(unittest.TestCase):
    def test_keeps_mapbox_and_fmwk(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "MapLibre.framework" / "Info.plist"
            _write_plist(
                path,
                {
                    "CFBundleIdentifier": MAPBOX,
                    "CFBundlePackageType": "FMWK",
                    "CFBundleName": "MapLibre",
                },
            )
            inspect.validate_framework_identifier(path)
            pl = _read_plist(path)
            self.assertEqual(pl["CFBundleIdentifier"], MAPBOX)
            self.assertEqual(pl["CFBundlePackageType"], "FMWK")

    def test_empty_bid_fails_closed(self) -> None:
        """33931992681: Apple rejects CFBundleIdentifier ''."""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "MapLibre.framework" / "Info.plist"
            _write_plist(path, {"CFBundlePackageType": "FMWK"})
            with self.assertRaises(inspect.InspectError):
                inspect.validate_framework_identifier(path)

    def test_owned_child_bid_fails_closed(self) -> None:
        """33929367958: owned child BID is what altool sought. Do not rewrite to owned."""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "MapLibre.framework" / "Info.plist"
            _write_plist(
                path,
                {
                    "CFBundleIdentifier": CHILD_MAPLIBRE,
                    "CFBundlePackageType": "FMWK",
                },
            )
            with self.assertRaises(inspect.InspectError) as ctx:
                inspect.validate_framework_identifier(path)
            self.assertIn(CHILD_MAPLIBRE, str(ctx.exception))
            self.assertEqual(_read_plist(path)["CFBundleIdentifier"], CHILD_MAPLIBRE)

    def test_placeholder_bundle_identifier_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "MapLibre.framework" / "Info.plist"
            _write_plist(
                path,
                {
                    "CFBundleIdentifier": "$bundleIdentifier",
                    "CFBundlePackageType": "FMWK",
                },
            )
            with self.assertRaises(inspect.InspectError):
                inspect.validate_framework_identifier(path)


class TestInspectPayload(unittest.TestCase):
    def test_keeps_nested_maplibre_and_accepts_app_and_widget(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = _fake_payload(Path(tmp))
            rewritten = inspect.inspect_and_rewrite_payload(payload)
            self.assertFalse(rewritten)
            app = payload / "Blackout.app"
            self.assertEqual(
                _read_plist(app / "Info.plist")["CFBundleIdentifier"], APP_BID
            )
            self.assertEqual(
                _read_plist(app / "PlugIns" / "BlackoutWidgets.appex" / "Info.plist")[
                    "CFBundleIdentifier"
                ],
                WIDGET_BID,
            )
            ml = _read_plist(app / "Frameworks" / "MapLibre.framework" / "Info.plist")
            self.assertEqual(ml["CFBundleIdentifier"], MAPBOX)
            self.assertEqual(ml["CFBundlePackageType"], "FMWK")

    def test_does_not_rewrite_fmwk_onto_owned_bid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = _fake_payload(Path(tmp), maplibre_bid=CHILD_MAPLIBRE)
            with self.assertRaises(inspect.InspectError):
                inspect.inspect_and_rewrite_payload(payload)
            ml = _read_plist(
                payload / "Blackout.app" / "Frameworks" / "MapLibre.framework" / "Info.plist"
            )
            self.assertEqual(ml["CFBundleIdentifier"], CHILD_MAPLIBRE)
            self.assertEqual(ml["CFBundlePackageType"], "FMWK")

    def test_widget_optional_when_absent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = _fake_payload(Path(tmp), widget=False)
            self.assertFalse(inspect.inspect_and_rewrite_payload(payload))

    def test_fail_closed_on_foreign_app_bid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = _fake_payload(Path(tmp))
            _write_plist(
                payload / "Other.app" / "Info.plist",
                {"CFBundleIdentifier": "com.example.other", "CFBundlePackageType": "APPL"},
            )
            with self.assertRaises(inspect.InspectError) as ctx:
                inspect.inspect_and_rewrite_payload(payload)
            self.assertIn("com.example.other", str(ctx.exception))

    def test_fail_closed_on_watchkit_appex_bid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = _fake_payload(Path(tmp))
            _write_plist(
                payload / "Blackout.app" / "PlugIns" / "Watch.appex" / "Info.plist",
                {
                    "CFBundleIdentifier": "com.crisiskhan.blackout.watchkitapp",
                    "CFBundlePackageType": "XPC",
                },
            )
            with self.assertRaises(inspect.InspectError) as ctx:
                inspect.inspect_and_rewrite_payload(payload)
            self.assertIn("watchkitapp", str(ctx.exception))

    def test_fail_closed_on_empty_maplibre_bid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = _fake_payload(Path(tmp), maplibre_bid=None)
            with self.assertRaises(inspect.InspectError):
                inspect.inspect_and_rewrite_payload(payload)

    def test_flattens_reserved_resources_into_app_root(self) -> None:
        """33931992681 Iris f30954fa: Blackout.app/Resources is reserved."""
        with tempfile.TemporaryDirectory() as tmp:
            payload = _fake_payload(Path(tmp))
            app = payload / "Blackout.app"
            packs = app / "Resources" / "Packs"
            packs.mkdir(parents=True)
            (packs / "catalog.json").write_text("{}", encoding="utf-8")
            field = app / "Resources" / "Field"
            field.mkdir(parents=True)
            (field / "field.core.json").write_text("{}", encoding="utf-8")
            inspect.inspect_and_rewrite_payload(payload)
            self.assertFalse((app / "Resources").exists())
            self.assertTrue((app / "Packs" / "catalog.json").is_file())
            self.assertTrue((app / "Field" / "field.core.json").is_file())


class TestInspectIpa(unittest.TestCase):
    def test_unzip_keeps_mapbox_no_rezip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            payload = _fake_payload(root)
            ipa = root / "Blackout.ipa"
            with zipfile.ZipFile(ipa, "w") as zf:
                for path in payload.rglob("*"):
                    if path.is_file():
                        zf.write(path, path.relative_to(root).as_posix())
            changed = inspect.inspect_ipa(ipa)
            self.assertFalse(changed)
            with zipfile.ZipFile(ipa) as zf:
                pl = plistlib.loads(
                    zf.read("Payload/Blackout.app/Frameworks/MapLibre.framework/Info.plist")
                )
                app_pl = plistlib.loads(zf.read("Payload/Blackout.app/Info.plist"))
            self.assertEqual(pl["CFBundleIdentifier"], MAPBOX)
            self.assertEqual(pl["CFBundlePackageType"], "FMWK")
            self.assertEqual(app_pl["CFBundleIdentifier"], APP_BID)


def main() -> None:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)


if __name__ == "__main__":
    main()
