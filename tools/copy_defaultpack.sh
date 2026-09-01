#!/usr/bin/env bash
# Copy DefaultPack into Blackout.app and fail if tiles/z/x/y.png are missing.
# ditto-plus-manifest is not enough: an empty tiles/ folder still copies.
set -euo pipefail

SRC="${SRCROOT}/Blackout/DefaultPack"
DST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/DefaultPack"
PROBE_REL="tiles/10/211/387.png"

if [ ! -f "${SRC}/manifest.json" ]; then
  echo "error: DefaultPack missing at ${SRC}" >&2
  exit 1
fi
if [ -d "${SRC}/routing" ] || [ -f "${SRC}/routing/graph.bin" ]; then
  echo "error: DefaultPack must not ship routing/ — El Paso graph lives in Field Packs" >&2
  exit 1
fi
if [ ! -d "${SRC}/tiles" ]; then
  echo "error: DefaultPack tiles missing at ${SRC}/tiles" >&2
  exit 1
fi
if [ ! -f "${SRC}/${PROBE_REL}" ]; then
  echo "error: DefaultPack source missing ${PROBE_REL}" >&2
  exit 1
fi

NEED="$(sed -n 's/.*"tileCount"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "${SRC}/manifest.json" | head -1)"
if [ -z "${NEED}" ]; then
  echo "error: DefaultPack manifest.json missing tileCount" >&2
  exit 1
fi

SRC_COUNT="$(find "${SRC}/tiles" -name '*.png' | wc -l | tr -d '[:space:]')"
if [ "${SRC_COUNT}" -lt "${NEED}" ]; then
  echo "error: DefaultPack source has ${SRC_COUNT} PNGs, manifest tileCount is ${NEED}" >&2
  exit 1
fi

mkdir -p "${DST}"
if command -v ditto >/dev/null 2>&1; then
  ditto "${SRC}" "${DST}"
else
  cp -a "${SRC}/." "${DST}/"
fi

COUNT="$(find "${DST}/tiles" -name '*.png' | wc -l | tr -d '[:space:]')"
echo "DefaultPack archive probe: ${COUNT} PNG tiles (need ${NEED}) under ${DST}/tiles/z/x/y.png"

if [ "${COUNT}" -lt "${NEED}" ]; then
  echo "error: DefaultPack copied ${COUNT} PNGs, manifest tileCount is ${NEED}" >&2
  find "${DST}" | head -80 >&2
  exit 1
fi
if [ ! -d "${DST}/tiles/10/211" ]; then
  echo "error: DefaultPack tiles not in tiles/z/x/y.png layout at ${DST}" >&2
  exit 1
fi
if [ ! -f "${DST}/${PROBE_REL}" ]; then
  echo "error: DefaultPack .app missing ${PROBE_REL}" >&2
  exit 1
fi
test -f "${DST}/manifest.json"
test -d "${DST}/tiles"
test -f "${DST}/tiles/12/848/1553.png"
echo "DefaultPack copy ok: ${PROBE_REL} and ${COUNT} PNGs in the .app"
