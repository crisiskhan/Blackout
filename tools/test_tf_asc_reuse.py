#!/usr/bin/env python3
"""Reuse Dist cert + App Store profiles. No network. Fail before implement."""
from __future__ import annotations

import sys
import unittest
from typing import Any

import tf_asc_reuse as reuse


KEEP = "45YLWHL6UP"
LOCAL_DIST = "LOCALDIST1"
KEEP_IOS_NAME = "Blackout iOS App Store GHA"
KEEP_WIDGET_NAME = "Blackout Widgets App Store GHA"
LOCAL_IOS_NAME = "Blackout iOS App Store GHA Local"
LOCAL_WIDGET_NAME = "Blackout Widgets App Store GHA Local"


def _cert(cid: str, ctype: str = "IOS_DISTRIBUTION", name: str = "iOS Distribution") -> dict:
    return {"id": cid, "attributes": {"certificateType": ctype, "name": name}}


def _profile(
    pid: str,
    name: str,
    state: str = "ACTIVE",
    cert_ids: list[str] | None = None,
) -> dict:
    body: dict[str, Any] = {
        "id": pid,
        "attributes": {"name": name, "profileState": state, "uuid": pid, "profileContent": "YQ=="},
    }
    if cert_ids is not None:
        body["relationships"] = {
            "certificates": {
                "data": [{"type": "certificates", "id": cid} for cid in cert_ids],
            }
        }
    return body


class TestPickKeepDistCert(unittest.TestCase):
    def test_keep_present_still_creates_local_dist(self) -> None:
        certs = [
            _cert("ORPHAN1"),
            _cert(KEEP, name="iOS Distribution: Stephan OConnor"),
            _cert("DEV1", "DEVELOPMENT"),
        ]
        picked = reuse.pick_keep_dist_cert(certs)
        self.assertIsNotNone(picked)
        assert picked is not None
        self.assertEqual(picked["id"], KEEP)
        self.assertTrue(reuse.should_create_dist_cert(picked))

    def test_create_also_when_keep_missing(self) -> None:
        certs = [_cert("ORPHAN1"), _cert("DEV1", "DEVELOPMENT")]
        picked = reuse.pick_keep_dist_cert(certs)
        self.assertIsNone(picked)
        self.assertTrue(reuse.should_create_dist_cert(picked))

    def test_never_revoke_keep(self) -> None:
        self.assertFalse(reuse.should_revoke_cert(_cert(KEEP)))
        self.assertFalse(reuse.should_revoke_development_orphan(_cert(KEEP)))

    def test_happy_path_does_not_revoke_dist_orphans_via_generic_helper(self) -> None:
        self.assertFalse(reuse.should_revoke_cert(_cert("ORPHAN1")))
        self.assertFalse(reuse.should_revoke_development_orphan(_cert("ORPHAN1")))

    def test_revokes_stale_non_keep_dist_before_next_mint(self) -> None:
        """33928044175: previous local Dist leftovers fill Apple's cap."""
        self.assertTrue(reuse.should_revoke_stale_local_dist(_cert("ORPHAN1")))
        self.assertTrue(
            reuse.should_revoke_stale_local_dist(_cert("YVK8HM9GT2", "DISTRIBUTION"))
        )
        self.assertFalse(reuse.should_revoke_stale_local_dist(_cert(KEEP)))
        self.assertFalse(
            reuse.should_revoke_stale_local_dist(
                _cert("DEVAPI", "IOS_DEVELOPMENT", "Created via API")
            )
        )

    def test_dist_create_hard_cap_fails_closed_without_revoking_keep(self) -> None:
        msg = reuse.dist_create_failure_message(
            409,
            {"errors": [{"status": "409", "code": "ENTITY_ERROR.CERTIFICATE.TYPE_LIMIT"}]},
            keep_id=KEEP,
        )
        self.assertIn("409", msg)
        self.assertIn("TYPE_LIMIT", msg)
        self.assertIn(KEEP, msg)
        self.assertIn("Not revoking KEEP", msg)
        self.assertIn("Fail closed", msg)


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
        self.bodies: list[Any] = []
        self.post_status = 201
        self.post_payload: dict[str, Any] = {
            "data": _profile("NEW", LOCAL_WIDGET_NAME, cert_ids=[LOCAL_DIST])
        }
        self.delete_status = 204
        self.delete_payload: dict[str, Any] = {}
        self.get_status = 200
        self.get_payload: dict[str, Any] = {}

    def __call__(self, method: str, url: str, body: Any = None) -> tuple[int, dict]:
        self.calls.append((method, url))
        self.bodies.append(body)
        if method == "POST":
            return self.post_status, self.post_payload
        if method == "DELETE":
            return self.delete_status, self.delete_payload
        if method == "GET":
            return self.get_status, self.get_payload
        return 200, {}


