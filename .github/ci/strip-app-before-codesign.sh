#!/bin/sh
# CI-only. Injected as a Run Script before CodeSign.
# Do NOT xattr -cr the .app.
# Do NOT rm / ditto / chmod 644 Assets.car, PrivacyInfo.xcprivacy, or embedded.mobileprovision.
# Proven CodeSign failures (code object is not signed at all):
#   33823846800  xattr -cr              → Assets.car
#   33824248310  rm Assets.car + xattr  → embedded.mobileprovision
#   33824455260  xattr + chmod 644 janitor → PrivacyInfo.xcprivacy
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
  if [ -f "$APP/Assets.car" ]; then
    echo "CI Assets.car before a-x:"
    ls -lO@ "$APP/Assets.car" || ls -la "$APP/Assets.car" || true
    file "$APP/Assets.car" || true
    /bin/chmod a-x "$APP/Assets.car" || true
    echo "CI Assets.car after a-x:"
    ls -lO@ "$APP/Assets.car" || ls -la "$APP/Assets.car" || true
  fi
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
