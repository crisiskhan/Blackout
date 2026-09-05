#!/bin/bash
# Archive, then recover a signed Blackout.app if xcarchive assembly fails.
# 33829001016: packaging left Products/Applications/Blackout.app but no
# xcarchive Info.plist. Do not rm _CodeSignature and leave unsigned.
# Write Info.plist and exportArchive or hand-zip the signed .app. No xattr.
# 33931034850: ExportOptions signingCertificate from find-identity (not a
# hard-coded Apple Distribution). Hand-zip fail-closed on submission Authority.
set -euo pipefail
NEXT="${NEXT_CPV:?NEXT_CPV not set}"
if [ -z "$NEXT" ]; then
  echo "No next CFBundleVersion. No archive."
  exit 1
fi
echo "CURRENT_PROJECT_VERSION on the command line only: $NEXT (not committed)"

if [ -n "${SIGNING_KEYCHAIN:-}" ] && [ -f "$SIGNING_KEYCHAIN" ]; then
  security unlock-keychain -p "$SIGNING_KC_PASS" "$SIGNING_KEYCHAIN"
  security set-keychain-settings -lut 21600 "$SIGNING_KEYCHAIN"
  security default-keychain -s "$SIGNING_KEYCHAIN"
  EXISTING=$(security list-keychains -d user | sed 's/"//g')
  security list-keychains -d user -s "$SIGNING_KEYCHAIN" $EXISTING
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$SIGNING_KC_PASS" "$SIGNING_KEYCHAIN" || true
  echo "identities after unlock:"
  security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" || true
  security find-identity -v -p codesigning || true
fi

ARCHIVE="$RUNNER_TEMP/Blackout.xcarchive"
EXPORT="$RUNNER_TEMP/export"
AUTH=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$AUTH_KEY_PATH"
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID"
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"
)

# 33931034850: write signingCertificate from the Dist find-identity alias
# (iPhone Distribution / Apple Distribution / iOS Distribution). Do not
# hard-code Apple Distribution — that misses an iPhone Distribution keychain
# identity and exportArchive then looks for 3rd Party Mac Developer Installer.
IDLINE=$(security find-identity -v -p codesigning "${SIGNING_KEYCHAIN:-}" 2>/dev/null | grep -i Distribution | grep -v "CSSMERR" | head -n 1 || true)
if [ -z "$IDLINE" ]; then
  IDLINE=$(security find-identity -v -p codesigning | grep -i Distribution | grep -v "CSSMERR" | head -n 1 || true)
fi
IDHASH=""
if [ -n "$IDLINE" ]; then
  IDHASH=$(printf '%s' "$IDLINE" | awk '{print $2}')
  echo "Using Dist identity $IDLINE"
fi
"$PYBIN" tools/tf_archive_signing.py write-export-options "$IDLINE"

# 33926435868 / 33927056130: HAS_LOCAL_DIST_KEY=1 Manual Dist on
# com.crisiskhan.blackout + com.crisiskhan.blackout.widgets only
# (Blackout iOS App Store GHA Local / Blackout Widgets App Store GHA Local).
# Do not write CODE_SIGN_IDENTITY on the xcodebuild CLI — that hits SPM
# packages. Identity placeholder and hash rewrite share one string in
# tools/tf_archive_signing.py (iPhone Distribution).
"$PYBIN" tools/tf_archive_signing.py patch

if [ -n "$IDHASH" ]; then
  echo "Using CODE_SIGN_IDENTITY hash=$IDHASH"
  "$PYBIN" tools/tf_archive_signing.py rewrite-hash "$IDHASH"
fi

# 33825793771 stock+STANDALONE_ICON_BEHAVIOR=none: no AppIcon pngs; CodeSign
# died on Metadata.appintents. No-op the App Intents processors.
# 33825608089: after Metadata was gone, 644 PrivacyInfo / Assets.car were
# still "unsigned nested code". 33826265768: blob-sign of those two moved
# CodeSign to embedded.mobileprovision. Blob-sign all three.
DEVELOPER_DIR="$(xcode-select -p)"
XCTool="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
for tool in appintentsmetadataprocessor appintentsnltrainingprocessor; do
  SRC="$XCTool/$tool"
  if [ -x "$SRC" ] && [ ! -e "$SRC.blackout-real" ]; then
    sudo mv "$SRC" "$SRC.blackout-real"
    echo 'IyEvYmluL2Jhc2gKIyBCbGFja291dCBHSGEgbm8tb3A6IHNraXAgQXBwIEludGVudHMgbWV0YWRhdGEgZ2VuZXJhdGlvbiAocnVubmVyLU9OTFkpCmV4aXQgMAo=' | base64 -d | sudo tee "$SRC" >/dev/null
    sudo chmod 755 "$SRC"
    echo "no-op installed: $tool"
  elif [ -x "$SRC" ]; then
    echo "no-op already present: $tool"
  else
    echo "WARNING: missing $SRC"
  fi
