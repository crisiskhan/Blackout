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

HUD tree `3abaf58` tagged `tf-83`. Run `34502826993` uploaded CPV **83** and `ASSIGN Internal 83 204`. Dist `947QX8HSZ9`. ASC `9ef5ecfb-f11a-40a8-b2c9-27148f0a02ea` **VALID**. PATCH 200. Expedition condition rails; FIELD book + VISION still (pack-book name / UNKNOWN / NO VISION MODEL, never edible); COMMS HOLD PTT, real mic clip, LEAVE NET. Leave 82 until TestFlight shows 83 Ready. Watch omitted. Internal only. Do not re-upload 54–82. Next Internal after 83 would be **84**.
