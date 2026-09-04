"""Get-or-create App Store Connect Dist cert + App Store profiles.

Happy path: KEEP Dist 45YLWHL6UP is reference-only. Always mint a
runner-local Dist cert and bind Local-named App Store profiles to it.
Never revoke KEEP. Never delete KEEP-named profiles.
"""
from __future__ import annotations

from typing import Any, Callable, Optional

KEEP_DIST_IDS = frozenset({"45YLWHL6UP"})
DIST_TYPES = frozenset({"IOS_DISTRIBUTION", "DISTRIBUTION"})
DEV_TYPES = frozenset({"IOS_DEVELOPMENT", "DEVELOPMENT"})
ACTIVE_PROFILE_STATES = frozenset({"ACTIVE"})
KEEP_PROFILE_NAMES = frozenset(
    {
        "Blackout iOS App Store GHA",
        "Blackout Widgets App Store GHA",
    }
)

BUNDLES = [
    ("com.crisiskhan.blackout", "Blackout iOS App Store GHA Local", "IOS"),
    ("com.crisiskhan.blackout.widgets", "Blackout Widgets App Store GHA Local", "IOS"),
]

ApiFn = Callable[..., tuple[int, dict[str, Any]]]


class ProfileCreateError(RuntimeError):
    """ASC profile POST failed. Do not delete existing profiles or retry."""


class RevokeDeniedError(RuntimeError):
    """ASC refused to revoke a Development orphan. Do not continue."""


def pick_keep_dist_cert(
    certs: list[dict[str, Any]],
    keep_ids: frozenset[str] = KEEP_DIST_IDS,
) -> Optional[dict[str, Any]]:
    for cert in certs:
        cid = str(cert.get("id") or "")
        ctype = str((cert.get("attributes") or {}).get("certificateType") or "")
        if cid in keep_ids and ctype in DIST_TYPES:
            return cert
    return None


def should_create_dist_cert(keep_cert: Optional[dict[str, Any]]) -> bool:
    """Always mint a runner-local Dist cert. KEEP is reference-only."""
    del keep_cert
    return True


def should_revoke_cert(
    cert: dict[str, Any],
    keep_ids: frozenset[str] = KEEP_DIST_IDS,
) -> bool:
    """Happy path never revokes Dist certs. KEEP is pinned."""
    del cert, keep_ids
    return False


def should_revoke_development_orphan(
    cert: dict[str, Any],
    keep_ids: frozenset[str] = KEEP_DIST_IDS,
) -> bool:
    cid = str(cert.get("id") or "")
    if cid in keep_ids:
        return False
    attrs = cert.get("attributes") or {}
    ctype = str(attrs.get("certificateType") or "")
    if ctype not in DEV_TYPES:
        return False
    name = str(attrs.get("name") or "")
    return "Created via API" in name


def revoke_denied_message(cert_id: str, status: int, payload: dict[str, Any]) -> str:
    errors = payload.get("errors") or []
    codes = [str(err.get("code") or "") for err in errors if isinstance(err, dict)]
    code_note = codes[0] if codes else "FORBIDDEN"
    return (
        f"ASC revoke development orphan id={cert_id} HTTP {status} {code_note}. "
        "Fail closed. Not revoking KEEP Dist. Not continuing archive."
    )


def revoke_development_orphans(
    api: ApiFn,
    certs: list[dict[str, Any]],
    keep_ids: frozenset[str] = KEEP_DIST_IDS,
) -> list[str]:
    revoked: list[str] = []
    for cert in certs:
        if not should_revoke_development_orphan(cert, keep_ids=keep_ids):
            continue
        cid = str(cert.get("id") or "")
        status, payload = api(
            "DELETE",
            f"https://api.appstoreconnect.apple.com/v1/certificates/{cid}",
        )
        if status not in (200, 204):
            raise RevokeDeniedError(revoke_denied_message(cid, status, payload))
        revoked.append(cid)
    return revoked


