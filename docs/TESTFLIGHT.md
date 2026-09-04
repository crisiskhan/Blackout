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
- `33827851150` (`23a7d04`): blob-sign of all three + official CodeSign of `Blackout.app` succeeded. `xcodebuild archive` then failed `Archive Missing Bundle Identifier` (exit 70) and tore down `InstallationBuildProductsLocation`. `BuildProductsPath/Release-iphoneos/Blackout.app` is only a symlink to that same path, so post-archive recover found nothing. Snapshot the `.app` during the blob-sign phase and hand-zip the IPA from that copy. Do not rely on a valid `.xcarchive`.

GitHub requires the workflow file on the default branch for the Run workflow button. CoS will place ONLY this yml on `main`; PR #4 app code stays unmerged.

## How Crisis runs it from iPhone Safari

1. Request Desktop Website.
2. Open https://github.com/crisiskhan/Blackout/actions/workflows/testflight-internal.yml
3. Tap Run workflow.
4. Use workflow from `main` (GitHub only lists dispatch on the default branch). The input `git_ref` default is `cursor/blackout-bible-v3-64d0` — leave it (that is the app tree). Do not archive main’s old app.
5. Tap Run workflow / green button.
6. Wait until the job is green, then TestFlight app → Blackout → new build (not 50-series) → Install. Airplane On, BT On. Score `docs/SOLO_QA.md`.

Do not run this workflow from a Cursor agent. CoS / Crisis taps Run workflow.

## Mac-optional / do not use

Do not export a p12. Unsigned `.github/workflows/xcodebuild.yml` does not read ASC secrets and must stay green without them.