done
restore_intent_tools() {
  for tool in appintentsmetadataprocessor appintentsnltrainingprocessor; do
    SRC="$XCTool/$tool"
    if [ -e "$SRC.blackout-real" ]; then
      sudo mv -f "$SRC.blackout-real" "$SRC" 2>/dev/null || true
      echo "restored $tool"
    fi
  done
}
trap restore_intent_tools EXIT

"$PYBIN" << 'PY'
from pathlib import Path
script = Path("ci_blob_sign_resources.sh")
script.write_text(
    "#!/bin/sh\n"
    "set -e\n"
    'APP="${CODESIGNING_FOLDER_PATH:-}"\n'
    '[ -d "$APP" ] || exit 0\n'
    'echo "CI blob-sign resources app=$APP"\n'
    # 33827851150: archive packaging reads the built .app Info.plist.
    # Source plist used to be NSBonjourServices-only; log + inject if
    # ProcessInfoPlistFile still omitted CFBundleIdentifier.
    'BID="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$APP/Info.plist" 2>/dev/null || true)"\n'
    'echo "processed CFBundleIdentifier=${BID:-MISSING}"\n'
    'echo "processed CFBundleVersion=$(/usr/bin/plutil -extract CFBundleVersion raw "$APP/Info.plist" 2>/dev/null || echo MISSING)"\n'
    'echo "processed CFBundleShortVersionString=$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP/Info.plist" 2>/dev/null || echo MISSING)"\n'
    'if [ -z "$BID" ]; then\n'
    '  WANT="${PRODUCT_BUNDLE_IDENTIFIER:-com.crisiskhan.blackout}"\n'
    '  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $WANT" "$APP/Info.plist" 2>/dev/null \\\n'
    '    || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $WANT" "$APP/Info.plist"\n'
    '  echo "injected CFBundleIdentifier=$WANT"\n'
    'fi\n'
    'rm -rf "$APP/Metadata.appintents" 2>/dev/null || true\n'
    'find "$APP" -maxdepth 1 -name "AppIcon*.png" -delete 2>/dev/null || true\n'
    'ID="${EXPANDED_CODE_SIGN_IDENTITY:-}"\n'
    'if [ -z "$ID" ] || [ "$ID" = "-" ]; then ID="${CODE_SIGN_IDENTITY:-}"; fi\n'
    'if [ -z "$ID" ] || [ "$ID" = "-" ]; then\n'
    '  echo "CI blob-sign skip: no identity"\n'
    'else\n'
    '  for f in "$APP/Assets.car" "$APP/PrivacyInfo.xcprivacy" "$APP/embedded.mobileprovision"; do\n'
    '    [ -f "$f" ] || continue\n'
    '    echo "CI blob-sign $f"\n'
    '    /usr/bin/codesign --force --sign "$ID" --timestamp=none --identifier "com.crisiskhan.blackout.$(basename "$f")" "$f"\n'
    '  done\n'
    'fi\n'
    # After identifier + blob-sign, copy off the install tree. 33827851150
    # tore it down after CodeSign. Widget is already embedded. Watch is not.
    'SNAP="${RUNNER_TEMP:-/Users/runner/work/_temp}/recovered-Blackout.app"\n'
    'rm -rf "$SNAP"\n'
    'cp -a "$APP" "$SNAP"\n'
    'echo "CI snapshot $SNAP"\n'
)
script.chmod(0o755)
path = Path("Blackout.xcodeproj/project.pbxproj")
text = path.read_text()
phase_id = "C1A00001B007000000000002"
note = "CI blob-sign Assets.car and PrivacyInfo"
if phase_id in text:
    print("blob-sign phase already present")
