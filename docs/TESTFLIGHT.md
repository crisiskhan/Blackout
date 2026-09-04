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
- Archive runner is **macos-14 + Xcode 16** (same toolchain as unsigned `.github/workflows/xcodebuild.yml`). Do not use `macos-latest` / Xcode 26: that toolchain recreates `Metadata.appintents` after the CI strip script and CodeSign fails.
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
- `33925258357` (`4456206`): KEEP Dist cert reuse + Watch omitted. Hand-zip IPA ready. `altool` −19000 on **`com.maplibre.mapbox`** (MapLibre.framework Info.plist). Vendor slices now use `com.crisiskhan.blackout.maplibre`. Do not create an ASC app for MapLibre.
- Archive exit 70 `Archive Missing Bundle Identifier` after the main app plist already had `com.crisiskhan.blackout`: the extra archived product was the **Vendor/MapLibre xcframework** linked beside `MapLibreMap`. That XFWK wrapper Info.plist has `CFBundlePackageType=XFWK` and **no** `CFBundleIdentifier`. App/widget source plists already carry `CFBundleIdentifier=$(PRODUCT_BUNDLE_IDENTIFIER)`. Watch stays omitted from the App Store archive.
- App target now links **MapLibreMap only** (MapLibreMap already depends on the vendor binary). `tf-archive.sh` runs `tools/tf_ipa_inspect.py` after the IPA exists: assert app/widget BIDs, rewrite any nested FMWK whose BID is not under `com.crisiskhan.blackout` to `com.crisiskhan.blackout.<frameworkname>`, fail closed, re-zip if rewritten.

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

GHA `33924134240` / `33924251037`: tip still **deleted** stale GHA App Store profiles then POSTed new ones and ASC returned HTTP 500 `UNEXPECTED_ERROR`. Archive never ran; CPV 54 was not minted. Keep Dist cert `45YLWHL6UP`. Reuse ACTIVE profiles named `Blackout iOS App Store GHA` and `Blackout Widgets App Store GHA`. Create a Dist cert or profile only if missing. Never revoke KEEP. Never delete+create as the happy path.

## How Crisis runs it from iPhone Safari

Safari **Run workflow** lists the default-branch YAML. Until CoS copies **only** this tip yml onto `main` (app tree stays unmerged), Crisis cannot pick tip YAML from the button. CoS runs the `gh workflow run --ref` command above.

After a green job: TestFlight app → Blackout → new build (not 50-series) → Install. Airplane On, BT On. Score `docs/SOLO_QA.md`.

## Mac-optional / do not use

Do not export a p12. Unsigned `.github/workflows/xcodebuild.yml` does not read ASC secrets and must stay green without them.
