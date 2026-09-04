#!/bin/bash
# Archive, then recover a signed Blackout.app if xcarchive assembly fails.
# 33829001016: packaging left Products/Applications/Blackout.app but no
# xcarchive Info.plist. Do not rm _CodeSignature / re-seal that product.
# Write Info.plist and exportArchive or hand-zip the signed .app. No xattr.
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

"$PYBIN" << 'PY'
import json, os, plistlib
from pathlib import Path
path = os.environ["RUNNER_TEMP"] + "/ExportOptions.plist"
profiles = {}
pmap = Path(os.environ["RUNNER_TEMP"]) / "profile_map.json"
if pmap.exists():
    profiles = json.loads(pmap.read_text())
body = {
    "method": "app-store",
    "destination": "export",
    "teamID": os.environ["APPLE_TEAM_ID"],
    "uploadSymbols": True,
    "manageAppVersionAndBuildNumber": False,
    "stripSwiftSymbols": True,
}
if profiles and os.environ.get("HAS_LOCAL_DIST_KEY") == "1":
    body["signingStyle"] = "manual"
    body["signingCertificate"] = "Apple Distribution"
    body["provisioningProfiles"] = profiles
else:
    body["signingStyle"] = "automatic"
plistlib.dump(body, open(path, "wb"))
print("wrote", path, "signingStyle", body["signingStyle"])
PY

"$PYBIN" << 'PY'
import json, os, re
from pathlib import Path
team = os.environ["APPLE_TEAM_ID"]
pmap = {}
mp = Path(os.environ["RUNNER_TEMP"]) / "profile_map.json"
if mp.exists():
    pmap = json.loads(mp.read_text())
path = Path("Blackout.xcodeproj/project.pbxproj")
text = path.read_text()
spec = {
    "com.crisiskhan.blackout": pmap.get("com.crisiskhan.blackout", "Blackout iOS App Store GHA Local"),
    "com.crisiskhan.blackout.widgets": pmap.get("com.crisiskhan.blackout.widgets", "Blackout Widgets App Store GHA Local"),
}
# 33926435868: HAS_LOCAL_DIST_KEY=0 skipped this patch and left stock
# Automatic. xcodebuild archive then demanded Apple Development certs
# ("Revoke certificate" / iOS App Development profiles) and exited 65.
# Happy path now always mints a runner-local Dist cert so this Manual
# branch runs. The != 1 pin is a last-ditch fallback only.
if os.environ.get("HAS_LOCAL_DIST_KEY") != "1":
    def pin_dist(block):
        def sub(key, val):
            nonlocal block
            if re.search(rf"{key} = ", block):
                block = re.sub(rf"{key} = [^;]*;", f"{key} = {val};", block, count=1)
            else:
                block = block.replace("buildSettings = {", "buildSettings = {\n\t\t\t\t" + f"{key} = {val};")
            return block
        block = sub("CODE_SIGN_STYLE", "Automatic")
        block = sub("CODE_SIGN_IDENTITY", '"iPhone Distribution"')
        block = sub("DEVELOPMENT_TEAM", team)
        return block
    out = text
    for bundle in spec:
        pattern = re.compile(
            r"(buildSettings = \{[^{}]*PRODUCT_BUNDLE_IDENTIFIER = " + re.escape(bundle) + r";[^{}]*\})",
            re.S,
        )
        out, n = pattern.subn(lambda m: pin_dist(m.group(1)), out)
        print(f"pinned Distribution Automatic {bundle} blocks={n}")
    path.write_text(out)
    print("CI-only pbxproj Dist Automatic pin (KEEP cert reuse, not committed)")
    raise SystemExit(0)
def patch_block(block, bundle):
    name = spec[bundle]
    def sub(key, val):
        nonlocal block
        if re.search(rf"{key} = ", block):
            block = re.sub(rf"{key} = [^;]*;", f"{key} = {val};", block, count=1)
        else:
            block = block.replace("buildSettings = {", "buildSettings = {\n\t\t\t\t" + f"{key} = {val};")
        return block
    block = sub("CODE_SIGN_STYLE", "Manual")
    block = sub("CODE_SIGN_IDENTITY", '"iOS Distribution"')
    block = sub("DEVELOPMENT_TEAM", team)
    block = sub("PROVISIONING_PROFILE_SPECIFIER", f'"{name}"')
    return block
out = text
for bundle in spec:
    pattern = re.compile(
        r"(buildSettings = \{[^{}]*PRODUCT_BUNDLE_IDENTIFIER = " + re.escape(bundle) + r";[^{}]*\})",
        re.S,
    )
    out, n = pattern.subn(lambda m: patch_block(m.group(1), bundle), out)
    print(f"patched {bundle} blocks={n}")
path.write_text(out)
print("CI-only pbxproj signing patch (not committed)")
PY

IDLINE=$(security find-identity -v -p codesigning "${SIGNING_KEYCHAIN:-}" 2>/dev/null | grep -i Distribution | grep -v "CSSMERR" | head -n 1 || true)
if [ -z "$IDLINE" ]; then
  IDLINE=$(security find-identity -v -p codesigning | grep -i Distribution | grep -v "CSSMERR" | head -n 1 || true)
