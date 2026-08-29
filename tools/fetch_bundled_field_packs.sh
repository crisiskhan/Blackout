#!/usr/bin/env bash
# Archive-time only. Download the four statewide packs from packs-v1, verify
# sha256, ROOT-flatten into BundledFieldPacks/<us-xx>/. Never city packs.
# Do not commit the zips or the staging folder.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${FIELD_PACKS_SRC:-${ROOT}/BundledFieldPacks}"
ZIPDIR="${FIELD_PACKS_ZIPDIR:-${RUNNER_TEMP:-${DEST}/.zips}}"
BASE="https://github.com/crisiskhan/Blackout/releases/download/packs-v1"

# id|filename|bytes|sha256
PACKS=(
  "us-tx|texas.pack.zip|208461647|dc74d8069ca161f0c818dcfb760037d79ae96c9da777b550f095cf0b9569bbfb"
  "us-nm|new-mexico.pack.zip|77478829|2e605b0a386c6fbfa1288e5bea4ef96f42ddd5c60633f954b42c8c0e7665a4a8"
  "us-fl|florida.pack.zip|79093063|49d27c808c49fc894a1ba1021f951966560408c1ebe808f4c0d158e0c238b62d"
  "us-ny|new-york.pack.zip|130327390|928034851277ab8628521f5bfd7f2f06e6bfed5b588d58f9b46033bae5e64500"
)

verify_sha() {
  local file="$1"
  local expect="$2"
  local got
  if command -v shasum >/dev/null 2>&1; then
    got="$(shasum -a 256 "${file}" | awk '{print $1}')"
  else
    got="$(sha256sum "${file}" | awk '{print $1}')"
  fi
  if [ "${got}" != "${expect}" ]; then
    echo "error: sha256 mismatch for ${file}" >&2
    echo "  expected ${expect}" >&2
    echo "  got      ${got}" >&2
    exit 1
  fi
}

# Unzip so dest/manifest.json + dest/tiles/ exist. Strip one wrapper folder.
stage_zip() {
  local zip="$1"
  local dest="$2"
  local tmp root
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/blackout-pack.XXXXXX")"
  unzip -q "${zip}" -d "${tmp}"
  if [ -f "${tmp}/manifest.json" ]; then
    root="${tmp}"
  else
    root=""
    local dir
    for dir in "${tmp}"/*; do
      [ -d "${dir}" ] || continue
      case "$(basename "${dir}")" in
        __MACOSX|.DS_Store) continue ;;
      esac
      if [ -f "${dir}/manifest.json" ]; then
        if [ -n "${root}" ]; then
          echo "error: ${zip} has more than one pack root" >&2
          rm -rf "${tmp}"
          exit 1
        fi
        root="${dir}"
      fi
    done
    if [ -z "${root}" ]; then
      local found
      found="$(find "${tmp}" -name manifest.json -type f | head -1 || true)"
      if [ -z "${found}" ]; then
        echo "error: ${zip} has no manifest.json" >&2
        rm -rf "${tmp}"
        exit 1
      fi
      root="$(dirname "${found}")"
    fi
  fi
  if [ ! -d "${root}/tiles" ]; then
    echo "error: ${zip} pack root missing tiles/" >&2
    rm -rf "${tmp}"
    exit 1
  fi
  rm -rf "${dest}"
  mkdir -p "${dest}"
  cp -a "${root}/." "${dest}/"
  rm -rf "${tmp}"
  if [ ! -f "${dest}/manifest.json" ] || [ ! -d "${dest}/tiles" ]; then
    echo "error: ROOT-flatten failed for ${zip} -> ${dest}" >&2
    exit 1
  fi
}

if [ "${1:-}" = "--stage-zip" ]; then
  stage_zip "$2" "$3"
  exit 0
fi

mkdir -p "${DEST}" "${ZIPDIR}"

for spec in "${PACKS[@]}"; do
  IFS='|' read -r id filename bytes sha <<<"${spec}"
  url="${BASE}/${filename}"
  zip="${ZIPDIR}/${filename}"
  echo "Fetching ${id} from ${url}"
  curl -fL --retry 4 --retry-delay 4 --retry-all-errors -o "${zip}" "${url}"
  size="$(wc -c < "${zip}" | tr -d '[:space:]')"
  if [ "${size}" != "${bytes}" ]; then
    echo "error: ${filename} size ${size}, expected ${bytes}" >&2
    exit 1
  fi
  verify_sha "${zip}" "${sha}"
  echo "Verified ${filename} sha256 ${sha}"
  stage_zip "${zip}" "${DEST}/${id}"
  echo "Staged ${id} -> ${DEST}/${id}"
done

# Refuse city-only packs in the IPA staging tree.
for city in el-paso las-cruces albuquerque; do
  if [ -d "${DEST}/${city}" ]; then
    echo "error: city pack ${city} must not be staged into the IPA" >&2
    exit 1
  fi
done

# Refuse a merged tiles/ directory at the FieldPacks root.
if [ -d "${DEST}/tiles" ]; then
  echo "error: do not flatten four states into one tiles/ directory" >&2
  exit 1
fi

echo "Statewide Field Packs staged: us-tx us-nm us-fl us-ny under ${DEST}"
