#!/bin/bash
# Stock archive + export only. No strip, xattr, actool, or post-archive bundle rewrite.
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
    "com.crisiskhan.blackout": pmap.get("com.crisiskhan.blackout", "Blackout iOS App Store GHA"),
    "com.crisiskhan.blackout.widgets": pmap.get("com.crisiskhan.blackout.widgets", "Blackout Widgets App Store GHA"),
    "com.crisiskhan.blackout.watchkitapp": pmap.get("com.crisiskhan.blackout.watchkitapp", "Blackout Watch App Store GHA"),
}
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

DD="$RUNNER_TEMP/DerivedData"
rm -rf "$DD" "$ARCHIVE" "$EXPORT"
mkdir -p "$EXPORT"

echo "Stock xcodebuild archive..."
xcodebuild \
  -project Blackout.xcodeproj \
  -scheme Blackout \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$NEXT" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  "${AUTH[@]}" \
  archive 2>&1 | tee "$RUNNER_TEMP/archive.log"

echo "Stock xcodebuild -exportArchive..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$RUNNER_TEMP/ExportOptions.plist" \
  "${AUTH[@]}" \
  2>&1 | tee "$RUNNER_TEMP/export.log"

IPA="$(ls "$EXPORT"/*.ipa 2>/dev/null | head -n 1 || true)"
if [ -z "$IPA" ] || [ ! -f "$IPA" ]; then
  echo "No IPA from exportArchive. No upload."
  exit 1
fi
ls -la "$IPA"
echo "IPA ready: $IPA"
echo "IPA=$IPA" >> "$GITHUB_ENV"
echo "NEXT_BUILD=$NEXT" >> "$GITHUB_ENV"