else:
    phase = (
        f"\t\t{phase_id} /* {note} */ = {{\n"
        "\t\t\tisa = PBXShellScriptBuildPhase;\n"
        "\t\t\talwaysOutOfDate = 1;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n\t\t\t);\n"
        "\t\t\tinputFileListPaths = (\n\t\t\t);\n"
        "\t\t\tinputPaths = (\n\t\t\t);\n"
        f'\t\t\tname = "{note}";\n'
        "\t\t\toutputFileListPaths = (\n\t\t\t);\n"
        "\t\t\toutputPaths = (\n\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 1;\n"
        "\t\t\tshellPath = /bin/sh;\n"
        '\t\t\tshellScript = "\\"$SRCROOT/ci_blob_sign_resources.sh\\"\\n";\n'
        "\t\t\tshowEnvVarsInLog = 0;\n"
        "\t\t};\n"
    )
    marker = "/* Begin PBXShellScriptBuildPhase section */\n"
    if marker not in text:
        raise SystemExit("PBXShellScriptBuildPhase section missing")
    text = text.replace(marker, marker + phase, 1)
    needle = "\t\t\t\t22B4790C46112DC12EE4F2A3 /* Embed Foundation Extensions */,\n"
    if needle not in text:
        raise SystemExit("Embed Foundation Extensions missing")
    text = text.replace(needle, needle + f"\t\t\t\t{phase_id} /* {note} */,\n", 1)
    path.write_text(text)
    print("injected blob-sign phase")
print("blob-sign script ready")
PY

DD="$RUNNER_TEMP/DerivedData"
SNAP="$RUNNER_TEMP/recovered-Blackout.app"
rm -rf "$DD" "$ARCHIVE" "$EXPORT" "$SNAP"
mkdir -p "$EXPORT"

# 33927056130: do not pass CODE_SIGN_IDENTITY on this CLI. It applies to
# every target including SPM packages (VisionCoreML, Tokens, MapLibreMap).
# Those stay Automatic. App/widget identity is the CI pbx patch only.
set +e
echo "xcodebuild archive..."
xcodebuild \
  -project Blackout.xcodeproj \
  -scheme Blackout \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$NEXT" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGNING_ALLOWED=YES \
  STANDALONE_ICON_BEHAVIOR=none \
  ASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR=none \
  ENABLE_APP_INTENTS_METADATA_GENERATION=NO \
  "${AUTH[@]}" \
  archive 2>&1 | tee "$RUNNER_TEMP/archive.log"
echo "${PIPESTATUS[0]}" > "$RUNNER_TEMP/archive.exit"
set -e
ARC="$(cat "$RUNNER_TEMP/archive.exit")"
echo "archive exit=$ARC"

echo "---- Blackout.app locations ----"
find "$DD" -name 'Blackout.app' 2>/dev/null || true
if [ -e "$ARCHIVE" ]; then
  echo "---- archive tree ----"
  ls -la "$ARCHIVE" || true
  find "$ARCHIVE" -name 'Blackout.app' 2>/dev/null || true
  if [ -f "$ARCHIVE/Info.plist" ]; then
    echo "---- archive Info.plist ----"
    plutil -p "$ARCHIVE/Info.plist" || true
  fi
else
  echo "no xcarchive at $ARCHIVE"
fi
if [ -d "$SNAP" ]; then
  echo "---- blob-sign snapshot present $SNAP ----"
  ls -ld "$SNAP" || true
fi

# Prefer a still-living post-CodeSign product. Fall back to the snapshot
# taken during blob-sign (33827851150: archive assembly deleted the install
# tree; BuildProductsPath/Blackout.app was only a symlink to it).
APP=""
for cand in \
  "$ARCHIVE/Products/Applications/Blackout.app" \
  "$DD/Build/Intermediates.noindex/ArchiveIntermediates/Blackout/InstallationBuildProductsLocation/Applications/Blackout.app" \
  "$SNAP"
do
  if [ -d "$cand" ] && [ -f "$cand/Blackout" ] && [ -f "$cand/Info.plist" ]; then
    APP="$cand"
    echo "picked $APP"
    break
  fi
done
if [ -z "$APP" ]; then
  while IFS= read -r cand; do
    if [ -f "$cand/Blackout" ] && [ -f "$cand/Info.plist" ]; then
      APP="$cand"
      echo "picked find $APP"
      break
    fi
  done < <(find "$DD" -name 'Blackout.app' 2>/dev/null || true)
