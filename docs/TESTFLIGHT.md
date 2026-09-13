# TESTFLIGHT — GitHub Actions Internal (no p12)

Primary install path is `.github/workflows/testflight-internal.yml`, not Xcode Cloud.

Crisis: iPhone 12 Pro Max. Safari. No Mac. No Xcode. No p12.

## Facts

- App Blackout / CKBlackout, bundle `com.crisiskhan.blackout`, ASC `6806388963`
- Repo `crisiskhan/Blackout`
- App tree this job archives: `cursor/blackout-bible-v3-64d0` (never the old app on `main`)
- Destination: TestFlight Internal only (`28035586-fce6-474f-9bc2-ef0f1f65306e`). No App Review. No External Testing.
- This job has **no** GitHub `environment:` and must not. Auto-review / required reviewers must not gate Internal upload. If Settings → Environments later names a gate, CoS/Crisis must clear protection on that env (YAML cannot remove Settings-only rules).
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
- `33987452079` (`7095fa1`): macos-15 / Xcode 26.3. `exportArchive OK`. CPV **57**. Dist `R8P2DS495P` (`DISTRIBUTION`). altool no errors. ASC `96af7288-860d-4a28-8009-b4a1ed8d47b7` **VALID**. PATCH 200. `ASSIGN Internal 57 204`. Tip-57 streets + pack bbox + YOU. Later tip-58 (`88b1726`) is not in this IPA.
- `34002236273` (`67f9b5f`): macos-15 / Xcode 26.3. `exportArchive OK`. CPV **58**. Dist `AN8MADVN3Z` (`DISTRIBUTION`). altool no errors. ASC `b4063ed9-f737-4da1-81bf-1206f625e342` **VALID**. PATCH 200. `ASSIGN Internal 58 204`. Tip-58 MARK/timer/RED/PTT plus tip-57 streets.
- `34002862630` (`919dfa8`): first `tf:` push auto-upload. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **59**. Dist `6L4U8L695G` (`DISTRIBUTION`). altool no errors. ASC `3da30d72-408b-4cd2-a6e7-7009106e97bb` **VALID**. PATCH 200. `ASSIGN Internal 59 204`. Same tip-58 app as 58 (docs-only tree).
- `34232353416` (`b451bb1`): tip-60 `tf:` push. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **60**. Dist `U8C9ZLHLTJ` (`DISTRIBUTION`). altool no errors. ASC `4bcbdb70-f766-4d5d-8aff-8315399e56ca` **VALID**. PATCH 200. `ASSIGN Internal 60 204`. Leave 59 until TestFlight shows 60 Ready.
- `34237111681` (`b947536`): tip-61 `tf:` push. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **61**. Dist `422W3DA782` (`DISTRIBUTION`). altool no errors. ASC `b7c98209-6c8d-4f42-a209-cbff4c63c789` **VALID**. PATCH 200. `ASSIGN Internal 61 204`. TX WEST walkable OSM. Leave 60 until TestFlight shows 61 Ready.
- `34245270215` (`b0601e2`): tip-62 `tf:` push. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **62**. Dist `RMG3W7ARUD` (`DISTRIBUTION`). altool no errors. ASC `198debb6-312a-41ba-b1a7-c4ff6d683456` **VALID**. PATCH 200. `ASSIGN Internal 62 204`. MAP chips + WALK/DRIVE. Leave 61 until TestFlight shows 62 Ready.
- `34248224189` (`35ad515`): tip-63 `tf:` push. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **63**. Dist `7CTCLZKX2Z` (`DISTRIBUTION`). altool no errors. ASC `53323e29-bd51-426e-88bf-bf0fdb557b90` **VALID**. PATCH 200. `ASSIGN Internal 63 204`. NM walkable pack; tx-west default. Leave 62 until TestFlight shows 63 Ready.
- `34257680002` (`9eb32c4`): tip-64 `tf:` push. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **64**. Dist `S3R65K88HJ` (`DISTRIBUTION`). altool no errors. ASC `5116f1c0-09a3-4419-a304-d6ea86914856` **VALID**. PATCH 200. `ASSIGN Internal 64 204`. TX WEST arterial casing + highway refs. Leave 63 until TestFlight shows 64 Ready.
- `34260710700` (`f401a3d`): tip-65 `tf:` push. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **65**. Dist `2T2U9RQMJD` (`DISTRIBUTION`). altool no errors. ASC `94bcaf54-c944-47db-a399-b373a7be2012` **VALID**. PATCH 200. `ASSIGN Internal 65 204`. Speak turn-by-turn + TX EAST. Leave 64 until TestFlight shows 65 Ready.
- `34261557379` (`c55d861`): tip-66 `tf:` push. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **66**. Dist `33BKW9XRQN` (`DISTRIBUTION`). altool no errors. ASC `b3310736-f1d6-4ea8-96a4-c40eccb9e770` **VALID**. PATCH 200. `ASSIGN Internal 66 204`. Same Speak + TX EAST tree as 65. Leave 65 until TestFlight shows 66 Ready.
- `34264110982` (`960a8a2`): tip-67 `tf:` push. Mint OK (`HAS_LOCAL_DIST_KEY=1`), then GET `/v1/builds` HTTP 500 in Next CPV. No IPA. Retry list 500 (15s/30s/60s/90s/120s) via `tools/tf_asc_cpv.py`. Do not re-upload 54–66.
- `34264462418` (`960a8a2`): tip-67 `workflow_dispatch` with a concatenated `git_ref`. Checkout fetch failed. No IPA.
- `34264699162` (`960a8a2`): tip-67 `workflow_dispatch` retry. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **67**. Dist `Q8AX4T282L` (`DISTRIBUTION`). altool no errors. ASC `e2cf188e-1fa8-4e07-b306-1e088087c7d0` **VALID**. PATCH 200. `ASSIGN Internal 67 204`. GraphProbe + warmup + keep-awake. Leave 66 until TestFlight shows 67 Ready.
- `34269174169` (`20d2df7`): tip-68 `tf:` push. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **68**. Dist `S4B68PPMFK` (`DISTRIBUTION`). altool no errors. ASC `6f4ebfca-b491-408e-831a-e63a1bac63cb` **VALID**. PATCH 200. `ASSIGN Internal 68 204`. Speak finish + clean field + walking-zoom names. Leave 67 until TestFlight shows 68 Ready.
- `34463051408` (`9911aaf`): HUD tag `tf-79`. CPV **79**. Unnamed tank sure. Leave 78 until TestFlight showed 79 Ready.
- `34464769463` (`15516ec`): HUD tag `tf-80`. CPV **80**. Compass mark as App Icon and boot logo. Leave 79 until TestFlight shows 80 Ready.
- `34480452541` (`98bb68a`): HUD tag `tf-81`. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **81**. Dist `TPTQ6GKWZ7` (`DISTRIBUTION`). KEEP `45YLWHL6UP` untouched. altool no errors. `WAIT no build 81`, then ASC `b4d4d85f-7f42-4338-a38c-58e0c3ae4591` **VALID**. PATCH 200. `ASSIGN Internal 81 204`. HUD on every tab + hold water classify + named marks. Leave 80 until TestFlight shows 81 Ready.
- `34491969097` (`323aa7f`): HUD tag `tf-82`. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **82**. Dist `8872S8A8NY` (`DISTRIBUTION`). KEEP `45YLWHL6UP` untouched. altool no errors. `WAIT no build 82`, then ASC `f5262825-9fc6-44a3-90c5-4eade1cee20b` **VALID**. PATCH 200. `ASSIGN Internal 82 204`. Textless compass + HUD mark language through the instrument. Leave 81 until TestFlight shows 82 Ready.
- `34502826993` (`3abaf58`): HUD tag `tf-83`. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **83**. Dist `947QX8HSZ9` (`DISTRIBUTION`). KEEP `45YLWHL6UP` untouched. altool no errors. `WAIT no build 83`, then ASC `9ef5ecfb-f11a-40a8-b2c9-27148f0a02ea` **VALID**. PATCH 200. `ASSIGN Internal 83 204`. Expedition HUD + FIELD vision still + COMMS call. Leave 82 until TestFlight shows 83 Ready.
- `34536953430` (`4ec42d4`): HUD tag `tf-84`. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **84**. Dist `WK9VCHNP39` (`DISTRIBUTION`). KEEP `45YLWHL6UP` untouched. altool no errors. `WAIT no build 84`, then ASC `e0ac0030-87e3-4952-b2a7-8336dffe99ef` **VALID**. PATCH 200. `ASSIGN Internal 84 204`. Scarce red, no fake party bodies, chrome that actually sleeps. Leave 83 until TestFlight shows 84 Ready.
- `34547063820` (`487f290`): HUD tag `tf-85`. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **85**. Dist `JVJ9WKTV5A` (`DISTRIBUTION`). KEEP `45YLWHL6UP` untouched. altool no errors. `WAIT no build 85`, then ASC `5cbd4db3-9642-4892-bef4-e8542a75afa9` **VALID**. PATCH 200. `ASSIGN Internal 85 204`. Hold ground + VISION still open this pack's plant, bite, animal, and cave cards. Never edible. Leave 84 until TestFlight shows 85 Ready.
- `34550033439` (`0d0e0b3`): HUD tag `tf-86`. macos-15 / Xcode 26.3. `exportArchive OK`. CPV **86**. Dist `6KKC39285N` (`DISTRIBUTION`). KEEP `45YLWHL6UP` untouched. altool `UPLOAD SUCCEEDED with no errors`. `WAIT no build 86`, then ASC `f1a73104-c56c-4171-ba94-c08b0853c716` **VALID**. PATCH 200. `ASSIGN Internal 86 204`. Tree-use first on woodland, `BOOK` + `CARD n OF`, named tree is not woodland, hole walks cave then cold. Never edible. Leave 85 until TestFlight shows 86 Ready.
- `34572153310` (`2c91036`): HUD tag `tf-87`. macos-15 / Xcode 26.3. `HAS_LOCAL_DIST_KEY=1`. `exportArchive OK`. CPV **87**. Dist `SJ7LCMGH3L` (`DISTRIBUTION`). KEEP `45YLWHL6UP` untouched. altool `UPLOAD SUCCEEDED with no errors`. `WAIT no build 87`, then ASC `6ab6b596-0c4f-4a60-89f6-6cc39dfad22b` **VALID**. PATCH 200. `ASSIGN Internal 87 204`. `usesNonExemptEncryption: null`. Peak walk includes bite; NM mammal SPEAK names the bite card. Never edible. Leave 86 until TestFlight shows 87 Ready.
- `34629533409` (`6295e73`): HUD tag `tf-88`. macos-15 / Xcode 26.3. `HAS_LOCAL_DIST_KEY=1`. `exportArchive OK`. CPV **88**. Dist `4JYX5MF425` (`DISTRIBUTION`). KEEP `45YLWHL6UP` untouched. altool `UPLOAD SUCCEEDED with no errors`. `WAIT no build 88`, then ASC `a0a32168-94a7-422d-8204-31332e32eaa1` **VALID**. PATCH 200. `ASSIGN Internal 88 204`. `usesNonExemptEncryption: null`. Notable OSM reserves, caves, and named trees; karst / wildlife preserve / Audubon / nature area / habitat preserve Holds. Never edible. Leave 87 until TestFlight shows 88 Ready.
- `34648083111` (`c1388f3`): HUD tag `tf-89`. macos-15 / Xcode 26.3. `HAS_LOCAL_DIST_KEY=1`. `exportArchive OK`. CPV **89**. Dist `NVH99KH233` (`DISTRIBUTION`). KEEP `45YLWHL6UP` untouched. altool `UPLOAD SUCCEEDED with no errors`. `WAIT no build 89`, then ASC `24e2c615-db24-4f09-b362-563cdafd1d4c` **VALID**. PATCH 200. `ASSIGN Internal 89 204`. `usesNonExemptEncryption: null`. FIELD SEARCH, from-nothing book, botanic Holds (Lush n Lean / Orchard Garden / Harvey Cornell). Never edible. Leave 88 until TestFlight shows 89 Ready.

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

