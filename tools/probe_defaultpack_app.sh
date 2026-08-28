#!/usr/bin/env bash
# Fail if Blackout.app does not contain DefaultPack/tiles/z/x/y.png files.
# Intended for CI after xcodebuild archive or simulator build.
set -euo pipefail

APP="${1:?path to Blackout.app}"
PACK="${APP}/DefaultPack"
PROBE="${PACK}/tiles/10/211/387.png"
MANIFEST="${PACK}/manifest.json"

if [ ! -d "${APP}" ]; then
  echo "error: Blackout.app missing at ${APP}" >&2
  exit 1
fi
if [ ! -f "${MANIFEST}" ]; then
  echo "error: ${APP} has no DefaultPack/manifest.json" >&2
  find "${APP}" -maxdepth 2 | head -80 >&2
  exit 1
fi

NEED="$(sed -n 's/.*"tileCount"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "${MANIFEST}" | head -1)"
if [ -z "${NEED}" ]; then
  echo "error: DefaultPack manifest.json missing tileCount" >&2
  exit 1
fi

if [ ! -d "${PACK}/tiles" ]; then
  echo "error: ${APP} DefaultPack/tiles directory missing" >&2
  exit 1
fi

COUNT="$(find "${PACK}/tiles" -name '*.png' | wc -l | tr -d '[:space:]')"
echo "Blackout.app DefaultPack PNG count: ${COUNT} (need ${NEED})"
echo "Probe path: ${PROBE}"

if [ ! -f "${PROBE}" ]; then
  echo "error: missing ${PROBE} — tiles/z/x/y.png did not land in the .app" >&2
  find "${PACK}" | head -80 >&2
  exit 1
fi
if [ ! -d "${PACK}/tiles/10/211" ] || [ ! -f "${PACK}/tiles/12/848/1553.png" ]; then
  echo "error: DefaultPack tiles are not in tiles/z/x/y.png layout" >&2
  find "${PACK}/tiles" | head -80 >&2
  exit 1
fi
if [ "${COUNT}" -lt "${NEED}" ]; then
  echo "error: Blackout.app has ${COUNT} DefaultPack PNGs, manifest tileCount is ${NEED}" >&2
  exit 1
fi

echo "DefaultPack in .app ok: Front Range sample tiles/${NEED} PNGs, including tiles/10/211/387.png"