fi

if [ "$ARC" -eq 0 ] && [ -n "$APP" ] && [ "$APP" != "$SNAP" ]; then
  rm -rf "$SNAP"
  cp -a "$APP" "$SNAP"
  APP="$SNAP"
  echo "copied live product to $SNAP"
fi

if [ -n "$APP" ] && [ -f "$APP/Info.plist" ]; then
  echo "CFBundleIdentifier=$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist" 2>/dev/null || echo missing)"
  echo "CFBundleVersion=$(plutil -extract CFBundleVersion raw "$APP/Info.plist" 2>/dev/null || echo missing)"
fi

find_local_ios_provision() {
  local d f name
  for d in \
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
    "$HOME/Library/MobileDevice/Provisioning Profiles"
  do
    [ -d "$d" ] || continue
    for f in "$d"/*.mobileprovision; do
      [ -f "$f" ] || continue
      name=$(security cms -D -i "$f" 2>/dev/null | plutil -extract Name raw -o - - 2>/dev/null || true)
      if [ "$name" = "Blackout iOS App Store GHA Local" ]; then
        printf '%s' "$f"
        return 0
      fi
    done
  done
  return 1
}

provision_entitlements() {
  local prov="$1"
  local dest="$2"
  "$PYBIN" - "$prov" "$dest" << 'PY'
import plistlib, subprocess, sys
from pathlib import Path
raw = subprocess.check_output(["security", "cms", "-D", "-i", sys.argv[1]], stderr=subprocess.DEVNULL)
pl = plistlib.loads(raw)
Path(sys.argv[2]).write_bytes(plistlib.dumps(pl.get("Entitlements") or {}))
print("wrote", sys.argv[2])
PY
}

verify_submission_app() {
  local app="$1"
  local dv="$RUNNER_TEMP/codesign-dv.txt"
  local bid
  /usr/bin/codesign -d --verbose=4 "$app" > "$dv" 2>&1 || true
  if ! /usr/bin/codesign --verify --deep --strict "$app"; then
    echo "codesign --verify failed for $app"
    return 1
  fi
  if ! "$PYBIN" tools/tf_archive_signing.py check-submission-authority "$dv"; then
    echo "Fail closed: $app is not signed with an Apple submission Dist identity"
    return 1
  fi
  bid="$(plutil -extract CFBundleIdentifier raw "$app/Info.plist" 2>/dev/null || true)"
  if [ -z "$bid" ]; then
    bid="com.crisiskhan.blackout"
  fi
  if ! "$PYBIN" tools/tf_archive_signing.py check-identifier "$dv" "$bid"; then
    echo "Fail closed: $app codesign Identifier does not match CFBundleIdentifier=$bid"
    return 1
  fi
  return 0
}

resign_submission() {
  local app="$1"
  if [ -z "${IDHASH:-}" ]; then
    echo "No Dist keychain hash for re-sign"
    return 1
  fi
  echo "re-sign nested frameworks/appex then app with Dist hash $IDHASH"
  # Do not rm _CodeSignature and leave unsigned (33829001016).
  local prov=""
  prov="$(find_local_ios_provision || true)"
  if [ -n "$prov" ] && [ -f "$prov" ]; then
    cp "$prov" "$app/embedded.mobileprovision"
    echo "embedded Local iOS provision $prov"
  elif [ ! -f "$app/embedded.mobileprovision" ]; then
    echo "No Local iOS embedded.mobileprovision for re-sign"
    return 1
  fi
  local ENT=""
  local XCENT
  XCENT="$(find "$DD" -name 'Blackout.app.xcent' 2>/dev/null | head -n 1 || true)"
  if [ -n "$XCENT" ] && [ -f "$XCENT" ]; then
    ENT="$XCENT"
    echo "using xcent $ENT"
  else
    ENT="$RUNNER_TEMP/ent-main.plist"
    provision_entitlements "$app/embedded.mobileprovision" "$ENT"
  fi
  if [ -d "$app/Frameworks" ]; then
    while IFS= read -r fw; do
      echo "re-sign nested $fw"
      /usr/bin/codesign --force --sign "$IDHASH" --identifier com.maplibre.mapbox --timestamp --generate-entitlement-der "$fw"
    done < <(find "$app/Frameworks" -name '*.framework' -print | sort -r)
  fi
  if [ -d "$app/PlugIns" ]; then
    local WENT=""
    local WXCENT
    WXCENT="$(find "$DD" -name 'BlackoutWidgets.appex.xcent' 2>/dev/null | head -n 1 || true)"
    if [ -n "$WXCENT" ] && [ -f "$WXCENT" ]; then
      WENT="$WXCENT"
    fi
    while IFS= read -r appex; do
      echo "re-sign nested $appex"
      if [ -n "$WENT" ]; then
        /usr/bin/codesign --force --sign "$IDHASH" --identifier com.crisiskhan.blackout.widgets --entitlements "$WENT" --timestamp --generate-entitlement-der "$appex"
      else
        /usr/bin/codesign --force --sign "$IDHASH" --identifier com.crisiskhan.blackout.widgets --timestamp --generate-entitlement-der "$appex"
      fi
    done < <(find "$app/PlugIns" -name '*.appex' -print)
  fi
  /usr/bin/codesign --force --sign "$IDHASH" --identifier com.crisiskhan.blackout --entitlements "$ENT" --timestamp --generate-entitlement-der "$app"
  echo "re-signed $app"
}

ensure_submission_seal() {
  local app="$1"
  if verify_submission_app "$app"; then
    echo "archive product already has submission Authority"
    return 0
  fi
  echo "archive product signature incomplete after archive exit ${ARC:-?} — re-sign nested then app (no rm _CodeSignature)"
  resign_submission "$app" || {
    echo "Fail closed: re-sign failed. No altool."
    exit 1
  }
  if ! verify_submission_app "$app"; then
    echo "Fail closed: re-sign did not produce a submission Dist Authority. No altool."
    exit 1
  fi
}

prepare_app_for_upload() {
  local app="$1"
  echo "flatten reserved Resources on $app"
  "$PYBIN" tools/tf_ipa_inspect.py --app "$app"
  if [ -e "$app/Resources" ]; then
    echo "Fail closed: reserved Resources remains under $app"
    exit 1
  fi
}

handzip_ipa() {
  local src="$1"
  if [ ! -d "$src" ] || [ ! -f "$src/Blackout" ]; then
    echo "hand-zip source missing $src"
    return 1
  fi
  prepare_app_for_upload "$src"
  ensure_submission_seal "$src"
  rm -rf "$EXPORT"
  mkdir -p "$EXPORT/Payload"
  # 33931034850: info-zip of Payload produced an IPA Apple rejected as not
  # signed with a submission certificate. ditto keeps the Dist seal. Do not
  # ditto individual product files (Assets.car / PrivacyInfo / provision).
  # 33931992681: sequestering resource forks created reserved Blackout.app/Resources.
  ditto --norsrc "$src" "$EXPORT/Payload/Blackout.app"
  ( cd "$EXPORT" && ditto -c -k --norsrc --keepParent Payload Blackout.ipa )
  IPA="$EXPORT/Blackout.ipa"
  echo "hand-zipped $IPA from $src"
  if ! verify_submission_app "$EXPORT/Payload/Blackout.app"; then
    echo "Fail closed: hand-zip Payload/Blackout.app is not a submission Dist signature"
    exit 1
  fi
}

write_xcarchive_plist() {
  local app="$ARCHIVE/Products/Applications/Blackout.app"
  [ -d "$app" ] && [ -f "$app/Info.plist" ] || return 1
  local bid ver short identity
  bid="$(plutil -extract CFBundleIdentifier raw "$app/Info.plist" 2>/dev/null || true)"
  ver="$(plutil -extract CFBundleVersion raw "$app/Info.plist" 2>/dev/null || true)"
  short="$(plutil -extract CFBundleShortVersionString raw "$app/Info.plist" 2>/dev/null || true)"
  identity=$(printf '%s' "${IDLINE:-}" | sed -n 's/.*"\(.*\)".*/\1/p')
  "$PYBIN" tools/tf_archive_signing.py write-xcarchive-plist \
    "$ARCHIVE/Info.plist" "$bid" "$ver" "$short" "${APPLE_TEAM_ID}" "$identity" "$NEXT"
}

