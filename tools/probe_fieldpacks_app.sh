#!/usr/bin/env bash
# Fail if Blackout.app is missing the four statewide Field Packs as Ready roots.
set -euo pipefail

APP="${1:-}"
if [ -z "${APP}" ] || [ ! -d "${APP}" ]; then
  echo "error: Blackout.app path required" >&2
  exit 1
fi

ROOT="${APP}/FieldPacks"
if [ ! -d "${ROOT}" ]; then
  echo "error: ${APP} has no FieldPacks/" >&2
  exit 1
fi
if [ -d "${ROOT}/tiles" ]; then
  echo "error: ${APP} flattened four states into FieldPacks/tiles/" >&2
  exit 1
fi

for id in us-tx us-nm us-fl us-ny; do
  if [ ! -f "${ROOT}/${id}/manifest.json" ]; then
    echo "error: ${APP} missing FieldPacks/${id}/manifest.json" >&2
    exit 1
  fi
  if [ ! -d "${ROOT}/${id}/tiles" ]; then
    echo "error: ${APP} missing FieldPacks/${id}/tiles" >&2
    exit 1
  fi
  count="$(find "${ROOT}/${id}/tiles" -name '*.png' | wc -l | tr -d '[:space:]')"
  if [ "${count}" -lt 1 ]; then
    echo "error: ${APP} FieldPacks/${id} has no PNG tiles" >&2
    exit 1
  fi
  echo "FieldPacks/${id} ready: ${count} PNG tiles"
done

for city in el-paso las-cruces albuquerque; do
  if [ -d "${ROOT}/${city}" ]; then
    echo "error: city pack ${city} must not be in the IPA" >&2
    exit 1
  fi
done

echo "FieldPacks in .app ok: us-tx us-nm us-fl us-ny Ready, no city packs, no merged tiles/"
