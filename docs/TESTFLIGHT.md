# TESTFLIGHT — iPhone Safari + Xcode Cloud

Crisis is on iPhone 12 Pro Max only. No Xcode. No Mac. No p12.

Start from the app page menu: Distribution / Analytics / TestFlight / Xcode Cloud.

## Facts

- Bundle `com.crisiskhan.blackout`
- Repo `crisiskhan/Blackout`
- Branch Xcode Cloud MUST use: `cursor/blackout-bible-v3-64d0` (never `main`)
- Destination: TestFlight Internal only. No App Review. No External Testing.
- Repo CPV is 1 and collides; turn ON Apple managing the build number.
- A 50-series TestFlight build is the old vessel.
- `ci_scripts` are in the repo; they do not start a build by themselves.

## Safari first

1. Open appstoreconnect.apple.com in Safari. Sign in with the Apple Developer account that owns this app (human tap 1 — I cannot do this).
2. Safari: tap Aa / Page Settings → Request Desktop Website. Stay on desktop site.
3. Open the Blackout app. Tap **Xcode Cloud** on that row (Distribution / Analytics / TestFlight / Xcode Cloud).

## GitHub not connected yet — exact taps

Use Apple's Grant Access language. Do not invent extra menus.

4. If Xcode Cloud shows Get Started / Grant Access / Connect Repository / GitHub not connected: tap **Grant Access** (or Get Started then Grant Access).
5. Choose **GitHub** (github.com, not Enterprise).
6. Sign into GitHub as the owner of `crisiskhan/Blackout`. Authorize Apple's Xcode Cloud GitHub app. Install it on **only** `crisiskhan/Blackout`, not every repo. Return to App Store Connect (human tap 2 — I cannot do this).
7. If GitHub is already connected, skip 4–6.

## Workflow (still Safari, Xcode Cloud tab → Manage Workflows)

8. Add or edit a workflow named Internal TF (or edit the existing product for this bundle).
9. Start condition: Branch Changes on `cursor/blackout-bible-v3-64d0` only. Do not use `main`.
10. Action: Archive, platform iOS, scheme **Blackout**, project `Blackout.xcodeproj`. Distribution preparation: TestFlight Internal Only. Manage version and build number ON.
11. Post-Actions: TestFlight Internal Test, artifact Archive - iOS, existing Internal group. Do not add App Store Review. Do not add External Testing.
12. Save. Tap **Start Build**. Branch picker: `cursor/blackout-bible-v3-64d0`. Start Build (human tap 3 — I cannot do this).
13. Wait until Processed / Ready to Test.

## Then iPhone TestFlight app

14. Open TestFlight. Redeem Internal invite if Blackout is missing.
15. Confirm the build number is the new Xcode Cloud build, not 50-series. Install or Update. Open Blackout.
16. Airplane On, then Bluetooth On. Wi-Fi off. Cell off. Score `docs/SOLO_QA.md`.

## Three taps I cannot do

1. Apple login (Safari → App Store Connect)
2. Grant GitHub to Xcode Cloud (Grant Access → GitHub → install app on `crisiskhan/Blackout`)
3. Start Build on `cursor/blackout-bible-v3-64d0`

## Mac-optional GHA — do not use

`.github/workflows/testflight-internal.yml` stays `workflow_dispatch` only. Default CI does not need p12. Do not run the p12 workflow.
