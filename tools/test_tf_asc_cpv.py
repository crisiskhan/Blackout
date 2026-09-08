#!/usr/bin/env python3
"""Next CPV retries ASC list 500. No network. Fail before implement."""
from __future__ import annotations

import sys
import unittest
from typing import Any

import tf_asc_cpv as cpv


class FakeAPI:
    def __init__(self, script: list[tuple[str, int, dict[str, Any]]]) -> None:
        self.script = list(script)
        self.calls: list[tuple[str, str]] = []

    def __call__(
        self, method: str, url: str, body: Any = None, tok: str | None = None
    ) -> tuple[int, dict]:
        self.calls.append((method, url))
        if not self.script:
            raise AssertionError(f"unexpected {method} {url}")
        want_method, st, payload = self.script.pop(0)
        if want_method and want_method != method:
            raise AssertionError(f"wanted {want_method} got {method} {url}")
        return st, payload


def _builds(*versions: str) -> dict:
    return {
        "data": [
            {"id": f"b{v}", "attributes": {"version": v}} for v in versions
        ]
    }


class TestNextCpvRetries500(unittest.TestCase):
    def test_500_then_200(self) -> None:
        """34264110982: GET builds HTTP 500 after mint. Retry, then next=67."""
        api = FakeAPI(
            [
                ("GET", 500, {"errors": [{"status": "500"}]}),
                ("GET", 200, _builds("66", "65", "64")),
            ]
        )
        sleeps: list[float] = []
        nxt = cpv.fetch_next_cpv(
            api=api,
            app="6806388963",
            sleep=sleeps.append,
        )
        self.assertEqual(nxt, 67)
        self.assertEqual(sleeps, [15.0])
        self.assertEqual(len(api.calls), 2)

    def test_happy_path_no_sleep(self) -> None:
        api = FakeAPI([("GET", 200, _builds("66"))])
        sleeps: list[float] = []
        nxt = cpv.fetch_next_cpv(
            api=api,
            app="6806388963",
            sleep=sleeps.append,
        )
        self.assertEqual(nxt, 67)
        self.assertEqual(sleeps, [])

    def test_empty_list_starts_at_one(self) -> None:
        api = FakeAPI([("GET", 200, {"data": []})])
        self.assertEqual(
            cpv.fetch_next_cpv(
                api=api,
                app="6806388963",
                sleep=lambda _: None,
            ),
            1,
        )

    def test_500_exhausts_retries(self) -> None:
        api = FakeAPI(
            [("GET", 500, {"errors": [{"status": "500"}]})]
            * (len(cpv.LIST_BACKOFF) + 1)
        )
        with self.assertRaises(cpv.AscListError):
            cpv.fetch_next_cpv(
                api=api,
                app="6806388963",
                sleep=lambda _: None,
            )
        self.assertEqual(len(api.calls), len(cpv.LIST_BACKOFF) + 1)

    def test_401_fails_closed_without_retry(self) -> None:
        api = FakeAPI([("GET", 401, {"errors": [{"status": "401"}]})])
        with self.assertRaises(cpv.AscListError):
            cpv.fetch_next_cpv(
                api=api,
                app="6806388963",
                sleep=lambda _: None,
            )
        self.assertEqual(len(api.calls), 1)


def main() -> None:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)


if __name__ == "__main__":
    main()
