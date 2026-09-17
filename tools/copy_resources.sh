#!/bin/bash
# Flatten Packs/Field/Vision into the .app root. Merge GitHub NAIP shards
# into one aerial.pmtiles the Metal canvas actually draws. Leave NM photo
# shards off the phone (tf-174/176 IPA ~4.21 GB then ASC INVALID; tf-173
# 3.52 GB VALID). Leave build GeoJSON and Cesium off the phone.
set -euo pipefail
SRC="${SRCROOT}/Resources"
DST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
if [ ! -f "${SRC}/Packs/catalog.json" ]; then
  echo "error: Resources/Packs/catalog.json missing" >&2
  exit 1
fi
mkdir -p "${DST}"
rsync -a \
  --exclude 'Globe' \
  --exclude 'Packs/*/osm.geojson' \
  --exclude 'Packs/*/khan.geojson' \
  --exclude 'Packs/*/osm.fetched' \
  --exclude 'Packs/*/.naip-cache' \
  --exclude 'Packs/*/.aerial-write' \
  --exclude 'Packs/*/metro.geojson' \
  --exclude 'Packs/*/region.geojson' \
  --exclude 'Packs/*/union.geojson' \
  --exclude 'Packs/*/corridor.geojson' \
  --exclude 'Packs/*/border.geojson' \
  --exclude 'Packs/*/desk3d.geojson' \
  --exclude 'Packs/*/pois.geojson' \
  --exclude 'Packs/*/walk-dem.json' \
  --exclude 'Packs/*/contours.geojson' \
  --exclude 'Packs/*/wild.geojson' \
  --exclude 'Packs/*/layers/public_land.geojson' \
  --exclude 'Packs/*/layers/flood.geojson' \
  --exclude 'Packs/*/layers/hazards.geojson' \
  --exclude 'Packs/*/layers/ground.geojson' \
  --exclude 'Packs/*/layers/water.geojson' \
  --exclude 'Packs/nm/aerial*.pmtiles' \
  "${SRC}/" "${DST}/"
rm -rf "${DST}/Resources"
rm -rf "${DST}/Globe"
export PYTHONPATH="${SRCROOT}/tools/third_party:${SRCROOT}/tools${PYTHONPATH:+:$PYTHONPATH}"
python3 "${SRCROOT}/tools/pack_phone.py" "${DST}"
test -f "${DST}/Packs/catalog.json"
test -f "${DST}/Field/field.core.json"
test -f "${DST}/Vision/labels.tx.json"
test ! -d "${DST}/Globe"
test ! -f "${DST}/Packs/tx-west/osm.geojson"
test ! -f "${DST}/Packs/tx-west/aerial-1.pmtiles"
test -f "${DST}/Packs/tx-west/aerial.pmtiles"
test -f "${DST}/Packs/tx-west/overlay.pmtiles"
test -f "${DST}/Packs/tx-west/layers/water.bin"
test -f "${DST}/Packs/nm/overlay.pmtiles"
test -f "${DST}/Packs/tx-east/overlay.pmtiles"
test ! -f "${DST}/Packs/nm/aerial-1.pmtiles"
test ! -f "${DST}/Packs/nm/aerial.pmtiles"
test ! -f "${DST}/Packs/tx-east/aerial-1.pmtiles"