class TestResolveProfileGetOrCreate(unittest.TestCase):
    def test_reuse_does_not_delete_or_create(self) -> None:
        api = FakeAPI()
        existing = _profile("HIT", KEEP_IOS_NAME)
        action, match = reuse.resolve_profile(
            api,
            [existing],
            name=KEEP_IOS_NAME,
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
            name=LOCAL_WIDGET_NAME,
            bundle_id="bid2",
            cert_id=LOCAL_DIST,
        )
        self.assertEqual(action, "create")
        self.assertEqual(match["id"], "NEW")
        self.assertEqual([m for m, _ in api.calls], ["POST"])
        self.assertFalse(any(m == "DELETE" for m, _ in api.calls))
        posted = api.bodies[0]["data"]
        self.assertEqual(posted["attributes"]["name"], LOCAL_WIDGET_NAME)
        certs = posted["relationships"]["certificates"]["data"]
        self.assertEqual([c["id"] for c in certs], [LOCAL_DIST])

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
                name=LOCAL_WIDGET_NAME,
                bundle_id="bid2",
                cert_id=LOCAL_DIST,
            )
        msg = str(ctx.exception)
        self.assertIn("500", msg)
        self.assertIn("UNEXPECTED_ERROR", msg)
        self.assertIn("Not deleting", msg)
        self.assertFalse(any(m == "DELETE" for m, _ in api.calls))
        self.assertEqual([m for m, _ in api.calls], ["POST"])

    def test_reuse_local_named_profile_bound_to_local_cert(self) -> None:
        api = FakeAPI()
        existing = _profile("LOCHIT", LOCAL_IOS_NAME, cert_ids=[LOCAL_DIST])
        action, match = reuse.resolve_profile(
            api,
            [existing],
            name=LOCAL_IOS_NAME,
            bundle_id="bid1",
            cert_id=LOCAL_DIST,
            require_cert=True,
        )
        self.assertEqual(action, "reuse")
        self.assertEqual(match["id"], "LOCHIT")
        self.assertEqual(api.calls, [])

    def test_local_named_wrong_cert_replaces_local_only(self) -> None:
        """33928044175: Local profile bound to previous mint must be replaced."""
        api = FakeAPI()
        existing = _profile("OLDLOC", LOCAL_IOS_NAME, cert_ids=[KEEP])
        keep_named = _profile("KEEPPROF", KEEP_IOS_NAME, cert_ids=[KEEP])
        action, match = reuse.resolve_profile(
            api,
            [existing, keep_named],
            name=LOCAL_IOS_NAME,
            bundle_id="bid1",
            cert_id=LOCAL_DIST,
            require_cert=True,
        )
        self.assertEqual(action, "replace")
        self.assertEqual(match["id"], "NEW")
        self.assertEqual([m for m, _ in api.calls], ["DELETE", "POST"])
        self.assertIn("profiles/OLDLOC", api.calls[0][1])
        self.assertFalse(any("KEEPPROF" in url for _m, url in api.calls))
        posted = api.bodies[1]["data"]
        self.assertEqual(posted["attributes"]["name"], LOCAL_IOS_NAME)
        self.assertEqual(
            [c["id"] for c in posted["relationships"]["certificates"]["data"]],
            [LOCAL_DIST],
        )

    def test_keep_named_wrong_cert_never_deletes(self) -> None:
        api = FakeAPI()
        keep_named = _profile("KEEPPROF", KEEP_IOS_NAME, cert_ids=[KEEP])
        with self.assertRaises(reuse.ProfileCreateError) as ctx:
            reuse.resolve_profile(
                api,
                [keep_named],
                name=KEEP_IOS_NAME,
                bundle_id="bid1",
                cert_id=LOCAL_DIST,
                require_cert=True,
            )
        msg = str(ctx.exception)
        self.assertIn(KEEP_IOS_NAME, msg)
        self.assertIn("Not deleting", msg)
        self.assertFalse(any(m == "DELETE" for m, _ in api.calls))
        self.assertEqual(api.calls, [])

    def test_invalid_local_named_after_dist_revoke_replaces(self) -> None:
        """Dist prune invalidates Local; same-name CREATE 409s unless we delete first."""
        api = FakeAPI()
        stale = _profile(
            "OLDLOC",
            LOCAL_IOS_NAME,
            state="INVALID",
            cert_ids=["DR46Y6TTC3"],
        )
        keep_named = _profile("KEEPPROF", KEEP_IOS_NAME, cert_ids=[KEEP])
        action, match = reuse.resolve_profile(
            api,
            [stale, keep_named],
            name=LOCAL_IOS_NAME,
            bundle_id="bid1",
            cert_id="YVK8HM9GT2",
            require_cert=True,
        )
        self.assertEqual(action, "replace")
        self.assertEqual(match["id"], "NEW")
        self.assertEqual([m for m, _ in api.calls], ["DELETE", "POST"])
        self.assertIn("profiles/OLDLOC", api.calls[0][1])
        self.assertFalse(any("KEEPPROF" in url for _m, url in api.calls))
        posted = api.bodies[1]["data"]
        self.assertEqual(posted["attributes"]["name"], LOCAL_IOS_NAME)
        self.assertEqual(
            [c["id"] for c in posted["relationships"]["certificates"]["data"]],
            ["YVK8HM9GT2"],
        )

    def test_widget_local_wrong_cert_replaces(self) -> None:
        api = FakeAPI()
        existing = _profile("OLDWID", LOCAL_WIDGET_NAME, cert_ids=["DR46Y6TTC3"])
        action, match = reuse.resolve_profile(
            api,
            [existing],
            name=LOCAL_WIDGET_NAME,
            bundle_id="bid2",
            cert_id=LOCAL_DIST,
            require_cert=True,
        )
        self.assertEqual(action, "replace")
        self.assertEqual(match["id"], "NEW")
        self.assertEqual([m for m, _ in api.calls], ["DELETE", "POST"])
        self.assertIn("profiles/OLDWID", api.calls[0][1])
        posted = api.bodies[1]["data"]
        self.assertEqual(posted["attributes"]["name"], LOCAL_WIDGET_NAME)
        self.assertEqual(
            [c["id"] for c in posted["relationships"]["certificates"]["data"]],
            [LOCAL_DIST],
        )

    def test_local_delete_denied_fails_closed(self) -> None:
        api = FakeAPI()
        api.delete_status = 403
        api.delete_payload = {
            "errors": [{"status": "403", "code": "FORBIDDEN.REQUIRED", "title": "Forbidden"}]
        }
        existing = _profile("OLDLOC", LOCAL_IOS_NAME, cert_ids=[KEEP])
        with self.assertRaises(reuse.ProfileCreateError) as ctx:
            reuse.resolve_profile(
                api,
                [existing],
                name=LOCAL_IOS_NAME,
                bundle_id="bid1",
                cert_id=LOCAL_DIST,
                require_cert=True,
            )
        msg = str(ctx.exception)
        self.assertIn(LOCAL_IOS_NAME, msg)
        self.assertIn("OLDLOC", msg)
        self.assertIn("403", msg)
        self.assertIn("Fail closed", msg)
        self.assertEqual([m for m, _ in api.calls], ["DELETE"])
        self.assertFalse(any(m == "POST" for m, _ in api.calls))

    def test_local_recreate_denied_fails_closed(self) -> None:
        api = FakeAPI()
        api.post_status = 409
        api.post_payload = {
            "errors": [{"status": "409", "code": "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE"}]
        }
        existing = _profile("OLDLOC", LOCAL_IOS_NAME, cert_ids=["DR46Y6TTC3"])
        with self.assertRaises(reuse.ProfileCreateError) as ctx:
            reuse.resolve_profile(
                api,
                [existing],
                name=LOCAL_IOS_NAME,
                bundle_id="bid1",
                cert_id=LOCAL_DIST,
                require_cert=True,
            )
        msg = str(ctx.exception)
        self.assertIn(LOCAL_IOS_NAME, msg)
        self.assertIn("409", msg)
        self.assertEqual([m for m, _ in api.calls], ["DELETE", "POST"])
        self.assertFalse(any("KEEP" in url for _m, url in api.calls))

    def test_reuse_fetches_certs_when_list_omits_relationships(self) -> None:
        api = FakeAPI()
        api.get_payload = {
            "data": [{"type": "certificates", "id": LOCAL_DIST}],
        }
        existing = _profile("LOCHIT", LOCAL_IOS_NAME)
        action, match = reuse.resolve_profile(
            api,
            [existing],
            name=LOCAL_IOS_NAME,
            bundle_id="bid1",
            cert_id=LOCAL_DIST,
            require_cert=True,
        )
        self.assertEqual(action, "reuse")
        self.assertEqual(match["id"], "LOCHIT")
        self.assertEqual([m for m, _ in api.calls], ["GET"])
        self.assertIn("profiles/LOCHIT/certificates", api.calls[0][1])
        self.assertFalse(any(m == "DELETE" for m, _ in api.calls))


