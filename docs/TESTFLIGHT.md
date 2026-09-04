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
- Do not `xattr -cr` the `.app`, and do not `rm`/`ditto`/`chmod 644` `Assets.car`. Run `33823846800` showed CodeSign then dying on `Assets.car` (`code object is not signed at all`). Clear execute only (`chmod a-x`) if codesign treats the catalog as nested code.

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
