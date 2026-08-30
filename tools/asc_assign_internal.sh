#!/usr/bin/env bash
# Poll App Store Connect, PATCH usesNonExemptEncryption false, assign Internal.
# Requires APP_STORE_CONNECT_API_KEY, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID.
# In GitHub Actions, ASC_NOT_BEFORE (ISO-8601) is required so a same-number
# build uploaded before this archive cannot be assigned by mistake.
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
export ASC_NOT_BEFORE="${ASC_NOT_BEFORE:-}"

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
from datetime import datetime, timezone
import jwt

key = os.environ["APP_STORE_CONNECT_API_KEY"].replace("\r\n", "\n").strip() + "\n"
kid = os.environ["APP_STORE_CONNECT_KEY_ID"].strip()
iss = os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip()
app = os.environ["ASC_APP_ID"]
group = os.environ["ASC_INTERNAL_GROUP_ID"]
want = (os.environ.get("WANT_BUILD") or "").strip()
not_before_raw = (os.environ.get("ASC_NOT_BEFORE") or "").strip()
if os.environ.get("GITHUB_ACTIONS") == "true" and not not_before_raw:
    raise SystemExit("ASC_NOT_BEFORE is required in GitHub Actions")


def parse_iso(raw):
    if not raw:
        return None
    text = raw.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    dt = datetime.fromisoformat(text)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def pick_assign_match(candidates, not_before):
    if not candidates:
        return "none", None
    fresh = candidates
    if not_before:
        fresh = []
        for rec in candidates:
            uploaded = parse_iso(rec.get("uploadedDate") or "")
            if uploaded is None or uploaded < not_before:
                continue
            fresh.append(rec)
    if fresh:
        return "fresh", fresh[0]
    return "none", None


not_before = parse_iso(not_before_raw)
if not_before_raw:
    print("NOT_BEFORE", not_before.isoformat(), flush=True)


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
    params = {"limit": "50", "sort": "-uploadedDate"}
    if want:
        params["filter[app]"] = app
        params["filter[version]"] = want
    else:
        params["filter[app]"] = app
    q = urllib.parse.urlencode(params)
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
stale_only_since = None
target = None
last_tok = None
last_tok_at = 0
while time.time() < deadline:
    if last_tok is None or time.time() - last_tok_at > 10 * 60:
        last_tok = token()
        last_tok_at = time.time()
    builds = list_builds(last_tok)
    candidates = [b for b in builds if b["version"] == want] if want else builds[:1]
    if not_before:
        for rec in candidates:
            uploaded = parse_iso(rec.get("uploadedDate") or "")
            if uploaded is None or uploaded < not_before:
                print(
                    "SKIP stale",
                    rec.get("version"),
                    rec.get("id"),
                    rec.get("uploadedDate"),
                    flush=True,
                )
    kind, chosen = pick_assign_match(candidates, not_before)
    if kind == "fallback":
        raise SystemExit("refusing FALLBACK assign of a stale same-number build")
    if chosen:
        target = chosen
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
            stale_only_since = None
    else:
        print("WAIT no fresh build", want, flush=True)
        if not_before and candidates:
            if stale_only_since is None:
                stale_only_since = time.time()
            elif time.time() - stale_only_since >= 8 * 60:
                raise SystemExit(
                    f"CFBundleVersion {want} already exists on ASC from before this archive; bump CURRENT_PROJECT_VERSION"
                )
        else:
            stale_only_since = None
    time.sleep(30)
print("TIMEOUT", json.dumps(target), flush=True)
raise SystemExit(1)
PY
