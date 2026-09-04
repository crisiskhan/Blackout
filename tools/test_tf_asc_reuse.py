#!/usr/bin/env python3
"""Reuse Dist cert + App Store profiles. No network. Fail before implement."""
from __future__ import annotations

import sys
import unittest
from typing import Any

import tf_asc_reuse as reuse


KEEP = "45YLWHL6UP"


def _cert(cid: str, ctype: str = "IOS_DISTRIBUTION", name: str = "iOS Distribution") -> dict:
    return {"id": cid, "attributes": {"certificateType": ctype, "name": name}}


def _profile(pid: str, name: str, state: str = "ACTIVE") -> dict:
    return {
        "id": pid,
        "attributes": {"name": name, "profileState": state, "uuid": pid, "profileContent": "YQ=="},
    }


class TestPickKeepDistCert(unittest.TestCase):
    def test_reuses_pinned_keep_when_present(self) -> None:
        certs = [
            _cert("ORPHAN1"),
            _cert(KEEP, name="iOS Distribution: Stephan OConnor"),
            _cert("DEV1", "DEVELOPMENT"),
        ]
        picked = reuse.pick_keep_dist_cert(certs)
        self.assertIsNotNone(picked)
        assert picked is not None
        self.assertEqual(picked["id"], KEEP)
        self.assertFalse(reuse.should_create_dist_cert(picked))

    def test_create_only_when_keep_missing(self) -> None:
        certs = [_cert("ORPHAN1"), _cert("DEV1", "DEVELOPMENT")]
        picked = reuse.pick_keep_dist_cert(certs)
        self.assertIsNone(picked)
        self.assertTrue(reuse.should_create_dist_cert(picked))

    def test_never_revoke_keep(self) -> None:
        self.assertFalse(reuse.should_revoke_cert(_cert(KEEP)))

    def test_happy_path_does_not_revoke_orphans(self) -> None:
        self.assertFalse(reuse.should_revoke_cert(_cert("ORPHAN1")))


class TestSelectReusableProfile(unittest.TestCase):
    def test_reuses_active_profile_by_exact_name(self) -> None:
        profiles = [
            _profile("OTHER", "Other Profile"),
            _profile("HIT", "Blackout iOS App Store GHA"),
            _profile("DEAD", "Blackout iOS App Store GHA", "INVALID"),
        ]
        match = reuse.select_reusable_profile(profiles, "Blackout iOS App Store GHA")
        self.assertIsNotNone(match)
        assert match is not None
        self.assertEqual(match["id"], "HIT")

    def test_missing_or_invalid_only_is_not_reuse(self) -> None:
        self.assertIsNone(reuse.select_reusable_profile([], "Blackout iOS App Store GHA"))
        self.assertIsNone(
            reuse.select_reusable_profile(
                [_profile("DEAD", "Blackout iOS App Store GHA", "INVALID")],
                "Blackout iOS App Store GHA",
            )
        )


class FakeAPI:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []
        self.post_status = 201
        self.post_payload: dict[str, Any] = {
            "data": _profile("NEW", "Blackout Widgets App Store GHA")
        }

    def __call__(self, method: str, url: str, body: Any = None) -> tuple[int, dict]:
        self.calls.append((method, url))
        if method == "POST":
            return self.post_status, self.post_payload
        if method == "DELETE":
            return 204, {}
        return 200, {}


class TestResolveProfileGetOrCreate(unittest.TestCase):
    def test_reuse_does_not_delete_or_create(self) -> None:
        api = FakeAPI()
        existing = _profile("HIT", "Blackout iOS App Store GHA")
        action, match = reuse.resolve_profile(
            api,
            [existing],
            name="Blackout iOS App Store GHA",
            bundle_id="bid1",
            cert_id=KEEP,
        )
        self.assertEqual(action, "reuse")
        self.assertEqual(match["id"], "HIT")
        self.assertEqual(api.calls, [])

    def test_create_only_when_active_missing(self) -> None:
        api = FakeAPI()
        action, match = reuse.resolve_profile(
            api,
            [],
            name="Blackout Widgets App Store GHA",
            bundle_id="bid2",
            cert_id=KEEP,
        )
        self.assertEqual(action, "create")
        self.assertEqual(match["id"], "NEW")
        self.assertEqual([m for m, _ in api.calls], ["POST"])
        self.assertFalse(any(m == "DELETE" for m, _ in api.calls))

    def test_create_500_fails_clearly_without_delete(self) -> None:
        api = FakeAPI()
        api.post_status = 500
        api.post_payload = {
            "errors": [{"status": "500", "code": "UNEXPECTED_ERROR", "title": "An unexpected error occurred."}]
        }
        with self.assertRaises(reuse.ProfileCreateError) as ctx:
            reuse.resolve_profile(
                api,
                [],
                name="Blackout Widgets App Store GHA",
                bundle_id="bid2",
                cert_id=KEEP,
            )
        msg = str(ctx.exception)
        self.assertIn("500", msg)
        self.assertIn("UNEXPECTED_ERROR", msg)
        self.assertIn("Not deleting", msg)
        self.assertFalse(any(m == "DELETE" for m, _ in api.calls))
        self.assertEqual([m for m, _ in api.calls], ["POST"])


class TestBundlesPhoneAndWidgetOnly(unittest.TestCase):
    def test_bundles_omit_watchkitapp(self) -> None:
        ids = [ident for ident, _name, _plat in reuse.BUNDLES]
        self.assertEqual(
            ids,
            ["com.crisiskhan.blackout", "com.crisiskhan.blackout.widgets"],
        )
        self.assertTrue(all(plat == "IOS" for _i, _n, plat in reuse.BUNDLES))
        self.assertNotIn("watchkitapp", " ".join(ids))


def main() -> None:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)


if __name__ == "__main__":
    main()