try_export_archive() {
  set +e
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT" \
    -exportOptionsPlist "$RUNNER_TEMP/ExportOptions.plist" \
    "${AUTH[@]}" \
    2>&1 | tee "$RUNNER_TEMP/export.log"
  EX="${PIPESTATUS[0]}"
  set -e
  IPA="$(ls "$EXPORT"/*.ipa 2>/dev/null | head -n 1 || true)"
  if [ "$EX" -eq 0 ] && [ -n "$IPA" ] && [ -f "$IPA" ]; then
    echo "exportArchive OK $IPA"
    return 0
  fi
  echo "exportArchive exit=${EX:-?} — will hand-zip"
  return 1
}

ARCH_APP="$ARCHIVE/Products/Applications/Blackout.app"
# 33829001016: archive packaging wrote Products/Applications/Blackout.app +
# dSYMs/Signatures but no xcarchive Info.plist (exit 70). Recover then rm'd
# _CodeSignature and codesign said "bundle format unrecognized". Do not
# rm _CodeSignature. no re-seal of a complete Dist product; re-sign only
# when hand-zip sees a missing submission Authority.
if [ -d "$ARCH_APP" ] && [ -f "$ARCH_APP/Blackout" ]; then
  echo "Archive product present (archive exit=$ARC) — flatten reserved Resources, then write Info.plist"
  prepare_app_for_upload "$ARCH_APP"
  if write_xcarchive_plist && [ -f "$ARCHIVE/Info.plist" ]; then
    echo "---- archive Info.plist after write ----"
    plutil -p "$ARCHIVE/Info.plist" || true
    try_export_archive || handzip_ipa "$ARCH_APP"
  else
    echo "xcarchive Info.plist write failed — hand-zip safety net"
    handzip_ipa "$ARCH_APP"
  fi
