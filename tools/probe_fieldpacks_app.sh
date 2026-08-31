#!/usr/bin/env bash
# Fail if Blackout.app is missing the three statewide Field Packs (FL TX NM) as Ready roots.
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
  echo "error: ${APP} flattened three states into FieldPacks/tiles/" >&2
  exit 1
fi

for id in us-tx us-nm us-fl; do
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
  if [ -d "${ROOT}/${id}/routing" ]; then
    for f in routing.json graph.bin names.bin geometry.bin; do
      if [ ! -f "${ROOT}/${id}/routing/${f}" ]; then
        echo "error: ${APP} FieldPacks/${id}/routing missing ${f}" >&2
        exit 1
      fi
    done
    graph_magic="$(dd if="${ROOT}/${id}/routing/graph.bin" bs=8 count=1 2>/dev/null || true)"
    names_magic="$(dd if="${ROOT}/${id}/routing/names.bin" bs=8 count=1 2>/dev/null || true)"
    geom_magic="$(dd if="${ROOT}/${id}/routing/geometry.bin" bs=8 count=1 2>/dev/null || true)"
    if [ "${graph_magic}" != "BLRG0001" ] || [ "${names_magic}" != "BLNM0001" ] || [ "${geom_magic}" != "BLGM0001" ]; then
      echo "error: ${APP} FieldPacks/${id}/routing magic mismatch" >&2
      exit 1
    fi
    echo "FieldPacks/${id} routing/ present (BLRG0001 / BLNM0001 / BLGM0001)"
  fi
done

if [ -d "${ROOT}/us-ny" ]; then
  echo "error: New York pack must not be in the IPA" >&2
  exit 1
fi

for city in el-paso las-cruces albuquerque; do
  if [ -d "${ROOT}/${city}" ]; then
    echo "error: city pack ${city} must not be in the IPA" >&2
    exit 1
  fi
done

echo "FieldPacks in .app ok: us-tx us-nm us-fl Ready, no city packs, no merged tiles/"
