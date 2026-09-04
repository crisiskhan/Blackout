#!/bin/bash
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
STOP='ASC API key cannot create or reuse signing certificates. In App Store Connect → Users and Access → Integrations → App Store Connect API, the key’s role must be Admin or Account Holder (not Developer, not App Manager). Account Holder/Admin: edit or replace APP_STORE_CONNECT_API_KEY with an Admin key.'
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
    # app-store (IPA). app-store-connect on a hand-packed archive
    # can mis-detect platform and demand Mac installer certs.
    "method": "app-store",
    "destination": "export",
    "teamID": os.environ["APPLE_TEAM_ID"],
    "uploadSymbols": True,
    "manageAppVersionAndBuildNumber": False,
    "stripSwiftSymbols": True,
}
if profiles and os.environ.get("HAS_LOCAL_DIST_KEY") == "1":
    body["signingStyle"] = "manual"
    # Prefer modern Apple Distribution; iPhone Distribution also accepted.
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
# Per-target Release/Debug: only the 3 native app targets, never SPM packages.
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
    # ExtractAppIntentsMetadata runs AFTER user Run Scripts and recreates
    # Metadata.appintents; codesign then fails (bundle format unrecognized).
    # Do NOT disable AppIntents autolink — BlackoutWidgets uses AppIntent.
    block = sub("ENABLE_APP_INTENTS_METADATA_GENERATION", "NO")
    return block
out = text
for bundle in spec:
    # patch every buildSettings block that contains this PRODUCT_BUNDLE_IDENTIFIER
    pattern = re.compile(
        r"(buildSettings = \{[^{}]*PRODUCT_BUNDLE_IDENTIFIER = " + re.escape(bundle) + r";[^{}]*\})",
        re.S,
    )
    out, n = pattern.subn(lambda m: patch_block(m.group(1), bundle), out)
    print(f"patched {bundle} blocks={n}")
path.write_text(out)
print("CI-only pbxproj signing patch (not committed)")
PY
# Write cleanup script + wire one-liner phase (quoted heredoc).
"$PYBIN" << 'PY'
from pathlib import Path
script = Path("ci_strip_appicon.sh")
script.write_text(
    "#!/bin/sh\n"
    "set -e\n"
    "strip_app() {\n"
    '  APP="$1"\n'
    '  [ -d "$APP" ] || return 0\n'
    '  echo "CI AppIcon strip app=$APP"\n'
    '  find "$APP" -maxdepth 1 -name "AppIcon*.png" -print -delete || true\n'
    '  if [ -d "$APP/Metadata.appintents" ]; then\n'
    '    echo "CI remove unsigned Metadata.appintents"\n'
    '    rm -rf "$APP/Metadata.appintents"\n'
    '  fi\n'
    # Force resources non-executable. SetMode (chmod a+rX) can leave +x on
    # Assets.car / PrivacyInfo / provision; codesign then treats them as nested code.
    '  for f in "$APP/Assets.car" "$APP/PrivacyInfo.xcprivacy" "$APP/embedded.mobileprovision"; do\n'
    '    [ -f "$f" ] && /bin/chmod 644 "$f" || true\n'
    '  done\n'
    '  find "$APP" -type f \\( -name "*.car" -o -name "*.xcprivacy" -o -name "*.mobileprovision" -o -name "*.png" -o -name "*.plist" \\) -exec /bin/chmod 644 {} + 2>/dev/null || true\n'
    '  /usr/bin/xattr -cr "$APP" || true\n'
    "}\n"
    'strip_app "$CODESIGNING_FOLDER_PATH"\n'
    'strip_app "$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"\n'
    'strip_app "$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"\n'
    'if [ -n "$BUILD_DIR" ]; then\n'
    '  find "$BUILD_DIR" -type d -path "*/InstallationBuildProductsLocation/Applications/*.app" 2>/dev/null | while read -r APP; do\n'
    "    strip_app \"$APP\"\n"
    "  done\n"
    "fi\n"
)
script.chmod(0o755)
print("wrote", script.resolve())
path = Path("Blackout.xcodeproj/project.pbxproj")
text = path.read_text()
phase_id = "C1A00001B007000000000001"
note = "CI strip loose AppIcon before CodeSign"
if phase_id in text:
    print("phase already present")
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
        # pbxproj: shellScript = "\"$SRCROOT/ci_strip_appicon.sh\"\n";
        '\t\t\tshellScript = "\\"$SRCROOT/ci_strip_appicon.sh\\"\\n";\n'
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
    print("injected AppIcon cleanup phase")