## How to fire Internal (bible-v3 only)

Push triggers live on tip YAML (`cursor/blackout-bible-v3-64d0`). Do not add `main` as a trigger. Do not merge this job to main to “enable” it — a push to bible-v3 uses the workflow file on that branch.

1. **Commit message** on `cursor/blackout-bible-v3-64d0` starting with `tf:` (example: `tf: streets + tip-58`). Any other prefix (including `ci(tf):`) does **not** upload.
2. **Tag** matching `tf-*` (example: `git tag tf-58 && git push origin tf-58`). The tagged commit must contain this workflow.
3. **Backup** `workflow_dispatch` with `git_ref` (same as before):

```bash
gh workflow run "TestFlight Internal" --ref cursor/blackout-bible-v3-64d0 -f git_ref=cursor/blackout-bible-v3-64d0
```

`--ref` selects the workflow file. `-f git_ref=` selects the app tree to archive. Both must be the tip. Do not dispatch `--ref main`. Do not bump tree CPV. Agents must not dispatch a TestFlight upload unless asked to verify.

A push to bible-v3 that does **not** start with `tf:` still starts the workflow file, then **skips** the upload job. That skip is intentional so CI YAML edits do not burn ASC quota.

First automated Internal upload: this `tf:` push on bible-v3. Tree CPV stays 1. Watch omitted. Internal only.

