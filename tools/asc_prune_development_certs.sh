#!/usr/bin/env bash
# Revoke leftover Apple Development / iOS Development certs so a fresh
# GHA runner does not hit the team cap. Never touches Distribution.
# Requires APP_STORE_CONNECT_API_KEY, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID.
set -euo pipefail

missing=()
for name in APP_STORE_CONNECT_API_KEY APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID; do
  if [[ -z "${!name:-}" ]]; then
    missing+=("$name")
  fi
done
if (( ${#missing[@]} > 0 )); then
  echo "missing required App Store Connect secrets: ${missing[*]}" >&2
  exit 1
fi

PY=python3
if ! python3 -c 'import jwt' >/dev/null 2>&1; then
  venv="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/blackout-asc-venv"
  python3 -m venv "$venv"
  "$venv/bin/pip" install -q PyJWT cryptography
  PY="$venv/bin/python3"
fi

exec "$PY" - <<'PY'
import json, os, time, urllib.error, urllib.parse, urllib.request
import jwt

key = os.environ["APP_STORE_CONNECT_API_KEY"].replace("\r\n", "\n").strip() + "\n"
kid = os.environ["APP_STORE_CONNECT_KEY_ID"].strip()
iss = os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip()

REVOKE_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}
BLOCKED = (
    "DISTRIBUTION",
    "DEVELOPER_ID",
    "APPLE_PAY",
    "PASS_TYPE",
    "MAC_APP",
    "MAC_INSTALLER",
    "IDENTITY_ACCESS",
)


def token():
    now = int(time.time())
    t = jwt.encode(
        {"iss": iss, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": kid, "typ": "JWT"},
    )
    return t.decode() if isinstance(t, bytes) else t


def req(method, url, tok=None):
    r = urllib.request.Request(
        url,
        method=method,
        headers={
            "Authorization": f"Bearer {tok or token()}",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(r, timeout=45) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = {"raw": raw[:800]}
        return e.code, parsed


def list_certificates(tok):
    items = []
    url = "https://api.appstoreconnect.apple.com/v1/certificates?" + urllib.parse.urlencode(
        {"limit": "200"}
    )
    while url:
        st, data = req("GET", url, tok=tok)
        if st != 200:
            print("LIST", st, json.dumps(data)[:800], flush=True)
            return st, items
        for row in data.get("data") or []:
            attrs = row.get("attributes") or {}
            items.append(
                {
                    "id": row.get("id"),
                    "certificateType": attrs.get("certificateType"),
                    "displayName": attrs.get("displayName") or attrs.get("name"),
                    "expirationDate": attrs.get("expirationDate"),
                    "serialNumber": attrs.get("serialNumber"),
                }
            )
        url = ((data.get("links") or {}).get("next"))
    return 200, items


def blocked(cert_type: str) -> bool:
    upper = (cert_type or "").upper()
    return any(part in upper for part in BLOCKED)


tok = token()
st, certs = list_certificates(tok)
if st != 200:
    # API key may lack Certificates read. Archive can still use Distribution.
    print("SKIP list failed; not revoking", flush=True)
    raise SystemExit(0)

for rec in certs:
    print("CERT", json.dumps(rec), flush=True)

revoked = 0
skipped = 0
for rec in certs:
    kind = rec.get("certificateType") or ""
    if blocked(kind):
        print("KEEP", kind, rec.get("id"), rec.get("displayName"), flush=True)
        skipped += 1
        continue
    if kind not in REVOKE_TYPES:
        print("KEEP", kind, rec.get("id"), rec.get("displayName"), flush=True)
        skipped += 1
        continue
    cid = rec.get("id")
    if not cid:
        continue
    dst, body = req("DELETE", f"https://api.appstoreconnect.apple.com/v1/certificates/{cid}", tok=tok)
    print("REVOKE", kind, cid, rec.get("displayName"), dst, flush=True)
    if dst in (200, 204):
        revoked += 1
    elif dst == 403:
        print("SKIP revoke forbidden", cid, json.dumps(body)[:400], flush=True)
    else:
        print("WARN revoke", dst, json.dumps(body)[:400], flush=True)

print("RESULT revoked", revoked, "kept", skipped, flush=True)
raise SystemExit(0)
PY
