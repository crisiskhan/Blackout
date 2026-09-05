# TESTFLIGHT — GitHub Actions Internal (no p12)

Primary install path is `.github/workflows/testflight-internal.yml`, not Xcode Cloud.

Crisis: iPhone 12 Pro Max. Safari. No Mac. No Xcode. No p12.

## Facts

- App Blackout / CKBlackout, bundle `com.crisiskhan.blackout`, ASC `6806388963`
- Repo `crisiskhan/Blackout`
- App tree this job archives: `cursor/blackout-bible-v3-64d0` (never the old app on `main`)
- Destination: TestFlight Internal only (`28035586-fce6-474f-9bc2-ef0f1f65306e`). No App Review. No External Testing.
- Repo CPV is 1 and collides; the job sets `CURRENT_PROJECT_VERSION` on the xcodebuild command line (max ASC + 1). It does not commit a bump.
- A 50-series TestFlight build is the old vessel.
- Signing: existing ASC AuthKey + automatic signing. No human certificate export.
- Unsigned compile stays **macos-14 + Xcode 16** (`.github/workflows/xcodebuild.yml`). TestFlight archive is **macos-15 + Xcode 26** for the iOS 26 SDK (`33931992681`). Do not use `macos-latest`. Keep App Intents processor no-ops on the selected toolchain.
- Do not `xattr -cr` the `.app` or the repo. Do not `rm`/`ditto`/`chmod 644` `Assets.car`, `PrivacyInfo.xcprivacy`, or `embedded.mobileprovision`. Do not run a chmod janitor during archive. Codesign then reports `code object is not signed at all` on the next data file.
- `STANDALONE_ICON_BEHAVIOR=none` is required: stock `33825215841` failed on loose `AppIcon60x60@2x.png`; `33825793771` with that setting did not.
- After AppIcons are gone, stock CodeSign fails on `Metadata.appintents` (`33825793771`). Keep the App Intents processor no-ops.
- After Metadata is gone, 644 `PrivacyInfo.xcprivacy` / `Assets.car` still fail as unsigned nested code (`33825608089`). Blob-sign those files. `33826265768` then failed on `embedded.mobileprovision` — blob-sign that too. Do not `xattr -cr`.
- `33827851150` (`23a7d04`): blob-sign of all three + official CodeSign of `Blackout.app` succeeded. `xcodebuild archive` then failed `Archive Missing Bundle Identifier` (exit 70) and tore down `InstallationBuildProductsLocation`. `BuildProductsPath/Release-iphoneos/Blackout.app` is only a symlink to that same path, so post-archive recover found nothing.
- FACT (33827851150): `ProcessInfoPlistFile` ran `builtin-infoPlistUtility` on `Blackout/Info.plist` + `assetcatalog_generated_info.plist` only. Source plist was `NSBonjourServices` only. `PRODUCT_BUNDLE_IDENTIFIER=com.crisiskhan.blackout` and `GENERATE_INFOPLIST_FILE=YES` were in the env. CodeSign + Validate + Touch succeeded; IDE archive packaging then exited 70.
- INFERENCE revised by `33829001016`: the processed iOS `.app` **had** `CFBundleIdentifier=com.crisiskhan.blackout`. Archive packaging still failed to write the xcarchive-root `Info.plist` `ApplicationProperties` (Products/dSYMs/Signatures present, archive Info.plist absent). The missing-identifier error is the IDE archive wrapper, not an empty iOS app plist.
- FACT (`33829001016` `ProcessInfoPlistFile`): `GENERATE_INFOPLIST_FILE=YES` did **not** pass a generated Info.plist into `builtin-infoPlistUtility`. Watch (`product-type.application`) and Widgets were processed from their source plists only. Watch source had `WKWatchOnly` + companion id — **no `CFBundleIdentifier`**. Widget source had NSExtension only — **no `CFBundleIdentifier`**. Main app `PRODUCT_BUNDLE_IDENTIFIER=com.crisiskhan.blackout` / `SKIP_INSTALL=NO` were already in the env.
- Project fix: every archived product Info.plist now carries `CFBundleIdentifier=$(PRODUCT_BUNDLE_IDENTIFIER)` plus the packaging keys ProcessInfoPlistFile actually copies (executable / package type / versions). Main target sets `SKIP_INSTALL=NO` and `INSTALL_PATH=$(LOCAL_APPS_DIR)` explicitly. Prefer stock `xcodebuild archive` + `exportArchive`. Do not delete `PrivacyInfo` / `Assets.car` / AppIcons.
- `33829001016` (`43f13b9`): processed iOS `CFBundleIdentifier=com.crisiskhan.blackout` / version 54. Snapshot ran. Archive packaging still exited 70, but left `Blackout.xcarchive/Products/Applications/Blackout.app` + dSYMs + Signatures and **no** xcarchive `Info.plist`. Recover overwrote the snapshot with that already-signed product, `rm -rf _CodeSignature`, then `codesign` reported `bundle format unrecognized`. Do not re-seal a signed archive product. CI may still write a missing xcarchive `Info.plist` and `exportArchive` or hand-zip if packaging fails; the project fix is Watch/Widget identifiers so stock archive can write ApplicationProperties.
- `33907781589`: archive + IPA succeeded (inject CFBundleVersion 54). `altool` upload failed −19000 — no ASC application record for `com.crisiskhan.blackout.watchkitapp`. Crisis cut: **Watch is omitted from the App Store / TestFlight archive** so phone Internal can land. Widget stays embedded. The `BlackoutWatch` target and `BlackoutWatch.xcscheme` remain in the project for later.
- `33925258357` (`4456206`): KEEP Dist cert reuse + Watch omitted. Hand-zip IPA ready. `altool` −19000 on **`com.maplibre.mapbox`** (MapLibre.framework Info.plist). Do not create an ASC app for MapLibre.
- `33929367958` (`0e3d31d`): signing + archive + IPA succeeded (Local Dist `FG5MXH5347`, CPV 54). `altool` −19000 on **`com.crisiskhan.blackout.maplibre`**. Upload had no `--apple-id` / `--bundle-id`, so altool picked the nested FMWK BID. Bind upload to ASC `6806388963` + `com.crisiskhan.blackout`. Do **not** rewrite nested FMWK onto `com.crisiskhan.blackout.*`. Strip FMWK `CFBundleIdentifier` (keep `CFBundlePackageType=FMWK`) or leave a foreign vendor id. Still do not create an ASC app for MapLibre.
- Archive exit 70 `Archive Missing Bundle Identifier` after the main app plist already had `com.crisiskhan.blackout`: the extra archived product was the **Vendor/MapLibre xcframework** linked beside `MapLibreMap`. That XFWK wrapper Info.plist has `CFBundlePackageType=XFWK` and **no** `CFBundleIdentifier`. App/widget source plists already carry `CFBundleIdentifier=$(PRODUCT_BUNDLE_IDENTIFIER)`. Watch stays omitted from the App Store archive.
- App target now links **MapLibreMap only** (MapLibreMap already depends on the vendor binary). `tf-archive.sh` runs `tools/tf_ipa_inspect.py` after the IPA exists: assert app/widget BIDs, require nested FMWK `CFBundleIdentifier=com.maplibre.mapbox` (do not strip; do not rewrite onto owned), fail closed on foreign `Payload/*.app` / `PlugIns/*.appex`. Upload uses `xcrun altool --upload-package` with `--apple-id "$ASC_APP_ID"` `--bundle-id com.crisiskhan.blackout` `--bundle-version` `--bundle-short-version-string`.
- `33926435868` (`e096955`): KEEP reuse, `HAS_LOCAL_DIST_KEY=0`, no Manual patch. `xcodebuild archive` then asked for **Apple Development** certs/profiles (`Revoke certificate` / no iOS App Development profiles) and exited 65 — no IPA. Fix: even when KEEP Dist `45YLWHL6UP` exists, mint a **runner-local Dist cert** (`HAS_LOCAL_DIST_KEY=1`) and bind Local-named App Store profiles (`Blackout iOS App Store GHA Local` / `Blackout Widgets App Store GHA Local`) to that cert. Leave KEEP-named ACTIVE profiles alone. Never revoke KEEP. If Dist create hits Apple’s cap, fail closed (do not auto-revoke KEEP). Optional: revoke only `IOS_DEVELOPMENT` / `DEVELOPMENT` certs named `Created via API` that block AuthKey.
- `33927056130` (`ce331dd`): mint worked (`HAS_LOCAL_DIST_KEY=1`). Archive still exit 65 because CLI `CODE_SIGN_IDENTITY="iPhone Distribution"` applied to **every** target, including SPM packages (`VisionCoreML`, `Tokens`, `MapLibreMap`) that stay Automatic: “automatically signed for development, but a conflicting code signing identity iPhone Distribution has been manually specified.” Do **not** pass `CODE_SIGN_IDENTITY` on the `xcodebuild archive` or `exportArchive` command line. Keep the per-target CI pbx patch (Manual + Dist identity + Local profile) on app/widget only. The patch and keychain-hash rewrite share one placeholder (`iPhone Distribution`) so the rewrite cannot miss (`iOS Distribution` / `Apple Distribution` aliases also rewrite).
- `33928044175` (`6e1e411`): mint created Dist `YVK8HM9GT2` (IOS_DISTRIBUTION was HTTP 409 — Apple already had `2LWNR93SGQ` + KEEP `45YLWHL6UP`). Archive never ran: ACTIVE Local profile `Blackout iOS App Store GHA Local` was still bound to the previous mint. Each runner is ephemeral, so the next flight must (1) revoke stale **non-KEEP** Dist leftovers so the cap has a slot, (2) replace Local-named profiles onto the new local Dist, including INVALID leftovers after that Dist revoke. Never revoke KEEP. Never delete KEEP-named profiles (`Blackout iOS App Store GHA` / `Blackout Widgets App Store GHA`).
- `33930228429` (`31fcfe5`): Dist prune + iOS Local replace succeeded (`KR7N96LT42`). Widget Local CREATE then ASC HTTP 500 `UNEXPECTED_ERROR`. Dist revoke leaves the previous Local profile `INVALID`; an ACTIVE-only list misses it so CREATE collides. List `ACTIVE,INVALID`. Retry Local-named CREATE/replace-recreate on 500/UNEXPECTED_ERROR (5 attempts, backoff 15s/30s/60s/90s/120s, re-list between attempts). Cool down ~25s after an iOS Local write before Widgets Local create/replace. Never delete KEEP-named profiles.
- `33931034850` (`f4ba3af`): signing + archive + hand-zip IPA succeeded (Local Dist `FQK7KQDXGP`, CPV 54, inspect no FMWK rewrite). altool bound the primary app, then 409: `Payload/Blackout.app` is not signed using an Apple submission certificate. ExportOptions asked for Apple Distribution while the keychain identity was `iPhone Distribution`; exportArchive looked for `3rd Party Mac Developer Installer` (`Bundle identifier is missing`). Write ExportOptions `signingCertificate` from `security find-identity` (iPhone / Apple / iOS Distribution). Fill xcarchive ApplicationProperties BID/versions/Team before exportArchive (`app-store`, no Mac installer). Hand-zip re-signs nested code if Authority is not a submission Dist identity, then fail-closed — do not hand altool a rejected IPA.
- `33931992681` (`d86628c`): Apple Distribution mint `VN8S62458Z`, ExportOptions `Apple Distribution`, archive product already had submission Authority, ditto hand-zip, `codesign --verify` OK. altool bound the primary app (no −19000). Then 409: reserved `Blackout.app/Resources` (`ditto --sequesterRsrc` **and** the Xcode copy of repo `Resources/` into the `.app`); MapLibre `CFBundleIdentifier ''` / Identifier `MapLibre` vs `$bundleIdentifier`; iOS 18.2 SDK not accepted (need iOS 26 SDK / Xcode 26). Keep vendor `com.maplibre.mapbox` (not an owned ASC invent). Hand-zip `ditto --norsrc`. Flatten repo Packs/Field/Vision into the `.app` root (no reserved `Resources/` directory); IPA inspect + hand-zip fail-closed if it remains, then re-sign. codesign `--identifier` must equal app/widget/FMWK BID. TF runner **macos-15 + Xcode 26**; unsigned compile stays **macos-14 + Xcode 16**. CoS must copy the yml to `main` (runs-on lives there). No MapLibre ASC app. KEEP Dist `45YLWHL6UP` untouched.
- `33986112949` (`3ae500a`): archive + altool OK, CPV **56** `VALID`, PATCH 200, then `ASSIGN Internal 56 404` (`NOT_FOUND` on that build id). Build is on ASC; Internal group attach raced. Retry betaGroups 404 (15s/30s/60s/90s/120s). 409 stays success (already assigned). CoS must copy the yml so the assign step calls `tools/tf_asc_assign.py`.