# sanity: shellScript line must contain escaped quotes
check = path.read_text()
if 'shellScript = "\\"$SRCROOT/ci_strip_appicon.sh\\"\\n";' not in check and 'shellScript = "\\"$SRCROOT/ci_strip_appicon.sh"\\n";' not in check:
    # print nearby for debug
    i = check.find("ci_strip_appicon")
    print("SANITY FAIL nearby:", repr(check[i-40:i+80]))
    raise SystemExit("pbxproj shellScript line malformed")
print("pbxproj shellScript line OK")
PY
/usr/bin/xattr -cr . || true
find . -name '*.png' -exec chmod a-x {} + || true
echo "codesign identities:"
security find-identity -v -p codesigning || true
IDLINE=$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" 2>/dev/null | grep -i Distribution | grep -v "CSSMERR" | head -n 1 || true)
if [ -n "$IDLINE" ]; then
  IDHASH=$(printf '%s' "$IDLINE" | awk '{print $2}')
  IDNAME=$(printf '%s' "$IDLINE" | sed -n 's/.*"\(.*\)"/\1/p')
  echo "Using CODE_SIGN_IDENTITY hash=$IDHASH name=$IDNAME"
  "$PYBIN" - "$IDHASH" << 'PY'
import sys
from pathlib import Path
name = sys.argv[1]
p = Path("Blackout.xcodeproj/project.pbxproj")
t = p.read_text()
t = t.replace('CODE_SIGN_IDENTITY = "iOS Distribution";', f'CODE_SIGN_IDENTITY = "{name}";')
p.write_text(t)
print("rewrote CODE_SIGN_IDENTITY to exact keychain name")
PY
fi
strip_watch() {
  echo "CI-only: strip Embed Watch Content from checkout (not committed) after Watch profile packaging fail"
  "$PYBIN" - << 'PY'
from pathlib import Path
p = Path("Blackout.xcodeproj/project.pbxproj")
text = p.read_text()
old = text
text = text.replace("BlackoutWatch.app in Embed Watch Content", "BlackoutWatch.app in Embed Watch Content DISABLED")
# drop the embed phase file from the resources build phase by commenting the id usage is brittle;
# instead remove the Embed Watch Content PBXCopyFilesBuildPhase block if present.
lines = text.splitlines(True)
out = []
skip = 0
i = 0
while i < len(lines):
    line = lines[i]
    if "Embed Watch Content" in line and "isa = PBXCopyFilesBuildPhase" in "".join(lines[i:i+8]):
        # walk back to the id = { start
        pass
    out.append(line)
    i += 1
# simpler: delete lines that reference the watch embed build file in the main target
text = old
text = text.replace("\t\t\t\t61FBFF9043DC2352CAEDC813 /* BlackoutWatch.app in Embed Watch Content */,\n", "")
if text == old:
    print("Watch embed line not found; pbxproj may have changed")
else:
    p.write_text(text)
    print("Removed Embed Watch Content build file from iOS target (working copy only)")
PY
}
DD="$RUNNER_TEMP/DerivedData"
# /usr/bin codesign is sealed. Xcode toolchain under /Applications is writable on GHA.
# No-op appintentsmetadataprocessor so Metadata.appintents is never written (Crisis-approved
# ephemeral runner-only fix). Restore on EXIT.
XCTool="/Applications/Xcode_16.2.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
for tool in appintentsmetadataprocessor appintentsnltrainingprocessor; do
  SRC="$XCTool/$tool"
  if [ -x "$SRC" ] && [ ! -e "$SRC.blackout-real" ]; then
    sudo mv "$SRC" "$SRC.blackout-real"
    # YAML-safe: base64 no-op stub
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