elif [ -n "$APP" ] && [ -d "$APP" ]; then
  echo "No archive product — re-seal snapshot $APP"
  IDLINE=$(security find-identity -v -p codesigning "${SIGNING_KEYCHAIN:-}" 2>/dev/null | grep -i Distribution | grep -v CSSMERR | head -n 1 || true)
  if [ -z "$IDLINE" ]; then
    IDLINE=$(security find-identity -v -p codesigning | grep -i Distribution | grep -v CSSMERR | head -n 1 || true)
  fi
  IDHASH=$(printf '%s' "$IDLINE" | awk '{print $2}')
  if [ -z "$IDHASH" ]; then
    echo "No Distribution identity"
    exit 1
  fi
  find "$APP" -type d -name 'Metadata.appintents' -exec rm -rf {} + 2>/dev/null || true
  find "$APP" -maxdepth 1 -name 'AppIcon*.png' -delete 2>/dev/null || true
  for f in "$APP/Assets.car" "$APP/PrivacyInfo.xcprivacy" "$APP/embedded.mobileprovision"; do
    if [ -f "$f" ]; then
      echo "fallback blob-sign $f"
      /usr/bin/codesign --force --sign "$IDHASH" --timestamp=none \
        --identifier "com.crisiskhan.blackout.$(basename "$f")" "$f"
    fi
  done
  ENT=""
  XCENT="$(find "$DD" -name 'Blackout.app.xcent' 2>/dev/null | head -n 1 || true)"
  if [ -n "$XCENT" ] && [ -f "$XCENT" ]; then
    ENT="$XCENT"
    echo "using xcent $ENT"
  elif [ -f "$APP/embedded.mobileprovision" ]; then
    ENT="$RUNNER_TEMP/ent-main.plist"
    "$PYBIN" - "$APP/embedded.mobileprovision" "$ENT" << 'PY'
import plistlib, subprocess, sys
from pathlib import Path
raw = subprocess.check_output(["security", "cms", "-D", "-i", sys.argv[1]], stderr=subprocess.DEVNULL)
pl = plistlib.loads(raw)
Path(sys.argv[2]).write_bytes(plistlib.dumps(pl.get("Entitlements") or {}))
print("wrote", sys.argv[2])
PY
  fi
  if [ -n "$ENT" ] && [ -f "$ENT" ]; then
    /usr/bin/codesign --force --sign "$IDHASH" --entitlements "$ENT" --generate-entitlement-der "$APP"
  else
    /usr/bin/codesign --force --sign "$IDHASH" --generate-entitlement-der "$APP"
  fi
  echo "snapshot re-sealed"
  handzip_ipa "$APP"
else
  echo "Archive failed and no recoverable Blackout.app. No upload."
  exit 1
fi

if [ -z "${IPA:-}" ] || [ ! -f "$IPA" ]; then
  echo "No IPA. No upload."
  exit 1
