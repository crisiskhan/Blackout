#!/usr/bin/env python3
"""Create a runner-local ASC Dist cert + Local App Store profiles for TF GHA.

KEEP Dist 45YLWHL6UP is reference-only and is never revoked. Always mint a
runner-local Dist cert (CSR/openssl/p12 → keychain) and bind Local-named
App Store profiles to that cert. Leave KEEP-named ACTIVE profiles alone.
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tf_asc_reuse as reuse

STOP = (
    "ASC API key cannot create or reuse signing certificates. "
    "In App Store Connect → Users and Access → Integrations → App Store Connect API, "
    "the key’s role must be Admin or Account Holder (not Developer, not App Manager). "
    "Account Holder/Admin: edit or replace APP_STORE_CONNECT_API_KEY with an Admin key."
)


def token(key: str, kid: str, iss: str) -> str:
    now = int(time.time())
    encoded = jwt.encode(
        {"iss": iss, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": kid, "typ": "JWT"},
    )
    return encoded.decode() if isinstance(encoded, bytes) else encoded


def api(method: str, url: str, body: dict | None = None) -> tuple[int, dict]:
    key = os.environ["APP_STORE_CONNECT_API_KEY"].replace("\r\n", "\n").strip() + "\n"
    kid = os.environ["APP_STORE_CONNECT_KEY_ID"].strip()
    iss = os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip()
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token(key, kid, iss)}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", "replace")
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = {"raw": raw[:1200]}
        return exc.code, parsed


def die_admin(st: int, payload: dict) -> None:
    print(f"ASC HTTP {st}")
    print(json.dumps(payload)[:800])
    print(STOP)
    raise SystemExit(1)


def list_certificates() -> list[dict]:
    st, payload = api("GET", "https://api.appstoreconnect.apple.com/v1/certificates?limit=200")
    if st in (401, 403):
        die_admin(st, payload)
    if st != 200:
        print(f"ASC certificates list HTTP {st}")
        print(json.dumps(payload)[:800])
        raise SystemExit(1)
    certs = payload.get("data") or []
    counts: dict[str, int] = {}
    dist: list[dict] = []
    for cert in certs:
        attrs = cert.get("attributes") or {}
        ctype = str(attrs.get("certificateType") or "")
        counts[ctype] = counts.get(ctype, 0) + 1
        print(f"CERT type={ctype} id={cert.get('id')} name={attrs.get('name')} exp={attrs.get('expirationDate')}")
        if ctype in reuse.DIST_TYPES:
            dist.append(cert)
    print(f"ASC certificate type counts {json.dumps(counts, sort_keys=True)}")
    print(f"ASC distribution-class certificates n={len(dist)}")
    return certs


def append_env(text: str) -> None:
    Path(os.environ["GITHUB_ENV"]).open("a").write(text)


def create_and_import_dist_cert(tmp: Path, keep_id: str | None = None) -> str:
    openssl = ["/usr/bin/openssl"]
    key_path = tmp / "dist.key"
    csr_path = tmp / "dist.csr"
    subprocess.check_call(openssl + ["genrsa", "-out", str(key_path), "2048"], stdout=subprocess.DEVNULL)
    subprocess.check_call(
        openssl
        + [
            "req",
            "-new",
            "-key",
            str(key_path),
            "-out",
            str(csr_path),
            "-subj",
            "/CN=Blackout GHA Distribution/C=US",
        ]
    )
    csr = csr_path.read_text()
    created = None
    last_st = 0
    last_payload: dict = {}
    for ctype in ("DISTRIBUTION", "IOS_DISTRIBUTION"):
        st, payload = api(
            "POST",
            "https://api.appstoreconnect.apple.com/v1/certificates",
            {
                "data": {
                    "type": "certificates",
                    "attributes": {"certificateType": ctype, "csrContent": csr},
                }
            },
        )
        last_st, last_payload = st, payload
        if st in (401, 403):
            die_admin(st, payload)
        if st in (200, 201):
            created = payload.get("data") or {}
            print(f"CREATED local Dist certificate type={ctype} id={created.get('id')}")
            break
        print(f"CREATE {ctype} HTTP {st} {json.dumps(payload)[:500]}")
    if created is None:
        print(reuse.dist_create_failure_message(last_st, last_payload, keep_id))
        raise SystemExit(1)
    der_b64 = (created.get("attributes") or {}).get("certificateContent") or ""
    if not der_b64:
        print("Create returned no certificateContent")
        raise SystemExit(1)
    cer_path = tmp / "dist.cer"
    pem_path = tmp / "dist.pem"
    p12_path = tmp / "dist.p12"
    cer_path.write_bytes(base64.b64decode(der_b64))
    subprocess.check_call(openssl + ["x509", "-inform", "DER", "-in", str(cer_path), "-out", str(pem_path)])
    p12_pass = "gha-dist-" + os.urandom(8).hex()
    cert_id = str(created.get("id") or "")

    def revoke_created() -> None:
        st, _payload = api("DELETE", f"https://api.appstoreconnect.apple.com/v1/certificates/{cert_id}")
        print(f"REVOKE created cert id={cert_id} after import fail HTTP {st}")

    def export_p12(cmd: list[str]) -> None:
        if p12_path.exists():
            p12_path.unlink()
        subprocess.check_call(cmd)

    p12_cmds = [
        openssl
        + [
            "pkcs12",
            "-export",
            "-inkey",
            str(key_path),
            "-in",
            str(pem_path),
            "-out",
            str(p12_path),
            "-passout",
            f"pass:{p12_pass}",
            "-name",
            "Blackout GHA Distribution",
        ],
        openssl
        + [
            "pkcs12",
            "-export",
            "-legacy",
            "-inkey",
            str(key_path),
            "-in",
            str(pem_path),
            "-out",
            str(p12_path),
            "-passout",
            f"pass:{p12_pass}",
            "-name",
            "Blackout GHA Distribution",
        ],
        openssl
        + [
            "pkcs12",
            "-export",
            "-keypbe",
            "PBE-SHA1-3DES",
            "-certpbe",
            "PBE-SHA1-3DES",
            "-macalg",
            "sha1",
            "-inkey",
            str(key_path),
            "-in",
            str(pem_path),
            "-out",
            str(p12_path),
            "-passout",
            f"pass:{p12_pass}",
            "-name",
            "Blackout GHA Distribution",
        ],
    ]
    exported = False
    for cmd in p12_cmds:
        try:
            export_p12(cmd)
            exported = True
            print("P12 export ok", cmd[1:4])
            break
        except subprocess.CalledProcessError as exc:
            print("P12 export failed", exc)
    if not exported:
        revoke_created()
        raise SystemExit("p12 export failed")
    kc = tmp / "signing.keychain-db"
    kc_pass = "gha-kc-" + os.urandom(8).hex()
    subprocess.check_call(["security", "create-keychain", "-p", kc_pass, str(kc)])
    subprocess.check_call(["security", "set-keychain-settings", "-lut", "21600", str(kc)])
    subprocess.check_call(["security", "unlock-keychain", "-p", kc_pass, str(kc)])
    existing = subprocess.check_output(["security", "list-keychains", "-d", "user"]).decode()
    paths = [str(kc)] + [ln.strip().strip('"') for ln in existing.splitlines() if ln.strip()]
    subprocess.check_call(["security", "list-keychains", "-d", "user", "-s", *paths])
    try:
        subprocess.check_call(
            [
                "security",
                "import",
                str(p12_path),
                "-k",
                str(kc),
                "-P",
                p12_pass,
                "-A",
                "-T",
                "/usr/bin/codesign",
                "-T",
                "/usr/bin/security",
                "-T",
                "/usr/bin/xcodebuild",
            ]
        )
    except subprocess.CalledProcessError:
        print("p12 import failed; trying cert+key PEM")
        try:
            subprocess.check_call(["security", "import", str(cer_path), "-k", str(kc), "-A"])
            subprocess.check_call(["security", "import", str(key_path), "-k", str(kc), "-A"])
        except subprocess.CalledProcessError:
            revoke_created()
            raise SystemExit("keychain import failed")
    subprocess.check_call(
        [
            "security",
            "set-key-partition-list",
            "-S",
            "apple-tool:,apple:,codesign:",
            "-s",
            "-k",
            kc_pass,
            str(kc),
        ]
    )
    print(f"IMPORTED distribution cert id={cert_id} into runner keychain (temporary; not a human p12 secret)")
    cert_type = str((created.get("attributes") or {}).get("certificateType") or "")
    with Path(os.environ["GITHUB_ENV"]).open("a") as fh:
        fh.write("HAS_LOCAL_DIST_KEY=1\n")
        fh.write(f"DIST_CERT_ID={cert_id}\n")
        fh.write(f"DIST_CERT_TYPE={cert_type}\n")
        fh.write(f"SIGNING_KEYCHAIN={kc}\n")
        fh.write(f"SIGNING_KC_PASS={kc_pass}\n")
    print("identities in signing keychain:")
    subprocess.call(["security", "find-identity", "-v", "-p", "codesigning", str(kc)])
    return cert_id


def ensure_bundle(ident: str, platform: str) -> str:
    q = urllib.parse.urlencode({"filter[identifier]": ident, "limit": "5"})
    st, payload = api("GET", "https://api.appstoreconnect.apple.com/v1/bundleIds?" + q)
    if st in (401, 403):
        die_admin(st, payload)
    if st != 200:
        print(f"bundleId list {ident} HTTP {st}")
        raise SystemExit(1)
    for bundle in payload.get("data") or []:
        if (bundle.get("attributes") or {}).get("identifier") == ident:
            print(f"BUNDLE reuse {ident} id={bundle.get('id')}")
            return str(bundle["id"])
    st, payload = api(
        "POST",
        "https://api.appstoreconnect.apple.com/v1/bundleIds",
        {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": ident,
                    "name": ident.replace(".", " ")[:30],
                    "platform": platform,
                },
            }
        },
    )
    if st in (401, 403):
        die_admin(st, payload)
    if st not in (200, 201):
        print(f"bundleId create {ident} HTTP {st} {json.dumps(payload)[:500]}")
        raise SystemExit(1)
    bid = (payload.get("data") or {}).get("id")
    print(f"BUNDLE created {ident} id={bid}")
    return str(bid)


def write_profile(home: Path, uuid: str, content_b64: str) -> None:
    blob = base64.b64decode(content_b64)
    dirs = [
        home / "Library/Developer/Xcode/UserData/Provisioning Profiles",
        home / "Library/MobileDevice/Provisioning Profiles",
    ]
    for directory in dirs:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / f"{uuid}.mobileprovision").write_bytes(blob)
    print(f"PROFILE wrote {uuid} bytes={len(blob)}")


def list_app_store_profiles() -> list[dict]:
    q = reuse.profile_list_query()
    st, payload = api("GET", "https://api.appstoreconnect.apple.com/v1/profiles?" + q)
    if st in (401, 403):
        die_admin(st, payload)
    if st != 200:
        print(f"ASC profiles list HTTP {st}")
        print(json.dumps(payload)[:800])
        raise SystemExit(1)
    return payload.get("data") or []


def hydrate_profile(match: dict, pname: str) -> dict:
    attrs = match.get("attributes") or {}
    if attrs.get("profileContent"):
        return match
    st, payload = api("GET", f"https://api.appstoreconnect.apple.com/v1/profiles/{match['id']}")
    if st != 200:
        print(f"profile get {pname} HTTP {st}")
        raise SystemExit(1)
    return payload.get("data") or {}


def write_profiles(
    home: Path,
    tmp: Path,
    cert_id: str,
    sleeper=None,
) -> None:
    sleep = sleeper if sleeper is not None else time.sleep
    profiles = list_app_store_profiles()
    profile_names: dict[str, str] = {}
    prev_name: str | None = None
    prev_action: str | None = None
    for ident, pname, platform in reuse.BUNDLES:
        delay = reuse.local_profile_inter_create_delay(prev_name, prev_action, pname)
        if prev_name is not None:
            if delay:
                print(
                    f"ASC cooldown {delay:.0f}s after {prev_name} {prev_action} "
                    f"before {pname}"
                )
                sleep(delay)
            profiles = list_app_store_profiles()
        bid = ensure_bundle(ident, platform)
        try:
            action, match = reuse.resolve_profile(
                api,
                profiles,
                name=pname,
                bundle_id=bid,
                cert_id=cert_id,
                ident=ident,
                require_cert=True,
                sleeper=sleep,
                logger=print,
            )
        except reuse.ProfileCreateError as exc:
            print(str(exc))
            raise SystemExit(1) from exc
        if action == "reuse":
            print(f"PROFILE reuse {pname} id={match.get('id')}")
        elif action == "replace":
            print(f"PROFILE replaced {pname} id={match.get('id')} bound to local Dist {cert_id}")
            profiles.append(match)
        elif action == "create":
            print(f"PROFILE created {pname} id={match.get('id')}")
            profiles.append(match)
        else:
            raise SystemExit(f"unknown profile action {action!r}")
        match = hydrate_profile(match, pname)
        attrs = match.get("attributes") or {}
        uuid = attrs.get("uuid") or match.get("id")
        content = attrs.get("profileContent")
        if not content:
            print(f"profile {pname} missing profileContent")
            raise SystemExit(1)
        write_profile(home, str(uuid), content)
        profile_names[ident] = pname
        prev_name, prev_action = pname, action
    (tmp / "profile_map.json").write_text(json.dumps(profile_names))
    print("wrote profile_map.json", profile_names)


def main() -> None:
    tmp = Path(os.environ["RUNNER_TEMP"])
    home = Path.home()
    certs = list_certificates()
    try:
        revoked = reuse.revoke_development_orphans(api, certs)
    except reuse.RevokeDeniedError as exc:
        print(str(exc))
        raise SystemExit(1) from exc
    for cid in revoked:
        print(f"REVOKED development orphan id={cid} (Created via API; not KEEP Dist)")
    try:
        stale = reuse.revoke_stale_local_dist(api, certs)
    except reuse.RevokeDeniedError as exc:
        print(str(exc))
        raise SystemExit(1) from exc
    for cid in stale:
        print(f"REVOKED stale local Dist id={cid} (previous runner mint; not KEEP)")
    keep = reuse.pick_keep_dist_cert(certs)
    keep_id = str(keep.get("id") or "") if keep is not None else ""
    if keep is not None:
        name = str((keep.get("attributes") or {}).get("name") or "")
        print(f"KEEP Dist cert present id={keep_id} name={name} (reference only)")
        print("Creating a runner-local Dist cert for this flight. Not revoking KEEP.")
    else:
        print("KEEP Dist cert missing — creating a runner-local Dist cert.")
    cert_id = create_and_import_dist_cert(tmp, keep_id or None)
    print(f"KEEP Dist id={keep_id or 'none'} (reference)")
    print(f"LOCAL Dist id={cert_id} (signing)")
    append_env(f"KEEP_DIST_CERT_ID={keep_id}\n")
    write_profiles(home, tmp, cert_id)


if __name__ == "__main__":
    main()