# Busy-poll chmod after SetMode a+rX until CodeSign finishes.
ARCH_ROOT="$DD/Build/Intermediates.noindex/ArchiveIntermediates/Blackout"
JANITOR_LOG="$RUNNER_TEMP/chmod-janitor.log"
: > "$JANITOR_LOG"
(
  while true; do
    APP="$ARCH_ROOT/InstallationBuildProductsLocation/Applications/Blackout.app"
    if [ -d "$APP" ]; then
      for f in Assets.car PrivacyInfo.xcprivacy embedded.mobileprovision; do
        if [ -f "$APP/$f" ] && [ -x "$APP/$f" ]; then
          echo "$(date -u +%H:%M:%S) chmod644 $f" >> "$JANITOR_LOG"
          /bin/chmod 644 "$APP/$f" || true
        fi
      done
      find "$APP" -type f \( -name '*.car' -o -name '*.xcprivacy' -o -name '*.mobileprovision' -o -name '*.png' \) -perm +111 -exec chmod 644 {} + 2>/dev/null || true
    fi
  done
) &
JANITOR_PID=$!
stop_janitor() {
  kill "$JANITOR_PID" 2>/dev/null || true
  wait "$JANITOR_PID" 2>/dev/null || true
  echo "chmod janitor log:"
  tail -40 "$JANITOR_LOG" || true
  restore_intent_tools
}
trap stop_janitor EXIT

set +e
rm -rf "$DD" "$ARCHIVE"
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
  ENABLE_APP_INTENTS_METADATA_GENERATION=NO \
  "${AUTH[@]}" \
  archive 2>&1 | tee "$RUNNER_TEMP/archive.log"
echo "${PIPESTATUS[0]}" > "$RUNNER_TEMP/archive.exit"
set -e
ARC="$(cat "$RUNNER_TEMP/archive.exit")"
echo "archive exit=$ARC"

IPA=""
if [ "$ARC" -eq 0 ] && [ -d "$ARCHIVE/Products/Applications/Blackout.app" ]; then
  echo "Archive OK — exportArchive"
  APP="$ARCHIVE/Products/Applications/Blackout.app"
  ASSETS_SRC="$(find . -type d -name Assets.xcassets | head -n 1 || true)"
  if [ -n "$ASSETS_SRC" ] && [ -d "$ASSETS_SRC" ]; then
    echo "actool compile from $ASSETS_SRC"
    xcrun actool "$ASSETS_SRC" \
      --compile "$APP" \
      --platform iphoneos \
      --minimum-deployment-target 18.0 \
      --app-icon AppIcon \
      --output-partial-info-plist "$RUNNER_TEMP/actool-partial.plist" \
      --compress-pngs \
      2>&1 | tee "$RUNNER_TEMP/actool.log" || true
    chmod 644 "$APP/Assets.car" 2>/dev/null || true
    /usr/bin/xattr -cr "$APP/Assets.car" 2>/dev/null || true
    # Re-seal main after adding Assets.car
    IDLINE=$(security find-identity -v -p codesigning "${SIGNING_KEYCHAIN:-}" 2>/dev/null | grep -i Distribution | grep -v CSSMERR | head -n 1 || true)
    IDHASH=$(printf '%s' "$IDLINE" | awk '{print $2}')
    XCENT="$(find "$DD" -name 'Blackout.app.xcent' 2>/dev/null | head -n 1 || true)"
    if [ -n "$IDHASH" ] && [ -n "$XCENT" ] && [ -f "$APP/Assets.car" ]; then
      echo "re-seal after actool with $IDHASH"
      /usr/bin/codesign --force --sign "$IDHASH" --entitlements "$XCENT" --generate-entitlement-der "$APP"
    fi
  else
    echo "WARNING: no Assets.xcassets found; IPA may lack App Icon"
  fi
  rm -rf "$EXPORT"
  mkdir -p "$EXPORT"
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
  if [ "$EX" -eq 0 ]; then
    IPA="$(ls "$EXPORT"/*.ipa 2>/dev/null | head -n 1 || true)"
  else
    echo "exportArchive exit=$EX — hand-zip from archive Products"
  fi
  if [ -z "$IPA" ] || [ ! -f "$IPA" ]; then
    APP="$ARCHIVE/Products/Applications/Blackout.app"
    rm -rf "$EXPORT"
    mkdir -p "$EXPORT/Payload"
    cp -a "$APP" "$EXPORT/Payload/Blackout.app"
    ( cd "$EXPORT" && zip -r -y -q Blackout.ipa Payload )
    IPA="$EXPORT/Blackout.ipa"
  fi