## Watch omitted from App Store archive (re-enable later)

Scheme **Blackout** (what GHA archives) does **not** embed `BlackoutWatch.app`. There is no Embed Watch Content phase and no Blackout → BlackoutWatch target dependency. The exported IPA must not contain `Payload/Blackout.app/Watch/` or a `.watchkitapp`. `tf-archive.sh` fails closed if it does.

Do **not** create an ASC Watch companion app just to unblock phone Internal.

To put Watch back in the uploaded iOS IPA (only after ASC has a companion record for `com.crisiskhan.blackout.watchkitapp`):

1. In `Blackout.xcodeproj/project.pbxproj` (and `tools/v3/generate_project.py` so regen matches): restore **Embed Watch Content** (`dstPath = $(CONTENTS_FOLDER_PATH)/Watch`, copy `BlackoutWatch.app`) on the Blackout target, and restore the Blackout → BlackoutWatch `PBXTargetDependency`.
2. Add `com.crisiskhan.blackout.watchkitapp` back to `BUNDLES` in `tools/tf_asc_reuse.py` (platform `WATCHOS`, not `IOS`) and to the signing `spec` in `.github/ci/tf-archive.sh`.
3. Keep Watch `CFBundleIdentifier=$(PRODUCT_BUNDLE_IDENTIFIER)` in `BlackoutWatch/Info.plist`.
4. Confirm the IPA listing includes `Payload/Blackout.app/Watch/BlackoutWatch.app` before upload. Then remove the “no Watch/ companion” fail-closed check in `tf-archive.sh`, or invert it to require Watch.
5. Do not bump tree `CURRENT_PROJECT_VERSION`. Do not add a strip script.

