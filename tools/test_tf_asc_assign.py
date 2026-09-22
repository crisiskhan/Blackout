#!/usr/bin/env python3
"""Internal assign retries ASC 404. No network. Fail before implement."""
from __future__ import annotations

import sys
import unittest
import urllib.error
from typing import Any

import tf_asc_assign as assign


class FakeAPI:
    def __init__(self, script: list[tuple[str, int, dict[str, Any]]]) -> None:
        self.script = list(script)
        self.calls: list[tuple[str, str]] = []

    def __call__(self, method: str, url: str, body: Any = None, tok: str | None = None) -> tuple[int, dict]:
        self.calls.append((method, url))
        if not self.script:
            raise AssertionError(f"unexpected {method} {url}")
        want_method, st, payload = self.script.pop(0)
        if want_method and want_method != method:
            raise AssertionError(f"wanted {want_method} got {method} {url}")
        return st, payload


def _build(bid: str, version: str, state: str = "VALID") -> dict:
    return {
        "data": [
            {
                "id": bid,
                "attributes": {
                    "version": version,
                    "processingState": state,
                    "usesNonExemptEncryption": False,
                },
            }
        ]
    }


class TestTransportFailure(unittest.TestCase):
    def test_urlerror_is_598(self) -> None:
        st, data = assign.transport_failure(urllib.error.URLError("timed out"))
        self.assertEqual(st, 598)
        self.assertIn("timed out", data["raw"])


class TestAssignInternalRetries404(unittest.TestCase):
    def test_404_then_204(self) -> None:
        """33986112949: VALID + PATCH 200, then betaGroups 404. Retry."""
        api = FakeAPI(
            [
                ("GET", 200, _build("b56", "56")),
                ("POST", 404, {"errors": [{"status": "404", "code": "NOT_FOUND"}]}),
                ("GET", 200, _build("b56", "56")),
                ("POST", 204, {}),
            ]
        )
        sleeps: list[float] = []
        rc = assign.assign_internal(
            api=api,
            app="6806388963",
            group="28035586-fce6-474f-9bc2-ef0f1f65306e",
            want="56",
            sleep=sleeps.append,
            deadline=1e18,
        )
        self.assertEqual(rc, 0)
        self.assertEqual(sleeps, [15.0])
        posts = [c for c in api.calls if c[0] == "POST"]
        self.assertEqual(len(posts), 2)

    def test_409_is_already_assigned(self) -> None:
        api = FakeAPI(
            [
                ("GET", 200, _build("b55", "55")),
                ("POST", 409, {"errors": [{"status": "409"}]}),
            ]
        )
        rc = assign.assign_internal(
            api=api,
            app="6806388963",
            group="28035586-fce6-474f-9bc2-ef0f1f65306e",
            want="55",
            sleep=lambda _: None,
            deadline=1e18,
        )
        self.assertEqual(rc, 0)

    def test_invalid_fails_closed(self) -> None:
        api = FakeAPI([("GET", 200, _build("b56", "56", "INVALID"))])
        rc = assign.assign_internal(
            api=api,
            app="6806388963",
            group="28035586-fce6-474f-9bc2-ef0f1f65306e",
            want="56",
            sleep=lambda _: None,
            deadline=1e18,
        )
        self.assertEqual(rc, 2)

    def test_list_timeout_then_valid_assigns(self) -> None:
        """35742115500: GET /v1/builds urlopen timed out. Retry, then ASSIGN."""
        api = FakeAPI(
            [
                ("GET", 598, {"raw": "timed out"}),
                ("GET", 200, _build("b164", "164")),
                ("POST", 204, {}),
            ]
        )
        sleeps: list[float] = []
        rc = assign.assign_internal(
            api=api,
            app="6806388963",
            group="28035586-fce6-474f-9bc2-ef0f1f65306e",
            want="164",
            sleep=sleeps.append,
            deadline=1e18,
        )
        self.assertEqual(rc, 0)
        self.assertEqual(sleeps, [30.0])
        self.assertEqual([c[0] for c in api.calls], ["GET", "GET", "POST"])

    def test_list_500_then_valid_assigns(self) -> None:
        api = FakeAPI(
            [
                ("GET", 500, {"errors": [{"status": "500"}]}),
                ("GET", 200, _build("b164", "164")),
                ("POST", 204, {}),
            ]
        )
        sleeps: list[float] = []
        rc = assign.assign_internal(
            api=api,
            app="6806388963",
            group="28035586-fce6-474f-9bc2-ef0f1f65306e",
            want="164",
            sleep=sleeps.append,
            deadline=1e18,
        )
        self.assertEqual(rc, 0)
        self.assertEqual(sleeps, [30.0])

    def test_list_401_fails_closed(self) -> None:
        api = FakeAPI([("GET", 401, {"errors": [{"status": "401"}]})])
        rc = assign.assign_internal(
            api=api,
            app="6806388963",
            group="28035586-fce6-474f-9bc2-ef0f1f65306e",
            want="164",
            sleep=lambda _: None,
            deadline=1e18,
        )
        self.assertEqual(rc, 1)
        self.assertEqual(len(api.calls), 1)

    def test_404_exhausts_retries(self) -> None:
        api = FakeAPI(
            [
                ("GET", 200, _build("b56", "56")),
                ("POST", 404, {"errors": [{"status": "404"}]}),
                ("GET", 200, _build("b56", "56")),
                ("POST", 404, {"errors": [{"status": "404"}]}),
                ("GET", 200, _build("b56", "56")),
                ("POST", 404, {"errors": [{"status": "404"}]}),
                ("GET", 200, _build("b56", "56")),
                ("POST", 404, {"errors": [{"status": "404"}]}),
                ("GET", 200, _build("b56", "56")),
                ("POST", 404, {"errors": [{"status": "404"}]}),
                ("GET", 200, _build("b56", "56")),
                ("POST", 404, {"errors": [{"status": "404"}]}),
            ]
        )
        rc = assign.assign_internal(
            api=api,
            app="6806388963",
            group="28035586-fce6-474f-9bc2-ef0f1f65306e",
            want="56",
            sleep=lambda _: None,
            deadline=1e18,
        )
        self.assertEqual(rc, 1)


def main() -> None:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)


if __name__ == "__main__":
    main()
