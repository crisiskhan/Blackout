#!/bin/sh
# CI-only. Copied to $SRCROOT/ci_strip_appicon.sh and injected as a Run Script.
# Do NOT xattr -cr the .app or the repo.
# Do NOT rm / ditto / chmod 644 Assets.car, PrivacyInfo.xcprivacy, or embedded.mobileprovision.
# Proven CodeSign failures (code object is not signed at all):
#   33823846800  xattr -cr                 → Assets.car
#   33824248310  rm Assets.car + xattr     → embedded.mobileprovision
#   33824455260  xattr + chmod 644 janitor → PrivacyInfo.xcprivacy
#   33824948720  rm PrivacyInfo, no a-x    → Assets.car
set -e
strip_app() {
  APP="$1"
  [ -d "$APP" ] || return 0
  echo "CI AppIcon strip app=$APP"
  find "$APP" -maxdepth 1 -name "AppIcon*.png" -print -delete || true
  if [ -d "$APP/Metadata.appintents" ]; then
    echo "CI remove unsigned Metadata.appintents"
    rm -rf "$APP/Metadata.appintents"
  fi
  # Top-level data files only. +x (SetMode a+rX) makes codesign treat them as nested code.
  # a-x does not rewrite contents. Do not chmod 644 and do not xattr.
  for f in "$APP/Assets.car" "$APP/PrivacyInfo.xcprivacy" "$APP/embedded.mobileprovision"; do
    if [ -f "$f" ]; then
      echo "CI before a-x $(basename "$f"):"
      ls -lO@ "$f" || ls -la "$f" || true
      /bin/chmod a-x "$f" || true
      echo "CI after a-x $(basename "$f"):"
      ls -lO@ "$f" || ls -la "$f" || true
    fi
  done
  find "$APP" -maxdepth 1 -type f -name "*.png" -exec /bin/chmod a-x {} + 2>/dev/null || true
}
strip_app "$CODESIGNING_FOLDER_PATH"
strip_app "$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
strip_app "$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
if [ -n "${BUILD_DIR:-}" ]; then
  find "$BUILD_DIR" -type d -path "*/InstallationBuildProductsLocation/Applications/*.app" 2>/dev/null | while read -r APP; do
    strip_app "$APP"
  done
fi
