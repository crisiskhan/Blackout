"""Get-or-create App Store Connect Dist cert + App Store profiles.

Happy path: reuse KEEP Dist cert 45YLWHL6UP and ACTIVE profiles by name.
Never revoke KEEP. Never delete+create profiles. Create only if missing.
"""
from __future__ import annotations

from typing import Any, Callable, Optional

KEEP_DIST_IDS = frozenset({"45YLWHL6UP"})
DIST_TYPES = frozenset({"IOS_DISTRIBUTION", "DISTRIBUTION"})
ACTIVE_PROFILE_STATES = frozenset({"ACTIVE"})

BUNDLES = [
    ("com.crisiskhan.blackout", "Blackout iOS App Store GHA", "IOS"),
    ("com.crisiskhan.blackout.widgets", "Blackout Widgets App Store GHA", "IOS"),
]

ApiFn = Callable[..., tuple[int, dict[str, Any]]]


class ProfileCreateError(RuntimeError):
    """ASC profile POST failed. Do not delete existing profiles or retry."""


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
    return keep_cert is None


def should_revoke_cert(
    cert: dict[str, Any],
    keep_ids: frozenset[str] = KEEP_DIST_IDS,
) -> bool:
    """Happy path never revokes. KEEP is pinned; orphans are a separate CoS step."""
    del cert, keep_ids
    return False


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


def resolve_profile(
    api: ApiFn,
    profiles: list[dict[str, Any]],
    *,
    name: str,
    bundle_id: str,
    cert_id: str,
    ident: str = "",
) -> tuple[str, dict[str, Any]]:
    match = select_reusable_profile(profiles, name)
    if match is not None:
        return "reuse", match
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
