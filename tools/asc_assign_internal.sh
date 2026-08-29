#!/usr/bin/env bash
# Poll App Store Connect, PATCH usesNonExemptEncryption false, assign Internal.
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

export ASC_APP_ID="${ASC_APP_ID:-6806388963}"
export ASC_INTERNAL_GROUP_ID="${ASC_INTERNAL_GROUP_ID:-28035586-fce6-474f-9bc2-ef0f1f65306e}"

if [[ -z "${WANT_BUILD:-}" ]]; then
  if [[ -n "${1:-}" ]]; then
    WANT_BUILD="$1"
  else
    root="$(cd "$(dirname "$0")/.." && pwd)"
    WANT_BUILD="$(
      awk -F= '/CURRENT_PROJECT_VERSION/ {
        gsub(/[ ;"]/, "", $2)
        print $2
        exit
      }' "$root/Blackout.xcodeproj/project.pbxproj"
    )"
  fi
fi
export WANT_BUILD

PY=python3
if ! python3 -c 'import jwt' >/dev/null 2>&1; then
  # macos-26 Python is PEP 668; never pip-install into the system interpreter.
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
app = os.environ["ASC_APP_ID"]
group = os.environ["ASC_INTERNAL_GROUP_ID"]
want = (os.environ.get("WANT_BUILD") or "").strip()


def token():
    now = int(time.time())
    t = jwt.encode(
        {"iss": iss, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": kid, "typ": "JWT"},
    )
    return t.decode() if isinstance(t, bytes) else t


def req(method, url, body=None, tok=None):
    data = None if body is None else json.dumps(body).encode()
    r = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {tok or token()}",
            "Content-Type": "application/json",
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


def list_builds(tok):
    q = urllib.parse.urlencode({"filter[app]": app, "limit": "20", "sort": "-uploadedDate"})
    st, data = req("GET", "https://api.appstoreconnect.apple.com/v1/builds?" + q, tok=tok)
    if st != 200:
        raise SystemExit(f"list {st} {data}")
    out = []
    for b in data.get("data") or []:
        a = b.get("attributes") or {}
        st2, d2 = req(
            "GET",
            f"https://api.appstoreconnect.apple.com/v1/builds/{b['id']}/buildBetaDetail",
            tok=tok,
        )
        det = (d2.get("data") or {}).get("attributes") if isinstance(d2, dict) else {}
        rec = {
            "id": b["id"],
            "version": str(a.get("version")),
            "processingState": a.get("processingState"),
            "usesNonExemptEncryption": a.get("usesNonExemptEncryption"),
            "uploadedDate": a.get("uploadedDate"),
            "internalBuildState": det.get("internalBuildState") if isinstance(det, dict) else None,
        }
        out.append(rec)
        print("BUILD", json.dumps(rec), flush=True)
    return out


def sync(rec, tok):
    bid = rec["id"]
    if rec.get("usesNonExemptEncryption") is None or rec.get("internalBuildState") == "MISSING_EXPORT_COMPLIANCE":
        st, data = req(
            "PATCH",
            f"https://api.appstoreconnect.apple.com/v1/builds/{bid}",
            {"data": {"type": "builds", "id": bid, "attributes": {"usesNonExemptEncryption": False}}},
            tok=tok,
        )
        print("PATCH", rec["version"], st, flush=True)
        if st >= 400:
            print(json.dumps(data)[:500], flush=True)
    st, data = req(
        "POST",
        f"https://api.appstoreconnect.apple.com/v1/betaGroups/{group}/relationships/builds",
        {"data": [{"type": "builds", "id": bid}]},
        tok=tok,
    )
    print("ASSIGN", rec["version"], st, flush=True)
    if st >= 400 and st != 409:
        print(json.dumps(data)[:500], flush=True)
    st, d2 = req("GET", f"https://api.appstoreconnect.apple.com/v1/builds/{bid}/buildBetaDetail", tok=tok)
    det = (d2.get("data") or {}).get("attributes") if isinstance(d2, dict) else {}
    print("AFTER", rec["version"], json.dumps(det)[:400], flush=True)
    return det


deadline = time.time() + 20 * 60
target = None
last_tok = None
last_tok_at = 0
while time.time() < deadline:
    if last_tok is None or time.time() - last_tok_at > 10 * 60:
        last_tok = token()
        last_tok_at = time.time()
    builds = list_builds(last_tok)
    match = [b for b in builds if b["version"] == want] if want else builds[:1]
    if match:
        target = match[0]
        if target["processingState"] == "VALID":
            det = sync(target, last_tok)
            state = (det or {}).get("internalBuildState")
            print("RESULT", target["version"], target["id"], state, flush=True)
            if state in ("IN_BETA_TESTING", "READY_FOR_BETA_TESTING"):
                raise SystemExit(0)
        elif target["processingState"] in ("FAILED", "INVALID"):
            print("FAILED_STATE", target, flush=True)
            raise SystemExit(2)
        else:
            print("WAIT", target["processingState"], target.get("uploadedDate"), flush=True)
    else:
        print("WAIT no build", want, flush=True)
    time.sleep(30)
print("TIMEOUT", json.dumps(target), flush=True)
raise SystemExit(1)
PY