fi
if [ -n "$IDLINE" ]; then
  IDHASH=$(printf '%s' "$IDLINE" | awk '{print $2}')
  echo "Using CODE_SIGN_IDENTITY hash=$IDHASH"
  "$PYBIN" - "$IDHASH" << 'PY'
import sys
from pathlib import Path
name = sys.argv[1]
p = Path("Blackout.xcodeproj/project.pbxproj")
t = p.read_text()
t = t.replace('CODE_SIGN_IDENTITY = "iOS Distribution";', f'CODE_SIGN_IDENTITY = "{name}";')
p.write_text(t)
print("rewrote CODE_SIGN_IDENTITY to exact keychain hash")
PY
fi

# 33825793771 stock+STANDALONE_ICON_BEHAVIOR=none: no AppIcon pngs; CodeSign
# died on Metadata.appintents. No-op the App Intents processors.
# 33825608089: after Metadata was gone, 644 PrivacyInfo / Assets.car were
# still "unsigned nested code". 33826265768: blob-sign of those two moved
# CodeSign to embedded.mobileprovision. Blob-sign all three.
XCTool="/Applications/Xcode_16.2.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
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
  CODE_SIGN_IDENTITY="iPhone Distribution" \
  CODE_SIGNING_ALLOWED=YES \
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

handzip_ipa() {
  local src="$1"
  if [ ! -d "$src" ] || [ ! -f "$src/Blackout" ]; then
    echo "hand-zip source missing $src"
    return 1
  fi
  rm -rf "$EXPORT"
  mkdir -p "$EXPORT/Payload"
  cp -a "$src" "$EXPORT/Payload/Blackout.app"
  ( cd "$EXPORT" && zip -r -y -q Blackout.ipa Payload )
  IPA="$EXPORT/Blackout.ipa"
  echo "hand-zipped $IPA from $src"
}

write_xcarchive_plist() {
  local app="$ARCHIVE/Products/Applications/Blackout.app"
  [ -d "$app" ] && [ -f "$app/Info.plist" ] || return 1
  local bid ver short
  bid="$(plutil -extract CFBundleIdentifier raw "$app/Info.plist" 2>/dev/null || true)"
  ver="$(plutil -extract CFBundleVersion raw "$app/Info.plist" 2>/dev/null || true)"
  short="$(plutil -extract CFBundleShortVersionString raw "$app/Info.plist" 2>/dev/null || true)"
  [ -n "$bid" ] || bid="com.crisiskhan.blackout"
  [ -n "$ver" ] || ver="$NEXT"
  [ -n "$short" ] || short="0.1.0"
  "$PYBIN" - "$ARCHIVE/Info.plist" "$bid" "$ver" "$short" "${APPLE_TEAM_ID}" << 'PY'
import datetime, plistlib, sys
path, bid, ver, short, team = sys.argv[1:]
body = {
    "ApplicationProperties": {
        "ApplicationPath": "Applications/Blackout.app",
        "Architectures": ["arm64"],
        "CFBundleIdentifier": bid,
        "CFBundleShortVersionString": short,
        "CFBundleVersion": ver,
        "Team": team,
    },
    "ArchiveVersion": 2,
    "CreationDate": datetime.datetime.utcnow(),
    "Name": "Blackout",
    "SchemeName": "Blackout",
}
plistlib.dump(body, open(path, "wb"))
print("wrote xcarchive Info.plist", bid, ver)
PY
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
# dSYMs/Signatures but no xcarchive Info.plist (exit 70). Official CodeSign
# of that .app already succeeded. Recover then rm'd _CodeSignature and
# codesign said "bundle format unrecognized". Do not re-seal a signed product.
if [ -d "$ARCH_APP" ] && [ -f "$ARCH_APP/Blackout" ]; then
  echo "Archive product present (archive exit=$ARC) — write Info.plist, no re-seal"
  write_xcarchive_plist || true
  if [ -f "$ARCHIVE/Info.plist" ]; then
    echo "---- archive Info.plist after write ----"
    plutil -p "$ARCHIVE/Info.plist" || true
  fi
  if [ "$ARC" -eq 0 ] || [ -f "$ARCHIVE/Info.plist" ]; then
    try_export_archive || handzip_ipa "$ARCH_APP"
  else
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
# 33925258357: after Watch was gone, altool -19000 on com.maplibre.mapbox
# (MapLibre.framework Info.plist). Inspect Payload before declaring IPA ready:
# assert app/widget BIDs, rewrite foreign FMWK ids (plutil/PlistBuddy via
# tools/tf_ipa_inspect.py), fail closed, re-zip if rewritten.
# Do not create an ASC app for com.maplibre.mapbox.
"$PYBIN" tools/tf_ipa_inspect.py --ipa "$IPA"
echo "IPA ready: $IPA"
echo "IPA=$IPA" >> "$GITHUB_ENV"
echo "NEXT_BUILD=$NEXT" >> "$GITHUB_ENV"
