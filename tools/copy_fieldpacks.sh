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

# Whole-tree ditto already copies routing/ when present. Re-ditto that folder
# and fail if the source graph was dropped. Packs without routing/ stay honest-empty.
copy_routing_if_present() {
  local from="$1"
  local to="$2"
  local id="$3"
  if [ ! -d "${from}/routing" ]; then
    return 0
  fi
  copy_tree "${from}/routing" "${to}/routing"
  local f
  for f in routing.json graph.bin names.bin geometry.bin; do
    if [ ! -f "${to}/routing/${f}" ]; then
      echo "error: ${id} source has routing/ but copied tree is missing routing/${f}" >&2
      exit 1
    fi
  done
  local graph_magic names_magic geom_magic
  graph_magic="$(dd if="${to}/routing/graph.bin" bs=8 count=1 2>/dev/null || true)"
  names_magic="$(dd if="${to}/routing/names.bin" bs=8 count=1 2>/dev/null || true)"
  geom_magic="$(dd if="${to}/routing/geometry.bin" bs=8 count=1 2>/dev/null || true)"
  if [ "${graph_magic}" != "BLRG0001" ] || [ "${names_magic}" != "BLNM0001" ] || [ "${geom_magic}" != "BLGM0001" ]; then
    echo "error: ${id} routing/ magic mismatch (need BLRG0001 / BLNM0001 / BLGM0001)" >&2
    exit 1
  fi
  echo "Copied FieldPacks/${id} routing/ (graph+names+geometry)"
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
  copy_routing_if_present "${pack}" "${DST}/${id}" "${id}"
  count="$(find "${DST}/${id}/tiles" -name '*.png' | wc -l | tr -d '[:space:]')"
  if [ "${count}" -lt 1 ]; then
    echo "error: copied ${id} has no PNG tiles" >&2
    exit 1
  fi
  case "${id}" in
    us-tx) printf '%s\n' "6ff6c9a191fe5df8d3bf48abb360ad361990bc672c1c59bd0cf2e3a3d5d55ade" > "${DST}/${id}/catalog.sha256" ;;
    us-nm) printf '%s\n' "2e605b0a386c6fbfa1288e5bea4ef96f42ddd5c60633f954b42c8c0e7665a4a8" > "${DST}/${id}/catalog.sha256" ;;
    us-fl) printf '%s\n' "49d27c808c49fc894a1ba1021f951966560408c1ebe808f4c0d158e0c238b62d" > "${DST}/${id}/catalog.sha256" ;;
    us-ny) printf '%s\n' "928034851277ab8628521f5bfd7f2f06e6bfed5b588d58f9b46033bae5e64500" > "${DST}/${id}/catalog.sha256" ;;
  esac
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
