# TESTFLIGHT — Internal, iPhone only

Crisis is the operator. iPhone 12 Pro Max. No Mac. No Xcode.

App: Blackout  
Bundle id: `com.crisiskhan.blackout`  
App Store Connect app id: `6806388963`  
Group: Internal only (`28035586-fce6-474f-9bc2-ef0f1f65306e`)  
Branch that produces a new build: `cursor/blackout-bible-v3-64d0` (PR #4)

This branch is not on TestFlight until a signed upload succeeds. If TestFlight still lists a 50-series build, that is the old vessel, not this PR tree.

Do not enable External Testing. Do not submit for App Review.

## Steps (iPhone)

1. TestFlight app (install from the App Store if needed).
2. Internal tester for Blackout / `com.crisiskhan.blackout` — redeem the email invite from App Store Connect if TestFlight does not already show Blackout.
3. Install the Internal build of Blackout. Use the build that matches a successful signed upload of this PR tree. Do not treat an old 50-series build as this branch unless that is the only build listed (then this PR tree is not on TestFlight yet).
4. After install: Airplane On, then Bluetooth On. Wi-Fi stays off. Cell stays off.
5. Score `docs/SOLO_QA.md`.