GHA `33924134240` / `33924251037`: tip still **deleted** stale GHA App Store profiles then POSTed new ones and ASC returned HTTP 500 `UNEXPECTED_ERROR`. Archive never ran; CPV 54 was not minted. Keep Dist cert `45YLWHL6UP` as reference. Always mint a runner-local Dist cert for the archive. Reuse or create Local-named profiles (`Blackout iOS App Store GHA Local` / `Blackout Widgets App Store GHA Local`) bound to that local cert. Do not delete KEEP-named `Blackout iOS App Store GHA` / `Blackout Widgets App Store GHA`. Never revoke KEEP.

## How Crisis runs it from iPhone Safari

Preferred: GitHub → this repo → branch `cursor/blackout-bible-v3-64d0` → edit or commit with message starting `tf:` (or create tag `tf-58` on that tip). That push fires Internal. Do not use a `tf:` prefix on commits that must not upload.

Safari **Run workflow** lists the default-branch YAML and stays the backup. Until CoS copies **only** this tip yml onto `main` (app tree stays unmerged), the button cannot pick tip YAML. CoS can still run the `gh workflow run --ref` command above.

After a green job: TestFlight app → Blackout → new build (not 50-series) → Install. Airplane On, BT On. Score `docs/SOLO_QA.md`.