else
  # Fallback: recover InstallationBuildProductsLocation, strip, re-seal main only
  APP=""
  if [ -d "$ARCHIVE/Products/Applications/Blackout.app" ]; then
    APP="$ARCHIVE/Products/Applications/Blackout.app"
  else
    APP="$(find "$DD" -type d -path '*/InstallationBuildProductsLocation/Applications/Blackout.app' 2>/dev/null | head -n 1 || true)"
  fi
  if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "Archive failed and no recoverable Blackout.app. No upload."
    exit 1
  fi
  echo "Recovered app at $APP (archive exit=$ARC) — fallback re-seal"
  IDLINE=$(security find-identity -v -p codesigning "${SIGNING_KEYCHAIN:-}" 2>/dev/null | grep -i Distribution | grep -v CSSMERR | head -n 1 || true)
  if [ -z "$IDLINE" ]; then
    IDLINE=$(security find-identity -v -p codesigning | grep -i Distribution | grep -v CSSMERR | head -n 1 || true)
  fi
  IDHASH=$(printf '%s' "$IDLINE" | awk '{print $2}')
  if [ -z "$IDHASH" ]; then
    echo "No Distribution identity"
    exit 1
  fi
  echo "Re-seal nested + main with $IDHASH"
  IDHASH="$IDHASH" DD="$DD" APP="$APP" "$PYBIN" << 'PY'
import os, subprocess, plistlib, sys
from pathlib import Path

app = Path(os.environ["APP"])
dd = Path(os.environ["DD"])
idhash = os.environ["IDHASH"]
tmp = Path(os.environ["RUNNER_TEMP"])

def run(cmd):
    print("+", " ".join(cmd))
    subprocess.check_call(cmd)

# Strip killers
for p in app.rglob("Metadata.appintents"):
    if p.is_dir():
        print("rm", p)
        subprocess.call(["rm", "-rf", str(p)])
for p in app.glob("AppIcon*.png"):
    print("rm", p)
    p.unlink(missing_ok=True)

# Non-code resources must not be executable (codesign treats +x as nested code)
for pat in ("*.xcprivacy", "*.car", "*.png", "*.plist", "*.json", "*.strings", "*.nib", "*.storyboardc"):
    for p in app.rglob(pat):
        if p.is_file():
            p.chmod(0o644)
subprocess.call(["/usr/bin/xattr", "-cr", str(app)])

# Ensure main + nested binaries stay executable
for rel in ("Blackout",):
    b = app / rel
    if b.is_file():
        b.chmod(0o755)
for appex in app.rglob("*.appex"):
    for cand in appex.iterdir():
        if cand.is_file() and cand.suffix == "" and cand.name != "embedded.mobileprovision":
            # heuristic: Mach-O next to Info.plist
            pass
    # named executable usually matches appex stem
    exe = appex / appex.stem
    if exe.is_file():
        exe.chmod(0o755)
for fw in app.rglob("*.framework"):
    exe = fw / fw.stem
    if exe.is_file():
        exe.chmod(0o755)

def ents_from_provision(prov: Path, out: Path):
    raw = subprocess.check_output(["security", "cms", "-D", "-i", str(prov)], stderr=subprocess.DEVNULL)
    pl = plistlib.loads(raw)
    out.write_bytes(plistlib.dumps(pl.get("Entitlements") or {}))
    return out

def ensure_provision(bundle: Path, bundle_id: str):
    prov = bundle / "embedded.mobileprovision"
    if prov.exists():
        return prov
    home = Path.home()
    for d in (
        home / "Library/Developer/Xcode/UserData/Provisioning Profiles",
        home / "Library/MobileDevice/Provisioning Profiles",
    ):
        if not d.exists():
            continue
        for p in d.glob("*.mobileprovision"):
            try:
                raw = subprocess.check_output(["security", "cms", "-D", "-i", str(p)], stderr=subprocess.DEVNULL)
                pl = plistlib.loads(raw)
            except Exception:
                continue
            ents = pl.get("Entitlements") or {}
            appid = ents.get("application-identifier") or ""
            bid = appid.split(".", 1)[-1] if "." in appid else ""
            if bid == bundle_id:
                prov.write_bytes(p.read_bytes())
                print(f"embedded {bundle_id} from {p.name}")
                return prov
    return prov