fi
ls -la "$IPA"
if unzip -l "$IPA" | grep -qiE 'Payload/Blackout\.app/Watch/|\.watchkitapp|BlackoutWatch\.app'; then
  echo "IPA still embeds Watch. altool would require ASC watchkitapp. No upload."
  unzip -l "$IPA" | grep -iE 'Watch/|watchkitapp|BlackoutWatch' || true
  exit 1
fi
echo "IPA has no Watch/ companion (phone Internal only)."
# 33925258357 / 33929367958: altool -19000 on com.maplibre.mapbox, then on
# com.crisiskhan.blackout.maplibre when upload was unbound. 33931992681:
# bound altool then Apple rejected empty FMWK BID. Keep vendor
# com.maplibre.mapbox. Do not strip. Do not rewrite onto an owned BID.
# Inspect Payload before declaring IPA ready. No ASC app for MapLibre.
"$PYBIN" tools/tf_ipa_inspect.py --ipa "$IPA"
VERIFY="$RUNNER_TEMP/ipa-verify"
rm -rf "$VERIFY"
mkdir -p "$VERIFY"
ditto -x -k --norsrc "$IPA" "$VERIFY"
if [ ! -d "$VERIFY/Payload/Blackout.app" ]; then
  echo "IPA verify extract missing Payload/Blackout.app"
  exit 1
fi
if [ -e "$VERIFY/Payload/Blackout.app/Resources" ]; then
  echo "IPA still has reserved Resources after inspect — flatten and re-sign"
  prepare_app_for_upload "$VERIFY/Payload/Blackout.app"
  resign_submission "$VERIFY/Payload/Blackout.app" || {
    echo "Fail closed: reserved Resources remains / re-sign failed"
    exit 1
  }
  ( cd "$VERIFY" && ditto -c -k --norsrc --keepParent Payload Blackout.ipa )
  cp "$VERIFY/Blackout.ipa" "$IPA"
  rm -rf "$VERIFY"
  mkdir -p "$VERIFY"
  ditto -x -k --norsrc "$IPA" "$VERIFY"
fi
if [ -e "$VERIFY/Payload/Blackout.app/Resources" ]; then
  echo "Fail closed: IPA contains reserved Blackout.app/Resources (33931992681)"
  find "$VERIFY/Payload/Blackout.app/Resources" | head -n 40 || true
  exit 1
fi
if ! verify_submission_app "$VERIFY/Payload/Blackout.app"; then
  echo "IPA inspect mutated the payload — re-sign then re-zip"
  resign_submission "$VERIFY/Payload/Blackout.app" || {
    echo "Fail closed: re-sign after inspect failed. No altool."
    exit 1
  }
  if ! verify_submission_app "$VERIFY/Payload/Blackout.app"; then
    echo "Fail closed: re-sign after inspect did not produce submission Authority"
    exit 1
  fi
  ( cd "$VERIFY" && ditto -c -k --norsrc --keepParent Payload Blackout.ipa )
  cp "$VERIFY/Blackout.ipa" "$IPA"
  rm -rf "$VERIFY"
  mkdir -p "$VERIFY"
  ditto -x -k --norsrc "$IPA" "$VERIFY"
fi
/usr/bin/codesign --verify --deep --strict "$VERIFY/Payload/Blackout.app"
echo "codesign --verify --deep --strict OK"
/usr/bin/codesign -d --verbose=4 "$VERIFY/Payload/Blackout.app" > "$RUNNER_TEMP/ipa-codesign-dv.txt" 2>&1 || true
if ! "$PYBIN" tools/tf_archive_signing.py check-submission-authority "$RUNNER_TEMP/ipa-codesign-dv.txt"; then
  echo "Fail closed: Payload/Blackout.app is not signed using an Apple submission certificate"
  exit 1
fi
if ! "$PYBIN" tools/tf_archive_signing.py check-identifier "$RUNNER_TEMP/ipa-codesign-dv.txt" com.crisiskhan.blackout; then
  echo "Fail closed: Payload/Blackout.app codesign Identifier must be com.crisiskhan.blackout"
  exit 1
fi
echo "IPA ready: $IPA"
echo "IPA=$IPA" >> "$GITHUB_ENV"
echo "NEXT_BUILD=$NEXT" >> "$GITHUB_ENV"
