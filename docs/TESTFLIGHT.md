# TESTFLIGHT — Xcode Cloud → Internal

Primary path: Xcode Cloud. iPhone + any browser (ASUS laptop is fine). No Mac. No Xcode. No p12.

## Facts

- App: Blackout  
- Bundle id: `com.crisiskhan.blackout`  
- ASC app id: `6806388963`  
- GitHub repo: `crisiskhan/Blackout`  
- Exact branch Xcode Cloud must build: `cursor/blackout-bible-v3-64d0`  
- Destination: TestFlight Internal group only (`28035586-fce6-474f-9bc2-ef0f1f65306e`). No App Review. No External Testing.

This PR tree is not on TestFlight until an Xcode Cloud archive of that branch is VALID and assigned Internal. A 50-series build in TestFlight is the old vessel.

`pbxproj` `CURRENT_PROJECT_VERSION` is `1` and WILL collide with old ASC builds. In the Xcode Cloud workflow, turn ON Apple managing the build number (unique `CFBundleVersion`, next unused after existing internals). Do not require Crisis to export a cert.

## A — start the cloud build (browser, not Xcode)

1. App Store Connect → Apps → Blackout (`com.crisiskhan.blackout`) → Xcode Cloud.
2. Product is this GitHub repo `crisiskhan/Blackout`, scheme Blackout, project `Blackout.xcodeproj`. If a product already exists from the old tree, point the workflow at branch `cursor/blackout-bible-v3-64d0` (do not use `main` for this pass).
3. Workflow settings: Archive, TestFlight Internal, not App Store Review, not External Testing. Manage version and build number ON.
4. Start Build on `cursor/blackout-bible-v3-64d0`. Wait until the build is Processed / Ready to Test.

## B — iPhone taps after the build appears in TestFlight

1. Open TestFlight (install from the App Store if needed).
2. If Blackout is missing, redeem the Internal tester email invite.
3. Open Blackout. Confirm the build number is the new Xcode Cloud build, not a leftover 50-series.
4. Tap Install (or Update).
5. Open Blackout.
6. Airplane On, then Bluetooth On. Wi-Fi off. Cell off.
7. Score `docs/SOLO_QA.md`.

## C — Mac-optional GHA (do not use)

`.github/workflows/testflight-internal.yml` remains `workflow_dispatch` only. It needs a Mac-exported Apple Distribution p12 + three App Store profiles. Crisis cannot produce those. Default CI (`.github/workflows/xcodebuild.yml`) does not read those secrets and must not fail when they are missing. Do not run the p12 workflow.