## Mac-optional / do not use

Do not export a p12. Unsigned `.github/workflows/xcodebuild.yml` does not read ASC secrets and must stay green without them.

## Tip 60 Internal (CoS 2026-09-08)

SOURCE GO tip `e4e2e7e91ca3879a22fca1295dea48cbfb2d0618` (product `47a9edfc`). Five chrome PASS. Run `34232353416` uploaded CPV **60** and `ASSIGN Internal 60 204`. Leave 59 until TestFlight shows 60 Ready. Watch omitted. Internal only. Do not re-upload 54–59.

## Tip 61 Internal (CoS 2026-09-08)

SOURCE GO tip `9ae26f18ee5eb15a6f529b80af4e801c5271a309` BEST IN CLASS TX WEST walkable OSM (~48.3 MB; streets at walking zoom yes). Run `34237111681` uploaded CPV **61** and `ASSIGN Internal 61 204`. Leave 60 until TestFlight shows 61 Ready. Watch omitted. Internal only. Do not re-upload 54–60.

## Tip 62 product (no Internal yet)

WALK/DRIVE on-graph polyline on the existing TX WEST pack. Graph already shipped in tip 61 (`Resources/Packs/tx-west/graph.json`, ~264k edges). Do not `tf:` until CoS+Crisis GO. Tree CPV stays 1. Watch omitted.

## Tip 62 Internal (CoS 2026-09-08 Crisis GO)

SOURCE GO tip `81a8903a82bf9a6f717e960793da72e5b508b39f` (tree also has `a410b47` 44pt chips). Factory mode. Run `34245270215` uploaded CPV **62** and `ASSIGN Internal 62 204`. Leave 61 until TestFlight shows 62 Ready. Watch omitted. Internal only. Do not re-upload 54–61.

## Tip 63 Internal (CoS 2026-09-08 Director factory)

NM walkable pack tip `52cac90b` merge `42b61974` (~64.1 MB streets yes). tx-west stays default. Run `34248224189` uploaded CPV **63** and `ASSIGN Internal 63 204`. Leave 62 until TestFlight shows 63 Ready. Watch omitted. Internal only. Do not re-upload 54–62.

## Tip 64 Internal (CoS 2026-09-08)

SOURCE GO tip `556b4a5b` / merge `999e110a`. Run `34257680002` uploaded CPV **64** and `ASSIGN Internal 64 204`. TX WEST arterial red casing + readable highway refs. Leave 63 until TestFlight shows 64 Ready. Watch omitted. Internal only. Do not re-upload 54–63.

## Tip 65 Internal (CoS 2026-09-08)

