#!/usr/bin/env python3
"""IPA inspect + MapLibre FMWK BID strip. No network. Fail before implement."""
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


class TestStripFrameworkPlist(unittest.TestCase):
    def test_strips_mapbox_and_keeps_fmwk(self) -> None:
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
            changed = inspect.strip_framework_identifier(path)
            self.assertTrue(changed)
            pl = _read_plist(path)
            self.assertNotIn("CFBundleIdentifier", pl)
            self.assertEqual(pl["CFBundlePackageType"], "FMWK")
            self.assertEqual(pl["CFBundleName"], "MapLibre")

    def test_child_maplibre_bid_is_stripped_not_owned(self) -> None:
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
            self.assertTrue(inspect.strip_framework_identifier(path))
            pl = _read_plist(path)
            self.assertNotIn("CFBundleIdentifier", pl)
            self.assertEqual(pl["CFBundlePackageType"], "FMWK")

    def test_parent_app_bid_on_fmwk_is_stripped(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "MapLibre.framework" / "Info.plist"
            _write_plist(
                path,
                {
                    "CFBundleIdentifier": APP_BID,
                    "CFBundlePackageType": "FMWK",
                },
            )
            self.assertTrue(inspect.strip_framework_identifier(path))
            self.assertNotIn("CFBundleIdentifier", _read_plist(path))

    def test_already_stripped_fmwk_is_left_alone(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "MapLibre.framework" / "Info.plist"
            _write_plist(path, {"CFBundlePackageType": "FMWK", "CFBundleName": "MapLibre"})
            self.assertFalse(inspect.strip_framework_identifier(path))
            pl = _read_plist(path)
            self.assertNotIn("CFBundleIdentifier", pl)
            self.assertEqual(pl["CFBundlePackageType"], "FMWK")


class TestInspectPayload(unittest.TestCase):
    def test_strips_nested_maplibre_and_accepts_app_and_widget(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = _fake_payload(Path(tmp))
            rewritten = inspect.inspect_and_rewrite_payload(payload)
            self.assertTrue(rewritten)
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
            self.assertNotIn("CFBundleIdentifier", ml)
            self.assertEqual(ml["CFBundlePackageType"], "FMWK")

    def test_does_not_rewrite_fmwk_onto_owned_bid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = _fake_payload(Path(tmp), maplibre_bid=CHILD_MAPLIBRE)
            inspect.inspect_and_rewrite_payload(payload)
            ml = _read_plist(
                payload / "Blackout.app" / "Frameworks" / "MapLibre.framework" / "Info.plist"
            )
            bid = ml.get("CFBundleIdentifier")
            self.assertTrue(bid in (None, ""))
            self.assertNotEqual(bid, APP_BID)
            self.assertNotEqual(bid, CHILD_MAPLIBRE)
            self.assertEqual(ml["CFBundlePackageType"], "FMWK")

    def test_widget_optional_when_absent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = _fake_payload(Path(tmp), widget=False, maplibre_bid=None)
            self.assertFalse(inspect.inspect_and_rewrite_payload(payload))

    def test_fail_closed_on_foreign_app_bid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = _fake_payload(Path(tmp), maplibre_bid=None)
            _write_plist(
                payload / "Other.app" / "Info.plist",
                {"CFBundleIdentifier": "com.example.other", "CFBundlePackageType": "APPL"},
            )
            with self.assertRaises(inspect.InspectError) as ctx:
                inspect.inspect_and_rewrite_payload(payload)
            self.assertIn("com.example.other", str(ctx.exception))

    def test_fail_closed_on_watchkit_appex_bid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            payload = _fake_payload(Path(tmp), maplibre_bid=None)
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


class TestInspectIpa(unittest.TestCase):
    def test_unzip_strip_rezip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            payload = _fake_payload(root)
            ipa = root / "Blackout.ipa"
            with zipfile.ZipFile(ipa, "w") as zf:
                for path in payload.rglob("*"):
                    if path.is_file():
                        zf.write(path, path.relative_to(root).as_posix())
            changed = inspect.inspect_ipa(ipa)
            self.assertTrue(changed)
            with zipfile.ZipFile(ipa) as zf:
                pl = plistlib.loads(
                    zf.read("Payload/Blackout.app/Frameworks/MapLibre.framework/Info.plist")
                )
                app_pl = plistlib.loads(zf.read("Payload/Blackout.app/Info.plist"))
            self.assertNotIn("CFBundleIdentifier", pl)
            self.assertEqual(pl["CFBundlePackageType"], "FMWK")
            self.assertEqual(app_pl["CFBundleIdentifier"], APP_BID)


def main() -> None:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)


if __name__ == "__main__":
    main()