class TestBundlesPhoneAndWidgetOnly(unittest.TestCase):
    def test_bundles_omit_watchkitapp(self) -> None:
        ids = [ident for ident, _name, _plat in reuse.BUNDLES]
        self.assertEqual(
            ids,
            ["com.crisiskhan.blackout", "com.crisiskhan.blackout.widgets"],
        )
        self.assertTrue(all(plat == "IOS" for _i, _n, plat in reuse.BUNDLES))
        self.assertNotIn("watchkitapp", " ".join(ids))

    def test_bundles_use_local_profile_names(self) -> None:
        names = [name for _ident, name, _plat in reuse.BUNDLES]
        self.assertEqual(names, [LOCAL_IOS_NAME, LOCAL_WIDGET_NAME])
        self.assertNotIn(KEEP_IOS_NAME, names)
        self.assertNotIn(KEEP_WIDGET_NAME, names)
        self.assertIn(KEEP_IOS_NAME, reuse.KEEP_PROFILE_NAMES)
        self.assertIn(KEEP_WIDGET_NAME, reuse.KEEP_PROFILE_NAMES)


class TestDevelopmentOrphanRevoke(unittest.TestCase):
    def test_revokes_created_via_api_development_orphans_only(self) -> None:
        api_dev = _cert("DEVAPI", "IOS_DEVELOPMENT", "Apple Development: Created via API")
        api_dev2 = _cert("DEVAPI2", "DEVELOPMENT", "Created via API")
        human = _cert("DEV1", "DEVELOPMENT", "Apple Development: Stephan OConnor")
        dist = _cert("ORPHAN1")
        self.assertTrue(reuse.should_revoke_development_orphan(api_dev))
        self.assertTrue(reuse.should_revoke_development_orphan(api_dev2))
        self.assertFalse(reuse.should_revoke_development_orphan(human))
        self.assertFalse(reuse.should_revoke_development_orphan(dist))
        self.assertFalse(reuse.should_revoke_development_orphan(_cert(KEEP)))

    def test_revoke_helper_deletes_only_dev_orphans(self) -> None:
        api = FakeAPI()
        certs = [
            _cert(KEEP, name="iOS Distribution: Stephan OConnor"),
            _cert("ORPHAN1"),
            _cert("DEVAPI", "IOS_DEVELOPMENT", "Apple Development: Created via API"),
            _cert("DEV1", "DEVELOPMENT", "Apple Development: Stephan OConnor"),
        ]
        revoked = reuse.revoke_development_orphans(api, certs)
        self.assertEqual(revoked, ["DEVAPI"])
        self.assertEqual([m for m, _ in api.calls], ["DELETE"])
        self.assertIn("certificates/DEVAPI", api.calls[0][1])
        self.assertFalse(any(KEEP in url for _m, url in api.calls))

    def test_revoke_stale_local_dist_deletes_non_keep_only(self) -> None:
        api = FakeAPI()
        certs = [
            _cert(KEEP, name="iOS Distribution: Stephan OConnor"),
            _cert("2LWNR93SGQ"),
            _cert("DR46Y6TTC3", "DISTRIBUTION"),
            _cert("DEVAPI", "IOS_DEVELOPMENT", "Apple Development: Created via API"),
        ]
        revoked = reuse.revoke_stale_local_dist(api, certs)
        self.assertEqual(set(revoked), {"2LWNR93SGQ", "DR46Y6TTC3"})
        self.assertEqual([m for m, _ in api.calls], ["DELETE", "DELETE"])
        urls = " ".join(url for _m, url in api.calls)
        self.assertIn("certificates/2LWNR93SGQ", urls)
        self.assertIn("certificates/DR46Y6TTC3", urls)
        self.assertNotIn(KEEP, urls)
        self.assertNotIn("DEVAPI", urls)

    def test_revoke_stale_local_dist_denied_fails_closed(self) -> None:
        api = FakeAPI()
        api.delete_status = 403
        api.delete_payload = {
            "errors": [{"status": "403", "code": "FORBIDDEN.REQUIRED", "title": "Forbidden"}]
        }
        orphan = _cert("2LWNR93SGQ")
        with self.assertRaises(reuse.RevokeDeniedError) as ctx:
            reuse.revoke_stale_local_dist(api, [orphan])
        msg = str(ctx.exception)
        self.assertIn("403", msg)
        self.assertIn("2LWNR93SGQ", msg)
        self.assertIn("Fail closed", msg)
        self.assertIn("KEEP", msg)

    def test_revoke_denied_fails_closed(self) -> None:
        api = FakeAPI()
        api.delete_status = 403
        api.delete_payload = {
            "errors": [{"status": "403", "code": "FORBIDDEN.REQUIRED", "title": "Forbidden"}]
        }
        orphan = _cert("DEVAPI", "IOS_DEVELOPMENT", "Apple Development: Created via API")
        with self.assertRaises(reuse.RevokeDeniedError) as ctx:
            reuse.revoke_development_orphans(api, [orphan])
        msg = str(ctx.exception)
        self.assertIn("403", msg)
        self.assertIn("DEVAPI", msg)
        self.assertIn("Fail closed", msg)
        self.assertIn("KEEP", msg)


def main() -> None:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)


if __name__ == "__main__":
    main()