def dist_create_failure_message(
    status: int,
    payload: dict[str, Any],
    keep_id: str | None = None,
) -> str:
    errors = payload.get("errors") or []
    codes = [str(err.get("code") or "") for err in errors if isinstance(err, dict)]
    code_note = codes[0] if codes else "UNEXPECTED_ERROR"
    keep = keep_id or next(iter(KEEP_DIST_IDS))
    return (
        f"ASC Dist cert create HTTP {status} {code_note}. "
        "Apple may have hit the distribution certificate cap. "
        f"Not revoking KEEP Dist {keep}. "
        "Not auto-revoking other Dist certs. Fail closed."
    )


def select_reusable_profile(
    profiles: list[dict[str, Any]],
    name: str,
) -> Optional[dict[str, Any]]:
    for profile in profiles:
        attrs = profile.get("attributes") or {}
        if attrs.get("name") != name:
            continue
        state = str(attrs.get("profileState") or "").upper()
        if state in ACTIVE_PROFILE_STATES:
            return profile
    return None


def profile_certificate_ids(profile: dict[str, Any]) -> list[str]:
    rel = ((profile.get("relationships") or {}).get("certificates") or {}).get("data") or []
    return [str(item.get("id") or "") for item in rel if item.get("id")]


def profile_includes_cert(profile: dict[str, Any], cert_id: str) -> bool:
    return cert_id in profile_certificate_ids(profile)


def fetch_profile_certificate_ids(api: ApiFn, profile_id: str) -> list[str]:
    status, payload = api(
        "GET",
        f"https://api.appstoreconnect.apple.com/v1/profiles/{profile_id}/certificates",
    )
    if status != 200:
        return []
    return [str(item.get("id") or "") for item in (payload.get("data") or []) if item.get("id")]


def profile_create_failure_message(
    ident: str,
    name: str,
    status: int,
    payload: dict[str, Any],
) -> str:
    errors = payload.get("errors") or []
    codes = [str(err.get("code") or "") for err in errors if isinstance(err, dict)]
    code_note = codes[0] if codes else "UNEXPECTED_ERROR"
    return (
        f"ASC profile create {ident} ({name}) HTTP {status} {code_note}. "
        "Not deleting existing profiles. Not retrying delete+create. "
        "Reuse an ACTIVE profile by name, or wait for App Store Connect."
    )


def local_profile_cert_mismatch_message(name: str, cert_id: str) -> str:
    keep_names = ", ".join(sorted(KEEP_PROFILE_NAMES))
    return (
        f"ACTIVE local profile {name} is not bound to local Dist {cert_id}. "
        f"Not deleting KEEP-named profiles ({keep_names}). "
        "Not auto-replacing. Fail closed."
    )


def resolve_profile(
    api: ApiFn,
    profiles: list[dict[str, Any]],
    *,
    name: str,
    bundle_id: str,
    cert_id: str,
    ident: str = "",
    require_cert: bool = False,
) -> tuple[str, dict[str, Any]]:
    match = select_reusable_profile(profiles, name)
    if match is not None:
        if not require_cert:
            return "reuse", match
        cert_ids = profile_certificate_ids(match)
        if not cert_ids:
            cert_ids = fetch_profile_certificate_ids(api, str(match.get("id") or ""))
        if cert_id in cert_ids:
            return "reuse", match
        raise ProfileCreateError(local_profile_cert_mismatch_message(name, cert_id))
    status, payload = api(
        "POST",
        "https://api.appstoreconnect.apple.com/v1/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                    "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
                },
            }
        },
    )
    if status not in (200, 201):
        raise ProfileCreateError(
            profile_create_failure_message(ident or name, name, status, payload)
        )
    created = payload.get("data") or {}
    if not created.get("id"):
        raise ProfileCreateError(
            profile_create_failure_message(ident or name, name, status, payload)
        )
    return "create", created
