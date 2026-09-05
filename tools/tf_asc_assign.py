#!/usr/bin/env python3
"""Wait for an ASC build to go VALID, then assign the Internal group.

33986112949: altool uploaded CPV 56, processingState VALID, PATCH 200,
then POST betaGroups/.../relationships/builds 404 NOT_FOUND on that
build id. Treat 409 as already assigned. Retry 404 with backoff.
No App Review. No External. No network unless main() is invoked.
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

ASSIGN_BACKOFF = (15.0, 30.0, 60.0, 90.0, 120.0)
INTERNAL_GROUP = "28035586-fce6-474f-9bc2-ef0f1f65306e"
ASC_APP = "6806388963"


def _match_build(payload: dict[str, Any], want: str) -> dict[str, Any] | None:
    for body in payload.get("data") or []:
        attrs = body.get("attributes") or {}
        if str(attrs.get("version")) == want:
            return {
                "id": body["id"],
                "version": str(attrs.get("version")),
                "processingState": attrs.get("processingState"),
                "usesNonExemptEncryption": attrs.get("usesNonExemptEncryption"),
            }
    return None


def assign_internal(
    *,
    api: Callable[..., tuple[int, dict[str, Any]]],
    app: str,
    group: str,
    want: str,
    sleep: Callable[[float], None],
    deadline: float,
    now: Callable[[], float] = time.time,
) -> int:
    """Return 0 on assign/409, 2 on FAILED/INVALID, 1 on timeout/404 exhaust."""
    assign_tries = 0
    target: dict[str, Any] | None = None
    while now() < deadline:
        query = urllib.parse.urlencode(
            {"filter[app]": app, "limit": "20", "sort": "-uploadedDate"}
        )
        st, data = api("GET", "https://api.appstoreconnect.apple.com/v1/builds?" + query)
        if st != 200:
            print(f"list {st} {data}")
            return 1
        match = _match_build(data, want)
        if not match:
            print("WAIT no build", want)
            sleep(30.0)
            continue
        target = match
        print("BUILD", json.dumps(target))
        state = target["processingState"]
        if state in ("FAILED", "INVALID"):
            return 2
        if state != "VALID":
            print("WAIT", state)
            sleep(30.0)
            continue
        bid = target["id"]
        if target.get("usesNonExemptEncryption") is None:
            st, data = api(
                "PATCH",
                f"https://api.appstoreconnect.apple.com/v1/builds/{bid}",
                {
                    "data": {
                        "type": "builds",
                        "id": bid,
                        "attributes": {"usesNonExemptEncryption": False},
                    }
                },
            )
            print("PATCH", target["version"], st)
        st, data = api(
            "POST",
            f"https://api.appstoreconnect.apple.com/v1/betaGroups/{group}/relationships/builds",
            {"data": [{"type": "builds", "id": bid}]},
        )
        print("ASSIGN Internal", target["version"], st)
        if st < 400 or st == 409:
            return 0
        if st == 404 and assign_tries < len(ASSIGN_BACKOFF):
            wait = ASSIGN_BACKOFF[assign_tries]
            assign_tries += 1
            print(json.dumps(data)[:500])
            print("RETRY assign 404 in", int(wait), "s")
            sleep(wait)
            continue
        print(json.dumps(data)[:500])
        return 1
    print("TIMEOUT", json.dumps(target))
    return 1


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
    want = (os.environ.get("WANT_BUILD") or os.environ.get("NEXT_BUILD") or "").strip()
    if not want:
        print("WANT_BUILD / NEXT_BUILD empty. No assign.")
        return 1
    return assign_internal(
        api=_http,
        app=os.environ.get("ASC_APP_ID") or ASC_APP,
        group=os.environ.get("ASC_INTERNAL_GROUP_ID") or INTERNAL_GROUP,
        want=want,
        sleep=time.sleep,
        deadline=time.time() + 25 * 60,
    )


if __name__ == "__main__":
    raise SystemExit(main())