SOURCE GO tip `344094f4` / merge `955c3b24`. Run `34260710700` uploaded CPV **65** and `ASSIGN Internal 65 204`. Speak turn-by-turn + names + TX EAST pack. Leave 64 until TestFlight shows 65 Ready. Watch omitted. Internal only. Do not re-upload 54–64.

## Tip 66 Internal (CoS 2026-09-08)

SOURCE GO tip `09e4fffe` / merge `1eaa33b5`. Run `34261557379` uploaded CPV **66** and `ASSIGN Internal 66 204`. TX EAST ~65.6 MB; default tx-west. Same Speak tree as 65. Leave 65 until TestFlight shows 66 Ready. Watch omitted. Internal only. Do not re-upload 54–65.

## Tip 67 Internal (CoS 2026-09-08)

SOURCE GO tip `b7953348` / merge `a72a8478`. Run `34264699162` uploaded CPV **67** and `ASSIGN Internal 67 204`. Map keep-awake + graph warmup. Leave 66 until TestFlight shows 67 Ready. Watch omitted. Internal only. Do not re-upload 54–66.

## Tip 68 Internal (CoS 2026-09-08)

SOURCE GO tip `afb2e2fc` / merge `7abb9e0b`. Run `34269174169` uploaded CPV **68** and `ASSIGN Internal 68 204`. Speak banner finish + clean field + walking-zoom names. Leave 67 until TestFlight shows 68 Ready. Watch omitted. Internal only. Do not re-upload 54–67.

## HUD 79–80 Internal

HUD side path, not bible-v3. Tag `tf-79` (`9911aaf`, run `34463051408`) uploaded CPV **79**. Tag `tf-80` (`15516ec`, run `34464769463`) uploaded CPV **80** — compass mark as App Icon and boot logo. Watch omitted. Internal only. Do not re-upload 54–80.

## HUD 81 Internal (Crisis GO)

HUD tree `98bb68a` tagged `tf-81`. Run `34480452541` uploaded CPV **81** and `ASSIGN Internal 81 204`. Dist `TPTQ6GKWZ7`. ASC `b4d4d85f-7f42-4338-a38c-58e0c3ae4591` **VALID**. PATCH 200. Keep Map mounted, classify hold water, named marks survive pack re-read. Leave 80 until TestFlight shows 81 Ready. Watch omitted. Internal only. Do not re-upload 54–80.

## HUD 82 Internal (Crisis GO)

HUD tree `323aa7f` tagged `tf-82`. Run `34491969097` uploaded CPV **82** and `ASSIGN Internal 82 204`. Dist `8872S8A8NY`. ASC `f5262825-9fc6-44a3-90c5-4eade1cee20b` **VALID**. PATCH 200. Textless compass on the home screen and boot; overlay titles carry the mark; selected tab is the reticle; SOS silver ring; INSTRUMENTS is HUD. Leave 81 until TestFlight shows 82 Ready. Watch omitted. Internal only. Do not re-upload 54–81.

## HUD 83 Internal (Crisis GO)

HUD tree `3abaf58` tagged `tf-83`. Run `34502826993` uploaded CPV **83** and `ASSIGN Internal 83 204`. Dist `947QX8HSZ9`. ASC `9ef5ecfb-f11a-40a8-b2c9-27148f0a02ea` **VALID**. PATCH 200. Expedition condition rails; FIELD book + VISION still (pack-book name / UNKNOWN / NO VISION MODEL, never edible); COMMS HOLD PTT, real mic clip, LEAVE NET. Leave 82 until TestFlight shows 83 Ready. Watch omitted. Internal only. Do not re-upload 54–82.

## HUD 84 Internal (Crisis GO)