Local Watch compile: scheme **BlackoutWatch**, destination `generic/platform=watchOS`. Unsigned `xcodebuild.yml` still builds scheme **Blackout** for iOS only (Widget embedded; Watch not).

GitHub requires a workflow file on the default branch for the Actions **Run workflow** button. **Do not use that button against `main` until CoS syncs host YAML.** Main still has watchkitapp in `BUNDLES`; tip does not. Tip YAML is the source of truth.

## CoS dispatch (required)

Next TestFlight Internal run **must** use tip host YAML so reuse (not delete+create) is what GHA executes:

```bash
gh workflow run "TestFlight Internal" --ref cursor/blackout-bible-v3-64d0 -f git_ref=cursor/blackout-bible-v3-64d0
```

`--ref` selects the workflow file. `-f git_ref=` selects the app tree to archive. Both must be the tip. Do not dispatch `--ref main`. Do not bump tree CPV. Agents must not dispatch.

GHA `33924134240` / `33924251037`: tip still **deleted** stale GHA App Store profiles then POSTed new ones and ASC returned HTTP 500 `UNEXPECTED_ERROR`. Archive never ran; CPV 54 was not minted. Keep Dist cert `45YLWHL6UP` as reference. Always mint a runner-local Dist cert for the archive. Reuse or create Local-named profiles (`Blackout iOS App Store GHA Local` / `Blackout Widgets App Store GHA Local`) bound to that local cert. Do not delete KEEP-named `Blackout iOS App Store GHA` / `Blackout Widgets App Store GHA`. Never revoke KEEP.

## How Crisis runs it from iPhone Safari

Safari **Run workflow** lists the default-branch YAML. Until CoS copies **only** this tip yml onto `main` (app tree stays unmerged), Crisis cannot pick tip YAML from the button. CoS runs the `gh workflow run --ref` command above.

After a green job: TestFlight app → Blackout → new build (not 50-series) → Install. Airplane On, BT On. Score `docs/SOLO_QA.md`.

## Mac-optional / do not use

Do not export a p12. Unsigned `.github/workflows/xcodebuild.yml` does not read ASC secrets and must stay green without them.
