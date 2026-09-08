#!/usr/bin/env python3
"""Read ASC max CFBundleVersion and write next= to GITHUB_OUTPUT.

34264110982: mint OK, then GET /v1/builds HTTP 500. Retry list 500
with backoff. Auth 401/403 fail closed. No App Review. No External.
No network unless main() is invoked.
"""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable
from typing import Any

try:
    import jwt
except ImportError:  # unit tests never call _http
    jwt = None

LIST_BACKOFF = (15.0, 30.0, 60.0, 90.0, 120.0)
ASC_APP = "6806388963"


class AscListError(RuntimeError):
    """ASC build list failed after retries or on a non-retryable status."""


def next_from_payload(payload: dict[str, Any]) -> int:
    nums: list[int] = []
    for body in payload.get("data") or []:
        version = str((body.get("attributes") or {}).get("version") or "")
        if version.isdigit():
            nums.append(int(version))
    return (max(nums) + 1) if nums else 1


def fetch_next_cpv(
    *,
    api: Callable[..., tuple[int, dict[str, Any]]],
    app: str,
    sleep: Callable[[float], None],
) -> int:
    """Return max(version)+1. Retry GET 500. Raise AscListError otherwise."""
    query = urllib.parse.urlencode(
        {"filter[app]": app, "limit": "50", "sort": "-version"}
    )
    url = "https://api.appstoreconnect.apple.com/v1/builds?" + query
    tries = 0
    last: dict[str, Any] = {}
    while True:
        st, data = api("GET", url)
        if st == 200:
            nxt = next_from_payload(data)
            print(
                f"ASC existing CFBundleVersion "
                f"next={nxt} list={st}"
            )
            return nxt
        last = data if isinstance(data, dict) else {"raw": data}
        print("LIST", st, json.dumps(last)[:500])
        if st == 500 and tries < len(LIST_BACKOFF):
            wait = LIST_BACKOFF[tries]
            tries += 1
            print("RETRY list 500 in", int(wait), "s")
            sleep(wait)
            continue
        raise AscListError(f"ASC builds list {st}")


def _http(
    method: str, url: str, body: Any = None, tok: str | None = None
) -> tuple[int, dict[str, Any]]:
    if jwt is None:
        raise RuntimeError("PyJWT is required to call App Store Connect")
    key = os.environ["APP_STORE_CONNECT_API_KEY"].replace("\r\n", "\n").strip() + "\n"
    kid = os.environ["APP_STORE_CONNECT_KEY_ID"].strip()
    iss = os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip()
    now = int(time.time())
    token = jwt.encode(
        {"iss": iss, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": kid, "typ": "JWT"},
    )
    if isinstance(token, bytes):
        token = token.decode()
    raw_body = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        url,
        data=raw_body,
        method=method,
        headers={
            "Authorization": f"Bearer {tok or token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode()
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = {"raw": raw[:800]}
        return exc.code, parsed


def main() -> int:
    nxt = fetch_next_cpv(
        api=_http,
        app=os.environ.get("ASC_APP_ID") or ASC_APP,
        sleep=time.sleep,
    )
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as fh:
            fh.write(f"next={nxt}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
