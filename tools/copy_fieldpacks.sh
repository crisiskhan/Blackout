#!/usr/bin/env bash
# Copy staged statewide Field Packs into Blackout.app/FieldPacks/<id>/.
# Compile/unsigned: staging is absent — no-op.
# Archive: FIELD_PACKS_REQUIRED=1 fails the build if any of the four is missing.
# Each state stays in its own folder so tile z/x/y.png names cannot collide.
set -euo pipefail

SRC="${FIELD_PACKS_SRC:-${SRCROOT}/BundledFieldPacks}"
DST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/FieldPacks"
IDS="us-tx us-nm us-fl us-ny"
REQUIRED="${FIELD_PACKS_REQUIRED:-0}"

copy_tree() {
  local from="$1"
  local to="$2"
  mkdir -p "${to}"
  if command -v ditto >/dev/null 2>&1; then
    ditto "${from}" "${to}"
  else
    cp -a "${from}/." "${to}/"
  fi
}

if [ ! -d "${SRC}" ]; then
  if [ "${REQUIRED}" = "1" ]; then
    echo "error: Field Packs staging missing at ${SRC} (archive must fetch first)" >&2
    exit 1
  fi
  echo "FieldPacks staging absent — unsigned compile skips statewide copy"
  exit 0
fi

copied=0
for id in ${IDS}; do
  pack="${SRC}/${id}"
  if [ ! -f "${pack}/manifest.json" ] || [ ! -d "${pack}/tiles" ]; then
    if [ "${REQUIRED}" = "1" ]; then
      echo "error: staged pack ${id} missing manifest.json or tiles/ at ${pack}" >&2
      exit 1
    fi
    echo "skip ${id} — not staged"
    continue
  fi
  copy_tree "${pack}" "${DST}/${id}"
  if [ ! -f "${DST}/${id}/manifest.json" ] || [ ! -d "${DST}/${id}/tiles" ]; then
    echo "error: copied ${id} is missing manifest.json or tiles/" >&2
    exit 1
  fi
  count="$(find "${DST}/${id}/tiles" -name '*.png' | wc -l | tr -d '[:space:]')"
  if [ "${count}" -lt 1 ]; then
    echo "error: copied ${id} has no PNG tiles" >&2
    exit 1
  fi
  echo "Copied FieldPacks/${id} (${count} PNG tiles)"
  copied=$((copied + 1))
done

if [ -d "${DST}/tiles" ]; then
  echo "error: FieldPacks/tiles would collide across states — keep us-tx/us-nm/us-fl/us-ny" >&2
  exit 1
fi

if [ "${REQUIRED}" = "1" ] && [ "${copied}" -ne 4 ]; then
  echo "error: archive needs all four statewide packs, copied ${copied}" >&2
  exit 1
fi

echo "FieldPacks copy ok: ${copied} statewide pack(s) under ${DST}"