# Prefer Xcode-generated xcent for main when present
xcent = None
for cand in dd.rglob("Blackout.app.xcent"):
    xcent = cand
    break

# Re-sign nested deepest-first (Metadata strip invalidated their seals)
nested = sorted(
    list(app.rglob("*.appex")) + list(app.rglob("*.framework")) + list(app.rglob("*.app")),
    key=lambda p: len(p.parts),
    reverse=True,
)
# exclude the main app itself from nested list
nested = [p for p in nested if p.resolve() != app.resolve()]
for bundle in nested:
    # strip nest metadata again
    md = bundle / "Metadata.appintents"
    if md.exists():
        subprocess.call(["rm", "-rf", str(md)])
    if bundle.suffix == ".framework":
        run([
            "/usr/bin/codesign", "--force", "--sign", idhash,
            "--preserve-metadata=identifier,entitlements,flags",
            "--generate-entitlement-der", str(bundle),
        ])
    else:
        # appex / watch app
        bid = {
            ".appex": "com.crisiskhan.blackout.widgets",
            ".app": "com.crisiskhan.blackout.watchkitapp",
        }.get(bundle.suffix, "")
        if bundle.suffix == ".app" and "watch" not in bundle.name.lower() and bundle.name != "BlackoutWatch.app":
            continue
        prov = ensure_provision(bundle, bid) if bid else None
        cmd = ["/usr/bin/codesign", "--force", "--sign", idhash, "--generate-entitlement-der", str(bundle)]
        if prov and prov.exists():
            ent = tmp / f"ent-{bundle.name}.plist"
            ents_from_provision(prov, ent)
            cmd = ["/usr/bin/codesign", "--force", "--sign", idhash, "--entitlements", str(ent), "--generate-entitlement-der", str(bundle)]
        run(cmd)

ensure_provision(app, "com.crisiskhan.blackout")
if xcent and xcent.exists():
    ent = xcent
    print("using xcent", xcent)
else:
    ent = tmp / "ent-main.plist"
    ents_from_provision(app / "embedded.mobileprovision", ent)
    print("wrote", ent)

rm_sig = app / "_CodeSignature"
if rm_sig.exists():
    subprocess.call(["rm", "-rf", str(rm_sig)])

def sign_main():
    run([
        "/usr/bin/codesign", "--force", "--sign", idhash,
        "--entitlements", str(ent),
        "--generate-entitlement-der",
        str(app),
    ])

try:
    sign_main()
except subprocess.CalledProcessError:
    car = app / "Assets.car"
    if car.exists():
        print("main sign failed; moving Assets.car aside and retrying")
        bak = Path(os.environ["RUNNER_TEMP"]) / "Assets.car.bak"
        car.replace(bak)
        sign_main()
        # restore via actool if possible
        assets = None
        for cand in Path(".").rglob("Assets.xcassets"):
            assets = cand
            break
        if assets and assets.is_dir():
            subprocess.call([
                "xcrun", "actool", str(assets),
                "--compile", str(app),
                "--platform", "iphoneos",
                "--minimum-deployment-target", "18.0",
                "--app-icon", "AppIcon",
                "--output-partial-info-plist", str(Path(os.environ["RUNNER_TEMP"]) / "actool-partial.plist"),
                "--compress-pngs",
            ])
            if (app / "Assets.car").exists():
                (app / "Assets.car").chmod(0o644)
                subprocess.call(["/usr/bin/xattr", "-cr", str(app / "Assets.car")])
                sign_main()
        elif bak.exists():
            print("WARNING: shipping without Assets.car")
    else:
        raise
print("main app re-sealed")
PY
  rm -rf "$EXPORT"
  mkdir -p "$EXPORT/Payload"
  cp -a "$APP" "$EXPORT/Payload/Blackout.app"
  ( cd "$EXPORT" && zip -r -y -q Blackout.ipa Payload )
  IPA="$EXPORT/Blackout.ipa"
fi

ls -la "$IPA"
echo "IPA ready: $IPA"
if [ ! -f "$IPA" ]; then
  echo "No IPA. No upload."
  exit 1
fi
echo "IPA=$IPA" >> "$GITHUB_ENV"
echo "NEXT_BUILD=$NEXT" >> "$GITHUB_ENV"