HUD tree `4ec42d4` tagged `tf-84`. Run `34536953430` uploaded CPV **84** and `ASSIGN Internal 84 204`. Dist `WK9VCHNP39`. ASC `e0ac0030-87e3-4952-b2a7-8336dffe99ef` **VALID**. PATCH 200. Unsigned compile [34536170362](https://github.com/crisiskhan/Blackout/actions/runs/34536170362) (generic device + simulator). No fake party body on YOU; highway refs and the walk line silver; water class labels off the canvas; hit/mark rows fade; LAYOUT can place SOS. Leave 83 until TestFlight shows 84 Ready. Watch omitted. Internal only. Do not re-upload 54–83.

## HUD 85 Internal (Crisis GO)

HUD tree `487f290` tagged `tf-85`. Run `34547063820` uploaded CPV **85** and `ASSIGN Internal 85 204`. Dist `JVJ9WKTV5A`. ASC `5cbd4db3-9642-4892-bef4-e8542a75afa9` **VALID**. PATCH 200. Unsigned compile [34546255034](https://github.com/crisiskhan/Blackout/actions/runs/34546255034) (generic device + simulator). Hold woodland/scrub/peak/hole opens plant, bite, animal, cave cards; a FIELD still of the same kind offers the same procedure. TX WEST sinkhole 31.694905, −106.441133. No wildlife GPS. Never edible. Leave 84 until TestFlight shows 85 Ready. Watch omitted. Internal only. Do not re-upload 54–84.

## HUD 86 Internal (Crisis GO)

HUD tree `0d0e0b3` tagged `tf-86`. Run [34550033439](https://github.com/crisiskhan/Blackout/actions/runs/34550033439) uploaded CPV **86** and `ASSIGN Internal 86 204`. Dist `6KKC39285N`. ASC `f1a73104-c56c-4171-ba94-c08b0853c716` **VALID**. PATCH 200. Unsigned compile [34549187846](https://github.com/crisiskhan/Blackout/actions/runs/34549187846) (generic device + simulator). Woodland `FIELD · PLANT` opens tree-use first; `BOOK` / `CARD n OF`; a named tree is tree cards only; a hole is `FIELD · CAVE` then `NEXT · COLD`. No wildlife GPS. Never edible. Leave 85 until TestFlight shows 86 Ready. Watch omitted. Internal only. Do not re-upload 54–85.

## HUD 87 Internal (Crisis GO)

HUD tree `2c91036` tagged `tf-87`. Run [34572153310](https://github.com/crisiskhan/Blackout/actions/runs/34572153310) uploaded CPV **87** and `ASSIGN Internal 87 204`. Dist `SJ7LCMGH3L`. ASC `6ab6b596-0c4f-4a60-89f6-6cc39dfad22b` **VALID**. PATCH 200. Unsigned compile [34571356306](https://github.com/crisiskhan/Blackout/actions/runs/34571356306) (generic device + simulator). A Texas peak is `FIELD · ANIMAL` then `NEXT · BITE` then `NEXT · COLD`. NM mammal SPEAK names the bite card. No wildlife GPS. Never edible. Leave 86 until TestFlight shows 87 Ready. Watch omitted. Internal only. Do not re-upload 54–86. Do not retag 85, 86, or 87.

## HUD 88 Internal (Crisis GO)

HUD tree `6295e73` tagged `tf-88`. Run [34629533409](https://github.com/crisiskhan/Blackout/actions/runs/34629533409) uploaded CPV **88** and `ASSIGN Internal 88 204`. Dist `4JYX5MF425`. ASC `a0a32168-94a7-422d-8204-31332e32eaa1` **VALID**. PATCH 200. Unsigned compile [34629197731](https://github.com/crisiskhan/Blackout/actions/runs/34629197731) on the tagged tree. Notable OSM extract: named nature-reserve relations, cave mouths, named trees; karst / wildlife preserve / Audubon / nature area / habitat preserve Holds. No wildlife GPS. Never edible. Leave 87 until TestFlight shows 88 Ready, then install `0.1.0 (88)`. Watch omitted. Internal only. Do not re-upload 54–87. Do not retag 85, 86, 87, or 88.

## HUD 89 Internal (Crisis GO)

HUD tree `c1388f3` tagged `tf-89`. Run [34648083111](https://github.com/crisiskhan/Blackout/actions/runs/34648083111) uploaded CPV **89** and `ASSIGN Internal 89 204`. Dist `NVH99KH233`. ASC `24e2c615-db24-4f09-b362-563cdafd1d4c` **VALID**. PATCH 200. Unsigned compile generic iOS green on [34647718165](https://github.com/crisiskhan/Blackout/actions/runs/34647718165); simulator still in flight. FIELD SEARCH + from-nothing book. Botanic Holds: Lush n Lean Garden, Orchard Garden, Harvey Cornell Rose Park. No wildlife GPS. Never edible. Leave 88 until TestFlight shows 89 Ready, then install `0.1.0 (89)`. Watch omitted. Internal only. Do not re-upload 54–88. Do not retag 85–89.

## HUD 90 Internal (Crisis GO)

HUD tree `3eace8e` tagged `tf-90`. Run [34698148948](https://github.com/crisiskhan/Blackout/actions/runs/34698148948) uploaded CPV **90** and `ASSIGN Internal 90 204`. Dist `WQLW3QMVCJ`. ASC `9c8557d6-3735-44bd-9027-cd1b3bb712ac` **VALID**. PATCH 200. Unsigned compile [34697829522](https://github.com/crisiskhan/Blackout/actions/runs/34697829522) (generic device + simulator). MapLibreMapTests **Executed 175 tests, with 0 failures** (104.749s). FACE on YOU and party, Bennett Mountain, heading fail-closed (tick dark until accuracy is real). No wildlife GPS. Never edible. Leave 89 until TestFlight shows 90 Ready, then install `0.1.0 (90)`. Watch omitted. Internal only. Do not re-upload 54–89. **91** is caught. Leave 90 until TestFlight shows 91 Ready, then install `0.1.0 (91)`. Do not retag 85–90.

## HUD 91 Internal (Crisis GO)

HUD tree `6572ba2` tagged `tf-91`. Run [34702742398](https://github.com/crisiskhan/Blackout/actions/runs/34702742398) uploaded CPV **91** and `ASSIGN Internal 91 204`. Dist `QC3528L4VU`. KEEP `45YLWHL6UP` untouched. ASC `4bc30e84-fb08-4c6e-aba8-163788614c73` **VALID**. PATCH 200. Unsigned compile [34701892788](https://github.com/crisiskhan/Blackout/actions/runs/34701892788) (generic device + simulator). MapLibreMapTests **Executed 175 tests, with 0 failures** (114.035s). Empty polyline / rest-of-app fail-closed, puck/crash, San Antonio Mountain. IPA 91 is `6572ba2`. Big Brushy Mountain (`587c984`) is a later SHA and is not on 91. No wildlife GPS. Never edible. Leave 90 until TestFlight shows 91 Ready, then install `0.1.0 (91)`. Watch omitted. Internal only. Do not re-upload 54–90. **92** is caught. Leave 91 until TestFlight shows 92 Ready, then install `0.1.0 (92)`. Do not retag 85–91.

## HUD 92 Internal (Crisis GO)

HUD tree `4764bc5` tagged `tf-92`. Run [34712071568](https://github.com/crisiskhan/Blackout/actions/runs/34712071568) uploaded CPV **92** and `ASSIGN Internal 92 204`. Dist `635A8PMWLS`. KEEP `45YLWHL6UP` untouched. ASC `1faed6d4-3d3e-4a92-839e-ba3f023e6bed` **VALID**. PATCH 200. `usesNonExemptEncryption: null`. Crash-safe MAP SEARCH (rank off the HUD) + Western Honey Mesquite. IPA 92 is `4764bc5`. Castner / El Cerro / Galisteo (`4865b3d`) and later open-reserve Holds are later SHAs and are not on 92. No wildlife GPS. Never edible. Leave 91 until TestFlight shows 92 Ready, then install `0.1.0 (92)`. Watch omitted. Internal only. Do not re-upload 54–91. **93** is caught. Leave 92 until TestFlight shows 93 Ready, then install `0.1.0 (93)`. Do not retag 85–92.

## HUD 93 Internal (Crisis GO)

HUD tree `85e10d0` tagged `tf-93`. Run [34714005365](https://github.com/crisiskhan/Blackout/actions/runs/34714005365) uploaded CPV **93** and `ASSIGN Internal 93 204`. Dist `T4LZRLF5GZ`. KEEP `45YLWHL6UP` untouched. ASC `4fee472b-bce2-4779-8433-ed317bfa8c19` **VALID**. PATCH 200. `usesNonExemptEncryption: null`. Unsigned compile [34713786716](https://github.com/crisiskhan/Blackout/actions/runs/34713786716) (generic device + simulator). MapLibreMapTests **Executed 175 tests, with 0 failures** (107.484s). Hold overlay PIP bbox-rejects far sheets so a White Sands / Petroglyph press cannot stall the HUD. PTT clip refuses a 0-channel buffer. IPA 93 is `85e10d0` (Castner / Trackways / White Sands / Ojito / Tent Rocks / Petroglyph / Placitas / Cerrillos and the Hold PIP fix). IPA 92 (`4764bc5`) is not this tree. No wildlife GPS. Never edible. Leave 92 until TestFlight shows 93 Ready, then install `0.1.0 (93)`. Watch omitted. Internal only. Do not re-upload 54–92. Do not retag 85–93.
